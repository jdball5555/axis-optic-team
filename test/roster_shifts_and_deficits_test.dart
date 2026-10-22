import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axis_team/core/staffing_calculator.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/ui/views/rosters_view.dart';
import 'package:axis_team/ui/views/dashboard_view.dart';
import 'package:axis_team/providers/app_providers.dart';

void main() {
  group('StaffingCalculator Unit Tests', () {
    test('calculateCoveredShifts sums member avgShifts correctly', () {
      final members = [
        UserModel(id: '1', avgShifts: '5'),
        UserModel(id: '2', avgShifts: '4'),
        UserModel(id: '3', avgShifts: null),
        UserModel(id: '4', avgShifts: 'invalid'),
      ];
      expect(StaffingCalculator.calculateCoveredShifts(members), equals(9));
    });

    test('calculateHiresNeeded matches screenshot scenario 1: SVC 5 shifts/day (=30/wk), covered 29 -> 1 hire', () {
      // 7 members with total covered 29
      final members = [
        UserModel(id: '1', avgShifts: '5'),
        UserModel(id: '2', avgShifts: '5'),
        UserModel(id: '3', avgShifts: '3'),
        UserModel(id: '4', avgShifts: '3'),
        UserModel(id: '5', avgShifts: '3'),
        UserModel(id: '6', avgShifts: '5'),
        UserModel(id: '7', avgShifts: '5'),
      ];
      // Daily needed = 5 -> weekly needed = 30. Covered = 29. Deficit = 1.
      // Average shift = 29 / 7 = 4.14.
      // Hires needed = ceil(1 / 4.14) = 1 hire!
      expect(
        StaffingCalculator.calculateHiresNeeded(dailyShiftsNeeded: 5, members: members),
        equals(1),
      );
    });

    test('calculateHiresNeeded matches screenshot scenario 2: DT 6 shifts/day (=36/wk), covered 37 -> 0 hires (surplus)', () {
      // 8 members with total covered 37
      final members = [
        UserModel(id: '1', avgShifts: '5'),
        UserModel(id: '2', avgShifts: '5'),
        UserModel(id: '3', avgShifts: '5'),
        UserModel(id: '4', avgShifts: '3'),
        UserModel(id: '5', avgShifts: '5'),
        UserModel(id: '6', avgShifts: '5'),
        UserModel(id: '7', avgShifts: '4'),
        UserModel(id: '8', avgShifts: '5'),
      ];
      // Daily needed = 6 -> weekly needed = 36. Covered = 37. Deficit = 0.
      expect(
        StaffingCalculator.calculateHiresNeeded(dailyShiftsNeeded: 6, members: members),
        equals(0),
      );
    });

    test('calculateHiresNeeded matches screenshot scenario 3: KT 8 shifts/day (=48/wk), covered 40 -> 2 hires', () {
      // 8 members with total covered 40
      final members = List.generate(8, (i) => UserModel(id: '$i', avgShifts: '5'));
      // Daily needed = 8 -> weekly needed = 48. Covered = 40. Deficit = 8.
      // Average shift = 5.
      // Hires needed = ceil(8 / 5) = 2 hires!
      expect(
        StaffingCalculator.calculateHiresNeeded(dailyShiftsNeeded: 8, members: members),
        equals(2),
      );
    });

    test('calculateHiresNeeded falls back to 4.0 when no members or 0 avgShifts', () {
      final members = <UserModel>[];
      // Daily needed = 2 -> weekly needed = 12. Covered = 0. Deficit = 12.
      // Fallback avgShift = 4.0.
      // Hires needed = ceil(12 / 4.0) = 3.
      expect(
        StaffingCalculator.calculateHiresNeeded(dailyShiftsNeeded: 2, members: members),
        equals(3),
      );
    });

    test('calculateAllDeficits evaluates daily needed * 6 as weekly needed', () {
      final users = [
        UserModel(id: 'u1', store: 's1', position: 'FOH', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'u2', store: 's1', position: 'FOH', workingTime: 'Night', avgShifts: '4'),
        UserModel(id: 'u3', store: 's1', title: 'Director', avgShifts: '5'),
      ];

      final rosterNeeds = {
        's1_FOH_Day': 3, // 3/day -> 18/wk. Covered 5 -> deficit 13 -> hires ceil(13/5) = 3
        's1_FOH_Night': 1, // 1/day -> 6/wk. Covered 4 -> deficit 2 -> hires ceil(2/4) = 1
        's1_Director': 1, // 1/day -> 6/wk. Covered 5 -> deficit 1 -> hires ceil(1/5) = 1
      };

      final stores = [
        {'id': 's1', 'name': 'Store One'},
      ];

      final storeSettingsMap = {
        's1': const StoreSettingsModel(
          positions: ['FOH'],
          workingTimes: ['Day', 'Night'],
          titles: [
            TitleConfig(id: 't1', name: 'Director', color: 'Blue', isolatedRoster: true),
          ],
        ),
      };

      final deficits = StaffingCalculator.calculateAllDeficits(
        users: users,
        rosterNeeds: rosterNeeds,
        stores: stores,
        storeSettingsMap: storeSettingsMap,
        currentStoreId: 's1',
      );

      final fohDay = deficits.firstWhere((d) => d.key == 's1_FOH_Day');
      expect(fohDay.dailyShiftsNeeded, equals(3));
      expect(fohDay.weeklyShiftsNeeded, equals(18));
      expect(fohDay.shiftsCovered, equals(5));
      expect(fohDay.shiftDeficit, equals(13));
      expect(fohDay.hiresNeeded, equals(3));

      final fohNight = deficits.firstWhere((d) => d.key == 's1_FOH_Night');
      expect(fohNight.dailyShiftsNeeded, equals(1));
      expect(fohNight.weeklyShiftsNeeded, equals(6));
      expect(fohNight.shiftDeficit, equals(2));
      expect(fohNight.hiresNeeded, equals(1));
    });

    test('when all tiles are covered total hires is 0, not 288', () {
      final users = [
        UserModel(id: 'u1', store: 's1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'u2', store: 's1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'u3', store: 's1', position: 'DT', workingTime: 'Day', avgShifts: '6'),
      ];

      // 1 shift/day for SVC -> 6/wk. Covered = 10 -> surplus.
      // 1 shift/day for DT -> 6/wk. Covered = 6 -> covered.
      // Old leftover keys in Firestore data must NOT create phantom 288 shifts / hires:
      final rosterNeeds = {
        's1_SVC_Day': 1,
        's1_DT_Day': 1,
        's1_FOH': 48,
        's1_SVC': 48,
      };

      final stores = [
        {'id': 's1', 'name': 'Store One'},
      ];

      final storeSettingsMap = {
        's1': const StoreSettingsModel(
          positions: ['SVC', 'DT'],
          workingTimes: ['Day'],
        ),
      };

      final deficits = StaffingCalculator.calculateAllDeficits(
        users: users,
        rosterNeeds: rosterNeeds,
        stores: stores,
        storeSettingsMap: storeSettingsMap,
        currentStoreId: 's1',
      );

      final totalHires = deficits.fold<int>(0, (sum, d) => sum + d.hiresNeeded);
      expect(totalHires, equals(0));
    });

    test('calculates hires per tile using that tile’s average shifts and adds up to total hires', () {
      // 3 tiles: SVC (needs 1 hire), DT (covered -> 0 hires), KT (needs 2 hires)
      final users = [
        // SVC: 7 staff, 29 covered. Avg = 29/7 = 4.14
        UserModel(id: 's1', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 's2', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 's3', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '3'),
        UserModel(id: 's4', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '3'),
        UserModel(id: 's5', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '3'),
        UserModel(id: 's6', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 's7', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),

        // DT: 8 staff, 37 covered
        UserModel(id: 'd1', store: 'store_1', position: 'DT', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'd2', store: 'store_1', position: 'DT', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'd3', store: 'store_1', position: 'DT', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'd4', store: 'store_1', position: 'DT', workingTime: 'Day', avgShifts: '3'),
        UserModel(id: 'd5', store: 'store_1', position: 'DT', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'd6', store: 'store_1', position: 'DT', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'd7', store: 'store_1', position: 'DT', workingTime: 'Day', avgShifts: '4'),
        UserModel(id: 'd8', store: 'store_1', position: 'DT', workingTime: 'Day', avgShifts: '5'),

        // KT: 8 staff, 40 covered. Avg = 40/8 = 5.0
        ...List.generate(8, (i) => UserModel(id: 'k$i', store: 'store_1', position: 'KT', workingTime: 'Day', avgShifts: '5')),
      ];

      final rosterNeeds = {
        'store_1_SVC_Day': 5, // 30 needed, 29 covered -> deficit 1 -> ceil(1 / 4.14) = 1 hire
        'store_1_DT_Day': 6,  // 36 needed, 37 covered -> deficit 0 -> 0 hires
        'store_1_KT_Day': 8,  // 48 needed, 40 covered -> deficit 8 -> ceil(8 / 5.0) = 2 hires
      };

      final stores = [
        {'id': 'store_1', 'name': 'Main Store'},
      ];

      final storeSettingsMap = {
        'store_1': const StoreSettingsModel(
          positions: ['SVC', 'DT', 'KT'],
          workingTimes: ['Day'],
        ),
      };

      final results = StaffingCalculator.calculateAllDeficits(
        users: users,
        rosterNeeds: rosterNeeds,
        stores: stores,
        storeSettingsMap: storeSettingsMap,
        currentStoreId: 'store_1',
      );

      final svc = results.firstWhere((r) => r.key == 'store_1_SVC_Day');
      expect(svc.hiresNeeded, equals(1));

      final dt = results.firstWhere((r) => r.key == 'store_1_DT_Day');
      expect(dt.hiresNeeded, equals(0));

      final kt = results.firstWhere((r) => r.key == 'store_1_KT_Day');
      expect(kt.hiresNeeded, equals(2));

      // Sum of hires across all roster tiles
      final totalHires = results.fold<int>(0, (sum, r) => sum + r.hiresNeeded);
      expect(totalHires, equals(3));
    });
  });

  group('Hires totals add up', () {
    // Two stores. s1 has a customized roster (an isolated Shift Lead tile);
    // s2 uses its default tiles.
    final stores = [
      {'id': 's1', 'name': 'One'},
      {'id': 's2', 'name': 'Two'},
    ];
    final settingsMap = {
      's1': const StoreSettingsModel(
        positions: ['FOH', 'KT'],
        workingTimes: ['Day'],
        titles: [TitleConfig(id: 'sl', name: 'Shift Lead')],
      ),
      's2': const StoreSettingsModel(positions: ['FOH'], workingTimes: ['Day']),
    };
    final users = [
      UserModel(id: 'a', store: 's1', position: 'FOH', workingTime: 'Day', avgShifts: '4'),
      UserModel(id: 'b', store: 's1', position: 'FOH', workingTime: 'Day', avgShifts: '4.5'),
      UserModel(id: 'c', store: 's1', position: 'KT', workingTime: 'Day', avgShifts: '5'),
      UserModel(id: 'd', store: 's1', position: 'KT', workingTime: 'Day', avgShifts: '5'),
      UserModel(id: 'e', store: 's1', position: 'KT', workingTime: 'Day', title: 'Shift Lead', avgShifts: '5'),
      UserModel(id: 'f', store: 's2', position: 'FOH', workingTime: 'Day', avgShifts: '3'),
    ];
    final needs = {
      's1_FOH_Day': 3, // 18/wk, covered 8.5, avg 4.25 -> ceil(9.5/4.25) = 3
      's1_KT_Day': 1, // 6/wk, covered 15 -> surplus 9, avg 5 -> 1 person
      's1_Shift Lead': 1, // 6/wk, covered 5 -> 1 hire
      's2_FOH_Day': 2, // 12/wk, covered 3, avg 3 -> 3 hires
    };
    final layouts = <String, List<dynamic>?>{
      's1': [
        {'id': 's1|Day - FOH|FOH|false|Day'},
        {'id': 's1|Day - KT|KT|false|Day'},
        {'id': 's1|Shift Lead|Shift Lead|true|Other'},
      ],
    };

    List<PositionStaffingResult> run(String? storeId) =>
        StaffingCalculator.calculateAllDeficits(
          users: users,
          rosterNeeds: needs,
          stores: stores,
          storeSettingsMap: settingsMap,
          currentStoreId: storeId,
          layoutsByStore: layouts,
        );

    test('each group follows daily x 6, sum of avg shifts, and the group average', () {
      final s1 = run('s1');
      final foh = s1.firstWhere((r) => r.key == 's1_FOH_Day');
      expect(foh.weeklyShiftsNeeded, 18);
      expect(foh.shiftsCovered, 8.5);
      expect(foh.hiresNeeded, 3);

      final kt = s1.firstWhere((r) => r.key == 's1_KT_Day');
      expect(kt.hiresNeeded, 0);
      expect(kt.shiftSurplus, 4); // isolated Shift Lead isn't in KT: 10 - 6
      expect(kt.surplusPeople, 0);

      final lead = s1.firstWhere((r) => r.key == 's1_Shift Lead');
      expect(lead.hiresNeeded, 1);
    });

    test('All Stores equals the sum of each store, and surpluses are not subtracted', () {
      final one = StaffingTotals.of(run('s1'));
      final two = StaffingTotals.of(run('s2'));
      final all = StaffingTotals.of(run(null));

      expect(one.hiresNeeded, 4); // 3 + 0 + 1
      expect(two.hiresNeeded, 3);
      expect(all.hiresNeeded, one.hiresNeeded + two.hiresNeeded);
      expect(all.weeklyShiftsNeeded, 18 + 6 + 6 + 12);
      expect(
        all.weeklyShiftsNeeded,
        one.weeklyShiftsNeeded + two.weeklyShiftsNeeded,
      );
    });

    test('a surplus is reported in people', () {
      final r = StaffingCalculator.evaluateGroup(
        key: 'k',
        storeId: 's',
        displayName: 'X',
        dailyShiftsNeeded: 5, // 30/wk
        members: List.generate(8, (i) => UserModel(id: '$i', avgShifts: '5')),
      ); // 40 covered, +10, avg 5 -> 2 people
      expect(r.hiresNeeded, 0);
      expect(r.shiftSurplus, 10);
      expect(r.surplusPeople, 2);
    });
  });

  group('RostersView Widget Tests', () {
    testWidgets('Roster tile displays Shifts/Day: 5 (=30/wk), staff count, and coverage banner',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 7 staff with total 29 shifts (matching screenshot Tile 1: SVC)
      final users = [
        UserModel(id: 'u1', firstName: 'Rosa', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'u2', firstName: 'Priya', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'u3', firstName: 'Andrew', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '3'),
        UserModel(id: 'u4', firstName: 'Janet', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '3'),
        UserModel(id: 'u5', firstName: 'Owen', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '3'),
        UserModel(id: 'u6', firstName: 'Victor', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),
        UserModel(id: 'u7', firstName: 'Casey', store: 'store_1', position: 'SVC', workingTime: 'Day', avgShifts: '5'),
      ];

      const settings = StoreSettingsModel(
        positions: ['SVC'],
        workingTimes: ['Day'],
      );

      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_1'),
          allStoresStreamProvider.overrideWith(
            (ref) => Stream.value([
              {'id': 'store_1', 'name': 'Main Store', 'is_dev': false},
            ]),
          ),
          storeStreamProvider('store_1').overrideWith(
            (ref) => Stream.value({
              'id': 'store_1',
              'name': 'Main Store',
              'is_dev': false,
            }),
          ),
          currentMembersProvider.overrideWith(
            (ref) => AsyncValue.data(users),
          ),
          rosterNeedsStreamProvider.overrideWith(
            (ref) => Stream.value(<String, dynamic>{
              'store_1_SVC_Day': 5, // 5 shifts/day -> 30/wk. 29 covered -> 1 deficit, 1 hire
            }),
          ),
          specificStoreSettingsProvider('store_1').overrideWith(
            (ref) => Stream.value(settings),
          ),
          currentUserProvider.overrideWith(
            (ref) => {'id': 'user_1', 'first_name': 'Alex', 'owned_stores': ['store_1']},
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: RostersView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header staff count
      expect(find.text('7 staff'), findsOneWidget);

      // Check subheader: Shifts/Day: and (=30/wk)
      expect(find.text('Shifts/Day:'), findsOneWidget);
      final countFinder = find.byKey(const ValueKey('roster_need_count_SVC_Day'));
      expect(countFinder, findsOneWidget);
      expect((tester.widget(countFinder) as Text).data, equals('5'));
      expect(find.text('(=30/wk)'), findsOneWidget);

      // Check coverage banner: Covered: 29/30 (-1) • Need 1 hire
      expect(find.text('Covered: 29/30 (-1) • Need 1 hire'), findsOneWidget);

      // Hover over the adjuster number
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(countFinder));
      await tester.pumpAndSettle();

      // After hovering, keyboard_arrow_up and keyboard_arrow_down should appear!
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    });
  });

  group('DashboardView Staffing Deficits Widget Tests', () {
    testWidgets('Dashboard staffing deficits tile matches daily * 6 calculation',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final users = [
        UserModel(
          id: 'u1',
          firstName: 'Alice',
          store: 'store_1',
          position: 'FOH',
          workingTime: 'Day',
          avgShifts: '5',
          startDate: DateTime(2023, 1, 1),
        ),
      ];

      const settings = StoreSettingsModel(
        positions: ['FOH'],
        workingTimes: ['Day'],
      );

      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_1'),
          allStoresStreamProvider.overrideWith(
            (ref) => Stream.value([
              {'id': 'store_1', 'name': 'Main Store', 'is_dev': false},
            ]),
          ),
          storeStreamProvider('store_1').overrideWith(
            (ref) => Stream.value({
              'id': 'store_1',
              'name': 'Main Store',
              'is_dev': false,
            }),
          ),
          currentMembersProvider.overrideWith(
            (ref) => AsyncValue.data(users),
          ),
          rosterNeedsStreamProvider.overrideWith(
            (ref) => Stream.value(<String, dynamic>{
              'store_1_FOH_Day': 3, // 3/day -> 18/wk needed, 5 covered -> deficit 13, hires 3
            }),
          ),
          specificStoreSettingsProvider('store_1').overrideWith(
            (ref) => Stream.value(settings),
          ),
          storeSettingsProvider.overrideWith(
            (ref) => Stream.value(settings),
          ),
          currentUserProvider.overrideWith(
            (ref) => {'id': 'user_1', 'first_name': 'Alex', 'owned_stores': ['store_1']},
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: DashboardView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check deficits card
      expect(find.text('ROSTER STAFFING DEFICITS'), findsOneWidget);
      expect(find.text('3 Hires Needed'), findsOneWidget);
      expect(find.text('3 Hires'), findsOneWidget);
      expect(find.text('(-13 of 18 shifts/wk)'), findsOneWidget);
    });
  });
}
