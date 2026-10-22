import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/ui/widgets/multi_select_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('status: Active, Leaving until the last day, Former after it', () {
    final today = DateTime(2026, 10, 12);
    expect(memberStatus(const UserModel(), today: today), 'Active');
    expect(
      memberStatus(UserModel(endDate: DateTime(2026, 10, 20)), today: today),
      'Leaving',
    );
    // Their last day is today: still leaving.
    expect(
      memberStatus(UserModel(endDate: DateTime(2026, 10, 12)), today: today),
      'Leaving',
    );
    expect(
      memberStatus(UserModel(endDate: DateTime(2026, 10, 11)), today: today),
      'Former',
    );
    expect(memberStatus(const UserModel(status: 'Inactive')), 'Inactive');
    expect(isCurrentMember(UserModel(endDate: DateTime(2020))), isFalse);
    expect(isCurrentMember(UserModel(endDate: DateTime(2999))), isTrue);
  });

  testWidgets('tags field is the same height as a normal dropdown', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 14);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DropdownButtonFormField<String>(
                key: const Key('normal'),
                initialValue: 'Adult',
                style: style,
                decoration: const InputDecoration(),
                items: const [
                  DropdownMenuItem(value: 'Adult', child: Text('Adult')),
                ],
                onChanged: (_) {},
              ),
              MultiSelectField(
                key: const Key('tags'),
                style: style,
                options: const ['Trainer', 'Truck'],
                selected: const ['Trainer'],
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('tags'))).height,
      tester.getSize(find.byKey(const Key('normal'))).height,
    );
    // Opens a checkbox list; picking keeps it open.
    await tester.tap(find.byKey(const Key('tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Truck'));
    await tester.pumpAndSettle();
    expect(find.byType(AppCheckbox), findsWidgets);
    expect(find.text('Trainer, Truck'), findsOneWidget);
  });
}
