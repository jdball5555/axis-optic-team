import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/ui/views/dashboard_view.dart';
import 'package:axis_team/ui/widgets/store_intro.dart';
import 'package:axis_team/ui/widgets/store_team_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('index links the store to its blueprint, which loads', () async {
    final index = await StoreIntros.index();
    expect(index['sample-store-a'], 'store_a.json');
    expect(index['sample-store-b'], 'store_b.json');
    final hwy = await StoreIntros.pickFor(['sample-store-b']);
    expect(hwy!.name, 'Sample Store B');
    expect(hwy.count, greaterThan(100));

    final intro = await StoreIntros.pickFor(['sample-store-a']);
    expect(intro, isNotNull);
    expect(intro!.count, greaterThan(100));
    expect(intro.name, isNotEmpty);
  });

  test('only linked stores get an intro', () async {
    expect(await StoreIntros.pickFor(['not-a-store']), isNull);
    expect(
      StoreIntros.storeIdsOf({
        'storeId': 'a',
        'owned_stores': ['b', 'a'],
      }),
      ['a', 'b'],
    );
  });

  testWidgets('the intro plays through and hands over to the app', (
    tester,
  ) async {
    final intro = (await tester.runAsync(
      () => StoreIntros.pickFor(['sample-store-a']),
    ))!;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StoreIntroScreen(
          intro: intro,
          ready: true,
          onDone: () => done = true,
        ),
      ),
    );
    expect(find.text('TAP TO ENTER'), findsOneWidget);

    // Orbit, turn to the door, fly in, fade.
    for (var i = 0; i < 12 * 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (done) break;
    }
    expect(done, isTrue);
  });

  testWidgets('a tap still flies through the door, just quickly', (
    tester,
  ) async {
    final intro = (await tester.runAsync(
      () => StoreIntros.pickFor(['sample-store-a']),
    ))!;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StoreIntroScreen(
          intro: intro,
          ready: true,
          onDone: () => done = true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(StoreIntroScreen));

    // Not instantly gone: it turns to the door and flies in first...
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    expect(done, isFalse);
    expect(find.text('TAP TO ENTER'), findsOneWidget);

    // ...but it's in within about a second and a half.
    var ms = 316;
    while (!done && ms < 3000) {
      await tester.pump(const Duration(milliseconds: 16));
      ms += 16;
    }
    expect(done, isTrue);
    expect(ms, lessThan(1600));
  });

  testWidgets(
    'pressing Login shows the intro at once; a failed login hides it',
    (tester) async {
      await tester.runAsync(StoreIntros.preloadAll);
      final container = ProviderContainer(
        overrides: [
          allStoresStreamProvider.overrideWith((ref) => const Stream.empty()),
          allStoreUsersStreamProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: StoreIntroGate(child: Text('login page')),
          ),
        ),
      );
      expect(find.byType(StoreIntroScreen), findsNothing);

      container.read(storeIntroRequestProvider.notifier).state = [
        'sample-store-a',
      ];
      await tester.pump();
      expect(find.byType(StoreIntroScreen), findsOneWidget);
      expect(find.text('LOADING YOUR STORE'), findsOneWidget);

      container.read(storeIntroRequestProvider.notifier).state = null;
      await tester.pump();
      expect(find.byType(StoreIntroScreen), findsNothing);
    },
  );

  testWidgets('a store tile fills the tile with the blueprint and its count', (
    tester,
  ) async {
    await tester.runAsync(StoreIntros.preloadAll);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeMembersProvider('sample-store-a').overrideWith(
            (ref) => Stream.value([
              for (var i = 0; i < 24; i++) UserModel(id: '$i'),
            ]),
          ),
        ],
        child: const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 350,
              height: 250,
              child: StoreTeamTile(
                storeId: 'sample-store-a',
                name: 'Sample Store A',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('SAMPLE STORE A'), findsOneWidget);
    expect(find.textContaining('24'), findsOneWidget);
    expect(find.byType(StoreOrbit), findsOneWidget);
    // The blueprint covers the whole tile.
    expect(tester.getSize(find.byType(StoreOrbit)), const Size(350, 250));
  });

  testWidgets(
    'the dashboard offers a tile for each linked store, on any store\'s dashboard',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      await tester.runAsync(StoreIntros.preloadAll);

      const linked = 'sample-store-a';
      final container = ProviderContainer(
        overrides: [
          // Looking at the *other* store's dashboard.
          currentStoreIdProvider.overrideWith((ref) => 'north'),
          allStoresStreamProvider.overrideWith(
            (ref) => Stream.value([
              {'id': linked, 'name': 'Sample Store A'},
              {'id': 'north', 'name': 'North'},
            ]),
          ),
          storeStreamProvider('north').overrideWith(
            (ref) => Stream.value({'id': 'north', 'name': 'North'}),
          ),
          currentMembersProvider.overrideWith(
            (ref) => const AsyncValue.data(<UserModel>[]),
          ),
          rosterNeedsStreamProvider.overrideWith(
            (ref) => Stream.value(<String, dynamic>{}),
          ),
          storeMembersProvider(linked).overrideWith(
            (ref) => Stream.value([UserModel(id: 'a'), UserModel(id: 'b')]),
          ),
          currentUserProvider.overrideWith(
            (ref) => {
              'id': 'owner',
              'owned_stores': [linked, 'north'],
            },
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: DashboardView(isConfigMode: true)),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Stores'), findsOneWidget);
      expect(find.text('SAMPLE STORE A'), findsOneWidget); // its tile's preview
      expect(find.text('NORTH'), findsNothing); // no animation, no tile
      expect(find.byType(StoreTeamTile), findsOneWidget);
    },
  );

  testWidgets(
    'the app underneath is hidden while covered and shown for the fly-in',
    (tester) async {
      await tester.runAsync(StoreIntros.preloadAll);
      final container = ProviderContainer(
        overrides: [
          allStoresStreamProvider.overrideWith((ref) => Stream.value(const [])),
          allStoreUsersStreamProvider.overrideWith(
            (ref) => Stream.value(const <UserModel>[]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: StoreIntroGate(child: Text('the app')),
          ),
        ),
      );
      expect(find.text('the app'), findsOneWidget);

      container.read(currentUserProvider.notifier).state = {
        'id': 'u',
        'owned_stores': ['sample-store-a'],
      };
      await tester.pump();
      expect(find.byType(StoreIntroScreen), findsOneWidget);
      expect(find.text('the app'), findsNothing); // not drawn under the intro

      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(StoreIntroScreen));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.text('the app'),
        findsOneWidget,
      ); // drawing again to be revealed

      for (
        var i = 0;
        i < 120 && find.byType(StoreIntroScreen).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(StoreIntroScreen), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    },
  );
}
