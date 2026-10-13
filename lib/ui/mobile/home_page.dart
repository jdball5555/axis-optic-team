import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../services/schedule_repository.dart';
import '../views/team_roster_view.dart' show activeChecklistsFor;
import 'mobile_data.dart';
import 'mobile_shell.dart';
import 'mobile_ui.dart';

/// Home: a welcome, your title and tags, your next shift and the numbers
/// that matter to you.
class MobileHomePage extends ConsumerWidget {
  const MobileHomePage({super.key});

  static const _quotes = [
    '"A leader is one who knows the way, goes the way, and shows the way." - John C. Maxwell',
    '"The function of leadership is to produce more leaders, not more followers." - Ralph Nader',
    '"Businesses don\'t succeed or fail, people do." - Truett Cathy',
    '"To win in the marketplace you must first win in the workplace." - Doug Conant',
    '"Your company\'s culture is simply a combination of the behaviors you reward and the behaviors you tolerate." - Dave Ramsey',
    '"Leaders are readers. If you want to lead, you must read." - Dave Ramsey',
  ];

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
    final title =
        member?.title ??
        (access.isOwner
            ? 'Owner'
            : access.isBot
            ? 'Bot'
            : null);
    final color = member?.title != null
        ? titleColor(member!.title, settings)
        : AppTheme.accent;
    final tags = member?.additionalTags ?? const <String>[];

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: MEyebrow(longDate(now))),
            const StoreChip(),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          '${greetingFor(now)},',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          firstName.isEmpty ? 'Welcome' : firstName,
          style: TextStyle(
            fontSize: 40,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: c.title,
          ),
        ),
        if (title != null || tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (title != null) MPill(title, color: color, large: true),
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

    return MPage(
      title: '',
      header: header,
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
          ),
        if (access.leadership)
          _StoreToday(storeId: storeId, config: config, weekStart: weekStart)
        else if (!access.mySchedule)
          _WorkingToday(storeId: storeId, weekStart: weekStart, boards: boards),
        if (member != null) ...[
          _ChecklistCard(member: member),
          _PermitCard(member: member),
        ],
        const SizedBox(height: 26),
        MCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.format_quote_rounded, color: AppTheme.accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _quotes[(now.difference(DateTime(now.year)).inDays) %
                      _quotes.length],
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    color: c.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Your week: next shift + this week's numbers
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
    final thisWeek = ref.watch(
      postedWeekProvider((
        storeId: storeId,
        weekStart: dateKey(weekStart),
        boards: boards,
      )),
    );
    final nextWeek = ref.watch(
      postedWeekProvider((
        storeId: storeId,
        weekStart: dateKey(addDays(weekStart, 7)),
        boards: boards,
      )),
    );
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

    final mine = [
      ...?thisWeek.valueOrNull,
      ...?nextWeek.valueOrNull,
    ].where((e) => e.userId == id).toList()
      ..sort((a, b) {
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
        const MSection('Your next shift', top: 4),
        if (loading)
          const MCard(
            child: SizedBox(
              height: 96,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else if (next == null)
          MCard(
            child: Row(
              children: [
                Icon(Icons.event_available_outlined, color: c.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No upcoming shifts posted yet.',
                    style: TextStyle(fontSize: 15, color: c.text),
                  ),
                ),
              ],
            ),
          )
        else
          _NextShiftCard(entry: next, users: users),
        const SizedBox(height: 12),
        MStatGrid(
          children: [
            MStat(
              label: 'This week',
              value: '${formatHours(weekHours)} hrs',
              caption: weekDays == 0
                  ? 'No shifts posted'
                  : '$weekDays ${weekDays == 1 ? 'shift' : 'shifts'} · ${weekRange(weekStart)}',
              icon: Icons.schedule,
              onTap: () => MobileTabs.go(context, MobileTab.schedule),
            ),
            MStat(
              label: 'Time off',
              value: pending == 0 ? 'None' : '$pending',
              caption: pending == 0
                  ? 'No requests waiting'
                  : '${pending == 1 ? 'Request' : 'Requests'} waiting',
              icon: Icons.flight_takeoff,
              color: pending == 0 ? null : AppTheme.yellow,
              onTap: () => MobileTabs.go(context, MobileTab.schedule),
            ),
          ],
        ),
      ],
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

    return MCard(
      glow: AppTheme.accent,
      borderColor: AppTheme.edge(AppTheme.accent).withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MEyebrow(relativeDay(day), color: AppTheme.onTint(AppTheme.accent)),
              const Spacer(),
              if (lead != null)
                MPill(
                  lead,
                  color: onNow ? AppTheme.green : AppTheme.accent,
                  icon: onNow ? Icons.circle : Icons.timer_outlined,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatRange(entry.start, entry.end, compact: false),
            style: TextStyle(
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: c.title,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${formatHours(entry.hours)} hrs',
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
              if (entry.area.isNotEmpty) MPill(entry.area, color: AppTheme.blue),
              if (entry.isAdmin)
                MPill('Admin time', color: AppTheme.purple, icon: Icons.assignment_outlined),
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
                caption: anyDay ? '${formatHours(labor)} labor hrs' : 'Nothing scheduled',
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
              caption: hires == 0 ? 'Roster is covered' : 'From your roster needs',
              icon: Icons.person_add_alt,
              color: hires == 0 ? AppTheme.green : AppTheme.red,
            ),
            if (pending != null)
              MStat(
                label: 'Time off waiting',
                value: '$pending',
                caption: pending == 0 ? 'All answered' : 'Answer on the desktop app',
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
    final done = {for (final t in member.completedTasks ?? const <String>[]) t.trim()};
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
                final count = cl.items.where((i) => done.contains(i.trim())).length;
                return MCard(
                  onTap: () => showChecklistSheet(context, cl.name, cl.items, done, color),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_box_outlined, size: 20, color: color),
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
                            '$count / ${cl.items.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.onTint(color),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      MProgress(
                        value: cl.items.isEmpty ? 0 : count / cl.items.length,
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
                    style: TextStyle(fontSize: 13, color: AppTheme.onTint(status.color)),
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
