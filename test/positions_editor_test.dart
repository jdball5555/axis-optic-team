import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/ui/views/schedule/positions_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dragging a position reports the new order right away', (
    tester,
  ) async {
    final saves = <List<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PositionsEditor(
            positions: const [
              ShiftPosition(id: 'a', name: 'Front Counter'),
              ShiftPosition(id: 'b', name: 'DT Order Taker'),
              ShiftPosition(id: 'c', name: 'Fries'),
            ],
            onChanged: (list) => saves.add([for (final p in list) p.id]),
          ),
        ),
      ),
    );
    // Drag Front Counter below DT Order Taker.
    final handle = find.byIcon(Icons.drag_indicator).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    final rowHeight =
        tester.getSize(find.byKey(const ValueKey('a'))).height + 8;
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, rowHeight * 1.2 / 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(saves.last, ['b', 'a', 'c']);

    // Renaming reports the change too, keeping the order.
    await tester.enterText(find.byType(TextFormField).last, 'Fries 1');
    await tester.pump();
    expect(saves.last, ['b', 'a', 'c']);
  });
}
