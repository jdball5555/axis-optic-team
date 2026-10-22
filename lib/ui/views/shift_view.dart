import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/store_settings_model.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../services/schedule_repository.dart';
import 'schedule/position_ops.dart';
import 'schedule/shift_board_settings_dialog.dart';
import 'schedule/shift_layout_customizer.dart';
import 'schedule/schedule_common.dart';
import 'schedule/training_flow.dart';
import 'member_detail_view.dart' show showMemberProfileDialog;

/// Shift page: who's on which position, hour by hour. Pick a day with the
/// arrows and an hour from the tiles; drag people onto position tiles (they
/// stay there from that hour to the end of their shift). The right panel
/// lists who's working that hour; show / hide it with the button under the
/// gear and drag the divider to resize it. "Auto-fill" deploys the whole day
/// by priority. Positions and their priority are set with the gear.
class ShiftView extends ConsumerStatefulWidget {
  const ShiftView({super.key});

  @override
  ConsumerState<ShiftView> createState() => _ShiftViewState();
}

/// Drag payload: a shift being moved between positions.
class _ShiftDrag {
  final String shiftId;
  const _ShiftDrag(this.shiftId);
}

class _ShiftViewState extends ConsumerState<ShiftView> {
  DateTime _date = dateOnly(DateTime.now());

  /// Start (in minutes) of the selected hour; null = pick a sensible one.
  int? _hour;
  bool _showPanel = true;
  double _panelWidth = 320;

  String get _storeId => ref.read(currentStoreIdProvider)!;
  ScheduleRepository _repoFor(String scheduleId) => ref.read(
    boardRepositoryProvider((storeId: _storeId, boardId: scheduleId)),
  );

  /// The board's schedules' days for the day on screen (set in build), and
  /// which schedule each shift belongs to, so changes go back to the right
  /// schedule.
  Map<String, ScheduleDay> _sources = const {};
  Map<String, String> _origin = const {};

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Saves the board's day: each schedule whose shifts changed.
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
      _snack('Couldn\'t save. Please try again.');
    }
  }

  void _goToDate(DateTime d) => setState(() {
    _date = dateOnly(d);
    _hour = null;
  });

  /// Shift board settings: the boards and each one's ranked positions.
  /// Every change saves right away.
  Future<void> _openBoardSettings(
    ShiftConfig config,
    ScheduleConfig schedules,
    String? boardId,
  ) async {
    final repo = ref.read(scheduleRepositoryProvider(_storeId));
    await showShiftBoardSettings(
      context,
      config: config,
      schedules: schedules,
      boardId: boardId,
      onSave: (c) async {
        try {
          await repo.saveShiftConfig(c);
        } catch (_) {
          _snack('Couldn\'t save the shift board settings. Please try again.');
        }
      },
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
    final out = deployPositions(
      day,
      positions,
      pinned: trainingPins(day, steps),
    );
    await _save(out);
    _snack('Positions deployed by priority for the whole day.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storeId = ref.watch(currentStoreIdProvider);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: storeId == null
          ? _centerMessage(
              theme,
              Icons.store_outlined,
              'Choose a store to deploy its shift',
              'Pick one from the store menu in the sidebar.',
            )
          : _buildPage(theme, storeId),
    );
  }

  Widget _buildPage(ThemeData theme, String storeId) {
    final config =
        ref.watch(scheduleConfigProvider(storeId)).valueOrNull ??
        const ScheduleConfig();
    final shiftConfig =
        ref.watch(shiftConfigProvider(storeId)).valueOrNull ??
        const ShiftConfig();
    final boards = shiftConfig.boardsFor(config);
    final selected = ref.watch(selectedShiftBoardProvider(storeId));
    final scheduleOnPage = config
        .boardById(ref.watch(selectedBoardProvider(storeId)))
        .id;
    final board =
        boards.where((b) => b.id == selected).firstOrNull ??
        boards
            .where((b) => b.scheduleIds.contains(scheduleOnPage))
            .firstOrNull ??
        boards.firstOrNull ??
        const ShiftBoard(id: '', name: 'Board');
    final positions = board.positions;
    final weekStart = weekStartFor(_date, config.weekStart);
    // The board's schedules for this day, merged into one.
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
          weekAsync.valueOrNull?[dateKey(_date)] ??
          ScheduleDay.empty(dateKey(_date));
    }
    final merged = mergeBoardDay(dateKey(_date), sources);
    _sources = sources;
    _origin = merged.origin;
    final day = merged.day;
    final users = {
      for (final u
          in ref.watch(usersStreamProvider).valueOrNull ?? const <UserModel>[])
        if (u.id != null) u.id!: u,
    };
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final titleOrder = (settings?.titles ?? const [])
        .map((t) => t.name)
        .where((n) => n.isNotEmpty)
        .toList();
    final steps = <String, TrainingStep>{
      for (final e in sources.entries)
        ...trainingStepsFor(
          ref,
          storeId: storeId,
          boardId: e.key,
          date: _date,
          people: [
            for (final s in e.value.shifts) ?users[s.userId],
            for (final s in e.value.shifts) ?users[s.traineeId],
          ],
          config: config,
          titleOrder: titleOrder,
        ),
    };

    // Hours of the day, and the one being looked at.
    final (dayStart, dayEnd) = timelineRange(day.rows, day.shifts);
    final hours = [for (var h = dayStart; h < dayEnd; h += 60) h];
    var hour = _hour;
    if (hour == null || !hours.contains(hour)) {
      final now = DateTime.now();
      final nowHour = now.hour * 60;
      hour = dateOnly(now) == _date && hours.contains(nowHour)
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
    bool placedNow(Shift s) =>
        positionIds.contains(positionAt(s, refMinute(s) ?? at));
    final unplaced = working.where((s) => !placedNow(s)).toList();
    final placed = working.where(placedNow).toList();

    final ctx = _TileContext(
      day: day,
      users: users,
      settings: settings,
      steps: steps,
      shiftConfig: shiftConfig,
      dayStart: dayStart,
      dayEnd: dayEnd,
    );

    void place(String shiftId, ShiftPosition? position) {
      final shift = day.shiftById(shiftId);
      if (shift == null) return;
      final from = refMinute(shift) ?? at;
      if (position != null && !fitsPositionFrom(day, shift, position, from)) {
        _snack('${position.name} is taken from ${formatMinutes(from)} on.');
        return;
      }
      _save(assignPositionFrom(day, shiftId, position?.id, from));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _scrollIfNarrow(
            1080,
            _buildTopBar(
              theme,
              config,
              board,
              boards,
              hours,
              at,
              day,
              positions,
              steps,
              shiftConfig,
            ),
          ),
          const SizedBox(height: 6),
          _scrollIfNarrow(
            900,
            _buildToolbar(theme, day, at, working.length, unplaced.length),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: board.scheduleIds.isEmpty || positions.isEmpty
                              ? _centerMessage(
                                  theme,
                                  Icons.grid_view_outlined,
                                  board.scheduleIds.isEmpty
                                      ? '${board.name} has no schedules'
                                      : 'Set up ${board.name}\'s positions',
                                  board.scheduleIds.isEmpty
                                      ? 'Pick which schedules it shows in the '
                                            'shift board settings.'
                                      : 'Add the positions you deploy people to '
                                            '(Register, Drive-thru, ...) and rank '
                                            'them by priority.',
                                  action: FilledButton.icon(
                                    onPressed: () => _openBoardSettings(
                                      shiftConfig,
                                      config,
                                      board.id,
                                    ),
                                    icon: const Icon(Icons.settings_outlined),
                                    label: const Text('Shift board settings'),
                                  ),
                                )
                              : day.shifts.isEmpty
                              ? _centerMessage(
                                  theme,
                                  Icons.event_available_outlined,
                                  'No one is scheduled on '
                                      '${weekdayNames[_date.weekday - 1]}',
                                  'Build this day on the Schedule page first.',
                                )
                              : _PositionBoard(
                                  positions: positions,
                                  ctx: ctx,
                                  hour: at,
                                  onDrop: place,
                                  onUnassign: (id) => place(id, null),
                                ),
                        ),
                      ),
                      if (_showPanel) ...[
                        _Divider(
                          onDrag: (dx) => setState(
                            () => _panelWidth = (_panelWidth - dx)
                                .clamp(240.0, 600.0)
                                .toDouble(),
                          ),
                        ),
                        SizedBox(
                          width: _panelWidth,
                          child: _WorkingPanel(
                            hour: at,
                            unplaced: unplaced,
                            placed: placed,
                            admin: [
                              for (final s in day.shifts)
                                if (s.adminPieces.any(
                                  (p) => p.overlaps(at, at + 60),
                                ))
                                  s,
                            ],
                            ctx: ctx,
                            onUnassign: (id) => place(id, null),
                            onClose: () => setState(() => _showPanel = false),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _scrollIfNarrow(double minWidth, Widget child) => LayoutBuilder(
    builder: (context, c) => c.maxWidth >= minWidth
        ? child
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: minWidth, child: child),
          ),
  );

  Widget _buildTopBar(
    ThemeData theme,
    ScheduleConfig config,
    ShiftBoard board,
    List<ShiftBoard> boards,
    List<int> hours,
    int hour,
    ScheduleDay day,
    List<ShiftPosition> positions,
    Map<String, TrainingStep> steps,
    ShiftConfig shiftConfig,
  ) {
    final today = dateOnly(DateTime.now());
    return Row(
      children: [
        if (boards.length > 1) ...[
          BoardSwitcher(
            boards: [for (final b in boards) (id: b.id, name: b.name)],
            selectedId: board.id,
            tooltip: 'Switch board',
            onChanged: (id) => setState(() {
              ref.read(selectedShiftBoardProvider(_storeId).notifier).state =
                  id;
            }),
          ),
          const SizedBox(width: 8),
        ],
        IconButton(
          tooltip: 'Previous day',
          visualDensity: VisualDensity.compact,
          onPressed: () => _goToDate(addDays(_date, -1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '${weekdayShort[_date.weekday - 1]}, ${monthShort[_date.month - 1]} ${_date.day}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          visualDensity: VisualDensity.compact,
          onPressed: () => _goToDate(addDays(_date, 1)),
          icon: const Icon(Icons.chevron_right),
        ),
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: _date == today ? null : () => _goToDate(today),
          child: const Text('Today'),
        ),
        const SizedBox(width: 8),
        // One tile per hour: placed / working at that hour.
        Expanded(
          child: Row(
            children: [
              for (final h in hours)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: _HourTile(
                      label: formatMinutes(h, compact: true),
                      selected: h == hour,
                      working: day.shifts
                          .where((s) => workingMinuteInHour(s, h) != null)
                          .length,
                      placed: day.shifts.where((s) {
                        final m = workingMinuteInHour(s, h);
                        return m != null &&
                            positions.any((p) => p.id == positionAt(s, m));
                      }).length,
                      onTap: () => setState(() => _hour = h),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message:
              'Deploy the whole day by priority: at every moment the people '
              'working fill the highest-priority positions (trainers stay on '
              'their trainee\'s training position)',
          child: FilledButton.icon(
            onPressed: day.shifts.isEmpty || positions.isEmpty
                ? null
                : () => _autoFill(day, positions, steps),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Auto-fill'),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          color: theme.cardColor,
          icon: const Icon(Icons.more_horiz),
          onSelected: (v) {
            if (v == 'clear') {
              var d = day;
              for (final s in day.shifts) {
                d = assignPosition(d, s.id, null);
              }
              _save(d);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'clear',
              enabled: day.shifts.any((s) => s.positions.isNotEmpty),
              child: const Text('Take everyone off their positions'),
            ),
          ],
        ),
        IconButton(
          tooltip: 'Customize tile layout (Grid)',
          visualDensity: VisualDensity.compact,
          onPressed: () => showShiftLayoutCustomizer(
            context,
            config: shiftConfig,
            board: board,
            schedules: config,
            onSave: (c) async {
              try {
                await ref
                    .read(scheduleRepositoryProvider(_storeId))
                    .saveShiftConfig(c);
              } catch (_) {
                _snack('Couldn\'t save tile layout. Please try again.');
              }
            },
          ),
          icon: const Icon(Icons.dashboard_customize_outlined),
        ),
        IconButton(
          tooltip: 'Shift board settings',
          visualDensity: VisualDensity.compact,
          onPressed: () => _openBoardSettings(shiftConfig, config, board.id),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }

  Widget _buildToolbar(
    ThemeData theme,
    ScheduleDay day,
    int hour,
    int working,
    int unplaced,
  ) {
    return Row(
      children: [
        Text(
          '${weekdayNames[_date.weekday - 1]}, ${monthNames[_date.month - 1]} '
          '${_date.day} · ${hourLabel(hour)}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: theme.textTheme.titleLarge?.color,
          ),
        ),
        const SizedBox(width: 14),
        _Pill(text: '$working working', color: AppTheme.accent2),
        const SizedBox(width: 6),
        if (working > 0)
          _Pill(
            text: unplaced == 0 ? 'Everyone placed' : '$unplaced not placed',
            color: unplaced == 0 ? AppTheme.accent2 : AppTheme.accent,
          ),
        const SizedBox(width: 6),
        if (day.shifts.isNotEmpty && !day.isPosted)
          _Pill(text: 'Schedule not posted', color: AppTheme.red),
        const Spacer(),
        // Show / hide the "who's working" panel (sits under the gear).
        Badge(
          isLabelVisible: unplaced > 0,
          label: Text('$unplaced'),
          backgroundColor: AppTheme.accent,
          child: IconButton(
            tooltip: _showPanel ? 'Hide who\'s working' : 'Show who\'s working',
            visualDensity: VisualDensity.compact,
            isSelected: _showPanel,
            style: IconButton.styleFrom(
              backgroundColor: _showPanel
                  ? AppTheme.accent2.withValues(alpha: 0.15)
                  : null,
            ),
            color: _showPanel ? AppTheme.accent2 : null,
            onPressed: () => setState(() => _showPanel = !_showPanel),
            icon: const Icon(Icons.people_alt_outlined),
          ),
        ),
      ],
    );
  }

  Widget _centerMessage(
    ThemeData theme,
    IconData icon,
    String title,
    String subtitle, {
    Widget? action,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: theme.textTheme.bodySmall?.color),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textTheme.bodySmall?.color),
            ),
            ?action == null ? null : const SizedBox(height: 16),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// One hour in the top bar: placed / working then.
class _HourTile extends StatelessWidget {
  final String label;
  final bool selected;
  final int working;
  final int placed;
  final VoidCallback onTap;

  const _HourTile({
    required this.label,
    required this.selected,
    required this.working,
    required this.placed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final allPlaced = working > 0 && placed == working;
    return Tooltip(
      message: working == 0 ? 'No one working' : '$placed of $working placed',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 38,
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.tint(AppTheme.accent)
                  : theme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? AppTheme.edge(AppTheme.accent)
                    : theme.dividerColor,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: selected
                        ? AppTheme.onTint(AppTheme.accent)
                        : theme.textTheme.bodyLarge?.color,
                  ),
                ),
                if (working > 0)
                  Text(
                    '$placed/$working',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: allPlaced ? AppTheme.accent2 : muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The draggable line between the board and the right-hand panel.
class _Divider extends StatelessWidget {
  final ValueChanged<double> onDrag;
  const _Divider({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: SizedBox(
          width: 12,
          child: Center(
            child: Container(
              width: 6,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 3,
                      height: 3,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.textTheme.bodySmall?.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Right panel: who's working at the selected hour
// =============================================================================

class _WorkingPanel extends StatelessWidget {
  final int hour;
  final List<Shift> unplaced;
  final List<Shift> placed;

  /// On admin time this hour: listed last, not on the floor.
  final List<Shift> admin;
  final _TileContext ctx;
  final ValueChanged<String> onUnassign;
  final VoidCallback onClose;

  const _WorkingPanel({
    required this.hour,
    required this.unplaced,
    required this.placed,
    this.admin = const [],
    required this.ctx,
    required this.onUnassign,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: muted,
        ),
      ),
    );

    // Dropping someone here takes them off their position from this hour.
    return DragTarget<_ShiftDrag>(
      onWillAcceptWithDetails: (d) =>
          !unplaced.any((s) => s.id == d.data.shiftId),
      onAcceptWithDetails: (d) => onUnassign(d.data.shiftId),
      builder: (context, candidate, _) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: candidate.isNotEmpty ? AppTheme.accent2 : theme.dividerColor,
            width: candidate.isNotEmpty ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Working at ${hourLabel(hour)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.titleLarge?.color,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hide',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                children: [
                  heading('NOT PLACED (${unplaced.length})'),
                  if (unplaced.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        placed.isEmpty
                            ? 'No one is working this hour.'
                            : 'Everyone has a position.',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  for (final s in unplaced)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PersonCard(shift: s, ctx: ctx),
                    ),
                  if (placed.isNotEmpty) ...[
                    heading('PLACED (${placed.length})'),
                    for (final s in placed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PersonCard(
                          shift: s,
                          ctx: ctx,
                          showPosition: true,
                        ),
                      ),
                  ],
                  if (admin.isNotEmpty) ...[
                    heading('SCHEDULED ADMIN TIME (${admin.length})'),
                    for (final s in admin)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.assignment_outlined,
                              size: 18,
                              color: muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap: ctx.users[s.userId]?.id != null
                                        ? () => context.go(
                                            '/member/${ctx.users[s.userId]!.id}?from=/shift',
                                          )
                                        : null,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Text(
                                      personName(
                                        ctx.users[s.userId],
                                        short: true,
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: theme.textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Scheduled admin time · '
                                    '${s.adminPieces.map((p) => formatRange(p.start, p.end)).join(', ')} · '
                                    'not on the floor',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Main area: position tiles at the selected hour
// =============================================================================

class _PositionBoard extends StatelessWidget {
  final List<ShiftPosition> positions;
  final _TileContext ctx;
  final int hour;
  final void Function(String shiftId, ShiftPosition position) onDrop;
  final ValueChanged<String> onUnassign;

  const _PositionBoard({
    required this.positions,
    required this.ctx,
    required this.hour,
    required this.onDrop,
    required this.onUnassign,
  });

  @override
  Widget build(BuildContext context) {
    final hasCustomCoords = positions.any((p) => p.x != null && p.y != null);

    return LayoutBuilder(
      builder: (context, c) {
        if (hasCustomCoords) {
          double maxX = c.maxWidth;
          double maxY = c.maxHeight;
          for (final p in positions) {
            final x = (p.x ?? 0.0) + 220.0;
            final y = (p.y ?? 0.0) + 70.0;
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SizedBox(
                width: maxX,
                height: maxY,
                child: Stack(
                  children: [
                    for (var i = 0; i < positions.length; i++)
                      Positioned(
                        key: ValueKey(positions[i].id),
                        left: positions[i].x ?? (50.0 + (i % 4) * 250.0),
                        top: positions[i].y ?? (50.0 + (i ~/ 4) * 100.0),
                        width: 200,
                        height: 50.0,
                        child: _PositionTile(
                          rank: i + 1,
                          position: positions[i],
                          ctx: ctx,
                          hour: hour,
                          onDrop: (id) => onDrop(id, positions[i]),
                          onUnassign: onUnassign,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        // Responsive wrap of compact tiles if no coordinates were saved yet: side-by-side
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < positions.length; i++)
                  SizedBox(
                    width: 200,
                    height: 50.0,
                    child: _PositionTile(
                      rank: i + 1,
                      position: positions[i],
                      ctx: ctx,
                      hour: hour,
                      onDrop: (id) => onDrop(id, positions[i]),
                      onUnassign: onUnassign,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PositionTile extends StatelessWidget {
  final int rank;
  final ShiftPosition position;
  final _TileContext ctx;
  final int hour;
  final ValueChanged<String> onDrop;
  final ValueChanged<String> onUnassign;

  const _PositionTile({
    required this.rank,
    required this.position,
    required this.ctx,
    required this.hour,
    required this.onDrop,
    required this.onUnassign,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final day = ctx.day;
    int? refMinute(Shift s) => workingMinuteInHour(s, hour);
    final here = day.shifts.where((s) {
      final m = refMinute(s);
      return m != null && positionAt(s, m) == position.id;
    }).toList()..sort((a, b) => a.start.compareTo(b.start));

    bool canTake(Shift s) {
      final m = refMinute(s);
      return m != null &&
          positionAt(s, m) != position.id &&
          fitsPositionFrom(day, s, position, m);
    }

    if (here.isEmpty) {
      return DragTarget<_ShiftDrag>(
        onWillAcceptWithDetails: (d) {
          final s = day.shiftById(d.data.shiftId);
          return s != null && canTake(s);
        },
        onAcceptWithDetails: (d) => onDrop(d.data.shiftId),
        builder: (context, candidate, rejectedData) {
          final isHovered = candidate.isNotEmpty;
          final rejected = rejectedData.whereType<_ShiftDrag>().where((d) {
            final s = day.shiftById(d.shiftId);
            if (s == null) return false;
            final m = refMinute(s);
            return m == null || positionAt(s, m) != position.id;
          }).toList();
          final isRejected = rejected.isNotEmpty;

          return Tooltip(
            message: isRejected
                ? 'Full during part of that time'
                : 'Drop someone here (from ${hourLabel(hour)})',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 50,
              decoration: BoxDecoration(
                color: isHovered
                    ? AppTheme.green.withValues(alpha: 0.1)
                    : isRejected
                    ? AppTheme.red.withValues(alpha: 0.08)
                    : theme.cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isHovered
                      ? AppTheme.green
                      : isRejected
                      ? AppTheme.red
                      : theme.dividerColor.withValues(alpha: 0.7),
                  width: (isHovered || isRejected) ? 1.8 : 1,
                ),
                boxShadow: isHovered
                    ? [
                        BoxShadow(
                          color: AppTheme.green.withValues(alpha: 0.15),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add,
                    size: 14,
                    color: isHovered
                        ? AppTheme.green
                        : isRejected
                        ? AppTheme.red
                        : muted?.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      position.name.isEmpty ? 'Untitled' : position.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isHovered
                            ? AppTheme.green
                            : isRejected
                            ? AppTheme.red
                            : theme.textTheme.bodyMedium?.color?.withValues(
                                alpha: 0.8,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    // When someone is dragged on there, that person fills up the entire tile!
    // When someone is dragged on there, that person fills up the entire tile!
    // The tile has a clean card background with a title color accent stripe on the left.
    // There is a little tag next to the name that says what that tile or where that position is.
    Widget buildCard(Shift s, {bool dragging = false}) {
      final user = ctx.users[s.userId];
      final color = colorForUser(user, ctx.settings);
      final name = personName(user, short: true);
      final posTag = position.name.isEmpty ? 'Pos' : position.name;

      return Container(
        height: 50,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.8),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dragging ? 0.25 : 0.04),
              blurRadius: dragging ? 10 : 3,
              offset: Offset(0, dragging ? 4 : 1),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left color bar showing title color neatly
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(9),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Person Name (interactive: click pops up profile)
            Expanded(
              child: _HoverableTileName(
                name: name,
                onTap: () {
                  if (user?.id != null) {
                    showMemberProfileDialog(context, user!.id!);
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            // Little tag next to the name saying what that tile or where that position is
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                posTag,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      );
    }

    Widget buildFilledTile(Shift s) {
      final user = ctx.users[s.userId];
      final posTag = position.name.isEmpty ? 'Pos' : position.name;
      final tooltipMsg =
          '${personName(user)} · ${formatRange(s.start, s.end)} · $posTag';

      final cardContent = buildCard(s, dragging: false);
      final tooltipWrapped = Tooltip(
        message: tooltipMsg,
        waitDuration: const Duration(milliseconds: 400),
        child: cardContent,
      );

      return MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<_ShiftDrag>(
          data: _ShiftDrag(s.id),
          onDragEnd: (details) {
            // Dragging the person out of the tile removes them
            if (!details.wasAccepted) {
              onUnassign(s.id);
            }
          },
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 200,
              height: 50,
              child: buildCard(s, dragging: true),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: tooltipWrapped),
          child: tooltipWrapped,
        ),
      );
    }

    if (here.isNotEmpty) {
      return buildFilledTile(here.first);
    }

    return const SizedBox.shrink();
  }
}

// =============================================================================
// Shared pieces
// =============================================================================

/// What the tiles need to draw people.
class _TileContext {
  final ScheduleDay day;
  final Map<String, UserModel> users;
  final StoreSettingsModel? settings;
  final Map<String, TrainingStep> steps;
  final ShiftConfig shiftConfig;
  final int dayStart;
  final int dayEnd;

  const _TileContext({
    required this.day,
    required this.users,
    required this.settings,
    required this.steps,
    required this.shiftConfig,
    required this.dayStart,
    required this.dayEnd,
  });

  String? trainingFor(String? uid) {
    final step = uid == null ? null : steps[uid];
    return step == null ? null : trainingLabel(step, shiftConfig);
  }
}

/// A working person (their shift). Draggable onto a position.
class _PersonCard extends StatelessWidget {
  final Shift shift;
  final _TileContext ctx;
  final bool showPosition;
  final bool compact;
  final VoidCallback? onRemove;

  /// When shown on a position tile: just the time spent on that position.
  final List<PositionSegment>? segments;

  const _PersonCard({
    required this.shift,
    required this.ctx,
    this.showPosition = false,
    this.compact = false,
    this.onRemove,
    this.segments,
  });

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<_ShiftDrag>(
        data: _ShiftDrag(shift.id),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: 250, child: _card(context, dragging: true)),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: card,
      ),
    );
  }

  Widget _card(BuildContext context, {bool dragging = false}) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final user = ctx.users[shift.userId];
    final trainee = shift.isTraining ? ctx.users[shift.traineeId] : null;
    final color = colorForUser(user, ctx.settings);
    final where = showPosition ? positionsSummary(shift, ctx.shiftConfig) : '';
    final seg = segments;
    final times = seg == null || seg.isEmpty
        ? formatRange(shift.start, shift.end)
        : seg.map((p) => formatRange(p.start, p.end)).join(', ');
    final minutes = seg == null || seg.isEmpty
        ? shift.minutes
        : seg.fold<int>(0, (a, p) => a + p.minutes);
    final training = ctx.trainingFor(shift.userId);
    final traineeTraining = ctx.trainingFor(shift.traineeId);

    return Container(
      decoration: BoxDecoration(
        color: dragging ? theme.cardColor : theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dragging ? color : theme.dividerColor.withValues(alpha: 0.8),
        ),
        boxShadow: dragging
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(10),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  compact ? 6 : 9,
                  4,
                  compact ? 6 : 9,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: user?.id != null
                          ? () => context.go('/member/${user!.id}?from=/shift')
                          : null,
                      borderRadius: BorderRadius.circular(4),
                      child: Text(
                        personName(user),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        times,
                        '${formatHours(minutes / 60)}h',
                        if (!compact && user?.title != null) user!.title!,
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    if (where.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          where,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.green,
                          ),
                        ),
                      ),
                    if (trainee != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            // The trainer: linked, no hat.
                            Icon(Icons.link, size: 14, color: AppTheme.accent2),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Training ${personName(trainee, short: true)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accent2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (training != null) TrainingBadge(label: training),
                    if (traineeTraining != null)
                      TrainingBadge(
                        label:
                            '${personName(trainee, short: true)}: $traineeTraining',
                      ),
                  ],
                ),
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Take off this position',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onRemove,
                icon: Icon(Icons.close, color: muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// People on a position through the day: empty, part-filled or full.
class _CoverageBar extends StatelessWidget {
  final List<int> coverage; // per half hour
  final int start;
  final int end;

  /// The selected hour, marked on the bar.
  final int? marker;

  const _CoverageBar({
    required this.coverage,
    required this.start,
    required this.end,
    this.marker,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final empty = theme.dividerColor.withValues(alpha: 0.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: 'Green: someone on it · gray: no one',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: LayoutBuilder(
                builder: (context, c) => Stack(
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
                    if (marker != null && end > start)
                      Positioned(
                        left: (c.maxWidth * (marker! - start) / (end - start))
                            .clamp(0.0, c.maxWidth - 2),
                        width: 2,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              hourLabel(start),
              style: TextStyle(fontSize: 10, color: muted),
            ),
            Text(hourLabel(end), style: TextStyle(fontSize: 10, color: muted)),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.tint(color),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.onTint(color),
      ),
    ),
  );
}

class _HoverableTileName extends StatefulWidget {
  final String name;
  final VoidCallback onTap;

  const _HoverableTileName({required this.name, required this.onTap});

  @override
  State<_HoverableTileName> createState() => _HoverableTileNameState();
}

class _HoverableTileNameState extends State<_HoverableTileName> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.centerLeft,
          child: Text(
            widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _hovered
                  ? theme.colorScheme.primary
                  : theme.textTheme.bodyLarge?.color,
              decoration: _hovered
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}
