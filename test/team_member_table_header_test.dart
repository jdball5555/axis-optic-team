import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axis_team/ui/views/team_roster_view.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/models/store_settings_model.dart';

void main() {
  testWidgets('Team member table headers are full rectangular buttons without pill border radius', (tester) async {
    final mockUser = UserModel(
      id: 'user_1',
      firstName: 'Alice',
      lastName: 'Smith',
      store: 'test_store',
      position: 'Team Member',
      title: 'Trainer',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => {
            'id': 'owner_1',
            'owned_stores': ['test_store'],
          }),
          currentStoreIdProvider.overrideWith((ref) => 'test_store'),
          allStoreUsersStreamProvider.overrideWith((ref) => Stream.value([mockUser])),
          allStoresStreamProvider.overrideWith((ref) => Stream.value([
            {'id': 'test_store', 'name': 'Test Store', 'is_dev': false},
          ])),
          storeSettingsProvider.overrideWith((ref) => Stream.value(const StoreSettingsModel())),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TeamRosterView(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Name header exists
    final nameHeaderFinder = find.text('Name');
    expect(nameHeaderFinder, findsOneWidget);

    // Find the InkWell wrapping the Name header
    final headerInkWells = find.ancestor(
      of: nameHeaderFinder,
      matching: find.byType(InkWell),
    );
    expect(headerInkWells, findsOneWidget);

    final inkWell = tester.widget<InkWell>(headerInkWells);
    // It should NOT have a rounded pill border radius
    expect(inkWell.borderRadius, isNull);

    // Tap the Name header to verify sorting can be triggered
    await tester.tap(nameHeaderFinder);
    await tester.pumpAndSettle();

    // Verify sort arrow icon appears
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });
}

