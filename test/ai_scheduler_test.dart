import 'dart:convert';

import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/services/sample_data.dart';
import 'package:axis_team/ui/views/schedule/ai_scheduler.dart';
import 'package:axis_team/ui/views/schedule/position_ops.dart';
import 'package:axis_team/ui/views/schedule/schedule_common.dart';
import 'package:axis_team/ui/views/schedule/schedule_ops.dart';
import 'package:flutter_test/flutter_test.dart';

// Week of Mon 2026-10-05.
final _weekStart = DateTime(2026, 10, 5);

UserModel _u(
  String id, {
  String title = 'Team Member',
  Map<String, dynamic>? availability,
  String? avg,
  List<String> tags = const [],
}) => UserModel(
  id: id,
  firstName: id,
  title: title,
  activeAvailability: availability,
  avgShifts: avg,
  additionalTags: tags,
);

const _twoMorning = [
  ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
  ScheduleRow(id: 'r2', windows: [TimeWindow(360, 840)]),
];

/// A week where [rows] are needed on the first [days] days.
AiWeekContext _ctx(
  List<UserModel> people, {
  List<ScheduleRow> rows = _twoMorning,
  int days = 1,
  Map<String, List<int>> training = const {},
  List<String> trainerTags = const [],
  List<TimeOffEntry> timeOff = const [],
  Map<String, Map<String, List<TimeWindow>>> busy = const {},
}) => AiWeekContext(
  weekStart: _weekStart,
  days: [
    for (var i = 0; i < 7; i++)
      ScheduleDay(
        date: dateKey(addDays(_weekStart, i)),
        templateId: i < days ? 't' : null,
        rows: i < days ? rows : const [],
      ),
  ],
  people: people,
  timeOff: timeOff,
  requestedOff: const [],
  config: ScheduleConfig(
    trainingFlowEnabled: true,
    trainingDays: const [TrainingDay(training: true, positionId: 'fry')],
    trainerTags: trainerTags,
  ),
  positions: const [
    ShiftPosition(id: 'reg', name: 'Register'),
    ShiftPosition(id: 'fry', name: 'Fries'),
  ],
  titleOrder: const ['Team Member', 'Leader'],
  trainingRemaining: training,
  busyElsewhere: busy,
  backendUrl: '', // the local algorithm, whether or not a backend is running
);

/// A model that never changes anything.
Future<String> _noChanges(
  String _,
  String _,
  String _, {
  bool json = false,
}) async => jsonEncode({'changes': []});

Future<(AiBuildResult, List<AiLine>)> _build(
  AiWeekContext ctx, {
  AiGenerate generate = _noChanges,
}) async {
  final lines = <AiLine>[];
  final users = {for (final u in ctx.people) u.id!: u};
  final result = await AiScheduler(
    generate: generate,
  ).buildWeek(ctx, users: users, log: lines.add);
  return (result, lines);
}

/// Never more people working than the template needs.
void _expectNotOverstaffed(ScheduleDay d) {
  for (var t = 0; t < kMaxScheduleMinute; t += kScheduleStep) {
    expect(
      d.scheduledAt(t) <= d.neededAt(t),
      isTrue,
      reason:
          '${d.date} ${formatMinutes(t)}: ${d.scheduledAt(t)} working, ${d.neededAt(t)} needed',
    );
  }
}

void main() {
  setUp(() => AiScheduler.lastWorkingModel = null);

  test('people are sent to the AI as ids, never names', () {
    final ctx = _ctx([_u('alex'), _u('bree')]);
    final e = ctx.engine()..fill(short: false);
    final json = jsonEncode(ctx.reviewJson(e));
    expect(json.contains('alex'), isFalse);
    expect(json.contains('"P1"'), isTrue);
    expect(ctx.unalias('P2 is short'), 'bree is short');
  });

  test('exactly the template: 3 free people, 2 slots → 2 shifts', () async {
    final (result, lines) = await _build(_ctx([_u('a'), _u('b'), _u('c')]));
    final monday = result['2026-10-05']!;
    expect(monday.shifts, hasLength(2));
    expect(monday.rows, hasLength(2)); // no rows added
    expect(monday.openHours, 0);
    _expectNotOverstaffed(monday);
    expect(lines.any((l) => l.text == 'Every needed hour is covered.'), isTrue);
  });

  test('a long bar is split where people are free on both sides', () async {
    final morning = _u(
      'am',
      availability: {
        'monday': [
          {'start': '05:00', 'end': '15:00'},
        ],
      },
    );
    final evening = _u(
      'pm',
      availability: {
        'monday': [
          {'start': '14:00', 'end': '23:00'},
        ],
      },
    );
    final ctx = _ctx(
      [morning, evening],
      rows: const [
        ScheduleRow(id: 'r1', windows: [TimeWindow(360, 1365)]),
      ],
    );
    final (result, _) = await _build(ctx);
    final monday = result['2026-10-05']!;
    expect(monday.shifts.map((s) => s.userId).toSet(), {'am', 'pm'});
    expect(monday.openHours, 0);
    final am = monday.shiftForUser('am')!;
    expect(am.start, 360);
    expect(am.end, inInclusiveRange(14 * 60, 15 * 60));
    _expectNotOverstaffed(monday);
  });

  test('a short bar joins onto the shift next to it', () async {
    final ctx = _ctx(
      [_u('a'), _u('b')],
      rows: const [
        ScheduleRow(
          id: 'truck',
          label: 'Truck',
          windows: [TimeWindow(315, 360)],
        ),
        ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
      ],
    );
    final (result, _) = await _build(ctx);
    final monday = result['2026-10-05']!;
    expect(monday.shifts, hasLength(1));
    final s = monday.shifts.single;
    expect(s.pieces.map((p) => p.rowId).toSet(), {'truck', 'r1'});
    expect((s.start, s.end), (315, 840));
  });

  test('title bars get people with that title; others take the rest', () async {
    final ctx = _ctx(
      [_u('tm'), _u('lead', title: 'Leader')],
      rows: const [
        ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
        ScheduleRow(
          id: 'lead',
          windows: [TimeWindow(360, 840)],
          allowedTitles: ['Leader'],
        ),
      ],
    );
    final (result, _) = await _build(ctx);
    final monday = result['2026-10-05']!;
    expect(monday.shiftForUser('lead')!.pieces.single.rowId, 'lead');
    expect(monday.shiftForUser('tm')!.pieces.single.rowId, 'r1');
  });

  test('nobody works more than 5 shifts a week by default', () async {
    const row = [
      ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
    ];
    final (result, lines) = await _build(
      _ctx([_u('u', avg: '3-4')], rows: row, days: 6),
    );
    expect(result.values.where((d) => d.shifts.isNotEmpty).length, 5);
    expect(
      lines.any(
        (l) => l.text.startsWith('Sat 10') && l.text.contains('most shifts'),
      ),
      isTrue,
    );
  });

  test('more than 5 only when their avg shifts says so', () async {
    const row = [
      ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
    ];
    final (result, _) = await _build(
      _ctx([_u('u', avg: '6')], rows: row, days: 6),
    );
    expect(result.values.where((d) => d.shifts.isNotEmpty).length, 6);
  });

  test('people below their usual shifts are picked first', () async {
    const row = [
      ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
    ];
    final (result, _) = await _build(
      _ctx(
        [_u('full', avg: '1'), _u('wants', avg: '5')],
        rows: row,
        days: 4,
      ),
    );
    final days = result.values.where((d) => d.shifts.isNotEmpty);
    expect(days.where((d) => d.shifts.single.userId == 'wants').length, 4);
    expect(days.where((d) => d.shifts.single.userId == 'full'), isEmpty);
  });

  test('avg shifts is read as an estimate', () {
    UserModel u(String v) => UserModel(id: 'x', avgShifts: v);
    expect(avgShiftsEstimate(u('4')), 4);
    expect(avgShiftsEstimate(u('3-4')), 3.5);
    expect(avgShiftsEstimate(u('')), isNull);
    expect(maxShiftsPerWeek(u('3')), 5);
    expect(maxShiftsPerWeek(u('5-6')), 6);
    expect(maxShiftsPerWeek(u('9')), 7);
  });

  test('new hires shadow a trainer and the trainer is pinned', () async {
    final people = [_u('lead', title: 'Leader'), _u('alex'), _u('new')];
    final ctx = _ctx(
      people,
      training: {
        'new': [0],
      },
      trainerTags: ['Leader'],
    );
    final (result, lines) = await _build(ctx);
    final monday = result['2026-10-05']!;
    expect(monday.shiftForUser('lead')!.traineeId, 'new');
    expect(monday.shiftForUser('alex')!.traineeId, isNull);
    expect(monday.shifts.any((s) => s.userId == 'new'), isFalse);
    // Training flow day 1 is "train on Fries".
    expect(positionAt(monday.shiftForUser('lead')!, 7 * 60), 'fry');
    expect(
      lines.any((l) => l.text.contains('1 training shift for 1 person')),
      isTrue,
    );
  });

  test('several training shifts in one week: trainer, solo, trainer', () async {
    final people = [
      _u('lead', title: 'Leader'),
      _u('lead2', title: 'Leader'),
      _u('alex'),
      _u('new'),
    ];
    const row = [
      ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
      ScheduleRow(id: 'r2', windows: [TimeWindow(360, 840)]),
    ];
    final ctx = AiWeekContext(
      weekStart: _weekStart,
      days: [
        for (var i = 0; i < 7; i++)
          ScheduleDay(
            date: dateKey(addDays(_weekStart, i)),
            templateId: i < 5 ? 't' : null,
            rows: i < 5 ? row : const [],
          ),
      ],
      people: people,
      timeOff: const [],
      requestedOff: const [],
      config: const ScheduleConfig(
        trainingFlowEnabled: true,
        trainingDays: [
          TrainingDay(training: true, positionId: 'reg'),
          TrainingDay(training: false, positionId: 'reg'),
          TrainingDay(training: true, positionId: 'fry'),
        ],
        trainerTags: ['Leader'],
      ),
      positions: const [
        ShiftPosition(id: 'reg', name: 'Register'),
        ShiftPosition(id: 'fry', name: 'Fries'),
      ],
      titleOrder: const ['Team Member', 'Leader'],
      trainingRemaining: {
        'new': [0, 1, 2],
      },
    );
    final (result, lines) = await _build(ctx);
    final days = (result.keys.toList()..sort()).map((d) => result[d]!).toList();
    // Mon: with a trainer; Tue: on their own; Wed: with a trainer again.
    expect(days[0].shifts.where((s) => s.traineeId == 'new'), hasLength(1));
    final tue = days[1].shiftForUser('new');
    expect(tue, isNotNull);
    expect(tue!.traineeId, isNull);
    expect(positionAt(tue, 7 * 60), 'reg');
    final wed = days[2].shifts.where((s) => s.traineeId == 'new').single;
    expect(positionAt(wed, 7 * 60), 'fry');
    // Nothing else for them this week.
    expect(
      days.skip(3).every((d) => !d.shifts.any((s) => s.involves('new'))),
      isTrue,
    );
    expect(lines.any((l) => l.text.contains('3 training shifts')), isTrue);
    for (final d in days) {
      _expectNotOverstaffed(d);
    }
  });

  test(
    'two trainees training on the same position go on different days',
    () async {
      final people = [
        _u('lead', title: 'Leader'),
        _u('lead2', title: 'Leader'),
        _u('new1'),
        _u('new2'),
      ];
      final ctx = _ctx(
        people,
        days: 2,
        training: {
          'new1': [0],
          'new2': [0],
        },
        trainerTags: ['Leader'],
      );
      final (result, lines) = await _build(ctx);
      Set<String> traineesOn(String date) => {
        for (final s in result[date]!.shifts) ?s.traineeId,
      };
      // Training flow step 1 is "train on Fries" for both: one a day.
      expect(traineesOn('2026-10-05'), hasLength(1));
      expect(traineesOn('2026-10-06'), hasLength(1));
      expect(
        {...traineesOn('2026-10-05'), ...traineesOn('2026-10-06')},
        {'new1', 'new2'},
      );
    },
  );

  test('people keep the shifts they usually work (last few weeks)', () async {
    const row = [
      ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
    ];
    final base = _ctx(
      [_u('ivy', avg: '1'), _u('ben', avg: '1')],
      rows: row,
      days: 2,
    );
    // Ben always works Mondays 6–2; Ivy always works Tuesdays.
    final ctx = AiWeekContext(
      weekStart: base.weekStart,
      days: base.days,
      people: base.people,
      timeOff: const [],
      requestedOff: const [],
      config: const ScheduleConfig(),
      titleOrder: base.titleOrder,
      history: {
        'ben': [
          for (var i = 0; i < 4; i++)
            (DateTime.monday, const TimeWindow(360, 840)),
        ],
        'ivy': [
          for (var i = 0; i < 4; i++)
            (DateTime.tuesday, const TimeWindow(360, 840)),
        ],
      },
    );
    final (result, lines) = await _build(ctx);
    expect(result['2026-10-05']!.shifts.single.userId, 'ben');
    expect(result['2026-10-06']!.shifts.single.userId, 'ivy');
    // The AI sees who usually works each slot.
    final e = ctx.engine()..fill(short: false);
    final slots = ctx.reviewJson(e)['slots'] as List;
    expect(slots.first['usually'], [ctx.aliasOf['ben']]);
  });

  test(
    'time off (approved or requested) and other schedules block people',
    () async {
      final ctx = _ctx(
        [_u('off'), _u('busy'), _u('free'), _u('free2')],
        timeOff: const [
          TimeOffEntry(
            userId: 'off',
            startDate: '2026-10-05',
            endDate: '2026-10-05',
          ),
        ],
        busy: {
          'busy': {
            '2026-10-05': [TimeWindow(600, 900)],
          },
        },
      );
      final (result, _) = await _build(ctx);
      expect(result['2026-10-05']!.shifts.map((s) => s.userId).toSet(), {
        'free',
        'free2',
      });
    },
  );

  test('times no one can work are reported with the reason', () async {
    final eve = _u(
      'eve',
      availability: {
        'monday': [
          {'start': '10:00', 'end': '22:00'},
        ],
      },
    );
    final (result, lines) = await _build(
      _ctx(
        [eve],
        rows: const [
          ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
        ],
      ),
    );
    // Eve covers 10a–2p; 6–10 AM stays open.
    expect(result['2026-10-05']!.shiftForUser('eve')!.start, 600);
    expect(
      lines.any(
        (l) =>
            l.text.startsWith('Mon 5') &&
            l.text.contains('6a – 10a') &&
            l.text.contains('no one is available'),
      ),
      isTrue,
    );
  });

  group('AI review', () {
    test('valid swaps are applied, invalid ones skipped', () async {
      // Two days, one slot each. The AI moves Tuesday from a to b, and also
      // tries to give Monday to someone who isn't available.
      final b = _u('b', avg: '1');
      final late = _u(
        'late',
        availability: {
          'monday': [
            {'start': '15:00', 'end': '22:00'},
          ],
        },
      );
      const row = [
        ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
      ];
      final ctx = _ctx([_u('a', avg: '5'), b, late], rows: row, days: 2);
      String? prompt;
      final (result, lines) = await _build(
        ctx,
        generate: (_, _, p, {json = false}) async {
          prompt = p;
          final slots = (jsonDecode(p)['slots'] as List).cast<Map>();
          final tue = slots.firstWhere((s) => s['date'] == '2026-10-06')['id'];
          final mon = slots.firstWhere((s) => s['date'] == '2026-10-05')['id'];
          final aliases = {for (final u in ctx.people) u.id: ctx.aliasOf[u.id]};
          return jsonEncode({
            'changes': [
              {'slot': tue, 'person': aliases['b']},
              {'slot': mon, 'person': aliases['late']},
            ],
            'notes': '${aliases['b']} wanted a shift.',
          });
        },
      );
      expect(prompt, isNotNull);
      expect(result['2026-10-06']!.shifts.single.userId, 'b');
      expect(result['2026-10-05']!.shifts.single.userId, isNot('late'));
      expect(
        lines.any((l) => l.text.startsWith('1 change applied (1 broke a rule')),
        isTrue,
      );
      expect(
        lines.any(
          (l) => l.kind == AiLineKind.ai && l.text.contains('b wanted'),
        ),
        isTrue,
      );
    });

    test('falls back to the next model when one fails', () async {
      final asked = <String>[];
      final lines = <AiLine>[];
      final ctx = _ctx([_u('alex'), _u('bree')]);
      await AiScheduler(
        models: const ['m1', 'm2'],
        generate: (model, _, _, {json = false}) async {
          asked.add(model);
          if (model == 'm1')
            throw const GeminiException('Model not found.', status: 404);
          return jsonEncode({'changes': []});
        },
      ).buildWeek(
        ctx,
        users: {for (final u in ctx.people) u.id!: u},
        log: lines.add,
      );
      expect(asked, ['m1', 'm2']);
      expect(AiScheduler.lastWorkingModel, 'm2');
      expect(
        lines.any((l) => l.text.contains('Trying the next model')),
        isTrue,
      );
    });

    test(
      'a bad key stops right away and keeps the algorithm\'s schedule',
      () async {
        final asked = <String>[];
        final (result, lines) = await _build(
          _ctx([_u('alex'), _u('bree')]),
          generate: (model, _, _, {json = false}) async {
            asked.add(model);
            throw const GeminiException('API key not valid.', status: 400);
          },
        );
        expect(asked, hasLength(1));
        expect(result['2026-10-05']!.openHours, 0);
        expect(lines.any((l) => l.text.contains('Kept the algorithm')), isTrue);
      },
    );
  });

  test('the sample week: matches the template, never overstaffed', () async {
    final seeder = SampleSeeder('pgb', today: DateTime(2026, 10, 10));
    final docs = seeder.memberDocs();
    final everyone = [
      for (final e in docs.entries)
        UserModel.fromJson({...e.value, 'id': e.key}),
    ];
    for (final board in [kMainBoardId, kitchenBoardId]) {
      final areas = board == kMainBoardId ? ['DT', 'SVC'] : ['KT', 'DIR'];
      final people = everyone.where((u) => areas.contains(u.position)).toList();
      final days = [
        for (var i = 0; i < 7; i++)
          i < 6
              ? seeder
                    .buildDay(i, board)
                    .copyWith(templateId: 't', shifts: const [])
              : ScheduleDay(date: dateKey(addDays(_weekStart, i))),
      ];
      final ctx = AiWeekContext(
        weekStart: _weekStart,
        days: [
          for (var i = 0; i < 7; i++)
            ScheduleDay(
              date: dateKey(addDays(_weekStart, i)),
              templateId: days[i].templateId,
              rows: days[i].rows,
            ),
        ],
        people: people,
        timeOff: const [],
        requestedOff: const [],
        config: const ScheduleConfig(trainerTags: ['Trainer', 'Leader']),
        titleOrder: const ['In Training', 'Team Member', 'Leader'],
      );
      final (result, lines) = await _build(ctx);
      var needed = 0.0, open = 0.0;
      final perPerson = <String, int>{};
      for (final d in result.values) {
        _expectNotOverstaffed(d);
        needed += d.neededHours;
        open += d.openHours;
        final date = DateTime.parse(d.date);
        for (final s in d.shifts) {
          perPerson[s.userId] = (perPerson[s.userId] ?? 0) + 1;
          final u = everyone.firstWhere((u) => u.id == s.userId);
          for (final b in shiftBlocks(s)) {
            expect(
              availabilityConflict(
                u,
                date: date,
                start: b.start,
                end: b.end,
                timeOff: const [],
              ),
              isNull,
            );
            expect(b.minutes, lessThanOrEqualTo(11 * 60));
          }
          for (final p in s.pieces) {
            expect(userFitsRow(u, d.rowById(p.rowId)!), isTrue);
          }
        }
      }
      for (final e in perPerson.entries) {
        final u = everyone.firstWhere((u) => u.id == e.key);
        expect(e.value, lessThanOrEqualTo(maxShiftsPerWeek(u)));
      }
      // The real week was staffed by these people, so nearly all of it fits.
      expect(
        open / needed,
        lessThan(0.05),
        reason:
            '$board: ${open.toStringAsFixed(1)} of ${needed.toStringAsFixed(1)} h open\n'
            '${lines.map((l) => l.text).join('\n')}',
      );
    }
  });
}
