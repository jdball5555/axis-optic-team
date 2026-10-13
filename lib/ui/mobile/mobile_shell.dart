import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'mobile_data.dart';
import 'mobile_ui.dart';

/// The phone app's tabs, in branch order (see app_router.dart).
enum MobileTab {
  home('/m/home', 'Home', Icons.home_outlined, Icons.home_rounded),
  schedule(
    '/m/schedule',
    'Schedule',
    Icons.calendar_month_outlined,
    Icons.calendar_month,
  ),
  team('/m/team', 'Team', Icons.people_outline, Icons.people),
  roster(
    '/m/roster',
    'Roster',
    Icons.view_timeline_outlined,
    Icons.view_timeline,
  ),
  settings('/m/settings', 'Settings', Icons.settings_outlined, Icons.settings);

  const MobileTab(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class MobileTabs {
  static void go(BuildContext context, MobileTab tab) => context.go(tab.path);

  /// The tabs this person gets.
  static List<MobileTab> visible(MobileAccess access) => [
    MobileTab.home,
    if (access.mySchedule) MobileTab.schedule,
    if (access.team) MobileTab.team,
    MobileTab.roster,
    MobileTab.settings,
  ];
}

/// Bottom-tab frame around the phone pages. Also makes sure a single store
/// is picked (the phone app always works in one store).
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  bool _pickingStore = false;

  void _ensureStore(List<String> ids, String? current) {
    if (ids.isEmpty || (current != null && ids.contains(current))) return;
    if (_pickingStore) return;
    _pickingStore = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pickingStore = false;
      if (!mounted) return;
      final now = ref.read(currentStoreIdProvider);
      if (now == null || !ids.contains(now)) {
        ref.read(currentStoreIdProvider.notifier).state = ids.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final ids = ref.watch(mobileStoreIdsProvider);
    final storeId = ref.watch(currentStoreIdProvider);
    _ensureStore(ids, storeId);

    if (storeId == null || !ids.contains(storeId)) {
      final storesLoading = ref.watch(allStoresStreamProvider).isLoading;
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: ids.isEmpty && !storesLoading
              ? MEmpty(
                  icon: Icons.storefront_outlined,
                  title: 'No store yet',
                  message: 'Your account isn\'t connected to a store.',
                  action: SizedBox(
                    width: 220,
                    child: MButton(
                      label: 'Sign out',
                      secondary: true,
                      onPressed: () => signOut(context, ref),
                    ),
                  ),
                )
              : CircularProgressIndicator(color: AppTheme.accent),
        ),
      );
    }

    final access = ref.watch(mobileAccessProvider);
    final tabs = MobileTabs.visible(access);
    final current = MobileTab.values[widget.navigationShell.currentIndex];
    final selected = tabs.indexOf(current);

    // A tab they can't use any more (access changed): back to Home.
    if (selected < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.navigationShell.goBranch(MobileTab.home.index);
      });
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: widget.navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line.withValues(alpha: 0.7))),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: c.card,
            surfaceTintColor: Colors.transparent,
            indicatorColor: AppTheme.tint(AppTheme.accent),
            height: 66,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 11.5,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: states.contains(WidgetState.selected)
                    ? c.title
                    : c.muted,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                size: 24,
                color: states.contains(WidgetState.selected)
                    ? AppTheme.onTint(AppTheme.accent)
                    : c.muted,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: selected < 0 ? 0 : selected,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) {
              final tab = tabs[i];
              widget.navigationShell.goBranch(
                tab.index,
                // Tapping the tab you're on goes back to its first page.
                initialLocation: tab == current,
              );
            },
            destinations: [
              for (final t in tabs)
                NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: t.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signs out and returns to the login screen.
Future<void> signOut(BuildContext context, WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('saved_email');
  await prefs.remove('saved_password');
  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}
  ref.read(currentUserProvider.notifier).state = null;
  ref.read(currentStoreIdProvider.notifier).state = null;
  if (context.mounted) context.go('/auth');
}

/// The current store's name; tap to switch when you have more than one.
class StoreChip extends ConsumerWidget {
  const StoreChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = MColors(context);
    final ids = ref.watch(mobileStoreIdsProvider);
    final storeId = ref.watch(currentStoreIdProvider);
    final stores = ref.watch(allStoresStreamProvider).valueOrNull ?? const [];
    String nameOf(String? id) =>
        stores.where((s) => s['id'] == id).firstOrNull?['name'] as String? ??
        'Store';
    final canSwitch = ids.length > 1;
    return GestureDetector(
      onTap: canSwitch
          ? () => showStorePicker(context, ref, ids, nameOf)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line.withValues(alpha: 0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 15, color: c.muted),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                nameOf(storeId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
            ),
            if (canSwitch) ...[
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 16, color: c.muted),
            ],
          ],
        ),
      ),
    );
  }
}

void showStorePicker(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
  String Function(String?) nameOf,
) {
  final current = ref.read(currentStoreIdProvider);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).cardColor,
    builder: (ctx) {
      final c = MColors(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  'Switch store',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.title,
                  ),
                ),
              ),
              for (final id in ids)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(
                    Icons.storefront_outlined,
                    color: id == current ? AppTheme.accent : c.muted,
                  ),
                  title: Text(
                    nameOf(id),
                    style: TextStyle(
                      fontWeight: id == current ? FontWeight.w700 : FontWeight.w500,
                      color: c.text,
                    ),
                  ),
                  trailing: id == current
                      ? Icon(Icons.check_rounded, color: AppTheme.accent)
                      : null,
                  onTap: () {
                    ref.read(currentStoreIdProvider.notifier).state = id;
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
