import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';
import '../../../models/store_settings_model.dart';
import '../../../models/user_model.dart';
import 'schedule_common.dart';
import 'coverage_strip.dart';
import 'schedule_ops.dart';

/// Team-member view of a day: one thin row per person, name (and times) on
/// the left. No template bars; the coverage counts stay at the top.
///  * Drag across someone's row to give them a shift.
///  * Drag a shift's middle to slide it, its ends to change its times.
///  * Hours someone can't work are shaded.
/// Shifts are still stored in the template rows; every change re-places the
/// block with the same rules as the compact view's ✓.
class MemberScheduleGrid extends StatefulWidget {
  final ScheduleDay day;
  final DateTime date;
  final List<UserModel> people;
  final Map<String, UserModel> users;
  final StoreSettingsModel? settings;
  final List<TimeOffEntry> timeOff; // approved
  final List<TimeOffEntry> requestedOff; // pending
  final String? selectedShiftId;
  final Map<String, String> warnings; // pieceId -> message
  final ValueChanged<String?> onSelectShift;

  /// Why [userId] can't have block [w] (replacing [old]), or null.
  final String? Function(String userId, TimeWindow? old, TimeWindow w)
  blockProblem;
  final void Function(String userId, TimeWindow? old, TimeWindow w) onSetBlock;

  /// New hires' training-flow step for this day, by user id.
  final Map<String, String> trainingLabels;

  /// Which of their weekly shifts the selected day is (0 = off that day) and
  /// their total, e.g. (2, 5) → "2/5", (0, 5) → "5".
  final Map<String, (int, int)> weekShifts;

  /// Hours they work on the selected day and in the whole week, e.g.
  /// (6.5, 28) → "6.5/28h", (0, 28) → "28h".
  final Map<String, (double, double)> weekHours;

  /// Receives the timeline scale, so a person dragged from "Who can work"
  /// is drawn as a true-to-scale 6-hour shift.
  final ValueNotifier<double>? pixelsPerMinute;

  const MemberScheduleGrid({
    super.key,
    required this.day,
    required this.date,
    required this.people,
    required this.users,
    required this.settings,
    required this.timeOff,
    required this.requestedOff,
    required this.selectedShiftId,
    required this.warnings,
    required this.onSelectShift,
    required this.blockProblem,
    required this.onSetBlock,
    this.trainingLabels = const {},
    this.weekShifts = const {},
    this.weekHours = const {},
    this.pixelsPerMinute,
  });

  static const double nameWidth = 280;

  /// Name column when collapsed to names only: fits the longest name,
  /// between these.
  static const double compactMinWidth = 110;
  static const double compactMaxWidth = 220;

  /// Fixed slots so every row's shift and hours pills line up: shift pills
  /// right-aligned, hours pills starting right after them.
  static const double _shiftSlot = 34;
  static const double _hoursSlot = 88;
  static const double rowHeight = 32;
  static const double rowGap = 2;
  static const double headerHeight = 26;

  @override
  State<MemberScheduleGrid> createState() => _MemberScheduleGridState();
}

enum _Drag { draw, move, resizeStart, resizeEnd }

/// The two halves of a person's row: the pinned name column and the
/// timeline (which scrolls sideways when the day doesn't fit).
enum _RowPart { name, timeline }

class _MemberScheduleGridState extends State<MemberScheduleGrid> {
  /// Name column collapsed to just names (no shift / hours pills).
  bool _compact = false;
  double get _nameW => _compact ? _compactWidth() : MemberScheduleGrid.nameWidth;

  /// Collapsed: fits the longest name (plus the color dot, padding and room
  /// for the training hat), between the min and max (very long names are
  /// cut off with "…" so nothing jumps around).
  double _compactWidth() {
    final scaler = MediaQuery.textScalerOf(context);
    // Measured once per set of names (not on every rebuild while dragging).
    final key = Object.hash(scaler, Object.hashAll(widget.people.map((u) => personName(u, short: true))));
    if (key == _measuredKey) return _measured;
    var longest = 0.0;
    for (final u in widget.people) {
      final tp = TextPainter(
        text: TextSpan(
          text: personName(u, short: true),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      longest = math.max(longest, tp.width);
      tp.dispose();
    }
    // 16 padding + 8 dot + 8 gap + 19 hat + a little slack.
    _measuredKey = key;
    return _measured = (longest + 16 + 8 + 8 + 19 + 6).clamp(
      MemberScheduleGrid.compactMinWidth,
      MemberScheduleGrid.compactMaxWidth,
    );
  }

  int? _measuredKey;
  double _measured = MemberScheduleGrid.compactMinWidth;

  static const double _edge = 6;

  /// Pixels per minute below which the timeline scrolls sideways instead of
  /// shrinking, so the coverage numbers (3/3, 5/5, ...) always fit.
  static const double _minPixelsPerMinute = 1.1;

  final _vertical = ScrollController();
  final _timelineKey = GlobalKey();
  final _hHeader = ScrollController();
  final _hBody = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _hBody.addListener(() => _sync(_hBody, _hHeader));
    _hHeader.addListener(() => _sync(_hHeader, _hBody));
  }

  /// Keeps the time header and the rows scrolled to the same spot.
  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients || !from.hasClients) return;
    if ((to.offset - from.offset).abs() < 0.5) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0.0, to.position.maxScrollExtent));
    _syncing = false;
  }

  String? _hoverUid;

  // The drag in progress (one person's row at a time).
  String? _uid;
  TimeWindow? _old;
  _Drag? _mode;
  int? _anchor;
  int? _current;
  double _dx = 0;

  @override
  void dispose() {
    _vertical.dispose();
    _hHeader.dispose();
    _hBody.dispose();
    super.dispose();
  }

  int _snap(double minutes) =>
      (minutes / kScheduleStep).round() * kScheduleStep;

  int _minuteAt(TimelineMetrics m, double dx) =>
      (m.start + _snap(dx / m.ppm)).clamp(m.start, m.end).toInt();

  TimeWindow? _preview(TimelineMetrics m) {
    final old = _old;
    switch (_mode) {
      case null:
        return null;
      case _Drag.draw:
        return TimeWindow(
          math.min(_anchor!, _current!),
          math.max(_anchor!, _current!),
        );
      case _Drag.move:
        final len = old!.minutes;
        final s = (old.start + _snap(_dx / m.ppm))
            .clamp(m.start, m.end - len)
            .toInt();
        return TimeWindow(s, s + len);
      case _Drag.resizeStart:
        return TimeWindow(
          (old!.start + _snap(_dx / m.ppm))
              .clamp(m.start, old.end - kScheduleStep)
              .toInt(),
          old.end,
        );
      case _Drag.resizeEnd:
        return TimeWindow(
          old!.start,
          (old.end + _snap(_dx / m.ppm))
              .clamp(old.start + kScheduleStep, m.end)
              .toInt(),
        );
    }
  }

  void _endDrag(TimelineMetrics m) {
    final w = _preview(m);
    final uid = _uid;
    final old = _old;
    final mode = _mode;
    setState(() {
      _uid = null;
      _old = null;
      _mode = null;
      _anchor = null;
      _current = null;
      _dx = 0;
    });
    if (w == null || uid == null || mode == null) return;
    if (mode == _Drag.draw) {
      if (w.minutes >= kScheduleStep) widget.onSetBlock(uid, null, w);
      return;
    }
    if (old != null && w != old) widget.onSetBlock(uid, old, w);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = widget.day;
    final (start, end) = timelineRange(day.rows, day.shifts);

    return LayoutBuilder(
      builder: (context, c) {
        final timelineWidth = math.max(
          c.maxWidth - _nameW - 8,
          (end - start) * _minPixelsPerMinute,
        );
        final m = TimelineMetrics(start: start, end: end, width: timelineWidth);
        widget.pixelsPerMinute?.value = m.ppm;
        final preview = _preview(m);
        final problem = preview == null
            ? null
            : widget.blockProblem(
                _uid!,
                _mode == _Drag.draw ? null : _old,
                preview,
              );
        Widget rows(_RowPart part) => Column(
          children: [
            for (var i = 0; i < widget.people.length; i++)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: MemberScheduleGrid.rowGap,
                ),
                child: SizedBox(
                  height: MemberScheduleGrid.rowHeight,
                  child: _personRow(
                    context,
                    theme,
                    m,
                    i,
                    widget.people[i],
                    preview,
                    problem,
                    part,
                  ),
                ),
              ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: _nameW + 8,
                  height:
                      MemberScheduleGrid.headerHeight + CoverageStrip.height,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(text: 'TEAM'),
                                  TextSpan(
                                    text: '  ${day.shifts.length} working',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _compact
                                ? 'Show shifts and hours'
                                : 'Names only',
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () =>
                                setState(() => _compact = !_compact),
                            icon: Icon(
                              _compact
                                  ? Icons.keyboard_double_arrow_right
                                  : Icons.keyboard_double_arrow_left,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _hHeader,
                    child: SingleChildScrollView(
                      controller: _hHeader,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: m.width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TimelineHeader(
                              metrics: m,
                              height: MemberScheduleGrid.headerHeight,
                            ),
                            Tooltip(
                              message:
                                  'Scheduled / needed people for each half hour',
                              child: CoverageStrip(day: day, metrics: m),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Scrollbar(
                controller: _vertical,
                child: SingleChildScrollView(
                  controller: _vertical,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: _nameW, child: rows(_RowPart.name)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Scrollbar(
                          controller: _hBody,
                          child: SingleChildScrollView(
                            controller: _hBody,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(bottom: 10),
                            // Drop someone from "Who can work" anywhere here:
                            // a 6-hour shift starting where it was let go.
                            child: DragTarget<PersonDrag>(
                              onAcceptWithDetails: (d) {
                                final box =
                                    _timelineKey.currentContext
                                            ?.findRenderObject()
                                        as RenderBox?;
                                final dx = box?.globalToLocal(d.offset).dx ?? 0;
                                widget.onSetBlock(
                                  d.data.userId,
                                  null,
                                  placeShift(
                                    TimeWindow(m.start, m.end),
                                    _minuteAt(m, dx),
                                  ),
                                );
                              },
                              builder: (context, candidate, _) => Container(
                                key: _timelineKey,
                                width: m.width,
                                decoration: BoxDecoration(
                                  color: candidate.isNotEmpty
                                      ? AppTheme.accent2.withValues(alpha: 0.06)
                                      : null,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: rows(_RowPart.timeline),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _personRow(
    BuildContext context,
    ThemeData theme,
    TimelineMetrics m,
    int index,
    UserModel user,
    TimeWindow? preview,
    String? problem,
    _RowPart part,
  ) {
    final uid = user.id!;
    final day = widget.day;
    final key = dateKey(widget.date);
    final color = colorForUser(user, widget.settings);
    final shift = day.shiftForUser(uid);
    // Floor time as blocks (admin time is drawn on its own, faded).
    final blocks = shift == null
        ? const <TimeWindow>[]
        : mergeWindows(shift.workPieces.map((p) => TimeWindow(p.start, p.end)));
    final admin = shift?.adminPieces ?? const <ShiftPiece>[];
    final trainingIn = day.shifts.where((s) => s.traineeId == uid).toList();
    final dayOff = widget.timeOff.any(
      (t) => t.userId == uid && t.isFullDay && t.covers(key),
    );
    final requestedOff =
        !dayOff &&
        widget.requestedOff.any(
          (t) => t.userId == uid && t.isFullDay && t.covers(key),
        );
    final work = workWindowsFor(user, widget.date, widget.timeOff);
    final unavailable = work == null
        ? const <TimeWindow>[]
        : subtractWindows([TimeWindow(m.start, m.end)], work);
    final shade = theme.brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.35)
        : Colors.black.withValues(alpha: 0.08);

    final training = widget.trainingLabels[uid];
    final usualShifts = avgShiftsEstimate(user);
    final hovered = _hoverUid == uid;
    final stripe = hovered
        ? AppTheme.accent2.withValues(alpha: 0.08)
        : (index.isOdd
              ? theme.dividerColor.withValues(alpha: 0.18)
              : Colors.transparent);

    Widget pill(String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.tint(c),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.onTint(c),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hoverUid = uid),
      onExit: (_) => setState(() {
        if (_hoverUid == uid) _hoverUid = null;
      }),
      child: Container(
        decoration: BoxDecoration(
          color: stripe,
          borderRadius: BorderRadius.circular(6),
        ),
        child: part == _RowPart.name
            // Name, then hours (or why they're off).
            ? Container(
                width: _nameW,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Name, with the training hat and off tag right after it.
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Tooltip(
                              message: [
                                personName(user),
                                ?user.title,
                                ?training,
                              ].join('\n'),
                              waitDuration: const Duration(milliseconds: 500),
                              child: Text(
                                personName(user, short: true),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                              ),
                            ),
                          ),
                          if (training != null) ...[
                            const SizedBox(width: 4),
                            Tooltip(
                              message: training,
                              child: Icon(
                                Icons.school,
                                size: 15,
                                color: AppTheme.accent2,
                              ),
                            ),
                          ],
                          if (dayOff) ...[
                            const SizedBox(width: 4),
                            pill('Off', AppTheme.red),
                          ] else if (requestedOff) ...[
                            const SizedBox(width: 4),
                            pill('Req. off', AppTheme.accent2),
                          ],
                        ],
                      ),
                    ),
                    if (!_compact) ...[
                      // Shifts this week ("2/5", or "5" when off today).
                      SizedBox(
                        width: MemberScheduleGrid._shiftSlot,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: switch (widget.weekShifts[uid]) {
                            (final nth, final total) when total > 0 => Tooltip(
                              message:
                                  '${nth > 0 ? 'Shift $nth of $total' : '$total ${total == 1 ? 'shift' : 'shifts'}'} this week'
                                  '${usualShifts == null ? '' : ' (usually ~${formatHours(usualShifts)})'}',
                              child: pill(
                                nth > 0 ? '$nth/$total' : '$total',
                                AppTheme.accent2,
                              ),
                            ),
                            _ => const SizedBox.shrink(),
                          },
                        ),
                      ),
                      // Hours today / this week ("6.5/28h", or "28h").
                      const SizedBox(width: 4),
                      SizedBox(
                        width: MemberScheduleGrid._hoursSlot,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: switch (widget.weekHours[uid]) {
                            (final today, final week) when week > 0 => Tooltip(
                              message:
                                  '${today > 0 ? '${formatHours(today)} hours today, ' : ''}'
                                  '${formatHours(week)} hours this week',
                              child: pill(
                                today > 0
                                    ? '${formatHours(today)}/${formatHours(week)}h'
                                    : '${formatHours(week)}h',
                                AppTheme.blue,
                              ),
                            ),
                            _ => const SizedBox.shrink(),
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              )
            // Timeline.
            : SizedBox(
                width: m.width,
                height: MemberScheduleGrid.rowHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (_) => widget.onSelectShift(null),
                        onPanStart: (d) => setState(() {
                          _uid = uid;
                          _old = null;
                          _mode = _Drag.draw;
                          _anchor = _minuteAt(m, d.localPosition.dx);
                          _current = _anchor;
                        }),
                        onPanUpdate: (d) => setState(
                          () => _current = _minuteAt(m, d.localPosition.dx),
                        ),
                        onPanEnd: (_) => _endDrag(m),
                        onPanCancel: () => _endDrag(m),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.precise,
                          child: CustomPaint(
                            painter: TimelineGridPainter(
                              m,
                              theme.dividerColor.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Hours they can't work.
                    for (final w in unavailable)
                      Positioned(
                        left: m.x(w.start),
                        width: m.w(w.start, w.end),
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: shade,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    // Training (as the trainee): shown, edited from the trainer's row.
                    for (final s in trainingIn)
                      for (final b in shiftBlocks(s))
                        Positioned(
                          left: m.x(b.start),
                          width: math.max(4.0, m.w(b.start, b.end)),
                          top: 4,
                          bottom: 4,
                          child: Tooltip(
                            message:
                                'Training with ${personName(widget.users[s.userId])} '
                                '${formatRange(b.start, b.end)}\n'
                                'Change it from ${personName(widget.users[s.userId], short: true)}\'s row',
                            child: GestureDetector(
                              onTap: () => widget.onSelectShift(s.id),
                              child: _block(
                                color: color.withValues(alpha: 0.5),
                                window: b,
                                m: m,
                                selected: widget.selectedShiftId == s.id,
                                training: true,
                                linked: true,
                              ),
                            ),
                          ),
                        ),
                    // Admin time: faded, with an icon; off the floor.
                    for (final a in admin)
                      Positioned(
                        left: m.x(a.start),
                        width: math.max(4.0, m.w(a.start, a.end)),
                        top: 4,
                        bottom: 4,
                        child: Tooltip(
                          message:
                              'Admin time ${formatRange(a.start, a.end)}\n'
                              'Off the floor: not counted toward the people needed',
                          child: GestureDetector(
                            onTap: () => widget.onSelectShift(shift?.id),
                            child: _block(
                              color: color.withValues(alpha: 0.45),
                              window: TimeWindow(a.start, a.end),
                              m: m,
                              selected: widget.selectedShiftId == shift?.id,
                              admin: true,
                            ),
                          ),
                        ),
                      ),
                    // Their shift, as blocks.
                    for (var i = 0; i < blocks.length; i++)
                      Positioned(
                        key: ValueKey('block-$i'),
                        left: m.x(blocks[i].start),
                        width: math.max(
                          4.0,
                          m.w(blocks[i].start, blocks[i].end),
                        ),
                        top: 4,
                        bottom: 4,
                        child: _blockHandle(m, uid, shift!, blocks[i], color),
                      ),
                    // The block being drawn / moved / resized.
                    if (preview != null && _uid == uid)
                      Positioned(
                        left: m.x(preview.start),
                        width: math.max(4.0, m.w(preview.start, preview.end)),
                        top: 4,
                        bottom: 4,
                        child: IgnorePointer(
                          child: _block(
                            color: color,
                            window: preview,
                            m: m,
                            selected: true,
                            problem: problem,
                          ),
                        ),
                      ),
                    if (problem != null && _uid == uid && preview != null)
                      Positioned(
                        left: m.x(preview.end) + 6,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Text(
                              problem,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.red,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  /// One of a person's shift blocks: click to select the shift, drag the
  /// middle to slide it, drag an end to change its times.
  Widget _blockHandle(
    TimelineMetrics m,
    String uid,
    Shift shift,
    TimeWindow b,
    Color color,
  ) {
    final width = math.max(4.0, m.w(b.start, b.end));
    final edges = width >= 3 * _edge;
    final dragging = _uid == uid && _old == b && _mode != _Drag.draw;
    final warning = shift.pieces
        .where((p) => p.start >= b.start && p.end <= b.end)
        .map((p) => widget.warnings[p.id])
        .whereType<String>()
        .firstOrNull;
    final isSelected = widget.selectedShiftId == shift.id;
    return Tooltip(
      message: [
        '${personName(widget.users[uid])} ${formatRange(b.start, b.end, compact: false)}',
        if (shift.isTraining)
          'Training ${personName(widget.users[shift.traineeId])}',
        ?warning,
        'Drag to move · drag the ends to change times',
      ].join('\n'),
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: () => widget.onSelectShift(isSelected ? null : shift.id),
        onPanStart: (d) {
          final x = d.localPosition.dx;
          setState(() {
            _uid = uid;
            _old = b;
            _dx = 0;
            _mode = edges && x <= _edge
                ? _Drag.resizeStart
                : (edges && x >= width - _edge ? _Drag.resizeEnd : _Drag.move);
          });
        },
        onPanUpdate: (d) => setState(() => _dx += d.delta.dx),
        onPanEnd: (_) => _endDrag(m),
        onPanCancel: () => _endDrag(m),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: dragging ? 0.25 : 1,
                  child: _block(
                    color: color,
                    window: b,
                    m: m,
                    selected: isSelected,
                    problem: warning,
                    // Hat: this person is training (a solo step of the
                    // training flow). Link: paired with someone, so the
                    // trainer gets the link but not the hat.
                    training: widget.trainingLabels.containsKey(shift.userId),
                    linked: shift.isTraining,
                  ),
                ),
              ),
              if (edges) ...[
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _edge,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                  ),
                ),
                const Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _edge,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _block({
    required Color color,
    required TimeWindow window,
    required TimelineMetrics m,
    required bool selected,
    String? problem,
    bool training = false,
    bool linked = false,
    bool admin = false,
  }) {
    final width = m.w(window.start, window.end);
    final fg = readableOn(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: selected
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
            : null,
        border: Border.all(
          color: problem != null
              ? Colors.red
              : (selected ? Colors.white : Colors.transparent),
          width: problem != null || selected ? 1.5 : 0,
        ),
      ),
      child: width < 56
          ? (admin && width >= 16
                ? Center(child: Icon(Icons.assignment_outlined, size: 13, color: fg))
                : null)
          : Row(
              children: [
                if (admin) ...[
                  Icon(Icons.assignment_outlined, size: 13, color: fg),
                  const SizedBox(width: 3),
                ],
                if (training) ...[
                  Icon(Icons.school, size: 13, color: fg),
                  const SizedBox(width: 3),
                ],
                if (linked && width >= 76) ...[
                  Icon(Icons.link, size: 14, color: fg),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    '${formatRange(window.start, window.end)}'
                    '${width > 120 ? ' · ${formatHours(window.minutes / 60)}h' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
