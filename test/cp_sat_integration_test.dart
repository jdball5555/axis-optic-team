import 'dart:convert';
import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/ui/views/schedule/schedule_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test CP-SAT solveRemote against running backend', () async {
    final engine = ScheduleEngine(
      days: [
        ScheduleDay(
          date: '2026-10-12',
          templateId: 't1',
          rows: [
            ScheduleRow(
              id: 'r1',
              label: 'Leader',
              windows: [TimeWindow(480, 960)],
              allowedTitles: ['Leader'],
            ),
            ScheduleRow(
              id: 'r2',
              label: 'Team',
              windows: [TimeWindow(480, 960)],
            ),
          ],
        ),
      ],
      people: [
        UserModel(
          id: 'u1',
          firstName: 'Alice',
          lastName: 'Leader',
          title: 'Leader',
          additionalTags: ['Leader'],
        ),
        UserModel(
          id: 'u2',
          firstName: 'Bob',
          lastName: 'Team',
          title: 'Team Member',
        ),
      ],
      timeOff: const [],
      config: const ScheduleConfig(),
    );

    print('Sending solveRemote...');
    final result = await engine.solveRemote(
      backendUrl: 'http://127.0.0.1:8000',
    );
    print('Result days: ${result.keys.toList()}');
    expect(result.containsKey('2026-10-12'), isTrue);
    final day = result['2026-10-12']!;
    print('Day shifts: ${day.shifts.length}');
    for (final s in day.shifts) {
      print('Shift for ${s.userId}: ${s.start} - ${s.end}');
    }
    expect(day.shifts.length, equals(2));
  });

  test(
    'test CP-SAT gracefully leaves slots open when demand exceeds supply',
    () async {
      final engine = ScheduleEngine(
        days: [
          ScheduleDay(
            date: '2026-10-12',
            templateId: 't1',
            rows: [
              ScheduleRow(
                id: 'r1',
                label: 'Leader',
                windows: [TimeWindow(480, 960)],
                allowedTitles: ['Leader'],
              ),
              ScheduleRow(
                id: 'r2',
                label: 'Team 1',
                windows: [TimeWindow(480, 960)],
              ),
              ScheduleRow(
                id: 'r3',
                label: 'Team 2',
                windows: [TimeWindow(480, 960)],
              ),
            ],
          ),
        ],
        people: [
          UserModel(
            id: 'u1',
            firstName: 'Alice',
            lastName: 'Leader',
            title: 'Leader',
            additionalTags: ['Leader'],
          ),
        ],
        timeOff: const [],
        config: const ScheduleConfig(),
      );

      final result = await engine.solveRemote(
        backendUrl: 'http://127.0.0.1:8000',
      );
      expect(result.containsKey('2026-10-12'), isTrue);
      final day = result['2026-10-12']!;
      expect(day.shifts.length, equals(1));
      expect(day.shifts.first.userId, equals('u1'));
      // Open slots must be 2
      expect(engine.openSlots.length, equals(2));
    },
  );
}
