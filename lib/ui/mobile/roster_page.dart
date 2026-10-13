import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/store_settings_model.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../services/schedule_repository.dart';
import 'mobile_data.dart';
import 'mobile_ui.dart';
import 'shift_board_mobile.dart';

enum _RosterView { roster, shift }

/// Roster: who's working any day. With access, the Shift board too
/// (positions, drag people onto them).
class RosterMobilePage extends ConsumerStatefulWidget {
  const RosterMobilePage({super.key});

  @override
  ConsumerState<RosterMobilePage> createState() => _RosterMobilePageState();
}

class _RosterMobilePageState extends ConsumerState<RosterMobilePage> {
  DateTime _date = dateOnly(DateTime.now());
  _RosterView _view = _RosterView.roster;
  String? _board; // null = all schedules

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(mobileAccessProvider);
    final storeId = ref.watch(currentStoreIdProvider);
    if (storeId == null) return const SizedBox.shrink();
    if (!access.scheduleOn) {
      return const MPage(
        title: 'Roster',
        children: [
          MEmpty(
            icon: Icons.view_timeline_outlined,
            title: 'No schedule yet',
            message: 'The schedule isn\'t turned on for this store.',
          ),
        ],
      );
    }
    final config =
        ref.watch(scheduleConfigProvider(storeId)).valueOrNull ??
        const ScheduleConfig();
    final weekStart = weekStartFor(_date, config.weekStart);
    final view = access.seeShiftBoard ? _view : _RosterView.roster;
    final today = dateOnly(DateTime.now());

    return MPage(
      title: view == _RosterView.shift ? 'Shift' : 'Roster',
      subtitle: longDate(_date),
      trailing: _date == today
          ? null
          : TextButton(
              onPressed: () => setState(() => _date = today),
              child: Text(
                'Today',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.accent),
              ),
            ),
      children: [
        if (access.seeShiftBoard) ...[
          MSegmented<_RosterView>(
            options: const [
              (_RosterView.roster, 'Roster'),
              (_RosterView.shift, 'Shift board'),
            ],
            value: view,
            onChanged: (v) => setState(() => _view = v),
          ),
          const SizedBox(height: 16),
        ],
        _DayStrip(
          weekStart: weekStart,
          selected: _date,
          onSelect: (d) => setState(() => _date = d),
          onWeek: (d) => setState(() => _date = addDays(_date, 7 * d)),
        ),
        const SizedBox(height: 16),
        if (view == _RosterView.shift)
          ShiftBoardMobile(
            storeId: storeId,
            date: _date,
            canEdit: access.editShiftBoard,
          )
        else ...[
          if (config.allBoards.length > 1) ...[
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _BoardChip(
                    label: 'All schedules',
                    selected: _board == null,
                    onTap: () => setState(() => _board = null),
                  ),
                  for (final b in config.allBoards)
                    _BoardChip(
                      label: b.name,
                      selected: _board == b.id,
                      onTap: () => setState(() => _board = b.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _DayRoster(
            storeId: storeId,
            config: config,
            date: _date,
            weekStart: weekStart,
            boardIds: [
              for (final b in config.allBoards)
                if (_board == null || _board == b.id) b.id,
            ],
            drafts: access.draftSchedules,
          ),
        ],
      ],
    );
  }
}

class _BoardChip extends StatelessWidget {
  const _BoardChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.tint(AppTheme.teal) : c.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppTheme.edge(AppTheme.teal) : c.line.withValues(alpha: 0.8),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppTheme.onTint(AppTheme.teal) : c.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The week's days as tappable tiles, with arrows for other weeks.
class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.weekStart,
    required this.selected,
    required this.onSelect,
    required this.onWeek,
  });

  final DateTime weekStart;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onWeek;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final today = dateOnly(DateTime.now());
    return Row(
      children: [
        _Arrow(icon: Icons.chevron_left, onTap: () => onWeek(-1)),
        const SizedBox(width: 4),
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(
              builder: (context) {
                final d = addDays(weekStart, i);
                final isSel = d == selected;
                final isToday = d == today;
                return GestureDetector(
                  onTap: () => onSelect(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? AppTheme.tint(AppTheme.accent) : c.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSel
                            ? AppTheme.edge(AppTheme.accent)
                            : c.line.withValues(alpha: 0.7),
                        width: isSel ? 1.4 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          weekdayShort[d.weekday - 1].substring(0, 2).toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: isSel ? AppTheme.onTint(AppTheme.accent) : c.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isSel ? AppTheme.onTint(AppTheme.accent) : c.title,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isToday ? AppTheme.accent : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(width: 4),
        _Arrow(icon: Icons.chevron_right, onTap: () => onWeek(1)),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
      child: Icon(icon, color: MColors(context).muted),
    ),
  );
}

/// Everyone working one day, morning to close.
class _DayRoster extends ConsumerWidget {
  const _DayRoster({
    required this.storeId,
    required this.config,
    required this.date,
    required this.weekStart,
    required this.boardIds,
    required this.drafts,
  });

  final String storeId;
  final ScheduleConfig config;
  final DateTime date;
  final DateTime weekStart;
  final List<String> boardIds;

  /// Show the working schedule (leaders) instead of only what's posted.
  final bool drafts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final key = dateKey(date);
    final entries = <RosterEntry>[];
    var loading = false;
    bool? posted; // leaders: is this day posted?

    if (drafts) {
      for (final id in boardIds) {
        final async = ref.watch(
          scheduleWeekProvider((
            storeId: storeId,
            weekStart: dateKey(weekStart),
            boardId: id,
          )),
        );
        if (async.isLoading && !async.hasValue) loading = true;
        final day = async.valueOrNull?[key];
        if (day == null || day.shifts.isEmpty) continue;
        entries.addAll(entriesFromDay(day, id));
        posted = (posted ?? true) && day.isPosted;
      }
    } else {
      final async = ref.watch(
        postedWeekProvider((
          storeId: storeId,
          weekStart: dateKey(weekStart),
          boards: boardIds.join(','),
        )),
      );
      loading = async.isLoading && !async.hasValue;
      entries.addAll((async.valueOrNull ?? const <RosterEntry>[]).where((e) => e.date == key));
    }
    entries.sort((a, b) {
      final s = a.start.compareTo(b.start);
      return s != 0 ? s : a.end.compareTo(b.end);
    });

    final users = {
      for (final u
          in ref.watch(allStoreUsersStreamProvider).valueOrNull ?? const <UserModel>[])
        if (u.id != null) u.id!: u,
    };
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final me = ref.watch(mobileAccessProvider).member?.id;

    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (entries.isEmpty) {
      return MEmpty(
        icon: Icons.event_busy_outlined,
        title: 'No one on the roster',
        message: drafts
            ? 'Nothing is scheduled for ${weekdayNames[date.weekday - 1]} yet.'
            : 'Nothing is posted for ${weekdayNames[date.weekday - 1]} yet.',
        compact: true,
      );
    }

    final floor = entries.where((e) => !e.isAdmin).toList();
    final people = {for (final e in floor) e.userId}.length;
    final hours = entries.fold<double>(0, (a, e) => a + e.hours);
    final lo = (entries.map((e) => e.start).reduce(math.min) ~/ 60) * 60;
    final hi = ((entries.map((e) => e.end).reduce(math.max) + 59) ~/ 60) * 60;

    String part(RosterEntry e) {
      if (e.start < 11 * 60) return 'Morning';
      if (e.start < 16 * 60) return 'Afternoon';
      return 'Evening';
    }

    final groups = <String, List<RosterEntry>>{};
    for (final e in entries) {
      (groups[part(e)] ??= []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MPill('$people working', color: AppTheme.teal, large: true, icon: Icons.groups_2_outlined),
            MPill('${formatHours(hours)} hrs', color: AppTheme.blue, large: true, icon: Icons.schedule),
            if (posted != null)
              MPill(
                posted == true ? 'Posted' : 'Not posted yet',
                color: posted == true ? AppTheme.green : AppTheme.orange,
                large: true,
              ),
          ],
        ),
        for (final g in ['Morning', 'Afternoon', 'Evening'])
          if (groups[g] case final list?) ...[
            MSection('$g · ${list.length}'),
            for (final e in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RosterRow(
                  entry: e,
                  user: users[e.userId],
                  users: users,
                  settings: settings,
                  lo: lo,
                  hi: hi,
                  isMe: e.userId == me,
                ),
              ),
          ],
        if (drafts && posted != true) ...[
          const SizedBox(height: 4),
          Text(
            'You\'re seeing the working schedule. Team members see it once it\'s posted.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        ],
      ],
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.entry,
    required this.user,
    required this.users,
    required this.settings,
    required this.lo,
    required this.hi,
    required this.isMe,
  });

  final RosterEntry entry;
  final UserModel? user;
  final Map<String, UserModel> users;
  final StoreSettingsModel? settings;
  final int lo;
  final int hi;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final color = entry.isAdmin ? AppTheme.purple : titleColor(user?.title, settings);
    final partner = entry.trainingWith ?? entry.traineeId;
    final span = math.max(1, hi - lo);
    return MCard(
      padding: EdgeInsets.zero,
      radius: 14,
      borderColor: isMe ? AppTheme.edge(AppTheme.accent).withValues(alpha: 0.6) : null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isMe ? '${fullNameOf(user)} (you)' : fullNameOf(user),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.title,
                            ),
                          ),
                        ),
                        Text(
                          formatRange(entry.start, entry.end),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Where the shift sits in the day.
                    LayoutBuilder(
                      builder: (context, box) {
                        final w = box.maxWidth;
                        final left = w * (entry.start - lo) / span;
                        final width = math.max(6.0, w * entry.minutes / span);
                        return SizedBox(
                          height: 6,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: c.line.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: left,
                                width: math.min(width, w - left),
                                top: 0,
                                bottom: 0,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (user?.title != null ||
                        entry.area.isNotEmpty ||
                        entry.isAdmin ||
                        partner != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (entry.isAdmin)
                            MPill('Admin time', color: AppTheme.purple)
                          else if (user?.title != null)
                            MPill(user!.title!, color: titleColor(user!.title, settings)),
                          if (!entry.isAdmin && entry.area.isNotEmpty && entry.area != user?.title)
                            MPill(entry.area, color: AppTheme.blue),
                          if (partner != null)
                            MPill(
                              entry.trainingWith != null
                                  ? 'With ${firstNameOf(users[partner])}'
                                  : 'Training ${firstNameOf(users[partner])}',
                              color: AppTheme.teal,
                              icon: Icons.school,
                            ),
                          Text(
                            '${formatHours(entry.hours)}h',
                            style: TextStyle(fontSize: 12.5, color: c.muted),
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
