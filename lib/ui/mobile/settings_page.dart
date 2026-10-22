import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_version.dart';
import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart' show dateOnly;
import '../../providers/app_providers.dart';
import '../../services/push_service.dart';
import 'leader_preview.dart' show startPromotionTest;
import 'mobile_data.dart';
import 'mobile_shell.dart';
import 'mobile_ui.dart';
import '../widgets/change_name_dialog.dart';

/// Settings: your login, everything on file about you (title, permits and
/// their expiration dates), your store and how the app looks.
class SettingsMobilePage extends ConsumerStatefulWidget {
  const SettingsMobilePage({super.key});

  @override
  ConsumerState<SettingsMobilePage> createState() => _SettingsMobilePageState();
}

class _SettingsMobilePageState extends ConsumerState<SettingsMobilePage> {
  bool _isEditingName = false;
  late final TextEditingController _firstController;
  late final TextEditingController _lastController;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider) ?? const <String, dynamic>{};
    _firstController = TextEditingController(
      text: user['first_name'] as String? ?? '',
    );
    _lastController = TextEditingController(
      text: user['last_name'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _firstController.dispose();
    _lastController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final user = ref.watch(currentUserProvider) ?? const <String, dynamic>{};
    if (!_isEditingName) {
      _firstController.text = user['first_name'] as String? ?? '';
      _lastController.text = user['last_name'] as String? ?? '';
    }
    final access = ref.watch(mobileAccessProvider);
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final member = access.member;
    final storeId = ref.watch(currentStoreIdProvider);
    final stores = ref.watch(allStoresStreamProvider).valueOrNull ?? const [];
    final storeIds = ref.watch(mobileStoreIdsProvider);
    String storeName(String? id) =>
        stores.where((s) => s['id'] == id).firstOrNull?['name'] as String? ??
        'Store';

    final email =
        user['email'] as String? ??
        FirebaseAuth.instance.currentUser?.email ??
        '';
    final name = member != null
        ? fullNameOf(member)
        : [
            user['first_name'],
            user['last_name'],
          ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    final role = access.isOwner
        ? 'Owner'
        : access.isBot
        ? 'Bot account'
        : 'Team member';
    final color = member?.title != null
        ? titleColor(member!.title, settings)
        : MBrand.red;
    final initials = member != null
        ? initialsOf(member)
        : name
              .split(' ')
              .where((p) => p.isNotEmpty)
              .take(2)
              .map((p) => p[0].toUpperCase())
              .join();

    final themeMode = ref.watch(themeModeProvider);
    final needsMgr =
        settings?.titles
            .where((t) => t.name == member?.title)
            .firstOrNull
            ?.mgrPermit ??
        false;

    final viewingAsTeam = ref.watch(teamMemberViewProvider);

    return MPage(
      title: 'Settings',
      children: [
        // "View as team member" is on: the way back.
        if (viewingAsTeam) ...[
          _TeamMemberViewCard(
            on: true,
            onChanged: (_) {
              setTeamMemberView(ref, false);
              context.go('/dashboard');
            },
          ),
          const SizedBox(height: 16),
        ],

        // Who's signed in.
        MCard(
          padding: const EdgeInsets.all(18),
          onTap: (access.isOwner && !_isEditingName)
              ? () => setState(() => _isEditingName = true)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MAvatar(
                    initials: initials.isEmpty ? '?' : initials,
                    color: color,
                    size: 60,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Your account' : name,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: c.title,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email,
                          style: TextStyle(fontSize: 13.5, color: c.muted),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            MPill(role, color: MBrand.red),
                            if (member?.title != null)
                              MPill(member!.title!, color: color),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_isEditingName) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _firstController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'First Name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _lastController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Last Name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _isEditingName = false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final first = _firstController.text.trim();
                        final last = _lastController.text.trim();
                        if (first.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('First name cannot be empty.'),
                            ),
                          );
                          return;
                        }
                        await updateUserName(
                          ref: ref,
                          newFirst: first,
                          newLast: last,
                        );
                        if (mounted) {
                          setState(() => _isEditingName = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Name updated to $first $last'),
                            ),
                          );
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // About you.
        if (member != null) ...[
          const MSection('About you'),
          MCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(
              children: [
                MField('Title', member.title),
                MField(
                  'Tags',
                  null,
                  valueWidget: (member.additionalTags ?? const []).isEmpty
                      ? Text(
                          '—',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        )
                      : Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final t in member.additionalTags!)
                              MPill(t, color: tagColor(t, settings)),
                          ],
                        ),
                ),
                MField('Position', member.position),
                MField('Designation', member.designation),
                MField('Working time', member.workingTime),
                MField('Avg shifts / wk', member.avgShifts),
                MField('Store', storeName(member.store ?? storeId)),
                MField(
                  'Start date',
                  member.startDate == null
                      ? null
                      : mediumDate(member.startDate!),
                ),
                MField(
                  'With the team',
                  member.startDate == null
                      ? null
                      : tenureSince(member.startDate!),
                ),
                MField(
                  'Pay',
                  member.payRate == null
                      ? null
                      : '\$${member.payRate!.toStringAsFixed(2)} / hr',
                  last: member.endDate == null,
                ),
                if (member.endDate != null)
                  MField('Last day', mediumDate(member.endDate!), last: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Something wrong? Let a leader know so they can update it.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ),

          // Permits.
          const MSection('Permits'),
          _PermitCard(
            title: 'Food handler\'s permit',
            expires: member.foodHandlersExpiration,
          ),
          if (needsMgr || member.managerPermitExpiration != null) ...[
            const SizedBox(height: 10),
            _PermitCard(
              title: 'Manager permit',
              expires: member.managerPermitExpiration,
            ),
          ],
        ],

        // Login.
        const MSection('Login'),
        MCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(
            children: [
              MField('Email', email),
              MField('Account', role, last: true),
            ],
          ),
        ),
        const SizedBox(height: 10),
        MButton(
          label: 'Change email',
          icon: Icons.alternate_email,
          secondary: true,
          onPressed: () => showChangeEmailDialog(context, ref),
        ),
        const SizedBox(height: 10),
        MButton(
          label: 'Send password reset email',
          icon: Icons.lock_reset,
          secondary: true,
          onPressed: email.isEmpty
              ? null
              : () async {
                  try {
                    await FirebaseAuth.instance.sendPasswordResetEmail(
                      email: email,
                    );
                    if (context.mounted)
                      mSnack(context, 'Email sent to $email.');
                  } catch (_) {
                    if (context.mounted)
                      mSnack(
                        context,
                        'Couldn\'t send the email. Please try again.',
                      );
                  }
                },
        ),

        // Store.
        if (storeIds.length > 1) ...[
          const MSection('Store'),
          MCard(
            onTap: () => showStorePicker(context, ref, storeIds, storeName),
            child: Row(
              children: [
                Icon(Icons.storefront_outlined, color: c.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    storeName(storeId),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                ),
                Text(
                  'Switch',
                  style: TextStyle(
                    color: MBrand.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Leader tools.
        if (access.isOwner || (access.leadership && !access.isBot)) ...[
          const MSection('Leader tools'),
          _TeamMemberViewCard(
            on: false,
            onChanged: (_) {
              setTeamMemberView(ref, true);
              context.go(MobileTab.home.path);
            },
          ),
          const SizedBox(height: 10),
          _ToolTile(
            icon: Icons.workspace_premium_outlined,
            title: 'Test the promotion',
            subtitle:
                'Sends you a promotion notification (to Operator) so you can see what your team sees. Nothing changes.',
            onTap: () => startPromotionTest(context, ref),
          ),
        ],

        // Notifications.
        if (member?.id != null && storeId != null && PushService.supported) ...[
          const MSection('Notifications'),
          _NotificationsCard(storeId: storeId, memberId: member!.id!),
        ],

        // Appearance.
        const MSection('Appearance'),
        MCard(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Dark mode',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
                ),
                value: themeMode != ThemeMode.light,
                activeTrackColor: MBrand.red,
                onChanged: (v) {
                  ref.read(themeModeProvider.notifier).state = v
                      ? ThemeMode.dark
                      : ThemeMode.light;
                  ref.read(brightColorsProvider.notifier).state = null;
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Bright colors',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
                ),
                subtitle: Text(
                  'The bright shades of the accent colors',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
                value: ref.watch(effectiveBrightColorsProvider),
                activeTrackColor: MBrand.red,
                onChanged: (v) =>
                    ref.read(brightColorsProvider.notifier).state = v,
              ),
            ],
          ),
        ),

        const SizedBox(height: 26),
        MButton(
          label: 'Sign out',
          icon: Icons.logout,
          onPressed: () => signOut(context, ref),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'Axis Team v$appVersion',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ),
      ],
    );
  }
}

class _PermitCard extends StatelessWidget {
  const _PermitCard({required this.title, required this.expires});
  final String title;
  final DateTime? expires;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final status = permitStatus(expires);
    final days = expires == null
        ? null
        : dateOnly(expires!).difference(dateOnly(DateTime.now())).inDays;
    return MCard(
      borderColor: status.ok
          ? null
          : AppTheme.edge(status.color).withValues(alpha: 0.55),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.tint(status.color),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.badge_outlined,
              color: AppTheme.onTint(status.color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: c.title),
                ),
                const SizedBox(height: 3),
                Text(
                  expires == null
                      ? 'None on file'
                      : days != null && days >= 0
                      ? 'Expires ${mediumDate(expires!)}'
                      : 'Expired ${mediumDate(expires!)}',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
          MPill(status.label, color: status.color),
        ],
      ),
    );
  }
}

/// Push notifications on this phone (promotions and other news about you).
class _NotificationsCard extends ConsumerStatefulWidget {
  const _NotificationsCard({required this.storeId, required this.memberId});
  final String storeId;
  final String memberId;

  @override
  ConsumerState<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends ConsumerState<_NotificationsCard>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool? _permitted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the phone's settings: check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await PushService.permitted();
    if (mounted) setState(() => _permitted = ok);
  }

  Future<void> _set(bool on) async {
    setState(() => _busy = true);
    try {
      if (on) {
        final ok = await PushService.enable(
          widget.storeId,
          widget.memberId,
          remember: true,
        );
        if (!ok && mounted) {
          mSnack(
            context,
            'Notifications are blocked for Axis Team. Turn them on in your '
            'phone\'s settings, then try again.',
          );
        }
      } else {
        await PushService.disable(widget.storeId, widget.memberId);
      }
    } catch (_) {
      if (mounted) mSnack(context, 'Couldn\'t change that. Please try again.');
    }
    await _check();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final doc = ref
        .watch(
          memberDocProvider((
            storeId: widget.storeId,
            memberId: widget.memberId,
          )),
        )
        .valueOrNull;
    final wanted = doc?['notifications_enabled'] != false;
    final blocked = _permitted == false;
    final on = wanted && !blocked;
    return MCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          'Push notifications',
          style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
        ),
        subtitle: Text(
          blocked && wanted
              ? 'Blocked in your phone\'s settings'
              : 'Promotions and other news about you',
          style: TextStyle(
            fontSize: 12.5,
            color: blocked && wanted ? AppTheme.orange : c.muted,
          ),
        ),
        value: on,
        activeTrackColor: MBrand.red,
        onChanged: _busy || doc == null ? null : _set,
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return MCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.tint(MBrand.red),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.onTint(MBrand.red)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: c.title),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: c.muted),
        ],
      ),
    );
  }
}

/// "View as team member": the whole app exactly as your team sees it, as
/// you with a sample schedule. Off goes back to your dashboard.
class _TeamMemberViewCard extends StatelessWidget {
  const _TeamMemberViewCard({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return MCard(
      glow: on ? MBrand.red : null,
      onTap: () => onChanged(!on),
      child: Row(
        children: [
          const MIconBadge(Icons.visibility_outlined, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  on ? 'Viewing as a team member' : 'View as team member',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: c.title,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  on
                      ? 'This is exactly what your team sees, with a sample schedule. Nothing you do here is saved. Turn off to go back to your dashboard.'
                      : 'See the whole app exactly as your team does, as you with a sample schedule.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: on,
            activeTrackColor: MBrand.red,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
