import 'package:axis_team/ui/widgets/equal_height_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cards in a row all get the tallest card\'s height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EqualHeightRow(
              children: [
                const Card(key: Key('short'), child: Text('one line')),
                Card(
                  key: const Key('tall'),
                  child: Column(
                    children: [
                      ListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (var i = 0; i < 8; i++) Text('title $i'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final short = tester.getSize(find.byKey(const Key('short')));
    final tall = tester.getSize(find.byKey(const Key('tall')));
    expect(short.height, tall.height);
    expect(tall.height, greaterThan(100));
    expect(short.width, tall.width);
  });

  testWidgets('in a fixed-height space (the store-name header) it fills it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverPersistentHeader(pinned: true, delegate: _Header()),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('a'))).height, 68);
  });
}

class _Header extends SliverPersistentHeaderDelegate {
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: const EqualHeightRow(
      children: [
        Center(
          key: Key('a'),
          child: Text('North', style: TextStyle(fontSize: 32)),
        ),
        Center(child: Text('Other store', style: TextStyle(fontSize: 32))),
      ],
    ),
  );

  @override
  double get maxExtent => 100;
  @override
  double get minExtent => 100;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}
