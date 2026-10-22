import 'package:axis_team/ui/views/schedule/requests_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pick a request from past weeks, add your own, build', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<String>? result;
    final forgotten = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showRequestsDialog(
              context,
              past: const [
                'Jordan needs 1 hour of admin after truck',
                'No training on Saturdays',
              ],
              onForget: forgotten.add,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Does anyone need admin time?'), findsOneWidget);
    expect(find.text('From past weeks'), findsOneWidget);

    await tester.tap(find.text('Jordan needs 1 hour of admin after truck'));
    await tester.pump();
    await tester.tap(find.text('Add another request'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).last,
      'Give Sam 2 hours of admin Tuesday',
    );
    // Forget the other one.
    await tester.tap(find.byTooltip('Forget this one').last);
    await tester.pump();
    expect(forgotten, ['No training on Saturdays']);

    await tester.tap(find.text('Build'));
    await tester.pumpAndSettle();
    expect(result, [
      'Jordan needs 1 hour of admin after truck',
      'Give Sam 2 hours of admin Tuesday',
    ]);
  });
}
