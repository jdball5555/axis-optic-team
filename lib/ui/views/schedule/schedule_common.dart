import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';
import '../../../models/store_settings_model.dart';
import '../../../models/user_model.dart';

// =============================================================================
// People helpers
// =============================================================================

String personName(UserModel? u, {bool short = false}) {
  if (u == null) return 'Unknown';
  final first = (u.preferredName?.trim().isNotEmpty ?? false)
      ? u.preferredName!.trim()
      : (u.firstName ?? '').trim();
  final last = (u.lastName ?? '').trim();
  if (short) return last.isEmpty ? first : '$first ${last[0]}.';
  return [first, last].where((s) => s.isNotEmpty).join(' ');
}

/// Can go on the schedule: still on the team (not past their last day,
/// not marked former / inactive).
bool isSchedulable(UserModel u) => isCurrentMember(u);

/// True if the person's title (or one of their tags) is allowed in [row].
bool userFitsRow(UserModel? u, ScheduleRow row) {
  if (!row.isRestricted) return true;
  if (u == null) return false;
  if (u.title != null && row.allowedTitles.contains(u.title)) return true;
  return (u.additionalTags ?? const []).any(row.allowedTitles.contains);
}

/// Numbers in someone's roster "avg shifts" (e.g. "4", "3-4", "4.5").
List<double> _avgShiftNumbers(UserModel? u) => RegExp(r'\d+(?:\.\d+)?')
    .allMatches(u?.avgShifts ?? '')
    .map((m) => double.parse(m.group(0)!))
    .toList();

/// Roughly how many shifts a week someone usually works, from the roster's
/// "avg shifts" ("3-4" → 3.5). Null when it isn't filled in.
double? avgShiftsEstimate(UserModel? u) {
  final n = _avgShiftNumbers(u);
  if (n.isEmpty) return null;
  return n.length == 1 ? n.first : (n[0] + n[1]) / 2;
}

/// Most shifts someone can get in a week: [base] (5 by default, set in the
/// schedule rules), unless their "avg shifts" says more (then that, up to 7).
int maxShiftsPerWeek(UserModel? u, {int base = 5}) {
  final n = _avgShiftNumbers(u);
  if (n.isEmpty) return base;
  final top = n.reduce((a, b) => a > b ? a : b);
  return top > base ? top.ceil().clamp(base, 7) : base;
}

/// Can [u] train others under the schedule's "Who can train" setting
/// (a title or additional tag in [ScheduleConfig.trainerTags]; empty = anyone)?
bool canTrain(UserModel? u, ScheduleConfig config) {
  if (config.trainerTags.isEmpty) return true;
  if (u == null) return false;
  if (u.title != null && config.trainerTags.contains(u.title)) return true;
  return (u.additionalTags ?? const []).any(config.trainerTags.contains);
}

Color colorForUser(UserModel? u, StoreSettingsModel? settings) {
  if (u?.title != null && settings != null) {
    final t = settings.titles.where((t) => t.name == u!.title).firstOrNull;
    if (t != null && t.color != 'Color') {
      final c = AppTheme.getColorFromName(t.color);
      if (c != Colors.grey) return c;
    }
  }
  return AppTheme.lightBlue;
}

Color readableOn(Color bg) =>
    bg.computeLuminance() > 0.45 ? const Color(0xFF111111) : Colors.white;

/// Outline color for a title-only row: the first allowed title (or tag) with
/// a color set in store settings, yellow if none has one.
Color colorForRow(ScheduleRow row, StoreSettingsModel? settings) {
  final configs = [...?settings?.titles, ...?settings?.tags];
  for (final name in row.allowedTitles) {
    final t = configs.where((t) => t.name == name).firstOrNull;
    if (t != null && t.color != 'Color') {
      final c = AppTheme.getColorFromName(t.color);
      if (c != Colors.grey) return c;
    }
  }
  return AppTheme.yellow;
}

/// Text for the tag shown after a slot's time: who can fill the row, or the
/// row's own name. Null for plain "anyone" rows.
String? rowTag(ScheduleRow row) {
  if (row.isRestricted) return row.allowedTitles.join(', ');
  return row.label.isNotEmpty ? row.label : null;
}

/// Small tag after a slot's time ("Leader"), filled in the title's color.
class SlotTag extends StatelessWidget {
  final String text;
  final Color? color; // null = neutral
  const SlotTag({super.key, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color ?? Theme.of(context).dividerColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: readableOn(bg),
        ),
      ),
    );
  }
}

/// Small blue "Shift 2 · Train on Register" badge for new hires.
class TrainingBadge extends StatelessWidget {
  final String label;
  final bool dense;
  const TrainingBadge({super.key, required this.label, this.dense = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: dense ? 0 : 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.tint(AppTheme.accent2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school, size: dense ? 11 : 12, color: AppTheme.onTint(AppTheme.accent2)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 10 : 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.onTint(AppTheme.accent2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drag payload for a person dragged out of the "Who can work" panel.
class PersonDrag {
  final String userId;
  const PersonDrag(this.userId);
}

/// Opens a popup menu where the pointer is.
Future<T?> showMenuAt<T>(
  BuildContext context,
  Offset globalPosition,
  List<PopupMenuEntry<T>> items,
) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  return showMenu<T>(
    context: context,
    color: Theme.of(context).cardColor,
    position: RelativeRect.fromRect(
      Rect.fromPoints(local, local),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
}

/// Dark-gray tile for template slots (needed time that isn't filled yet).
({Color fill, Color border, Color text}) slotColors(ThemeData theme) =>
    theme.brightness == Brightness.dark
    ? (
        fill: AppTheme.border,
        border: const Color(0xFF4A4A4A),
        text: AppTheme.gray,
      )
    : (
        fill: const Color(0xFF3A3A3A),
        border: const Color(0xFF2A2A2A),
        text: const Color(0xFFE0E0E0),
      );

/// Availability windows for a weekday from `active_availability`
/// (e.g. {"monday": [{"start": "16:00", "end": "22:30"}]}).
/// Returns null when the person has no availability on file.
List<TimeWindow>? availabilityFor(UserModel u, DateTime day) {
  final data = u.activeAvailability;
  if (data == null || data.isEmpty) return null;
  final key = weekdayNames[day.weekday - 1].toLowerCase();
  final raw = data[key];
  if (raw is! List) return const [];
  int? parse(dynamic v) {
    final parts = v?.toString().split(':');
    if (parts == null || parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  final result = <TimeWindow>[];
  for (final w in raw) {
    if (w is! Map) continue;
    final s = parse(w['start']);
    var e = parse(w['end']);
    if (s == null || e == null) continue;
    if (e <= s) e += 1440;
    result.add(TimeWindow(s, e));
  }
  return result;
}

// =============================================================================
// Time dropdown (15-minute steps)
// =============================================================================

class TimeDropdown extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;

  const TimeDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = kMaxScheduleMinute,
  });

  @override
  Widget build(BuildContext context) {
    final options = <int>[
      for (var m = min; m <= max; m += kScheduleStep) m,
    ];
    if (!options.contains(value)) {
      options
        ..add(value)
        ..sort();
    }
    return DropdownButtonFormField<int>(
      // Re-create when the value changes from outside so it never shows stale.
      key: ValueKey('$label-$value-$min-$max'),
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 320,
      dropdownColor: Theme.of(context).cardColor,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final m in options)
          DropdownMenuItem(value: m, child: Text(formatMinutes(m))),
      ],
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? value),
    );
  }
}

// =============================================================================
// Title picker
// =============================================================================

Future<List<String>?> showTitlePicker(
  BuildContext context, {
  required List<String> allTitles,
  required List<String> selected,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _TitlePickerDialog(all: allTitles, initial: selected),
  );
}

class _TitlePickerDialog extends StatefulWidget {
  final List<String> all;
  final List<String> initial;
  const _TitlePickerDialog({required this.all, required this.initial});

  @override
  State<_TitlePickerDialog> createState() => _TitlePickerDialogState();
}

class _TitlePickerDialogState extends State<_TitlePickerDialog> {
  late final Set<String> _sel = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: const Text('Who can fill this row?'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Leave everything unchecked to allow anyone. Check titles to '
              'make this a leader (or title-only) row.',
              style: TextStyle(color: theme.textTheme.bodySmall?.color),
            ),
            const SizedBox(height: 12),
            if (widget.all.isEmpty)
              const Text('No titles set up yet. Add titles in Settings.'),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final t in widget.all)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _sel.contains(t),
                        title: Text(t),
                        onChanged: (v) => setState(
                          () => v == true ? _sel.add(t) : _sel.remove(t),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(_sel.clear),
          child: const Text('Anyone'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _sel.toList()),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// =============================================================================
// Row editor (used by the template builder and for one-off day rows)
// =============================================================================

Future<ScheduleRow?> showRowEditor(
  BuildContext context, {
  required ScheduleRow row,
  required List<String> allTitles,
  String title = 'Edit row',
}) {
  return showDialog<ScheduleRow>(
    context: context,
    builder: (_) =>
        _RowEditorDialog(row: row, allTitles: allTitles, title: title),
  );
}

class _RowEditorDialog extends StatefulWidget {
  final ScheduleRow row;
  final List<String> allTitles;
  final String title;
  const _RowEditorDialog({
    required this.row,
    required this.allTitles,
    required this.title,
  });

  @override
  State<_RowEditorDialog> createState() => _RowEditorDialogState();
}

class _RowEditorDialogState extends State<_RowEditorDialog> {
  late final TextEditingController _label = TextEditingController(
    text: widget.row.label,
  );
  late List<TimeWindow> _windows = [...widget.row.windows];
  late List<String> _titles = [...widget.row.allowedTitles];
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final sorted = [..._windows]..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].end <= sorted[i].start) {
        setState(() => _error = 'Each window must end after it starts.');
        return;
      }
      if (i > 0 && sorted[i].start < sorted[i - 1].end) {
        setState(() => _error = 'Windows in the same row can\'t overlap.');
        return;
      }
    }
    Navigator.pop(
      context,
      widget.row.copyWith(
        label: _label.text.trim(),
        windows: mergeWindows(sorted),
        allowedTitles: _titles,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Row name (optional)',
                  hintText: 'e.g. Leader, Drive-thru, Kitchen',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Needs someone from',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _windows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TimeDropdown(
                          label: 'Start',
                          value: _windows[i].start,
                          onChanged: (v) => setState(() {
                            _error = null;
                            _windows[i] = TimeWindow(v, _windows[i].end);
                          }),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('to'),
                      ),
                      Expanded(
                        child: TimeDropdown(
                          label: 'End',
                          value: _windows[i].end,
                          onChanged: (v) => setState(() {
                            _error = null;
                            _windows[i] = TimeWindow(_windows[i].start, v);
                          }),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove window',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _windows.removeAt(i)),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() {
                  final last = _windows.isEmpty ? null : _windows.last;
                  final s = last == null ? 11 * 60 : math.min(last.end + 120, 22 * 60);
                  _windows = [
                    ..._windows,
                    TimeWindow(s, math.min(s + 4 * 60, kMaxScheduleMinute)),
                  ];
                }),
                icon: const Icon(Icons.add, size: 18),
                label: Text(
                  _windows.isEmpty ? 'Add time window' : 'Add another window',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Who can fill it',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTitlePicker(
                    context,
                    allTitles: widget.allTitles,
                    selected: _titles,
                  );
                  if (picked != null) setState(() => _titles = picked);
                },
                icon: Icon(
                  _titles.isEmpty ? Icons.people_outline : Icons.star,
                  size: 18,
                ),
                label: Text(
                  _titles.isEmpty ? 'Anyone' : 'Only: ${_titles.join(', ')}',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save row')),
      ],
    );
  }
}

// =============================================================================
// Timeline geometry + header
// =============================================================================

class TimelineMetrics {
  final int start; // minutes
  final int end;
  final double width;

  const TimelineMetrics({
    required this.start,
    required this.end,
    required this.width,
  });

  double get ppm => width / math.max(1, end - start);
  double x(int minute) => (minute - start) * ppm;
  double w(int from, int to) => math.max(0.0, (to - from) * ppm);

  int minuteAt(double dx, {int step = kScheduleStep}) {
    final m = start + dx / ppm;
    final snapped = (m / step).floor() * step;
    return snapped.clamp(start, end).toInt();
  }
}

/// "5 AM", "12 PM", "6:30 PM" for the timeline header.
String hourLabel(int minutes) {
  final m = minutes % 1440;
  var h = m ~/ 60;
  final min = m % 60;
  final pm = h >= 12;
  h = h % 12;
  if (h == 0) h = 12;
  final time = min == 0 ? '$h' : '$h:${min.toString().padLeft(2, '0')}';
  return '$time ${pm ? 'PM' : 'AM'}';
}

/// Timeline span that fits every window and piece, rounded to whole hours.
(int, int) timelineRange(
  List<ScheduleRow> rows, [
  List<Shift> shifts = const [],
]) {
  var lo = 1 << 30;
  var hi = -1;
  for (final r in rows) {
    for (final w in r.windows) {
      lo = math.min(lo, w.start);
      hi = math.max(hi, w.end);
    }
  }
  for (final s in shifts) {
    for (final p in s.pieces) {
      lo = math.min(lo, p.start);
      hi = math.max(hi, p.end);
    }
  }
  if (hi < 0) return (5 * 60, 23 * 60);
  lo = (lo ~/ 60) * 60;
  hi = ((hi + 59) ~/ 60) * 60;
  if (hi - lo < 4 * 60) hi = lo + 4 * 60;
  return (lo, hi);
}

class TimelineHeader extends StatelessWidget {
  final TimelineMetrics metrics;
  final double height;
  const TimelineHeader({super.key, required this.metrics, this.height = 26});

  @override
  Widget build(BuildContext context) {
    const labelW = 56.0;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final every = metrics.ppm * 60 < labelW ? 120 : 60;
    return SizedBox(
      height: height,
      width: metrics.width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var m = metrics.start; m <= metrics.end; m += every)
            Positioned(
              // Keep the first and last labels inside the timeline.
              left: (metrics.x(m) - labelW / 2)
                  .clamp(0.0, (metrics.width - labelW).clamp(0.0, double.infinity))
                  .toDouble(),
              width: labelW,
              top: 4,
              child: Text(
                hourLabel(m),
                maxLines: 1,
                textAlign: m == metrics.start
                    ? TextAlign.left
                    : (metrics.x(m) + labelW / 2 > metrics.width
                          ? TextAlign.right
                          : TextAlign.center),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertical hour lines behind the grid.
class TimelineGridPainter extends CustomPainter {
  final TimelineMetrics metrics;
  final Color color;
  TimelineGridPainter(this.metrics, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final hour = Paint()
      ..color = color
      ..strokeWidth = 1;
    final half = Paint()
      ..color = color.withValues(alpha: color.a * 0.45)
      ..strokeWidth = 1;
    for (var m = metrics.start; m <= metrics.end; m += 30) {
      final x = metrics.x(m);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), m % 60 == 0 ? hour : half);
    }
  }

  @override
  bool shouldRepaint(covariant TimelineGridPainter old) =>
      old.metrics.start != metrics.start ||
      old.metrics.end != metrics.end ||
      old.metrics.width != metrics.width ||
      old.color != color;
}

/// "5 → 7 at 11a → 5 at 3p" style summary of how many people a set of rows
/// needs through the day.
String staffingSummary(List<ScheduleRow> rows) {
  final points = <int>{};
  for (final r in rows) {
    for (final w in r.windows) {
      points
        ..add(w.start)
        ..add(w.end);
    }
  }
  final sorted = points.toList()..sort();
  final parts = <String>[];
  int? last;
  for (final p in sorted) {
    final n = rows
        .where((r) => r.windows.any((w) => p >= w.start && p < w.end))
        .length;
    if (n == last) continue;
    parts.add('${formatMinutes(p, compact: true)}: $n');
    last = n;
  }
  return parts.join('  ·  ');
}

/// Picks which schedule (Front of house, Kitchen, …) or shift board is
/// shown.
class BoardSwitcher extends StatelessWidget {
  final List<({String id, String name})> boards;
  final String selectedId;
  final ValueChanged<String> onChanged;
  final String tooltip;

  const BoardSwitcher({
    super.key,
    required this.boards,
    required this.selectedId,
    required this.onChanged,
    this.tooltip = 'Switch schedule',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = boards.where((b) => b.id == selectedId).firstOrNull ?? boards.first;
    return PopupMenuButton<String>(
      tooltip: tooltip,
      color: theme.cardColor,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final b in boards)
          PopupMenuItem(
            value: b.id,
            child: Row(
              children: [
                Icon(
                  b.id == current.id ? Icons.check : Icons.calendar_view_week,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(b.name),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.tint(AppTheme.accent2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.edge(AppTheme.accent2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_view_week,
              size: 16,
              color: AppTheme.onTint(AppTheme.accent2),
            ),
            const SizedBox(width: 6),
            Text(
              current.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.onTint(AppTheme.accent2),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: AppTheme.onTint(AppTheme.accent2),
            ),
          ],
        ),
      ),
    );
  }
}
