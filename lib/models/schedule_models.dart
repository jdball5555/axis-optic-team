// Plain Dart models for the schedule builder (no code generation needed).
//
// Firestore layout (per store):
//   /stores/{storeId}/settings/schedule_config      -> ScheduleConfig
//   /stores/{storeId}/schedule_templates/{id}       -> ScheduleTemplate
//   /stores/{storeId}/schedule_days/{yyyy-MM-dd}    -> ScheduleDay
//
// Times are stored as minutes from midnight of the schedule day (e.g. 5:15 AM
// = 315). Values above 1440 mean "after midnight" (e.g. 1500 = 1:00 AM +1).
//
// A ScheduleDay is self-contained: it holds a copy of the template rows it was
// built from plus every shift. That makes it easy to read for reporting, and
// easy for an AI model to fill in later (it only has to output `shifts`).

import 'dart:math' as math;

int _asInt(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

List<Map<String, dynamic>> _asMapList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

final _rand = math.Random();
String newScheduleId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';

/// Minutes in the last selectable time (4:00 AM the next day).
const int kMaxScheduleMinute = 1440 + 240;
const int kScheduleStep = 15;

/// 5:15 AM, 10:45 PM, 1:00 AM (+1)
String formatMinutes(int minutes, {bool compact = false}) {
  final nextDay = minutes >= 1440;
  final m = minutes % 1440;
  var h = m ~/ 60;
  final min = m % 60;
  final pm = h >= 12;
  h = h % 12;
  if (h == 0) h = 12;
  final String text;
  if (compact) {
    final suffix = pm ? 'p' : 'a';
    text = min == 0 ? '$h$suffix' : '$h:${min.toString().padLeft(2, '0')}$suffix';
  } else {
    text = '$h:${min.toString().padLeft(2, '0')} ${pm ? 'PM' : 'AM'}';
  }
  return nextDay && minutes != 1440 ? '$text (+1)' : text;
}

String formatRange(int start, int end, {bool compact = true}) =>
    '${formatMinutes(start, compact: compact)} – ${formatMinutes(end, compact: compact)}';

/// 7.5 -> "7.5", 7.25 -> "7.25", 8.0 -> "8"
String formatHours(double hours) {
  final rounded = (hours * 100).round() / 100;
  var s = rounded.toStringAsFixed(2);
  s = s.replaceAll(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day math (safe across daylight-saving changes, unlike Duration).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// First day of the schedule week containing [date].
/// [weekStart] uses DateTime weekday numbers (Monday = 1 ... Sunday = 7).
DateTime weekStartFor(DateTime date, int weekStart) {
  final d = dateOnly(date);
  final diff = (d.weekday - weekStart + 7) % 7;
  return DateTime(d.year, d.month, d.day - diff);
}

const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

// ---------------------------------------------------------------------------

class TimeWindow {
  final int start;
  final int end;
  const TimeWindow(this.start, this.end);

  int get minutes => math.max(0, end - start);
  bool overlaps(int s, int e) => s < end && e > start;
  bool containsRange(int s, int e) => s >= start && e <= end;

  factory TimeWindow.fromJson(Map<String, dynamic> j) =>
      TimeWindow(_asInt(j['start']), _asInt(j['end']));
  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  @override
  bool operator ==(Object other) =>
      other is TimeWindow && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
}

/// Sorts [windows] and joins any that overlap or touch (5p–… after …–5p),
/// so a row never shows two bars back to back.
List<TimeWindow> mergeWindows(Iterable<TimeWindow> windows) {
  final sorted = windows.where((w) => w.minutes > 0).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final out = <TimeWindow>[];
  for (final w in sorted) {
    if (out.isNotEmpty && w.start <= out.last.end) {
      final last = out.removeLast();
      out.add(TimeWindow(last.start, math.max(last.end, w.end)));
    } else {
      out.add(w);
    }
  }
  return out;
}

/// Subtracts [covered] intervals from [windows]; returns what's left.
List<TimeWindow> subtractWindows(
  List<TimeWindow> windows,
  List<TimeWindow> covered,
) {
  var result = [...windows];
  for (final c in covered) {
    final next = <TimeWindow>[];
    for (final w in result) {
      if (!w.overlaps(c.start, c.end)) {
        next.add(w);
        continue;
      }
      if (c.start > w.start) next.add(TimeWindow(w.start, c.start));
      if (c.end < w.end) next.add(TimeWindow(c.end, w.end));
    }
    result = next;
  }
  return result.where((w) => w.minutes > 0).toList();
}

/// A row in a template / day. A row can need coverage during more than one
/// window (e.g. 11–3 and 5–close). [allowedTitles] empty = anyone.
class ScheduleRow {
  final String id;
  final String label;
  final List<TimeWindow> windows;
  final List<String> allowedTitles;

  const ScheduleRow({
    required this.id,
    this.label = '',
    this.windows = const [],
    this.allowedTitles = const [],
  });

  bool get isRestricted => allowedTitles.isNotEmpty;
  int get neededMinutes => windows.fold(0, (a, w) => a + w.minutes);

  ScheduleRow copyWith({
    String? id,
    String? label,
    List<TimeWindow>? windows,
    List<String>? allowedTitles,
  }) => ScheduleRow(
    id: id ?? this.id,
    label: label ?? this.label,
    windows: windows ?? this.windows,
    allowedTitles: allowedTitles ?? this.allowedTitles,
  );

  factory ScheduleRow.fromJson(Map<String, dynamic> j) => ScheduleRow(
    id: j['id'] as String? ?? newScheduleId(),
    label: j['label'] as String? ?? '',
    windows: _asMapList(j['windows']).map(TimeWindow.fromJson).toList()
      ..sort((a, b) => a.start.compareTo(b.start)),
    allowedTitles: (j['allowed_titles'] as List?)?.whereType<String>().toList() ??
        const [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'windows': windows.map((w) => w.toJson()).toList(),
    'allowed_titles': allowedTitles,
  };
}

/// A template is stored in every store it's shared with, under the same id
/// (/stores/{storeId}/schedule_templates/{id}); [storeIds] lists those stores.
class ScheduleTemplate {
  final String id;
  final String name;
  final List<ScheduleRow> rows;

  /// Stores that see this template. Empty = only the store it was read from.
  final List<String> storeIds;

  /// Shared with every store (storeIds holds them all as of the last save).
  final bool allStores;

  const ScheduleTemplate({
    required this.id,
    required this.name,
    this.rows = const [],
    this.storeIds = const [],
    this.allStores = false,
  });

  ScheduleTemplate copyWith({
    String? name,
    List<ScheduleRow>? rows,
    List<String>? storeIds,
    bool? allStores,
  }) => ScheduleTemplate(
    id: id,
    name: name ?? this.name,
    rows: rows ?? this.rows,
    storeIds: storeIds ?? this.storeIds,
    allStores: allStores ?? this.allStores,
  );

  double get neededHours => rows.fold(0, (a, r) => a + r.neededMinutes) / 60;

  factory ScheduleTemplate.fromJson(String id, Map<String, dynamic> j) =>
      ScheduleTemplate(
        id: id,
        name: j['name'] as String? ?? 'Untitled template',
        rows: _asMapList(j['rows']).map(ScheduleRow.fromJson).toList(),
        storeIds:
            (j['store_ids'] as List?)?.whereType<String>().toList() ?? const [],
        allStores: j['all_stores'] == true,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'rows': rows.map((r) => r.toJson()).toList(),
    'store_ids': storeIds,
    'all_stores': allStores,
  };
}

/// One continuous block of a shift inside one row.
class ShiftPiece {
  final String id;
  final String rowId;
  final int start;
  final int end;

  /// Admin time: paid and on the schedule, but off the floor. It isn't in a
  /// template row, doesn't count toward the people needed and isn't put on
  /// a position. It always sits right before or after the person's shift.
  final bool admin;

  const ShiftPiece({
    required this.id,
    required this.rowId,
    required this.start,
    required this.end,
    this.admin = false,
  });

  int get minutes => math.max(0, end - start);
  bool overlaps(int s, int e) => s < end && e > start;

  ShiftPiece copyWith({String? rowId, int? start, int? end}) => ShiftPiece(
    id: id,
    rowId: rowId ?? this.rowId,
    start: start ?? this.start,
    end: end ?? this.end,
    admin: admin,
  );

  factory ShiftPiece.fromJson(Map<String, dynamic> j) => ShiftPiece(
    id: j['id'] as String? ?? newScheduleId(),
    rowId: j['row_id'] as String? ?? '',
    start: _asInt(j['start']),
    end: _asInt(j['end']),
    admin: j['admin'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'row_id': rowId,
    'start': start,
    'end': end,
    if (admin) 'admin': true,
  };
}

/// Row id used by admin pieces (they aren't in a template row).
const kAdminRowId = '_admin';

/// Part of a shift spent on one shift-page position (station).
class PositionSegment {
  final String positionId;
  final int start;
  final int end;

  const PositionSegment({
    required this.positionId,
    required this.start,
    required this.end,
  });

  int get minutes => math.max(0, end - start);

  factory PositionSegment.fromJson(Map<String, dynamic> j) => PositionSegment(
    positionId: j['position_id'] as String? ?? '',
    start: _asInt(j['start']),
    end: _asInt(j['end']),
  );

  Map<String, dynamic> toJson() => {
    'position_id': positionId,
    'start': start,
    'end': end,
  };

  @override
  bool operator ==(Object other) =>
      other is PositionSegment &&
      other.positionId == positionId &&
      other.start == start &&
      other.end == end;
  @override
  int get hashCode => Object.hash(positionId, start, end);
}

/// One person's shift for the day. It can be split across several rows.
/// A training shift has a [traineeId]: two people in the same slots.
class Shift {
  final String id;
  final String userId;
  final String? traineeId;
  final List<ShiftPiece> pieces;

  /// Where they are on the shift page through the shift (can change during
  /// it, e.g. Register 6–11 then Drive-thru 11–3). Empty = not deployed.
  final List<PositionSegment> positions;

  const Shift({
    required this.id,
    required this.userId,
    this.traineeId,
    this.pieces = const [],
    this.positions = const [],
  });

  bool get isTraining => traineeId != null && traineeId!.isNotEmpty;

  /// On the floor (in template rows) vs admin time.
  List<ShiftPiece> get workPieces => [for (final p in pieces) if (!p.admin) p];
  List<ShiftPiece> get adminPieces => [for (final p in pieces) if (p.admin) p];
  bool get hasAdmin => pieces.any((p) => p.admin);
  int get start => pieces.isEmpty ? 0 : pieces.map((p) => p.start).reduce(math.min);
  int get end => pieces.isEmpty ? 0 : pieces.map((p) => p.end).reduce(math.max);
  int get minutes => pieces.fold(0, (a, p) => a + p.minutes);

  /// Paid minutes for this shift (trainer + trainee).
  int get laborMinutes => minutes * (isTraining ? 2 : 1);

  bool involves(String uid) => userId == uid || traineeId == uid;

  Shift copyWith({
    String? userId,
    String? traineeId,
    bool clearTrainee = false,
    List<ShiftPiece>? pieces,
    List<PositionSegment>? positions,
  }) => Shift(
    id: id,
    userId: userId ?? this.userId,
    traineeId: clearTrainee ? null : (traineeId ?? this.traineeId),
    pieces: pieces ?? this.pieces,
    positions: positions ?? this.positions,
  );

  factory Shift.fromJson(Map<String, dynamic> j) {
    final pieces = _asMapList(j['pieces']).map(ShiftPiece.fromJson).toList();
    var positions = _asMapList(
      j['position_segments'],
    ).map(PositionSegment.fromJson).toList();
    // Older docs: one position for the whole shift.
    final legacy = j['position_id'] as String?;
    if (positions.isEmpty && legacy != null && pieces.isNotEmpty) {
      positions = [
        for (final w in mergeWindows(pieces.map((p) => TimeWindow(p.start, p.end))))
          PositionSegment(positionId: legacy, start: w.start, end: w.end),
      ];
    }
    return Shift(
      id: j['id'] as String? ?? newScheduleId(),
      userId: j['user_id'] as String? ?? '',
      traineeId: j['trainee_id'] as String?,
      pieces: pieces,
      positions: positions,
    );
  }

  /// The position they spend the most time on (handy for simple readers).
  String? get mainPositionId {
    if (positions.isEmpty) return null;
    final byId = <String, int>{};
    for (final p in positions) {
      byId[p.positionId] = (byId[p.positionId] ?? 0) + p.minutes;
    }
    return byId.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'trainee_id': traineeId,
    'start': pieces.isEmpty ? null : start,
    'end': pieces.isEmpty ? null : end,
    'pieces': pieces.map((p) => p.toJson()).toList(),
    'position_segments': positions.map((p) => p.toJson()).toList(),
    'position_id': mainPositionId,
  };
}

class ScheduleDay {
  final String date; // yyyy-MM-dd
  final String? templateId;
  final String? templateName;
  final List<ScheduleRow> rows;
  final List<Shift> shifts;

  /// ISO time the week containing this day was last posted (null = never).
  final String? postedAt;

  /// Changed since it was posted, so the posted version is out of date.
  final bool editedAfterPost;

  const ScheduleDay({
    required this.date,
    this.templateId,
    this.templateName,
    this.rows = const [],
    this.shifts = const [],
    this.postedAt,
    this.editedAfterPost = false,
  });

  bool get isPosted => postedAt != null && !editedAfterPost;

  factory ScheduleDay.empty(String date) => ScheduleDay(date: date);

  bool get isEmpty => rows.isEmpty && shifts.isEmpty;

  /// A template has been applied (possibly a blank one with no needed times).
  bool get hasTemplate => templateId != null || rows.isNotEmpty;

  ScheduleDay copyWith({
    String? templateId,
    String? templateName,
    List<ScheduleRow>? rows,
    List<Shift>? shifts,
    String? postedAt,
    bool? editedAfterPost,
  }) => ScheduleDay(
    date: date,
    templateId: templateId ?? this.templateId,
    templateName: templateName ?? this.templateName,
    rows: rows ?? this.rows,
    shifts: shifts ?? this.shifts,
    postedAt: postedAt ?? this.postedAt,
    editedAfterPost: editedAfterPost ?? this.editedAfterPost,
  );

  double get laborHours => shifts.fold(0, (a, s) => a + s.laborMinutes) / 60;
  double get neededHours => rows.fold(0, (a, r) => a + r.neededMinutes) / 60;

  ScheduleRow? rowById(String id) => rows.where((r) => r.id == id).firstOrNull;

  Shift? shiftById(String id) => shifts.where((s) => s.id == id).firstOrNull;

  Shift? shiftForUser(String uid) =>
      shifts.where((s) => s.userId == uid).firstOrNull;

  Shift? shiftOfPiece(String pieceId) =>
      shifts.where((s) => s.pieces.any((p) => p.id == pieceId)).firstOrNull;

  Iterable<(Shift, ShiftPiece)> piecesInRow(String rowId) sync* {
    for (final s in shifts) {
      for (final p in s.pieces) {
        if (p.rowId == rowId) yield (s, p);
      }
    }
  }

  /// Needed-but-unfilled time in a row.
  List<TimeWindow> openGaps(ScheduleRow row) => subtractWindows(
    row.windows,
    piecesInRow(row.id).map((e) => TimeWindow(e.$2.start, e.$2.end)).toList(),
  );

  double get openHours =>
      rows.fold(0, (a, r) => a + openGaps(r).fold(0, (b, w) => b + w.minutes)) /
      60;

  /// People needed at minute [m] according to the rows.
  int neededAt(int m) =>
      rows.where((r) => r.windows.any((w) => m >= w.start && m < w.end)).length;

  /// Distinct shifts (people slots) working at minute [m].
  /// (Admin time doesn't count: they're off the floor.)
  int scheduledAt(int m) => shifts
      .where((s) => s.pieces.any((p) => !p.admin && m >= p.start && m < p.end))
      .length;

  factory ScheduleDay.fromJson(String date, Map<String, dynamic> j) =>
      ScheduleDay(
        date: date,
        templateId: j['template_id'] as String?,
        templateName: j['template_name'] as String?,
        rows: _asMapList(j['rows']).map(ScheduleRow.fromJson).toList(),
        shifts: _asMapList(j['shifts']).map(Shift.fromJson).toList(),
        postedAt: j['posted_at'] as String?,
        editedAfterPost: j['edited_after_post'] == true,
      );

  Map<String, dynamic> toJson() => {
    'date': date,
    'template_id': templateId,
    'template_name': templateName,
    'rows': rows.map((r) => r.toJson()).toList(),
    'shifts': shifts.map((s) => s.toJson()).toList(),
    'posted_at': postedAt,
    'edited_after_post': editedAfterPost,
    // Handy flat fields for queries / reporting / AI.
    'user_ids': {
      for (final s in shifts) ...[s.userId, if (s.isTraining) s.traineeId!],
    }.toList(),
    'labor_hours': laborHours,
  };
}

/// One of a new hire's first shifts in the training flow: whether they
/// train with someone, and on which shift-page position.
class TrainingDay {
  final bool training;
  final String? positionId;

  const TrainingDay({this.training = true, this.positionId});

  TrainingDay copyWith({bool? training, String? positionId, bool clearPosition = false}) =>
      TrainingDay(
        training: training ?? this.training,
        positionId: clearPosition ? null : (positionId ?? this.positionId),
      );

  factory TrainingDay.fromJson(Map<String, dynamic> j) => TrainingDay(
    training: j['training'] != false,
    positionId: j['position_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'training': training,
    'position_id': positionId,
  };
}

/// Id of the main schedule (its days live where they always have).
const kMainBoardId = 'main';

/// A separate schedule (e.g. Front of house, Kitchen) with its own days and
/// shifts, covering some of the shift-page positions. Empty [positionIds] =
/// all positions. [teamAreas] are the roster areas (SVC, DT, KT, ...) whose
/// people show up on it; empty = everyone.
class ScheduleBoard {
  final String id;
  final String name;
  final List<String> positionIds;
  final List<String> teamAreas;

  const ScheduleBoard({
    required this.id,
    required this.name,
    this.positionIds = const [],
    this.teamAreas = const [],
  });

  bool get isMain => id == kMainBoardId;

  /// Does someone in roster area [area] belong on this schedule?
  bool includesArea(String? area) =>
      teamAreas.isEmpty || (area != null && teamAreas.contains(area));

  ScheduleBoard copyWith({
    String? name,
    List<String>? positionIds,
    List<String>? teamAreas,
  }) => ScheduleBoard(
    id: id,
    name: name ?? this.name,
    positionIds: positionIds ?? this.positionIds,
    teamAreas: teamAreas ?? this.teamAreas,
  );

  /// This schedule's share of an older store-wide position list (before
  /// positions belonged to shift boards), in priority order.
  List<ShiftPosition> positionsIn(List<ShiftPosition> positions) => positionIds.isEmpty
      ? positions
      : positions
            .where(
              (p) =>
                  positionIds.contains(p.id) ||
                  // A spot split off an older multi-spot position.
                  positionIds.contains(p.id.split('#').first),
            )
            .toList();

  factory ScheduleBoard.fromJson(Map<String, dynamic> j) => ScheduleBoard(
    id: j['id'] as String? ?? newScheduleId(),
    name: j['name'] as String? ?? 'Schedule',
    positionIds:
        (j['position_ids'] as List?)?.whereType<String>().toList() ?? const [],
    teamAreas:
        (j['team_areas'] as List?)?.whereType<String>().toList() ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'position_ids': positionIds,
    'team_areas': teamAreas,
  };
}

/// The scheduler's rules (Schedule settings → Rules). Hard rules are never
/// broken; the "try to" ones are preferences used to choose between people.
/// Availability, time off, title / tag bars, one stretch of work a day and
/// who can train are always hard rules.
class ScheduleRules {
  // --- Hard rules -----------------------------------------------------------

  /// Most shifts a week (more only when someone's "avg shifts" says more).
  final int maxShiftsPerWeek;

  /// Requested (pending) time off counts as time off.
  final bool requestedOffIsOff;

  final bool maxHoursPerDayOn;
  final double maxHoursPerDay;

  /// Hours off between one day's shift and the next.
  final bool restOn;
  final double restHours;

  final bool maxDaysInRowOn;
  final int maxDaysInRow;

  /// Minors (people with [minorDesignation]): no later than [minorLatestEnd]
  /// on school nights ([schoolNights], weekday numbers of the shift's day),
  /// and at most [minorMaxHoursPerDay] a day.
  final bool minorsOn;
  final String minorDesignation;
  final int minorLatestEnd;
  final List<int> schoolNights;
  final double minorMaxHoursPerDay;

  // --- Try to ----------------------------------------------------------------

  /// Get people close to their usual shifts a week ("avg shifts").
  final bool usualShifts;

  /// Keep people on the shifts they've worked the last few weeks.
  final bool consistency;

  /// Daytime people in the morning, Night people in the evening.
  final bool dayNight;

  /// Nobody closes one night and opens the next morning.
  final bool avoidClopen;

  /// Spread hours fairly.
  final bool fairHours;

  const ScheduleRules({
    this.maxShiftsPerWeek = 5,
    this.requestedOffIsOff = true,
    this.maxHoursPerDayOn = true,
    this.maxHoursPerDay = 11,
    this.restOn = false,
    this.restHours = 10,
    this.maxDaysInRowOn = false,
    this.maxDaysInRow = 6,
    this.minorsOn = false,
    this.minorDesignation = 'High School',
    this.minorLatestEnd = 22 * 60,
    this.schoolNights = const [7, 1, 2, 3, 4],
    this.minorMaxHoursPerDay = 8,
    this.usualShifts = true,
    this.consistency = true,
    this.dayNight = true,
    this.avoidClopen = true,
    this.fairHours = true,
  });

  ScheduleRules copyWith({
    int? maxShiftsPerWeek,
    bool? requestedOffIsOff,
    bool? maxHoursPerDayOn,
    double? maxHoursPerDay,
    bool? restOn,
    double? restHours,
    bool? maxDaysInRowOn,
    int? maxDaysInRow,
    bool? minorsOn,
    String? minorDesignation,
    int? minorLatestEnd,
    List<int>? schoolNights,
    double? minorMaxHoursPerDay,
    bool? usualShifts,
    bool? consistency,
    bool? dayNight,
    bool? avoidClopen,
    bool? fairHours,
  }) => ScheduleRules(
    maxShiftsPerWeek: maxShiftsPerWeek ?? this.maxShiftsPerWeek,
    requestedOffIsOff: requestedOffIsOff ?? this.requestedOffIsOff,
    maxHoursPerDayOn: maxHoursPerDayOn ?? this.maxHoursPerDayOn,
    maxHoursPerDay: maxHoursPerDay ?? this.maxHoursPerDay,
    restOn: restOn ?? this.restOn,
    restHours: restHours ?? this.restHours,
    maxDaysInRowOn: maxDaysInRowOn ?? this.maxDaysInRowOn,
    maxDaysInRow: maxDaysInRow ?? this.maxDaysInRow,
    minorsOn: minorsOn ?? this.minorsOn,
    minorDesignation: minorDesignation ?? this.minorDesignation,
    minorLatestEnd: minorLatestEnd ?? this.minorLatestEnd,
    schoolNights: schoolNights ?? this.schoolNights,
    minorMaxHoursPerDay: minorMaxHoursPerDay ?? this.minorMaxHoursPerDay,
    usualShifts: usualShifts ?? this.usualShifts,
    consistency: consistency ?? this.consistency,
    dayNight: dayNight ?? this.dayNight,
    avoidClopen: avoidClopen ?? this.avoidClopen,
    fairHours: fairHours ?? this.fairHours,
  );

  factory ScheduleRules.fromJson(Map<String, dynamic>? j) {
    const d = ScheduleRules();
    if (j == null) return d;
    bool b(String k, bool v) => j[k] is bool ? j[k] as bool : v;
    double n(String k, double v) => j[k] is num ? (j[k] as num).toDouble() : v;
    return ScheduleRules(
      maxShiftsPerWeek: _asInt(j['max_shifts_per_week'], d.maxShiftsPerWeek).clamp(1, 7),
      requestedOffIsOff: b('requested_off_is_off', d.requestedOffIsOff),
      maxHoursPerDayOn: b('max_hours_per_day_on', d.maxHoursPerDayOn),
      maxHoursPerDay: n('max_hours_per_day', d.maxHoursPerDay),
      restOn: b('rest_on', d.restOn),
      restHours: n('rest_hours', d.restHours),
      maxDaysInRowOn: b('max_days_in_row_on', d.maxDaysInRowOn),
      maxDaysInRow: _asInt(j['max_days_in_row'], d.maxDaysInRow).clamp(1, 7),
      minorsOn: b('minors_on', d.minorsOn),
      minorDesignation: j['minor_designation'] as String? ?? d.minorDesignation,
      minorLatestEnd: _asInt(j['minor_latest_end'], d.minorLatestEnd),
      schoolNights:
          (j['school_nights'] as List?)?.whereType<num>().map((e) => e.toInt()).toList() ??
          d.schoolNights,
      minorMaxHoursPerDay: n('minor_max_hours_per_day', d.minorMaxHoursPerDay),
      usualShifts: b('usual_shifts', d.usualShifts),
      consistency: b('consistency', d.consistency),
      dayNight: b('day_night', d.dayNight),
      avoidClopen: b('avoid_clopen', d.avoidClopen),
      fairHours: b('fair_hours', d.fairHours),
    );
  }

  Map<String, dynamic> toJson() => {
    'max_shifts_per_week': maxShiftsPerWeek,
    'requested_off_is_off': requestedOffIsOff,
    'max_hours_per_day_on': maxHoursPerDayOn,
    'max_hours_per_day': maxHoursPerDay,
    'rest_on': restOn,
    'rest_hours': restHours,
    'max_days_in_row_on': maxDaysInRowOn,
    'max_days_in_row': maxDaysInRow,
    'minors_on': minorsOn,
    'minor_designation': minorDesignation,
    'minor_latest_end': minorLatestEnd,
    'school_nights': schoolNights,
    'minor_max_hours_per_day': minorMaxHoursPerDay,
    'usual_shifts': usualShifts,
    'consistency': consistency,
    'day_night': dayNight,
    'avoid_clopen': avoidClopen,
    'fair_hours': fairHours,
  };
}

class ScheduleConfig {
  /// DateTime weekday number the week starts on (Monday = 1 ... Sunday = 7).
  final int weekStart;

  /// Only team members at [minTitle] or above (in the store's title order)
  /// show up for scheduling.
  final bool minTitleEnabled;
  final String? minTitle;

  /// A new hire's first shifts, in order (day 1, day 2, ...).
  final bool trainingFlowEnabled;
  final List<TrainingDay> trainingDays;

  /// Titles or additional tags whose people can train others. Empty = anyone.
  final List<String> trainerTags;

  /// The store's schedules. The main one is always there (added if missing).
  final List<ScheduleBoard> boards;

  /// The scheduler's rules.
  final ScheduleRules rules;

  List<ScheduleBoard> get allBoards => [
    if (!boards.any((b) => b.isMain))
      const ScheduleBoard(id: kMainBoardId, name: 'Main schedule'),
    ...boards,
  ];

  ScheduleBoard boardById(String id) =>
      allBoards.where((b) => b.id == id).firstOrNull ?? allBoards.first;

  const ScheduleConfig({
    this.weekStart = DateTime.monday,
    this.minTitleEnabled = false,
    this.minTitle,
    this.trainingFlowEnabled = false,
    this.trainingDays = const [],
    this.trainerTags = const [],
    this.boards = const [],
    this.rules = const ScheduleRules(),
  });

  ScheduleConfig copyWith({
    int? weekStart,
    bool? minTitleEnabled,
    String? minTitle,
    bool? trainingFlowEnabled,
    List<TrainingDay>? trainingDays,
    List<String>? trainerTags,
    List<ScheduleBoard>? boards,
    ScheduleRules? rules,
  }) => ScheduleConfig(
    weekStart: weekStart ?? this.weekStart,
    minTitleEnabled: minTitleEnabled ?? this.minTitleEnabled,
    minTitle: minTitle ?? this.minTitle,
    trainingFlowEnabled: trainingFlowEnabled ?? this.trainingFlowEnabled,
    trainingDays: trainingDays ?? this.trainingDays,
    trainerTags: trainerTags ?? this.trainerTags,
    boards: boards ?? this.boards,
    rules: rules ?? this.rules,
  );

  factory ScheduleConfig.fromJson(Map<String, dynamic>? j) {
    final w = _asInt(j?['week_start'], DateTime.monday);
    return ScheduleConfig(
      weekStart: w >= 1 && w <= 7 ? w : DateTime.monday,
      minTitleEnabled: j?['min_title_enabled'] == true,
      minTitle: j?['min_title'] as String?,
      trainingFlowEnabled: j?['training_flow_enabled'] == true,
      trainingDays: _asMapList(j?['training_days']).map(TrainingDay.fromJson).toList(),
      trainerTags:
          (j?['trainer_tags'] as List?)?.whereType<String>().toList() ?? const [],
      boards: _asMapList(j?['boards']).map(ScheduleBoard.fromJson).toList(),
      rules: ScheduleRules.fromJson(
        j?['rules'] is Map ? Map<String, dynamic>.from(j!['rules'] as Map) : null,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'week_start': weekStart,
    'min_title_enabled': minTitleEnabled,
    'min_title': minTitle,
    'training_flow_enabled': trainingFlowEnabled,
    'training_days': trainingDays.map((d) => d.toJson()).toList(),
    'trainer_tags': trainerTags,
    'boards': boards.map((b) => b.toJson()).toList(),
    'rules': rules.toJson(),
  };
}

/// A station on the shift page (Register, Drive-thru, ...). One person at a
/// time; a second spot is its own position (e.g. "Front Counter 2") so it
/// can be ranked separately.
class ShiftPosition {
  final String id;
  final String name;

  const ShiftPosition({required this.id, required this.name});

  ShiftPosition copyWith({String? name}) =>
      ShiftPosition(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

List<ShiftPosition> _positionsFrom(dynamic v) => [
  for (final m in _asMapList(v))
    // Older docs gave a position several "spots": those become separate
    // positions ("Front Counter", "Front Counter 2", …) right after it, with
    // ids `{id}#2`, `{id}#3`, … (see [ScheduleBoard.positionsIn]).
    for (var k = 1; k <= math.max(1, _asInt(m['spots'], 1)); k++)
      ShiftPosition(
        id: k == 1 ? (m['id'] as String? ?? newScheduleId()) : '${m['id']}#$k',
        name: k == 1 ? (m['name'] as String? ?? '') : '${m['name'] ?? ''} $k',
      ),
];

/// A board on the Shift page: the shifts of one or more schedules, deployed
/// onto its own positions (ranked, highest priority first).
class ShiftBoard {
  final String id;
  final String name;
  final List<String> scheduleIds;
  final List<ShiftPosition> positions;

  const ShiftBoard({
    required this.id,
    required this.name,
    this.scheduleIds = const [],
    this.positions = const [],
  });

  ShiftBoard copyWith({
    String? name,
    List<String>? scheduleIds,
    List<ShiftPosition>? positions,
  }) => ShiftBoard(
    id: id,
    name: name ?? this.name,
    scheduleIds: scheduleIds ?? this.scheduleIds,
    positions: positions ?? this.positions,
  );

  factory ShiftBoard.fromJson(Map<String, dynamic> j) => ShiftBoard(
    id: j['id'] as String? ?? newScheduleId(),
    name: j['name'] as String? ?? 'Board',
    scheduleIds:
        (j['schedule_ids'] as List?)?.whereType<String>().toList() ?? const [],
    positions: _positionsFrom(j['positions']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'schedule_ids': scheduleIds,
    'positions': positions.map((p) => p.toJson()).toList(),
  };
}

/// How the Shift page's boards are set up.
enum ShiftBoardLayout {
  /// One board per schedule, named after it.
  perSchedule,

  /// Boards that each combine one or more schedules.
  custom,
}

/// Shift-page settings (/stores/{storeId}/settings/shift_config): the board
/// layout and each board's positions. Both layouts are kept, so switching
/// back and forth doesn't lose anything.
class ShiftConfig {
  final ShiftBoardLayout layout;

  /// "A board for each schedule": positions by schedule id.
  final Map<String, List<ShiftPosition>> scheduleBoards;

  /// "Combine schedules": the boards.
  final List<ShiftBoard> customBoards;

  /// Older docs: one list of positions for the whole store (each schedule
  /// picked some of them). Only read, to set up boards that weren't saved
  /// yet.
  final List<ShiftPosition> positions;

  const ShiftConfig({
    this.layout = ShiftBoardLayout.perSchedule,
    this.scheduleBoards = const {},
    this.customBoards = const [],
    this.positions = const [],
  });

  ShiftConfig copyWith({
    ShiftBoardLayout? layout,
    Map<String, List<ShiftPosition>>? scheduleBoards,
    List<ShiftBoard>? customBoards,
  }) => ShiftConfig(
    layout: layout ?? this.layout,
    scheduleBoards: scheduleBoards ?? this.scheduleBoards,
    customBoards: customBoards ?? this.customBoards,
    positions: positions,
  );

  /// The boards to show, for the store's [schedules].
  List<ShiftBoard> boardsFor(ScheduleConfig schedules) {
    final ids = {for (final s in schedules.allBoards) s.id};
    if (layout == ShiftBoardLayout.custom && customBoards.isNotEmpty) {
      return [
        for (final b in customBoards)
          b.copyWith(scheduleIds: b.scheduleIds.where(ids.contains).toList()),
      ];
    }
    return [
      for (final s in schedules.allBoards)
        ShiftBoard(
          id: s.id,
          name: s.name,
          scheduleIds: [s.id],
          positions: scheduleBoards[s.id] ?? s.positionsIn(positions),
        ),
    ];
  }

  /// The board showing schedule [scheduleId], if any.
  ShiftBoard? boardForSchedule(ScheduleConfig schedules, String scheduleId) =>
      boardsFor(schedules).where((b) => b.scheduleIds.contains(scheduleId)).firstOrNull;

  /// Every position on any board (and older ones), by id.
  Map<String, ShiftPosition> get _byId => {
    for (final p in positions) p.id: p,
    for (final list in scheduleBoards.values)
      for (final p in list) p.id: p,
    for (final b in customBoards)
      for (final p in b.positions) p.id: p,
  };

  ShiftPosition? positionById(String? id) => id == null ? null : _byId[id];

  List<ShiftPosition> get allPositions => _byId.values.toList();

  factory ShiftConfig.fromJson(Map<String, dynamic>? j) {
    final per = j?['schedule_boards'];
    return ShiftConfig(
      layout: j?['layout'] == 'custom'
          ? ShiftBoardLayout.custom
          : ShiftBoardLayout.perSchedule,
      scheduleBoards: {
        if (per is Map)
          for (final e in per.entries)
            if (e.key is String && e.value is Map)
              e.key as String: _positionsFrom((e.value as Map)['positions']),
      },
      customBoards: _asMapList(j?['custom_boards']).map(ShiftBoard.fromJson).toList(),
      positions: _positionsFrom(j?['positions']),
    );
  }

  Map<String, dynamic> toJson() => {
    'layout': layout == ShiftBoardLayout.custom ? 'custom' : 'per_schedule',
    'schedule_boards': {
      for (final e in scheduleBoards.entries)
        e.key: {'positions': e.value.map((p) => p.toJson()).toList()},
    },
    'custom_boards': customBoards.map((b) => b.toJson()).toList(),
    // Older single list: replaced by the boards above.
    'positions': const <dynamic>[],
  };
}

class TimeOffEntry {
  final String userId;
  final String startDate; // yyyy-MM-dd
  final String endDate;
  final String reason;

  /// Set for part-day requests (minutes from midnight on each covered day).
  final int? startMinute;
  final int? endMinute;

  const TimeOffEntry({
    required this.userId,
    required this.startDate,
    required this.endDate,
    this.reason = '',
    this.startMinute,
    this.endMinute,
  });

  bool get isFullDay => startMinute == null || endMinute == null;

  bool covers(String dateKey) =>
      dateKey.compareTo(startDate) >= 0 && dateKey.compareTo(endDate) <= 0;
}

/// Where someone is in the training flow, as last reviewed before building
/// a schedule (/stores/{storeId}/training_progress/{memberId}).
class TrainingProgress {
  final String userId;

  /// Training-flow steps done (indexes into [ScheduleConfig.trainingDays]).
  final Set<int> done;

  /// Taken off the training list ("Not in training").
  final bool notInTraining;

  /// [done] is as of this day (yyyy-MM-dd); days worked from then on count
  /// as the next steps.
  final String? asOf;

  const TrainingProgress({
    required this.userId,
    this.done = const {},
    this.notInTraining = false,
    this.asOf,
  });

  TrainingProgress copyWith({Set<int>? done, bool? notInTraining, String? asOf}) =>
      TrainingProgress(
        userId: userId,
        done: done ?? this.done,
        notInTraining: notInTraining ?? this.notInTraining,
        asOf: asOf ?? this.asOf,
      );

  factory TrainingProgress.fromJson(String userId, Map<String, dynamic> j) =>
      TrainingProgress(
        userId: userId,
        done: {
          for (final v in (j['done'] as List? ?? const []))
            if (v is num) v.toInt(),
        },
        notInTraining: j['not_in_training'] == true,
        asOf: j['as_of'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'done': done.toList()..sort(),
    'not_in_training': notInTraining,
    'as_of': asOf,
  };
}
