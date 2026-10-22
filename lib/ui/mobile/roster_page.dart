import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/store_settings_model.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../services/schedule_repository.dart';
import 'mobile_data.dart';
import 'mobile_ui.dart';
import 'mobile_shell.dart';

/// Roster: who's working any day, and who isn't. The Shift board has its
/// own page (button at the top, with access).
class RosterMobilePage extends ConsumerStatefulWidget {
  const RosterMobilePage({super.key});

  @override
  ConsumerState<RosterMobilePage> createState() => _RosterMobilePageState();
}

class _RosterMobilePageState extends ConsumerState<RosterMobilePage> {
  DateTime _date = dateOnly(DateTime.now());
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
            icon: Icons.table_chart,
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
    final today = dateOnly(DateTime.now());

    return MPage(
      title: 'Roster',
      subtitle: longDate(_date),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_date != today)
            TextButton(
              onPressed: () => setState(() => _date = today),
              child: const Text(
                'Today',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          if (access.seeShiftBoard)
            _ShiftBoardButton(
              onTap: () => context.go(
                '${MobileTab.roster.path}/shift?date=${dateKey(_date)}',
              ),
            ),
        ],
      ),
      children: [
        MDayStrip(
          weekStart: weekStart,
          selected: _date,
          onSelect: (d) => setState(() => _date = d),
          onWeek: (d) => setState(() => _date = addDays(_date, 7 * d)),
        ),
        const SizedBox(height: 16),
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
          leader: access.team,
        ),
      ],
    );
  }
}

/// Opens the Shift board page.
class _ShiftBoardButton extends StatelessWidget {
  const _ShiftBoardButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Frosted glass on the page's gradient header.
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.32)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.grid_view_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              const Text(
                'Shift board',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardChip extends StatelessWidget {
  const _BoardChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
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
              color: selected
                  ? AppTheme.edge(AppTheme.teal)
                  : c.line.withValues(alpha: 0.8),
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

/// Everyone working one day, morning to close.
class _DayRoster extends ConsumerWidget {
  const _DayRoster({
    required this.storeId,
    required this.config,
    required this.date,
    required this.weekStart,
    required this.boardIds,
    required this.drafts,
    required this.leader,
  });

  final String storeId;
  final ScheduleConfig config;
  final DateTime date;
  final DateTime weekStart;
  final List<String> boardIds;

  /// Show the working schedule (leaders) instead of only what's posted.
  final bool drafts;

  /// Leaders also see who's off and when the others are available.
  final bool leader;

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
      entries.addAll(
        (async.valueOrNull ?? const <RosterEntry>[]).where(
          (e) => e.date == key,
        ),
      );
    }
    entries.sort((a, b) {
      final s = a.start.compareTo(b.start);
      return s != 0 ? s : a.end.compareTo(b.end);
    });

    final users = {
      for (final u
          in ref.watch(allStoreUsersStreamProvider).valueOrNull ??
              const <UserModel>[])
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
        icon: Icons.event_busy,
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

    // On right now (today only).
    final now = DateTime.now();
    final isToday = dateOnly(now) == dateOnly(date);
    final nowMinute = now.hour * 60 + now.minute;
    bool onNow(RosterEntry e) =>
        isToday && e.start <= nowMinute && nowMinute < e.end;
    final onNowCount = {
      for (final e in floor)
        if (onNow(e)) e.userId,
    }.length;

    // Everyone else on the team that day.
    final working = {for (final e in entries) e.userId};
    final titleOrder = [
      for (final t in settings?.titles ?? const <TitleConfig>[]) t.name,
    ];
    int rank(UserModel u) {
      // Higher titles first; no title last.
      return titleOrder.indexOf(u.title ?? '');
    }

    final offToday =
        [
          for (final u
              in ref.watch(usersStreamProvider).valueOrNull ??
                  const <UserModel>[])
            if (u.id != null && !working.contains(u.id) && isCurrentMember(u))
              u,
        ]..sort((a, b) {
          final r = rank(b).compareTo(rank(a));
          return r != 0 ? r : fullNameOf(a).compareTo(fullNameOf(b));
        });
    final timeOff = leader
        ? {
            for (final t
                in ref
                        .watch(storeApprovedTimeOffProvider(storeId))
                        .valueOrNull ??
                    const <({String userId, TimeOffRequest request})>[])
              if (t.request.startDate.compareTo(key) <= 0 &&
                  t.request.endDate.compareTo(key) >= 0)
                t.userId: t.request,
          }
        : const <String, TimeOffRequest>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MPill(
              '$people working',
              color: AppTheme.teal,
              large: true,
              icon: Icons.groups_2_outlined,
            ),
            if (onNowCount > 0)
              MPill(
                '$onNowCount on now',
                color: AppTheme.green,
                large: true,
                icon: Icons.circle,
              ),
            // Labor hours are for leaders.
            if (leader)
              MPill(
                '${formatHours(hours)} hrs',
                color: AppTheme.blue,
                large: true,
                icon: Icons.schedule,
              ),
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
                  onNow: onNow(e),
                ),
              ),
          ],
        if (offToday.isNotEmpty)
          _NotWorking(
            people: offToday,
            settings: settings,
            weekday: date.weekday,
            timeOff: timeOff,
            showDetails: leader,
            me: me,
          ),
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
    this.onNow = false,
  });

  final RosterEntry entry;
  final bool onNow;
  final UserModel? user;
  final Map<String, UserModel> users;
  final StoreSettingsModel? settings;
  final int lo;
  final int hi;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final color = entry.isAdmin
        ? AppTheme.purple
        : titleColor(user?.title, settings);
    final partner = entry.trainingWith ?? entry.traineeId;
    final span = math.max(1, hi - lo);
    return MCard(
      padding: EdgeInsets.zero,
      radius: 14,
      borderColor: isMe
          ? AppTheme.edge(MBrand.red).withValues(alpha: 0.6)
          : null,
      // The title's color as a hard edge on the left. (Not IntrinsicHeight:
      // the timeline below uses a LayoutBuilder, which can't be measured
      // that way.)
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
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
                  onNow ||
                  partner != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (entry.isAdmin)
                      MPill('Admin time', color: AppTheme.purple)
                    else if (user?.title != null)
                      MPill(
                        user!.title!,
                        color: titleColor(user!.title, settings),
                      ),
                    if (!entry.isAdmin &&
                        entry.area.isNotEmpty &&
                        entry.area != user?.title)
                      MPill(entry.area, color: AppTheme.blue),
                    if (onNow)
                      MPill(
                        'On now',
                        color: AppTheme.green,
                        icon: Icons.circle,
                      ),
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
    );
  }
}

/// Everyone on the team who isn't on the roster that day. Leaders also see
/// approved time off and when each person is available.
class _NotWorking extends StatefulWidget {
  const _NotWorking({
    required this.people,
    required this.settings,
    required this.weekday,
    required this.timeOff,
    required this.showDetails,
    required this.me,
  });

  final List<UserModel> people;
  final StoreSettingsModel? settings;
  final int weekday; // 1 = Monday
  final Map<String, TimeOffRequest> timeOff;
  final bool showDetails;
  final String? me;

  @override
  State<_NotWorking> createState() => _NotWorkingState();
}

class _NotWorkingState extends State<_NotWorking> {
  static const _preview = 6;
  bool _all = false;

  /// "Available 3p – 11p", "Not available", or null (nothing saved).
  (String, Color)? _availability(UserModel u) {
    final raw = u.activeAvailability;
    if (raw == null || raw.isEmpty) return null;
    final windows =
        parseAvailability(raw)[availabilityDays[widget.weekday - 1]] ??
        const [];
    if (windows.isEmpty) return ('Not available', AppTheme.red);
    final text = windows.map((w) => formatRange(w.start, w.end)).join(', ');
    return (text, AppTheme.green);
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final people = widget.people;
    final shown = _all || people.length <= _preview + 2
        ? people
        : people.take(_preview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MSection('Not working · ${people.length}'),
        MCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (final u in shown)
                Builder(
                  builder: (context) {
                    final off = widget.showDetails
                        ? widget.timeOff[u.id]
                        : null;
                    final avail = widget.showDetails && off == null
                        ? _availability(u)
                        : null;
                    final color = titleColor(u.title, widget.settings);
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        border: u == shown.last
                            ? null
                            : Border(
                                bottom: BorderSide(
                                  color: c.line.withValues(alpha: 0.5),
                                ),
                              ),
                      ),
                      child: Row(
                        children: [
                          MAvatar(
                            initials: initialsOf(u),
                            color: color,
                            size: 34,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  u.id == widget.me
                                      ? '${fullNameOf(u)} (you)'
                                      : fullNameOf(u),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: c.title,
                                  ),
                                ),
                                if (u.title != null)
                                  Text(
                                    u.title!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.onTint(color),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (off != null)
                            MPill(
                              off.isPartDay
                                  ? 'Off part of the day'
                                  : 'Time off',
                              color: AppTheme.purple,
                              icon: Icons.beach_access_outlined,
                            )
                          else if (avail case (final text, final tone))
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                text,
                                textAlign: TextAlign.right,
                                maxLines: 2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.onTint(tone),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              if (shown.length < people.length ||
                  _all && people.length > _preview + 2)
                InkWell(
                  onTap: () => setState(() => _all = !_all),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _all ? 'Show less' : 'Show all ${people.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: MBrand.red,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.showDetails)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Times on the right are when they\'re available that day.',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
      ],
    );
  }
}
