import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/ui/views/schedule/schedule_ops.dart';
import 'package:flutter_test/flutter_test.dart';

const _open = 6 * 60;
const _close = 22 * 60;

ScheduleRow _row(String id, int s, int e) =>
    ScheduleRow(id: id, windows: [TimeWindow(s, e)]);

TimeWindow _h(int s, int e) => TimeWindow(s * 60, e * 60);

/// Rows and times each person has, e.g. {'alex': {'r1': [6–11]}}.
Map<String, Map<String, List<TimeWindow>>> _layout(ScheduleDay d) => {
  for (final s in d.shifts)
    s.userId: {
      for (final p in s.pieces)
        p.rowId: [
          for (final q in s.pieces.where((q) => q.rowId == p.rowId))
            TimeWindow(q.start, q.end),
        ],
    },
};

void main() {
  test(
    'new shift takes a whole row; the overlap of another shift is pushed down',
    () {
      // 1 all-day row + 1 lunch row. Alex works open–3 in the all-day row.
      var day = ScheduleDay(
        date: '2026-10-09',
        rows: [_row('all', _open, _close), _row('lunch', 11 * 60, 15 * 60)],
      );
      day = insertShift(
        day,
        userId: 'alex',
        w: TimeWindow(_open, 15 * 60),
        users: const {},
      ).day;
      // Bree 11–6 goes whole into the all-day row; Alex's 11–3 moves to lunch.
      final r = insertShift(
        day,
        userId: 'bree',
        w: _h(11, 18),
        users: const {},
      );
      final l = _layout(r.day);
      expect(l['bree'], {
        'all': [_h(11, 18)],
      });
      expect(l['alex'], {
        'all': [TimeWindow(_open, 11 * 60)],
        'lunch': [_h(11, 15)],
      });
      expect(r.moved.single.window, _h(11, 15));
    },
  );

  test('a shift that ends where another starts shares its row', () {
    var day = ScheduleDay(
      date: '2026-10-09',
      rows: [_row('a', _open, _close), _row('b', _open, _close)],
    );
    // Carl 5p–close sits in the second row.
    day = addPiece(
      day,
      userId: 'carl',
      rowId: 'b',
      start: 17 * 60,
      end: _close,
    );
    final r = insertShift(day, userId: 'dee', w: _h(11, 17), users: const {});
    expect(_layout(r.day)['dee'], {
      'b': [_h(11, 17)],
    });
    expect(r.moved, isEmpty);
  });

  test(
    'when every row is full it gets an extra row instead of splitting people',
    () {
      var day = ScheduleDay(
        date: '2026-10-09',
        rows: [_row('a', _open, _close)],
      );
      day = addPiece(day, userId: 'x', rowId: 'a', start: _open, end: _close);
      final r = insertShift(day, userId: 'y', w: _h(11, 15), users: const {});
      expect(r.day.rows, hasLength(2));
      expect(r.day.rows.last.label, 'Extra');
      expect(_layout(r.day)['x'], {
        'a': [TimeWindow(_open, _close)],
      });
      expect(r.moved, isEmpty);
    },
  );

  test(
    'shrinking a split shift eats the last section, then the one before',
    () {
      final shift = Shift(
        id: 's',
        userId: 'alex',
        pieces: [
          ShiftPiece(id: 'a', rowId: 'all', start: _open, end: 11 * 60),
          ShiftPiece(id: 'b', rowId: 'lunch', start: 11 * 60, end: 15 * 60),
        ],
      );
      // End pulled from 3p to 1p: only the lunch piece shrinks.
      var p = resizeShiftPieces(shift, atEnd: true, t: 13 * 60);
      expect(p.map((x) => (x.rowId, x.start, x.end)), [
        ('all', _open, 11 * 60),
        ('lunch', 11 * 60, 13 * 60),
      ]);
      // Past 11a: the lunch piece is gone and the first piece shrinks.
      p = resizeShiftPieces(shift, atEnd: true, t: 10 * 60);
      expect(p.map((x) => (x.rowId, x.start, x.end)), [
        ('all', _open, 10 * 60),
      ]);
      // Start pulled later works from the front the same way.
      p = resizeShiftPieces(shift, atEnd: false, t: 12 * 60);
      expect(p.map((x) => (x.rowId, x.start, x.end)), [
        ('lunch', 12 * 60, 15 * 60),
      ]);
      // Growing stretches the last piece.
      p = resizeShiftPieces(shift, atEnd: true, t: 16 * 60);
      expect(p.last.end, 16 * 60);
    },
  );

  test('team view: moving a split shift re-places it as one block', () {
    var day = ScheduleDay(
      date: '2026-10-09',
      rows: [_row('all', _open, _close), _row('lunch', 11 * 60, 15 * 60)],
    );
    day = addPiece(
      day,
      userId: 'alex',
      rowId: 'all',
      start: _open,
      end: 11 * 60,
    );
    day = addPiece(
      day,
      userId: 'alex',
      rowId: 'lunch',
      start: 11 * 60,
      end: 15 * 60,
    );
    expect(shiftBlocks(day.shiftForUser('alex')!), [
      TimeWindow(_open, 15 * 60),
    ]);
    day = setPersonBlock(
      day,
      userId: 'alex',
      old: TimeWindow(_open, 15 * 60),
      w: _h(8, 16),
      users: const {},
    );
    final s = day.shiftForUser('alex')!;
    expect(shiftBlocks(s), [_h(8, 16)]);
    expect(s.pieces, hasLength(1));
  });
}
