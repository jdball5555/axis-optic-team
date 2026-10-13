// Pure functions that change a ScheduleDay, plus the rules that decide
// whether a change is allowed. Kept free of UI so the same rules can be used
// by an AI scheduler later.

import 'dart:math' as math;

import '../../../models/schedule_models.dart';
import '../../../models/user_model.dart';
import 'schedule_common.dart';

// =============================================================================
// Rules
// =============================================================================

/// Busy windows for [uid] across the day, optionally ignoring one piece and/or
/// every piece of one shift.
List<(Shift, ShiftPiece)> _busy(
  ScheduleDay day,
  String uid, {
  String? ignorePieceId,
  String? ignoreShiftId,
}) => [
  for (final s in day.shifts)
    if (s.involves(uid) && s.id != ignoreShiftId)
      for (final p in s.pieces)
        if (p.id != ignorePieceId) (s, p),
];

/// Returns a reason the piece can't be placed, or null if it's fine.
String? pieceConflict(
  ScheduleDay day, {
  required String userId,
  String? traineeId,
  required String rowId,
  required int start,
  required int end,
  String? ignorePieceId,
  required Map<String, UserModel> users,
}) {
  if (end <= start) return 'End time must be after the start time.';
  final row = day.rowById(rowId);
  if (row == null) return 'That row no longer exists.';

  final user = users[userId];
  if (!userFitsRow(user, row)) {
    return '${personName(user)} can\'t fill this row '
        '(only ${row.allowedTitles.join(', ')}).';
  }

  for (final (s, p) in day.piecesInRow(rowId)) {
    if (p.id == ignorePieceId) continue;
    if (p.overlaps(start, end)) {
      return 'This row already has ${personName(users[s.userId])} from '
          '${formatRange(p.start, p.end)}.';
    }
  }

  for (final (_, p) in _busy(day, userId, ignorePieceId: ignorePieceId)) {
    if (p.overlaps(start, end)) {
      return '${personName(user)} is already working '
          '${formatRange(p.start, p.end)}.';
    }
  }

  if (traineeId != null && traineeId.isNotEmpty) {
    if (traineeId == userId) return 'The trainee must be someone else.';
    final own = day.shiftForUser(userId);
    for (final (_, p) in _busy(
      day,
      traineeId,
      ignorePieceId: ignorePieceId,
      ignoreShiftId: own?.id,
    )) {
      if (p.overlaps(start, end)) {
        return '${personName(users[traineeId])} is already working '
            '${formatRange(p.start, p.end)}.';
      }
    }
  }
  return null;
}

List<TimeWindow> _intersect(List<TimeWindow> a, List<TimeWindow> b) => [
  for (final x in a)
    for (final y in b)
      if (x.overlaps(y.start, y.end))
        TimeWindow(
          x.start > y.start ? x.start : y.start,
          x.end < y.end ? x.end : y.end,
        ),
];

/// Whole-day time off on [date].
bool _hasTimeOff(UserModel user, DateTime date, List<TimeOffEntry> timeOff) {
  final key = dateKey(date);
  return timeOff.any(
    (t) => t.userId == user.id && t.isFullDay && t.covers(key),
  );
}

List<TimeWindow> _partTimeOff(
  UserModel user,
  DateTime date,
  List<TimeOffEntry> timeOff,
) {
  final key = dateKey(date);
  return [
    for (final t in timeOff)
      if (t.userId == user.id && !t.isFullDay && t.covers(key))
        TimeWindow(t.startMinute!, t.endMinute!),
  ];
}

/// When [user] can work on [date]: their availability minus part-day time
/// off. Null = no limits at all; empty = can't work that day.
List<TimeWindow>? _workWindows(
  UserModel user,
  DateTime date,
  List<TimeOffEntry> timeOff,
) {
  if (_hasTimeOff(user, date, timeOff)) return const [];
  final off = _partTimeOff(user, date, timeOff);
  final raw = availabilityFor(user, date);
  if (raw == null && off.isEmpty) return null;
  final base = raw == null
      ? const [TimeWindow(0, kMaxScheduleMinute)]
      : mergeWindows(raw);
  return mergeWindows(subtractWindows(base, off));
}

/// Why [user] can't work [start]–[end] on [date] (time off or outside their
/// availability), or null if they can. This blocks scheduling.
String? availabilityConflict(
  UserModel? user, {
  required DateTime date,
  required int start,
  required int end,
  required List<TimeOffEntry> timeOff,
}) {
  if (user == null) return null;
  if (_hasTimeOff(user, date, timeOff)) {
    return '${personName(user)} has approved time off.';
  }
  final windows = _workWindows(user, date, timeOff);
  if (windows == null || windows.any((w) => w.containsRange(start, end))) {
    return null;
  }
  final off = _partTimeOff(user, date, timeOff)
      .where((w) => w.overlaps(start, end))
      .firstOrNull;
  if (off != null) {
    return '${personName(user)} has time off ${formatRange(off.start, off.end)}.';
  }
  final avail = mergeWindows(availabilityFor(user, date) ?? const []);
  return avail.isEmpty
      ? '${personName(user)} is not available on '
            '${weekdayNames[date.weekday - 1]}s.'
      : 'Outside ${personName(user)}\'s availability '
            '(${avail.map((w) => formatRange(w.start, w.end)).join(', ')}).';
}

/// The longest part of [start]–[end] that [user] can work, or null if none.
TimeWindow? workableRange(
  UserModel user, {
  required DateTime date,
  required int start,
  required int end,
  required List<TimeOffEntry> timeOff,
}) {
  final windows = _workWindows(user, date, timeOff);
  if (windows == null) return TimeWindow(start, end);
  final parts = _intersect(windows, [TimeWindow(start, end)]);
  if (parts.isEmpty) return null;
  return parts.reduce((a, b) => b.minutes > a.minutes ? b : a);
}

/// Someone who could still be added to a day. [canWork] is null when they're
/// free for all of the day's needed time, otherwise the parts they can cover.
typedef AvailablePerson = ({UserModel user, List<TimeWindow>? canWork});

/// Splits the people not on [day] yet into who can work (for at least part
/// of the needed time), who has the whole day off (approved or requested),
/// and how many aren't available at all.
({List<AvailablePerson> people, List<UserModel> timeOff, int unavailable})
availablePeople(
  ScheduleDay day, {
  required DateTime date,
  required List<UserModel> people,
  required List<TimeOffEntry> timeOff,
}) {
  final needed = mergeWindows(day.rows.expand((r) => r.windows));
  final out = <AvailablePerson>[];
  final off = <UserModel>[];
  var unavailable = 0;
  for (final u in people) {
    if (u.id == null || day.shifts.any((s) => s.involves(u.id!))) continue;
    if (_hasTimeOff(u, date, timeOff)) {
      off.add(u);
      continue;
    }
    final windows = _workWindows(u, date, timeOff);
    if (windows == null) {
      out.add((user: u, canWork: null));
      continue;
    }
    final overlap = needed.isEmpty
        ? windows
        : mergeWindows(_intersect(windows, needed));
    if (overlap.isEmpty) {
      unavailable++;
    } else {
      final full = needed.isNotEmpty && subtractWindows(needed, windows).isEmpty;
      out.add((user: u, canWork: full ? null : overlap));
    }
  }
  return (people: out, timeOff: off, unavailable: unavailable);
}

/// Soft warnings (shown, but don't block saving).
List<String> pieceWarnings(
  ScheduleDay day, {
  required DateTime date,
  required UserModel? user,
  required ScheduleRow? row,
  required int start,
  required int end,
  required List<TimeOffEntry> timeOff,
}) {
  final out = <String>[];
  if (user == null) return out;
  final unavailable = availabilityConflict(
    user,
    date: date,
    start: start,
    end: end,
    timeOff: timeOff,
  );
  if (unavailable != null) out.add(unavailable);

  if (row != null && row.windows.isNotEmpty) {
    final inside = row.windows.any((w) => w.containsRange(start, end));
    if (!inside) out.add('Part of this is outside the row\'s needed times.');
  }
  return out;
}

/// Warnings for every piece already on the grid (drives the red outlines).
Map<String, String> dayWarnings(
  ScheduleDay day, {
  required DateTime date,
  required Map<String, UserModel> users,
  required List<TimeOffEntry> timeOff,
}) {
  final out = <String, String>{};
  for (final s in day.shifts) {
    for (final p in s.pieces) {
      final row = day.rowById(p.rowId);
      final msgs = <String>[
        if (row != null && !userFitsRow(users[s.userId], row))
          'Not allowed in this row (only ${row.allowedTitles.join(', ')}).',
        ...pieceWarnings(
          day,
          date: date,
          user: users[s.userId],
          row: null, // being outside the row window is normal-ish; skip here
          start: p.start,
          end: p.end,
          timeOff: timeOff,
        ),
        if (s.isTraining)
          ...pieceWarnings(
            day,
            date: date,
            user: users[s.traineeId],
            row: null,
            start: p.start,
            end: p.end,
            timeOff: timeOff,
          ),
      ];
      if (msgs.isNotEmpty) out[p.id] = msgs.join('\n');
    }
  }
  return out;
}

// =============================================================================
// Operations
// =============================================================================

/// Joins pieces of the same shift that touch inside the same row.
Shift _mergeTouching(Shift s) {
  final sorted = [...s.pieces]..sort((a, b) => a.start.compareTo(b.start));
  final out = <ShiftPiece>[];
  for (final p in sorted) {
    final i = out.lastIndexWhere((q) => q.rowId == p.rowId && q.end == p.start);
    if (i >= 0) {
      out[i] = out[i].copyWith(end: p.end);
    } else {
      out.add(p);
    }
  }
  return s.copyWith(pieces: out);
}

ScheduleDay _replaceShift(ScheduleDay day, Shift updated) {
  final shifts = [
    for (final s in day.shifts) s.id == updated.id ? _mergeTouching(updated) : s,
  ].where((s) => s.pieces.isNotEmpty).toList();
  return day.copyWith(shifts: shifts);
}

/// Adds a piece. If the person already has a shift today, the piece joins it
/// (that's how one shift ends up split across rows).
ScheduleDay addPiece(
  ScheduleDay day, {
  required String userId,
  String? traineeId,
  required String rowId,
  required int start,
  required int end,
}) {
  final piece = ShiftPiece(
    id: newScheduleId(),
    rowId: rowId,
    start: start,
    end: end,
  );
  final existing = day.shiftForUser(userId);
  if (existing != null) {
    return _replaceShift(
      day,
      existing.copyWith(
        pieces: [...existing.pieces, piece],
        traineeId: existing.isTraining ? null : traineeId,
      ),
    );
  }
  final shift = Shift(
    id: newScheduleId(),
    userId: userId,
    traineeId: (traineeId?.isEmpty ?? true) ? null : traineeId,
    pieces: [piece],
  );
  return day.copyWith(shifts: [...day.shifts, shift]);
}

ScheduleDay updatePiece(
  ScheduleDay day,
  String pieceId, {
  String? rowId,
  int? start,
  int? end,
}) {
  final s = day.shiftOfPiece(pieceId);
  if (s == null) return day;
  return _replaceShift(
    day,
    s.copyWith(
      pieces: [
        for (final p in s.pieces)
          p.id == pieceId ? p.copyWith(rowId: rowId, start: start, end: end) : p,
      ],
    ),
  );
}

ScheduleDay removePiece(ScheduleDay day, String pieceId) {
  final s = day.shiftOfPiece(pieceId);
  if (s == null) return day;
  return _replaceShift(
    day,
    s.copyWith(pieces: s.pieces.where((p) => p.id != pieceId).toList()),
  );
}

ScheduleDay removeShift(ScheduleDay day, String shiftId) =>
    day.copyWith(shifts: day.shifts.where((s) => s.id != shiftId).toList());

ScheduleDay setTrainee(ScheduleDay day, String shiftId, String? traineeId) {
  final s = day.shiftById(shiftId);
  if (s == null) return day;
  return _replaceShift(
    day,
    (traineeId == null || traineeId.isEmpty)
        ? s.copyWith(clearTrainee: true)
        : s.copyWith(traineeId: traineeId),
  );
}

/// Splits a piece at [at] and puts one part into [targetRowId].
/// [moveLater] = true moves the part after [at] (e.g. "off at 3, so 11–3
/// moves up into the 11–3 row").
ScheduleDay splitPiece(
  ScheduleDay day,
  String pieceId, {
  required int at,
  required bool moveLater,
  required String targetRowId,
}) {
  final s = day.shiftOfPiece(pieceId);
  if (s == null) return day;
  final p = s.pieces.firstWhere((x) => x.id == pieceId);
  if (at <= p.start || at >= p.end) return day;
  final first = p.copyWith(end: at, rowId: moveLater ? p.rowId : targetRowId);
  final second = ShiftPiece(
    id: newScheduleId(),
    rowId: moveLater ? targetRowId : p.rowId,
    start: at,
    end: p.end,
  );
  return _replaceShift(
    day,
    s.copyWith(
      pieces: [
        for (final x in s.pieces)
          if (x.id != pieceId) x,
        first,
        second,
      ],
    ),
  );
}

ScheduleDay addRow(ScheduleDay day, ScheduleRow row) =>
    day.copyWith(rows: [...day.rows, row]);

ScheduleDay replaceRow(ScheduleDay day, ScheduleRow row) => day.copyWith(
  rows: [for (final r in day.rows) r.id == row.id ? row : r],
);

ScheduleDay removeRow(ScheduleDay day, String rowId) => day.copyWith(
  rows: day.rows.where((r) => r.id != rowId).toList(),
  shifts: [
    for (final s in day.shifts)
      s.copyWith(pieces: s.pieces.where((p) => p.rowId != rowId).toList()),
  ].where((s) => s.pieces.isNotEmpty).toList(),
);

/// Applies a template to a day. Existing pieces stay in the same row position
/// (row 1 -> row 1, ...). If the old day had more rows than the template, the
/// extra rows are kept (without needed times) so no one disappears.
ScheduleDay applyTemplate(ScheduleDay day, ScheduleTemplate t) {
  final newRows = [
    for (final r in t.rows)
      r.copyWith(id: newScheduleId(), windows: mergeWindows(r.windows)),
  ];
  final idMap = <String, String>{};
  for (var i = 0; i < day.rows.length; i++) {
    final old = day.rows[i];
    if (i < newRows.length) {
      idMap[old.id] = newRows[i].id;
    } else if (day.piecesInRow(old.id).isNotEmpty) {
      final extra = old.copyWith(
        id: newScheduleId(),
        label: old.label.isEmpty ? 'Extra' : old.label,
        windows: const [],
      );
      newRows.add(extra);
      idMap[old.id] = extra.id;
    }
  }
  final shifts = [
    for (final s in day.shifts)
      s.copyWith(
        pieces: [
          for (final p in s.pieces)
            if (p.admin)
              p // admin time isn't in a row: it stays as is
            else if (idMap.containsKey(p.rowId))
              p.copyWith(rowId: idMap[p.rowId]),
        ],
      ),
  ].where((s) => s.pieces.isNotEmpty).toList();
  return day.copyWith(
    templateId: t.id,
    templateName: t.name,
    rows: newRows,
    shifts: shifts,
  );
}

// =============================================================================
// Template row packing
// =============================================================================

bool _sameKind(ScheduleRow a, ScheduleRow b) =>
    a.label == b.label &&
    a.allowedTitles.toSet().containsAll(b.allowedTitles) &&
    b.allowedTitles.toSet().containsAll(a.allowedTitles);

bool _hasRoomFor(ScheduleRow row, List<TimeWindow> windows) => windows.every(
  (w) => !row.windows.any((x) => x.overlaps(w.start, w.end)),
);

/// Adds [incoming] rows to [rows], putting each one's windows into the first
/// existing row of the same kind that is free for all of them (so an 11–5 row
/// and a 6–10 row become one row). Rows that don't fit anywhere are appended.
List<ScheduleRow> packRows(List<ScheduleRow> rows, List<ScheduleRow> incoming) {
  final result = [...rows];
  for (final row in incoming) {
    final i = row.windows.isEmpty
        ? -1
        : result.indexWhere(
            (r) =>
                r.windows.isNotEmpty &&
                _sameKind(r, row) &&
                _hasRoomFor(r, row.windows),
          );
    if (i < 0) {
      result.add(row);
    } else {
      result[i] = result[i].copyWith(
        windows: mergeWindows([...result[i].windows, ...row.windows]),
      );
    }
  }
  return result;
}

/// Re-packs every row of a template; returns the same rows when nothing can
/// be combined.
List<ScheduleRow> compactRows(List<ScheduleRow> rows) => packRows(const [], rows);

/// A [length]-minute shift inside [area] starting at [at] (snapped to 15
/// minutes). Pulled earlier if it would run past the end of [area]; shorter
/// when [area] itself is shorter.
TimeWindow placeShift(TimeWindow area, int at, {int length = 6 * 60}) {
  final len = length < area.minutes ? length : area.minutes;
  final snapped = (at ~/ kScheduleStep) * kScheduleStep;
  final start = snapped.clamp(area.start, area.end - len).toInt();
  return TimeWindow(start, start + len);
}

/// Adds a needed bar to a row (joined with any bar it touches). Returns null
/// when it would overlap a bar already in that row.
ScheduleRow? addBarToRow(ScheduleRow row, TimeWindow w) {
  if (row.windows.any((x) => x.overlaps(w.start, w.end))) return null;
  return row.copyWith(windows: mergeWindows([...row.windows, w]));
}

// =============================================================================
// Inserting a whole shift (the "drag shift here" lane)
// =============================================================================

/// Part of someone's shift that was moved to another row to make room.
typedef MovedPart = ({String userId, TimeWindow window, int toRow});

int _openMinutes(ScheduleDay d) => d.rows.fold(
  0,
  (a, r) => a + d.openGaps(r).fold(0, (b, w) => b + w.minutes),
);

int _pieceCount(ScheduleDay d) =>
    d.shifts.fold(0, (a, s) => a + s.pieces.length);

/// Hand-offs: a piece that starts right where another ends in the same row.
int _handoffs(ScheduleDay d) {
  var n = 0;
  for (final r in d.rows) {
    final ps = d.piecesInRow(r.id).map((e) => e.$2).toList();
    for (final a in ps) {
      if (ps.any((b) => b.start == a.end)) n++;
    }
  }
  return n;
}

bool _rowFree(ScheduleDay d, String rowId, TimeWindow w) =>
    !d.piecesInRow(rowId).any((e) => e.$2.overlaps(w.start, w.end));

ScheduleDay _setPieces(ScheduleDay d, String shiftId, List<ShiftPiece> pieces) =>
    d.copyWith(
      shifts: [
        for (final s in d.shifts)
          s.id == shiftId ? s.copyWith(pieces: pieces) : s,
      ],
    );

/// Puts the new shift whole into row [r]. Whatever overlaps it there is cut
/// out of those shifts and re-placed in other rows (preferring rows lower
/// down that need someone then), or in an "Extra" row if nothing is free.
({ScheduleDay day, List<MovedPart> moved, int extraRows}) _insertAt(
  ScheduleDay day,
  int r,
  String userId,
  TimeWindow w,
  Map<String, UserModel> users, {
  String? traineeId,
}) {
  var d = day;
  final rowId = d.rows[r].id;
  final displaced = <(String, TimeWindow)>[];
  for (final (s, p) in d.piecesInRow(rowId).toList()) {
    if (!p.overlaps(w.start, w.end)) continue;
    final cut = TimeWindow(math.max(p.start, w.start), math.min(p.end, w.end));
    displaced.add((s.id, cut));
    final shift = d.shiftById(s.id)!;
    d = _setPieces(d, s.id, [
      for (final q in shift.pieces)
        if (q.id != p.id)
          q
        else ...[
          if (p.start < cut.start) p.copyWith(end: cut.start),
          if (p.end > cut.end)
            ShiftPiece(
              id: newScheduleId(),
              rowId: p.rowId,
              start: cut.end,
              end: p.end,
            ),
        ],
    ]);
  }

  final moved = <MovedPart>[];
  var extraRows = 0;
  displaced.sort((a, b) => b.$2.minutes.compareTo(a.$2.minutes));
  for (final (shiftId, part) in displaced) {
    final shift = d.shiftById(shiftId)!;
    final user = users[shift.userId];
    int? best;
    List<int>? bestScore;
    for (var j = 0; j < d.rows.length; j++) {
      final row = d.rows[j];
      if (j == r || !userFitsRow(user, row) || !_rowFree(d, row.id, part)) {
        continue;
      }
      final covers = subtractWindows(
        [part],
        subtractWindows([part], d.openGaps(row)),
      ).fold(0, (a, x) => a + x.minutes);
      final joinsOwn = shift.pieces.any(
        (q) => q.rowId == row.id && (q.end == part.start || q.start == part.end),
      );
      // Higher is better for each, compared in order.
      final score = [covers, joinsOwn ? 1 : 0, j > r ? 1 : 0, -j];
      if (bestScore == null || _better(score, bestScore)) {
        best = j;
        bestScore = score;
      }
    }
    if (best == null) {
      d = addRow(d, ScheduleRow(id: newScheduleId(), label: 'Extra'));
      best = d.rows.length - 1;
      extraRows++;
    }
    d = _setPieces(d, shiftId, [
      ...d.shiftById(shiftId)!.pieces,
      ShiftPiece(
        id: newScheduleId(),
        rowId: d.rows[best].id,
        start: part.start,
        end: part.end,
      ),
    ]);
    moved.add((userId: shift.userId, window: part, toRow: best));
  }

  d = addPiece(
    d,
    userId: userId,
    traineeId: traineeId,
    rowId: rowId,
    start: w.start,
    end: w.end,
  );
  d = d.copyWith(
    shifts: [
      for (final s in d.shifts)
        if (s.pieces.isNotEmpty) _mergeTouching(s),
    ],
  );
  return (day: d, moved: moved, extraRows: extraRows);
}

bool _better(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Adds [userId]'s shift [w] to the day as one whole piece, in whichever row
/// leaves the least time uncovered. Parts of other shifts that are in the way
/// get pushed to other rows. Ties go to fewer splits, then to rows where it
/// hands off with another shift (e.g. ends at 5 where someone starts at 5),
/// then to the higher row.
({ScheduleDay day, List<MovedPart> moved}) insertShift(
  ScheduleDay day, {
  required String userId,
  required TimeWindow w,
  required Map<String, UserModel> users,
  String? traineeId,
}) {
  final user = users[userId];
  ({ScheduleDay day, List<MovedPart> moved, int extraRows})? best;
  List<int>? bestScore;

  void consider(
    ({ScheduleDay day, List<MovedPart> moved, int extraRows}) attempt,
    int rowIndex,
  ) {
    final score = [
      -_openMinutes(attempt.day),
      -attempt.extraRows,
      -_pieceCount(attempt.day),
      _handoffs(attempt.day),
      -rowIndex,
    ];
    if (bestScore == null || _better(score, bestScore!)) {
      best = attempt;
      bestScore = score;
    }
  }

  for (var r = 0; r < day.rows.length; r++) {
    if (!userFitsRow(user, day.rows[r])) continue;
    consider(_insertAt(day, r, userId, w, users, traineeId: traineeId), r);
  }
  // Fallback: an extra row of its own.
  final withExtra = addRow(day, ScheduleRow(id: newScheduleId(), label: 'Extra'));
  final extra = _insertAt(
    withExtra,
    withExtra.rows.length - 1,
    userId,
    w,
    users,
    traineeId: traineeId,
  );
  consider(
    (day: extra.day, moved: extra.moved, extraRows: extra.extraRows + 1),
    withExtra.rows.length - 1,
  );
  return (day: best!.day, moved: best!.moved);
}

/// The pieces of [shift] after dragging its start (or its end, if [atEnd])
/// to minute [t]. Shrinking eats pieces from that end in order, so a split
/// shift loses its last section first and then moves on into the one before.
/// Growing stretches the first / last piece.
List<ShiftPiece> resizeShiftPieces(
  Shift shift, {
  required bool atEnd,
  required int t,
}) {
  final sorted = [...shift.pieces]..sort((a, b) => a.start.compareTo(b.start));
  if (sorted.isEmpty) return sorted;
  final out = <ShiftPiece>[];
  if (atEnd) {
    for (final p in sorted) {
      if (p.start >= t) continue;
      out.add(p.end > t ? p.copyWith(end: t) : p);
    }
    if (out.isNotEmpty && t > shift.end) out.last = out.last.copyWith(end: t);
  } else {
    for (final p in sorted) {
      if (p.end <= t) continue;
      out.add(p.start < t ? p.copyWith(start: t) : p);
    }
    if (out.isNotEmpty && t < shift.start) {
      out.first = out.first.copyWith(start: t);
    }
  }
  return out;
}

/// Replaces a shift's pieces (touching pieces in a row are joined).
ScheduleDay setShiftPieces(
  ScheduleDay day,
  String shiftId,
  List<ShiftPiece> pieces,
) {
  final shift = day.shiftById(shiftId);
  if (shift == null) return day;
  return _replaceShift(day, shift.copyWith(pieces: pieces));
}

/// When [user] can work on [date] (availability minus part-day time off).
/// Null = no limits; empty = can't work that day.
List<TimeWindow>? workWindowsFor(
  UserModel user,
  DateTime date,
  List<TimeOffEntry> timeOff,
) => _workWindows(user, date, timeOff);

/// A person's shift as continuous blocks of time, ignoring which rows the
/// pieces sit in (used by the team-member view).
List<TimeWindow> shiftBlocks(Shift shift) =>
    mergeWindows(shift.pieces.map((p) => TimeWindow(p.start, p.end)));

/// Team-member view: gives [userId] the block [w], replacing [old] (one of
/// their blocks) when set. The block is placed whole into the rows the same
/// way as the "drag shift here" lane does it.
ScheduleDay setPersonBlock(
  ScheduleDay day, {
  required String userId,
  required TimeWindow w,
  required Map<String, UserModel> users,
  TimeWindow? old,
}) {
  var d = day;
  final shift = d.shiftForUser(userId);
  final traineeId = shift?.traineeId;
  if (shift != null && old != null) {
    d = setShiftPieces(d, shift.id, [
      for (final p in shift.pieces)
        if (!(p.start >= old.start && p.end <= old.end)) p,
    ]);
  }
  return insertShift(
    d,
    userId: userId,
    traineeId: traineeId,
    w: w,
    users: users,
  ).day;
}

/// A stretch of the day with fewer people working than needed.
typedef Shortage = ({TimeWindow window, int need, int have});

/// Times on [day] where fewer people are working than the template needs,
/// merged into ranges with the same numbers (e.g. 6–9 AM need 3, have 1).
List<Shortage> shortages(ScheduleDay day) {
  final out = <Shortage>[];
  if (day.rows.isEmpty) return out;
  final starts = day.rows.expand((r) => r.windows).map((w) => w.start);
  final ends = day.rows.expand((r) => r.windows).map((w) => w.end);
  if (starts.isEmpty) return out;
  final lo = starts.reduce(math.min);
  final hi = ends.reduce(math.max);
  for (var t = lo; t < hi; t += kScheduleStep) {
    final need = day.neededAt(t);
    final have = day.scheduledAt(t);
    if (have >= need) continue;
    final last = out.isEmpty ? null : out.last;
    if (last != null &&
        last.window.end == t &&
        last.need == need &&
        last.have == have) {
      out[out.length - 1] = (
        window: TimeWindow(last.window.start, t + kScheduleStep),
        need: need,
        have: have,
      );
    } else {
      out.add((window: TimeWindow(t, t + kScheduleStep), need: need, have: have));
    }
  }
  return out;
}

/// "6a – 9a need 3, have 1" for each shortage.
String describeShortages(List<Shortage> list) => list
    .map(
      (s) =>
          '${formatRange(s.window.start, s.window.end)} '
          '(need ${s.need}, have ${s.have})',
    )
    .join(', ');
