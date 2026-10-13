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
//              splitting the slot between two people.
//
// Hard rules (never broken): availability, time off, title / tag bars, one
// stretch of work per person per day (short bars can join onto it), at most
// [maxShiftsPerWeek] shifts a week, who can train.
// Priorities when choosing between people: covering the template first,
// then getting people close to their usual shifts a week, then keeping
// people on the shifts they've worked the last few weeks (same weekday,
// about the same time), then Daytime people in the morning and Night people
// in the evening, then no close-then-open, then fair hours.

import 'dart:math' as math;

import '../../../models/schedule_models.dart';
import '../../../models/user_model.dart';
import 'schedule_common.dart';
import 'schedule_ops.dart';

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
const int kMinPartMinutes = 2 * 60;

/// The manager's instructions for one build (from the "anything else?" box
/// or the terminal chat, read by the AI). They override the rules.
class ScheduleOverrides {
  /// Weekly most shifts for some people.
  final Map<String, int> maxShifts;

  /// Train this trainee with this trainer (even if they aren't a trainer),
  /// on [date] or any day. ([source] = which request it came from, for the
  /// report of what was done.)
  final List<({String trainer, String trainee, String? date, String source})> pairs;

  /// Must work on [date] (at [window] if set), even outside availability.
  final List<({String uid, String date, TimeWindow? window, String source})> mustWork;

  /// Everyone in [people] works at the same time for [minutes] (a meeting),
  /// on [date] or any day.
  final List<({List<String> people, int minutes, String? date, String source})> meetings;

  /// Admin time: [minutes] off the floor for [uid], right before or after
  /// their shift (on [date] or any day they work).
  final List<({String uid, int minutes, String? date, String source})> admin;

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
    List<({String uid, int minutes, String? date, String source})> admin,
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
  }) {
    _compile();
  }

  late final Map<String, UserModel> byId = {for (final u in people) u.id!: u};
  late final Map<String, ScheduleDay> _dayByDate = {for (final d in days) d.date: d};

  final List<Slot> slots = [];
  final Map<String, String> _who = {}; // slot id → uid
  final Map<String, String> _trainee = {}; // slot id → trainee uid
  final Map<String, Set<String>> _traineeDates = {}; // trainee → dates
  final List<TrainingOutcome> training = [];
  int _nextId = 1;

  String? whoOn(String slotId) => _who[slotId];
  String? traineeOn(String slotId) => _trainee[slotId];
  Slot? slotById(String id) => slots.where((s) => s.id == id).firstOrNull;

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
      out = workWindowsFor(byId[uid]!, DateTime.parse(date), [...timeOff, ...overrides.extraOff]);
    }
    return _windowCache[key] = out;
  }

  bool canWorkRange(String uid, String date, int start, int end) {
    final ws = workWindows(uid, date);
    return ws == null || ws.any((w) => w.containsRange(start, end));
  }

  bool fitsTags(String uid, List<String> tags) =>
      tags.isEmpty || userFitsRow(byId[uid], ScheduleRow(id: '', allowedTitles: tags));

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

  /// Longest slot: a long shift, or less with the "max hours a day" rule.
  int get _maxSlot => rules.maxHoursPerDayOn
      ? math.min(kMaxSlotMinutes, (rules.maxHoursPerDay * 60).round())
      : kMaxSlotMinutes;

  /// Cuts a bar into shift-sized pieces, splitting where the most people
  /// can work both sides (then nearest the middle).
  List<TimeWindow> _cut(String date, TimeWindow w, List<String> tags) {
    if (w.minutes <= _maxSlot) return [w];
    final pieces = (w.minutes / kSplitTargetMinutes).ceil();
    final ideal = w.start + w.minutes ~/ pieces;
    final lo = w.start + kMinSplitMinutes;
    final hi = w.end - kMinSplitMinutes;
    int? best;
    var bestScore = -1.0;
    for (var t = (lo / 30).ceil() * 30; t <= hi; t += 30) {
      final both = math.min(_supply(date, w.start, t, tags), _supply(date, t, w.end, tags));
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
      for (final e in (busyElsewhere[uid] ?? const <String, List<TimeWindow>>{}).entries)
        if (e.value.isNotEmpty) e.key,
    };
    return dates.length + (fixedShifts[uid] ?? 0);
  }

  int minutesOf(String uid) => slots
      .where((s) => _who[s.id] == uid)
      .fold(0, (a, s) => a + s.minutes);

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
    var cap = rules.maxHoursPerDayOn ? (rules.maxHoursPerDay * 60).round() : 16 * 60;
    if (isMinor(uid)) cap = math.min(cap, (rules.minorMaxHoursPerDay * 60).round());
    return cap;
  }

  static String _shiftDate(String date, int days) =>
      dateKey(addDays(DateTime.parse(date), days));

  /// When [uid] works on [date] (this schedule and the others).
  List<TimeWindow> _workOn(String uid, String date) => [
    for (final s in slotsOf(uid, date)) s.window,
    ...?busyElsewhere[uid]?[date],
  ];

  /// Dates [uid] works this week (as a trainee too, and on other schedules).
  Set<String> _datesWorked(String uid) => {
    for (final s in slots)
      if (_who[s.id] == uid) s.date,
    ...?_traineeDates[uid],
    for (final e in (busyElsewhere[uid] ?? const <String, List<TimeWindow>>{}).entries)
      if (e.value.isNotEmpty) e.key,
  };

  /// Why the hard day-to-day rules block [uid] working [w] on [date] (rest
  /// between shifts, days in a row, minors' latest time, apart), or null.
  String? _dayRules(String uid, String date, TimeWindow w, {bool newDay = true}) {
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
      if (run > rules.maxDaysInRow) return 'would work more than ${rules.maxDaysInRow} days in a row';
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
    if (inTraining(uid) && !trainingStep) return 'only on their training shifts this week';
    if (!fitsTags(uid, slot.onlyTags)) return 'not ${slot.onlyTags.join('/')}';
    if (_traineeDates[uid]?.contains(slot.date) ?? false) return 'training that day';
    if (!canWorkRange(uid, slot.date, slot.start, slot.end)) return 'not available';
    final mine = slotsOf(uid, slot.date);
    if (mine.isEmpty) {
      if (daysWorked(uid) >= maxShifts(uid)) return 'at their most shifts this week';
      if (slot.minutes > dayCap(uid, slot.date)) {
        return 'can work at most ${formatHours(dayCap(uid, slot.date) / 60)} hours a day';
      }
      return _dayRules(uid, slot.date, slot.window);
    }
    if (mine.any((s) => s.window.overlaps(slot.start, slot.end))) return 'already working then';
    final blocks = mergeWindows([...mine.map((s) => s.window), slot.window]);
    if (blocks.length > 1) return 'already working that day';
    if (blocks.first.minutes > math.min(kMaxDayMinutes, dayCap(uid, slot.date))) {
      return 'already working that day';
    }
    // Two long slots in one day only when the whole day is one shift.
    if (!slot.short && mine.any((s) => !s.short)) return 'already working that day';
    return _dayRules(uid, slot.date, blocks.first, newDay: false);
  }

  void _assign(Slot slot, String uid) => _who[slot.id] = uid;
  void _unassign(Slot slot) => _who.remove(slot.id);

  bool get _hasRestrictedOpen => slots.any((s) => s.restricted && _who[s.id] == null);

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
    // Fair hours.
    if (rules.fairHours) s -= minutesOf(uid) / 60 * 0.4;
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
      final int overlap = math.min(w.end, slot.end) - math.max(w.start, slot.start);
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
      bool covers(Slot s) => want == null || s.window.overlaps(want.start, want.end);
      if (slotsOf(m.uid, m.date).any(covers)) {
        _outcome(m.source, true, '${_who2(m.uid)} works ${_day(m.date)}.');
        continue;
      }
      if (slotsOf(m.uid, m.date).isNotEmpty) {
        _outcome(m.source, false, '${_who2(m.uid)} already works ${_day(m.date)} at another time.');
        continue;
      }
      Slot? best;
      var bestKey = -1;
      for (final s in slots) {
        if (s.date != m.date || _who[s.id] != null || s.short || !covers(s)) continue;
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
        _outcome(m.source, false, 'No open slot on ${_day(m.date)} for ${_who2(m.uid)}.');
        continue;
      }
      _assign(best, m.uid);
      _outcome(m.source, true, '${_who2(m.uid)} works ${_day(m.date)} ${formatRange(best.start, best.end)}.');
    }
    // Pairs for people who aren't in training (trainees in training get
    // theirs with their training shifts).
    for (final p in overrides.pairs) {
      if (inTraining(p.trainee) || !byId.containsKey(p.trainee) || !byId.containsKey(p.trainer)) {
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
      (_traineeDates[p.trainee] ??= {}).add(best.date);
      _outcome(
        p.source,
        true,
        '${_who2(p.trainer)} trains ${_who2(p.trainee)} ${_day(best.date)} '
        '${formatRange(best.start, best.end)}.',
      );
    }
    for (final meeting in overrides.meetings) {
      final people = meeting.people.where(byId.containsKey).toList();
      if (people.length < 2) continue;
      final placed = _placeMeeting(people, meeting.minutes, meeting.date);
      _outcome(
        meeting.source,
        placed != null,
        placed ??
            'No ${formatHours(meeting.minutes / 60)}-hour stretch when '
                '${people.map(_who2).join(', ')} can all be on'
                '${meeting.date == null ? ' this week' : ' on ${_day(meeting.date!)}'}.',
      );
    }
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

  /// Admin time added, by person and date.
  final Map<String, Map<String, List<TimeWindow>>> _admin = {};

  /// Adds the requested admin time, right before or after each person's
  /// shift (never on its own). Run last, once shifts are final.
  void placeAdmin() {
    for (final r in overrides.admin) {
      if (!byId.containsKey(r.uid)) continue;
      final placed = _placeAdminFor(r.uid, r.minutes, r.date);
      final what = '${formatHours(r.minutes / 60)} h admin for ${_who2(r.uid)}';
      if (placed != null) {
        _outcome(r.source, true, '$what: ${_day(placed.$1)} ${formatRange(placed.$2.start, placed.$2.end)}, '
            '${placed.$3 ? 'right after' : 'right before'} their shift.');
      } else {
        final works = days.any((d) => slotsOf(r.uid, d.date).isNotEmpty &&
            (r.date == null || r.date == d.date));
        _outcome(
          r.source,
          false,
          works
              ? '$what: they aren\'t free right before or after their shift'
                    '${r.date == null ? ' any day' : ' on ${_day(r.date!)}'} (availability or most hours a day).'
              : '$what: they aren\'t on the schedule'
                    '${r.date == null ? ' this week' : ' on ${_day(r.date!)}'}, and admin needs a shift right next to it.',
        );
      }
    }
  }

  /// (date, admin window, after the shift?) or null.
  (String, TimeWindow, bool)? _placeAdminFor(String uid, int minutes, String? date) {
    final candidates = [
      for (final d in days)
        if ((date == null || d.date == date) && slotsOf(uid, d.date).isNotEmpty) d.date,
    ]..sort((a, b) => _dayMinutes(uid, a).compareTo(_dayMinutes(uid, b)));
    for (final d in candidates) {
      final spans = [
        for (final s in slotsOf(uid, d)) s.window,
        ...?_admin[uid]?[d],
      ];
      final span = TimeWindow(
        spans.map((w) => w.start).reduce(math.min),
        spans.map((w) => w.end).reduce(math.max),
      );
      if (span.minutes + minutes > dayCap(uid, d)) continue;
      for (final after in [true, false]) {
        final w = after
            ? TimeWindow(span.end, span.end + minutes)
            : TimeWindow(span.start - minutes, span.start);
        if (w.start < 0 || w.end > kMaxScheduleMinute) continue;
        if (!canWorkRange(uid, d, w.start, w.end)) continue;
        final whole = TimeWindow(math.min(span.start, w.start), math.max(span.end, w.end));
        if (_dayRules(uid, d, whole, newDay: false) != null) continue;
        ((_admin[uid] ??= {})[d] ??= []).add(w);
        return (d, w, after);
      }
    }
    return null;
  }

  int _dayMinutes(String uid, String date) =>
      slotsOf(uid, date).fold(0, (a, s) => a + s.minutes) +
      (_admin[uid]?[date] ?? const <TimeWindow>[]).fold(0, (a, w) => a + w.minutes);

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
          if (slotsOf(p, day.date).any((s) => s.window.containsRange(w.start, w.end))) {
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
            if (forced.isNotEmpty ? !forced.any((p) => p.trainer == c) : !canTrain(u, config)) {
              continue;
            }
            if (_noTraining(c, slot.date)) continue;
            if (_trainee.entries.any(
              (e) => _who[e.key] == c && slotById(e.key)?.date == slot.date,
            )) {
              continue; // one trainee per trainer a day
            }
            if (blockReason(c, slot) != null) continue;
            final hasTag = (u.additionalTags ?? const []).any(config.trainerTags.contains);
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
        if (withTrainer) {
          _trainee[slot.id] = t;
          (_traineeDates[t] ??= {}).add(slot.date);
        }
        got.add((slot.date, withTrainer));
        if (step.positionId != null) {
          _training.add((date: slot.date, positionId: step.positionId!, window: slot.window));
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
  final List<({String date, String positionId, TimeWindow window})> _training = [];

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
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
  }

  int _daysFree(String uid) => days
      .where((d) => workWindows(uid, d.date)?.isNotEmpty ?? true)
      .length;

  // ---------------------------------------------------------------------------
  // 3–4. Filling
  // ---------------------------------------------------------------------------

  /// Fills open slots, scarcest first. [restrictedOnly]: title / tag bars;
  /// [short]: short bars only (else long ones only). Returns how many.
  int fill({bool restrictedOnly = false, required bool short}) {
    bool wanted(Slot s) =>
        _who[s.id] == null && s.short == short && (!restrictedOnly || s.restricted);
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
            (a == b && s.restricted == pick.restricted && s.minutes > pick.minutes);
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
        if (e.value.contains(uid) && blockReason(uid, slotById(e.key)!) != null) {
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
        if (_direct(s) || _swapIn(s) || _moveDay(s) || _shortViaNeighbour(s) || _split(s)) {
          fixed++;
          progress = true;
        }
      }
      if (!progress) break;
    }
    return fixed;
  }

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
      if (mine.length != 1 || _trainee.containsKey(mine.first.id)) continue;
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
      if (slotsOf(p, s.date).isNotEmpty || daysWorked(p) < maxShifts(p)) continue;
      for (final other in slots.where((o) => _who[o.id] == p && o.date != s.date).toList()) {
        if (_trainee.containsKey(other.id) || slotsOf(p, other.date).length != 1) continue;
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
      if (a == null || inTraining(a) || _trainee.containsKey(t.id) || slotsOf(a, t.date).length != 1) {
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

  /// Nobody can work all of [s]: split it so two people share it, or give
  /// part of it to one person and leave the rest open.
  bool _split(Slot s) {
    if (s.short || s.minutes < 2 * kMinPartMinutes) return _partial(s);
    (int, String, String)? best;
    for (var t = s.start + kMinPartMinutes; t <= s.end - kMinPartMinutes; t += 30) {
      final a = s.part('x', s.start, t);
      final b = s.part('y', t, s.end);
      final ca = candidates(a);
      if (ca.isEmpty) continue;
      final cb = candidates(b).where((c) => c != ca.first).toList();
      if (cb.isEmpty) continue;
      final balance = math.min(t - s.start, s.end - t);
      if (best == null || balance > best.$1) best = (t, ca.first, cb.first);
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
    (TimeWindow, String)? best;
    for (final u in people) {
      final p = u.id!;
      if (inTraining(p) || !fitsTags(p, s.onlyTags)) continue;
      final ws = workWindows(p, s.date);
      if (ws == null) continue; // free all day → would be a candidate already
      for (final w in ws) {
        final from = math.max(w.start, s.start);
        final to = math.min(w.end, s.end);
        if (to - from < kMinPartMinutes || to - from >= s.minutes) continue;
        if (from != s.start && to != s.end) continue;
        final part = s.part('t', from, to);
        if (blockReason(p, part) != null) continue;
        if (best == null || part.minutes > best.$1.minutes) best = (part.window, p);
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
      } else if (_trainee.containsKey(id) || (_who[id] != null && inTraining(_who[id]!))) {
        skipped.add((slotId: id, uid: uid, why: 'it\'s a training shift'));
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
    final who = s.restricted ? ' ${s.onlyTags.join('/')}' : ' one';
    final fits = people.where(
      (u) => !inTraining(u.id!) && fitsTags(u.id!, s.onlyTags),
    );
    if (fits.isEmpty) return 'nobody on this schedule is ${s.onlyTags.join('/')}';
    final whole = fits.where((u) => canWorkRange(u.id!, s.date, s.start, s.end)).toList();
    if (whole.isEmpty) {
      final some = fits.where((u) {
        final ws = workWindows(u.id!, s.date);
        return ws == null || ws.any((w) => w.overlaps(s.start, s.end));
      }).length;
      return some == 0
          ? 'no$who is available then (availability / time off)'
          : 'people are only free for part of it ($some could cover some)';
    }
    // What stops each of them, most common first.
    final reasons = <String, int>{};
    for (final u in whole) {
      final why = blockReason(u.id!, s) ?? 'another rule blocks them';
      reasons[why] = (reasons[why] ?? 0) + 1;
    }
    final parts = (reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(2)
        .map((e) => e.value == whole.length && reasons.length == 1 ? e.key : '${e.value} ${e.key}');
    return '${whole.length} could, but ${parts.join('; ')}';
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
      if (last != null && last.date == s.date && last.rowId == s.rowId && last.end == s.start) {
        out[out.length - 1] = (slot: last.part(last.id, last.start, s.end), why: out.last.why);
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
      final shifts = [
        for (final e in byPerson.entries)
          () {
            final mine = e.value..sort((a, b) => a.start.compareTo(b.start));
            return Shift(
              id: newScheduleId(),
              userId: e.key,
              traineeId: mine.map((s) => _trainee[s.id]).nonNulls.firstOrNull,
              pieces: [
                for (final s in mine)
                  ShiftPiece(id: newScheduleId(), rowId: s.rowId, start: s.start, end: s.end),
                for (final w in _admin[e.key]?[day.date] ?? const <TimeWindow>[])
                  ShiftPiece(
                    id: newScheduleId(),
                    rowId: kAdminRowId,
                    start: w.start,
                    end: w.end,
                    admin: true,
                  ),
              ]..sort((a, b) => a.start.compareTo(b.start)),
            );
          }(),
      ]..sort((a, b) => a.start.compareTo(b.start));
      out[day.date] = (_dayByDate[day.date] ?? day).copyWith(shifts: shifts);
    }
    return out;
  }
}
