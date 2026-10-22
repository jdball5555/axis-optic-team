import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/ui/views/account_view.dart';
import 'package:axis_team/ui/views/store_view.dart';
import 'package:axis_team/ui/widgets/change_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'StoreRow locked add-ons have tooltips and do not allow clicking/toggling',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeStreamProvider('store-1').overrideWith(
              (ref) => Stream.value({'id': 'store-1', 'name': 'Test Store'}),
            ),
            specificStoreSettingsProvider('store-1').overrideWith(
              (ref) => Stream.value(
                const StoreSettingsModel(
                  isScheduleEnabled: true,
                  isShiftBoardEnabled: false,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StoreRow(
                storeId: 'store-1',
                initialStoreName: 'Test Store',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify both add-on titles exist
      expect(find.text('Schedule Add-on'), findsOneWidget);
      expect(find.text('Shift Board Add-on'), findsOneWidget);

      // Verify tooltips exist on both add-ons with feedback message
      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .toList();
      final hasFeedbackTooltip = tooltips.any(
        (t) =>
            t.message ==
            'Submit a feedback request to talk to the team about enabling this feature.',
      );
      expect(hasFeedbackTooltip, isTrue);

      // Verify switches render their current state
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.length, 2);
      expect(switches[0].value, isTrue); // isScheduleEnabled = true
      expect(switches[1].value, isFalse); // isShiftBoardEnabled = false

      // Tap Schedule Add-on (should be absorbed by AbsorbPointer)
      await tester.tap(find.text('Schedule Add-on'), warnIfMissed: false);
      await tester.pump();

      // No SnackBar should be displayed
      expect(find.byType(SnackBar), findsNothing);

      // Verify switch states did NOT change
      final switchesAfter = tester
          .widgetList<Switch>(find.byType(Switch))
          .toList();
      expect(switchesAfter[0].value, isTrue);
      expect(switchesAfter[1].value, isFalse);
    },
  );

  testWidgets(
    'AccountView allows changing name directly in settings without dialog',
    (tester) async {
      final container = ProviderContainer();
      container.read(currentUserProvider.notifier).state = {
        'id': 'user-123',
        'first_name': 'Original',
        'last_name': 'Owner',
        'email': 'owner@example.com',
        'owned_stores': ['store-1'],
      };

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountView()),
        ),
      );

      await tester.pumpAndSettle();

      // Verify initial name display
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);

      // Tap 'Edit Name' button in settings
      await tester.tap(find.text('Edit Name'));
      await tester.pumpAndSettle();

      // Ensure NO AlertDialog or modal dialog is shown
      expect(find.byType(AlertDialog), findsNothing);

      // Inline TextFormFields should now be visible in the card
      final firstFields = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'Original',
      );
      expect(firstFields, findsOneWidget);

      final lastFields = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == 'Owner',
      );
      expect(lastFields, findsOneWidget);

      // Edit name inline
      await tester.enterText(firstFields, 'UpdatedFirst');
      await tester.enterText(lastFields, 'UpdatedLast');

      // Click inline Save button
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify state was updated in currentUserProvider
      final updatedUser = container.read(currentUserProvider);
      expect(updatedUser?['first_name'], 'UpdatedFirst');
      expect(updatedUser?['last_name'], 'UpdatedLast');

      // Verify view is out of edit mode and displays updated name
      expect(find.text('UpdatedFirst'), findsOneWidget);
      expect(find.text('UpdatedLast'), findsOneWidget);
    },
  );

  testWidgets('updateUserName updates current user state directly', (
    tester,
  ) async {
    final container = ProviderContainer();
    container.read(currentUserProvider.notifier).state = {
      'id': 'user-123',
      'first_name': 'Original',
      'last_name': 'Owner',
      'email': 'owner@example.com',
      'owned_stores': ['store-1'],
    };

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                return ElevatedButton(
                  onPressed: () async {
                    await updateUserName(
                      ref: ref,
                      newFirst: 'Jane',
                      newLast: 'Doe',
                    );
                  },
                  child: const Text('Update Direct'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Update Direct'));
    await tester.pumpAndSettle();

    final updated = container.read(currentUserProvider);
    expect(updated?['first_name'], 'Jane');
    expect(updated?['last_name'], 'Doe');
  });
}
