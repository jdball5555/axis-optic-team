import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/store_settings_model.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../services/schedule_repository.dart';
import '../views/schedule/position_ops.dart';
import '../views/schedule/schedule_common.dart';
import '../views/schedule/training_flow.dart';
import 'mobile_ui.dart';

/// The Shift board on a phone: pick an hour, see every position, and (with
/// access) long-press someone and drag them onto a position, or tap them to
/// choose one. Same rules and saving as the desktop Shift page.
class ShiftBoardMobile extends ConsumerStatefulWidget {
  const ShiftBoardMobile({
    super.key,
    required this.storeId,
    required this.date,
    required this.canEdit,
  });

  final String storeId;
  final DateTime date;
  final bool canEdit;

  @override
  ConsumerState<ShiftBoardMobile> createState() => _ShiftBoardMobileState();
}

class _ShiftBoardMobileState extends ConsumerState<ShiftBoardMobile> {
  int? _hour;
  DateTime? _hourFor;
  final _hourScroll = ScrollController();

  /// The board's schedules' days on screen (set in build) and which schedule
  /// each shift came from, so changes are saved back to the right one.
  Map<String, ScheduleDay> _sources = const {};
  Map<String, String> _origin = const {};

  @override
  void dispose() {
    _hourScroll.dispose();
    super.dispose();
  }

  ScheduleRepository _repoFor(String scheduleId) => ref.read(
    boardRepositoryProvider((storeId: widget.storeId, boardId: scheduleId)),
  );

  Future<void> _save(ScheduleDay day) async {
    final sources = _sources;
    try {
      final parts = splitBoardDay(day, sources, _origin);
      for (final e in parts.entries) {
        final before = sources[e.key];
        if (before != null &&
            jsonEncode(before.toJson()) == jsonEncode(e.value.toJson())) {
          continue;
        }
        await _repoFor(e.key).saveDay(e.value);
      }
    } catch (_) {
      if (mounted) mSnack(context, 'Couldn\'t save. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final storeId = widget.storeId;
    final date = widget.date;
    if (_hourFor != date) {
      _hourFor = date;
      _hour = null;
    }

    final config =
        ref.watch(scheduleConfigProvider(storeId)).valueOrNull ??
        const ScheduleConfig();
    final shiftConfig =
        ref.watch(shiftConfigProvider(storeId)).valueOrNull ??
        const ShiftConfig();
    final boards = shiftConfig.boardsFor(config);
    final selected = ref.watch(selectedShiftBoardProvider(storeId));
    final board =
        boards.where((b) => b.id == selected).firstOrNull ??
        boards.firstOrNull ??
        const ShiftBoard(id: '', name: 'Board');
    final positions = board.positions;
    final weekStart = weekStartFor(date, config.weekStart);

    var loading = false;
    final sources = <String, ScheduleDay>{};
    for (final sid in board.scheduleIds) {
      final weekAsync = ref.watch(
        scheduleWeekProvider((
          storeId: storeId,
          weekStart: dateKey(weekStart),
          boardId: sid,
        )),
      );
      if (weekAsync.isLoading && !weekAsync.hasValue) loading = true;
      sources[sid] =
          weekAsync.valueOrNull?[dateKey(date)] ?? ScheduleDay.empty(dateKey(date));
    }
    final merged = mergeBoardDay(dateKey(date), sources);
    _sources = sources;
    _origin = merged.origin;
    final day = merged.day;

    final users = {
      for (final u in ref.watch(usersStreamProvider).valueOrNull ?? const <UserModel>[])
        if (u.id != null) u.id!: u,
    };
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final titleOrder = (settings?.titles ?? const <TitleConfig>[])
        .map((t) => t.name)
        .where((n) => n.isNotEmpty)
        .toList();
    final steps = <String, TrainingStep>{
      for (final e in sources.entries)
        ...trainingStepsFor(
          ref,
          storeId: storeId,
          boardId: e.key,
          date: date,
          people: [
            for (final s in e.value.shifts) ?users[s.userId],
            for (final s in e.value.shifts) ?users[s.traineeId],
          ],
          config: config,
          titleOrder: titleOrder,
        ),
    };

    final header = <Widget>[
      if (boards.length > 1 || (widget.canEdit && positions.isNotEmpty))
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              if (boards.length > 1)
                BoardSwitcher(
                  boards: [for (final b in boards) (id: b.id, name: b.name)],
                  selectedId: board.id,
                  tooltip: 'Switch board',
                  onChanged: (id) =>
                      ref.read(selectedShiftBoardProvider(storeId).notifier).state = id,
                ),
              const Spacer(),
              if (widget.canEdit && positions.isNotEmpty)
                FilledButton.icon(
                  onPressed: day.shifts.isEmpty
                      ? null
                      : () => _autoFill(day, positions, steps),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Auto-fill'),
                ),
            ],
          ),
        ),
    ];

    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (board.scheduleIds.isEmpty || positions.isEmpty) {
      return Column(
        children: [
          ...header,
          const MEmpty(
            icon: Icons.grid_view_outlined,
            title: 'No positions yet',
            message: 'Set up this board\'s positions in Shift board settings on the desktop app.',
            compact: true,
          ),
        ],
      );
    }
    if (day.shifts.isEmpty) {
      return Column(
        children: [
          ...header,
          MEmpty(
            icon: Icons.event_busy_outlined,
            title: 'No one scheduled',
            message: 'Nothing is on the schedule for ${weekdayNames[date.weekday - 1]}.',
            compact: true,
          ),
        ],
      );
    }

    // Hours of the day and the one being looked at.
    final (dayStart, dayEnd) = timelineRange(day.rows, day.shifts);
    final hours = [for (var h = dayStart; h < dayEnd; h += 60) h];
    var hour = _hour;
    if (hour == null || !hours.contains(hour)) {
      final now = DateTime.now();
      final nowHour = now.hour * 60;
      hour = dateOnly(now) == date && hours.contains(nowHour)
          ? nowHour
          : hours.firstWhere(
              (h) => day.shifts.any((s) => workingMinuteInHour(s, h) != null),
              orElse: () => hours.first,
            );
    }
    final at = hour;
    int? refMinute(Shift s) => workingMinuteInHour(s, at);
    final positionIds = {for (final p in positions) p.id};
    final working = day.shifts.where((s) => refMinute(s) != null).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    bool placedNow(Shift s) => positionIds.contains(positionAt(s, refMinute(s) ?? at));
    final unplaced = working.where((s) => !placedNow(s)).toList();

    String? trainingFor(String? uid) {
      final step = uid == null ? null : steps[uid];
      return step == null ? null : trainingLabel(step, shiftConfig);
    }

    void place(String shiftId, ShiftPosition? position) {
      final shift = day.shiftById(shiftId);
      if (shift == null) return;
      final from = refMinute(shift) ?? at;
      if (position != null && !fitsPositionFrom(day, shift, position, from)) {
        mSnack(context, '${position.name} is taken from ${formatMinutes(from)} on.');
        return;
      }
      HapticFeedback.selectionClick();
      _save(assignPositionFrom(day, shiftId, position?.id, from));
    }

    Future<void> choose(Shift s) async {
      if (!widget.canEdit) return;
      final from = refMinute(s) ?? at;
      final current = positionAt(s, from);
      final pick = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Theme.of(context).cardColor,
        builder: (ctx) {
          final cc = MColors(ctx);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.92,
            builder: (ctx, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(
                    personName(users[s.userId]),
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: cc.title),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Put them on a position from ${hourLabel(from)} to the end of their shift.',
                    style: TextStyle(fontSize: 13, color: cc.muted),
                  ),
                ),
                if (current != null && positionIds.contains(current))
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: Icon(Icons.remove_circle_outline, color: AppTheme.red),
                    title: Text(
                      'Take off ${shiftConfig.positionById(current)?.name ?? 'position'}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.red),
                    ),
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                for (var i = 0; i < positions.length; i++)
                  Builder(
                    builder: (_) {
                      final p = positions[i];
                      final isHere = p.id == current;
                      final fits = isHere || fitsPositionFrom(day, s, p, from);
                      return ListTile(
                        enabled: fits && !isHere,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: _RankBadge(rank: i + 1),
                        title: Text(
                          p.name.isEmpty ? 'Untitled' : p.name,
                          style: TextStyle(fontWeight: FontWeight.w600, color: cc.text),
                        ),
                        subtitle: isHere
                            ? Text('Here now', style: TextStyle(color: AppTheme.green))
                            : fits
                            ? null
                            : Text('Taken then', style: TextStyle(color: cc.muted)),
                        onTap: () => Navigator.pop(ctx, p.id),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      );
      if (pick == null) return;
      if (pick.isEmpty) {
        place(s.id, null);
      } else {
        final p = positions.where((p) => p.id == pick).firstOrNull;
        if (p != null) place(s.id, p);
      }
    }

    Widget person(Shift s, {bool compact = false, List<PositionSegment>? segments}) {
      final card = _PersonChip(
        shift: s,
        user: users[s.userId],
        trainee: s.isTraining ? users[s.traineeId] : null,
        color: colorForUser(users[s.userId], settings),
        training: trainingFor(s.userId) ?? trainingFor(s.traineeId),
        segments: segments,
        compact: compact,
        onTap: widget.canEdit ? () => choose(s) : null,
      );
      if (!widget.canEdit) return card;
      return LongPressDraggable<String>(
        data: s.id,
        hapticFeedbackOnStart: true,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 260,
            child: _PersonChip(
              shift: s,
              user: users[s.userId],
              trainee: s.isTraining ? users[s.traineeId] : null,
              color: colorForUser(users[s.userId], settings),
              training: null,
              dragging: true,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: card,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...header,
        // Hour picker.
        SizedBox(
          height: 58,
          child: ListView.separated(
            controller: _hourScroll,
            scrollDirection: Axis.horizontal,
            itemCount: hours.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final h = hours[i];
              final n = day.shifts.where((s) => workingMinuteInHour(s, h) != null).length;
              final placed = day.shifts.where((s) {
                final m = workingMinuteInHour(s, h);
                return m != null && positionIds.contains(positionAt(s, m));
              }).length;
              final sel = h == at;
              return GestureDetector(
                onTap: () => setState(() => _hour = h),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 62,
                  decoration: BoxDecoration(
                    color: sel ? AppTheme.tint(AppTheme.accent) : c.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel ? AppTheme.edge(AppTheme.accent) : c.line.withValues(alpha: 0.7),
                      width: sel ? 1.4 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatMinutes(h, compact: true),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: sel ? AppTheme.onTint(AppTheme.accent) : c.title,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n == 0 ? '–' : '$placed/$n',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: n > 0 && placed == n ? AppTheme.green : c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MPill('${working.length} working at ${hourLabel(at)}', color: AppTheme.teal, large: true),
            if (working.isNotEmpty)
              MPill(
                unplaced.isEmpty ? 'Everyone placed' : '${unplaced.length} not placed',
                color: unplaced.isEmpty ? AppTheme.green : AppTheme.accent,
                large: true,
              ),
            if (!day.isPosted) MPill('Not posted', color: AppTheme.orange, large: true),
          ],
        ),

        // Not placed: drop here to take someone off their position.
        const MSection('Not placed'),
        DragTarget<String>(
          onWillAcceptWithDetails: (d) =>
              widget.canEdit && !unplaced.any((s) => s.id == d.data),
          onAcceptWithDetails: (d) => place(d.data, null),
          builder: (context, candidate, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: candidate.isNotEmpty ? AppTheme.tint(AppTheme.teal) : c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: candidate.isNotEmpty ? AppTheme.edge(AppTheme.teal) : c.line.withValues(alpha: 0.7),
                width: candidate.isNotEmpty ? 1.5 : 1,
              ),
            ),
            child: unplaced.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Text(
                      candidate.isNotEmpty
                          ? 'Drop to take them off their position'
                          : working.isEmpty
                          ? 'No one is working this hour.'
                          : 'Everyone has a position.',
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in unplaced)
                        Padding(
                          padding: EdgeInsets.only(bottom: s == unplaced.last ? 0 : 8),
                          child: person(s),
                        ),
                    ],
                  ),
          ),
        ),
        if (widget.canEdit && unplaced.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Tap someone to pick a position, or press and hold to drag them.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),

        const MSection('Positions'),
        for (var i = 0; i < positions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(
              builder: (context) {
                final p = positions[i];
                final here = day.shifts.where((s) {
                  final m = refMinute(s);
                  return m != null && positionAt(s, m) == p.id;
                }).toList()
                  ..sort((a, b) => a.start.compareTo(b.start));
                final coverage = positionCoverage(day, p.id, dayStart, dayEnd);
                bool canTake(Shift s) {
                  final m = refMinute(s);
                  return m != null && positionAt(s, m) != p.id && fitsPositionFrom(day, s, p, m);
                }

                return DragTarget<String>(
                  onWillAcceptWithDetails: (d) {
                    final s = day.shiftById(d.data);
                    return widget.canEdit && s != null && canTake(s);
                  },
                  onAcceptWithDetails: (d) => place(d.data, p),
                  builder: (context, candidate, rejected) {
                    final accent = candidate.isNotEmpty
                        ? AppTheme.green
                        : rejected.isNotEmpty
                        ? AppTheme.red
                        : null;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: accent == null ? c.card : Color.alphaBlend(AppTheme.tint(accent), c.card),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accent ?? c.line.withValues(alpha: 0.7),
                          width: accent != null ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              _RankBadge(rank: i + 1),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  p.name.isEmpty ? 'Untitled' : p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: c.title,
                                  ),
                                ),
                              ),
                              Text(
                                here.isEmpty ? 'Open' : 'Filled',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: here.isEmpty ? c.muted : AppTheme.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _Coverage(
                            coverage: coverage,
                            start: dayStart,
                            end: dayEnd,
                            marker: at,
                          ),
                          const SizedBox(height: 10),
                          if (here.isEmpty)
                            Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: c.line.withValues(alpha: 0.6)),
                                color: c.line.withValues(alpha: 0.12),
                              ),
                              child: Text(
                                rejected.isNotEmpty
                                    ? 'Taken then'
                                    : widget.canEdit
                                    ? 'Drop someone here'
                                    : 'No one',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: rejected.isNotEmpty ? AppTheme.red : c.muted,
                                ),
                              ),
                            ),
                          for (final s in here)
                            Padding(
                              padding: EdgeInsets.only(bottom: s == here.last ? 0 : 8),
                              child: person(s, compact: true, segments: segmentsOn(s, p.id)),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _autoFill(
    ScheduleDay day,
    List<ShiftPosition> positions,
    Map<String, TrainingStep> steps,
  ) async {
    if (day.shifts.any((s) => s.positions.isNotEmpty)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).cardColor,
          title: const Text('Re-deploy the whole day?'),
          content: const Text(
            'Auto-fill redoes every position for this day by priority, '
            'replacing the ones already set.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Auto-fill'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _save(deployPositions(day, positions, pinned: trainingPins(day, steps)));
    if (mounted) mSnack(context, 'Positions filled by priority for the whole day.');
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppTheme.tint(AppTheme.teal),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$rank',
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: AppTheme.onTint(AppTheme.teal),
      ),
    ),
  );
}

/// A working person on the board.
class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.shift,
    required this.user,
    required this.trainee,
    required this.color,
    required this.training,
    this.segments,
    this.compact = false,
    this.dragging = false,
    this.onTap,
  });

  final Shift shift;
  final UserModel? user;
  final UserModel? trainee;
  final Color color;
  final String? training;
  final List<PositionSegment>? segments;
  final bool compact;
  final bool dragging;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final seg = segments;
    final times = seg == null || seg.isEmpty
        ? formatRange(shift.start, shift.end)
        : seg.map((p) => formatRange(p.start, p.end)).join(', ');
    return Material(
      color: dragging ? c.card : c.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dragging ? color : c.line.withValues(alpha: 0.8)),
      ),
      elevation: dragging ? 8 : 0,
      shadowColor: Colors.black,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 10, compact ? 8 : 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        personName(user),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: c.title,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          times,
                          if (!compact && user?.title != null) user!.title!,
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                      if (trainee != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              Icon(Icons.link, size: 14, color: AppTheme.teal),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Training ${personName(trainee, short: true)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.teal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (training != null) TrainingBadge(label: training!),
                    ],
                  ),
                ),
              ),
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.drag_indicator, size: 18, color: c.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// People on a position through the day (green = covered).
class _Coverage extends StatelessWidget {
  const _Coverage({
    required this.coverage,
    required this.start,
    required this.end,
    required this.marker,
  });

  final List<int> coverage;
  final int start;
  final int end;
  final int marker;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final empty = c.line.withValues(alpha: 0.4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 7,
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Row(
                    children: [
                      for (final n in coverage)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(right: 1),
                            color: n == 0 ? empty : AppTheme.green,
                          ),
                        ),
                    ],
                  ),
                  if (end > start)
                    Positioned(
                      left: (box.maxWidth * (marker - start) / (end - start))
                          .clamp(0.0, box.maxWidth - 2)
                          .toDouble(),
                      width: 2,
                      top: 0,
                      bottom: 0,
                      child: Container(color: c.title),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(hourLabel(start), style: TextStyle(fontSize: 10, color: c.muted)),
            Text(hourLabel(end), style: TextStyle(fontSize: 10, color: c.muted)),
          ],
        ),
      ],
    );
  }
}
