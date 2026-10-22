import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/ui/views/schedule/schedule_ops.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-10-08 is a Thursday.
final _date = DateTime(2026, 10, 8);

UserModel _user(String id, [Map<String, dynamic>? availability]) =>
    UserModel(id: id, firstName: id, activeAvailability: availability);

final _day = ScheduleDay(
  date: '2026-10-08',
  rows: [
    ScheduleRow(id: 'r1', windows: [TimeWindow(11 * 60, 17 * 60)]),
    ScheduleRow(id: 'r2', windows: [TimeWindow(18 * 60, 22 * 60)]),
  ],
);

void main() {
  test('filters out time off, scheduled and unavailable people', () {
    final result = availablePeople(
      _day.copyWith(
        shifts: [
          Shift(
            id: 's',
            userId: 'busy',
            pieces: [ShiftPiece(id: 'p', rowId: 'r1', start: 660, end: 720)],
          ),
        ],
      ),
      date: _date,
      people: [
        _user('anytime'),
        _user('busy'),
        _user('off'),
        _user('morning', {
          'thursday': [
            {'start': '06:00', 'end': '10:00'},
          ],
        }),
        _user('evening', {
          'thursday': [
            {'start': '16:00', 'end': '22:30'},
          ],
        }),
        _user('notThursday', {'monday': []}),
      ],
      timeOff: const [
        TimeOffEntry(
          userId: 'off',
          startDate: '2026-10-07',
          endDate: '2026-10-09',
        ),
      ],
    );
    expect(result.people.map((p) => p.user.id), ['anytime', 'evening']);
    expect(result.people.first.canWork, isNull);
    expect(result.people.last.canWork, [
      const TimeWindow(16 * 60, 17 * 60),
      const TimeWindow(18 * 60, 22 * 60),
    ]);
    expect(result.timeOff.map((u) => u.id), ['off']);
    expect(result.unavailable, 2);
  });

  test('workableRange clips to availability and blocks time off', () {
    final evening = _user('e', {
      'thursday': [
        {'start': '16:00', 'end': '22:30'},
      ],
    });
    expect(
      workableRange(
        evening,
        date: _date,
        start: 660,
        end: 1020,
        timeOff: const [],
      ),
      const TimeWindow(16 * 60, 17 * 60),
    );
    expect(
      workableRange(
        evening,
        date: _date,
        start: 660,
        end: 900,
        timeOff: const [],
      ),
      isNull,
    );
    expect(
      availabilityConflict(
        evening,
        date: _date,
        start: 660,
        end: 900,
        timeOff: const [],
      ),
      isNotNull,
    );
    expect(
      availabilityConflict(
        evening,
        date: _date,
        start: 1080,
        end: 1320,
        timeOff: const [],
      ),
      isNull,
    );
  });

  test('part-day time off still shows them, for the hours left', () {
    final result = availablePeople(
      _day,
      date: _date,
      people: [_user('partial')],
      timeOff: const [
        TimeOffEntry(
          userId: 'partial',
          startDate: '2026-10-08',
          endDate: '2026-10-08',
          startMinute: 9 * 60,
          endMinute: 14 * 60,
        ),
      ],
    );
    expect(result.timeOff, isEmpty);
    expect(result.people.single.canWork, [
      const TimeWindow(14 * 60, 17 * 60),
      const TimeWindow(18 * 60, 22 * 60),
    ]);
    expect(
      availabilityConflict(
        result.people.single.user,
        date: _date,
        start: 11 * 60,
        end: 15 * 60,
        timeOff: const [
          TimeOffEntry(
            userId: 'partial',
            startDate: '2026-10-08',
            endDate: '2026-10-08',
            startMinute: 9 * 60,
            endMinute: 14 * 60,
          ),
        ],
      ),
      contains('time off'),
    );
  });
}
