import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart' show dateOnly;
import '../../providers/app_providers.dart';
import 'mobile_data.dart';
import 'mobile_shell.dart';
import 'mobile_ui.dart';

/// Settings: your login, everything on file about you (title, permits and
/// their expiration dates), your store and how the app looks.
class SettingsMobilePage extends ConsumerWidget {
  const SettingsMobilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final user = ref.watch(currentUserProvider) ?? const <String, dynamic>{};
    final access = ref.watch(mobileAccessProvider);
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final member = access.member;
    final storeId = ref.watch(currentStoreIdProvider);
    final stores = ref.watch(allStoresStreamProvider).valueOrNull ?? const [];
    final storeIds = ref.watch(mobileStoreIdsProvider);
    String storeName(String? id) =>
        stores.where((s) => s['id'] == id).firstOrNull?['name'] as String? ?? 'Store';

    final email = user['email'] as String? ?? FirebaseAuth.instance.currentUser?.email ?? '';
    final name = member != null
        ? fullNameOf(member)
        : [user['first_name'], user['last_name']]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(' ');
    final role = access.isOwner
        ? 'Owner'
        : access.isBot
        ? 'Bot account'
        : 'Team member';
    final color = member?.title != null ? titleColor(member!.title, settings) : AppTheme.accent;
    final initials = member != null
        ? initialsOf(member)
        : name
              .split(' ')
              .where((p) => p.isNotEmpty)
              .take(2)
              .map((p) => p[0].toUpperCase())
              .join();

    final themeMode = ref.watch(themeModeProvider);
    final needsMgr = settings?.titles
            .where((t) => t.name == member?.title)
            .firstOrNull
            ?.mgrPermit ??
        false;

    return MPage(
      title: 'Settings',
      children: [
        // Who's signed in.
        MCard(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              MAvatar(initials: initials.isEmpty ? '?' : initials, color: color, size: 60),
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
                    Text(email, style: TextStyle(fontSize: 13.5, color: c.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        MPill(role, color: AppTheme.accent),
                        if (member?.title != null) MPill(member!.title!, color: color),
                      ],
                    ),
                  ],
                ),
              ),
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
                      ? Text('—', style: TextStyle(fontWeight: FontWeight.w600, color: c.text))
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
                  member.startDate == null ? null : mediumDate(member.startDate!),
                ),
                MField(
                  'With the team',
                  member.startDate == null ? null : tenureSince(member.startDate!),
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
          label: 'Send password reset email',
          icon: Icons.lock_reset,
          secondary: true,
          onPressed: email.isEmpty
              ? null
              : () async {
                  try {
                    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                    if (context.mounted) mSnack(context, 'Email sent to $email.');
                  } catch (_) {
                    if (context.mounted) mSnack(context, 'Couldn\'t send the email. Please try again.');
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
                    style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
                  ),
                ),
                Text('Switch', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],

        // Appearance.
        const MSection('Appearance'),
        MCard(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Dark mode', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                value: themeMode != ThemeMode.light,
                activeTrackColor: AppTheme.accent,
                onChanged: (v) {
                  ref.read(themeModeProvider.notifier).state = v ? ThemeMode.dark : ThemeMode.light;
                  ref.read(brightColorsProvider.notifier).state = null;
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text('Bright colors', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                subtitle: Text(
                  'The bright shades of the accent colors',
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
                value: ref.watch(effectiveBrightColorsProvider),
                activeTrackColor: AppTheme.accent,
                onChanged: (v) => ref.read(brightColorsProvider.notifier).state = v,
              ),
            ],
          ),
        ),

        const SizedBox(height: 26),
        MButton(
          label: 'Sign out',
          icon: Icons.logout,
          color: AppTheme.red,
          onPressed: () => signOut(context, ref),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              Image.asset(
                'assets/branding/app_icon_circle.png',
                width: 34,
                height: 34,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(height: 6),
              Text(
                'Axis Team v$appVersion',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
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
      borderColor: status.ok ? null : AppTheme.edge(status.color).withValues(alpha: 0.55),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.tint(status.color),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.badge_outlined, color: AppTheme.onTint(status.color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: c.title)),
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
