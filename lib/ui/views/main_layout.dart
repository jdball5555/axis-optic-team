import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/app_version.dart';
import '../../providers/app_providers.dart';
import '../../providers/feature_providers.dart';
import '../widgets/unsaved_changes_dialog.dart';
import 'schedule/ai_build_controller.dart';

class MainLayout extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainLayout({super.key, required this.navigationShell});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  bool _isSidebarExpanded = true;
  final GlobalKey _storeMenuKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final usersAsyncValue = ref.watch(currentMembersProvider);
    final teamCount = usersAsyncValue.when(
      data: (users) => users.length.toString(),
      loading: () => '...',
      error: (e, st) => '!',
    );
    final isScheduleEnabled = ref.watch(scheduleFeatureProvider);
    final isShiftEnabled = ref.watch(shiftFeatureProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // Collapsible Side Navigation Bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isSidebarExpanded ? 240 : 70,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Everything but the bottom toggle scrolls when the window is
                // too short; the arrow and version always stay visible.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 20),
                              // App icon (always shown, centered over the nav
                              // icons when collapsed) + "Axis Team" (fades).
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const NeverScrollableScrollPhysics(),
                                child: SizedBox(
                                  width: 240,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      17,
                                      4,
                                      12,
                                      4,
                                    ),
                                    child: Row(
                                      children: [
                                        Image.asset(
                                          'assets/branding/app_icon_circle.png',
                                          width: 36,
                                          height: 36,
                                          filterQuality: FilterQuality.high,
                                          semanticLabel: 'Axis Team',
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: AnimatedOpacity(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            opacity: _isSidebarExpanded
                                                ? 1.0
                                                : 0.0,
                                            child: Text(
                                              'Axis Team',
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.fade,
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.titleLarge?.color,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 22,
                                                letterSpacing: 0.5,
                                                height: 1.1,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildNavItem(
                                context,
                                title: 'Dashboard',
                                icon: Icons.dashboard_outlined,
                                route: '/dashboard',
                                isSelected:
                                    _calculateSelectedIndex(context) == 1,
                              ),
                              _buildNavItem(
                                context,
                                title: 'Team Members',
                                icon: Icons.people_outline,
                                route: '/',
                                isSelected:
                                    _calculateSelectedIndex(context) == 0,
                                badgeCount: teamCount,
                              ),
                              _buildNavItem(
                                context,
                                title: 'Rosters',
                                icon: Icons.bar_chart,
                                route: '/rosters',
                                isSelected:
                                    _calculateSelectedIndex(context) == 2,
                                badgeCount:
                                    ref.watch(newHiresNeededProvider) > 0
                                    ? ref
                                          .watch(newHiresNeededProvider)
                                          .toString()
                                    : null,
                                badgeColor: AppTheme.primaryRed,
                              ),
                              _buildNavItem(
                                context,
                                title: 'Portal',
                                icon: Icons.link_outlined,
                                route: '/portal',
                                isSelected:
                                    _calculateSelectedIndex(context) == 9,
                              ),
                              _buildNavItem(
                                context,
                                title: 'Settings',
                                icon: Icons.settings_outlined,
                                route: '/settings',
                                isSelected:
                                    _calculateSelectedIndex(context) == 3,
                              ),
                              if (isScheduleEnabled || isShiftEnabled) ...[
                                const SizedBox(height: 8),
                                Divider(
                                  height: 1,
                                  color: Theme.of(context).dividerColor,
                                ),
                                const SizedBox(height: 8),
                                if (isScheduleEnabled)
                                  _buildNavItem(
                                    context,
                                    title: 'Schedule',
                                    icon: Icons.calendar_month,
                                    route: '/schedule',
                                    isSelected:
                                        _calculateSelectedIndex(context) == 4,
                                    busy: ref.watch(
                                      aiBuildProvider.select((s) => s.busy),
                                    ),
                                  ),
                                if (isScheduleEnabled && isShiftEnabled) ...[
                                  const SizedBox(height: 8),
                                  Divider(
                                    height: 1,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (isShiftEnabled)
                                  _buildNavItem(
                                    context,
                                    title: 'Shift',
                                    icon: Icons.access_time,
                                    route: '/shift',
                                    isSelected:
                                        _calculateSelectedIndex(context) == 5,
                                  ),
                                const SizedBox(height: 8),
                                Divider(
                                  height: 1,
                                  color: Theme.of(context).dividerColor,
                                ),
                                const SizedBox(height: 8),
                              ],
                              const Spacer(),
                              _buildSidebarUserSection(context),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Toggle Button at bottom
                InkWell(
                  onTap: () {
                    setState(() {
                      _isSidebarExpanded = !_isSidebarExpanded;
                    });
                  },
                  child: SizedBox(
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          left: 25,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _isSidebarExpanded ? 1.0 : 0.0,
                            child: Text(
                              'v$appVersion',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 25.0),
                            child: Icon(
                              _isSidebarExpanded
                                  ? Icons.keyboard_arrow_left
                                  : Icons.keyboard_arrow_right,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Main Content
          Expanded(child: widget.navigationShell),
        ],
      ),
    );
  }

  Future<void> _executeWithUnsavedCheck(
    BuildContext context,
    VoidCallback action,
  ) async {
    if (!ref.read(unsavedChangesProvider)) {
      action();
      return;
    }
    final choice = await showUnsavedChangesDialog(context);
    if (choice == null) return; // Cancel: stay put
    if (choice == UnsavedChoice.save) {
      final saveAction = ref.read(saveChangesActionProvider);
      if (saveAction != null) await saveAction();
    } else {
      ref.read(discardChangesActionProvider)?.call();
    }
    ref.read(unsavedChangesProvider.notifier).state = false;
    ref.read(saveChangesActionProvider.notifier).state = null;
    ref.read(discardChangesActionProvider.notifier).state = null;
    if (context.mounted) action();
  }

  void _navigateWithCheck(BuildContext context, String route) {
    if (GoRouterState.of(context).uri.path == route) return; // already there
    _executeWithUnsavedCheck(context, () => context.go(route));
  }

  Widget _buildNavItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String route,
    required bool isSelected,
    String? badgeCount,
    Color? badgeColor,
    bool busy = false, // e.g. the AI scheduler is building
  }) {
    final spinner = CircularProgressIndicator(
      strokeWidth: 2,
      color: AppTheme.accent2,
    );
    return InkWell(
      onTap: () => _navigateWithCheck(context, route),
      child: Container(
        height: 40, // Made slightly thinner
        decoration: BoxDecoration(
          border: isSelected
              ? Border(
                  left: BorderSide(
                    color:
                        Theme.of(context).textTheme.titleLarge?.color ??
                        Colors.white,
                    width: 4,
                  ),
                )
              : null,
          color: isSelected
              ? Theme.of(
                  context,
                ).textTheme.titleLarge?.color?.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: 240,
            child: Row(
              children: [
                // Centered icon in the 70px collapsed width (25 left padding, 20 icon, 25 right padding = 70)
                const SizedBox(width: 25),
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: isSelected
                          ? Theme.of(context).textTheme.titleLarge?.color
                          : Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    // Collapsed sidebar: a ring around the icon instead.
                    if (busy && !_isSidebarExpanded)
                      Positioned(
                        left: -5,
                        top: -5,
                        right: -5,
                        bottom: -5,
                        child: spinner,
                      ),
                  ],
                ),
                if (_isSidebarExpanded) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).textTheme.titleLarge?.color
                            : Theme.of(context).textTheme.bodyLarge?.color,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (badgeCount != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor ?? Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badgeCount,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: badgeColor != null
                              ? Colors.white
                              : Theme.of(context).textTheme.bodyLarge?.color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                  ] else if (busy) ...[
                    Tooltip(
                      message: 'Building the schedule…',
                      child: SizedBox(width: 14, height: 14, child: spinner),
                    ),
                    const SizedBox(width: 24),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location == '/' || location.startsWith('/member')) return 0;
    if (location.startsWith('/dashboard')) return 1;
    if (location.startsWith('/rosters')) return 2;
    if (location.startsWith('/settings')) return 3;
    if (location.startsWith('/schedule')) return 4;
    if (location.startsWith('/shift')) return 5;
    if (location.startsWith('/store')) return 6;
    if (location.startsWith('/account')) return 7;
    if (location.startsWith('/feedback')) return 8;
    if (location.startsWith('/portal')) return 9;
    return 0;
  }

  Widget _buildSidebarUserSection(BuildContext context) {
    final currentStoreId = ref.watch(currentStoreIdProvider);
    final allStoresAsync = ref.watch(allStoresStreamProvider);
    final currentUser = ref.watch(currentUserProvider);

    String userNameDisplay = 'Unknown User';
    if (currentUser != null) {
      userNameDisplay =
          '${currentUser['first_name']} ${currentUser['last_name']} (Owner)';
    }

    return allStoresAsync.when(
      data: (stores) {
        String storeDisplayName = 'All Stores';
        if (currentStoreId != null) {
          final s = stores.where((e) => e['id'] == currentStoreId).firstOrNull;
          storeDisplayName = s?['name'] as String? ?? 'Untitled Store';
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: 240,
            child: Column(
              children: [
                _buildNavItem(
                  context,
                  title: 'Feedback',
                  icon: Icons.feedback_outlined,
                  route: '/feedback',
                  isSelected: _calculateSelectedIndex(context) == 8,
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () {
                          _executeWithUnsavedCheck(context, () {
                            dynamic state = _storeMenuKey.currentState;
                            state?.showButtonMenu();
                          });
                        },
                        child: PopupMenuButton<String>(
                          key: _storeMenuKey,
                          enabled:
                              false, // Disables its own tap listener so InkWell can catch it
                          tooltip: 'Change Store',
                          color: Theme.of(context).cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Theme.of(context).dividerColor,
                              width: 1,
                            ),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 216,
                            maxWidth: 216,
                          ),
                          offset: const Offset(12, -20),
                          onSelected: (value) {
                            if (value == 'all') {
                              ref.read(currentStoreIdProvider.notifier).state =
                                  null;
                            } else {
                              ref.read(currentStoreIdProvider.notifier).state =
                                  value;
                            }
                            // Stay on the same page. A single team member's
                            // page belongs to the old store, so that one goes
                            // back to the team list.
                            final path = GoRouterState.of(context).uri.path;
                            if (path.startsWith('/member')) {
                              Future.microtask(() {
                                if (context.mounted) context.go('/');
                              });
                            }
                          },
                          itemBuilder: (context) {
                            List<PopupMenuEntry<String>> items = [
                              const PopupMenuItem(
                                value: 'all',
                                child: Text('All Stores'),
                              ),
                            ];
                            for (var s in stores) {
                              items.add(
                                PopupMenuItem(
                                  value: s['id'] as String,
                                  child: Text(
                                    s['name'] as String? ?? 'Untitled Store',
                                  ),
                                ),
                              );
                            }
                            return items;
                          },
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(width: 25),
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Icon(
                                  Icons.store,
                                  size: 20,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.color,
                                ),
                              ),
                              if (_isSidebarExpanded) ...[
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    storeDisplayName,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Icon(
                                    Icons.arrow_drop_up,
                                    size: 20,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.color,
                                  ),
                                ),
                                const SizedBox(width: 16),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () => _navigateWithCheck(context, '/account'),
                        child: Row(
                          children: [
                            const SizedBox(width: 25),
                            Icon(
                              Icons.account_circle,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                            if (_isSidebarExpanded) ...[
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  userNameDisplay,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => const Center(child: Text('Error')),
    );
  }
}
