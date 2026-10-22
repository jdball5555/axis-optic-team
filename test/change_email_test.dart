import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/ui/views/account_view.dart';
import 'package:axis_team/ui/widgets/change_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Change Email functionality', () {
    testWidgets('AccountView displays Change Email button and clickable Email field', (tester) async {
      final user = {
        'id': 'test-uid-1',
        'first_name': 'Test',
        'last_name': 'User',
        'email': 'current@example.com',
        'role': 'owner',
        'owned_stores': ['store-1'],
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => user),
            allStoresStreamProvider.overrideWith((ref) => Stream.value([
              {'id': 'store-1', 'name': 'Store 1', 'store_name': 'Store 1'}
            ])),
          ],
          child: const MaterialApp(
            home: AccountView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check for Change Email button
      expect(find.text('Change Email'), findsOneWidget);

      // Check that Email field is present
      expect(find.text('current@example.com'), findsOneWidget);

      // Tap Change Email button to open dialog
      await tester.tap(find.text('Change Email'));
      await tester.pumpAndSettle();

      // Verify Change Email dialog appears
      expect(find.text('Change Email'), findsNWidgets(2)); // Button + Dialog header
      expect(
        find.text('When you change your email, your password stays the same. You will use this new email to sign in.'),
        findsOneWidget,
      );
      expect(find.text('Save Email'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Tap the Email info field itself (it should also open the dialog)
      await tester.tap(find.text('current@example.com'));
      await tester.pumpAndSettle();

      expect(find.text('Save Email'), findsOneWidget);
    });

    testWidgets('showChangeEmailDialog validates empty or malformed email', (tester) async {
      final user = {
        'id': 'test-uid-2',
        'first_name': 'Sample',
        'last_name': 'User',
        'email': 'sample@test.com',
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => user),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () => showChangeEmailDialog(context, ref),
                    child: const Text('Open Dialog'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Clear the text field
      final textField = find.byType(TextField);
      await tester.enterText(textField, 'invalidemail');
      await tester.pumpAndSettle();

      // Tap Save Email
      await tester.tap(find.text('Save Email'));
      await tester.pumpAndSettle();

      // Should show validation error
      expect(find.text('Please enter a valid email address.'), findsOneWidget);
    });
  });
}

