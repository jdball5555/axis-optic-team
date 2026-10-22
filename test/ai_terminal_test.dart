import 'package:axis_team/ui/views/schedule/ai_build_controller.dart';
import 'package:axis_team/ui/views/schedule/ai_terminal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat sends a change; undo button calls back', (tester) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <String>[];
    var undone = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiTerminalPanel(
            lines: const [],
            busy: false,
            weekLabel: 'Oct 12',
            onBuild: () {},
            onClear: () {},
            onClose: () {},
            undoLabel: 'the AI build',
            onUndo: () => undone++,
            onSend: sent.add,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'No training for Lena on Wednesday',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(sent, ['No training for Lena on Wednesday']);
    await tester.tap(find.text('Undo the AI build'));
    expect(undone, 1);
  });

  test('controller: undo runs once and clears', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(aiBuildProvider.notifier);
    var restored = 0;
    c.setUndo('the AI build', () async => restored++);
    expect(container.read(aiBuildProvider).undoLabel, 'the AI build');
    await c.undo();
    expect(restored, 1);
    expect(container.read(aiBuildProvider).undoLabel, isNull);
    await c.undo();
    expect(restored, 1);
  });
}
