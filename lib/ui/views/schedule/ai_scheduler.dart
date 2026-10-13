// AI week builder.
//
// The algorithm in schedule_engine.dart builds the week; the AI only reviews
// it. That way the schedule always matches the template exactly (one person
// per needed slot, never extra people), and the AI's job is small and cheap:
// look at a finished draft and suggest better people for some slots.
//
// Steps (shown in the terminal):
//   1. Training      new hires who need a trainer get one (engine)
//   2. Title / tag bars   Leader, Truck… slots, scarcest first (engine)
//   3. Everyone else      the rest; short bars join onto shifts (engine)
//   4. Holes         swaps, moved days, split slots (engine)
//   5. AI review     the model sees the draft plus, for every slot, who else
//                    could legally take it, and returns swaps to bring people
//                    closer to their usual shifts, Daytime/Night, no
//                    close-then-open. Every swap is checked by the engine;
//                    if the result covers less, it's all undone.
//   6. Check         what's still open and why, who's under / over their usual
//                    shifts, then positions are deployed by priority.
// If the AI isn't reachable (no key, quota…), the algorithm's schedule is
// kept as is.
//
// Privacy: people are sent as P1, P2, ... — no names, pay or contact info.
//
// Moving to a Cloud Function later only means swapping [geminiGenerate].

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/gemini_key.dart';
import '../../../models/schedule_models.dart';
import '../../../models/user_model.dart';
import 'position_ops.dart';
import 'schedule_common.dart';
import 'schedule_engine.dart';

/// Gemini models to try, in order. If one fails (not available, out of
/// free-tier quota, overloaded…) the next is tried. The last one that worked
/// is tried first next time.
const kScheduleAiModels = [
  'gemini-3.8-flash',
  'gemini-3.7-flash',
  'gemini-3.6-flash',
  'gemini-3.5-flash-lite',
];

/// Kinds of lines in the AI terminal.
enum AiLineKind { command, info, success, warning, error, ai, user }

typedef AiLine = ({AiLineKind kind, String text});

/// Sends a prompt to [model] and returns its text. [json] asks for the
/// review JSON shape.
typedef AiGenerate =
    Future<String> Function(
      String model,
      String system,
      String prompt, {
      bool json,
    });

/// Everything about the week being built.
class AiWeekContext {
  final DateTime weekStart;
  final List<ScheduleDay> days; // the 7 days of the week, in order
  final List<UserModel> people; // who can be scheduled
  final List<TimeOffEntry> timeOff; // approved
  final List<TimeOffEntry> requestedOff; // pending (treated as off)
  final ScheduleConfig config;
  /// The positions this schedule is deployed onto (its shift board's). Empty
  /// when its board combines schedules: then the board is deployed as a whole
  /// after the build.
  final List<ShiftPosition> positions;
  final List<String> titleOrder; // new-hire title first

  /// People in training: the training-flow steps (indexes into
  /// [ScheduleConfig.trainingDays]) they still have to do, in order, from
  /// the training review.
  final Map<String, List<int>> trainingRemaining;

  /// Shifts each person worked on this schedule in the last few weeks
  /// (weekday, times), for keeping the schedule consistent week to week.
  final Map<String, List<(int, TimeWindow)>> history;
  final int historyWeeks;

  /// What the manager typed for this build ("anything else?" and chat
  /// requests). Read by the AI; overrides the rules.
  final List<String> instructions;

  /// The schedule as it is now (chat changes keep as much as they can).
  final Map<String, List<(String, TimeWindow)>> keep;

  /// Admin time asked for in the "anything else?" window: person, minutes,
  /// day (null = any day they work).
  final List<({String uid, int minutes, String? date})> adminRequests;

  /// Work on the store's other schedules this week: uid → date → times.
  final Map<String, Map<String, List<TimeWindow>>> busyElsewhere;

  late final Map<String, String> aliasOf = {
    for (var i = 0; i < people.length; i++) people[i].id!: 'P${i + 1}',
  };
  late final Map<String, String> idOf = {
    for (final e in aliasOf.entries) e.value: e.key,
  };
  late final Map<String, UserModel> _byId = {
    for (final u in people) u.id!: u,
  };

  AiWeekContext({
    required this.weekStart,
    required this.days,
    required this.people,
    required this.timeOff,
    required this.requestedOff,
    required this.config,
    this.positions = const [],
    required this.titleOrder,
    this.trainingRemaining = const {},
    this.busyElsewhere = const {},
    this.history = const {},
    this.historyWeeks = 4,
    this.instructions = const [],
    this.keep = const {},
    this.adminRequests = const [],
  });

  List<TimeOffEntry> get allOff => [...timeOff, ...requestedOff];

  /// Days that have a template (the ones that can be built).
  List<ScheduleDay> get buildable => days.where((d) => d.hasTemplate).toList();

  /// Shifts people already have on days that aren't being rebuilt.
  late final Map<String, int> fixedShifts = () {
    final out = <String, int>{};
    for (final d in days.where((d) => !d.hasTemplate)) {
      for (final s in d.shifts) {
        for (final uid in [s.userId, ?s.traineeId]) {
          out[uid] = (out[uid] ?? 0) + 1;
        }
      }
    }
    return out;
  }();

  /// Everyone in training: their remaining steps in order (with a trainer
  /// or not, and on which position).
  late final Map<String, List<TrainingStepPlan>> trainingPlans = () {
    if (!config.trainingFlowEnabled) return const <String, List<TrainingStepPlan>>{};
    return {
      for (final e in trainingRemaining.entries)
        if (e.value.where((i) => i < config.trainingDays.length).toList() case final steps
            when steps.isNotEmpty)
          e.key: [
            for (final i in steps)
              (
                withTrainer: config.trainingDays[i].training,
                positionId: config.trainingDays[i].positionId,
              ),
          ],
    };
  }();

  /// Swaps people's names in [text] for their P-ids, so the manager's
  /// instructions go to the AI without names (longest names first; a first
  /// name alone only when nobody else has it).
  String aliasNames(String text) {
    final names = <String, String>{};
    final firsts = <String, int>{};
    for (final u in people) {
      final f = (u.preferredName?.trim().isNotEmpty ?? false) ? u.preferredName!.trim() : (u.firstName ?? '').trim();
      if (f.isNotEmpty) firsts[f.toLowerCase()] = (firsts[f.toLowerCase()] ?? 0) + 1;
    }
    for (final u in people) {
      final alias = aliasOf[u.id]!;
      final first = (u.firstName ?? '').trim();
      final preferred = (u.preferredName ?? '').trim();
      final last = (u.lastName ?? '').trim();
      for (final f in {first, preferred}) {
        if (f.isEmpty) continue;
        if (last.isNotEmpty) {
          names['$f $last'] = alias;
          names['$f ${last[0]}.'] = alias;
          names['$f ${last[0]}'] = alias;
        }
        if (firsts[f.toLowerCase()] == 1) names[f] = alias;
      }
    }
    final keys = names.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    var out = text;
    for (final k in keys) {
      out = out.replaceAll(
        RegExp('(?<![A-Za-z])${RegExp.escape(k)}(?![A-Za-z])', caseSensitive: false),
        names[k]!,
      );
    }
    return out;
  }

  /// Puts real names back in place of P-ids in the model's text.
  String unalias(String text) => text.replaceAllMapped(
    RegExp(r'\bP\d+\b'),
    (m) {
      final id = idOf[m.group(0)];
      return id == null ? m.group(0)! : personName(_byId[id], short: true);
    },
  );

  static String hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  static String range(TimeWindow w) => '${hhmm(w.start)}-${hhmm(w.end)}';

  /// The algorithm for this week.
  ScheduleEngine engine([ScheduleOverrides? overrides]) => ScheduleEngine(
    days: [for (final d in buildable) d.copyWith(shifts: const [])],
    people: people,
    timeOff: config.rules.requestedOffIsOff ? allOff : timeOff,
    rules: config.rules,
    overrides: overrides ?? ScheduleOverrides(keep: keep),
    config: config,
    fixedShifts: fixedShifts,
    busyElsewhere: busyElsewhere,
    trainingPlans: trainingPlans,
    history: history,
    historyWeeks: historyWeeks,
  );

  /// The draft as the AI sees it: people by P-id with their numbers, and
  /// every slot with who has it and who else could take it.
  Map<String, dynamic> reviewJson(ScheduleEngine e) => {
    'week_start': dateKey(weekStart),
    'people': [
      for (final u in people)
        if (!e.inTraining(u.id!))
          {
            'id': aliasOf[u.id],
            'title': u.title ?? '',
            if ((u.additionalTags ?? const []).isNotEmpty) 'tags': u.additionalTags,
            if ((u.workingTime ?? '').isNotEmpty) 'time': u.workingTime,
            'usual': e.target(u.id!),
            'max': e.maxShifts(u.id!),
            'now': e.daysWorked(u.id!),
            'hours': (e.minutesOf(u.id!) / 6).round() / 10,
          },
    ],
    'slots': [
      for (final s in e.slots)
        {
          'id': s.id,
          'date': s.date,
          'time': range(s.window),
          if (s.restricted) 'only': s.onlyTags,
          'who': aliasOf[e.whoOn(s.id)],
          if (e.traineeOn(s.id) != null || (e.whoOn(s.id) != null && e.inTraining(e.whoOn(s.id)!)))
            'locked': true,
          'could': [
            for (final c in e.candidates(s, except: e.whoOn(s.id)).take(6)) aliasOf[c],
          ],
          if ([
            for (final u in people)
              if (e.habit(u.id!, s) >= 0.5) aliasOf[u.id],
          ] case final usual when usual.isNotEmpty)
            'usually': usual.take(3).toList(),
        },
    ],
  };
}

const _reviewRules = '''
You review a restaurant's draft weekly schedule. An algorithm already built
it: each slot is a fixed piece of the template (date + time) that needs one
person, and every hard rule already holds. Improve it by changing WHO works
some slots. Never leave a slot empty that has someone, never add slots.

Data:
- people: id, title, tags, time (Daytime/Night preference), usual (shifts a
  week they usually want), max (hard weekly cap), now (shifts in the draft),
  hours (hours in the draft).
- slots: id, date, time, only (titles/tags allowed), who (assigned person or
  null = still open), locked (a training shift: don't change it), could
  (people who can legally take it right now: free that day, available for
  the whole slot, under their max, right title/tag), usually (people who
  worked this weekday at about this time most of the last few weeks).

Priorities, in order:
1. Fill open slots (who = null) with someone from their "could" list.
2. Bring people close to their usual shifts: move slots from people above
   their usual to people below it.
3. Keep the schedule consistent week to week: prefer giving a slot to
   someone in its "usually" list.
4. Daytime people on morning slots, Night people on evening slots.
5. Nobody closes (ends 21:00 or later) and opens (starts 07:00 or earlier)
   the next morning.
6. Few changes. If the draft is already good, return no changes.

How to change: give a slot to a person in its "could" list, or swap two
people's slots on the same date (list both changes). A person works one slot
a day, except short slots right before/after their slot. Don't exceed max.

Manager instructions (manager_instructions, if any) come first: follow them
whenever a change in the slots' "could" lists can.

Reply JSON: {"changes": [{"slot": "S4", "person": "P7"}], "notes": "..."}.
Notes: one or two short sentences on what you changed and why (refer to
people by id).
''';

const _instructionRules = '''
You turn a restaurant manager's scheduling instructions into JSON directives
for the scheduling app. People are referred to by id (P1, P2, …); the app
puts names back. Use only ids from "people" and dates from "dates".

Directive types (one per thing asked; split "A and B" into one per person
where it makes sense):
- train: people = [trainer, trainee]; date optional. "A trains B".
- off: people; date optional (null = all week); start/end optional (HH:mm)
  for part of the day. "A can't work Friday", "B is off after 5".
- work: people; date required; start/end optional. "A must work Tuesday".
- meeting: people (2+); minutes (length); date optional. "Meeting with A, B,
  C for an hour" → minutes 60.
- max_shifts: people; value = most shifts this week. "Give A only 3 shifts".
- apart: people (2+) never on the same day. "Don't schedule A with B".
- no_training: people; date optional. "No training for A on Wednesday",
  "A shouldn't train anyone Monday".
- admin: people; minutes; date optional. Admin time (paperwork, ordering,
  truck check-in…) right before or after their shift, off the floor. If they
  describe someone ("whoever does truck"), pick one fitting id.
- note: anything else the app can't do directly; text = the request, kept
  short (it's passed on to the schedule review).

Every directive has "request": the number of the instruction it came from
(1 = the first one).

Reply JSON: {"directives": [...]}. Times are 24-hour "HH:mm".
''';

const Map<String, dynamic> _directiveSchema = {
  'type': 'OBJECT',
  'properties': {
    'directives': {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'type': {
            'type': 'STRING',
            'enum': ['train', 'off', 'work', 'meeting', 'max_shifts', 'apart', 'no_training', 'admin', 'note'],
          },
          'people': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
          'date': {'type': 'STRING', 'nullable': true},
          'start': {'type': 'STRING', 'nullable': true},
          'end': {'type': 'STRING', 'nullable': true},
          'minutes': {'type': 'INTEGER', 'nullable': true},
          'value': {'type': 'INTEGER', 'nullable': true},
          'text': {'type': 'STRING', 'nullable': true},
          'request': {'type': 'INTEGER', 'description': 'Which instruction (1 = first)'},
        },
        'required': ['type', 'request'],
      },
    },
  },
  'required': ['directives'],
};

/// The JSON shape the model must reply with (Gemini API schema format).
const Map<String, dynamic> _scheduleSchema = {
  'type': 'OBJECT',
  'properties': {
    'changes': {
      'type': 'ARRAY',
      'items': {
        'type': 'OBJECT',
        'properties': {
          'slot': {'type': 'STRING', 'description': 'Slot id, e.g. S12'},
          'person': {'type': 'STRING', 'description': 'Person id, e.g. P3'},
        },
        'required': ['slot', 'person'],
      },
    },
    'notes': {'type': 'STRING', 'description': 'What changed and why, briefly'},
  },
  'required': ['changes'],
};

/// Error from the Gemini API, with Google's message.
class GeminiException implements Exception {
  final int? status;
  final String message;
  const GeminiException(this.message, {this.status});

  /// Worth trying another model? Not for key / permission problems, which
  /// every model would hit the same way.
  bool get tryNextModel =>
      status != 401 &&
      status != 403 &&
      !message.contains('API key') &&
      !message.contains('No Gemini API key');

  /// First sentence, for the log.
  String get short {
    final first = message.split(RegExp(r'(?<=\.)\s')).first;
    return first.length > 140 ? '${first.substring(0, 140)}…' : first;
  }

  @override
  String toString() => message;
}

/// Calls the Gemini API with the key in [kGeminiApiKey].
Future<String> geminiGenerate(
  String model,
  String system,
  String prompt, {
  bool json = false,
}) async {
  if (kGeminiApiKey.isEmpty) {
    throw const GeminiException(
      'No Gemini API key yet: paste one into lib/core/gemini_key.dart.',
    );
  }
  final response = await http.post(
    Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
    ),
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': kGeminiApiKey,
    },
    body: jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': json ? 0.2 : 0.4,
        if (json) 'responseMimeType': 'application/json',
        if (json)
          'responseSchema': system == _instructionRules ? _directiveSchema : _scheduleSchema,
      },
    }),
  );
  Map<String, dynamic>? body;
  try {
    body = jsonDecode(response.body) as Map<String, dynamic>;
  } catch (_) {}
  if (response.statusCode != 200) {
    final message = (body?['error'] as Map?)?['message'] as String?;
    throw GeminiException(
      'Gemini API error ${response.statusCode}: ${message ?? response.body}',
      status: response.statusCode,
    );
  }
  final parts =
      ((body?['candidates'] as List?)?.firstOrNull as Map?)?['content']?['parts']
          as List?;
  return [
    for (final p in parts ?? const [])
      if (p is Map && p['text'] is String) p['text'] as String,
  ].join();
}

/// The days that were built (date → day), ready to save.
typedef AiBuildResult = Map<String, ScheduleDay>;

class AiScheduler {
  final AiGenerate generate;
  final List<String> models;
  AiScheduler({this.generate = geminiGenerate, this.models = kScheduleAiModels});

  /// The model that answered last time (tried first next time).
  static String? lastWorkingModel;

  /// Asks the models in order until one returns usable JSON.
  Future<Map<String, dynamic>> _ask(
    String prompt,
    void Function(AiLine) log, {
    String system = _reviewRules,
  }) async {
    final order = [
      if (models.contains(lastWorkingModel)) lastWorkingModel!,
      ...models.where((m) => m != lastWorkingModel),
    ];
    Object? lastError;
    for (final model in order) {
      try {
        final raw = await generate(model, system, prompt, json: true);
        final parsed = jsonDecode(raw);
        if (parsed is! Map<String, dynamic>) {
          throw const FormatException('not a JSON object');
        }
        lastWorkingModel = model;
        return parsed;
      } on GeminiException catch (e) {
        lastError = e;
        if (!e.tryNextModel) rethrow;
        log((
          kind: AiLineKind.warning,
          text: '$model failed (${e.short}). Trying the next model.',
        ));
      } on FormatException {
        lastError = 'bad JSON';
        log((
          kind: AiLineKind.warning,
          text: '$model didn\'t return valid JSON. Trying the next model.',
        ));
      }
    }
    throw GeminiException('Every model failed. Last error: $lastError');
  }

  /// Builds every day of [ctx] that has a template. Existing shifts on those
  /// days are replaced.
  Future<AiBuildResult> buildWeek(
    AiWeekContext ctx, {
    required Map<String, UserModel> users,
    required void Function(AiLine) log,
  }) async {
    String who(String uid) => personName(users[uid] ?? ctx._byId[uid], short: true);
    final targets = ctx.buildable;
    if (targets.isEmpty) {
      log((kind: AiLineKind.error, text: 'No day this week has a template yet.'));
      return const {};
    }
    final skipped = ctx.days.where((d) => !d.hasTemplate).map(_dayShort);

    // The manager's requests (they override the rules): free-text ones read
    // by the AI, admin time straight from the form.
    var overrides = ScheduleOverrides(keep: ctx.keep);
    final notes = <String>[];
    final direct = <({String source, int status, String text})>[];
    final ids = {for (final u in ctx.people) u.id};
    final admin = [
      for (var i = 0; i < ctx.adminRequests.length; i++)
        if (ids.contains(ctx.adminRequests[i].uid))
          (
            uid: ctx.adminRequests[i].uid,
            minutes: ctx.adminRequests[i].minutes,
            date: ctx.adminRequests[i].date,
            source: 'a$i',
          ),
    ];
    if (ctx.instructions.isNotEmpty) {
      final read = await readInstructions(ctx, log: log, who: who);
      overrides = read.overrides;
      notes.addAll(read.notes);
      direct.addAll(read.direct);
    }
    overrides = overrides.withAdmin([...overrides.admin, ...admin]);
    final hasRequests = ctx.instructions.isNotEmpty || admin.isNotEmpty;

    final e = ctx.engine(overrides);
    log((
      kind: AiLineKind.info,
      text:
          '${targets.length} days, ${ctx.people.length} people, ${e.slots.length} slots '
          '(${formatHours(e.neededMinutes / 60)} h)'
          '${skipped.isEmpty ? '' : '. No template: ${skipped.join(', ')}'}.',
    ));

    var step = 0;
    final hasTraining = e.trainingPlans.isNotEmpty;
    final steps = 3 + (hasTraining ? 1 : 0) + (hasRequests ? 1 : 0);
    // Each step logs a header, then lets the terminal draw before working.
    Future<void> header(String title) async {
      log((kind: AiLineKind.command, text: 'step ${++step}/$steps · $title'));
      await Future<void>.delayed(Duration.zero);
    }

    if (hasRequests) {
      await header('your requests');
      e.placeOverrides();
    }

    if (hasTraining) {
      await header('training');
      final n = e.placeTraining();
      final people = e.training.where((t) => t.shifts.isNotEmpty).length;
      log((
        kind: AiLineKind.success,
        text: '$n training ${n == 1 ? 'shift' : 'shifts'} for $people '
            '${people == 1 ? 'person' : 'people'}.',
      ));
      for (final t in e.training.where((t) => t.why != null)) {
        log((
          kind: AiLineKind.warning,
          text: '${who(t.traineeId)}: ${t.shifts.length} of ${t.wanted} training shifts (${t.why}).',
        ));
      }
    }
    e.checkTrainingPairs();

    await header('filling the schedule');
    e.fill(restrictedOnly: true, short: false);
    e.fill(short: false);
    e.fill(short: true);
    if (e.openSlots.isNotEmpty) e.repair();
    log((
      kind: e.openSlots.isEmpty ? AiLineKind.success : AiLineKind.info,
      text: 'Covered ${_pct(e)} of the needed time'
          '${e.openSlots.isEmpty ? '.' : ' (${e.openSlots.length} open).'}',
    ));

    await header('AI review');
    await _review(ctx, e, users: users, log: log, notes: notes);

    e.placeAdmin();
    await header('check');
    if (hasRequests) _reportRequests(ctx, e, direct, admin, log: log, who: who);
    _report(ctx, e, who: who, log: log);
    return finish(ctx, e.toDays(), log: log);
  }

  /// One line per request: done (✓), couldn't (✗, with why), or passed on.
  void _reportRequests(
    AiWeekContext ctx,
    ScheduleEngine e,
    List<({String source, int status, String text})> direct,
    List<({String uid, int minutes, String? date, String source})> admin, {
    required void Function(AiLine) log,
    required String Function(String) who,
  }) {
    final all = [
      ...direct,
      for (final o in e.outcomes) (source: o.source, status: o.ok ? 1 : 0, text: o.text),
    ];
    final requests = <(String, String)>[
      for (final a in admin)
        (
          a.source,
          'Admin for ${who(a.uid)} (${formatHours(a.minutes / 60)} h'
              '${a.date == null ? '' : ', ${_dateShort(a.date!)}'})',
        ),
      for (var i = 0; i < ctx.instructions.length; i++) ('r${i + 1}', '"${ctx.instructions[i]}"'),
    ];
    log((kind: AiLineKind.info, text: 'Your requests:'));
    for (final (source, label) in requests) {
      final mine = all.where((o) => o.source == source).toList();
      if (mine.isEmpty) {
        // A request naming nobody on this schedule is for another one.
        final i = int.tryParse(source.substring(1));
        if (source.startsWith('r') &&
            i != null &&
            ctx.aliasNames(ctx.instructions[i - 1]) == ctx.instructions[i - 1]) {
          continue;
        }
        log((kind: AiLineKind.warning, text: '$label: didn\'t understand it. Try rewording.'));
        continue;
      }
      final failed = mine.where((o) => o.status == 0).toList();
      final info = mine.every((o) => o.status == 2);
      log((
        kind: failed.isNotEmpty
            ? AiLineKind.warning
            : (info ? AiLineKind.info : AiLineKind.success),
        text: '$label: ${failed.isNotEmpty ? 'couldn\'t. ${failed.map((o) => o.text).join(' ')}' : mine.map((o) => o.text).join(' ')}',
      ));
    }
  }

  /// Turns the manager's instructions into directives for the engine (with
  /// the AI). Returns them, plus anything the engine can't do directly
  /// (passed on to the review). Without the AI, nothing is read.
  Future<
    ({
      ScheduleOverrides overrides,
      List<String> notes,
      List<({String source, int status, String text})> direct,
    })
  >
  readInstructions(
    AiWeekContext ctx, {
    required void Function(AiLine) log,
    required String Function(String) who,
  }) async {
    final dates = [for (final d in ctx.buildable) d.date];
    final Map<String, dynamic> parsed;
    try {
      parsed = await _ask(
        jsonEncode({
          'instructions': [
            for (var i = 0; i < ctx.instructions.length; i++)
              {'request': i + 1, 'text': ctx.aliasNames(ctx.instructions[i])},
          ],
          'dates': [
            for (final d in dates)
              {'date': d, 'weekday': weekdayNames[DateTime.parse(d).weekday - 1]},
          ],
          'people': [
            for (final u in ctx.people)
              {
                'id': ctx.aliasOf[u.id],
                'title': u.title ?? '',
                if ((u.additionalTags ?? const []).isNotEmpty) 'tags': u.additionalTags,
              },
          ],
        }),
        log,
        system: _instructionRules,
      );
    } on GeminiException catch (err) {
      log((
        kind: AiLineKind.warning,
        text: 'Couldn\'t read your instructions without the AI (${err.short}). '
            'Building without them.',
      ));
      return (
        overrides: ScheduleOverrides(keep: ctx.keep),
        notes: const <String>[],
        direct: const <({String source, int status, String text})>[],
      );
    }

    int? minute(dynamic v) {
      final parts = v?.toString().split(':');
      if (parts == null || parts.length != 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      return h == null || m == null ? null : h * 60 + m;
    }

    final maxShifts = <String, int>{};
    final pairs = <({String trainer, String trainee, String? date, String source})>[];
    final mustWork = <({String uid, String date, TimeWindow? window, String source})>[];
    final meetings = <({List<String> people, int minutes, String? date, String source})>[];
    final admin = <({String uid, int minutes, String? date, String source})>[];
    final direct = <({String source, int status, String text})>[];
    final apart = <Set<String>>[];
    final noTraining = <({String uid, String? date})>[];
    final extraOff = <TimeOffEntry>[];
    final notes = <String>[];
    String day(String d) => _dateShort(d);

    for (final raw in (parsed['directives'] as List? ?? const []).whereType<Map>()) {
      final type = raw['type'] as String? ?? '';
      final ids = [
        for (final p in (raw['people'] as List? ?? const []))
          if (ctx.idOf[p.toString()] case final id?) id,
      ];
      final date = dates.contains(raw['date']) ? raw['date'] as String : null;
      final start = minute(raw['start']);
      var end = minute(raw['end']);
      if (start != null && end != null && end <= start) end += 1440;
      final window = start != null && end != null ? TimeWindow(start, end) : null;
      final when = date == null ? 'this week' : day(date);
      final source = 'r${(raw['request'] as num?)?.toInt() ?? 1}';
      void done(String text) => direct.add((source: source, status: 1, text: text));
      switch (type) {
        case 'train' when ids.length >= 2:
          pairs.add((trainer: ids[0], trainee: ids[1], date: date, source: source));
        case 'off' when ids.isNotEmpty:
          for (final id in ids) {
            extraOff.add(
              TimeOffEntry(
                userId: id,
                startDate: date ?? dates.first,
                endDate: date ?? dates.last,
                reason: 'Your instructions',
                startMinute: window?.start,
                endMinute: window?.end,
              ),
            );
          }
          done('${ids.map(who).join(', ')} off $when'
              '${window == null ? '' : ' ${formatRange(window.start, window.end)}'}.');
        case 'work' when ids.isNotEmpty && date != null:
          for (final id in ids) {
            mustWork.add((uid: id, date: date, window: window, source: source));
          }
        case 'meeting' when ids.length >= 2:
          final minutes = (raw['minutes'] as num?)?.toInt() ?? 60;
          meetings.add((people: ids, minutes: minutes, date: date, source: source));
        case 'max_shifts' when ids.isNotEmpty && raw['value'] is num:
          for (final id in ids) {
            maxShifts[id] = (raw['value'] as num).toInt();
          }
          done('${ids.map(who).join(', ')} get at most ${raw['value']} shifts.');
        case 'apart' when ids.length >= 2:
          apart.add(ids.toSet());
          done('${ids.map(who).join(', ')} are never on the same day.');
        case 'no_training' when ids.isNotEmpty:
          for (final id in ids) {
            noTraining.add((uid: id, date: date));
          }
          done('No training for ${ids.map(who).join(', ')} $when.');
        case 'admin' when ids.isNotEmpty:
          final minutes = (raw['minutes'] as num?)?.toInt() ?? 60;
          for (final id in ids) {
            admin.add((uid: id, minutes: minutes, date: date, source: source));
          }
        default:
          final text = (raw['text'] as String?)?.trim();
          if (text != null && text.isNotEmpty) {
            notes.add(text);
            direct.add((source: source, status: 2, text: 'Passed to the AI review.'));
          }
      }
    }
    return (
      overrides: ScheduleOverrides(
        maxShifts: maxShifts,
        pairs: pairs,
        mustWork: mustWork,
        meetings: meetings,
        apart: apart,
        noTraining: noTraining,
        extraOff: extraOff,
        admin: admin,
        keep: ctx.keep,
      ),
      notes: notes,
      direct: direct,
    );
  }

  /// Asks the model to improve the draft with swaps, and applies the ones
  /// that keep every rule. Keeps the draft when the model isn't reachable.
  Future<void> _review(
    AiWeekContext ctx,
    ScheduleEngine e, {
    required Map<String, UserModel> users,
    required void Function(AiLine) log,
    List<String> notes = const [],
  }) async {
    final Map<String, dynamic> parsed;
    try {
      parsed = await _ask(
        jsonEncode({
          ...ctx.reviewJson(e),
          if (ctx.instructions.isNotEmpty)
            'manager_instructions': [
              for (final t in ctx.instructions) ctx.aliasNames(t),
              ...notes,
            ],
        }),
        log,
      );
    } on GeminiException catch (err) {
      final noKey = err.message.contains('No Gemini API key');
      log((
        kind: noKey ? AiLineKind.info : AiLineKind.warning,
        text: noKey
            ? 'No Gemini API key, so skipped the AI review '
                  '(lib/core/gemini_key.dart). Kept the algorithm\'s schedule.'
            : 'AI review failed (${err.short}). Kept the algorithm\'s schedule.',
      ));
      if (err.message.contains('API key not valid') || err.message.contains('API_KEY')) {
        log((
          kind: AiLineKind.info,
          text: 'Check the key in lib/core/gemini_key.dart (aistudio.google.com/apikey).',
        ));
      }
      return;
    }
    final changes = <(String, String)>[
      for (final c in (parsed['changes'] as List? ?? const []).whereType<Map>().take(80))
        if (c['slot'] is String && ctx.idOf[c['person']] != null)
          (c['slot'] as String, ctx.idOf[c['person']]!),
    ];
    final note = (parsed['notes'] as String?)?.trim();
    if (changes.isEmpty) {
      log((kind: AiLineKind.success, text: 'No changes needed.'));
    } else {
      final r = e.applyChanges(changes);
      if (r.reverted) {
        log((
          kind: AiLineKind.warning,
          text: 'The AI\'s ${changes.length} changes would have left slots open, so '
              'they were undone.',
        ));
      } else {
        log((
          kind: AiLineKind.success,
          text: '${r.applied} ${r.applied == 1 ? 'change' : 'changes'} applied'
              '${r.skipped.isEmpty ? '' : ' (${r.skipped.length} broke a rule and were skipped)'}.',
        ));
      }
    }
    if (note != null && note.isNotEmpty) {
      log((kind: AiLineKind.ai, text: 'AI note: ${ctx.unalias(note)}'));
    }
  }

  /// What's still open and why, and who's away from their usual shifts.
  static void _report(
    AiWeekContext ctx,
    ScheduleEngine e, {
    required String Function(String) who,
    required void Function(AiLine) log,
  }) {
    final open = e.openStretches();
    if (open.isEmpty) {
      log((kind: AiLineKind.success, text: 'Every needed hour is covered.'));
    } else {
      final hours = open.fold<int>(0, (a, o) => a + o.slot.minutes) / 60;
      log((
        kind: AiLineKind.error,
        text: 'Not fully staffed — ${open.length} open '
            '${open.length == 1 ? 'slot' : 'slots'} (${formatHours(hours)} hrs):',
      ));
      for (final o in open.take(8)) {
        final s = o.slot;
        final what = s.restricted
            ? ' ${s.onlyTags.join('/')}'
            : (s.label.isNotEmpty ? ' ${s.label}' : '');
        log((
          kind: AiLineKind.warning,
          text: '${_dateShort(s.date)} · ${formatRange(s.start, s.end)}$what: ${o.why}',
        ));
      }
    }

    if (open.length > 8) {
      log((kind: AiLineKind.warning, text: '…and ${open.length - 8} more.'));
    }
  }

  static String _pct(ScheduleEngine e) => e.neededMinutes == 0
      ? '100%'
      : '${(e.coveredMinutes * 100 / e.neededMinutes).floor()}%';

  /// Training-flow pins, position deployment and a summary per day.
  static AiBuildResult finish(
    AiWeekContext ctx,
    Map<String, ScheduleDay> current, {
    required void Function(AiLine) log,
  }) {
    final out = {...current};
    // A trainee's nth day this week → their nth remaining step's position.
    final appearances = <String, List<String>>{}; // uid -> dates in order
    for (final date in out.keys.toList()..sort()) {
      for (final s in out[date]!.shifts) {
        for (final uid in [s.userId, ?s.traineeId]) {
          if (ctx.trainingRemaining.containsKey(uid)) (appearances[uid] ??= []).add(date);
        }
      }
    }
    for (final date in out.keys) {
      final steps = <String, TrainingStep>{};
      appearances.forEach((uid, dates) {
        final n = dates.indexOf(date);
        if (n < 0) return;
        final left = ctx.trainingRemaining[uid]!;
        final step = n < left.length ? trainingStepFor(ctx.config, left[n]) : null;
        if (step != null) steps[uid] = step;
      });
      out[date] = deployPositions(
        out[date]!,
        ctx.positions,
        pinned: trainingPins(out[date]!, steps),
      );
    }

    return out;
  }

  static String _dayShort(ScheduleDay d) => _dateShort(d.date);

  static String _dateShort(String date) {
    final d = DateTime.parse(date);
    return '${weekdayShort[d.weekday - 1]} ${d.day}';
  }
}
