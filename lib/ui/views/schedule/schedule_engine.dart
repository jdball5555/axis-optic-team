// The schedule-building algorithm (no AI, no Firestore).
//
// The template is the plan: every bar is cut into SLOTS, and each slot gets
// exactly one person (or stays open). Nothing is ever added outside the
// template, so the schedule can't end up with more people than it needs.
//
// 1. Compile   Cut each row's bars into shift-sized slots. A bar longer than
//              a shift (e.g. 6a–10:45p) is split where the most people are
//              free on both sides. For every person and day, work out when
//              they can work (availability minus approved AND requested time
//              off, minus shifts on the store's other schedules).
// 2. Training  People in training get their next training-flow shifts, in
//              order, on later and later days of the week, as many as fit:
//              a step with a trainer puts a trainer on a slot they can both
//              work and the trainee shadows them (no slot of their own); a
//              solo step gives the trainee a slot themselves. They don't get
//              other shifts this week.
// 3. Title / tag bars   Slots only some people can take (Leader, Truck…),
//              scarcest first.
// 4. Everyone else      The rest, scarcest first; short bars (Truck, Prep,
//              Admin under 3 hours) last, added onto the start or end of
//              someone's shift.
// 5. Holes     Open slots are fixed with swaps (move someone in, give their
//              slot to someone free), by moving a person's other day, or by
//              splitting the slot between two people; last, by someone
//              already on that day staying on (up to the most hours a day).
// 6. Admin     Admin time and admin meetings are always joined onto a shift:
//              right before or after it (the floor stays covered), or inside
//              it only when that isn't possible. Never on its own. A meeting
//              is reserved before filling, on the day that gets the most
//              people to it while covering the most (each day is tried).
//
// Hard rules (never broken): availability, time off, title / tag bars, one
// stretch of work per person per day (short bars can join onto it), at most
// [maxShiftsPerWeek] shifts a week, who can train.
// Priorities when choosing between people: covering the template first,
// then getting people close to their usual shifts a week, then keeping
// people on the shifts they've worked the last few weeks (same weekday,
// about the same time), then Daytime people in the morning and Night people
// in the evening, then no close-then-open, then fair hours.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../models/schedule_models.dart';
import '../../../models/user_model.dart';
import 'schedule_common.dart';
import 'schedule_ops.dart';

/// Default URL for the Python FastAPI CP-SAT optimization backend.
const String kDefaultScheduleBackendUrl = String.fromEnvironment(
  'SCHEDULE_BACKEND_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

/// Exception thrown when the remote CP-SAT solver fails or returns infeasible.
class ScheduleSolveException implements Exception {
  final String message;
  final List<String> details;

  const ScheduleSolveException(this.message, [this.details = const []]);

  @override
  String toString() => details.isEmpty
      ? 'ScheduleSolveException: $message'
      : 'ScheduleSolveException: $message\n${details.map((d) => '  • $d').join('\n')}';
}

/// Longest bar that stays one slot (a long leader shift).
const int kMaxSlotMinutes = 11 * 60;

/// Longer bars are cut into pieces about this long.
const int kSplitTargetMinutes = 9 * 60;

/// Shortest piece a long bar is cut into.
const int kMinSplitMinutes = 4 * 60;

/// Bars shorter than this (Truck, Prep, Admin…) are added onto someone's
/// shift instead of being a shift of their own.
const int kShortSlotMinutes = 3 * 60;

/// Most someone works in a day when a short bar is added onto their shift.
const int kMaxDayMinutes = 11 * 60;

/// Shortest part of a slot given to someone when nobody can work all of it.
const int kMinPartMinutes = 3 * 60;

/// The manager's instructions for one build (from the "anything else?" box
/// or the terminal chat, read by the AI). They override the rules.
class ScheduleOverrides {
  /// Weekly most shifts for some people.
  final Map<String, int> maxShifts;

  /// Train this trainee with this trainer (even if they aren't a trainer),
  /// on [date] or any day. ([source] = which request it came from, for the
  /// report of what was done.)
  final List<({String trainer, String trainee, String? date, String source})>
  pairs;

  /// Must work on [date] (at [window] if set), even outside availability.
  final List<({String uid, String date, TimeWindow? window, String source})>
  mustWork;

  /// Everyone in [people] works at the same time for [minutes] (a meeting),
  /// on [date] or any day. [asAdmin] = scheduled as admin time off the floor.
  final List<
    ({
      List<String> people,
      int minutes,
      String? date,
      bool asAdmin,
      String source,
    })
  >
  meetings;

  /// Admin time: [minutes] off the floor for [uid], right before or after
  /// their shift (on [date] or any day they work, or [everyDay] on each day).
  final List<
    ({String uid, int minutes, String? date, bool everyDay, String source})
  >
  admin;

  /// Never scheduled on the same day as each other.
  final List<Set<String>> apart;

  /// No training (as trainer or trainee) on [date], or all week.
  final List<({String uid, String? date})> noTraining;

  /// Extra time off (e.g. "Ivy is off Friday").
  final List<TimeOffEntry> extraOff;

  /// The schedule as it is now: changes from the chat keep as much of it as
  /// they can. uid → (date, times).
  final Map<String, List<(String, TimeWindow)>> keep;

  const ScheduleOverrides({
    this.maxShifts = const {},
    this.pairs = const [],
    this.mustWork = const [],
    this.meetings = const [],
    this.apart = const [],
    this.noTraining = const [],
    this.extraOff = const [],
    this.admin = const [],
    this.keep = const {},
  });

  ScheduleOverrides withAdmin(
    List<
      ({String uid, int minutes, String? date, bool everyDay, String source})
    >
    admin,
  ) => ScheduleOverrides(
    maxShifts: maxShifts,
    pairs: pairs,
    mustWork: mustWork,
    meetings: meetings,
    apart: apart,
    noTraining: noTraining,
    extraOff: extraOff,
    admin: admin,
    keep: keep,
  );

  bool get isEmpty =>
      maxShifts.isEmpty &&
      pairs.isEmpty &&
      mustWork.isEmpty &&
      meetings.isEmpty &&
      apart.isEmpty &&
      noTraining.isEmpty &&
      extraOff.isEmpty &&
      admin.isEmpty;
}

/// Part of a template row one person should cover.
class Slot {
  final String id; // S1, S2, …
  final String date;
  final int dayIndex; // position in the week being built
  final String rowId;
  final int start;
  final int end;
  final List<String> onlyTags; // the row's allowed titles / tags
  final String label;

  const Slot({
    required this.id,
    required this.date,
    required this.dayIndex,
    required this.rowId,
    required this.start,
    required this.end,
    this.onlyTags = const [],
    this.label = '',
  });

  int get minutes => end - start;
  bool get restricted => onlyTags.isNotEmpty;
  bool get short => minutes < kShortSlotMinutes;
  TimeWindow get window => TimeWindow(start, end);

  Slot part(String id, int s, int e) => Slot(
    id: id,
    date: date,
    dayIndex: dayIndex,
    rowId: rowId,
    start: s,
    end: e,
    onlyTags: onlyTags,
    label: label,
  );
}

/// An admin meeting reserved before filling: when, and who's on for it.
typedef _MeetingPlan = ({String date, TimeWindow window, List<String> people});

/// Why a slot couldn't be filled.
typedef OpenSlot = ({Slot slot, String why});

/// An AI change that wasn't applied, and why.
typedef SkippedChange = ({String slotId, String uid, String why});

/// One training-flow step: with a trainer or on their own, and on which
/// position (null = any).
typedef TrainingStepPlan = ({bool withTrainer, String? positionId});

/// Training shifts someone got this week: (date, with a trainer?) in order,
/// how many steps they had left, and why they didn't get more.
typedef TrainingOutcome = ({
  String traineeId,
  int wanted,
  List<(String, bool)> shifts,
  String? why,
});

class ScheduleEngine {
  /// The days being built, in order (each has template rows).
  final List<ScheduleDay> days;
  final List<UserModel> people;
  final List<TimeOffEntry> timeOff; // approved + requested
  final ScheduleConfig config;

  /// Shifts each person already has this week on days not being built.
  final Map<String, int> fixedShifts;

  /// Work on the store's other schedules: uid → date → times.
  final Map<String, Map<String, List<TimeWindow>>> busyElsewhere;

  /// Shifts each person worked in the last [historyWeeks] weeks on this
  /// schedule: (weekday, times).
  final Map<String, List<(int, TimeWindow)>> history;
  final int historyWeeks;

  final ScheduleRules rules;
  final ScheduleOverrides overrides;

  /// People in training: their remaining training-flow steps in order.
  final Map<String, List<TrainingStepPlan>> trainingPlans;

  /// Optional backend URL override for remote CP-SAT solving.
  final String? backendUrl;

  /// Admin meetings (index in [ScheduleOverrides.meetings]) to reserve on
  /// this day before filling. Others go next to the shifts people have
  /// after filling. (See [bestMeetingDays].)
  final Map<int, String> meetingDays;

  bool inTraining(String uid) => trainingPlans.containsKey(uid);

  ScheduleEngine({
    required this.days,
    required this.people,
    required this.timeOff,
    required this.config,
    this.fixedShifts = const {},
    this.busyElsewhere = const {},
    this.trainingPlans = const {},
    this.history = const {},
    this.historyWeeks = 4,
    this.rules = const ScheduleRules(),
    this.overrides = const ScheduleOverrides(),
    this.backendUrl,
    this.meetingDays = const {},
  }) {
    _compile();
  }

  late final Map<String, UserModel> byId = {for (final u in people) u.id!: u};
  late final Map<String, ScheduleDay> _dayByDate = {
    for (final d in days) d.date: d,
  };

  final List<Slot> slots = [];
  final Map<String, String> _who = {}; // slot id → uid
  final Map<String, String> _trainee = {}; // slot id → trainee uid
  final Map<String, Set<String>> _traineeDates = {}; // trainee → dates
  final Set<String> _trainingSlots = {}; // slot ids reserved for training
  final Set<String> _pinned = {}; // slot ids placed for the manager's requests
  final List<TrainingOutcome> training = [];
  int _nextId = 1;

  String? whoOn(String slotId) => _who[slotId];
  String? traineeOn(String slotId) => _trainee[slotId];
  bool isTrainingSlot(String slotId) => _trainingSlots.contains(slotId);

  /// Placed for one of the manager's requests (must-work day, meeting, admin
  /// day): repairs and the AI review leave it alone.
  bool isPinned(String slotId) => _pinned.contains(slotId);

  /// Training or a request: nobody else may take this slot over.
  bool _locked(String slotId) =>
      _trainingSlots.contains(slotId) ||
      _trainee.containsKey(slotId) ||
      _pinned.contains(slotId);
  Slot? slotById(String id) => slots.where((s) => s.id == id).firstOrNull;

  // ---------------------------------------------------------------------------
  // Remote CP-SAT Solver Integration
  // ---------------------------------------------------------------------------

  /// Serializes the complete weekly scheduling problem into the JSON payload
  /// accepted by the Axis Python FastAPI CP-SAT backend. The manager's
  /// requests and training are placed here first (placeOverrides,
  /// placeTraining) and sent as fixed assignments; the solver fills the rest.
  Map<String, dynamic> buildSolveRequestJson() {
    // Shifts a person already has this week outside these slots (days not
    // being built, other schedules) count toward their weekly most.
    int elsewhere(String uid) =>
        (fixedShifts[uid] ?? 0) +
        (busyElsewhere[uid] ?? const <String, List<TimeWindow>>{}).values
            .where((w) => w.isNotEmpty)
            .length;
    int left(num n, String uid) =>
        (n.round() - elsewhere(uid)).clamp(0, days.length);
    return {
      'week_start': days.isNotEmpty ? days.first.date : dateKey(DateTime.now()),
      'roster': [
        for (final u in people)
          {
            'id': u.id ?? '',
            'name': '${u.firstName ?? ''} ${u.lastName ?? ''}'.trim(),
            'title': u.title ?? 'Team Member',
            'tags': u.additionalTags ?? <String>[],
            'designation': u.designation,
            'is_minor': isMinor(u.id!),
            'max_shifts_per_week': left(maxShifts(u.id!), u.id!),
            'target_shifts': left(
              math.min(target(u.id!), maxShifts(u.id!)),
              u.id!,
            ),
            'target_hours':
                ((target(u.id!) *
                        (rules.shiftLengthRangeOn
                            ? ((rules.minShiftHours + rules.maxShiftHours) / 2)
                            : 6.0) *
                        10)
                    .round() /
                10),
            'day_night_preference': u.workingTime,
            'can_train': canTrain(u, config),
          },
      ],
      'days': [
        for (var d = 0; d < days.length; d++)
          {
            'date': days[d].date,
            'day_index': d,
            'weekday': DateTime.parse(days[d].date).weekday,
            'template_id': days[d].templateId,
            'template_name': days[d].templateName,
            'slots': [
              for (final s in slots.where((s) => s.date == days[d].date))
                {
                  'id': s.id,
                  'date': s.date,
                  'day_index': s.dayIndex,
                  'row_id': s.rowId,
                  'label': s.label,
                  'start': s.start,
                  'end': s.end,
                  'minutes': s.minutes,
                  'allowed_titles': s.onlyTags,
                  'is_short': s.short,
                },
            ],
          },
      ],
      'availabilities': [
        for (final u in people)
          if (u.id != null)
            {
              'employee_id': u.id!,
              'day_windows': {
                // Availability minus time off and other schedules, exactly
                // as the local algorithm sees it.
                for (final day in days)
                  if (workWindows(u.id!, day.date) case final wins?)
                    day.date: [
                      for (final w in wins) {'start': w.start, 'end': w.end},
                    ],
              },
            },
      ],
      'time_off': [
        for (final to in [...timeOff, ...overrides.extraOff])
          for (final day in days)
            if (to.covers(day.date))
              {
                'employee_id': to.userId,
                'date': day.date,
                'start': to.startMinute ?? 0,
                'end': to.endMinute ?? 1440,
                'approved': true,
                'requested': false,
              },
      ],
      'busy_elsewhere': [
        for (final entry in busyElsewhere.entries)
          for (final dateEntry in entry.value.entries)
            for (final w in dateEntry.value)
              {
                'employee_id': entry.key,
                'date': dateEntry.key,
                'start': w.start,
                'end': w.end,
              },
      ],
      'history': [
        for (final entry in history.entries)
          for (final (weekday, w) in entry.value)
            {
              'employee_id': entry.key,
              'weekday': weekday,
              'start': w.start,
              'end': w.end,
              'frequency': 1.0,
            },
      ],
      // Training shifts and pairs are already placed (fixed_assignments,
      // trainees), and people in training work only those.
      'training_plans': const [],
      'pinned_pairs': const [],
      'training_only': [
        for (final uid in trainingPlans.keys)
          if (byId.containsKey(uid)) uid,
      ],
      'trainees': {
        for (final e in _trainee.entries)
          if (_who[e.key] != null) e.key: e.value,
      },
      'directives': {
        'must_work': [
          for (final mw in overrides.mustWork)
            {
              'employee_id': mw.uid,
              'date': mw.date,
              if (mw.window != null)
                'window': {'start': mw.window!.start, 'end': mw.window!.end},
            },
        ],
        'off': [
          for (final to in overrides.extraOff)
            for (final day in days)
              if (to.covers(day.date))
                {'employee_id': to.userId, 'date': day.date},
        ],
        'apart': [for (final s in overrides.apart) s.toList()],
        // Meetings are already placed (their shifts are fixed below) and
        // admin time is added here after solving.
        'together': const [],
        'meetings': const [],
        'keep': {
          for (final entry in overrides.keep.entries)
            entry.key: [
              for (final (dateStr, w) in entry.value)
                {'date': dateStr, 'start': w.start, 'end': w.end},
            ],
        },
        'max_shifts_override': overrides.maxShifts,
        'fixed_assignments': {
          for (final s in slots)
            if (_who[s.id] != null) s.id: _who[s.id]!,
        },
        'admin_requests': const [],
      },
      'rules': {
        'max_shifts_per_week': rules.maxShiftsPerWeek,
        'max_hours_per_day':
            math.min(
              kMaxDayMinutes,
              rules.maxHoursPerDayOn ? rules.maxHoursPerDay * 60 : 16 * 60,
            ) /
            60,
        'min_rest_hours': rules.restOn ? rules.restHours : 0.0,
        'max_consecutive_days': rules.maxDaysInRowOn ? rules.maxDaysInRow : 7,
        'min_shift_hours': rules.minShiftHours,
        'max_shift_hours': rules.maxShiftHours,
        'minor_max_daily_hours_school': rules.minorMaxHoursPerDay,
        'minor_max_daily_hours_weekend': rules.minorMaxHoursPerDay,
        'minor_curfew_school_night': rules.minorLatestEnd,
        'school_nights': rules.schoolNights,
        'usual_shifts': rules.usualShifts,
        'consistency': rules.consistency,
        'day_night': rules.dayNight,
        'avoid_clopen': rules.avoidClopen,
        'training_flow_enabled': config.trainingFlowEnabled,
        'clopen_close_end_min': 21 * 60,
        'clopen_open_start_min': 7 * 60,
        'solver_timeout_seconds': 30,
        'num_search_workers': 8,
      },
    };
  }

  /// Parses the response returned by the FastAPI CP-SAT backend into Axis ScheduleDay models.
  Map<String, ScheduleDay> parseSolveResponseJson(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'UNKNOWN';
    if (status == 'INFEASIBLE') {
      final reasons =
          (data['infeasibility_reasons'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [];
      throw ScheduleSolveException(
        'CP-SAT solver reported INFEASIBLE',
        reasons,
      );
    }

    final daysList = data['days'] as List? ?? const [];
    final out = <String, ScheduleDay>{};
    // Who has each slot now: the solver's answer replaces everything (built
    // apart so a bad response leaves the engine as it was).
    final who = <String, String>{};

    for (final dayJson in daysList.whereType<Map<String, dynamic>>()) {
      final date = dayJson['date'] as String;
      final shiftsJson = dayJson['shifts'] as List? ?? const [];
      final shifts = <Shift>[];

      for (final sJson in shiftsJson.whereType<Map<String, dynamic>>()) {
        final shiftId = sJson['id'] as String? ?? newScheduleId();
        final userId = sJson['user_id'] as String? ?? '';
        final traineeId = sJson['trainee_id'] as String?;
        final piecesJson = sJson['pieces'] as List? ?? const [];
        final pieces = <ShiftPiece>[];

        for (final pJson in piecesJson.whereType<Map<String, dynamic>>()) {
          pieces.add(
            ShiftPiece(
              id: pJson['id'] as String? ?? newScheduleId(),
              rowId: pJson['row_id'] as String? ?? '',
              start: pJson['start'] as int? ?? 0,
              end: pJson['end'] as int? ?? 0,
              admin: pJson['admin'] == true,
            ),
          );
        }

        shifts.add(
          Shift(
            id: shiftId,
            userId: userId,
            traineeId: traineeId,
            pieces: pieces..sort((a, b) => a.start.compareTo(b.start)),
          ),
        );

        // Update internal slot mapping so inspection helpers remain accurate
        for (final p in pieces) {
          if (!p.admin) {
            final hit = slots
                .where(
                  (sl) =>
                      sl.date == date &&
                      sl.rowId == p.rowId &&
                      sl.start == p.start &&
                      sl.end == p.end,
                )
                .firstOrNull;
            if (hit != null) who[hit.id] = userId;
          }
        }
      }

      out[date] = (_dayByDate[date] ?? ScheduleDay(date: date)).copyWith(
        shifts: shifts..sort((a, b) => a.start.compareTo(b.start)),
      );
    }
    _who
      ..clear()
      ..addAll(who);
    return out;
  }

  /// Checks whether a remote CP-SAT solver backend should be attempted.
  ///
  /// In Web builds, if the app is hosted on a public domain (e.g. `team.axisoptic.com`)
  /// and the backend URL points to `127.0.0.1` or `localhost`, any fetch request will
  /// be blocked by browser Private Network Access (PNA) and Mixed Content policies,
  /// causing macOS to show a local network permission prompt ("Chrome wants to find and
  /// connect to devices on your local network") and throwing a ClientException.
  ///
  /// In that environment, remote solving is disabled unless a remote, accessible
  /// HTTPS backend URL is explicitly configured.
  bool get canSolveRemote {
    final urlStr = backendUrl ?? kDefaultScheduleBackendUrl;
    if (urlStr.isEmpty) return false;
    final uri = Uri.tryParse(urlStr);
    if (uri == null) return false;
    final isBackendLocal = uri.host == '127.0.0.1' || uri.host == 'localhost';
    if (kIsWeb) {
      final pageHost = Uri.base.host;
      final isPageLocal = pageHost == 'localhost' || pageHost == '127.0.0.1';
      if (isBackendLocal && !isPageLocal) return false;
    }
    return true;
  }

  /// Sends the scheduling problem to the Python FastAPI CP-SAT backend via HTTP POST.
  Future<Map<String, ScheduleDay>> solveRemote({
    String? backendUrl,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    final effectiveBackendUrl =
        backendUrl ?? this.backendUrl ?? kDefaultScheduleBackendUrl;
    final url = Uri.parse('$effectiveBackendUrl/solve_schedule');
    final payload = buildSolveRequestJson();

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw ScheduleSolveException(
        'Solver returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return parseSolveResponseJson(data);
  }

  /// Solves using remote CP-SAT backend, falling back to local heuristic execution if offline.
  Future<Map<String, ScheduleDay>> solve({
    String? backendUrl,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    if (!canSolveRemote) {
      return solveLocal();
    }
    try {
      return await solveRemote(backendUrl: backendUrl, timeout: timeout);
    } catch (_) {
      return solveLocal();
    }
  }

  /// Fallback local schedule build.
  Map<String, ScheduleDay> solveLocal() {
    buildLocal();
    return toDays();
  }

  /// Every step of the local build (no AI review). [admin]: add the admin
  /// time too.
  void buildLocal({bool admin = true}) {
    placeOverrides();
    placeTraining();
    checkTrainingPairs();
    fill(restrictedOnly: true, short: false);
    fill(short: false);
    fill(short: true);
    if (openSlots.isNotEmpty) repair();
    if (admin) placeAdmin();
  }

  /// How many people are at admin meeting [index] (0 if it isn't on).
  int meetingAttendance(int index) {
    final plan = _meetingPlans[index];
    if (plan == null) return 0;
    return plan.people
        .where((p) => _admin[p]?[plan.date]?.contains(plan.window) ?? false)
        .length;
  }

  /// Days admin meeting [index] could be reserved on.
  List<String> meetingDayOptions(int index) {
    final m = overrides.meetings[index];
    return [
      for (final d in days)
        if (m.date == null || m.date == d.date) d.date,
    ];
  }

  /// Template minutes someone is on the floor for (admin time inside a
  /// shift leaves that part of its slot uncovered).
  int get floorMinutes {
    var total = 0;
    for (final s in slots) {
      final uid = _who[s.id];
      if (uid == null) continue;
      var m = s.minutes;
      for (final a in _admin[uid]?[s.date] ?? const <TimeWindow>[]) {
        m -= math.max(0, math.min(a.end, s.end) - math.max(a.start, s.start));
      }
      total += m;
    }
    return total;
  }

  // ---------------------------------------------------------------------------
  // 1. Compile
  // ---------------------------------------------------------------------------

  final Map<String, List<TimeWindow>?> _windowCache = {};

  /// When [uid] can work on [date]: availability minus time off. Null = any
  /// time; empty = not that day. Someone working on another schedule that
  /// day can't work this one.
  List<TimeWindow>? workWindows(String uid, String date) {
    final key = '$uid@$date';
    if (_windowCache.containsKey(key)) return _windowCache[key];
    final List<TimeWindow>? out;
    if ((busyElsewhere[uid]?[date] ?? const []).isNotEmpty) {
      out = const [];
    } else {
      out = workWindowsFor(byId[uid]!, DateTime.parse(date), [
        ...timeOff,
        ...overrides.extraOff,
      ]);
    }
    return _windowCache[key] = out;
  }

  bool canWorkRange(String uid, String date, int start, int end) {
    final ws = workWindows(uid, date);
    return ws == null || ws.any((w) => w.containsRange(start, end));
  }

  bool fitsTags(String uid, List<String> tags) =>
      tags.isEmpty ||
      userFitsRow(byId[uid], ScheduleRow(id: '', allowedTitles: tags));

  /// People (who fit [tags]) free for all of [start]–[end] on [date].
  int _supply(String date, int start, int end, List<String> tags) => people
      .where(
        (u) =>
            !inTraining(u.id!) &&
            fitsTags(u.id!, tags) &&
            canWorkRange(u.id!, date, start, end),
      )
      .length;

  void _compile() {
    for (var d = 0; d < days.length; d++) {
      final day = days[d];
      for (final row in day.rows) {
        for (final w in row.windows) {
          for (final piece in _cut(day.date, w, row.allowedTitles)) {
            slots.add(
              Slot(
                id: 'S${_nextId++}',
                date: day.date,
                dayIndex: d,
                rowId: row.id,
                start: piece.start,
                end: piece.end,
                onlyTags: row.allowedTitles,
                label: row.label,
              ),
            );
          }
        }
      }
    }
  }

  /// Longest slot: a long shift, or less with "max hours a day" or "shift length range".
  int get _maxSlot {
    var maxM = kMaxSlotMinutes;
    if (rules.maxHoursPerDayOn) {
      maxM = math.min(maxM, (rules.maxHoursPerDay * 60).round());
    }
    if (rules.shiftLengthRangeOn) {
      maxM = math.min(maxM, (rules.maxShiftHours * 60).round());
    }
    return maxM;
  }

  /// Cuts a bar into shift-sized pieces, splitting where the most people
  /// can work both sides (then nearest the middle).
  List<TimeWindow> _cut(String date, TimeWindow w, List<String> tags) {
    if (w.minutes <= _maxSlot) return [w];
    final splitTarget = rules.shiftLengthRangeOn
        ? ((rules.minShiftHours + rules.maxShiftHours) / 2 * 60).round()
        : kSplitTargetMinutes;
    final minSplit = rules.shiftLengthRangeOn
        ? (rules.minShiftHours * 60).round()
        : kMinSplitMinutes;
    final pieces = (w.minutes / splitTarget).ceil();
    final ideal = w.start + w.minutes ~/ pieces;
    final lo = w.start + minSplit;
    final hi = w.end - minSplit;
    int? best;
    var bestScore = -1.0;
    for (var t = (lo / 30).ceil() * 30; t <= hi; t += 30) {
      final both = math.min(
        _supply(date, w.start, t, tags),
        _supply(date, t, w.end, tags),
      );
      final score = both - (t - ideal).abs() / 600; // supply first, then middle
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    if (best == null) return [w];
    return [
      ..._cut(date, TimeWindow(w.start, best), tags),
      ..._cut(date, TimeWindow(best, w.end), tags),
    ];
  }

  // ---------------------------------------------------------------------------
  // State helpers
  // ---------------------------------------------------------------------------

  List<Slot> slotsOf(String uid, String date) => [
    for (final s in slots)
      if (s.date == date && _who[s.id] == uid) s,
  ];

  /// Days [uid] works this week (this schedule, other schedules, days not
  /// being built, and days as a trainee).
  int daysWorked(String uid) {
    final dates = <String>{
      for (final s in slots)
        if (_who[s.id] == uid) s.date,
      ...?_traineeDates[uid],
      for (final e
          in (busyElsewhere[uid] ?? const <String, List<TimeWindow>>{}).entries)
        if (e.value.isNotEmpty) e.key,
    };
    return dates.length + (fixedShifts[uid] ?? 0);
  }

  int minutesOf(String uid) =>
      slots.where((s) => _who[s.id] == uid).fold(0, (a, s) => a + s.minutes);

  /// Usual shifts a week: their roster "avg shifts", else by designation.
  double target(String uid) {
    final u = byId[uid];
    return avgShiftsEstimate(u) ??
        switch (u?.designation) {
          'High School' => 3,
          'College' => 4,
          _ => 5,
        };
  }

  int maxShifts(String uid) =>
      overrides.maxShifts[uid] ??
      maxShiftsPerWeek(byId[uid], base: rules.maxShiftsPerWeek);

  bool isMinor(String uid) =>
      rules.minorsOn && byId[uid]?.designation == rules.minorDesignation;

  /// Most minutes [uid] can work in a day on [date].
  int dayCap(String uid, String date) {
    var cap = rules.maxHoursPerDayOn
        ? (rules.maxHoursPerDay * 60).round()
        : 16 * 60;
    if (isMinor(uid))
      cap = math.min(cap, (rules.minorMaxHoursPerDay * 60).round());
    return cap;
  }

  static String _shiftDate(String date, int days) =>
      dateKey(addDays(DateTime.parse(date), days));

  /// When [uid] works on [date] (this schedule and the others, admin too).
  List<TimeWindow> _workOn(String uid, String date) => [
    for (final s in slotsOf(uid, date)) s.window,
    ...?_admin[uid]?[date],
    ...?busyElsewhere[uid]?[date],
  ];

  /// Dates [uid] works this week (as a trainee too, and on other schedules).
  Set<String> _datesWorked(String uid) => {
    for (final s in slots)
      if (_who[s.id] == uid) s.date,
    ...?_traineeDates[uid],
    for (final e
        in (busyElsewhere[uid] ?? const <String, List<TimeWindow>>{}).entries)
      if (e.value.isNotEmpty) e.key,
  };

  /// Why the hard day-to-day rules block [uid] working [w] on [date] (rest
  /// between shifts, days in a row, minors' latest time, apart), or null.
  String? _dayRules(
    String uid,
    String date,
    TimeWindow w, {
    bool newDay = true,
  }) {
    if (isMinor(uid) &&
        rules.schoolNights.contains(DateTime.parse(date).weekday) &&
        w.end > rules.minorLatestEnd) {
      return 'a minor, can\'t work past ${formatMinutes(rules.minorLatestEnd)} on a school night';
    }
    if (rules.restOn) {
      final rest = (rules.restHours * 60).round();
      final before = _workOn(uid, _shiftDate(date, -1));
      if (before.isNotEmpty &&
          w.start + 1440 - before.map((b) => b.end).reduce(math.max) < rest) {
        return 'needs ${formatHours(rules.restHours)} hours off after the day before';
      }
      final after = _workOn(uid, _shiftDate(date, 1));
      if (after.isNotEmpty &&
          after.map((b) => b.start).reduce(math.min) + 1440 - w.end < rest) {
        return 'needs ${formatHours(rules.restHours)} hours off before the next day';
      }
    }
    if (newDay && rules.maxDaysInRowOn) {
      final worked = _datesWorked(uid)..add(date);
      var run = 1;
      for (var d = -1; worked.contains(_shiftDate(date, d)); d--) {
        run++;
      }
      for (var d = 1; worked.contains(_shiftDate(date, d)); d++) {
        run++;
      }
      if (run > rules.maxDaysInRow)
        return 'would work more than ${rules.maxDaysInRow} days in a row';
    }
    for (final group in overrides.apart) {
      if (!group.contains(uid)) continue;
      for (final other in group) {
        if (other != uid && _datesWorked(other).contains(date)) {
          return 'not on the same day as ${personName(byId[other], short: true)} (your instructions)';
        }
      }
    }
    return null;
  }

  /// Why [uid] can't take [slot] right now, or null if they can.
  /// [trainingStep]: placing one of their own training-flow shifts.
  String? blockReason(String uid, Slot slot, {bool trainingStep = false}) {
    if (inTraining(uid) && !trainingStep)
      return 'only on their training shifts this week';
    if (!fitsTags(uid, slot.onlyTags)) return 'not ${slot.onlyTags.join('/')}';
    if (_traineeDates[uid]?.contains(slot.date) ?? false)
      return 'training that day';
    if (!canWorkRange(uid, slot.date, slot.start, slot.end))
      return 'not available';
    final mine = slotsOf(uid, slot.date);
    if (mine.isEmpty) {
      if (daysWorked(uid) >= maxShifts(uid))
        return 'at their most shifts this week';
      if (slot.minutes > dayCap(uid, slot.date)) {
        return 'can work at most ${formatHours(dayCap(uid, slot.date) / 60)} hours a day';
      }
      return _dayRules(uid, slot.date, slot.window);
    }
    if (mine.any((s) => s.window.overlaps(slot.start, slot.end)))
      return 'already working then';
    if ((_admin[uid]?[slot.date] ?? const <TimeWindow>[]).any(
      (w) => w.overlaps(slot.start, slot.end),
    )) {
      return 'has admin time then';
    }
    final blocks = mergeWindows([
      ...mine.map((s) => s.window),
      ...?_admin[uid]?[slot.date],
      slot.window,
    ]);
    if (blocks.length > 1) return 'already working that day';
    if (blocks.first.minutes >
        math.min(kMaxDayMinutes, dayCap(uid, slot.date))) {
      return 'already working that day';
    }
    // Two long slots in one day only when the whole day is one shift, and
    // only as a last resort (see [repair]).
    if (!slot.short && mine.any((s) => !s.short)) {
      if (!_longDays) return 'already working that day';
      if (rules.shiftLengthRangeOn &&
          blocks.first.minutes > (rules.maxShiftHours * 60).round()) {
        return 'already working that day';
      }
    }
    return _dayRules(uid, slot.date, blocks.first, newDay: false);
  }

  void _assign(Slot slot, String uid) => _who[slot.id] = uid;
  void _unassign(Slot slot) => _who.remove(slot.id);

  bool get _hasRestrictedOpen =>
      slots.any((s) => s.restricted && _who[s.id] == null);

  /// Higher = better choice of [uid] for [slot].
  double score(String uid, Slot slot) {
    final u = byId[uid]!;
    var s = 0.0;
    final joining = slotsOf(uid, slot.date).isNotEmpty;
    if (joining) {
      s += slot.short ? 100 : -20;
    } else {
      if (rules.usualShifts) {
        final deficit = target(uid) - daysWorked(uid);
        s += deficit.clamp(-3, 5) * 12;
      }
      // A short bar on its own is a tiny shift: only when nobody can add it on.
      if (slot.short) s -= 80;
    }
    // Changes from the chat: keep the schedule as it is where possible.
    s += _kept(uid, slot) * 200;
    // The shifts they usually work (same weekday and time, last weeks).
    if (rules.consistency) s += habit(uid, slot) * 14;
    // Daytime people in the morning, Night people in the evening.
    final wt = (u.workingTime ?? '').toLowerCase();
    if (!rules.dayNight) {
      // Off.
    } else if (wt.startsWith('day')) {
      s += slot.start < 14 * 60 ? 6 : (slot.start >= 15 * 60 ? -6 : 0);
    } else if (wt.startsWith('night')) {
      s += slot.end > 17 * 60 ? 6 : (slot.end <= 14 * 60 ? -6 : 0);
    }
    // Keep title / tag people free for their own bars that day.
    if (!slot.restricted && _hasRestrictedOpen) {
      final saved = slots.any(
        (o) =>
            o.date == slot.date &&
            o.restricted &&
            _who[o.id] == null &&
            fitsTags(uid, o.onlyTags) &&
            canWorkRange(uid, o.date, o.start, o.end),
      );
      if (saved) s -= 25;
    }
    // No closing one night then opening the next morning.
    if (rules.avoidClopen) s -= _clopen(uid, slot) ? 15 : 0;
    // Fair hours (legacy).
    if (rules.fairHours) s -= minutesOf(uid) / 60 * 0.4;
    // Hours match usual shifts.
    if (rules.hoursMatchUsual) {
      final avgShift = rules.shiftLengthRangeOn
          ? (rules.minShiftHours + rules.maxShiftHours) / 2
          : 6.5;
      final expectedHours = target(uid) * avgShift;
      final currentHours = minutesOf(uid) / 60.0;
      final gap = expectedHours - currentHours;
      s += gap.clamp(-8.0, 8.0) * 1.5;
    }
    // Shift length range preference.
    if (rules.shiftLengthRangeOn && !joining && !slot.short) {
      final hours = slot.minutes / 60.0;
      if (hours >= rules.minShiftHours && hours <= rules.maxShiftHours) {
        s += 6.0;
      } else if (hours < rules.minShiftHours) {
        s -= (rules.minShiftHours - hours) * 4.0;
      } else if (hours > rules.maxShiftHours) {
        s -= (hours - rules.maxShiftHours) * 4.0;
      }
    }
    return s;
  }

  /// How much of [slot] [uid] has on the schedule now (0–1), for chat
  /// changes that should keep the rest of the week.
  double _kept(String uid, Slot slot) {
    final now = overrides.keep[uid];
    if (now == null) return 0;
    var covered = 0;
    for (final (date, w) in now) {
      if (date != slot.date) continue;
      final int overlap =
          math.min(w.end, slot.end) - math.max(w.start, slot.start);
      if (overlap > 0) covered += overlap;
    }
    return (covered / slot.minutes).clamp(0.0, 1.0);
  }

  /// How much [slot] looks like [uid]'s usual week, 0–1: in how many of
  /// the last weeks they worked that weekday, weighted by how much of the
  /// slot's time it covered.
  double habit(String uid, Slot slot) {
    final h = history[uid];
    if (h == null || h.isEmpty || historyWeeks <= 0) return 0;
    final weekday = DateTime.parse(slot.date).weekday;
    var sum = 0.0;
    for (final (wd, w) in h) {
      if (wd != weekday) continue;
      final overlap = math.min(w.end, slot.end) - math.max(w.start, slot.start);
      if (overlap > 0) sum += overlap / slot.minutes;
    }
    return (sum / historyWeeks).clamp(0.0, 1.0);
  }

  bool _clopen(String uid, Slot slot) {
    for (final o in slots) {
      if (_who[o.id] != uid || o.date == slot.date) continue;
      final gap = o.dayIndex - slot.dayIndex;
      if (gap == -1 && o.end >= 21 * 60 && slot.start <= 7 * 60) return true;
      if (gap == 1 && slot.end >= 21 * 60 && o.start <= 7 * 60) return true;
    }
    return false;
  }

  /// Counts the close-then-opens for [uid] across the week.
  int clopens(String uid) {
    var count = 0;
    for (final s in slots) {
      if (_who[s.id] != uid) continue;
      for (final next in slots) {
        if (_who[next.id] != uid) continue;
        if (next.dayIndex - s.dayIndex == 1 &&
            s.end >= 21 * 60 &&
            next.start <= 7 * 60) {
          count++;
        }
      }
    }
    return count;
  }

  /// Valid people for [slot] right now, best first.
  List<String> candidates(Slot slot, {String? except}) {
    final out = [
      for (final u in people)
        if (u.id != except && blockReason(u.id!, slot) == null) u.id!,
    ];
    final scores = {for (final id in out) id: score(id, slot)};
    out.sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return out;
  }

  // ---------------------------------------------------------------------------
  // 1b. The manager's instructions (they override the rules)
  // ---------------------------------------------------------------------------

  String _who2(String uid) => personName(byId[uid], short: true);
  String _day(String date) {
    final d = DateTime.parse(date);
    return '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]} ${d.day}';
  }

  /// What happened to each of the manager's requests: (source, done?, what).
  final List<({String source, bool ok, String text})> outcomes = [];

  void _outcome(String source, bool ok, String text) =>
      outcomes.add((source: source, ok: ok, text: text));

  /// Must-work days, pairs and meetings, placed before anything else.
  void placeOverrides() {
    for (final m in overrides.mustWork) {
      if (!byId.containsKey(m.uid) || !_dayByDate.containsKey(m.date)) continue;
      final want = m.window;
      bool covers(Slot s) =>
          want == null || s.window.overlaps(want.start, want.end);
      if (slotsOf(m.uid, m.date).any(covers)) {
        _outcome(m.source, true, '${_who2(m.uid)} works ${_day(m.date)}.');
        continue;
      }
      if (slotsOf(m.uid, m.date).isNotEmpty) {
        _outcome(
          m.source,
          false,
          '${_who2(m.uid)} already works ${_day(m.date)} at another time.',
        );
        continue;
      }
      Slot? best;
      var bestKey = -1;
      for (final s in slots) {
        if (s.date != m.date || _who[s.id] != null || s.short || !covers(s))
          continue;
        final int overlap = want == null
            ? s.minutes
            : math.min(want.end, s.end) - math.max(want.start, s.start);
        final key = overlap * 2 + (fitsTags(m.uid, s.onlyTags) ? 1 : 0);
        if (key > bestKey) {
          bestKey = key;
          best = s;
        }
      }
      if (best == null) {
        _outcome(
          m.source,
          false,
          'No open slot on ${_day(m.date)} for ${_who2(m.uid)}.',
        );
        continue;
      }
      _assign(best, m.uid);
      _pinned.add(best.id);
      _outcome(
        m.source,
        true,
        '${_who2(m.uid)} works ${_day(m.date)} ${formatRange(best.start, best.end)}.',
      );
    }
    // Pairs for people who aren't in training (trainees in training get
    // theirs with their training shifts).
    for (final p in overrides.pairs) {
      if (inTraining(p.trainee) ||
          !byId.containsKey(p.trainee) ||
          !byId.containsKey(p.trainer)) {
        continue;
      }
      Slot? best;
      for (final slot in slots) {
        if (_who[slot.id] != null || slot.minutes < kMinSplitMinutes) continue;
        if (p.date != null && slot.date != p.date) continue;
        if (slotsOf(p.trainee, slot.date).isNotEmpty) continue;
        if (_traineeDates[p.trainee]?.contains(slot.date) ?? false) continue;
        if (!canWorkRange(p.trainee, slot.date, slot.start, slot.end)) continue;
        if (blockReason(p.trainer, slot) != null) continue;
        best = slot;
        break;
      }
      if (best == null) {
        _outcome(
          p.source,
          false,
          'No shift ${_who2(p.trainer)} and ${_who2(p.trainee)} can both work'
          '${p.date == null ? '' : ' on ${_day(p.date!)}'}.',
        );
        continue;
      }
      _assign(best, p.trainer);
      _trainee[best.id] = p.trainee;
      _trainingSlots.add(best.id);
      (_traineeDates[p.trainee] ??= {}).add(best.date);
      _outcome(
        p.source,
        true,
        '${_who2(p.trainer)} trains ${_who2(p.trainee)} ${_day(best.date)} '
        '${formatRange(best.start, best.end)}.',
      );
    }
    for (var i = 0; i < overrides.meetings.length; i++) {
      final meeting = overrides.meetings[i];
      final people = meeting.people.where(byId.containsKey).toList();
      if (people.length < 2) continue;
      if (meeting.asAdmin) {
        // Reserved now (so everyone gets a shift that touches it) or after
        // filling; reported in placeAdmin().
        final day = meetingDays[i];
        if (day != null && (meeting.date == null || meeting.date == day)) {
          _meetingPlans[i] = _planAdminMeeting(people, meeting.minutes, day);
        }
        continue;
      }
      final placed = _placeMeeting(people, meeting.minutes, meeting.date);
      _outcome(
        meeting.source,
        placed != null,
        placed ??
            'No ${formatHours(meeting.minutes / 60)}-hour stretch when '
                '${people.map(_who2).join(', ')} can all meet on the floor'
                '${meeting.date == null ? ' this week' : ' on ${_day(meeting.date!)}'}.',
      );
    }
    // Admin on a given day needs a shift that day to sit next to.
    for (final r in overrides.admin) {
      if (r.date == null || r.everyDay || !byId.containsKey(r.uid)) continue;
      if (!_dayByDate.containsKey(r.date) || slotsOf(r.uid, r.date!).isNotEmpty)
        continue;
      _giveShiftFor(r.uid, r.date!, r.minutes);
    }
  }

  /// Gives [uid] an open slot on [date] (keeping every rule) that [minutes]
  /// of admin can sit next to, best admin spot first. Pinned. Null if none.
  Slot? _giveShiftFor(String uid, String date, int minutes) {
    (Slot, double)? best;
    for (final s in slots) {
      if (s.date != date || _who[s.id] != null || s.short) continue;
      if (blockReason(uid, s) != null) continue;
      _assign(s, uid);
      final w = _bestAdminWindow(uid, date, minutes);
      _unassign(s);
      if (w == null) continue;
      final key = w.score + habit(uid, s) * 20;
      if (best == null || key > best.$2) best = (s, key);
    }
    if (best == null) return null;
    _assign(best.$1, uid);
    _pinned.add(best.$1.id);
    return best.$1;
  }

  /// Did the forced pairs for people in training happen? (Checked after
  /// their training shifts are placed.)
  void checkTrainingPairs() {
    for (final p in overrides.pairs) {
      if (!inTraining(p.trainee)) continue;
      final hit = _trainee.entries
          .where((e) => e.value == p.trainee && _who[e.key] == p.trainer)
          .map((e) => slotById(e.key))
          .nonNulls
          .where((s) => p.date == null || s.date == p.date)
          .firstOrNull;
      _outcome(
        p.source,
        hit != null,
        hit != null
            ? '${_who2(p.trainer)} trains ${_who2(p.trainee)} ${_day(hit.date)} ${formatRange(hit.start, hit.end)}.'
            : 'No shift ${_who2(p.trainer)} and ${_who2(p.trainee)} can both work'
                  '${p.date == null ? '' : ' on ${_day(p.date!)}'}.',
      );
    }
  }

  // --- Admin time --------------------------------------------------------------
  //
  // Admin time is always joined onto a floor shift: right before or after it
  // (the shift gets longer and the floor stays covered) or, when that would
  // break a rule, inside it (that part of the shift is off the floor). Never
  // a shift of its own, never with a gap.

  /// Admin time added, by person and date.
  final Map<String, Map<String, List<TimeWindow>>> _admin = {};

  /// Admin meetings reserved before filling: meeting index → the plan, or
  /// null when no time worked.
  final Map<int, _MeetingPlan?> _meetingPlans = {};

  /// Longest [uid] can work in one stretch on [date].
  int _dayLimit(String uid, String date) =>
      math.min(kMaxDayMinutes, dayCap(uid, date));

  /// [uid]'s work on [date] (floor and admin) as one stretch, or null when
  /// they aren't on.
  TimeWindow? _stretch(String uid, String date) {
    final ws = [
      for (final s in slotsOf(uid, date)) s.window,
      ...?_admin[uid]?[date],
    ];
    if (ws.isEmpty) return null;
    return TimeWindow(
      ws.map((w) => w.start).reduce(math.min),
      ws.map((w) => w.end).reduce(math.max),
    );
  }

  /// Floor minutes [w] takes from [uid]'s shift on [date] as admin time, or
  /// null when [w] can't join onto their shift (not on that day, a gap,
  /// availability, most hours a day, rest, a training shift, other admin).
  int? _adminFit(String uid, String date, TimeWindow w) {
    final floor = slotsOf(uid, date);
    if (floor.isEmpty) return null;
    final span = _stretch(uid, date)!;
    if (w.start > span.end || w.end < span.start) return null;
    if (w.start < 0 || w.end > kMaxScheduleMinute) return null;
    if ((_admin[uid]?[date] ?? const <TimeWindow>[]).any(
      (a) => a.overlaps(w.start, w.end),
    )) {
      return null;
    }
    if (!canWorkRange(uid, date, w.start, w.end)) return null;
    final whole = TimeWindow(
      math.min(span.start, w.start),
      math.max(span.end, w.end),
    );
    if (whole.minutes > _dayLimit(uid, date)) return null;
    if ((whole.start < span.start || whole.end > span.end) &&
        _dayRules(uid, date, whole, newDay: false) != null) {
      return null;
    }
    var carved = 0;
    for (final s in floor) {
      final int overlap = math.min(s.end, w.end) - math.max(s.start, w.start);
      if (overlap <= 0) continue;
      if (_trainee.containsKey(s.id)) return null; // not while training someone
      carved += overlap;
    }
    return carved;
  }

  /// Midday is best for admin; very early or late is bad.
  static double _timeOfDayScore(TimeWindow w) {
    var s = 0.0;
    if (w.start >= 10 * 60 && w.end <= 16 * 60 + 30) {
      s += 120;
      if (w.start >= 11 * 60 && w.end <= 15 * 60) s += 60;
    }
    if (w.start < 8 * 60 + 30) s -= (8 * 60 + 30 - w.start) * 4.0;
    if (w.end > 20 * 60) s -= (w.end - 20 * 60) * 4.0;
    return s;
  }

  /// Cost of admin time that takes [carved] minutes off the floor and adds
  /// the rest of [minutes] onto the shift. Off the floor leaves the template
  /// short-handed, so it costs more than any time of day is worth: inside
  /// the shift only when coming in earlier or staying later isn't possible.
  static double _floorCost(int minutes, int carved) =>
      -carved * 6.0 - (minutes - carved) * 0.25;

  /// The best [minutes] of admin joined onto [uid]'s shift on [date] (right
  /// after, right before, or inside it), or null.
  ({TimeWindow window, double score})? _bestAdminWindow(
    String uid,
    String date,
    int minutes,
  ) {
    final span = _stretch(uid, date);
    if (span == null) return null;
    final starts = <int>{
      span.end, // right after
      span.start - minutes, // right before
      span.start, // inside, at the start
      span.end - minutes, // inside, at the end
      for (
        var t = (span.start / 30).ceil() * 30;
        t + minutes <= span.end;
        t += 30
      )
        t,
    };
    ({TimeWindow window, double score})? best;
    for (final t in starts) {
      final w = TimeWindow(t, t + minutes);
      final carved = _adminFit(uid, date, w);
      if (carved == null) continue;
      // Inside: at an end keeps the floor time in one piece.
      final edge = carved > 0 && (t == span.start || w.end == span.end)
          ? 20
          : 0;
      final s = _timeOfDayScore(w) + _floorCost(minutes, carved) + edge;
      if (best == null || s > best.score) best = (window: w, score: s);
    }
    return best;
  }

  /// Adds [minutes] of admin for [uid] on the best of [dates] (lighter days
  /// first). Returns (date, window, before / after / during) or null.
  (String, TimeWindow, String)? _addAdmin(
    String uid,
    int minutes,
    Iterable<String> dates,
  ) {
    (String, TimeWindow, double)? best;
    for (final d in dates) {
      final opt = _bestAdminWindow(uid, d, minutes);
      if (opt == null) continue;
      final key = opt.score - _dayMinutes(uid, d) / 10;
      if (best == null || key > best.$3) best = (d, opt.window, key);
    }
    if (best == null) return null;
    final (d, w, _) = best;
    final span = _stretch(uid, d)!;
    ((_admin[uid] ??= {})[d] ??= []).add(w);
    final how = w.start >= span.end
        ? 'right after'
        : (w.end <= span.start ? 'right before' : 'during');
    return (d, w, how);
  }

  /// Adds the requested admin time: admin meetings (reserved before the
  /// schedule was filled) and each person's admin, joined onto their shifts.
  void placeAdmin() {
    _dropLooseAdmin();
    for (var i = 0; i < overrides.meetings.length; i++) {
      final meeting = overrides.meetings[i];
      if (!meeting.asAdmin) continue;
      final people = meeting.people.where(byId.containsKey).toList();
      if (people.length < 2) continue;
      // Not reserved before filling: next to the shifts people have now.
      if (!_meetingPlans.containsKey(i)) {
        _meetingPlans[i] = _planAdminMeeting(
          people,
          meeting.minutes,
          meeting.date,
        );
      }
      _outcome(
        meeting.source,
        _meetingPlans[i] != null,
        _meetingText(people, meeting.minutes, meeting.date, _meetingPlans[i]),
      );
    }

    for (final r in overrides.admin) {
      if (!byId.containsKey(r.uid)) continue;
      final what = '${formatHours(r.minutes / 60)} h admin for ${_who2(r.uid)}';
      final dates = [
        for (final d in days)
          if ((r.date == null || r.date == d.date) &&
              slotsOf(r.uid, d.date).isNotEmpty)
            d.date,
      ];
      final when = r.date == null ? ' this week' : ' on ${_day(r.date!)}';
      if (dates.isEmpty) {
        _outcome(
          r.source,
          false,
          '$what: they aren\'t on the schedule$when, and admin needs a shift to join onto.',
        );
        continue;
      }
      if (r.everyDay) {
        final placed = <String>[];
        final missed = <String>[];
        for (final d in dates) {
          (_addAdmin(r.uid, r.minutes, [d]) != null ? placed : missed).add(
            _day(d),
          );
        }
        _outcome(
          r.source,
          placed.isNotEmpty,
          placed.isEmpty
              ? '$what each day: no room next to their shifts (availability or most hours a day).'
              : '$what each day they work: ${placed.join(', ')}'
                    '${missed.isEmpty ? '' : ' (not ${missed.join(', ')}: no room next to the shift)'}.',
        );
        continue;
      }
      final placed = _addAdmin(r.uid, r.minutes, dates);
      _outcome(
        r.source,
        placed != null,
        placed != null
            ? '$what: ${_day(placed.$1)} ${formatRange(placed.$2.start, placed.$2.end)}, ${placed.$3} their shift.'
            : '$what: no room right before, after, or during their shift$when (availability or most hours a day).',
      );
    }
  }

  /// Safety net: admin time that isn't joined onto a floor shift (its shift
  /// moved after it was planned) is taken off.
  void _dropLooseAdmin() {
    for (final MapEntry(key: uid, value: byDate) in _admin.entries) {
      for (final date in byDate.keys.toList()) {
        final floor = [for (final s in slotsOf(uid, date)) s.window];
        if (floor.isEmpty) {
          byDate.remove(date);
          continue;
        }
        final blocks = mergeWindows([...floor, ...byDate[date]!]);
        if (blocks.length == 1) continue;
        final main = blocks.firstWhere(
          (b) => floor.any((f) => b.containsRange(f.start, f.end)),
        );
        byDate[date] = [
          for (final a in byDate[date]!)
            if (main.containsRange(a.start, a.end)) a,
        ];
      }
    }
  }

  int _dayMinutes(String uid, String date) => mergeWindows([
    for (final s in slotsOf(uid, date)) s.window,
    ...?_admin[uid]?[date],
  ]).fold(0, (a, w) => a + w.minutes);

  /// Finds the day and time for an admin meeting where the most of [people]
  /// can attend joined onto a shift (giving an open slot to those who aren't
  /// on yet), preferring midday and staying later or coming in earlier over
  /// leaving the floor. Reserves it: the new shifts are pinned and the time
  /// is everyone's admin. Null when fewer than two can make any time.
  _MeetingPlan? _planAdminMeeting(
    List<String> people,
    int minutes,
    String? date,
  ) {
    ({String date, TimeWindow window, Map<String, Slot?> plan, double score})?
    best;
    for (final day in days) {
      if (date != null && day.date != date) continue;
      final daySlots = [
        for (final s in slots)
          if (s.date == day.date) s,
      ];
      if (daySlots.isEmpty) continue;
      final from =
          ((daySlots.map((s) => s.start).reduce(math.min) - minutes) / 30)
              .floor() *
          30;
      final to = daySlots.map((s) => s.end).reduce(math.max) + minutes;
      for (var t = math.max(0, from); t + minutes <= to; t += 30) {
        final w = TimeWindow(t, t + minutes);
        final plan = <String, Slot?>{}; // null = joins the shift they have
        final used = <String>{};
        var total = 0.0;
        for (final p in people) {
          if (slotsOf(p, day.date).isNotEmpty) {
            final carved = _adminFit(p, day.date, w);
            if (carved == null) continue;
            plan[p] = null;
            total += _floorCost(minutes, carved);
            continue;
          }
          // Not on yet: the open slot that fits them and the meeting best,
          // their own title / tag bars first (leaders on leader slots), so
          // the shift is one they'd get anyway.
          (Slot, int, double)? pick;
          for (final s in daySlots) {
            if (_who[s.id] != null || used.contains(s.id) || s.short) continue;
            if (s.start > w.end || s.end < w.start) continue;
            if (blockReason(p, s) != null) continue;
            _assign(s, p);
            final carved = _adminFit(p, day.date, w);
            final fit = carved == null
                ? 0.0
                : score(p, s) +
                      (s.restricted ? 1000 : 0) +
                      _floorCost(minutes, carved);
            _unassign(s);
            if (carved == null) continue;
            if (pick == null || fit > pick.$3) pick = (s, carved, fit);
          }
          if (pick == null) continue;
          plan[p] = pick.$1;
          used.add(pick.$1.id);
          total += _floorCost(minutes, pick.$2);
        }
        if (plan.length < math.min(2, people.length)) continue;
        total += plan.length * 1000 + _timeOfDayScore(w);
        if (best == null || total > best.score) {
          best = (date: day.date, window: w, plan: plan, score: total);
        }
      }
    }
    if (best == null) return null;
    best.plan.forEach((p, s) {
      if (s != null) {
        _assign(s, p);
        _pinned.add(s.id);
      }
      ((_admin[p] ??= {})[best!.date] ??= []).add(best.window);
    });
    // Their admin keeps the shifts they joined onto from moving.
    for (final p in best.plan.keys) {
      for (final s in slotsOf(p, best.date)) {
        _pinned.add(s.id);
      }
    }
    return (
      date: best.date,
      window: best.window,
      people: best.plan.keys.toList(),
    );
  }

  /// What happened to an admin meeting, for the report.
  String _meetingText(
    List<String> people,
    int minutes,
    String? date,
    _MeetingPlan? plan,
  ) {
    final attending = plan == null
        ? const <String>[]
        : [
            for (final p in plan.people)
              if (_admin[p]?[plan.date]?.contains(plan.window) ?? false) p,
          ];
    if (plan == null || attending.length < math.min(2, people.length)) {
      return 'No ${formatHours(minutes / 60)}-hour time when '
          '${people.map(_who2).join(', ')} can meet next to their shifts'
          '${date == null ? ' this week' : ' on ${_day(date)}'}.';
    }
    final missed = people.where((p) => !attending.contains(p)).toList();
    return 'Meeting (admin) ${_day(plan.date)} ${formatRange(plan.window.start, plan.window.end)}: '
        '${missed.isEmpty ? 'everyone' : attending.map(_who2).join(', ')} on, joined onto their shifts'
        '${missed.isEmpty ? '' : ' (${missed.map(_who2).join(', ')}: no shift that day they could join it onto)'}.';
  }

  /// Puts everyone in [people] on at the same time for [minutes]: each one
  /// keeps a slot they already have, or gets an open one that covers it.
  String? _placeMeeting(List<String> people, int minutes, String? date) {
    for (final day in days) {
      if (date != null && day.date != date) continue;
      final daySlots = slots.where((s) => s.date == day.date).toList();
      if (daySlots.isEmpty) continue;
      final from = daySlots.map((s) => s.start).reduce(math.min);
      final to = daySlots.map((s) => s.end).reduce(math.max);
      for (var t = from; t + minutes <= to; t += 30) {
        final w = TimeWindow(t, t + minutes);
        final plan = <String, Slot?>{}; // null = already on then
        final used = <String>{};
        for (final p in people) {
          if (slotsOf(
            p,
            day.date,
          ).any((s) => s.window.containsRange(w.start, w.end))) {
            plan[p] = null;
            continue;
          }
          final pick = daySlots
              .where(
                (s) =>
                    _who[s.id] == null &&
                    !used.contains(s.id) &&
                    s.window.containsRange(w.start, w.end) &&
                    blockReason(p, s) == null,
              )
              .firstOrNull;
          if (pick == null) break;
          plan[p] = pick;
          used.add(pick.id);
        }
        if (plan.length != people.length) continue;
        plan.forEach((p, s) {
          if (s != null) _assign(s, p);
        });
        return 'Meeting ${_day(day.date)} ${formatRange(w.start, w.end)}: '
            '${people.map(_who2).join(', ')} are all on then.';
      }
    }
    return null;
  }

  bool _keptDay(String uid, String date) =>
      overrides.keep[uid]?.any((k) => k.$1 == date) ?? false;

  bool _noTraining(String uid, String date) => overrides.noTraining.any(
    (n) => n.uid == uid && (n.date == null || n.date == date),
  );

  // ---------------------------------------------------------------------------
  // 2. Training
  // ---------------------------------------------------------------------------

  /// Gives everyone in training their next training-flow shifts this week,
  /// in order, on later and later days, as many as fit (trainers free,
  /// their availability, their most shifts a week). Returns how many.
  int placeTraining() {
    var placed = 0;
    final trainees = trainingPlans.keys.toList()
      ..sort((a, b) => _daysFree(a).compareTo(_daysFree(b)));
    for (final t in trainees) {
      final plan = trainingPlans[t]!;
      final got = <(String, bool)>[];
      var lastDay = -1;
      String? why;
      for (final step in plan) {
        final withTrainer = step.withTrainer;
        if (daysWorked(t) >= maxShifts(t)) {
          why = 'they\'d go over their most shifts this week';
          break;
        }
        // Earliest day after their last training shift (leaves room for the
        // rest), then the best choice that day.
        (Slot, String)? best;
        (int, double)? bestKey;
        for (final slot in slots) {
          if (slot.dayIndex <= lastDay || _who[slot.id] != null) continue;
          if (slot.minutes < kMinSplitMinutes) continue;
          if (!canWorkRange(t, slot.date, slot.start, slot.end)) continue;
          if (_noTraining(t, slot.date)) continue;
          // Someone else is already training on that position then.
          if (_positionTaken(step.positionId, slot)) continue;
          // Chat changes: keep their training on the days it's on now.
          final dayKey = slot.dayIndex - (_keptDay(t, slot.date) ? 100 : 0);
          if (!withTrainer) {
            if (blockReason(t, slot, trainingStep: true) != null) continue;
            final key = (dayKey, score(t, slot));
            if (bestKey == null || _earlierOrBetter(key, bestKey)) {
              bestKey = key;
              best = (slot, t);
            }
            continue;
          }
          if (slotsOf(t, slot.date).isNotEmpty) continue;
          if (_traineeDates[t]?.contains(slot.date) ?? false) continue;
          // Your instructions can pick the trainer (even a non-trainer).
          final forced = overrides.pairs.where((p) => p.trainee == t).toList();
          if (forced.isNotEmpty &&
              !forced.any((p) => p.date == null || p.date == slot.date)) {
            continue;
          }
          for (final u in people) {
            final c = u.id!;
            if (c == t || inTraining(c)) continue;
            if (forced.isNotEmpty
                ? !forced.any((p) => p.trainer == c)
                : !canTrain(u, config)) {
              continue;
            }
            if (_noTraining(c, slot.date)) continue;
            if (_trainee.entries.any(
              (e) => _who[e.key] == c && slotById(e.key)?.date == slot.date,
            )) {
              continue; // one trainee per trainer a day
            }
            if (blockReason(c, slot) != null) continue;
            final hasTag = (u.additionalTags ?? const []).any(
              config.trainerTags.contains,
            );
            final key = (dayKey, score(c, slot) + (hasTag ? 10 : 0));
            if (bestKey == null || _earlierOrBetter(key, bestKey)) {
              bestKey = key;
              best = (slot, c);
            }
          }
        }
        if (best == null) {
          why = withTrainer
              ? 'no trainer is free for a whole shift when they are'
              : 'no open shift fits them';
          if (step.positionId != null &&
              _training.any((x) => x.positionId == step.positionId)) {
            why = '$why (or someone else is training on that position then)';
          }
          if (lastDay >= 0) why = '$why after ${_dayName(lastDay)}';
          break;
        }
        final (slot, who) = best;
        _assign(slot, who);
        _trainingSlots.add(slot.id);
        (_traineeDates[t] ??= {}).add(slot.date);
        if (withTrainer) {
          _trainee[slot.id] = t;
        }
        got.add((slot.date, withTrainer));
        if (step.positionId != null) {
          _training.add((
            date: slot.date,
            positionId: step.positionId!,
            window: slot.window,
          ));
        }
        lastDay = slot.dayIndex;
        placed++;
      }
      if (got.isEmpty && why != null && _daysFree(t) == 0) {
        why = 'they can\'t work any of the days being built';
      }
      training.add((traineeId: t, wanted: plan.length, shifts: got, why: why));
    }
    return placed;
  }

  /// Training shifts placed so far, by position (one person per position).
  final List<({String date, String positionId, TimeWindow window})> _training =
      [];

  bool _positionTaken(String? positionId, Slot slot) =>
      positionId != null &&
      _training.any(
        (x) =>
            x.positionId == positionId &&
            x.date == slot.date &&
            x.window.overlaps(slot.start, slot.end),
      );

  static bool _earlierOrBetter((int, double) a, (int, double) b) =>
      a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 > b.$2);

  String _dayName(int dayIndex) {
    final d = DateTime.parse(days[dayIndex].date);
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday -
        1];
  }

  int _daysFree(String uid) =>
      days.where((d) => workWindows(uid, d.date)?.isNotEmpty ?? true).length;

  // ---------------------------------------------------------------------------
  // 3–4. Filling
  // ---------------------------------------------------------------------------

  /// Fills open slots, scarcest first. [restrictedOnly]: title / tag bars;
  /// [short]: short bars only (else long ones only). Returns how many.
  int fill({bool restrictedOnly = false, required bool short}) {
    bool wanted(Slot s) =>
        _who[s.id] == null &&
        s.short == short &&
        (!restrictedOnly || s.restricted);
    final cand = <String, Set<String>>{
      for (final s in slots)
        if (wanted(s)) s.id: candidates(s).toSet(),
    };
    var filled = 0;
    while (true) {
      Slot? pick;
      for (final s in slots) {
        final c = cand[s.id];
        if (c == null || c.isEmpty || _who[s.id] != null) continue;
        if (pick == null) {
          pick = s;
          continue;
        }
        final a = c.length, b = cand[pick.id]!.length;
        final better =
            a < b ||
            (a == b && s.restricted && !pick.restricted) ||
            (a == b &&
                s.restricted == pick.restricted &&
                s.minutes > pick.minutes);
        if (better) pick = s;
      }
      if (pick == null) break;
      final options = cand[pick.id]!.toList()
        ..sort((a, b) => score(b, pick!).compareTo(score(a, pick)));
      final uid = options.first;
      _assign(pick, uid);
      filled++;
      cand.remove(pick.id);
      // Only this person's options can have changed.
      for (final e in cand.entries) {
        if (e.value.contains(uid) &&
            blockReason(uid, slotById(e.key)!) != null) {
          e.value.remove(uid);
        }
      }
    }
    return filled;
  }

  // ---------------------------------------------------------------------------
  // 5. Holes
  // ---------------------------------------------------------------------------

  /// Fixes open slots with swaps, moves and splits. Returns how many slots
  /// (or parts of slots) got someone.
  int repair() {
    var fixed = 0;
    for (var round = 0; round < 3; round++) {
      var progress = false;
      final open = slots.where((s) => _who[s.id] == null).toList()
        ..sort((a, b) => b.minutes.compareTo(a.minutes));
      for (final s in open) {
        if (_who[s.id] != null || !slots.contains(s)) continue;
        if (_direct(s) ||
            _swapIn(s) ||
            _moveDay(s) ||
            _shortViaNeighbour(s) ||
            _split(s)) {
          fixed++;
          progress = true;
        }
      }
      if (!progress) break;
    }
    // Last resort: someone already on that day stays on for (part of) the
    // slot next to their shift, up to the most hours a day.
    _longDays = true;
    try {
      final open = slots.where((s) => _who[s.id] == null).toList()
        ..sort((a, b) => b.minutes.compareTo(a.minutes));
      for (final s in open) {
        if (_who[s.id] != null || !slots.contains(s)) continue;
        if (_direct(s) || _split(s)) fixed++;
      }
    } finally {
      _longDays = false;
    }
    return fixed;
  }

  /// Set while [repair] lets someone work two long slots back to back.
  bool _longDays = false;

  bool _direct(Slot s) {
    final c = candidates(s);
    if (c.isEmpty) return false;
    _assign(s, c.first);
    return true;
  }

  /// Someone free for [s] but already working another long slot that day:
  /// move them here and give their slot to someone free.
  bool _swapIn(Slot s) {
    for (final u in people) {
      final p = u.id!;
      if (inTraining(p) || !fitsTags(p, s.onlyTags)) continue;
      if (!canWorkRange(p, s.date, s.start, s.end)) continue;
      final mine = slotsOf(p, s.date);
      if (mine.length != 1 || _locked(mine.first.id)) continue;
      final t = mine.first;
      _unassign(t);
      if (blockReason(p, s) == null) {
        _assign(s, p);
        final q = candidates(t);
        if (q.isNotEmpty) {
          _assign(t, q.first);
          return true;
        }
        _unassign(s);
      }
      _assign(t, p);
    }
    return false;
  }

  /// Someone at their weekly most who could work [s]: give one of their
  /// other days to someone free, and move them here.
  bool _moveDay(Slot s) {
    for (final u in people) {
      final p = u.id!;
      if (inTraining(p) || !fitsTags(p, s.onlyTags)) continue;
      if (!canWorkRange(p, s.date, s.start, s.end)) continue;
      if (slotsOf(p, s.date).isNotEmpty || daysWorked(p) < maxShifts(p))
        continue;
      for (final other
          in slots.where((o) => _who[o.id] == p && o.date != s.date).toList()) {
        if (_locked(other.id) || slotsOf(p, other.date).length != 1) continue;
        _unassign(other);
        final q = candidates(other);
        if (q.isNotEmpty && blockReason(p, s) == null) {
          _assign(other, q.first);
          if (blockReason(p, s) == null) {
            _assign(s, p);
            return true;
          }
          _unassign(other);
        }
        _assign(other, p);
      }
    }
    return false;
  }

  /// A short bar next to someone's slot who can't add it on: give both to
  /// someone free who can.
  bool _shortViaNeighbour(Slot s) {
    if (!s.short) return false;
    for (final t in slots) {
      if (t.date != s.date || t.id == s.id) continue;
      if (t.end != s.start && t.start != s.end) continue;
      final a = _who[t.id];
      if (a == null ||
          inTraining(a) ||
          _locked(t.id) ||
          slotsOf(a, t.date).length != 1) {
        continue;
      }
      _unassign(t);
      for (final q in candidates(t, except: a)) {
        _assign(t, q);
        if (blockReason(q, s) == null) {
          _assign(s, q);
          return true;
        }
        _unassign(t);
      }
      _assign(t, a);
    }
    return false;
  }

  int get _minPartMinutes => rules.shiftLengthRangeOn
      ? math.max(3 * 60, (rules.minShiftHours * 60).round())
      : kMinPartMinutes;

  /// Nobody can work all of [s]: split it so two people share it, or give
  /// part of it to one person and leave the rest open.
  bool _split(Slot s) {
    final minPart = _minPartMinutes;
    if (s.short || s.minutes < 2 * minPart) return _partial(s);
    (int, String, String)? best;
    for (var t = s.start + minPart; t <= s.end - minPart; t += 30) {
      final a = s.part('x', s.start, t);
      final b = s.part('y', t, s.end);
      final ca = candidates(a);
      if (ca.isEmpty) continue;
      final cb = candidates(b);
      if (cb.isEmpty) continue;
      String? bestA;
      String? bestB;
      for (final pa in ca) {
        for (final pb in cb) {
          if (pb != pa) {
            bestA = pa;
            bestB = pb;
            break;
          }
        }
        if (bestA != null) break;
      }
      if (bestA == null || bestB == null) continue;
      final balance = math.min(t - s.start, s.end - t);
      if (best == null || balance > best.$1) best = (t, bestA, bestB);
    }
    if (best == null) return _partial(s);
    final i = slots.indexOf(s);
    final a = s.part('S${_nextId++}', s.start, best.$1);
    final b = s.part('S${_nextId++}', best.$1, s.end);
    slots
      ..removeAt(i)
      ..insertAll(i, [a, b]);
    _assign(a, best.$2);
    if (blockReason(best.$3, b) == null) _assign(b, best.$3);
    return true;
  }

  /// The longest part of [s] (at least [kMinPartMinutes], from its start or
  /// to its end) one person can work; the rest stays open.
  bool _partial(Slot s) {
    final minPart = _minPartMinutes;
    (TimeWindow, String)? best;
    for (final u in people) {
      final p = u.id!;
      if (inTraining(p) || !fitsTags(p, s.onlyTags)) continue;
      final ws = workWindows(p, s.date);
      if (ws == null) continue; // free all day → would be a candidate already
      for (final w in ws) {
        final from = math.max(w.start, s.start);
        final to = math.min(w.end, s.end);
        if (to - from < minPart || to - from >= s.minutes) continue;
        if (from != s.start && to != s.end) continue;
        final part = s.part('t', from, to);
        if (blockReason(p, part) != null) continue;
        if (best == null || part.minutes > best.$1.minutes)
          best = (part.window, p);
      }
    }
    if (best == null) return false;
    final (w, p) = best;
    final i = slots.indexOf(s);
    final taken = s.part('S${_nextId++}', w.start, w.end);
    final rest = w.start == s.start
        ? s.part('S${_nextId++}', w.end, s.end)
        : s.part('S${_nextId++}', s.start, w.start);
    slots
      ..removeAt(i)
      ..insertAll(i, w.start == s.start ? [taken, rest] : [rest, taken]);
    _assign(taken, p);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Changes from the AI review
  // ---------------------------------------------------------------------------

  /// Applies [changes] (slot id → uid) together: the slots are cleared, then
  /// given out in order. Anything that breaks a rule is skipped (the slot
  /// goes back to who had it, or is refilled). If the result covers less
  /// time than before, everything is undone. Returns the applied changes
  /// and why the others were skipped.
  ({int applied, List<SkippedChange> skipped, bool reverted}) applyChanges(
    List<(String, String)> changes,
  ) {
    final before = Map<String, String>.from(_who);
    final coveredBefore = coveredMinutes;
    final skipped = <SkippedChange>[];
    final valid = <(Slot, String)>[];
    for (final (id, uid) in changes) {
      final s = slotById(id);
      if (s == null) {
        skipped.add((slotId: id, uid: uid, why: 'no such slot'));
      } else if (!byId.containsKey(uid)) {
        skipped.add((slotId: id, uid: uid, why: 'unknown person'));
      } else if (_trainingSlots.contains(id) ||
          _trainee.containsKey(id) ||
          (_who[id] != null && inTraining(_who[id]!)) ||
          inTraining(uid)) {
        skipped.add((
          slotId: id,
          uid: uid,
          why: 'training flow is a hard rule and cannot be altered',
        ));
      } else if (_pinned.contains(id)) {
        skipped.add((
          slotId: id,
          uid: uid,
          why: 'placed for one of your requests',
        ));
      } else if (_who[id] != uid) {
        valid.add((s, uid));
      }
    }
    for (final (s, _) in valid) {
      _unassign(s);
    }
    var applied = 0;
    for (final (s, uid) in valid) {
      final why = blockReason(uid, s);
      if (why == null) {
        _assign(s, uid);
        applied++;
      } else {
        skipped.add((slotId: s.id, uid: uid, why: why));
      }
    }
    for (final (s, _) in valid) {
      if (_who[s.id] != null) continue;
      final old = before[s.id];
      if (old != null && blockReason(old, s) == null) {
        _assign(s, old);
      }
    }
    if (coveredMinutes < coveredBefore) {
      fill(short: false);
      fill(short: true);
    }
    if (coveredMinutes < coveredBefore) {
      _who
        ..clear()
        ..addAll(before);
      return (applied: 0, skipped: skipped, reverted: true);
    }
    return (applied: applied, skipped: skipped, reverted: false);
  }

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------

  int get neededMinutes => slots.fold(0, (a, s) => a + s.minutes);
  int get coveredMinutes =>
      slots.where((s) => _who[s.id] != null).fold(0, (a, s) => a + s.minutes);
  List<Slot> get openSlots => slots.where((s) => _who[s.id] == null).toList();

  /// Slots given to someone who usually works them (habit ≥ 0.5).
  int get keptUsual => slots.where((s) {
    final uid = _who[s.id];
    return uid != null && habit(uid, s) >= 0.5;
  }).length;

  /// How far everyone is from their usual shifts (lower = better).
  double get targetGap => people
      .where((u) => !inTraining(u.id!))
      .fold(0.0, (a, u) => a + (target(u.id!) - daysWorked(u.id!)).abs());

  /// Open slots with the reason, merged per row and day.
  List<OpenSlot> unfilled() => [
    for (final s in openSlots) (slot: s, why: whyOpen(s)),
  ];

  /// Why nobody is on [s].
  String whyOpen(Slot s) {
    final who = s.restricted ? ' ${s.onlyTags.join('/')}' : '';
    final fits = people.where(
      (u) => !inTraining(u.id!) && fitsTags(u.id!, s.onlyTags),
    );
    if (fits.isEmpty)
      return 'Hard rule: no one${s.restricted ? ' with ${s.onlyTags.join('/')}' : ''} on the schedule has this title/tag';
    final whole = fits
        .where((u) => canWorkRange(u.id!, s.date, s.start, s.end))
        .toList();
    if (whole.isEmpty) {
      final some = fits.where((u) {
        final ws = workWindows(u.id!, s.date);
        return ws == null || ws.any((w) => w.overlaps(s.start, s.end));
      }).length;
      return some == 0
          ? 'Hard rule: availability (no one$who is available then)'
          : 'Hard rule: availability (people$who are free for only part of it; $some could cover some)';
    }
    // What stops each of them, most common first.
    final reasons = <String, int>{};
    for (final u in whole) {
      final why = blockReason(u.id!, s) ?? 'another rule blocks them';
      reasons[why] = (reasons[why] ?? 0) + 1;
    }
    final parts =
        (reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(2)
            .map(
              (e) => e.value == whole.length && reasons.length == 1
                  ? e.key
                  : '${e.value} ${e.key}',
            );
    return 'Hard rule: ${parts.join('; ')} (${whole.length} available otherwise)';
  }

  /// Open slots with the reason, back-to-back ones in the same row joined.
  List<OpenSlot> openStretches() {
    final open = openSlots
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        final r = a.rowId.compareTo(b.rowId);
        return r != 0 ? r : a.start.compareTo(b.start);
      });
    final out = <OpenSlot>[];
    for (final s in open) {
      final last = out.lastOrNull?.slot;
      if (last != null &&
          last.date == s.date &&
          last.rowId == s.rowId &&
          last.end == s.start) {
        out[out.length - 1] = (
          slot: last.part(last.id, last.start, s.end),
          why: out.last.why,
        );
      } else {
        out.add((slot: s, why: whyOpen(s)));
      }
    }
    out.sort((a, b) {
      final c = a.slot.date.compareTo(b.slot.date);
      return c != 0 ? c : a.slot.start.compareTo(b.slot.start);
    });
    return out;
  }

  /// The built days: template rows untouched, one shift per person.
  Map<String, ScheduleDay> toDays() {
    final out = <String, ScheduleDay>{};
    for (final day in days) {
      final byPerson = <String, List<Slot>>{};
      for (final s in slots) {
        if (s.date != day.date) continue;
        final uid = _who[s.id];
        if (uid != null) (byPerson[uid] ??= []).add(s);
      }
      for (final entry in _admin.entries) {
        if ((entry.value[day.date] ?? const []).isNotEmpty) {
          byPerson.putIfAbsent(entry.key, () => []);
        }
      }
      final shifts = [
        for (final e in byPerson.entries)
          () {
            final mine = e.value..sort((a, b) => a.start.compareTo(b.start));
            final adminWins = _admin[e.key]?[day.date] ?? const <TimeWindow>[];
            final pieces = <ShiftPiece>[];
            for (final s in mine) {
              var intervals = [TimeWindow(s.start, s.end)];
              for (final w in adminWins) {
                final next = <TimeWindow>[];
                for (final iv in intervals) {
                  if (w.end <= iv.start || w.start >= iv.end) {
                    next.add(iv);
                  } else {
                    if (w.start > iv.start)
                      next.add(TimeWindow(iv.start, w.start));
                    if (w.end < iv.end) next.add(TimeWindow(w.end, iv.end));
                  }
                }
                intervals = next;
              }
              for (final iv in intervals) {
                if (iv.minutes > 0) {
                  pieces.add(
                    ShiftPiece(
                      id: newScheduleId(),
                      rowId: s.rowId,
                      start: iv.start,
                      end: iv.end,
                    ),
                  );
                }
              }
            }
            for (final w in adminWins) {
              pieces.add(
                ShiftPiece(
                  id: newScheduleId(),
                  rowId: kAdminRowId,
                  start: w.start,
                  end: w.end,
                  admin: true,
                ),
              );
            }
            return Shift(
              id: newScheduleId(),
              userId: e.key,
              traineeId: mine.map((s) => _trainee[s.id]).nonNulls.firstOrNull,
              pieces: pieces..sort((a, b) => a.start.compareTo(b.start)),
            );
          }(),
      ]..sort((a, b) => a.start.compareTo(b.start));
      out[day.date] = (_dayByDate[day.date] ?? day).copyWith(shifts: shifts);
    }
    return out;
  }
}
