import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../../ui/views/dashboard_view.dart';
import '../../ui/views/main_layout.dart';
import '../../ui/views/team_roster_view.dart';
import '../../ui/views/member_detail_view.dart';
import '../../ui/views/settings_view.dart';
import '../../ui/views/access_view.dart';
import '../../ui/views/rosters_view.dart';
import '../../ui/views/store_view.dart';
import '../../ui/views/schedule_view.dart';
import '../../ui/views/shift_view.dart';
import '../../ui/views/auth_view.dart';
import '../../ui/views/account_view.dart';
import '../../ui/views/feedback_view.dart';
import '../../ui/views/portal_view.dart';

import '../../ui/views/team_member_dashboard_view.dart';
import '../../ui/mobile/home_page.dart';
import '../../ui/mobile/mobile_data.dart';
import '../../ui/mobile/mobile_shell.dart';
import '../../ui/mobile/mobile_ui.dart';
import '../../ui/mobile/my_schedule_page.dart';
import '../../ui/mobile/promotion_page.dart';
import '../../ui/mobile/roster_page.dart';
import '../../ui/mobile/settings_page.dart';
import '../../ui/mobile/shift_board_mobile.dart';
import '../../ui/mobile/team_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final currentUser = ref.read(currentUserProvider);
      final isAuth = currentUser != null;
      final location = state.matchedLocation;
      final isGoingToAuth = location == '/auth';

      if (!isAuth && !isGoingToAuth) {
        return '/auth';
      }
      if (!isAuth) return null;

      // Phones (and every team-member login) get the phone app under /m.
      final mobile = useMobileLayout(
        currentUser,
        teamMemberView: ref.read(teamMemberViewProvider),
      );
      final isMobileRoute = location == '/m' || location.startsWith('/m/');
      if (isGoingToAuth || location == '/team_member_dashboard') {
        return mobile ? MobileTab.home.path : '/dashboard';
      }
      if (mobile && !isMobileRoute) return MobileTab.home.path;
      if (!mobile && isMobileRoute) return '/dashboard';
      if (location == '/m') return MobileTab.home.path;
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        // The login screen is always dark with bright colors.
        builder: (context, state) => Theme(
          data: AppTheme.darkTheme(bright: true),
          child: AuthView(
            setupEmail: state.uri.queryParameters['email'],
            setupFirstName: state.uri.queryParameters['firstName'],
            setupLastName: state.uri.queryParameters['lastName'],
            setupMemberId: state.uri.queryParameters['memberId'],
            setupStoreId: state.uri.queryParameters['storeId'],
          ),
        ),
      ),
      GoRoute(
        path: '/team_member_dashboard',
        builder: (context, state) => const TeamMemberDashboardView(),
      ),
      // Phone app: the congratulations screen after a promotion (full screen,
      // over the tabs).
      GoRoute(
        path: celebratePath,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          transitionDuration: const Duration(milliseconds: 450),
          child: const PromotionCelebrationPage(),
          transitionsBuilder: (context, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
      ),
      // ---------------------------------------------------------------------
      // Phone app: bottom tabs (branch order = MobileTab order).
      // ---------------------------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MobileTheme(child: MobileShell(navigationShell: navigationShell)),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/m/home',
                builder: (context, state) => const MobileHomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/m/schedule',
                builder: (context, state) => const MyScheduleMobilePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/m/team',
                builder: (context, state) => const TeamMobilePage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        MemberMobilePage(userId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/m/roster',
                builder: (context, state) => const RosterMobilePage(),
                routes: [
                  GoRoute(
                    path: 'shift',
                    builder: (context, state) => ShiftBoardPage(
                      initialDate: DateTime.tryParse(
                        state.uri.queryParameters['date'] ?? '',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/m/settings',
                builder: (context, state) => const SettingsMobilePage(),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainLayout(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const TeamRosterView(),
                routes: [
                  GoRoute(
                    path: 'member/:id',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      final from = state.uri.queryParameters['from'];
                      return MemberDetailView(userId: id, returnPath: from);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardView(),
                routes: [
                  GoRoute(
                    path: 'config',
                    builder: (context, state) =>
                        const DashboardView(isConfigMode: true),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/rosters',
                builder: (context, state) => const RostersView(),
                routes: [
                  GoRoute(
                    path: 'config',
                    builder: (context, state) =>
                        const RostersView(isConfigMode: true),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/portal',
                builder: (context, state) => const PortalView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsView(),
                routes: [
                  GoRoute(
                    path: 'access',
                    builder: (context, state) => const AccessView(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/store',
                builder: (context, state) => const StoreView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/schedule',
                builder: (context, state) => const ScheduleView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shift',
                builder: (context, state) => const ShiftView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                builder: (context, state) => const AccountView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/feedback',
                builder: (context, state) => const FeedbackView(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
