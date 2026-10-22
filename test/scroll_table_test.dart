import 'package:axis_team/ui/widgets/scroll_table.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a diagonal scroll moves the table both ways', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ScrollController? vertical;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollTable(
            width: 2000,
            header: const Text('HEADER'),
            body: (v) {
              vertical = v;
              return ListView.builder(
                controller: v,
                itemCount: 100,
                itemBuilder: (_, i) =>
                    SizedBox(height: 40, child: Text('row $i')),
              );
            },
          ),
        ),
      ),
    );
    final horizontal = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .firstWhere((w) => w.physics is! NeverScrollableScrollPhysics)
        .controller!;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(400, 300)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(60, 80)));
    await tester.pump();
    expect(vertical!.offset, 80);
    expect(horizontal.offset, 60);

    // Sideways only.
    await tester.sendEventToBinding(pointer.scroll(const Offset(40, 0)));
    await tester.pump();
    expect(horizontal.offset, 100);
    expect(vertical!.offset, 80);
  });
}
