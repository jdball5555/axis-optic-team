import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/models/title_journey.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/ui/views/settings_view.dart';
import 'package:axis_team/ui/views/access_view.dart';

void main() {
  testWidgets('SettingsView in All Stores mode across various window sizes', (tester) async {
    final stores = [
      {'id': 'store_1', 'name': 'Downtown Flagship'},
      {'id': 'store_2', 'name': 'West End Center with Extra Long Name'},
      {'id': 'store_3', 'name': 'North Shore Plaza'},
    ];

    final settingsStore1 = StoreSettingsModel(
      titles: [
        const TitleConfig(id: 't1', name: 'Executive Team Member Coordinator'),
        const TitleConfig(id: 't2', name: 'Certified Senior Trainer'),
        const TitleConfig(id: 't3', name: 'Shift Operations Leader'),
      ],
      tags: [
        const TitleConfig(id: 'tag1', name: 'Opening Expert & Machine Master'),
      ],
      checklists: [
        const ChecklistConfig(
          id: 'c1',
          name: 'Morning Opening Checklist with extremely long title that could overflow',
          items: ['Step 1', 'Step 2'],
        ),
      ],
      positions: ['Front Counter & Drive Thru Combined', 'Kitchen Fryer Lead', 'Food Prep'],
      workingTimes: ['Morning 5am-1pm', 'Afternoon 1pm-7pm', 'Night Close 7pm-2am'],
      designations: ['Full Time Exempt', 'Part Time Non-Exempt'],
      employeeDataSummaryFields: ['First Name', 'Last Name', 'Title', 'Pay (\$ / Hr)', 'Store', 'Designation'],
      showOwnerInRoster: true,
    );

    final settingsStore2 = StoreSettingsModel(
      titles: [
        const TitleConfig(id: 't1', name: 'Team Member'),
        const TitleConfig(id: 't4', name: 'Store General Manager'),
      ],
      tags: [
        const TitleConfig(id: 'tag2', name: 'Closing Pro & Sanitation Specialist'),
      ],
      checklists: [
        const ChecklistConfig(
          id: 'c2',
          name: 'Closing & Overnight Cleanout Checklist',
          items: ['Clean kitchen', 'Lock safes', 'Turn off fryers'],
        ),
      ],
      positions: ['Service', 'Kitchen', 'Drive Thru Line'],
      workingTimes: ['Opening', 'Closing'],
      designations: ['Hourly'],
      employeeDataSummaryFields: ['First Name', 'Start Date'],
      showOwnerInRoster: false, // Differ triggers copy button on SettingsAccessCard!
    );

    final settingsStore3 = StoreSettingsModel(
      titles: [
        const TitleConfig(id: 't1', name: 'Team Member'),
      ],
      tags: [],
      checklists: [],
      positions: ['Host'],
      workingTimes: ['Day'],
      designations: ['Part Time'],
      employeeDataSummaryFields: [],
      showOwnerInRoster: true,
    );

    final owner = UserModel(
      id: 'owner_1',
      firstName: 'Jane-Alexandria',
      lastName: 'Doe-Smithsonian',
      email: 'jane.alexandria.doe.smithsonian@example.com',
      title: 'Owner',
    );

    for (final size in [
      const Size(280, 600),
      const Size(320, 800),
      const Size(360, 800),
      const Size(390, 844),
      const Size(414, 896),
      const Size(600, 900),
      const Size(768, 1024),
      const Size(820, 1180),
      const Size(1024, 768),
      const Size(1280, 800),
      const Size(1440, 900),
      const Size(1920, 1080),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => null), // All Stores mode!
            allStoresStreamProvider.overrideWith((ref) => Stream.value(stores)),
            specificStoreSettingsProvider('store_1').overrideWith((ref) => Stream.value(settingsStore1)),
            specificStoreSettingsProvider('store_2').overrideWith((ref) => Stream.value(settingsStore2)),
            specificStoreSettingsProvider('store_3').overrideWith((ref) => Stream.value(settingsStore3)),
            allStoreUsersStreamProvider.overrideWith((ref) => Stream.value([owner])),
            titleJourneyProvider('store_1').overrideWith((ref) => Stream.value(const TitleJourney())),
            titleJourneyProvider('store_2').overrideWith((ref) => Stream.value(const TitleJourney())),
            titleJourneyProvider('store_3').overrideWith((ref) => Stream.value(const TitleJourney())),
          ],
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Failed at window size ${size.width}x${size.height}: $exception');
    }
  });

  testWidgets('SettingsView in Single Store mode across various window sizes', (tester) async {
    final settingsStore1 = StoreSettingsModel(
      titles: [
        const TitleConfig(id: 't1', name: 'Team Member'),
        const TitleConfig(id: 't2', name: 'Trainer'),
        const TitleConfig(id: 't3', name: 'Shift Leader'),
      ],
      tags: [
        const TitleConfig(id: 'tag1', name: 'Opening Expert'),
      ],
      checklists: [
        const ChecklistConfig(
          id: 'c1',
          name: 'Morning Opening Checklist with very long title',
          items: ['Step 1', 'Step 2'],
        ),
      ],
      positions: ['Front Counter', 'Drive Thru', 'Kitchen'],
      workingTimes: ['Morning', 'Day', 'Night'],
      designations: ['Full Time', 'Part Time'],
      employeeDataSummaryFields: ['First Name', 'Last Name', 'Title', 'Pay (\$ / Hr)'],
      showOwnerInRoster: true,
    );

    final owner = UserModel(
      id: 'owner_1',
      firstName: 'Jane',
      lastName: 'Doe',
      email: 'jane.doe@example.com',
      title: 'Owner',
    );

    for (final size in [
      const Size(320, 800),
      const Size(360, 800),
      const Size(414, 896),
      const Size(768, 1024),
      const Size(1200, 800),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_1'), // Single Store mode!
            specificStoreSettingsProvider('store_1').overrideWith((ref) => Stream.value(settingsStore1)),
            allStoreUsersStreamProvider.overrideWith((ref) => Stream.value([owner])),
            titleJourneyProvider('store_1').overrideWith((ref) => Stream.value(const TitleJourney())),
          ],
          child: const MaterialApp(
            home: SettingsView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Failed single store at window size ${size.width}x${size.height}: $exception');
    }
  });

  testWidgets('AccessView across various window sizes', (tester) async {
    final owner = UserModel(
      id: 'owner_1',
      firstName: 'Jane',
      lastName: 'Doe',
      email: 'jane.doe@example.com',
      title: 'Owner',
      role: 'owner',
    );
    final bot = UserModel(
      id: 'bot_1',
      firstName: 'Order',
      lastName: 'Bot',
      email: 'bot@example.com',
      title: 'Bot',
      role: 'bot',
    );

    for (final size in [
      const Size(320, 800),
      const Size(360, 800),
      const Size(600, 900),
      const Size(1024, 768),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_1'),
            allStoreUsersStreamProvider.overrideWith((ref) => Stream.value([owner, bot])),
            storeSettingsProvider.overrideWith((ref) => Stream.value(const StoreSettingsModel(
              isScheduleEnabled: true,
              isShiftBoardEnabled: true,
            ))),
          ],
          child: const MaterialApp(
            home: AccessView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Failed AccessView at window size ${size.width}x${size.height}: $exception');
    }
  });
}
