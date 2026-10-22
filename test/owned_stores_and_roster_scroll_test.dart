import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/providers/feature_providers.dart';
import 'package:axis_team/services/firestore_service.dart';
import 'package:axis_team/ui/views/main_layout.dart';
import 'package:axis_team/ui/views/rosters_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class MockFirestoreService implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final mockFirestore = MockFirestoreService();

  group('Owned Stores Filtering in Sidebar', () {
    testWidgets(
      'Sidebar only displays stores matching currentUser owned_stores, omitting 202 and North',
      (tester) async {
        final stores = [
          {'id': '202', 'name': 'Store 202', 'is_dev': false},
          {'id': 'North', 'name': 'North Store', 'is_dev': false},
          {'id': 'my_store_1', 'name': 'My Store 1', 'is_dev': false},
          {'id': 'my_store_2', 'name': 'My Store 2', 'is_dev': true},
        ];

        final testRouter = GoRouter(
          initialLocation: '/',
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, navigationShell) {
                return MainLayout(navigationShell: navigationShell);
              },
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: '/',
                      builder: (context, state) =>
                          const Scaffold(body: Text('Page Body')),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
              firestoreServiceProvider.overrideWithValue(mockFirestore),
              allStoresStreamProvider.overrideWith((ref) => Stream.value(stores)),
              currentStoreIdProvider.overrideWith((ref) => null),
              currentUserProvider.overrideWith((ref) => {
                'id': 'owner_1',
                'first_name': 'Alex',
                'last_name': 'Owner',
                'owned_stores': ['my_store_1', 'my_store_2'],
              }),
              currentMembersProvider.overrideWith(
                (ref) => const AsyncValue.data(<UserModel>[]),
              ),
              scheduleFeatureProvider
                  .overrideWith(() => FeatureToggleNotifier(false)),
              shiftFeatureProvider
                  .overrideWith(() => FeatureToggleNotifier(false)),
              newHiresNeededProvider.overrideWith((ref) => 0),
            ],
            child: MaterialApp.router(
              routerConfig: testRouter,
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Tap the store switcher button at the bottom-left
        final storeButton = find.text('All Stores');
        expect(storeButton, findsOneWidget);

        await tester.tap(storeButton);
        await tester.pumpAndSettle();

        // The popup menu should display "All Stores", "My Store 1", "My Store 2"
        expect(find.text('My Store 1'), findsOneWidget);
        expect(find.text('My Store 2'), findsOneWidget);

        // Crucially, stores NOT in owned_stores (202 and North) MUST NOT appear!
        expect(find.text('Store 202'), findsNothing);
        expect(find.text('North Store'), findsNothing);
      },
    );
  });

  group('Roster Tile Scroll Isolation', () {
    testWidgets(
      'Scrolling inside a roster tile isolates scrolling and does not move outer canvas when at bounds',
      (tester) async {
        final users = [
          for (int i = 0; i < 20; i++)
            UserModel(
              id: 'user_$i',
              firstName: 'Member',
              lastName: '$i',
              position: 'Cook',
              store: 'store_1',
              title: 'Team Member',
              avgShifts: '4',
            ),
        ];

        final stores = [
          {'id': 'store_1', 'name': 'Store 1', 'is_dev': false},
        ];

        await tester.binding.setSurfaceSize(const Size(1200, 350));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
              firestoreServiceProvider.overrideWithValue(mockFirestore),
              allStoresStreamProvider.overrideWith((ref) => Stream.value(stores)),
              currentStoreIdProvider.overrideWith((ref) => 'store_1'),
              currentUserProvider.overrideWith((ref) => {
                'id': 'owner_1',
                'first_name': 'Alex',
                'last_name': 'Owner',
                'owned_stores': ['store_1'],
              }),
              currentMembersProvider.overrideWith(
                (ref) => AsyncValue.data(users),
              ),
              rosterNeedsStreamProvider.overrideWith(
                (ref) => Stream.value({'store_1_Cook': 5}),
              ),
              specificStoreSettingsProvider('store_1').overrideWith(
                (ref) => Stream.value(
                  StoreSettingsModel(
                    positions: ['Cook'],
                    titles: [TitleConfig(id: 'tm', name: 'Team Member')],
                  ),
                ),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: RostersView(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Find the outer vertical scroll view
        final outerScrollable = find.byType(SingleChildScrollView).first;
        final scrollableState = tester.state<ScrollableState>(
          find.descendant(of: outerScrollable, matching: find.byType(Scrollable)).first,
        );
        final initialOuterOffset = scrollableState.position.pixels;

        // Find member in the roster tile
        final memberFinder = find.text('Member 0');
        expect(memberFinder, findsOneWidget);

        // Scroll inside the tile downwards
        final pointerLocation = tester.getCenter(memberFinder);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: pointerLocation,
            scrollDelta: const Offset(0, 100),
          ),
        );
        await tester.pumpAndSettle();

        // The outer canvas vertical offset must remain unchanged!
        expect(scrollableState.position.pixels, equals(initialOuterOffset));

        // Now scroll upwards past top bound (already at or near top)
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: pointerLocation,
            scrollDelta: const Offset(0, -300),
          ),
        );
        await tester.pumpAndSettle();

        // The outer canvas vertical offset must STILL remain unchanged (no bounds escape)!
        expect(scrollableState.position.pixels, equals(initialOuterOffset));

        // When scrolling outside any tile (on the canvas background), canvas scrolls
        await tester.sendEventToBinding(
          const PointerScrollEvent(
            position: Offset(1150, 250),
            scrollDelta: Offset(0, 150),
          ),
        );
        await tester.pumpAndSettle();

        expect(scrollableState.position.pixels, greaterThan(initialOuterOffset));
      },
    );

    testWidgets(
      'Scrolling inside a roster tile with no overflowing members still isolates and does not move outer canvas',
      (tester) async {
        final users = [
          UserModel(
            id: 'user_1',
            firstName: 'Solo',
            lastName: 'Member',
            position: 'Cook',
            store: 'store_1',
            title: 'Team Member',
            avgShifts: '4',
          ),
        ];

        final stores = [
          {'id': 'store_1', 'name': 'Store 1', 'is_dev': false},
        ];

        await tester.binding.setSurfaceSize(const Size(1200, 350));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
              firestoreServiceProvider.overrideWithValue(mockFirestore),
              allStoresStreamProvider.overrideWith((ref) => Stream.value(stores)),
              currentStoreIdProvider.overrideWith((ref) => 'store_1'),
              currentUserProvider.overrideWith((ref) => {
                'id': 'owner_1',
                'first_name': 'Alex',
                'last_name': 'Owner',
                'owned_stores': ['store_1'],
              }),
              currentMembersProvider.overrideWith(
                (ref) => AsyncValue.data(users),
              ),
              rosterNeedsStreamProvider.overrideWith(
                (ref) => Stream.value({'store_1_Cook': 5}),
              ),
              specificStoreSettingsProvider('store_1').overrideWith(
                (ref) => Stream.value(
                  StoreSettingsModel(
                    positions: ['Cook'],
                    titles: [TitleConfig(id: 'tm', name: 'Team Member')],
                  ),
                ),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: RostersView(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final outerScrollable = find.byType(SingleChildScrollView).first;
        final scrollableState = tester.state<ScrollableState>(
          find.descendant(of: outerScrollable, matching: find.byType(Scrollable)).first,
        );
        final initialOuterOffset = scrollableState.position.pixels;

        final memberFinder = find.text('Solo Member');
        expect(memberFinder, findsOneWidget);

        // Scroll inside this non-overflowing tile
        final pointerLocation = tester.getCenter(memberFinder);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: pointerLocation,
            scrollDelta: const Offset(0, 100),
          ),
        );
        await tester.pumpAndSettle();

        // The outer canvas must NOT move!
        expect(scrollableState.position.pixels, equals(initialOuterOffset));
      },
    );
  });
}

