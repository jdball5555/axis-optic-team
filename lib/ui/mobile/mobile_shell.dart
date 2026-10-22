import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/app_providers.dart';
import '../../services/push_service.dart';
import '../widgets/axis_loader.dart';
import 'mobile_data.dart';
import 'mobile_ui.dart';
import 'promotion_page.dart';

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
  roster('/m/roster', 'Roster', Icons.table_chart_outlined, Icons.table_chart),
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

/// The store / team member this phone's notifications are set up for.
String? _pushSetupFor;

class _MobileShellState extends ConsumerState<MobileShell>
    with PromotionWatcher<MobileShell>, WidgetsBindingObserver {
  bool _pickingStore = false;

  @override
  void initState() {
    super.initState();
    PromotionWatcher.appOpened();
    WidgetsBinding.instance.addObserver(this);
    PushService.opened.addListener(_openedFromNotification);
    PushService.foreground.addListener(_arrivedWhileOpen);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openedFromNotification(),
    );
    // A test promotion waiting from before the app was closed.
    TestPromotion.load().then((p) {
      if (p != null && mounted && ref.read(promotionTestProvider) == null) {
        ref.read(promotionTestProvider.notifier).state = p;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushService.opened.removeListener(_openedFromNotification);
    PushService.foreground.removeListener(_arrivedWhileOpen);
    super.dispose();
  }

  // Coming back to the app counts as opening it (a promotion sent while
  // they were away plays now).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      PromotionWatcher.appOpened();
      setState(() {});
    }
  }

  /// A tapped notification opened the app: show the store it's about (the
  /// promotion screen then opens by itself).
  void _openedFromNotification() {
    final m = PushService.opened.value;
    if (m == null || !mounted) return;
    PushService.opened.value = null;
    PromotionWatcher.appOpened();
    final storeId = m.data['store_id'];
    if (storeId is String &&
        ref.read(mobileStoreIdsProvider).contains(storeId) &&
        ref.read(currentStoreIdProvider) != storeId) {
      ref.read(currentStoreIdProvider.notifier).state = storeId;
    }
    setState(() {});
  }

  /// A notification came in while they're in the app: show it here.
  void _arrivedWhileOpen() {
    final m = PushService.foreground.value;
    if (m == null || !mounted) return;
    PushService.foreground.value = null;
    final title = m.notification?.title ?? 'Axis Team';
    final body = m.notification?.body ?? '';
    final promotion = (m.data['type'] as String? ?? '').startsWith('promotion');
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 10),
          content: Text(body.isEmpty ? title : '$title\n$body'),
          action: promotion
              ? SnackBarAction(
                  label: 'Open',
                  onPressed: () {
                    PromotionWatcher.appOpened();
                    if (mounted) setState(() {});
                  },
                )
              : null,
        ),
      );
  }

  /// Sets up notifications for this phone (asks permission the first time),
  /// unless they turned them off in Settings.
  void _setUpPush(String storeId) {
    if (!PushService.supported) return;
    final memberId = ref.watch(myTeamRecordProvider).valueOrNull?.id;
    if (memberId == null) return;
    final key = (storeId: storeId, memberId: memberId);
    final doc = ref.watch(memberDocProvider(key));
    if (!doc.hasValue || doc.value == null) return;
    if (doc.value!['notifications_enabled'] == false) return;
    final id = '$storeId/$memberId';
    if (_pushSetupFor == id) return;
    _pushSetupFor = id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await PushService.enable(storeId, memberId);
      } catch (e) {
        debugPrint('Push setup failed: $e');
        _pushSetupFor = null;
      }
    });
  }

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
        backgroundColor: Colors.black,
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
              : const AxisLoader(size: 132, background: Colors.black),
        ),
      );
    }

    watchPromotion();
    _setUpPush(storeId);

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
      bottomNavigationBar: _NavBar(
        tabs: tabs,
        selected: selected < 0 ? 0 : selected,
        onTap: (i) {
          final tab = tabs[i];
          widget.navigationShell.goBranch(
            tab.index,
            // Tapping the tab you're on goes back to its first page.
            initialLocation: tab == current,
          );
        },
      ),
    );
  }
}

/// The tab bar: the picked tab's icon sits on a solid inverse pill.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.tabs,
    required this.selected,
    required this.onTap,
  });
  final List<MobileTab> tabs;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.line)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.light ? 0.06 : 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: InkResponse(
                    onTap: () => onTap(i),
                    radius: 34,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: i == selected ? 56 : 40,
                          height: 30,
                          decoration: BoxDecoration(
                            color: i == selected
                                ? c.inverse
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            i == selected ? tabs[i].selectedIcon : tabs[i].icon,
                            size: 21,
                            color: i == selected ? c.onInverse : c.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tabs[i].label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: i == selected ? c.title : c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
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
  // This phone stops getting their notifications.
  _pushSetupFor = null;
  await PushService.signOut(
    ref.read(currentStoreIdProvider),
    ref.read(myTeamRecordProvider).valueOrNull?.id,
  ).timeout(const Duration(seconds: 4), onTimeout: () {});
  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}
  setTeamMemberView(ref, false);
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
    final onHero = MHero.on(context);
    final fg = onHero ? Colors.white : c.text;
    final dim = onHero ? Colors.white.withValues(alpha: 0.75) : c.muted;
    return GestureDetector(
      onTap: canSwitch
          ? () => showStorePicker(context, ref, ids, nameOf)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: onHero ? Colors.white.withValues(alpha: 0.14) : c.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: onHero
                ? Colors.white.withValues(alpha: 0.3)
                : c.line.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 15, color: dim),
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
                  color: fg,
                ),
              ),
            ),
            if (canSwitch) ...[
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 16, color: dim),
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
                    color: id == current ? MBrand.red : c.muted,
                  ),
                  title: Text(
                    nameOf(id),
                    style: TextStyle(
                      fontWeight: id == current
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: c.text,
                    ),
                  ),
                  trailing: id == current
                      ? Icon(Icons.check_rounded, color: MBrand.red)
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
