import 'dart:convert';

import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/services/sample_data.dart';
import 'package:axis_team/ui/views/schedule/ai_scheduler.dart';
import 'package:axis_team/ui/views/schedule/schedule_engine.dart';
import 'package:axis_team/ui/views/schedule/schedule_ops.dart';
import 'package:flutter_test/flutter_test.dart';

final _weekStart = DateTime(2026, 10, 5); // Monday

UserModel _u(
  String id, {
  String title = 'Team Member',
  String? designation,
  Map<String, dynamic>? availability,
}) => UserModel(
  id: id,
  firstName: id[0].toUpperCase() + id.substring(1),
  lastName: 'Test',
  title: title,
  designation: designation,
  activeAvailability: availability,
);

AiWeekContext _ctx(
  List<UserModel> people, {
  required List<List<ScheduleRow>> rowsByDay,
  ScheduleRules rules = const ScheduleRules(),
  List<String> instructions = const [],
  List<({String uid, int minutes, String? date})> admin = const [],
  Map<String, List<(String, TimeWindow)>> keep = const {},
  List<String> trainerTags = const [],
  List<TimeOffEntry> timeOff = const [],
}) => AiWeekContext(
  weekStart: _weekStart,
  days: [
    for (var i = 0; i < 7; i++)
      ScheduleDay(
        date: dateKey(addDays(_weekStart, i)),
        templateId: i < rowsByDay.length && rowsByDay[i].isNotEmpty
            ? 't'
            : null,
        rows: i < rowsByDay.length ? rowsByDay[i] : const [],
      ),
  ],
  people: people,
  timeOff: timeOff,
  requestedOff: const [],
  config: ScheduleConfig(rules: rules, trainerTags: trainerTags),
  titleOrder: const ['Team Member', 'Leader'],
  instructions: instructions,
  adminRequests: admin,
  keep: keep,
  backendUrl: '', // the local algorithm, whether or not a backend is running
);

Future<(AiBuildResult, List<AiLine>)> _build(
  AiWeekContext ctx, {
  Map<String, dynamic>? directives,
}) async {
  final lines = <AiLine>[];
  final result =
      await AiScheduler(
        generate: (_, system, _, {json = false}) async =>
            system.contains('turn a restaurant manager')
            ? jsonEncode(directives ?? {'directives': []})
            : jsonEncode({'changes': []}),
      ).buildWeek(
        ctx,
        users: {for (final u in ctx.people) u.id!: u},
        log: lines.add,
      );
  return (result, lines);
}

ScheduleRow _row(String id, int s, int e) =>
    ScheduleRow(id: id, windows: [TimeWindow(s * 60, e * 60)]);

void main() {
  group('rules', () {
    test('rest between shifts: no close then open', () async {
      final ctx = _ctx(
        [_u('ivy'), _u('ben')],
        rowsByDay: [
          [_row('close', 14, 23)],
          [_row('open', 5, 13)],
        ],
        rules: const ScheduleRules(
          restOn: true,
          restHours: 10,
          usualShifts: false,
        ),
      );
      final (result, _) = await _build(ctx);
      final closer = result['2026-10-05']!.shifts.single.userId;
      final opener = result['2026-10-06']!.shifts.single.userId;
      expect(opener, isNot(closer));
    });

    test('minors stop by their latest time on school nights', () async {
      final ctx = _ctx(
        [
          _u('kid', designation: 'High School'),
          _u('adult', designation: 'Adult'),
        ],
        rowsByDay: [
          [_row('late', 17, 23)],
        ],
        rules: const ScheduleRules(minorsOn: true, minorLatestEnd: 22 * 60),
      );
      final (result, _) = await _build(ctx);
      expect(result['2026-10-05']!.shifts.single.userId, 'adult');
    });

    test('days in a row', () async {
      final ctx = _ctx(
        [_u('solo')],
        rowsByDay: [
          for (var i = 0; i < 4; i++) [_row('r', 6, 12)],
        ],
        rules: const ScheduleRules(maxDaysInRowOn: true, maxDaysInRow: 3),
      );
      final (result, lines) = await _build(ctx);
      expect(result.values.where((d) => d.shifts.isNotEmpty).length, 3);
      expect(lines.any((l) => l.text.contains('days in a row')), isTrue);
    });

    test('most hours a day splits long bars', () async {
      final ctx = _ctx(
        [_u('ivy'), _u('ben')],
        rowsByDay: [
          [_row('r', 6, 16)], // 10 h
        ],
        rules: const ScheduleRules(maxHoursPerDay: 8),
      );
      final (result, _) = await _build(ctx);
      final day = result['2026-10-05']!;
      expect(day.shifts, hasLength(2));
      expect(day.shifts.every((s) => s.minutes <= 8 * 60), isTrue);
      expect(day.openHours, 0);
    });

    test('rules save and load', () {
      const r = ScheduleRules(
        restOn: true,
        restHours: 11,
        minorsOn: true,
        schoolNights: [1, 2],
        consistency: false,
      );
      final back = ScheduleConfig.fromJson(
        const ScheduleConfig(rules: r).toJson(),
      ).rules;
      expect(back.restOn, isTrue);
      expect(back.restHours, 11);
      expect(back.schoolNights, [1, 2]);
      expect(back.consistency, isFalse);
    });
  });

  group('instructions', () {
    test('names are swapped for ids before they reach the AI', () {
      final ctx = _ctx([_u('lena'), _u('rosa')], rowsByDay: const []);
      final text = ctx.aliasNames('Have Rosa train Lena Test on Tuesday');
      expect(text.contains('Rosa'), isFalse);
      expect(text.contains('Lena'), isFalse);
      expect(text, contains(ctx.aliasOf['rosa']!));
    });

    test('a non-trainer can train someone, a meeting, and time off', () async {
      final people = [
        _u('rosa'),
        _u('lena'),
        _u('sam'),
        _u('omar'),
        _u('ben'),
      ];
      final ctx = _ctx(
        people,
        rowsByDay: [
          [_row('r1', 6, 14), _row('r2', 10, 18)],
          [_row('r1', 6, 14), _row('r2', 10, 18)],
        ],
        trainerTags: const ['Leader'], // nobody is a trainer
        instructions: const [
          'Rosa trains Lena Monday. Meeting with Sam and Omar. Ben off all week.',
        ],
      );
      final a = ctx.aliasOf;
      final (result, lines) = await _build(
        ctx,
        directives: {
          'directives': [
            {
              'type': 'train',
              'people': [a['rosa'], a['lena']],
              'date': '2026-10-05',
            },
            {
              'type': 'meeting',
              'people': [a['sam'], a['omar']],
              'minutes': 60,
            },
            {
              'type': 'off',
              'people': [a['ben']],
            },
          ],
        },
      );
      final mon = result['2026-10-05']!;
      expect(mon.shiftForUser('rosa')?.traineeId, 'lena');
      expect(
        result.values.any((d) => d.shifts.any((s) => s.involves('ben'))),
        isFalse,
      );
      // Sam and Omar overlap for an hour somewhere.
      final together = result.values.any((d) {
        final e = d.shiftForUser('sam');
        final j = d.shiftForUser('omar');
        if (e == null || j == null) return false;
        final from = e.start > j.start ? e.start : j.start;
        final to = e.end < j.end ? e.end : j.end;
        return to - from >= 60;
      });
      expect(together, isTrue);
      expect(lines.any((l) => l.text.contains('Meeting Tue 6')), isTrue);
      expect(lines.any((l) => l.text == 'Your requests:'), isTrue);
      expect(
        lines.any((l) => l.text.contains('Rosa T. trains Lena T.')),
        isTrue,
      );
    });

    test('chat changes keep the rest of the week', () async {
      final people = [_u('ivy'), _u('ben'), _u('cal'), _u('dee')];
      final rows = [_row('r1', 6, 14), _row('r2', 6, 14)];
      // Now: Mon ana+ben, Tue cal+dee. Change: ana is off Monday.
      final ctx = _ctx(
        people,
        rowsByDay: [rows, rows],
        instructions: const ['Ivy can\'t work Monday'],
        keep: {
          'ivy': [('2026-10-05', const TimeWindow(360, 840))],
          'ben': [('2026-10-05', const TimeWindow(360, 840))],
          'cal': [('2026-10-06', const TimeWindow(360, 840))],
          'dee': [('2026-10-06', const TimeWindow(360, 840))],
        },
      );
      final (result, _) = await _build(
        ctx,
        directives: {
          'directives': [
            {
              'type': 'off',
              'people': [ctx.aliasOf['ivy']],
              'date': '2026-10-05',
            },
          ],
        },
      );
      final mon = result['2026-10-05']!.shifts.map((s) => s.userId).toSet();
      final tue = result['2026-10-06']!.shifts.map((s) => s.userId).toSet();
      expect(mon.contains('ivy'), isFalse);
      expect(mon.contains('ben'), isTrue); // kept
      expect(tue, {'cal', 'dee'}); // untouched
    });
  });

  group('admin time', () {
    test(
      'right next to their shift, off the floor, posted on its own',
      () async {
        final ctx = _ctx(
          [_u('sam'), _u('ivy')],
          rowsByDay: [
            [_row('r1', 6, 14), _row('r2', 6, 14)],
          ],
          admin: const [(uid: 'sam', minutes: 60, date: null)],
        );
        final (result, lines) = await _build(ctx);
        final mon = result['2026-10-05']!;
        final eli = mon.shiftForUser('sam')!;
        expect(eli.adminPieces, hasLength(1));
        final a = eli.adminPieces.single;
        // Right after (or before) the shift, never on its own.
        final work = eli.workPieces.single;
        expect(a.start == work.end || a.end == work.start, isTrue);
        // Doesn't count toward the people needed: still 2 working at 7am,
        // and nobody "working" during the admin hour.
        expect(mon.scheduledAt(a.start), 0);
        expect(
          lines.any(
            (l) => l.text.startsWith(
              'Admin for Sam T. (1 h): 1 h admin for Sam T.: Mon 5 2p – 3p',
            ),
          ),
          isTrue,
        );
      },
    );

    test('not possible without a shift next to it: says why', () async {
      final ctx = _ctx(
        [
          _u('ivy'),
          _u('off', availability: {'monday': <dynamic>[]}),
        ],
        rowsByDay: [
          [_row('r1', 6, 14)],
        ],
        admin: const [(uid: 'off', minutes: 60, date: null)],
      );
      final (result, lines) = await _build(ctx);
      expect(result['2026-10-05']!.shiftForUser('off'), isNull);
      expect(
        lines.any(
          (l) =>
              l.kind == AiLineKind.warning &&
              l.text.contains("aren't on the schedule"),
        ),
        isTrue,
      );
    });

    test('admin from a typed request, and a request it can\'t read', () async {
      final ctx = _ctx(
        [_u('jordan'), _u('ivy')],
        rowsByDay: [
          [_row('r1', 6, 14), _row('r2', 6, 14)],
        ],
        instructions: const [
          'Jordan needs an hour of admin',
          'Make it nicer for Ivy',
        ],
      );
      final (result, lines) = await _build(
        ctx,
        directives: {
          'directives': [
            {
              'type': 'admin',
              'people': [ctx.aliasOf['jordan']],
              'minutes': 60,
              'request': 1,
            },
          ],
        },
      );
      expect(result['2026-10-05']!.shiftForUser('jordan')!.hasAdmin, isTrue);
      expect(
        lines.any(
          (l) =>
              l.kind == AiLineKind.success && l.text.startsWith('"Jordan needs'),
        ),
        isTrue,
      );
      expect(
        lines.any(
          (l) =>
              l.text.startsWith('"Make it nicer for Ivy": didn\'t understand'),
        ),
        isTrue,
      );
    });

    test(
      'somebody who does truck selects only 1 person even if AI returns both truck workers',
      () async {
        final truck1 = UserModel(
          id: 'carlos',
          firstName: 'Carlos',
          lastName: 'Trucker',
          title: 'Team Member',
          additionalTags: const ['Truck'],
        );
        final truck2 = UserModel(
          id: 'bob',
          firstName: 'Bob',
          lastName: 'Unloader',
          title: 'Team Member',
          additionalTags: const ['Truck'],
        );
        final ctx = _ctx(
          [truck1, truck2],
          rowsByDay: [
            [_row('r1', 6, 14), _row('r2', 6, 14)],
            [_row('r1', 6, 14), _row('r2', 6, 14)],
            [_row('r1', 6, 14), _row('r2', 6, 14)],
          ],
          instructions: const [
            'somebody who does truck to be scheduled an hour and thirty minutes each day',
          ],
        );
        // AI erroneously returns both truck workers in people
        final (result, lines) = await _build(
          ctx,
          directives: {
            'directives': [
              {
                'type': 'admin',
                'people': [ctx.aliasOf['carlos'], ctx.aliasOf['bob']],
                'minutes':
                    60, // AI thought 60, but instruction said hour and thirty minutes
                'every_day': true,
                'request': 1,
              },
            ],
          },
        );

        // Only Carlos (the primary truck person) gets admin, NOT both!
        final carlosAdminDays = result.values
            .where((d) => d.shiftForUser('carlos')?.hasAdmin ?? false)
            .length;
        final bobAdminDays = result.values
            .where((d) => d.shiftForUser('bob')?.hasAdmin ?? false)
            .length;
        expect(carlosAdminDays, 3);
        expect(bobAdminDays, 0); // Bob does NOT get truck admin!
        for (final d in result.values.take(3)) {
          final shift = d.shiftForUser('carlos')!;
          final adminMins = shift.adminPieces.fold<int>(
            0,
            (sum, p) => sum + (p.end - p.start),
          );
          expect(adminMins, 90); // 90 min parsed from "hour and thirty minutes"
        }
      },
    );

    test(
      'two truck workers: when primary has availability off on a day, secondary is scheduled and given admin',
      () async {
        final truck1 = UserModel(
          id: 'carlos',
          firstName: 'Carlos',
          lastName: 'Trucker',
          title: 'Team Member',
          additionalTags: const ['Truck'],
        );
        final truck2 = UserModel(
          id: 'bob',
          firstName: 'Bob',
          lastName: 'Unloader',
          title: 'Team Member',
          additionalTags: const ['Truck'],
        );
        // Carlos has day 2 (2026-10-06) off via time-off
        final timeOff = [
          TimeOffEntry(
            userId: 'carlos',
            startDate: '2026-10-06',
            endDate: '2026-10-06',
            reason: 'Unavailable',
          ),
        ];
        final ctx = _ctx(
          [truck1, truck2],
          rowsByDay: [
            [_row('r1', 6, 14)], // 2026-10-05
            [_row('r1', 6, 14)], // 2026-10-06: Carlos is off, Bob must work!
            [_row('r1', 6, 14)], // 2026-10-07
          ],
          timeOff: timeOff,
          instructions: const [
            '1 hour and a half of admin each day for someone with the truck tag',
          ],
        );
        final (result, lines) = await _build(
          ctx,
          directives: {
            'directives': [
              {
                'type': 'admin',
                'people': [ctx.aliasOf['carlos'], ctx.aliasOf['bob']],
                'minutes': 90,
                'every_day': true,
                'request': 1,
              },
            ],
          },
        );

        // On day 1 and 3: Carlos works and has admin
        expect(result['2026-10-05']!.shiftForUser('carlos')?.hasAdmin, isTrue);
        expect(result['2026-10-07']!.shiftForUser('carlos')?.hasAdmin, isTrue);
        // On day 2 (Carlos off): Bob works and has admin!
        expect(result['2026-10-06']!.shiftForUser('bob')?.hasAdmin, isTrue);
        expect(result['2026-10-06']!.shiftForUser('carlos'), isNull);
      },
    );

    test(
      'leadership meeting scheduled as admin time with all leaders for 1 hour attached during shifts',
      () async {
        final lead1 = UserModel(
          id: 'lead1',
          firstName: 'Sam',
          lastName: 'Lead',
          title: 'Shift Leader',
        );
        final lead2 = UserModel(
          id: 'lead2',
          firstName: 'Dana',
          lastName: 'Director',
          title: 'Director',
        );
        final lead3 = UserModel(
          id: 'lead3',
          firstName: 'Maya',
          lastName: 'Manager',
          title: 'Manager',
        );
        final tm = _u('joe');

        final ctx = _ctx(
          [lead1, lead2, lead3, tm],
          rowsByDay: [
            // Shifts run 8:00 to 16:00
            [_row('r1', 8, 16), _row('r2', 8, 16), _row('r3', 8, 16)],
            [_row('r1', 8, 16), _row('r2', 8, 16), _row('r3', 8, 16)],
          ],
          instructions: const [
            'try to have a leadership meeting that\'s scheduled as admin time with all the leaders for 1 hour sometime during the week',
          ],
        );

        final (result, lines) = await _build(
          ctx,
          directives: {
            'directives': [
              {
                'type': 'meeting',
                'people': [
                  ctx.aliasOf['lead1'],
                  ctx.aliasOf['lead2'],
                  ctx.aliasOf['lead3'],
                ],
                'minutes': 60,
                'as_admin': true,
                'request': 1,
              },
            ],
          },
        );

        // Find the day where all 3 leaders have admin meeting together
        var foundMeetingDay = false;
        for (final day in result.values) {
          final s1 = day.shiftForUser('lead1');
          final s2 = day.shiftForUser('lead2');
          final s3 = day.shiftForUser('lead3');
          if (s1 != null &&
              s2 != null &&
              s3 != null &&
              s1.adminPieces.isNotEmpty &&
              s2.adminPieces.isNotEmpty &&
              s3.adminPieces.isNotEmpty) {
            final a1 = s1.adminPieces.first;
            final a2 = s2.adminPieces.first;
            final a3 = s3.adminPieces.first;
            if (a1.start == a2.start && a2.start == a3.start) {
              foundMeetingDay = true;
              // Meeting MUST be during daylight hours (e.g. >= 9:00 AM), NOT early 6:00 AM!
              expect(a1.start, greaterThanOrEqualTo(9 * 60));
              // Floor pieces should be carved cleanly around the admin piece without overlapping
              for (final shift in [s1, s2, s3]) {
                // Ensure no piece overlaps with another piece in the same shift
                for (var i = 0; i < shift.pieces.length - 1; i++) {
                  expect(
                    shift.pieces[i].end,
                    lessThanOrEqualTo(shift.pieces[i + 1].start),
                  );
                }
              }
              break;
            }
          }
        }
        expect(foundMeetingDay, isTrue);
        expect(
          lines.any(
            (l) =>
                l.text.contains('Leadership meeting') &&
                l.text.contains('admin time'),
          ),
          isTrue,
        );
      },
    );

    test(
      'hard rule notification is distinctly emitted when open slots remain',
      () async {
        // 1 person available, but 2 slots needed
        final ctx = _ctx(
          [_u('solo')],
          rowsByDay: [
            [_row('r1', 8, 14), _row('r2', 8, 14)],
          ],
        );
        final (_, lines) = await _build(ctx);
        expect(
          lines.any(
            (l) =>
                l.kind == AiLineKind.error &&
                l.text.contains(
                  'Hard rule notification: schedule not fully covered',
                ),
          ),
          isTrue,
        );
        expect(lines.any((l) => l.text.contains('Hard rule:')), isTrue);
      },
    );

    test(
      'training flow is a hard rule: trainer-paired training shifts cannot be altered by AI review',
      () {
        final engine = ScheduleEngine(
          days: [
            ScheduleDay(
              date: '2026-10-05',
              templateId: 't',
              rows: [_row('r1', 8, 16)],
            ),
          ],
          people: [
            _u('trainer', title: 'Leader'),
            _u('trainee'),
            _u('other'),
          ],
          timeOff: const [],
          rules: const ScheduleRules(),
          config: const ScheduleConfig(trainingFlowEnabled: true),
          trainingPlans: {
            'trainee': [(withTrainer: true, positionId: null)],
          },
        );
        final placed = engine.placeTraining();
        expect(placed, equals(1));
        final slotId = engine.slots.first.id;
        expect(engine.isTrainingSlot(slotId), isTrue);
        expect(engine.traineeOn(slotId), equals('trainee'));
        expect(engine.whoOn(slotId), equals('trainer'));

        // AI review or repair attempting to change this slot must be skipped because training flow is a hard rule
        final res = engine.applyChanges([(slotId, 'other')]);
        expect(res.applied, equals(0));
        expect(res.skipped.first.why, contains('training flow is a hard rule'));
        expect(engine.whoOn(slotId), equals('trainer'));
      },
    );

    test(
      'training flow is a hard rule: solo training shifts are locked and protected from change',
      () {
        final engine = ScheduleEngine(
          days: [
            ScheduleDay(
              date: '2026-10-05',
              templateId: 't',
              rows: [_row('r1', 8, 16)],
            ),
          ],
          people: [_u('trainee'), _u('other')],
          timeOff: const [],
          rules: const ScheduleRules(),
          config: const ScheduleConfig(trainingFlowEnabled: true),
          trainingPlans: {
            'trainee': [(withTrainer: false, positionId: null)],
          },
        );
        final placed = engine.placeTraining();
        expect(placed, equals(1));
        final slotId = engine.slots.first.id;
        expect(engine.isTrainingSlot(slotId), isTrue);
        expect(engine.whoOn(slotId), equals('trainee'));

        // AI review or repair attempting to change this slot must be rejected
        final res = engine.applyChanges([(slotId, 'other')]);
        expect(res.applied, equals(0));
        expect(res.skipped.first.why, contains('training flow is a hard rule'));
        expect(engine.whoOn(slotId), equals('trainee'));
      },
    );
  });

  group('admin is always joined onto a shift', () {
    /// Every shift is one continuous stretch of floor + admin, never admin alone.
    void expectJoined(AiBuildResult result) {
      for (final d in result.values) {
        for (final s in d.shifts) {
          expect(
            s.workPieces,
            isNotEmpty,
            reason: '${d.date} ${s.userId}: admin with no shift',
          );
          expect(
            shiftBlocks(s),
            hasLength(1),
            reason: '${d.date} ${s.userId}: admin with a gap',
          );
        }
      }
    }

    test('staying later beats taking time off the floor', () async {
      final ctx = _ctx(
        [_u('sam'), _u('ivy')],
        rowsByDay: [
          [_row('r1', 8, 16), _row('r2', 8, 16)],
        ],
        admin: const [(uid: 'sam', minutes: 60, date: null)],
      );
      final (result, _) = await _build(ctx);
      final mon = result['2026-10-05']!;
      expect(mon.openHours, 0); // the floor stays covered
      final a = mon.shiftForUser('sam')!.adminPieces.single;
      expect(a.start >= 16 * 60 || a.end <= 8 * 60, isTrue);
      expectJoined(result);
    });

    test(
      'admin on a day they weren\'t going to work gets them a shift that day',
      () async {
        final ctx = _ctx(
          [_u('ivy'), _u('ben'), _u('sam')],
          rowsByDay: [
            [_row('r1', 8, 16), _row('r2', 8, 16)],
            [_row('r1', 8, 16), _row('r2', 8, 16)],
          ],
          rules: const ScheduleRules(maxShiftsPerWeek: 1),
          admin: const [(uid: 'sam', minutes: 60, date: '2026-10-06')],
        );
        final (result, _) = await _build(ctx);
        final tue = result['2026-10-06']!.shiftForUser('sam');
        expect(tue, isNotNull);
        expect(tue!.adminPieces, hasLength(1));
        expectJoined(result);
      },
    );

    test(
      'a manager meeting on the sample week: everyone joined onto a shift, floor still covered',
      () async {
        final seeder = SampleSeeder('pgb', today: DateTime(2026, 10, 10));
        final everyone = [
          for (final e in seeder.memberDocs().entries)
            UserModel.fromJson({...e.value, 'id': e.key}),
        ];
        for (final board in [kMainBoardId, kitchenBoardId]) {
          final areas = board == kMainBoardId ? ['DT', 'SVC'] : ['KT', 'DIR'];
          final people = everyone
              .where((u) => areas.contains(u.position))
              .toList();
          final ctx = AiWeekContext(
            weekStart: _weekStart,
            days: [
              for (var i = 0; i < 7; i++)
                ScheduleDay(
                  date: dateKey(addDays(_weekStart, i)),
                  templateId: i < 6 ? 't' : null,
                  rows: i < 6 ? seeder.buildDay(i, board).rows : const [],
                ),
            ],
            people: people,
            timeOff: const [],
            requestedOff: const [],
            config: const ScheduleConfig(trainerTags: ['Trainer', 'Leader']),
            titleOrder: const ['In Training', 'Team Member', 'Leader'],
            instructions: const [
              'manager meeting for an hour',
              'truck person gets 90 min admin every day',
            ],
            backendUrl: '',
          );
          final truck = people.firstWhere(
            (u) => (u.additionalTags ?? const []).contains('Truck'),
            orElse: () => people.first,
          );
          // The AI only names the request; the app finds the managers.
          final (result, lines) = await _build(
            ctx,
            directives: {
              'directives': [
                {'type': 'note', 'text': 'manager meeting', 'request': 1},
                {
                  'type': 'admin',
                  'people': [ctx.aliasOf[truck.id]],
                  'minutes': 90,
                  'every_day': true,
                  'request': 2,
                },
              ],
            },
          );
          expectJoined(result);
          final leaders = people.where(ctx.isLeader).map((u) => u.id).toSet();
          final meeting = <String, int>{}; // date + time → leaders there
          for (final d in result.values) {
            for (final s in d.shifts.where((s) => leaders.contains(s.userId))) {
              for (final a in s.adminPieces) {
                meeting['${d.date} ${a.start}'] =
                    (meeting['${d.date} ${a.start}'] ?? 0) + 1;
              }
            }
          }
          final most = meeting.values.fold(0, (a, b) => a > b ? a : b);
          expect(most, greaterThanOrEqualTo(4), reason: '$board: $meeting');
          final needed = result.values.fold<double>(
            0,
            (a, d) => a + d.neededHours,
          );
          final open = result.values.fold<double>(0, (a, d) => a + d.openHours);
          expect(
            open / needed,
            lessThan(0.015),
            reason: '$board: $open of $needed h open',
          );
          expect(lines.any((l) => l.text.contains('Meeting (admin)')), isTrue);
        }
      },
    );
  });
}
