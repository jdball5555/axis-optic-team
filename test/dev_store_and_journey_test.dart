import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/models/title_journey.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/ui/views/dashboard_view.dart';
import 'package:axis_team/ui/views/store_view.dart';
import 'package:axis_team/ui/widgets/journey_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StoreRow Add-on Tooltips', () {
    testWidgets('Enabled add-ons have NO tooltips; disabled add-ons have tooltips',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeStreamProvider('store-1').overrideWith(
              (ref) => Stream.value({'id': 'store-1', 'name': 'Test Store'}),
            ),
            specificStoreSettingsProvider('store-1').overrideWith(
              (ref) => Stream.value(
                const StoreSettingsModel(
                  isScheduleEnabled: true,
                  isShiftBoardEnabled: false,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StoreRow(
                storeId: 'store-1',
                initialStoreName: 'Test Store',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      // Only the disabled one (Shift Board) should be wrapped in Tooltip
      final feedbackTooltips = tooltips
          .where((t) =>
              t.message ==
              'Submit a feedback request to talk to the team about enabling this feature.')
          .toList();
      expect(feedbackTooltips.length, 1);

      // Verify switches
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches[0].value, isTrue); // Schedule Add-on is enabled
      expect(switches[1].value, isFalse); // Shift Board is disabled
    });

    testWidgets('Both enabled add-ons have NO feedback tooltips', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storeStreamProvider('store-2').overrideWith(
              (ref) => Stream.value({'id': 'store-2', 'name': 'Store 2'}),
            ),
            specificStoreSettingsProvider('store-2').overrideWith(
              (ref) => Stream.value(
                const StoreSettingsModel(
                  isScheduleEnabled: true,
                  isShiftBoardEnabled: true,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StoreRow(
                storeId: 'store-2',
                initialStoreName: 'Store 2',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final feedbackTooltips = tooltips
          .where((t) =>
              t.message ==
              'Submit a feedback request to talk to the team about enabling this feature.')
          .toList();
      expect(feedbackTooltips.isEmpty, isTrue);
    });
  });

  group('Dashboard Dev Store Mode & Configuration Icon', () {
    testWidgets('Non-dev store hides Clear All and Seed Sample Data buttons',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store-prod'),
          allStoresStreamProvider.overrideWith(
            (ref) => Stream.value([
              {'id': 'store-prod', 'name': 'Production Store', 'is_dev': false},
            ]),
          ),
          storeStreamProvider('store-prod').overrideWith(
            (ref) => Stream.value({
              'id': 'store-prod',
              'name': 'Production Store',
              'is_dev': false,
            }),
          ),
          currentMembersProvider.overrideWith(
            (ref) => const AsyncValue.data(<UserModel>[]),
          ),
          rosterNeedsStreamProvider.overrideWith(
            (ref) => Stream.value(<String, dynamic>{}),
          ),
          storeSettingsProvider.overrideWith(
            (ref) => Stream.value(const StoreSettingsModel()),
          ),
          currentUserProvider.overrideWith(
            (ref) => {'id': 'user-1', 'first_name': 'Dev', 'last_name': 'User'},
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: DashboardView()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Clear All and Seed Sample Store Data must NOT be present
      expect(find.text('Clear All'), findsNothing);
      expect(find.text('Seed Sample Store Data'), findsNothing);

      // Verify configuration icon is Icons.dashboard_customize
      expect(find.byIcon(Icons.dashboard_customize), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets('Dev store shows Clear All and Seed Sample Data buttons',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store-dev'),
          allStoresStreamProvider.overrideWith(
            (ref) => Stream.value([
              {'id': 'store-dev', 'name': 'Dev Store', 'is_dev': true},
            ]),
          ),
          storeStreamProvider('store-dev').overrideWith(
            (ref) => Stream.value({
              'id': 'store-dev',
              'name': 'Dev Store',
              'is_dev': true,
            }),
          ),
          currentMembersProvider.overrideWith(
            (ref) => const AsyncValue.data(<UserModel>[]),
          ),
          rosterNeedsStreamProvider.overrideWith(
            (ref) => Stream.value(<String, dynamic>{}),
          ),
          storeSettingsProvider.overrideWith(
            (ref) => Stream.value(const StoreSettingsModel()),
          ),
          currentUserProvider.overrideWith(
            (ref) => {'id': 'user-1', 'first_name': 'Dev', 'last_name': 'User'},
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: DashboardView()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Clear All and Seed Sample Store Data MUST be present for dev store
      expect(find.text('Clear All'), findsOneWidget);
      expect(find.text('Seed Sample Store Data'), findsOneWidget);

      // Configure icon is Icons.dashboard_customize
      expect(find.byIcon(Icons.dashboard_customize), findsOneWidget);
    });
  });

  group('Journey Arrow Flow & Straight Down Routing', () {
    test('Arrow to a node directly under it goes straight down', () {
      const layout = JourneyLayout();
      final journey = TitleJourney(
        nodes: const {
          't1': JourneyCell(0, 0),
          't2': JourneyCell(0, 1),
        },
        links: const [
          JourneyLink('t1', 't2'),
        ],
        icons: const {},
      );

      final routes = routeJourney(journey, layout);
      expect(routes.length, 1);
      final (link, route) = routes.first;
      expect(link.from, 't1');
      expect(link.to, 't2');

      // Must be a straight vertical line with exactly 2 points
      expect(route.points.length, 2);
      expect(route.points.first.dx, route.points.last.dx);
      expect(route.points.first.dy < route.points.last.dy, isTrue);

      // Direction should be straight down (dx == 0, dy == 1)
      final p1 = route.points.first;
      final p2 = route.points.last;
      expect(p1.dx, layout.center(const JourneyCell(0, 0)).dx);
      expect(p2.dx, layout.center(const JourneyCell(0, 1)).dx);
    });
  });
}
