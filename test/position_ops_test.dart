import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/ui/views/schedule/position_ops.dart';
import 'package:flutter_test/flutter_test.dart';

Shift _shift(String user, int s, int e) => Shift(
  id: user,
  userId: user,
  pieces: [ShiftPiece(id: '$user-p', rowId: 'r', start: s * 60, end: e * 60)],
);

const _register = ShiftPosition(id: 'reg', name: 'Register');
const _drive = ShiftPosition(id: 'dt', name: 'Drive-thru');
const _drive2 = ShiftPosition(id: 'dt2', name: 'Drive-thru 2');
const _fries = ShiftPosition(id: 'fry', name: 'Fries');
const _all = [_register, _drive, _drive2, _fries];

/// Positions at [hour] by user.
Map<String, String?> _at(ScheduleDay d, int hour) => {
  for (final s in d.shifts) s.userId: positionAt(s, hour * 60),
};

void main() {
  test('N people working fill the N highest-priority seats', () {
    final day = ScheduleDay(
      date: '2026-10-09',
      shifts: [
        _shift('a', 6, 14),
        _shift('b', 6, 12),
        _shift('c', 11, 19),
        _shift('d', 11, 15),
        _shift('e', 11, 13),
      ],
    );
    final out = deployPositions(day, _all);
    // 6–11: two people → Register + one Drive-thru seat.
    expect(_at(out, 7).values.whereType<String>().toList()..sort(), [
      'dt',
      'reg',
    ]);
    // 11–12: five people, four seats → all four seats filled, one extra.
    final noon = _at(out, 11).values.whereType<String>().toList()..sort();
    expect(noon, ['dt', 'dt2', 'fry', 'reg']);
    // 15–19: only c → c is on Register.
    expect(_at(out, 16)['c'], 'reg');
  });

  test('people move up when a higher seat opens, and stay put otherwise', () {
    final day = ScheduleDay(
      date: '2026-10-09',
      shifts: [_shift('a', 6, 11), _shift('b', 6, 15)],
    );
    final out = deployPositions(day, _all);
    // b stays longest, so b gets Register from the start and never moves.
    expect(_at(out, 7), {'a': 'dt', 'b': 'reg'});
    expect(out.shiftById('b')!.positions, hasLength(1));
    expect(_at(out, 12), {'a': null, 'b': 'reg'});
  });

  test('a later arrival who stays longer does not bump someone mid-seat', () {
    final day = ScheduleDay(
      date: '2026-10-09',
      shifts: [_shift('a', 6, 12), _shift('b', 9, 18)],
    );
    final out = deployPositions(day, _all);
    expect(_at(out, 10), {'a': 'reg', 'b': 'dt'});
    // a leaves at 12 → b moves up to Register.
    expect(_at(out, 13), {'a': null, 'b': 'reg'});
  });

  test('pinned shifts keep their position', () {
    final day = ScheduleDay(
      date: '2026-10-09',
      shifts: [_shift('a', 6, 14), _shift('t', 6, 14)],
    );
    final out = deployPositions(day, _all, pinned: {'t': 'fry'});
    expect(_at(out, 8), {'a': 'reg', 't': 'fry'});
  });

  test('older multi-spot positions become separate ranked positions', () {
    final config = ShiftConfig.fromJson({
      'positions': [
        {'id': 'fc', 'name': 'Front Counter', 'spots': 2},
        {'id': 'dt', 'name': 'Drive-thru'},
      ],
    });
    expect(config.positions.map((p) => p.name), [
      'Front Counter',
      'Front Counter 2',
      'Drive-thru',
    ]);
    const board = ScheduleBoard(id: 'b', name: 'B', positionIds: ['fc']);
    expect(board.positionsIn(config.positions).map((p) => p.id), [
      'fc',
      'fc#2',
    ]);
  });

  test('assigning a whole shift: one person per position', () {
    var day = ScheduleDay(
      date: '2026-10-09',
      shifts: [_shift('a', 6, 14), _shift('b', 8, 12)],
    );
    day = assignPosition(day, 'a', 'reg');
    expect(fitsPosition(day, day.shiftById('b')!, _register), isFalse);
    expect(fitsPosition(day, day.shiftById('b')!, _drive), isTrue);
  });

  test('training flow steps and pins', () {
    const config = ScheduleConfig(
      trainingFlowEnabled: true,
      trainingDays: [
        TrainingDay(training: true, positionId: 'reg'),
        TrainingDay(training: false, positionId: 'dt'),
      ],
    );
    const shiftConfig = ShiftConfig(positions: [_register, _drive]);
    expect(
      trainingLabel(trainingStepFor(config, 0)!, shiftConfig),
      'Shift 1 · Train on Register',
    );
    expect(
      trainingLabel(trainingStepFor(config, 1)!, shiftConfig),
      'Shift 2 · Drive-thru',
    );
    expect(trainingStepFor(config, 2), isNull);

    final day = ScheduleDay(
      date: '2026-10-09',
      shifts: [_shift('trainer', 6, 14).copyWith(traineeId: 'new')],
    );
    expect(trainingPins(day, {'new': trainingStepFor(config, 0)!}), {
      'trainer': 'reg',
    });
  });

  test('placing someone from an hour keeps what came before', () {
    var day = ScheduleDay(date: '2026-10-09', shifts: [_shift('a', 6, 14)]);
    day = assignPosition(day, 'a', 'reg');
    expect(workingMinuteInHour(day.shiftById('a')!, 11 * 60), 11 * 60);
    expect(workingMinuteInHour(day.shiftById('a')!, 15 * 60), isNull);
    day = assignPositionFrom(day, 'a', 'dt', 11 * 60);
    expect(_at(day, 8)['a'], 'reg');
    expect(_at(day, 12)['a'], 'dt');
    day = assignPositionFrom(day, 'a', null, 13 * 60);
    expect(_at(day, 12)['a'], 'dt');
    expect(_at(day, 13)['a'], isNull);
    // Back on Register from 6 joins into one stretch again.
    day = assignPositionFrom(day, 'a', 'reg', 6 * 60);
    expect(day.shiftById('a')!.positions, hasLength(1));
  });

  test('spots are checked from the hour onward', () {
    var day = ScheduleDay(
      date: '2026-10-09',
      shifts: [_shift('a', 6, 11), _shift('b', 8, 14)],
    );
    day = assignPosition(day, 'a', 'reg');
    // Register (1 spot) is taken until 11 by a.
    expect(
      fitsPositionFrom(day, day.shiftById('b')!, _register, 8 * 60),
      isFalse,
    );
    expect(
      fitsPositionFrom(day, day.shiftById('b')!, _register, 11 * 60),
      isTrue,
    );
  });
}
