import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../services/schedule_repository.dart';
import '../views/team_roster_view.dart' show activeChecklistsFor;
import 'journey_card.dart';
import 'mobile_data.dart';
import 'mobile_shell.dart';
import 'mobile_ui.dart';
import 'promotion_page.dart';

/// Home: you on the gradient header (photo-style initials, name, title and
/// tags), your next shift and your week as tiles over it, shortcuts to
/// everything, then your journey and checklists. Leaders also get the store
/// today and "View as team member".
class MobileHomePage extends ConsumerWidget {
  const MobileHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final user = ref.watch(currentUserProvider) ?? const <String, dynamic>{};
    final access = ref.watch(mobileAccessProvider);
    final storeId = ref.watch(currentStoreIdProvider);
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final member = access.member;
    final now = DateTime.now();

    final firstName = member != null
        ? firstNameOf(member)
        : (user['first_name'] as String? ?? '').trim();
    final lastName = member != null
        ? (member.lastName ?? '').trim()
        : (user['last_name'] as String? ?? '').trim();
    final title =
        member?.title ??
        (access.isOwner
            ? 'Owner'
            : access.isBot
            ? 'Bot'
            : null);
    final color = member?.title != null
        ? titleColor(member!.title, settings)
        : MBrand.red;
    final tags = member?.additionalTags ?? const <String>[];
    final initials = member != null
        ? initialsOf(member)
        : [
            firstName,
            lastName,
          ].where((s) => s.isNotEmpty).map((s) => s[0].toUpperCase()).join();
    // Just came from the congratulations screen: play the title change.
    final swap = ref.watch(titleSwapProvider);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: MEyebrow(longDate(now))),
            const StoreChip(),
          ],
        ),
        const SizedBox(height: 22),
        GestureDetector(
          onTap: () => MobileTabs.go(context, MobileTab.settings),
          child: Row(
            children: [
              MAvatar(
                initials: initials.isEmpty ? '?' : initials,
                color: color,
                size: 68,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greetingFor(now),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      firstName.isEmpty ? 'Welcome' : firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 36,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (title != null || tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (swap != null && (swap.test || member?.title == swap.to))
                TitleSwapPill(
                  key: ValueKey('${swap.from}>${swap.to}>${swap.test}'),
                  from: swap.from,
                  to: swap.to,
                  fromColor: titleColor(swap.from, settings),
                  toColor: titleColor(swap.to, settings),
                  // A test: put the real title back afterwards.
                  onDone: swap.test
                      ? () => ref.read(titleSwapProvider.notifier).state = null
                      : null,
                )
              else if (title != null)
                MPill(title, color: color, large: true),
              for (final t in tags)
                MPill(t, color: tagColor(t, settings), large: true),
            ],
          ),
        ],
      ],
    );

    if (storeId == null) {
      return MPage(title: '', header: header, children: const []);
    }

    final config =
        ref.watch(scheduleConfigProvider(storeId)).valueOrNull ??
        const ScheduleConfig();
    final weekStart = weekStartFor(now, config.weekStart);
    final boards = boardsKey(config);
    final canViewAsTeam =
        !ref.watch(teamMemberViewProvider) &&
        (access.isOwner || (access.leadership && !access.isBot));

    final viewAsCard = MCard(
      onTap: () {
        setTeamMemberView(ref, true);
        MobileTabs.go(context, MobileTab.home);
      },
      child: Row(
        children: [
          const MIconBadge(Icons.visibility_outlined, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'View as team member',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: c.title,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'See the app exactly as your team does. Turn it off in Settings.',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.arrow_forward_rounded, color: c.muted),
        ],
      ),
    );

    return MPage(
      title: '',
      header: header,
      compactTitle: firstName.isEmpty ? 'Home' : firstName,
      compactLeading: MAvatar(
        initials: initials.isEmpty ? '?' : initials,
        color: color,
        size: 32,
      ),
      onRefresh: () async {
        ref.invalidate(allStoreUsersStreamProvider);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
      children: [
        if (access.mySchedule)
          _MyWeek(
            storeId: storeId,
            member: member!,
            weekStart: weekStart,
            boards: boards,
          )
        else if (canViewAsTeam)
          viewAsCard,
        MBand(
          title: 'Shortcuts',
          child: _Shortcuts(access: access),
        ),
        if (access.leadership)
          _StoreToday(storeId: storeId, config: config, weekStart: weekStart)
        else if (!access.mySchedule)
          _WorkingToday(storeId: storeId, weekStart: weekStart, boards: boards),
        if (canViewAsTeam && access.mySchedule) ...[
          const SizedBox(height: 14),
          viewAsCard,
        ],
        if (member?.title != null)
          MyJourneySection(storeId: storeId, title: member!.title),
        if (member != null) ...[
          _ChecklistCard(member: member),
          _PermitCard(member: member),
        ],
      ],
    );
  }
}

// =============================================================================
// Shortcuts: everything you can open, as tiles
// =============================================================================

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.access});
  final MobileAccess access;

  @override
  Widget build(BuildContext context) {
    void schedule(WidgetRef ref, int section) {
      ref.read(scheduleSectionRequestProvider.notifier).state = section;
      MobileTabs.go(context, MobileTab.schedule);
    }

    return Consumer(
      builder: (context, ref, _) {
        final tiles = <Widget>[
          if (access.mySchedule) ...[
            _ShortcutTile(
              icon: Icons.calendar_month_rounded,
              label: 'Schedule',
              caption: 'Your shifts',
              onTap: () => schedule(ref, 0),
            ),
            _ShortcutTile(
              icon: Icons.event_available_rounded,
              label: 'Availability',
              caption: 'When you\'re free',
              onTap: () => schedule(ref, 1),
            ),
            _ShortcutTile(
              icon: Icons.flight_takeoff_rounded,
              label: 'Time off',
              caption: 'Ask for days off',
              onTap: () => schedule(ref, 2),
            ),
          ],
          _ShortcutTile(
            icon: Icons.groups_2_rounded,
            label: 'Who\'s on',
            caption: 'Today\'s roster',
            onTap: () => MobileTabs.go(context, MobileTab.roster),
          ),
          if (access.team)
            _ShortcutTile(
              icon: Icons.people_alt_rounded,
              label: 'Team',
              caption: 'Everyone',
              onTap: () => MobileTabs.go(context, MobileTab.team),
            ),
          if (access.seeShiftBoard)
            _ShortcutTile(
              icon: Icons.dashboard_customize_rounded,
              label: 'Shift board',
              caption: 'Positions today',
              onTap: () => context.go('${MobileTab.roster.path}/shift'),
            ),
          _ShortcutTile(
            icon: Icons.person_rounded,
            label: 'Profile',
            caption: 'You and settings',
            onTap: () => MobileTabs.go(context, MobileTab.settings),
          ),
        ];
        return LayoutBuilder(
          builder: (context, box) {
            const gap = 10.0;
            final perRow = box.maxWidth >= 520 ? 4 : 3;
            final w = (box.maxWidth - gap * (perRow - 1)) / perRow;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final t in tiles) SizedBox(width: w, child: t)],
            );
          },
        );
      },
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return MCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MIconBadge(icon, size: 34),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: c.title,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: c.muted),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Your week: next shift, the days of the week, hours and time off
// =============================================================================

class _MyWeek extends ConsumerWidget {
  const _MyWeek({
    required this.storeId,
    required this.member,
    required this.weekStart,
    required this.boards,
  });

  final String storeId;
  final UserModel member;
  final DateTime weekStart;
  final String boards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final id = member.id ?? '';
    // Viewing as a team member: the sample schedule.
    final preview = ref.watch(schedulePreviewProvider);
    final thisWeek = preview != null
        ? AsyncValue.data(preview.shiftsFor(weekStart))
        : ref.watch(
            postedWeekProvider((
              storeId: storeId,
              weekStart: dateKey(weekStart),
              boards: boards,
            )),
          );
    final nextWeek = preview != null
        ? AsyncValue.data(preview.shiftsFor(addDays(weekStart, 7)))
        : ref.watch(
            postedWeekProvider((
              storeId: storeId,
              weekStart: dateKey(addDays(weekStart, 7)),
              boards: boards,
            )),
          );
    final timeOff = preview != null
        ? preview.timeOff
        : ref
                  .watch(
                    memberTimeOffProvider((storeId: storeId, memberId: id)),
                  )
                  .valueOrNull ??
              const <TimeOffRequest>[];
    final users = {
      for (final u
          in ref.watch(allStoreUsersStreamProvider).valueOrNull ??
              const <UserModel>[])
        if (u.id != null) u.id!: u,
    };

    final mine =
        [
          ...?thisWeek.valueOrNull,
          ...?nextWeek.valueOrNull,
        ].where((e) => e.userId == id).toList()..sort((a, b) {
          final d = a.date.compareTo(b.date);
          return d != 0 ? d : a.start.compareTo(b.start);
        });

    final now = DateTime.now();
    final nowMinute = now.hour * 60 + now.minute;
    final todayKey = dateKey(now);
    final upcoming = mine.where((e) {
      final cmp = e.date.compareTo(todayKey);
      if (cmp > 0) return true;
      if (cmp < 0) return false;
      return e.end > nowMinute;
    }).toList();
    final next = upcoming.firstOrNull;
    final weekEntries = (thisWeek.valueOrNull ?? const <RosterEntry>[])
        .where((e) => e.userId == id)
        .toList();
    final weekHours = weekEntries.fold<double>(0, (a, e) => a + e.hours);
    final weekDays = {for (final e in weekEntries) e.date}.length;
    final pending = timeOff.where((r) => r.isPending).length;
    final loading = thisWeek.isLoading && !thisWeek.hasValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading)
          const MCard(
            child: SizedBox(
              height: 110,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else if (next == null)
          MCard(
            child: Row(
              children: [
                const MIconBadge(Icons.event_available_rounded, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your next shift',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Nothing posted yet',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: c.title,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          _NextShiftCard(entry: next, users: users),
        const SizedBox(height: 12),
        _WeekStrip(weekStart: weekStart, entries: weekEntries),
        const SizedBox(height: 12),
        MStatGrid(
          children: [
            MStat(
              label: 'This week',
              value: '${formatHours(weekHours)} hrs',
              caption: weekDays == 0
                  ? 'No shifts posted'
                  : '$weekDays ${weekDays == 1 ? 'shift' : 'shifts'} · ${weekRange(weekStart)}',
              icon: Icons.schedule_rounded,
              onTap: () {
                ref.read(scheduleSectionRequestProvider.notifier).state = 0;
                MobileTabs.go(context, MobileTab.schedule);
              },
            ),
            MStat(
              label: 'Time off',
              value: pending == 0 ? 'None' : '$pending',
              caption: pending == 0
                  ? 'No requests waiting'
                  : '${pending == 1 ? 'Request' : 'Requests'} waiting',
              icon: Icons.flight_takeoff_rounded,
              color: pending == 0 ? null : AppTheme.yellow,
              onTap: () {
                ref.read(scheduleSectionRequestProvider.notifier).state = 2;
                MobileTabs.go(context, MobileTab.schedule);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// This week day by day: the start of each shift, today ringed.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.weekStart, required this.entries});
  final DateTime weekStart;
  final List<RosterEntry> entries;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final today = dateKey(DateTime.now());
    return MCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final d = addDays(weekStart, i);
                  final key = dateKey(d);
                  final shifts =
                      entries.where((e) => e.date == key && !e.isAdmin).toList()
                        ..sort((a, b) => a.start.compareTo(b.start));
                  final working = shifts.isNotEmpty;
                  final isToday = key == today;
                  // Working days on a lighter gray, today solid inverse.
                  final fg = isToday ? c.onInverse : c.title;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isToday
                          ? c.inverse
                          : (working ? c.raised : Colors.transparent),
                      borderRadius: BorderRadius.circular(12),
                      border: working || isToday
                          ? null
                          : Border.all(color: c.line),
                    ),
                    child: Column(
                      children: [
                        Text(
                          weekdayShort[d.weekday - 1].substring(0, 1),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isToday
                                ? c.onInverse.withValues(alpha: 0.65)
                                : c.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: working || isToday ? fg : c.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            working
                                ? formatMinutes(
                                    shifts.first.start,
                                    compact: true,
                                  )
                                : 'Off',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: working
                                  ? MBrand.red
                                  : (isToday
                                        ? c.onInverse.withValues(alpha: 0.65)
                                        : c.muted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _NextShiftCard extends StatelessWidget {
  const _NextShiftCard({required this.entry, required this.users});
  final RosterEntry entry;
  final Map<String, UserModel> users;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final day = parseDateKey(entry.date) ?? DateTime.now();
    final now = DateTime.now();
    final isToday = dateKey(now) == entry.date;
    final nowMinute = now.hour * 60 + now.minute;
    final onNow = isToday && entry.start <= nowMinute && entry.end > nowMinute;
    final startsIn = isToday && !onNow ? entry.start - nowMinute : null;
    final partner = entry.trainingWith ?? entry.traineeId;

    String? lead;
    if (onNow) {
      lead = 'On now';
    } else if (startsIn != null && startsIn <= 12 * 60) {
      final h = startsIn ~/ 60;
      final m = startsIn % 60;
      lead = 'Starts in ${h > 0 ? '${h}h ' : ''}${m}m';
    }

    // A hard red edge marks the one thing to look at first.
    return MCard(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: MBrand.red, width: 5)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MEyebrow('Next shift · ${relativeDay(day)}', color: c.muted),
                const Spacer(),
                if (lead != null)
                  MPill(
                    lead,
                    color: onNow ? AppTheme.green : MBrand.red,
                    icon: onNow ? Icons.circle : Icons.timer_outlined,
                    filled: true,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              formatRange(entry.start, entry.end, compact: false),
              style: TextStyle(
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                color: c.title,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${formatHours(entry.hours)} hrs',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
                if (entry.area.isNotEmpty)
                  MPill(entry.area, color: AppTheme.blue),
                if (entry.isAdmin)
                  MPill(
                    'Admin time',
                    color: AppTheme.purple,
                    icon: Icons.assignment_outlined,
                  ),
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
        ),
      ),
    );
  }
}

// =============================================================================
// Leaders: the store today
// =============================================================================

class _StoreToday extends ConsumerWidget {
  const _StoreToday({
    required this.storeId,
    required this.config,
    required this.weekStart,
  });

  final String storeId;
  final ScheduleConfig config;
  final DateTime weekStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateKey(DateTime.now());
    final people = <String>{};
    var labor = 0.0;
    var open = 0.0;
    var anyDay = false;
    for (final b in config.allBoards) {
      final week = ref
          .watch(
            scheduleWeekProvider((
              storeId: storeId,
              weekStart: dateKey(weekStart),
              boardId: b.id,
            )),
          )
          .valueOrNull;
      final day = week?[today];
      if (day == null) continue;
      anyDay = anyDay || day.shifts.isNotEmpty;
      for (final s in day.shifts) {
        people.add(s.userId);
        if (s.isTraining) people.add(s.traineeId!);
      }
      labor += day.laborHours;
      open += day.openHours;
    }
    final team = ref.watch(currentMembersProvider).valueOrNull?.length;
    final hires = ref.watch(newHiresNeededProvider);
    final pending = ref.watch(storePendingTimeOffProvider(storeId)).valueOrNull;
    final scheduleOn = ref.watch(mobileAccessProvider).scheduleOn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MSection('The store today'),
        MStatGrid(
          children: [
            if (scheduleOn) ...[
              MStat(
                label: 'Working today',
                value: '${people.length}',
                caption: anyDay
                    ? '${formatHours(labor)} labor hrs'
                    : 'Nothing scheduled',
                icon: Icons.groups_2_outlined,
                onTap: () => MobileTabs.go(context, MobileTab.roster),
              ),
              MStat(
                label: 'Open hours',
                value: formatHours(open),
                caption: open == 0 ? 'Fully covered' : 'Still to fill today',
                icon: Icons.warning_amber_rounded,
                color: open == 0 ? AppTheme.green : AppTheme.orange,
                onTap: () => MobileTabs.go(context, MobileTab.roster),
              ),
            ],
            MStat(
              label: 'Team',
              value: team == null ? '–' : '$team',
              caption: 'Active team members',
              icon: Icons.people_outline,
              onTap: () => MobileTabs.go(context, MobileTab.team),
            ),
            MStat(
              label: 'Hires needed',
              value: '$hires',
              caption: hires == 0
                  ? 'Roster is covered'
                  : 'From your roster needs',
              icon: Icons.person_add_alt,
              color: hires == 0 ? AppTheme.green : AppTheme.red,
            ),
            if (pending != null)
              MStat(
                label: 'Time off waiting',
                value: '$pending',
                caption: pending == 0
                    ? 'All answered'
                    : 'Answer on the desktop app',
                icon: Icons.flight_takeoff,
                color: pending == 0 ? null : AppTheme.yellow,
              ),
          ],
        ),
      ],
    );
  }
}

/// Team members who aren't on the schedule (and aren't leaders): how many
/// are working today, from the posted schedule.
class _WorkingToday extends ConsumerWidget {
  const _WorkingToday({
    required this.storeId,
    required this.weekStart,
    required this.boards,
  });

  final String storeId;
  final DateTime weekStart;
  final String boards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateKey(DateTime.now());
    final entries =
        ref
            .watch(
              postedWeekProvider((
                storeId: storeId,
                weekStart: dateKey(weekStart),
                boards: boards,
              )),
            )
            .valueOrNull ??
        const <RosterEntry>[];
    final people = {
      for (final e in entries)
        if (e.date == today && !e.isAdmin) e.userId,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MSection('Today'),
        MStat(
          label: 'Working today',
          value: '${people.length}',
          caption: 'See who\'s on in Roster',
          icon: Icons.groups_2_outlined,
          onTap: () => MobileTabs.go(context, MobileTab.roster),
        ),
      ],
    );
  }
}

// =============================================================================
// Checklist progress and permit reminders
// =============================================================================

class _ChecklistCard extends ConsumerWidget {
  const _ChecklistCard({required this.member});
  final UserModel member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final active = activeChecklistsFor(member, settings);
    if (active.isEmpty) return const SizedBox.shrink();
    final done = {
      for (final t in member.completedTasks ?? const <String>[]) t.trim(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MSection('Your checklists'),
        for (final cl in active)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(
              builder: (context) {
                final color = AppTheme.getColorFromName(cl.color) == Colors.grey
                    ? AppTheme.teal
                    : AppTheme.getColorFromName(cl.color);
                final applicable = cl.tasksForPosition(member.position);
                final count = applicable
                    .where((i) => done.contains(i.text.trim()))
                    .length;
                final total = applicable.length;
                return MCard(
                  onTap: () => showChecklistSheet(
                    context,
                    cl.name,
                    applicable.map((t) => t.text).toList(),
                    done,
                    color,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_box_outlined,
                            size: 20,
                            color: color,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cl.name,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: c.title,
                              ),
                            ),
                          ),
                          Text(
                            '$count / $total',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onTint(color),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      MProgress(
                        value: total == 0 ? 0 : count / total,
                        color: color,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet listing a checklist's items (done ones checked).
void showChecklistSheet(
  BuildContext context,
  String name,
  List<String> items,
  Set<String> done,
  Color color,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).cardColor,
    builder: (ctx) {
      final c = MColors(ctx);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: c.title,
              ),
            ),
            const SizedBox(height: 14),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      done.contains(item.trim())
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: done.contains(item.trim()) ? color : c.muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: done.contains(item.trim()) ? c.muted : c.text,
                          decoration: done.contains(item.trim())
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _PermitCard extends StatelessWidget {
  const _PermitCard({required this.member});
  final UserModel member;

  @override
  Widget build(BuildContext context) {
    final status = permitStatus(member.foodHandlersExpiration);
    if (status.ok) return const SizedBox.shrink();
    final c = MColors(context);
    final exp = member.foodHandlersExpiration;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: MCard(
        borderColor: AppTheme.edge(status.color).withValues(alpha: 0.6),
        color: Color.alphaBlend(AppTheme.tint(status.color), c.card),
        onTap: () => MobileTabs.go(context, MobileTab.settings),
        child: Row(
          children: [
            Icon(Icons.badge_outlined, color: AppTheme.onTint(status.color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Food handler\'s permit',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: c.title,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    exp == null
                        ? 'We don\'t have one on file for you.'
                        : '${status.label} · ${mediumDate(exp)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.onTint(status.color),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.muted),
          ],
        ),
      ),
    );
  }
}
