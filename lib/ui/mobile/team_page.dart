import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/store_settings_model.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../services/schedule_repository.dart';
import '../views/team_roster_view.dart' show activeChecklistsFor;
import 'home_page.dart' show showChecklistSheet;
import 'mobile_data.dart';
import 'mobile_ui.dart';

/// Team: search and scroll the team, tap someone for everything on file.
class TeamMobilePage extends ConsumerStatefulWidget {
  const TeamMobilePage({super.key});

  @override
  ConsumerState<TeamMobilePage> createState() => _TeamMobilePageState();
}

class _TeamMobilePageState extends ConsumerState<TeamMobilePage> {
  final _search = TextEditingController();
  String _query = '';
  String? _title; // null = everyone

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(UserModel u) {
    if (_title != null && u.title != _title) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      u.firstName,
      u.lastName,
      u.preferredName,
      u.title,
      u.position,
      u.designation,
      u.workingTime,
      u.email,
      ...?u.additionalTags,
    ].whereType<String>().join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final access = ref.watch(mobileAccessProvider);
    if (!access.team) {
      return const MPage(
        title: 'Team',
        children: [
          MEmpty(
            icon: Icons.lock_outline,
            title: 'No access',
            message: 'Ask a leader for access to team members.',
          ),
        ],
      );
    }
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final async = ref.watch(currentMembersProvider);
    final all = [...?async.valueOrNull]
      ..sort(
        (a, b) =>
            fullNameOf(a).toLowerCase().compareTo(fullNameOf(b).toLowerCase()),
      );
    final titles = [
      for (final t in settings?.titles ?? const <TitleConfig>[])
        if (all.any((u) => u.title == t.name)) t.name,
    ];
    final shown = all.where(_matches).toList();

    return MPage(
      title: 'Team',
      subtitle: async.hasValue
          ? '${all.length} active team ${all.length == 1 ? 'member' : 'members'}'
          : null,
      children: [
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search names, titles, positions…',
            prefixIcon: Icon(Icons.search, color: c.muted),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close, color: c.muted),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
            filled: true,
            fillColor: c.card,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: c.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: c.line.withValues(alpha: 0.8)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: MBrand.red, width: 1.5),
            ),
          ),
        ),
        if (titles.length > 1) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: 'Everyone',
                  color: MBrand.red,
                  selected: _title == null,
                  onTap: () => setState(() => _title = null),
                ),
                for (final t in titles)
                  _FilterChip(
                    label: t,
                    color: titleColor(t, settings),
                    selected: _title == t,
                    onTap: () =>
                        setState(() => _title = _title == t ? null : t),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (async.isLoading && !async.hasValue)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (shown.isEmpty)
          const MEmpty(
            icon: Icons.person_search_outlined,
            title: 'No one found',
            message: 'Try a different name or filter.',
            compact: true,
          )
        else
          for (final u in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MemberTile(user: u, settings: settings),
            ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
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
            color: selected ? AppTheme.tint(color) : c.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppTheme.edge(color)
                  : c.line.withValues(alpha: 0.8),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppTheme.onTint(color) : c.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.user, required this.settings});
  final UserModel user;
  final StoreSettingsModel? settings;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final color = titleColor(user.title, settings);
    final checklist = activeChecklistsFor(user, settings).firstOrNull;
    final done = {
      for (final t in user.completedTasks ?? const <String>[]) t.trim(),
    };
    final permit = permitStatus(user.foodHandlersExpiration);
    final details = [
      user.position,
      user.workingTime,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return MCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: user.id == null ? null : () => context.push('/m/team/${user.id}'),
      child: Row(
        children: [
          MAvatar(initials: initialsOf(user), color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullNameOf(user),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: c.title,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (user.title != null) MPill(user.title!, color: color),
                    if (checklist != null)
                      MPill(
                        '${checklist.name} ${cl(checklist, done, user.position)}/${checklist.tasksForPosition(user.position).length}',
                        color:
                            AppTheme.getColorFromName(checklist.color) ==
                                Colors.grey
                            ? AppTheme.teal
                            : AppTheme.getColorFromName(checklist.color),
                      ),
                    if (!permit.ok)
                      MPill(
                        user.foodHandlersExpiration == null
                            ? 'No permit'
                            : permit.label,
                        color: permit.color,
                      ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: c.muted),
        ],
      ),
    );
  }

  static int cl(ChecklistConfig checklist, Set<String> done, [String? position]) {
    final tasks = checklist.tasksForPosition(position);
    return tasks.where((i) => done.contains(i.text.trim())).length;
  }
}

// =============================================================================
// One team member
// =============================================================================

class MemberMobilePage extends ConsumerWidget {
  const MemberMobilePage({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final access = ref.watch(mobileAccessProvider);
    if (!access.team) {
      return const MSubPage(
        title: 'Team member',
        child: MEmpty(icon: Icons.lock_outline, title: 'No access'),
      );
    }
    final async = ref.watch(userStreamProvider(userId));
    final user = async.valueOrNull;
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    if (user == null) {
      return MSubPage(
        title: 'Team member',
        child: async.isLoading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : const MEmpty(icon: Icons.person_off_outlined, title: 'Not found'),
      );
    }

    final color = titleColor(user.title, settings);
    final storeName = (user.store ?? '').isEmpty
        ? null
        : ref.watch(storeStreamProvider(user.store!)).valueOrNull?['name']
              as String?;
    final status = memberStatus(user);
    final food = permitStatus(user.foodHandlersExpiration);
    final needsMgr =
        settings?.titles
            .where((t) => t.name == user.title)
            .firstOrNull
            ?.mgrPermit ??
        false;
    final mgr = permitStatus(user.managerPermitExpiration);
    final storeId = ref.watch(currentStoreIdProvider);

    return MSubPage(
      title: firstNameOf(user),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          // Header.
          Center(
            child: MAvatar(initials: initialsOf(user), color: color, size: 84),
          ),
          const SizedBox(height: 14),
          Text(
            fullNameOf(user),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: c.title,
            ),
          ),
          if (user.startDate != null) ...[
            const SizedBox(height: 4),
            Text(
              'Since ${mediumDate(user.startDate!)} · ${tenureSince(user.startDate!)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.muted),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (user.title != null)
                MPill(user.title!, color: color, large: true),
              for (final t in user.additionalTags ?? const <String>[])
                MPill(t, color: tagColor(t, settings), large: true),
              MPill(
                status,
                large: true,
                color: switch (status) {
                  'Active' => AppTheme.green,
                  'Leaving' => AppTheme.orange,
                  _ => Colors.grey,
                },
              ),
              if (user.foodHandlersExpiration == null)
                MPill(
                  'No food permit',
                  color: AppTheme.red,
                  large: true,
                  filled: true,
                ),
            ],
          ),
          if ((user.email ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MButton(
                    label: 'Email',
                    icon: Icons.mail_outline,
                    secondary: true,
                    onPressed: () =>
                        launchUrl(Uri.parse('mailto:${user.email}')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MButton(
                    label: 'Copy email',
                    icon: Icons.copy_rounded,
                    secondary: true,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: user.email!));
                      mSnack(context, 'Email copied.');
                    },
                  ),
                ),
              ],
            ),
          ],

          // Checklists.
          ..._checklists(context, user, settings),

          // This week.
          if (storeId != null) _MemberWeek(storeId: storeId, userId: userId),

          // Details.
          const MSection('Details'),
          MCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(
              children: [
                MField('First name', user.firstName),
                if ((user.preferredName ?? '').isNotEmpty)
                  MField('Preferred name', user.preferredName),
                MField('Last name', user.lastName),
                MField('Email', user.email),
                MField('Title', user.title),
                MField('Position', user.position),
                MField('Designation', user.designation),
                MField('Working time', user.workingTime),
                MField('Avg shifts / wk', user.avgShifts),
                MField(
                  'Pay',
                  user.payRate == null ? null : '\$${_money(user.payRate!)}',
                ),
                MField('Store', storeName ?? user.store),
                MField(
                  'Start date',
                  user.startDate == null ? null : mediumDate(user.startDate!),
                ),
                MField(
                  'End date',
                  user.endDate == null ? null : mediumDate(user.endDate!),
                  last: true,
                ),
              ],
            ),
          ),

          // Permits.
          const MSection('Permits'),
          MCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(
              children: [
                _PermitLine(
                  label: 'Food handler\'s',
                  expires: user.foodHandlersExpiration,
                  status: food,
                  last: !(needsMgr || user.managerPermitExpiration != null),
                ),
                if (needsMgr || user.managerPermitExpiration != null)
                  _PermitLine(
                    label: 'Manager',
                    expires: user.managerPermitExpiration,
                    status: mgr,
                    last: true,
                  ),
              ],
            ),
          ),

          // Availability and time off.
          const MSection('Availability'),
          _AvailabilityCard(data: user.activeAvailability),
          if (storeId != null) _MemberTimeOff(storeId: storeId, userId: userId),

          // Notes.
          if ((user.generalNotes ?? '').trim().isNotEmpty ||
              (user.hiringNotes ?? '').trim().isNotEmpty) ...[
            const MSection('Notes'),
            if ((user.generalNotes ?? '').trim().isNotEmpty)
              _NoteCard(title: 'General notes', text: user.generalNotes!),
            if ((user.hiringNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _NoteCard(title: 'Hiring notes', text: user.hiringNotes!),
            ],
          ],

          // History.
          if ((user.historyLogs ?? const []).isNotEmpty) ...[
            const MSection('History'),
            MCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final log in user.historyLogs!.reversed.take(12))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: AppTheme.blue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${log['event'] ?? 'Event'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: c.text,
                                  ),
                                ),
                                if ((log['date'] ?? log['timestamp']) != null)
                                  Text(
                                    _historyDate(
                                      log['date'] ?? log['timestamp'],
                                    ),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: c.muted,
                                    ),
                                  ),
                              ],
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
    );
  }
}

List<Widget> _checklists(
  BuildContext context,
  UserModel user,
  StoreSettingsModel? settings,
) {
  final c = MColors(context);
  final active = activeChecklistsFor(user, settings);
  if (active.isEmpty) return const <Widget>[];
  final done = {
    for (final t in user.completedTasks ?? const <String>[]) t.trim(),
  };
  return [
    const MSection('Checklists'),
    for (final cl in active)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Builder(
          builder: (context) {
            final col = AppTheme.getColorFromName(cl.color) == Colors.grey
                ? AppTheme.teal
                : AppTheme.getColorFromName(cl.color);
            final applicable = cl.tasksForPosition(user.position);
            final n = applicable.where((i) => done.contains(i.text.trim())).length;
            final total = applicable.length;
            return MCard(
              onTap: () => showChecklistSheet(
                context,
                cl.name,
                applicable.map((t) => t.text).toList(),
                done,
                col,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_box_outlined, size: 20, color: col),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cl.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: c.title,
                          ),
                        ),
                      ),
                      Text(
                        '$n / $total',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onTint(col),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  MProgress(
                    value: total == 0 ? 0 : n / total,
                    color: col,
                  ),
                ],
              ),
            );
          },
        ),
      ),
  ];
}

String _money(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

String _historyDate(dynamic v) {
  final s = v.toString();
  final d = DateTime.tryParse(s);
  return d == null ? s : mediumDate(d);
}

class _PermitLine extends StatelessWidget {
  const _PermitLine({
    required this.label,
    required this.expires,
    required this.status,
    this.last = false,
  });

  final String label;
  final DateTime? expires;
  final ({String label, Color color, bool ok}) status;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return MField(
      label,
      null,
      last: last,
      valueWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (expires != null)
            Text(
              mediumDate(expires!),
              style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
            ),
          const SizedBox(height: 4),
          MPill(status.label, color: status.color),
        ],
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.data});
  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    if (data == null || data!.isEmpty) {
      return MCard(
        child: Text(
          'No availability on file.',
          style: TextStyle(color: c.muted),
        ),
      );
    }
    final byDay = parseAvailability(data);
    return MCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < 7; i++)
            MField(
              weekdayNames[i],
              null,
              last: i == 6,
              valueWidget: Text(
                (byDay[availabilityDays[i]] ?? const []).isEmpty
                    ? 'Unavailable'
                    : byDay[availabilityDays[i]]!
                          .map(
                            (w) => w.start % 1440 == 0 && w.minutes >= 1440
                                ? 'All day'
                                : formatRange(w.start, w.end),
                          )
                          .join(', '),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: (byDay[availabilityDays[i]] ?? const []).isEmpty
                      ? c.muted
                      : c.text,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(fontSize: 14.5, height: 1.45, color: c.text),
          ),
        ],
      ),
    );
  }
}

/// The member's shifts this week (the working schedule for leaders who can
/// see it, otherwise what's posted).
class _MemberWeek extends ConsumerWidget {
  const _MemberWeek({required this.storeId, required this.userId});
  final String storeId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final access = ref.watch(mobileAccessProvider);
    final config =
        ref.watch(scheduleConfigProvider(storeId)).valueOrNull ??
        const ScheduleConfig();
    if (!access.scheduleOn) return const SizedBox.shrink();
    final weekStart = weekStartFor(DateTime.now(), config.weekStart);
    final entries = <RosterEntry>[];
    if (access.draftSchedules) {
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
        for (final day in week?.values ?? const <ScheduleDay>[]) {
          entries.addAll(
            entriesFromDay(day, b.id).where((e) => e.userId == userId),
          );
        }
      }
    } else {
      entries.addAll(
        (ref
                    .watch(
                      postedWeekProvider((
                        storeId: storeId,
                        weekStart: dateKey(weekStart),
                        boards: boardsKey(config),
                      )),
                    )
                    .valueOrNull ??
                const <RosterEntry>[])
            .where((e) => e.userId == userId),
      );
    }
    entries.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.start.compareTo(b.start);
    });
    final hours = entries.fold<double>(0, (a, e) => a + e.hours);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MSection(
          'This week',
          action: Text(
            '${formatHours(hours)} hrs',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c.muted,
            ),
          ),
        ),
        MCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Not on the schedule this week.',
                    style: TextStyle(color: c.muted),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      MField(
                        relativeDay(
                          parseDateKey(entries[i].date) ?? DateTime.now(),
                        ),
                        '${formatRange(entries[i].start, entries[i].end)}'
                        '${entries[i].isAdmin ? ' · Admin' : ''}',
                        last: i == entries.length - 1,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MemberTimeOff extends ConsumerWidget {
  const _MemberTimeOff({required this.storeId, required this.userId});
  final String storeId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final list =
        ref
            .watch(memberTimeOffProvider((storeId: storeId, memberId: userId)))
            .valueOrNull ??
        const <TimeOffRequest>[];
    final today = dateKey(DateTime.now());
    final upcoming = list.where((r) => r.endDate.compareTo(today) >= 0).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MSection('Time off'),
        MCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: upcoming.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'No upcoming time off.',
                    style: TextStyle(color: c.muted),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < upcoming.length; i++)
                      Builder(
                        builder: (context) {
                          final r = upcoming[i];
                          final s = parseDateKey(r.startDate);
                          final e = parseDateKey(r.endDate);
                          final label = s == null
                              ? r.startDate
                              : r.startDate == r.endDate || e == null
                              ? shortDate(s)
                              : '${shortDate(s)} – ${shortDate(e)}';
                          final (text, color) = switch (r.status) {
                            'approved' => ('Approved', AppTheme.green),
                            'denied' => ('Denied', AppTheme.red),
                            _ => ('Pending', AppTheme.yellow),
                          };
                          return MField(
                            label,
                            null,
                            last: i == upcoming.length - 1,
                            valueWidget: MPill(text, color: color),
                          );
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
