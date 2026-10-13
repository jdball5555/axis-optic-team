import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../services/schedule_repository.dart';
import 'mobile_data.dart';
import 'mobile_ui.dart';

enum _ScheduleView { shifts, availability, timeOff }

/// Your schedule: posted shifts week by week, your availability and your
/// time off requests. Only for people on the team table (building the
/// schedule stays on the desktop app).
class MyScheduleMobilePage extends ConsumerStatefulWidget {
  const MyScheduleMobilePage({super.key});

  @override
  ConsumerState<MyScheduleMobilePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends ConsumerState<MyScheduleMobilePage> {
  _ScheduleView _view = _ScheduleView.shifts;
  int _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(mobileAccessProvider);
    final storeId = ref.watch(currentStoreIdProvider);
    final member = access.member;
    if (!access.mySchedule || storeId == null || member?.id == null) {
      return MPage(
        title: 'Schedule',
        children: [
          MEmpty(
            icon: Icons.calendar_month_outlined,
            title: 'No schedule here',
            message: access.isOnTeam
                ? 'The schedule isn\'t turned on for this store.'
                : 'Shifts, availability and time off show up for people on the team.',
          ),
        ],
      );
    }

    final segmented = MSegmented<_ScheduleView>(
      options: const [
        (_ScheduleView.shifts, 'Shifts'),
        (_ScheduleView.availability, 'Availability'),
        (_ScheduleView.timeOff, 'Time off'),
      ],
      value: _view,
      onChanged: (v) => setState(() => _view = v),
    );

    return MPage(
      title: 'Schedule',
      subtitle: switch (_view) {
        _ScheduleView.shifts => 'Your posted shifts',
        _ScheduleView.availability => 'When you can work',
        _ScheduleView.timeOff => 'Days you need off',
      },
      children: [
        segmented,
        const SizedBox(height: 18),
        switch (_view) {
          _ScheduleView.shifts => _ShiftsWeek(
            storeId: storeId,
            member: member!,
            weekOffset: _weekOffset,
            onWeek: (d) => setState(() => _weekOffset += d),
            onThisWeek: () => setState(() => _weekOffset = 0),
          ),
          _ScheduleView.availability => _AvailabilityView(
            storeId: storeId,
            member: member!,
          ),
          _ScheduleView.timeOff => _TimeOffView(storeId: storeId, member: member!),
        },
      ],
    );
  }
}

// =============================================================================
// Shifts
// =============================================================================

class _ShiftsWeek extends ConsumerWidget {
  const _ShiftsWeek({
    required this.storeId,
    required this.member,
    required this.weekOffset,
    required this.onWeek,
    required this.onThisWeek,
  });

  final String storeId;
  final UserModel member;
  final int weekOffset;
  final ValueChanged<int> onWeek;
  final VoidCallback onThisWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final config =
        ref.watch(scheduleConfigProvider(storeId)).valueOrNull ??
        const ScheduleConfig();
    final weekStart = addDays(
      weekStartFor(DateTime.now(), config.weekStart),
      7 * weekOffset,
    );
    final async = ref.watch(
      postedWeekProvider((
        storeId: storeId,
        weekStart: dateKey(weekStart),
        boards: boardsKey(config),
      )),
    );
    final id = member.id!;
    final mine = (async.valueOrNull ?? const <RosterEntry>[])
        .where((e) => e.userId == id)
        .toList();
    final byDay = <String, List<RosterEntry>>{};
    for (final e in mine) {
      (byDay[e.date] ??= []).add(e);
    }
    for (final l in byDay.values) {
      l.sort((a, b) => a.start.compareTo(b.start));
    }
    final hours = mine.fold<double>(0, (a, e) => a + e.hours);
    final timeOff =
        ref
            .watch(memberTimeOffProvider((storeId: storeId, memberId: id)))
            .valueOrNull ??
        const <TimeOffRequest>[];
    final users = {
      for (final u
          in ref.watch(allStoreUsersStreamProvider).valueOrNull ??
              const <UserModel>[])
        if (u.id != null) u.id!: u,
    };
    final today = dateKey(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Week picker.
        Row(
          children: [
            _RoundIcon(icon: Icons.chevron_left, onTap: () => onWeek(-1)),
            Expanded(
              child: GestureDetector(
                onTap: weekOffset == 0 ? null : onThisWeek,
                child: Column(
                  children: [
                    Text(
                      weekRange(weekStart),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.title,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      weekOffset == 0
                          ? 'This week'
                          : weekOffset == 1
                          ? 'Next week'
                          : weekOffset == -1
                          ? 'Last week'
                          : 'Tap for this week',
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ],
                ),
              ),
            ),
            _RoundIcon(icon: Icons.chevron_right, onTap: () => onWeek(1)),
          ],
        ),
        const SizedBox(height: 14),
        MStatGrid(
          children: [
            MStat(label: 'Hours', value: formatHours(hours), icon: Icons.schedule),
            MStat(
              label: 'Shifts',
              value: '${byDay.length}',
              icon: Icons.event_available_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (async.isLoading && !async.hasValue)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (context) {
                final day = addDays(weekStart, i);
                final key = dateKey(day);
                final off = timeOff
                    .where(
                      (r) =>
                          r.status == 'approved' &&
                          key.compareTo(r.startDate) >= 0 &&
                          key.compareTo(r.endDate) <= 0,
                    )
                    .firstOrNull;
                return _DayRow(
                  day: day,
                  isToday: key == today,
                  entries: byDay[key] ?? const [],
                  timeOff: off,
                  users: users,
                );
              },
            ),
        if (mine.isEmpty && !(async.isLoading && !async.hasValue))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Nothing posted for you this week yet. Posted schedules show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return Material(
      color: c.card,
      shape: CircleBorder(side: BorderSide(color: c.line.withValues(alpha: 0.8))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 22, color: c.text),
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.isToday,
    required this.entries,
    required this.timeOff,
    required this.users,
  });

  final DateTime day;
  final bool isToday;
  final List<RosterEntry> entries;
  final TimeOffRequest? timeOff;
  final Map<String, UserModel> users;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final working = entries.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date block.
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isToday ? AppTheme.tint(AppTheme.accent) : c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isToday
                    ? AppTheme.edge(AppTheme.accent)
                    : c.line.withValues(alpha: 0.7),
                width: isToday ? 1.4 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  weekdayShort[day.weekday - 1].toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: isToday ? AppTheme.onTint(AppTheme.accent) : c.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isToday ? AppTheme.onTint(AppTheme.accent) : c.title,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: !working
                ? Container(
                    constraints: const BoxConstraints(minHeight: 62),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.line.withValues(alpha: 0.45)),
                    ),
                    child: timeOff != null
                        ? Row(
                            children: [
                              MPill('Time off', color: AppTheme.green, icon: Icons.beach_access_outlined),
                              if (timeOff!.reason.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    timeOff!.reason,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: c.muted),
                                  ),
                                ),
                              ],
                            ],
                          )
                        : Text(
                            'Off',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.muted,
                            ),
                          ),
                  )
                : Column(
                    children: [
                      for (final e in entries)
                        Padding(
                          padding: EdgeInsets.only(bottom: e == entries.last ? 0 : 8),
                          child: _ShiftTile(entry: e, users: users),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ShiftTile extends StatelessWidget {
  const _ShiftTile({required this.entry, required this.users});
  final RosterEntry entry;
  final Map<String, UserModel> users;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final accent = entry.isAdmin ? AppTheme.purple : AppTheme.accent;
    final partner = entry.trainingWith ?? entry.traineeId;
    return MCard(
      padding: EdgeInsets.zero,
      radius: 14,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatRange(entry.start, entry.end, compact: false),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: c.title,
                            ),
                          ),
                        ),
                        Text(
                          '${formatHours(entry.hours)}h',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                    if (entry.area.isNotEmpty || entry.isAdmin || partner != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (entry.isAdmin)
                            MPill('Admin time', color: AppTheme.purple)
                          else if (entry.area.isNotEmpty)
                            MPill(entry.area, color: AppTheme.blue),
                          if (partner != null)
                            MPill(
                              entry.trainingWith != null
                                  ? 'Training with ${firstNameOf(users[partner])}'
                                  : 'Training ${firstNameOf(users[partner])}',
                              color: AppTheme.teal,
                              icon: Icons.school,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Availability
// =============================================================================

class _AvailabilityView extends StatelessWidget {
  const _AvailabilityView({required this.storeId, required this.member});
  final String storeId;
  final UserModel member;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final raw = member.activeAvailability;
    final hasAny = raw != null && raw.isNotEmpty;
    final byDay = parseAvailability(raw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hasAny)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: MCard(
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: c.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You haven\'t set your availability yet. Add it so the '
                      'schedule only puts you on when you can work.',
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: c.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        MCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < 7; i++)
                _AvailabilityLine(
                  day: weekdayNames[i],
                  windows: byDay[availabilityDays[i]] ?? const [],
                  unset: !hasAny,
                  last: i == 6,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MButton(
          label: hasAny ? 'Edit availability' : 'Set availability',
          icon: Icons.edit_calendar_outlined,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AvailabilityEditorPage(
                storeId: storeId,
                memberId: member.id!,
                initial: hasAny ? byDay : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AvailabilityLine extends StatelessWidget {
  const _AvailabilityLine({
    required this.day,
    required this.windows,
    required this.unset,
    required this.last,
  });

  final String day;
  final List<TimeWindow> windows;
  final bool unset;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final text = unset
        ? 'Not set'
        : windows.isEmpty
        ? 'Unavailable'
        : windows.map((w) => _windowText(w)).join(', ');
    return MField(
      day,
      null,
      last: last,
      valueWidget: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: windows.isEmpty ? c.muted : c.text,
        ),
      ),
    );
  }
}

String _windowText(TimeWindow w) {
  if (w.start % 1440 == 0 && w.end - w.start >= 1440) return 'All day';
  return formatRange(w.start, w.end);
}

/// Edit your availability: for each day, unavailable, all day, or one or
/// more time windows.
class AvailabilityEditorPage extends StatefulWidget {
  const AvailabilityEditorPage({
    super.key,
    required this.storeId,
    required this.memberId,
    this.initial,
  });

  final String storeId;
  final String memberId;

  /// Current availability (null = none on file yet).
  final Map<String, List<TimeWindow>>? initial;

  @override
  State<AvailabilityEditorPage> createState() => _AvailabilityEditorPageState();
}

class _AvailabilityEditorPageState extends State<AvailabilityEditorPage> {
  late final Map<String, List<TimeWindow>> _days = {
    for (final d in availabilityDays)
      d: [...?widget.initial?[d]],
  };
  bool _saving = false;
  bool _changed = false;

  void _set(String day, List<TimeWindow> windows) => setState(() {
    _days[day] = windows;
    _changed = true;
  });

  Future<int?> _pickTime(int minutes, String help) async {
    final t = await showTimePicker(
      context: context,
      helpText: help,
      initialTime: TimeOfDay(hour: (minutes % 1440) ~/ 60, minute: minutes % 60),
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (t == null) return null;
    // Snap to the schedule's 15-minute steps.
    final m = t.hour * 60 + t.minute;
    return (m / 15).round() * 15 % 1440;
  }

  Future<void> _addWindow(String day) async {
    final start = await _pickTime(16 * 60, 'Available from');
    if (start == null || !mounted) return;
    final endPick = await _pickTime((start + 6 * 60) % 1440, 'Available until');
    if (endPick == null) return;
    var end = endPick;
    if (end <= start) end += 1440; // past midnight
    _set(day, mergeWindows([..._days[day]!, TimeWindow(start, end)]));
  }

  Future<void> _editWindow(String day, int index) async {
    final w = _days[day]![index];
    final start = await _pickTime(w.start, 'Available from');
    if (start == null || !mounted) return;
    final endPick = await _pickTime(w.end % 1440, 'Available until');
    if (endPick == null) return;
    var end = endPick;
    if (end <= start) end += 1440;
    final list = [..._days[day]!]..[index] = TimeWindow(start, end);
    _set(day, mergeWindows(list));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await MobileWrites.saveAvailability(widget.storeId, widget.memberId, _days);
      if (!mounted) return;
      mSnack(context, 'Availability saved.');
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) mSnack(context, 'Couldn\'t save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return PopScope(
      canPop: !_changed || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(ctx).cardColor,
            title: const Text('Discard changes?'),
            content: const Text('Your availability changes haven\'t been saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Discard', style: TextStyle(color: AppTheme.red)),
              ),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          setState(() => _changed = false);
          Navigator.of(context).pop();
        }
      },
      child: MSubPage(
        title: 'Availability',
        bottom: MButton(
          label: 'Save availability',
          busy: _saving,
          onPressed: _changed ? _save : null,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Set the times you can work each day. Leaders see these when they build the schedule.',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < 7; i++) ...[
              _DayEditor(
                label: weekdayNames[i],
                windows: _days[availabilityDays[i]]!,
                onAllDay: () => _set(availabilityDays[i], const [TimeWindow(0, 1440)]),
                onNone: () => _set(availabilityDays[i], const []),
                onAdd: () => _addWindow(availabilityDays[i]),
                onEdit: (k) => _editWindow(availabilityDays[i], k),
                onRemove: (k) => _set(
                  availabilityDays[i],
                  [..._days[availabilityDays[i]]!]..removeAt(k),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayEditor extends StatelessWidget {
  const _DayEditor({
    required this.label,
    required this.windows,
    required this.onAllDay,
    required this.onNone,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final String label;
  final List<TimeWindow> windows;
  final VoidCallback onAllDay;
  final VoidCallback onNone;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final allDay = windows.length == 1 && _windowText(windows.first) == 'All day';
    return MCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: c.title,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                color: Theme.of(context).cardColor,
                icon: Icon(Icons.more_horiz, color: c.muted),
                onSelected: (v) {
                  if (v == 'all') onAllDay();
                  if (v == 'none') onNone();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'all', child: Text('Available all day')),
                  PopupMenuItem(value: 'none', child: Text('Unavailable')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (windows.isEmpty)
                Text('Unavailable', style: TextStyle(fontSize: 13.5, color: c.muted)),
              for (var k = 0; k < windows.length; k++)
                InputChip(
                  label: Text(_windowText(windows[k])),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onTint(AppTheme.teal),
                  ),
                  backgroundColor: AppTheme.tint(AppTheme.teal),
                  side: BorderSide(color: AppTheme.edge(AppTheme.teal)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  onPressed: allDay ? null : () => onEdit(k),
                  onDeleted: () => onRemove(k),
                  deleteIconColor: AppTheme.onTint(AppTheme.teal),
                ),
              if (!allDay)
                ActionChip(
                  avatar: Icon(Icons.add, size: 16, color: c.text),
                  label: const Text('Add time'),
                  labelStyle: TextStyle(fontWeight: FontWeight.w600, color: c.text),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  side: BorderSide(color: c.line),
                  backgroundColor: Colors.transparent,
                  onPressed: onAdd,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Time off
// =============================================================================

class _TimeOffView extends ConsumerWidget {
  const _TimeOffView({required this.storeId, required this.member});
  final String storeId;
  final UserModel member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final async = ref.watch(
      memberTimeOffProvider((storeId: storeId, memberId: member.id!)),
    );
    final today = dateKey(DateTime.now());
    final all = async.valueOrNull ?? const <TimeOffRequest>[];
    final upcoming = all.where((r) => r.endDate.compareTo(today) >= 0).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final past = all.where((r) => r.endDate.compareTo(today) < 0).take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MButton(
          label: 'Request time off',
          icon: Icons.add,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TimeOffRequestPage(storeId: storeId, memberId: member.id!),
            ),
          ),
        ),
        if (async.isLoading && !async.hasValue)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (all.isEmpty)
          const MEmpty(
            icon: Icons.beach_access_outlined,
            title: 'No requests yet',
            message: 'Ask for days off here. Leaders approve them on the desktop app.',
          )
        else ...[
          const MSection('Upcoming'),
          if (upcoming.isEmpty)
            Text('Nothing coming up.', style: TextStyle(color: c.muted)),
          for (final r in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TimeOffTile(request: r, storeId: storeId),
            ),
          if (past.isNotEmpty) ...[
            const MSection('Past'),
            for (final r in past)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TimeOffTile(request: r, storeId: storeId, past: true),
              ),
          ],
        ],
      ],
    );
  }
}

class _TimeOffTile extends StatelessWidget {
  const _TimeOffTile({required this.request, required this.storeId, this.past = false});
  final TimeOffRequest request;
  final String storeId;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final start = parseDateKey(request.startDate);
    final end = parseDateKey(request.endDate);
    final sameDay = request.startDate == request.endDate;
    final dates = start == null
        ? request.startDate
        : sameDay || end == null
        ? shortDate(start)
        : '${shortDate(start)} – ${shortDate(end)}';
    final (label, color) = switch (request.status) {
      'approved' => ('Approved', AppTheme.green),
      'denied' => ('Denied', AppTheme.red),
      _ => ('Pending', AppTheme.yellow),
    };
    return Opacity(
      opacity: past ? 0.65 : 1,
      child: MCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dates,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: c.title,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (request.isPartDay)
                        '${request.startTime} – ${request.endTime}'
                      else
                        'All day',
                      if (request.reason.isNotEmpty) request.reason,
                    ].join(' · '),
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MPill(label, color: color),
                if (request.isPending && !past)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: c.muted,
                    ),
                    onPressed: () => _cancel(context),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        title: const Text('Cancel this request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel request', style: TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MobileWrites.cancelTimeOff(storeId, request.id);
      if (context.mounted) mSnack(context, 'Request canceled.');
    } catch (_) {
      if (context.mounted) mSnack(context, 'Couldn\'t cancel. Please try again.');
    }
  }
}

/// Ask for time off: dates, all day or part of the day, and a reason.
class TimeOffRequestPage extends StatefulWidget {
  const TimeOffRequestPage({super.key, required this.storeId, required this.memberId});
  final String storeId;
  final String memberId;

  @override
  State<TimeOffRequestPage> createState() => _TimeOffRequestPageState();
}

class _TimeOffRequestPageState extends State<TimeOffRequestPage> {
  DateTimeRange? _range;
  bool _partDay = false;
  TimeOfDay _from = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 17, minute: 0);
  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final today = dateOnly(DateTime.now());
    final r = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 2),
      initialDateRange: _range,
      helpText: 'Days you need off',
    );
    if (r != null) setState(() => _range = r);
  }

  Future<void> _pickTime(bool from) async {
    final t = await showTimePicker(context: context, initialTime: from ? _from : _to);
    if (t == null) return;
    setState(() {
      if (from) {
        _from = t;
      } else {
        _to = t;
      }
    });
  }

  Future<void> _submit() async {
    final r = _range;
    if (r == null) return;
    setState(() => _saving = true);
    try {
      await MobileWrites.requestTimeOff(
        storeId: widget.storeId,
        memberId: widget.memberId,
        start: r.start,
        end: r.end,
        reason: _reason.text.trim(),
        startMinute: _partDay ? _from.hour * 60 + _from.minute : null,
        endMinute: _partDay ? _to.hour * 60 + _to.minute : null,
      );
      if (!mounted) return;
      mSnack(context, 'Request sent.');
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) mSnack(context, 'Couldn\'t send. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final r = _range;
    final dates = r == null
        ? 'Pick dates'
        : dateKey(r.start) == dateKey(r.end)
        ? longDate(r.start)
        : '${shortDate(r.start)} – ${shortDate(r.end)}';
    return MSubPage(
      title: 'Request time off',
      bottom: MButton(
        label: 'Send request',
        busy: _saving,
        onPressed: r == null ? null : _submit,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const MSection('When', top: 4),
          MCard(
            onTap: _pickDates,
            child: Row(
              children: [
                Icon(Icons.date_range_outlined, color: AppTheme.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dates,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: r == null ? c.muted : c.title,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: c.muted),
              ],
            ),
          ),
          const SizedBox(height: 10),
          MCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _partDay,
              activeTrackColor: AppTheme.accent,
              title: Text(
                'Only part of the day',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
              ),
              onChanged: (v) => setState(() => _partDay = v),
            ),
          ),
          if (_partDay) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: MCard(
                    onTap: () => _pickTime(true),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('From', style: TextStyle(fontSize: 12.5, color: c.muted)),
                        const SizedBox(height: 4),
                        Text(
                          _from.format(context),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: c.title,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MCard(
                    onTap: () => _pickTime(false),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Until', style: TextStyle(fontSize: 12.5, color: c.muted)),
                        const SizedBox(height: 4),
                        Text(
                          _to.format(context),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: c.title,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          const MSection('Reason (optional)'),
          TextField(
            controller: _reason,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Family trip, appointment, school event…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
              ),
              filled: true,
              fillColor: c.card,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Your leaders review requests on the desktop app. You\'ll see the answer here.',
            style: TextStyle(fontSize: 13, height: 1.4, color: c.muted),
          ),
        ],
      ),
    );
  }
}
