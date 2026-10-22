import 'package:flutter_test/flutter_test.dart';
import 'package:axis_team/ui/views/rosters_view.dart';

CustomRosterItem item(
  String id, {
  double x = 0,
  double y = 0,
  List<String>? split,
}) => CustomRosterItem(id: id, x: x, y: y, splitTitles: split);

void main() {
  test('a store roster saved wrongly is cleaned up', () {
    final cleaned = cleanStoreRosterBoard('s1', 'Main', [
      item('s1|Day - FOH|FOH|false|Day', x: 0),
      // Saved from All Stores by mistake: store name in front of the title.
      item('s1|Main - Day - Kitchen|Kitchen|false|Day', x: 350),
      // The same tile again.
      item('s1|Main - Day - FOH|FOH|false|Day', x: 700),
      // Another store's tile.
      item('s2|North - Day - FOH|FOH|false|Day', x: 1050),
    ]);
    expect(cleaned.map((i) => i.id).toList(), [
      's1|Day - FOH|FOH|false|Day',
      's1|Day - Kitchen|Kitchen|false|Day',
    ]);
    expect(cleaned[1].x, 350); // positions kept
  });

  test('All Stores shows each store\'s roster as is, one below the other', () {
    final main = [
      item('s1|Day - FOH|FOH|false|Day', x: 0, y: 0),
      item('s1|Day - Kitchen|Kitchen|false|Day', x: 350, y: 0),
      item('s1|Shift Lead|Shift Lead|true|Other', x: 0, y: 550, split: ['A']),
    ];
    final north = [item('s2|Day - FOH|FOH|false|Day', x: 0, y: 0)];

    final all = composeAllStoresBoard([
      (id: 's1', name: 'Main', board: main),
      (id: 's2', name: 'North', board: north),
    ]);

    final byId = {for (final i in all.items) i.id: i};
    expect(byId.keys, {
      's1|Main - Day - FOH|FOH|false|Day',
      's1|Main - Day - Kitchen|Kitchen|false|Day',
      's1|Main - Shift Lead|Shift Lead|true|Other',
      's2|North - Day - FOH|FOH|false|Day',
    });
    // The first store keeps its layout exactly...
    expect(byId['s1|Main - Day - Kitchen|Kitchen|false|Day']!.x, 350);
    expect(byId['s1|Main - Shift Lead|Shift Lead|true|Other']!.y, 550);
    expect(byId['s1|Main - Shift Lead|Shift Lead|true|Other']!.splitTitles, [
      'A',
    ]);
    // ...and the second store starts right below it.
    expect(byId['s2|North - Day - FOH|FOH|false|Day']!.y, 1100);
    expect(all.offsets, {'s1': 0.0, 's2': 1100.0});
  });

  test('changes on All Stores go back to each store\'s own roster', () {
    final all = composeAllStoresBoard([
      (id: 's1', name: 'Main', board: [item('s1|Day - FOH|FOH|false|Day')]),
      (id: 's2', name: 'North', board: [item('s2|Day - FOH|FOH|false|Day')]),
    ]);
    final items = List.of(all.items)
      // A tile added to North on All Stores, next to its first tile.
      ..add(item('s2|North - Day - Kitchen|Kitchen|false|Day', x: 350, y: 550));
    // A North tile moved over.
    items.firstWhere((i) => i.id.startsWith('s2|')).x = 700;

    final split = splitAllStoresBoard(items, const {
      's1': 'Main',
      's2': 'North',
    }, all.offsets);

    expect(split['s1']!.map((i) => i.id), ['s1|Day - FOH|FOH|false|Day']);
    expect(split['s2']!.map((i) => (i.id, i.x, i.y)), [
      ('s2|Day - FOH|FOH|false|Day', 700.0, 0.0),
      ('s2|Day - Kitchen|Kitchen|false|Day', 350.0, 0.0),
    ]);

    // Put back together, it's the same board.
    final again = composeAllStoresBoard([
      (id: 's1', name: 'Main', board: split['s1']!),
      (id: 's2', name: 'North', board: split['s2']!),
    ]);
    expect(
      again.items.map((i) => (i.id, i.x, i.y)).toSet(),
      items.map((i) => (i.id, i.x, i.y)).toSet(),
    );
  });
}
