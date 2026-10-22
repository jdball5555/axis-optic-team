import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/ui/views/access_view.dart';
import 'package:axis_team/ui/views/member_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccessView account access options', () {
    testWidgets(
      'When schedule and shift are disabled, dialog only allows bot accounts',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              allStoreUsersStreamProvider.overrideWith(
                (ref) => Stream.value([
                  UserModel(
                    id: 'owner-1',
                    firstName: 'Owner',
                    lastName: 'User',
                    role: 'owner',
                    title: 'Owner',
                  ),
                ]),
              ),
              storeSettingsProvider.overrideWith(
                (ref) => Stream.value(
                  const StoreSettingsModel(
                    isScheduleEnabled: false,
                    isShiftBoardEnabled: false,
                  ),
                ),
              ),
              currentStoreIdProvider.overrideWith((ref) => 'store-1'),
            ],
            child: const MaterialApp(home: AccessView()),
          ),
        );

        await tester.pumpAndSettle();

        // Button shows 'Add Bot Account'
        expect(find.text('Add Bot Account'), findsOneWidget);

        // Click to open dialog
        await tester.tap(find.text('Add Bot Account'));
        await tester.pumpAndSettle();

        // Dialog should open with 'Add Bot Account'
        expect(
          find.text('Add Bot Account'),
          findsNWidgets(2),
        ); // Button + Dialog title
        // Should NOT have 'Team Member' radio option
        expect(find.text('Team Member'), findsNothing);
        // Should have Bot fields
        expect(find.widgetWithText(TextField, 'Bot Name'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Bot Email'), findsOneWidget);
        // Explanatory note
        expect(
          find.text(
            'Team member accounts are disabled. Enable Schedule or Shift Board to grant access to team members.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'When schedule or shift is enabled, dialog allows both bot accounts and team members',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              allStoreUsersStreamProvider.overrideWith(
                (ref) => Stream.value([
                  UserModel(
                    id: 'owner-1',
                    firstName: 'Owner',
                    lastName: 'User',
                    role: 'owner',
                    title: 'Owner',
                  ),
                ]),
              ),
              storeSettingsProvider.overrideWith(
                (ref) => Stream.value(
                  const StoreSettingsModel(
                    isScheduleEnabled: true,
                    isShiftBoardEnabled: false,
                  ),
                ),
              ),
              currentStoreIdProvider.overrideWith((ref) => 'store-1'),
            ],
            child: const MaterialApp(home: AccessView()),
          ),
        );

        await tester.pumpAndSettle();

        // Button shows 'Add or Give Account Access'
        expect(find.text('Add or Give Account Access'), findsOneWidget);

        // Click to open dialog
        await tester.tap(find.text('Add or Give Account Access'));
        await tester.pumpAndSettle();

        // Dialog title
        expect(find.text('Add or Give Account Access'), findsNWidgets(2));
        // Both Bot and Team Member radio options are present
        expect(find.text('Bot Account (View Only)'), findsOneWidget);
        expect(find.text('Team Member'), findsOneWidget);
      },
    );
  });

  group('MemberDetailView bottom tiles', () {
    testWidgets(
      'When schedule and shift are disabled, bottom tiles show locked disabled messages',
      (tester) async {
        final member = UserModel(
          id: 'member-1',
          firstName: 'John',
          lastName: 'Doe',
          email: null,
          store: 'store-1',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userStreamProvider(
                'member-1',
              ).overrideWith((ref) => Stream.value(member)),
              sortedUsersProvider.overrideWith(
                (ref) => AsyncValue.data([member]),
              ),
              specificStoreSettingsProvider('store-1').overrideWith(
                (ref) => Stream.value(
                  const StoreSettingsModel(
                    isScheduleEnabled: false,
                    isShiftBoardEnabled: false,
                  ),
                ),
              ),
              currentStoreIdProvider.overrideWith((ref) => 'store-1'),
              userAvailabilityProvider(
                'member-1',
              ).overrideWith((ref) => Stream.value({})),
              userTimeOffRequestsProvider(
                'member-1',
              ).overrideWith((ref) => Stream.value([])),
            ],
            child: const MaterialApp(
              home: MemberDetailView(userId: 'member-1'),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // All 3 tiles and History Log should exist at the bottom
        expect(find.text('Availability'), findsOneWidget);
        expect(find.text('Time Off Requests'), findsOneWidget);
        expect(find.text('Account Login'), findsOneWidget);
        expect(find.text('History Log'), findsOneWidget);

        // Availability and Time Off show schedule disabled notice
        expect(
          find.text('Enable schedule for the store to see this tile.'),
          findsNWidgets(2),
        );

        // Account Login shows account creation disabled notice
        expect(
          find.text('Enable schedule or shift board to create an account.'),
          findsOneWidget,
        );

        // 'Create Account' button should NOT be shown
        expect(find.text('Create Account'), findsNothing);
      },
    );

    testWidgets(
      'When schedule is enabled, Availability, Time Off, and Account tiles show active contents',
      (tester) async {
        final member = UserModel(
          id: 'member-1',
          firstName: 'John',
          lastName: 'Doe',
          email: 'john@example.com',
          store: 'store-1',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userStreamProvider(
                'member-1',
              ).overrideWith((ref) => Stream.value(member)),
              sortedUsersProvider.overrideWith(
                (ref) => AsyncValue.data([member]),
              ),
              specificStoreSettingsProvider('store-1').overrideWith(
                (ref) => Stream.value(
                  const StoreSettingsModel(
                    isScheduleEnabled: true,
                    isShiftBoardEnabled: false,
                  ),
                ),
              ),
              currentStoreIdProvider.overrideWith((ref) => 'store-1'),
              userAvailabilityProvider(
                'member-1',
              ).overrideWith((ref) => Stream.value({})),
              userTimeOffRequestsProvider(
                'member-1',
              ).overrideWith((ref) => Stream.value([])),
            ],
            child: const MaterialApp(
              home: MemberDetailView(userId: 'member-1'),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Availability active content
        expect(find.text('Availability'), findsOneWidget);
        expect(find.text('No availability set.'), findsOneWidget);

        // Time off active content
        expect(find.text('Time Off Requests'), findsOneWidget);
        expect(find.text('No time off requests found.'), findsOneWidget);

        // Account Login active content with email and reset button
        expect(find.text('Account Login'), findsOneWidget);
        expect(find.text('Email: john@example.com'), findsOneWidget);
        expect(find.text('Send Password Reset Email'), findsOneWidget);
      },
    );
  });
}
