import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/ui/views/schedule/schedule_ops.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleRow _row(int s, int e, {List<String> titles = const []}) => ScheduleRow(
  id: newScheduleId(),
  windows: [TimeWindow(s * 60, e * 60)],
  allowedTitles: titles,
);

void main() {
  test('non-overlapping windows share a row', () {
    final rows = packRows([_row(11, 17)], [_row(18, 22)]);
    expect(rows, hasLength(1));
    expect(rows.single.windows, [
      const TimeWindow(11 * 60, 17 * 60),
      const TimeWindow(18 * 60, 22 * 60),
    ]);
  });

  test('overlapping windows get their own row', () {
    expect(packRows([_row(11, 17)], [_row(16, 22)]), hasLength(2));
  });

  test('rows for different titles are not combined', () {
    expect(
      packRows(
        [_row(11, 17)],
        [
          _row(18, 22, titles: ['Leader']),
        ],
      ),
      hasLength(2),
    );
  });

  test('several new rows fill separate gaps', () {
    final rows = packRows(
      [_row(6, 10), _row(6, 10)],
      [_row(11, 15), _row(11, 15), _row(11, 15)],
    );
    expect(rows, hasLength(3));
    expect(rows[0].windows, hasLength(2));
    expect(rows[1].windows, hasLength(2));
    expect(rows[2].windows, hasLength(1));
  });

  test('compactRows merges an existing template', () {
    expect(
      compactRows([_row(5, 23), _row(11, 17), _row(18, 22)]),
      hasLength(2),
    );
  });

  test('bars that touch become one bar', () {
    final rows = packRows([_row(11, 17)], [_row(17, 22)]);
    expect(rows.single.windows, [const TimeWindow(11 * 60, 22 * 60)]);
  });

  test(
    'placeShift defaults to 6 hours from the drop point, inside the bar',
    () {
      const bar = TimeWindow(5 * 60, 23 * 60);
      expect(placeShift(bar, 14 * 60 + 7), const TimeWindow(14 * 60, 20 * 60));
      expect(placeShift(bar, 21 * 60), const TimeWindow(17 * 60, 23 * 60));
      expect(
        placeShift(const TimeWindow(11 * 60, 14 * 60), 12 * 60),
        const TimeWindow(11 * 60, 14 * 60),
      );
    },
  );
}
