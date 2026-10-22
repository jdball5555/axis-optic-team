import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/providers/feature_providers.dart';
import 'package:axis_team/services/firestore_service.dart';
import 'package:axis_team/ui/views/main_layout.dart';
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

  Widget buildTestApp({
    required List<Map<String, dynamic>> stores,
    required String? currentStoreId,
  }) {
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
                  builder: (context, state) => const Scaffold(body: Text('Page Body')),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
        firestoreServiceProvider.overrideWithValue(mockFirestore),
        allStoresStreamProvider.overrideWith((ref) => Stream.value(stores)),
        currentStoreIdProvider.overrideWith((ref) => currentStoreId),
        currentUserProvider.overrideWith((ref) => {
          'id': 'u1',
          'first_name': 'Alice',
          'last_name': 'Owner',
        }),
        currentMembersProvider.overrideWith(
          (ref) => const AsyncValue.data(<UserModel>[]),
        ),
        scheduleFeatureProvider.overrideWith(() => FeatureToggleNotifier(false)),
        shiftFeatureProvider.overrideWith(() => FeatureToggleNotifier(false)),
        newHiresNeededProvider.overrideWith((ref) => 0),
      ],
      child: MaterialApp.router(
        routerConfig: testRouter,
      ),
    );
  }

  testWidgets('Dev store shows purple dev icon at top, purple store icon, and NO badge below store name', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final stores = [
      {'id': 'store-1', 'name': 'Downtown Store', 'is_dev': true},
      {'id': 'store-2', 'name': 'Uptown Store', 'is_dev': false},
    ];

    await tester.pumpWidget(buildTestApp(stores: stores, currentStoreId: 'store-1'));
    await tester.pumpAndSettle();

    // Verify top header has Team and purple DEV icon
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);
    final devIcon = tester.widget<Icon>(find.byIcon(Icons.developer_mode));
    expect(devIcon.color, const Color(0xFFA855F7));

    // Verify store switcher displays Downtown Store and purple store icon
    expect(find.text('Downtown Store'), findsOneWidget);
    final storeIcon = tester.widget<Icon>(find.byIcon(Icons.store));
    expect(storeIcon.color, const Color(0xFFA855F7));

    // Verify there is NO text badge or icon below the store name
    expect(find.text('DEV MODE'), findsNothing);
    expect(find.text('DEV (1/2)'), findsNothing);
  });

  testWidgets('Non-dev store hides DEV badge and store icon is not purple', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final stores = [
      {'id': 'store-1', 'name': 'Downtown Store', 'is_dev': true},
      {'id': 'store-2', 'name': 'Uptown Store', 'is_dev': false},
    ];

    await tester.pumpWidget(buildTestApp(stores: stores, currentStoreId: 'store-2'));
    await tester.pumpAndSettle();

    // Verify store switcher displays Uptown Store
    expect(find.text('Uptown Store'), findsOneWidget);

    // Verify store icon is NOT purple
    final storeIcon = tester.widget<Icon>(find.byIcon(Icons.store));
    expect(storeIcon.color, isNot(const Color(0xFFA855F7)));

    // Verify NO dev badges
    expect(find.text('DEV'), findsNothing);
    expect(find.text('DEV MODE'), findsNothing);
    expect(find.byIcon(Icons.developer_mode), findsNothing);
  });

  testWidgets('All Stores with partial dev stores shows purple top dev icon and purple store icon', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final stores = [
      {'id': 'store-1', 'name': 'Downtown Store', 'is_dev': true},
      {'id': 'store-2', 'name': 'Uptown Store', 'is_dev': false},
    ];

    await tester.pumpWidget(buildTestApp(stores: stores, currentStoreId: null));
    await tester.pumpAndSettle();

    expect(find.text('All Stores'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget); // Top badge
    final devIcon = tester.widget<Icon>(find.byIcon(Icons.developer_mode));
    expect(devIcon.color, const Color(0xFFA855F7));

    // Store icon is purple
    final storeIcon = tester.widget<Icon>(find.byIcon(Icons.store));
    expect(storeIcon.color, const Color(0xFFA855F7));

    // Verify NO badge below the store name
    expect(find.text('DEV MODE'), findsNothing);
    expect(find.text('DEV (1/2)'), findsNothing);
  });

  testWidgets('All Stores where all are dev stores shows purple icons and no badge below store name', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final stores = [
      {'id': 'store-1', 'name': 'Downtown Store', 'is_dev': true},
      {'id': 'store-2', 'name': 'Uptown Store', 'is_dev': true},
    ];

    await tester.pumpWidget(buildTestApp(stores: stores, currentStoreId: null));
    await tester.pumpAndSettle();

    expect(find.text('All Stores'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);

    final storeIcon = tester.widget<Icon>(find.byIcon(Icons.store));
    expect(storeIcon.color, const Color(0xFFA855F7));

    expect(find.text('DEV MODE'), findsNothing);
  });

  testWidgets('All Stores where none are dev stores shows no DEV badges', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final stores = [
      {'id': 'store-1', 'name': 'Downtown Store', 'is_dev': false},
      {'id': 'store-2', 'name': 'Uptown Store', 'is_dev': false},
    ];

    await tester.pumpWidget(buildTestApp(stores: stores, currentStoreId: null));
    await tester.pumpAndSettle();

    expect(find.text('All Stores'), findsOneWidget);
    expect(find.text('DEV'), findsNothing);
    expect(find.text('DEV MODE'), findsNothing);
    expect(find.byIcon(Icons.developer_mode), findsNothing);
  });
}
