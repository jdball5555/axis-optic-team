// Shift-page rules: putting the day's shifts on positions (stations), and the
// new-hire training flow. Pure functions, like schedule_ops.dart.

import 'dart:math' as math;

import '../../../models/schedule_models.dart';

/// Where a new hire is in the training flow: their [day] number (1-based)
/// and what that day calls for.
typedef TrainingStep = ({int day, TrainingDay plan});

/// The training-flow step for someone who was scheduled [priorDays] times
/// before, or null when the flow is off or they're past it.
TrainingStep? trainingStepFor(ScheduleConfig config, int priorDays) {
  if (!config.trainingFlowEnabled) return null;
  if (priorDays < 0 || priorDays >= config.trainingDays.length) return null;
  return (day: priorDays + 1, plan: config.trainingDays[priorDays]);
}

/// Training-flow steps (indexes) someone still has to do, in order: the
/// steps not in [done], minus one for each of the [workedSince] days they've
/// worked since [done] was last reviewed.
List<int> remainingTrainingSteps(int stepCount, Set<int> done, int workedSince) => [
  for (var i = 0; i < stepCount; i++)
    if (!done.contains(i)) i,
].skip(math.max(0, workedSince)).toList();

/// "Shift 2 · Train on Register" / "Shift 3 · Register".
String trainingLabel(TrainingStep step, ShiftConfig shiftConfig) {
  final position = shiftConfig.positionById(step.plan.positionId)?.name;
  final what = step.plan.training
      ? (position == null ? 'Training' : 'Train on $position')
      : (position ?? 'On their own');
  return 'Shift ${step.day} · $what';
}

/// Shifts that must stay on one position for the training flow: a trainer
/// whose trainee is on a training day there, or a new hire's own shift.
Map<String, String> trainingPins(
  ScheduleDay day,
  Map<String, TrainingStep> steps,
) {
  final out = <String, String>{};
  for (final s in day.shifts) {
    final position =
        (s.isTraining ? steps[s.traineeId]?.plan.positionId : null) ??
        steps[s.userId]?.plan.positionId;
    if (position != null) out[s.id] = position;
  }
  return out;
}

bool _working(Shift s, int minute) =>
    s.workPieces.any((p) => minute >= p.start && minute < p.end);

/// The position [shift] is on at [minute], if any.
String? positionAt(Shift shift, int minute) {
  if (!_working(shift, minute)) return null;
  return shift.positions
      .where((p) => minute >= p.start && minute < p.end)
      .firstOrNull
      ?.positionId;
}

/// The parts of [shift] spent on [positionId].
List<PositionSegment> segmentsOn(Shift shift, String positionId) =>
    shift.positions.where((p) => p.positionId == positionId).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

/// Is [shift] on any of the store's positions?
bool isPlaced(Shift shift, ShiftConfig config) =>
    shift.positions.any((p) => config.positionById(p.positionId) != null);

/// How many people are on [positionId] at [minute].
int onPositionAt(
  ScheduleDay day,
  String positionId,
  int minute, {
  String? ignoreShiftId,
}) => day.shifts
    .where(
      (s) => s.id != ignoreShiftId && positionAt(s, minute) == positionId,
    )
    .length;

/// Whether all of [shift] can go on [position] without anyone else on it at
/// the same time.
bool fitsPosition(ScheduleDay day, Shift shift, ShiftPosition position) {
  for (final p in shift.workPieces) {
    for (var t = p.start; t < p.end; t += kScheduleStep) {
      if (onPositionAt(day, position.id, t, ignoreShiftId: shift.id) >=
          1) {
        return false;
      }
    }
  }
  return true;
}

/// Puts a whole shift on one position (null takes it off positions).
ScheduleDay assignPosition(ScheduleDay day, String shiftId, String? positionId) =>
    day.copyWith(
      shifts: [
        for (final s in day.shifts)
          if (s.id != shiftId)
            s
          else
            s.copyWith(
              positions: positionId == null
                  ? const []
                  : [
                      for (final w in mergeWindows(
                        s.workPieces.map((p) => TimeWindow(p.start, p.end)),
                      ))
                        PositionSegment(
                          positionId: positionId,
                          start: w.start,
                          end: w.end,
                        ),
                    ],
            ),
      ],
    );

/// Deploys the whole day by priority. Every position is one seat,
/// highest-priority position first. At each moment the N people
/// working fill the N highest seats, so with 4 people on, the top 4 seats are
/// filled. People only move when they have to (a higher seat opens up, or
/// theirs drops out of the top N); whoever is staying longest takes the
/// higher seat. [pinned] shifts (training flow) stay on their position.
/// More people than seats: the extras have no position at that time.
ScheduleDay deployPositions(
  ScheduleDay day,
  List<ShiftPosition> positions, {
  Map<String, String> pinned = const {},
}) {
  final seats = [for (final p in positions) p.id];
  final shifts = day.shifts.where((s) => s.workPieces.isNotEmpty).toList();
  if (seats.isEmpty || shifts.isEmpty) {
    return day.copyWith(
      shifts: [for (final s in day.shifts) s.copyWith(positions: const [])],
    );
  }
  final lo = shifts.map((s) => s.start).reduce(math.min);
  final hi = shifts.map((s) => s.end).reduce(math.max);
  final seatOf = <String, int>{};
  final out = <String, List<PositionSegment>>{};

  void record(String shiftId, int t, String positionId) {
    final list = out.putIfAbsent(shiftId, () => []);
    final last = list.isEmpty ? null : list.last;
    if (last != null && last.positionId == positionId && last.end == t) {
      list[list.length - 1] = PositionSegment(
        positionId: positionId,
        start: last.start,
        end: t + kScheduleStep,
      );
    } else {
      list.add(
        PositionSegment(positionId: positionId, start: t, end: t + kScheduleStep),
      );
    }
  }

  for (var t = lo; t < hi; t += kScheduleStep) {
    final working = shifts.where((s) => _working(s, t)).toList();
    final ids = {for (final s in working) s.id};
    seatOf.removeWhere((id, _) => !ids.contains(id));
    final taken = <int>{};

    // Pinned shifts first: their own position, even if someone's in it.
    final seatedPins = <String>{};
    for (final s in working) {
      final pin = pinned[s.id];
      if (pin == null || !seats.contains(pin)) continue;
      final cur = seatOf[s.id];
      int? seat = cur != null && seats[cur] == pin && !taken.contains(cur)
          ? cur
          : null;
      if (seat == null) {
        for (var i = 0; i < seats.length; i++) {
          if (seats[i] == pin && !taken.contains(i)) {
            seat = i;
            break;
          }
        }
      }
      if (seat != null) {
        seatOf[s.id] = seat;
        taken.add(seat);
        seatedPins.add(s.id);
      }
    }

    // Everyone else fills the highest free seats.
    final others = working.where((s) => !seatedPins.contains(s.id)).toList();
    final target = [
      for (var i = 0; i < seats.length; i++)
        if (!taken.contains(i)) i,
    ].take(others.length).toSet();
    final movers = <Shift>[];
    for (final s in others) {
      final cur = seatOf[s.id];
      if (cur != null && target.contains(cur) && !taken.contains(cur)) {
        taken.add(cur);
      } else {
        movers.add(s);
      }
    }
    movers.sort((a, b) => b.end.compareTo(a.end));
    final open = target.where((i) => !taken.contains(i)).toList()..sort();
    for (var i = 0; i < movers.length; i++) {
      if (i < open.length) {
        seatOf[movers[i].id] = open[i];
        taken.add(open[i]);
      } else {
        seatOf.remove(movers[i].id);
      }
    }

    for (final s in working) {
      final seat = seatOf[s.id];
      if (seat != null) record(s.id, t, seats[seat]);
    }
  }

  return day.copyWith(
    shifts: [
      for (final s in day.shifts) s.copyWith(positions: out[s.id] ?? const []),
    ],
  );
}

/// "Register 6a – 11a, Drive-thru 11a – 3p".
String positionsSummary(Shift shift, ShiftConfig config) => [
  for (final p in [...shift.positions]..sort((a, b) => a.start.compareTo(b.start)))
    if (config.positionById(p.positionId) case final pos?)
      '${pos.name} ${formatRange(p.start, p.end)}',
].join(', ');

/// People on [positionId] per half hour from [start] to [end], for the
/// little coverage bar on each position tile.
List<int> positionCoverage(
  ScheduleDay day,
  String positionId,
  int start,
  int end,
) => [
  for (var t = start; t < end; t += 30)
    math.max(
      onPositionAt(day, positionId, t),
      onPositionAt(day, positionId, t + 15),
    ),
];

/// The first minute in the hour starting at [hourStart] that [shift] is
/// working, or null if they're off that whole hour.
int? workingMinuteInHour(Shift shift, int hourStart) {
  for (var t = hourStart; t < hourStart + 60; t += kScheduleStep) {
    if (_working(shift, t)) return t;
  }
  return null;
}

/// Puts [shift] on [positionId] from minute [from] to the end of the shift
/// (null takes them off positions from then). Earlier positions stay.
ScheduleDay assignPositionFrom(
  ScheduleDay day,
  String shiftId,
  String? positionId,
  int from,
) => day.copyWith(
  shifts: [
    for (final s in day.shifts)
      if (s.id != shiftId)
        s
      else
        s.copyWith(
          positions: _joinSegments([
            for (final p in s.positions)
              if (p.start < from)
                PositionSegment(
                  positionId: p.positionId,
                  start: p.start,
                  end: math.min(p.end, from),
                ),
            if (positionId != null)
              for (final w in mergeWindows(
                s.workPieces.map((p) => TimeWindow(p.start, p.end)),
              ))
                if (w.end > from)
                  PositionSegment(
                    positionId: positionId,
                    start: math.max(w.start, from),
                    end: w.end,
                  ),
          ]),
        ),
  ],
);

List<PositionSegment> _joinSegments(List<PositionSegment> list) {
  final sorted = [...list]..sort((a, b) => a.start.compareTo(b.start));
  final out = <PositionSegment>[];
  for (final p in sorted) {
    if (p.minutes <= 0) continue;
    final last = out.isEmpty ? null : out.last;
    if (last != null && last.positionId == p.positionId && last.end >= p.start) {
      out[out.length - 1] = PositionSegment(
        positionId: p.positionId,
        start: last.start,
        end: math.max(last.end, p.end),
      );
    } else {
      out.add(p);
    }
  }
  return out;
}

/// Whether [shift] can go on [position] from [from] to the end of the shift
/// without anyone else on it at the same time.
bool fitsPositionFrom(
  ScheduleDay day,
  Shift shift,
  ShiftPosition position,
  int from,
) {
  for (final p in shift.workPieces) {
    for (var t = math.max(p.start, from); t < p.end; t += kScheduleStep) {
      if (onPositionAt(day, position.id, t, ignoreShiftId: shift.id) >=
          1) {
        return false;
      }
    }
  }
  return true;
}

// =============================================================================
// Boards that show several schedules
// =============================================================================

/// One day of a shift board: the days of its schedules merged into one
/// (rows and pieces get the schedule id in front so they stay apart), and
/// which schedule each shift came from.
typedef BoardDay = ({ScheduleDay day, Map<String, String> origin});

/// Merges [bySchedule] (schedule id → its day) into one day for a board.
/// One schedule: its day as is.
BoardDay mergeBoardDay(String date, Map<String, ScheduleDay> bySchedule) {
  if (bySchedule.length == 1) {
    final e = bySchedule.entries.first;
    return (day: e.value, origin: {for (final s in e.value.shifts) s.id: e.key});
  }
  String tag(String sid, String rowId) => '$sid::$rowId';
  final origin = <String, String>{};
  final rows = <ScheduleRow>[];
  final shifts = <Shift>[];
  for (final e in bySchedule.entries) {
    for (final r in e.value.rows) {
      rows.add(r.copyWith(id: tag(e.key, r.id)));
    }
    for (final s in e.value.shifts) {
      origin[s.id] = e.key;
      shifts.add(
        s.copyWith(
          pieces: [for (final p in s.pieces) p.copyWith(rowId: tag(e.key, p.rowId))],
        ),
      );
    }
  }
  return (day: ScheduleDay(date: date, rows: rows, shifts: shifts), origin: origin);
}

/// Splits a board's [merged] day back into its schedules' days ([sources] =
/// what was merged), keeping everything else about each day.
Map<String, ScheduleDay> splitBoardDay(
  ScheduleDay merged,
  Map<String, ScheduleDay> sources,
  Map<String, String> origin,
) {
  if (sources.length == 1) {
    final e = sources.entries.first;
    return {e.key: e.value.copyWith(shifts: merged.shifts)};
  }
  return {
    for (final e in sources.entries)
      e.key: e.value.copyWith(
        shifts: [
          for (final s in merged.shifts)
            if (origin[s.id] == e.key)
              s.copyWith(
                pieces: [
                  for (final p in s.pieces)
                    p.copyWith(
                      rowId: p.rowId.startsWith('${e.key}::')
                          ? p.rowId.substring(e.key.length + 2)
                          : p.rowId,
                    ),
                ],
              ),
        ],
      ),
  };
}
