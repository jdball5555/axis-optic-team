import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axis_team/ui/views/rosters_view.dart';
import 'package:axis_team/ui/views/dashboard_view.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/providers/app_providers.dart';

/// Adding a roster tile next asks whether to split any title / tag out
/// within it; answer "No".
Future<void> skipSplitQuestion(WidgetTester tester) async {
  if (find.text('Yes, Choose Which').evaluate().isEmpty) return;
  await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    RostersView.clearSessionCache();
  });
  final sampleUsers = [
    UserModel(
      id: 'u1',
      firstName: 'Alice',
      lastName: 'Smith',
      store: 'store_1',
      position: 'Front of House',
      title: 'Cashier',
      avgShifts: '4',
    ),
    UserModel(
      id: 'u2',
      firstName: 'Bob',
      lastName: 'Jones',
      store: 'store_1',
      position: 'Kitchen',
      title: 'Cook',
      avgShifts: '5',
    ),
  ];

  final sampleStores = [
    {'id': 'store_1', 'name': 'Main Street Store'},
  ];

  Widget createWidgetUnderTest({
    List<UserModel>? users,
    List<Map<String, dynamic>>? stores,
    String? currentStoreId = 'store_1',
    StoreSettingsModel? store1Settings,
    StoreSettingsModel? store2Settings,
    bool isConfigMode = false,
    bool useRouter = false,
  }) {
    return ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => {
            'id': 'owner_1',
            'first_name': 'Owner',
            'last_name': 'User',
            'owned_stores': ['store_1', 'store_2'],
          },
        ),
        currentMembersProvider.overrideWith(
          (ref) => AsyncValue.data(users ?? sampleUsers),
        ),
        allStoresStreamProvider.overrideWith(
          (ref) => Stream.value(stores ?? sampleStores),
        ),
        currentStoreIdProvider.overrideWith((ref) => currentStoreId),
        rosterNeedsStreamProvider.overrideWith(
          (ref) => Stream.value({
            'store_1_Front of House': 2,
            'store_1_Kitchen': 3,
            'store_1_Trainer': 1,
            'store_2_Drive Thru': 2,
          }),
        ),
        specificStoreSettingsProvider('store_1').overrideWith(
          (ref) => Stream.value(
            store1Settings ??
                const StoreSettingsModel(
                  positions: ['Front of House', 'Kitchen'],
                  titles: [
                    TitleConfig(id: 't1', name: 'Cashier', color: 'Blue'),
                    TitleConfig(id: 't2', name: 'Cook', color: 'Red'),
                  ],
                ),
          ),
        ),
        if (store2Settings != null)
          specificStoreSettingsProvider('store_2').overrideWith(
            (ref) => Stream.value(store2Settings),
          ),
      ],
      child: useRouter
          ? MaterialApp.router(
              routerConfig: GoRouter(
                initialLocation: isConfigMode ? '/rosters/config' : '/rosters',
                routes: [
                  GoRoute(
                    path: '/rosters',
                    builder: (context, state) =>
                        const RostersView(isConfigMode: false),
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
            )
          : MaterialApp(
              home: RostersView(isConfigMode: isConfigMode),
            ),
    );
  }

  testWidgets('RostersView renders configuration button and toggles editing mode',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Verify title and customize button
    expect(find.text('Store Rosters & Staffing (6 Days/Week)'), findsOneWidget);
    expect(find.byIcon(Icons.dashboard_customize), findsOneWidget);

    // Verify both positions are visible
    expect(find.text('FRONT OF HOUSE'), findsOneWidget);
    expect(find.text('KITCHEN'), findsOneWidget);
    expect(find.text('Alice Smith'), findsOneWidget);
    expect(find.text('Bob Jones'), findsOneWidget);

    // Tap customize button to enter edit mode
    await tester.tap(find.byIcon(Icons.dashboard_customize));
    await tester.pumpAndSettle();

    // Verify edit mode actions
    expect(find.text('Reset to Default'), findsOneWidget);
    expect(find.text('Save Layout'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Tap cancel to exit edit mode
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dashboard_customize), findsOneWidget);
    expect(find.text('Save Layout'), findsNothing);
  });

  testWidgets(
      'Default layout clumps tiles at (0, 0) with no gaps, separating standard and custom rows',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final usersWithIsolated = [
      UserModel(
        id: 'u1',
        firstName: 'Alice',
        store: 'store_1',
        position: 'Front of House',
        title: 'Cashier',
      ),
      UserModel(
        id: 'u2',
        firstName: 'Bob',
        store: 'store_1',
        position: 'Kitchen',
        title: 'Cook',
      ),
      UserModel(
        id: 'u3',
        firstName: 'Charlie',
        store: 'store_1',
        position: 'Front of House',
        title: 'Trainer', // Isolated roster
      ),
    ];

    const settings = StoreSettingsModel(
      positions: ['Front of House', 'Kitchen'],
      titles: [
        TitleConfig(id: 't1', name: 'Cashier', color: 'Blue'),
        TitleConfig(id: 't2', name: 'Cook', color: 'Red'),
        TitleConfig(id: 't3', name: 'Trainer', color: 'Purple', isolatedRoster: true),
      ],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(
        users: usersWithIsolated,
        store1Settings: settings,
      ),
    );
    await tester.pumpAndSettle();

    // Find the Positioned widgets
    final positionedWidgets =
        tester.widgetList<Positioned>(find.byType(Positioned)).toList();

    // Row 0 (Standard): Front of House at x=0, y=0; Kitchen at x=350, y=0
    final fohPos = positionedWidgets.firstWhere(
      (p) => p.left == 0.0 && p.top == 0.0,
    );
    expect(fohPos, isNotNull);
    expect(fohPos.width, 350.0);
    expect(fohPos.height, 550.0);

    final kitchenPos = positionedWidgets.firstWhere(
      (p) => p.left == 350.0 && p.top == 0.0,
    );
    expect(kitchenPos, isNotNull);
    expect(kitchenPos.width, 350.0);
    expect(kitchenPos.height, 550.0);

    // Row 1 (Custom): Trainer at x=0, y=550.0 (directly below row 0)
    final trainerPos = positionedWidgets.firstWhere(
      (p) => p.left == 0.0 && p.top == 550.0,
    );
    expect(trainerPos, isNotNull);
    expect(trainerPos.width, 350.0);
    expect(trainerPos.height, 550.0);
  });

  testWidgets(
      'All Stores mode defaults to Store 1 standard row, Store 1 custom row, then Store 2 standard row',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final multiStoreUsers = [
      UserModel(
        id: 'u1',
        firstName: 'Alice',
        store: 'store_1',
        position: 'Front of House',
        title: 'Cashier',
      ),
      UserModel(
        id: 'u2',
        firstName: 'Charlie',
        store: 'store_1',
        position: 'Front of House',
        title: 'Trainer', // Isolated
      ),
      UserModel(
        id: 'u3',
        firstName: 'Alex',
        store: 'store_2',
        position: 'Drive Thru',
        title: 'Cashier',
      ),
    ];

    const store1Settings = StoreSettingsModel(
      positions: ['Front of House'],
      titles: [
        TitleConfig(id: 't1', name: 'Cashier', color: 'Blue'),
        TitleConfig(id: 't3', name: 'Trainer', color: 'Purple', isolatedRoster: true),
      ],
    );

    const store2Settings = StoreSettingsModel(
      positions: ['Drive Thru'],
      titles: [
        TitleConfig(id: 't4', name: 'Cashier', color: 'Blue'),
      ],
    );

    final multiStores = [
      {'id': 'store_1', 'name': 'First Store'},
      {'id': 'store_2', 'name': 'Second Store'},
    ];

    await tester.pumpWidget(
      createWidgetUnderTest(
        users: multiStoreUsers,
        stores: multiStores,
        currentStoreId: null, // All stores
        store1Settings: store1Settings,
        store2Settings: store2Settings,
      ),
    );
    await tester.pumpAndSettle();

    final positionedWidgets =
        tester.widgetList<Positioned>(find.byType(Positioned)).toList();

    // Store 1 standard row at y=0
    expect(
      positionedWidgets.any((p) => p.left == 0.0 && p.top == 0.0),
      isTrue,
    );

    // Store 1 custom row at y=550
    expect(
      positionedWidgets.any((p) => p.left == 0.0 && p.top == 550.0),
      isTrue,
    );

    // Store 2 standard row at y=1100
    expect(
      positionedWidgets.any((p) => p.left == 0.0 && p.top == 1100.0),
      isTrue,
    );
  });

  testWidgets(
      'Roster tiles default per working time: a row for Day, a row for Night, and a row for Other',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final users = [
      UserModel(
        id: 'u1',
        firstName: 'Alice',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
      ),
      UserModel(
        id: 'u2',
        firstName: 'Bob',
        store: 'store_1',
        position: 'Kitchen',
        workingTime: 'Night',
      ),
      UserModel(
        id: 'u3',
        firstName: 'Charlie',
        store: 'store_1',
        position: 'Kitchen',
        workingTime: 'Other',
      ),
      UserModel(
        id: 'u4',
        firstName: 'Diana',
        store: 'store_1',
        position: 'Front of House',
        title: 'Trainer', // Isolated role
      ),
    ];

    const settings = StoreSettingsModel(
      positions: ['Front of House', 'Kitchen'],
      workingTimes: ['Day', 'Night'],
      titles: [
        TitleConfig(id: 't1', name: 'Trainer', color: 'Purple', isolatedRoster: true),
      ],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(
        users: users,
        store1Settings: settings,
      ),
    );
    await tester.pumpAndSettle();

    final positionedWidgets =
        tester.widgetList<Positioned>(find.byType(Positioned)).toList();

    // Row 0 (Day) at y=0.0: Front of House (x=0) and Kitchen (x=350)
    expect(positionedWidgets.any((p) => p.left == 0.0 && p.top == 0.0), isTrue);
    expect(positionedWidgets.any((p) => p.left == 350.0 && p.top == 0.0), isTrue);

    // Row 1 (Night) at y=550.0: Front of House (x=0) and Kitchen (x=350)
    expect(positionedWidgets.any((p) => p.left == 0.0 && p.top == 550.0), isTrue);
    expect(positionedWidgets.any((p) => p.left == 350.0 && p.top == 550.0), isTrue);

    // Row 2 (Other / Extra tiles) at y=1100.0:
    // Only extra tiles (Kitchen with Charlie and Trainer isolated role), NO "Other" for Front of House!
    expect(positionedWidgets.any((p) => p.left == 0.0 && p.top == 1100.0), isTrue);
    expect(positionedWidgets.any((p) => p.left == 350.0 && p.top == 1100.0), isTrue);
    expect(positionedWidgets.any((p) => p.left == 700.0 && p.top == 1100.0), isFalse);
  });

  testWidgets(
      'Dashboard default layout matches 3x3 grid screenshot with no borders around edges',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final sampleUsers = [
      UserModel(
        id: 'u1',
        firstName: 'Alice',
        lastName: 'Smith',
        store: 'store_1',
        position: 'SVC',
        workingTime: 'Daytime',
        designation: 'Adult',
        startDate: DateTime.now().subtract(const Duration(days: 400)),
        foodHandlersExpiration: DateTime.now().add(const Duration(days: 60)),
      ),
      UserModel(
        id: 'u2',
        firstName: 'Bob',
        lastName: 'Jones',
        store: 'store_1',
        position: 'DT',
        workingTime: 'Night',
        designation: 'College',
        startDate: DateTime.now().subtract(const Duration(days: 200)),
        foodHandlersExpiration: DateTime.now().subtract(const Duration(days: 5)),
      ),
      UserModel(
        id: 'u3',
        firstName: 'Charlie',
        lastName: 'Brown',
        store: 'store_1',
        position: 'KT',
        workingTime: 'Daytime',
        designation: 'High School',
        startDate: DateTime.now().subtract(const Duration(days: 50)),
      ),
    ];

    const sampleSettings = StoreSettingsModel(
      positions: ['SVC', 'DT', 'KT'],
      workingTimes: ['Daytime', 'Night'],
      designations: ['Adult', 'College', 'High School'],
    );

    final container = ProviderContainer(
      overrides: [
        currentStoreIdProvider.overrideWith((ref) => 'store_1'),
        allStoresStreamProvider.overrideWith(
          (ref) => Stream.value([
            {'id': 'store_1', 'name': 'Main Store', 'is_dev': false},
          ]),
        ),
        storeStreamProvider('store_1').overrideWith(
          (ref) => Stream.value({
            'id': 'store_1',
            'name': 'Main Store',
            'is_dev': false,
          }),
        ),
        currentMembersProvider.overrideWith(
          (ref) => AsyncValue.data(sampleUsers),
        ),
        rosterNeedsStreamProvider.overrideWith(
          (ref) => Stream.value(<String, dynamic>{'store_1_SVC': 10}),
        ),
        storeSettingsProvider.overrideWith(
          (ref) => Stream.value(sampleSettings),
        ),
        currentUserProvider.overrideWith(
          (ref) => {'id': 'user_1', 'first_name': 'Alex', 'last_name': 'Parker'},
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

    // Verify Row 1: Welcome quote, Average tenure, Roster staffing deficits
    expect(find.text('Hello, Alex!'), findsOneWidget);
    expect(find.text('AVERAGE TEAM MEMBER TENURE'), findsOneWidget);
    expect(find.text('ROSTER STAFFING DEFICITS'), findsOneWidget);

    // Verify Row 2: Working Time, Position, Designation distributions
    expect(find.text('Working Time Distribution'), findsOneWidget);
    expect(find.text('Position Distribution'), findsOneWidget);
    expect(find.text('Designation Distribution'), findsOneWidget);

    // Verify Row 3: Team Member Tenure, Permits, Tenure by Year
    expect(find.text('Team Member Tenure'), findsOneWidget);
    expect(find.text('Permits'), findsOneWidget);
    expect(find.text('Tenure by Year'), findsOneWidget);

    // Verify items in Positioned widgets have no outer 50px border (x starts at 0, y starts at 0)
    final positionedWidgets =
        tester.widgetList<Positioned>(find.byType(Positioned)).toList();

    // Col 0 at x=0
    expect(positionedWidgets.any((p) => p.left == 0.0 && p.top == 0.0), isTrue); // welcome_quote
    expect(positionedWidgets.any((p) => p.left == 0.0 && p.top == 150.0), isTrue); // working_time
    expect(positionedWidgets.any((p) => p.left == 0.0 && p.top == 400.0), isTrue); // tenure_dist

    // Col 1 at x=350
    expect(positionedWidgets.any((p) => p.left == 350.0 && p.top == 0.0), isTrue); // tenure
    expect(positionedWidgets.any((p) => p.left == 350.0 && p.top == 150.0), isTrue); // position
    expect(positionedWidgets.any((p) => p.left == 350.0 && p.top == 400.0), isTrue); // permit

    // Col 2 at x=700
    expect(positionedWidgets.any((p) => p.left == 700.0 && p.top == 0.0), isTrue); // deficits
    expect(positionedWidgets.any((p) => p.left == 700.0 && p.top == 150.0), isTrue); // designation
    expect(positionedWidgets.any((p) => p.left == 700.0 && p.top == 400.0), isTrue); // tenure_by_year
  });

  testWidgets(
      'RostersView in Config Mode renders sections, Trainer tiles, Titles, Tags, and Add/Added toggle',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const settings = StoreSettingsModel(
      workingTimes: ['Day', 'Night'],
      positions: ['Front of House', 'Kitchen'],
      titles: [
        TitleConfig(id: 't1', name: 'Director', color: 'Gold'),
      ],
      tags: [
        TitleConfig(id: 'tg1', name: 'Prep', color: 'Green'),
      ],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(
        isConfigMode: true,
        store1Settings: settings,
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title and Action button
    expect(find.text('Configure Rosters'), findsOneWidget);
    expect(find.text('Edit Roster Display'), findsOneWidget);

    // Verify Section Headers
    expect(find.text('Day Shifts'), findsOneWidget);
    expect(find.text('Night Shifts'), findsOneWidget);
    expect(find.text('Titles'), findsOneWidget);
    expect(find.text('Additional Tags'), findsOneWidget);

    // Verify Standard Positions & Trainer tile per working time
    expect(find.text('DAY - FRONT OF HOUSE'), findsOneWidget);
    expect(find.text('DAY - KITCHEN'), findsOneWidget);
    expect(find.text('DAY - TRAINER'), findsOneWidget);
    expect(find.text('NIGHT - FRONT OF HOUSE'), findsOneWidget);
    expect(find.text('NIGHT - KITCHEN'), findsOneWidget);
    expect(find.text('NIGHT - TRAINER'), findsOneWidget);

    // Verify Titles and Tags tiles
    expect(find.text('DIRECTOR'), findsOneWidget);
    expect(find.text('PREP'), findsOneWidget);

    // Verify "Add" and "Added" buttons are rendered
    expect(find.text('Add'), findsWidgets);
    expect(find.text('Added'), findsWidgets);

    // Tap on an "Add" button (e.g. Day Trainer) to toggle
    final addButtons = find.text('Add');
    expect(addButtons, findsWidgets);
    await tester.tap(addButtons.first);
    await tester.pumpAndSettle();

    // Verify isolation dialog appears for non-standard tile
    expect(find.text('Yes, Include in Both'), findsOneWidget);
    await tester.tap(find.text('Yes, Include in Both'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    // After adding, number of "Added" / "Added (Shared)" badges should be present
    expect(find.text('Added (Shared)'), findsWidgets);
  });

  testWidgets('RostersView canvas layout editing allows resizing a tile',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Enter layout editing mode
    await tester.tap(find.byIcon(Icons.dashboard_customize));
    await tester.pumpAndSettle();

    expect(find.text('Save Layout'), findsOneWidget);

    // Tap the first tile at (0,0) to select it
    await tester.tap(find.text('FRONT OF HOUSE'));
    await tester.pumpAndSettle();

    // Verify drag indicator resize handle appears
    final dragHandle = find.byIcon(Icons.drag_indicator);
    expect(dragHandle, findsOneWidget);

    // Drag the handle to resize width and height by +100px (2 grid increments)
    final gesture = await tester.startGesture(tester.getCenter(dragHandle));
    await gesture.moveBy(const Offset(50.0, 50.0));
    await tester.pump();
    await gesture.moveBy(const Offset(50.0, 50.0));
    await tester.pump();
    await gesture.moveBy(const Offset(50.0, 50.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Verify tile has resized to width 450.0 and height 650.0 (350 + 100, 550 + 100)
    final positionedWidgets =
        tester.widgetList<Positioned>(find.byType(Positioned)).toList();
    final resizedTile = positionedWidgets.firstWhere(
      (p) => p.left == 0.0 && p.top == 0.0,
    );
    expect(resizedTile.width, 450.0);
    expect(resizedTile.height, 650.0);
  });

  testWidgets(
      'Adding time-of-day Trainer tile places it at the end of that working time row and Edit Roster Display transitions to editing mode',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const settings = StoreSettingsModel(
      positions: ['Front of House', 'Kitchen'],
      workingTimes: ['Day', 'Night'],
    );

    final users = [
      UserModel(
        id: 'u1',
        firstName: 'Alice',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
      ),
      UserModel(
        id: 'u2',
        firstName: 'Bob',
        store: 'store_1',
        position: 'Kitchen',
        workingTime: 'Day',
      ),
      UserModel(
        id: 'u3',
        firstName: 'Charlie',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Night',
      ),
      UserModel(
        id: 'u4',
        firstName: 'Diana',
        store: 'store_1',
        position: 'Kitchen',
        workingTime: 'Night',
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => {
            'id': 'owner_1',
            'first_name': 'Owner',
            'last_name': 'User',
            'owned_stores': ['store_1'],
          },
        ),
        currentMembersProvider.overrideWith(
          (ref) => AsyncValue.data(users),
        ),
        allStoresStreamProvider.overrideWith(
          (ref) => Stream.value(sampleStores),
        ),
        currentStoreIdProvider.overrideWith((ref) => 'store_1'),
        rosterNeedsStreamProvider.overrideWith(
          (ref) => Stream.value({}),
        ),
        specificStoreSettingsProvider('store_1').overrideWith(
          (ref) => Stream.value(settings),
        ),
      ],
    );

    final router = GoRouter(
      initialLocation: '/rosters/config',
      routes: [
        GoRoute(
          path: '/rosters',
          builder: (context, state) => const RostersView(isConfigMode: false),
          routes: [
            GoRoute(
              path: 'config',
              builder: (context, state) =>
                  const RostersView(isConfigMode: true),
            ),
          ],
        ),
      ],
    );

    // 1. Render in Config Mode via GoRouter
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify sections and trainer tiles in config
    expect(find.text('DAY - TRAINER'), findsWidgets);
    expect(find.text('NIGHT - TRAINER'), findsWidgets);
    expect(find.text('Edit Roster Display'), findsOneWidget);

    // Standard positions are added by default; Day - Trainer, Night - Trainer, and Trainer have "Add" buttons
    final addButtons = find.text('Add');
    expect(addButtons, findsNWidgets(3));

    // Tap first Add button (Day - Trainer)
    await tester.tap(addButtons.at(0));
    await tester.pumpAndSettle();

    // Verify isolation dialog appears and select "Yes, Include in Both"
    expect(find.text('Yes, Include in Both'), findsOneWidget);
    await tester.tap(find.text('Yes, Include in Both'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    // Now 2 Add buttons remain (Night - Trainer, Additional Tag Trainer)
    expect(find.text('Add'), findsNWidgets(2));
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();

    expect(find.text('Yes, Include in Both'), findsOneWidget);
    await tester.tap(find.text('Yes, Include in Both'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    // Tap "Edit Roster Display" button
    await tester.tap(find.text('Edit Roster Display'));
    await tester.pumpAndSettle();

    // Verify it transitioned to layout editing mode!
    expect(find.text('Save Layout'), findsOneWidget);
    expect(find.text('Reset to Default'), findsOneWidget);
    expect(find.text('Add to Roster'), findsOneWidget);

    final positionedWidgets =
        tester.widgetList<Positioned>(find.byType(Positioned)).toList();

    // Day row is at y=0.0. Positions are:
    // Front of House at (0.0, 0.0), Kitchen at (350.0, 0.0), Day Trainer at (700.0, 0.0)
    final dayTrainerPos = positionedWidgets.firstWhere(
      (p) => p.left == 700.0 && p.top == 0.0,
    );
    expect(dayTrainerPos, isNotNull);

    // Night row is at y=550.0. Positions are:
    // Front of House at (0.0, 550.0), Kitchen at (350.0, 550.0), Night Trainer at (700.0, 550.0)
    final nightTrainerPos = positionedWidgets.firstWhere(
      (p) => p.left == 700.0 && p.top == 550.0,
    );
    expect(nightTrainerPos, isNotNull);
  });

  testWidgets(
      'A store\'s default roster is laid out exactly like its part of All Stores, with no other store\'s tiles',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final stores = [
      {'id': 'store_1', 'name': 'Main'},
      {'id': 'store_2', 'name': 'North'},
    ];
    final users = [
      UserModel(id: 'a', firstName: 'Ann', store: 'store_1', position: 'Front of House', workingTime: 'Day', avgShifts: '5'),
      UserModel(id: 'b', firstName: 'Bo', store: 'store_2', position: 'Drive Thru', workingTime: 'Day', avgShifts: '5'),
    ];
    const s1 = StoreSettingsModel(
      workingTimes: ['Day', 'Night'],
      positions: ['Front of House', 'Kitchen'],
      titles: [TitleConfig(id: 'm', name: 'Manager', isolatedRoster: true)],
    );
    const s2 = StoreSettingsModel(workingTimes: ['Day'], positions: ['Drive Thru']);
    const s1Tiles = [
      'DAY - FRONT OF HOUSE',
      'DAY - KITCHEN',
      'NIGHT - FRONT OF HOUSE',
      'NIGHT - KITCHEN',
      'MANAGER',
    ];

    Map<String, Offset> layoutOf(String prefix) {
      final first = tester.getTopLeft(find.text('${prefix}DAY - FRONT OF HOUSE'));
      return {
        for (final t in s1Tiles)
          t: tester.getTopLeft(find.text('$prefix$t')) - first,
      };
    }

    // One store.
    await tester.pumpWidget(createWidgetUnderTest(
      users: users,
      stores: stores,
      store1Settings: s1,
      store2Settings: s2,
    ));
    await tester.pumpAndSettle();
    expect(find.text('DAY - DRIVE THRU'), findsNothing);
    final single = layoutOf('');

    // All Stores.
    await tester.pumpWidget(const SizedBox());
    RostersView.clearSessionCache();
    await tester.pumpWidget(createWidgetUnderTest(
      users: users,
      stores: stores,
      currentStoreId: null,
      store1Settings: s1,
      store2Settings: s2,
    ));
    await tester.pumpAndSettle();
    expect(find.text('NORTH - DAY - DRIVE THRU'), findsOneWidget);
    final all = layoutOf('MAIN - ');

    expect(all, single);
  });

  testWidgets(
      'Adding a tile asks which titles / tags to split within it, and groups them',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final testMembers = [
      UserModel(
        id: 'u_lead',
        firstName: 'Lee',
        lastName: 'Lead',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
        title: 'Shift Lead',
        avgShifts: '5',
      ),
      UserModel(
        id: 'u_prep',
        firstName: 'Pat',
        lastName: 'Prep',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
        additionalTags: ['Prep'],
        avgShifts: '5',
      ),
      UserModel(
        id: 'u_regular',
        firstName: 'Sam',
        lastName: 'Staff',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
        avgShifts: '4',
      ),
    ];

    const settings = StoreSettingsModel(
      workingTimes: ['Day'],
      positions: ['Front of House', 'Kitchen'],
      titles: [TitleConfig(id: 't_sl', name: 'Shift Lead', color: 'Gold')],
      tags: [TitleConfig(id: 'tg_prep', name: 'Prep', color: 'Green')],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(
        users: testMembers,
        isConfigMode: true,
        useRouter: true,
        store1Settings: settings,
      ),
    );
    await tester.pumpAndSettle();

    // Remove the default "Day - Front of House" tile, then add it back.
    await tester.tap(find.text('Added').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();

    // A standard position skips the isolation question but asks about splits.
    expect(find.text('Yes, Include in Both'), findsNothing);
    expect(
      find.text('Split anyone within "Day - Front of House"?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Yes, Choose Which'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Shift Lead')),
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('Prep')));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Added · Split'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to Rosters'));
    await tester.pumpAndSettle();

    // Lee (title) and Pat (additional tag) each get their own group.
    expect(find.text('SHIFT LEAD (1)'), findsOneWidget);
    expect(find.text('PREP (1)'), findsOneWidget);
    expect(find.text('Sam Staff'), findsOneWidget);
  });

  testWidgets(
      'Tiles added before the split question keep the old Split in Area setting',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      createWidgetUnderTest(
        users: [
          UserModel(
            id: 'u_lead',
            firstName: 'Lee',
            lastName: 'Lead',
            store: 'store_1',
            position: 'Front of House',
            workingTime: 'Day',
            title: 'Shift Lead',
            avgShifts: '5',
          ),
        ],
        store1Settings: const StoreSettingsModel(
          workingTimes: ['Day'],
          positions: ['Front of House'],
          titles: [
            TitleConfig(id: 't_sl', name: 'Shift Lead', splitInArea: true),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SHIFT LEAD (1)'), findsOneWidget);
  });

  testWidgets(
      'Non-standard tiles trigger isolation popup dialog, supporting Shared vs Isolated member placement',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final testMembers = [
      UserModel(
        id: 'u_trainer',
        firstName: 'Tom',
        lastName: 'Trainer',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
        additionalTags: ['Trainer'],
        avgShifts: '5',
      ),
      UserModel(
        id: 'u_regular',
        firstName: 'Sam',
        lastName: 'Staff',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
        avgShifts: '4',
      ),
    ];

    const settings = StoreSettingsModel(
      workingTimes: ['Day'],
      positions: ['Front of House', 'Kitchen'],
      titles: [
        TitleConfig(id: 't_dir', name: 'Director', color: 'Gold'),
      ],
      tags: [
        TitleConfig(id: 'tg_prep', name: 'Prep', color: 'Green'),
      ],
    );

    // 1. Render in Config Mode
    await tester.pumpWidget(
      createWidgetUnderTest(
        users: testMembers,
        isConfigMode: true,
        useRouter: true,
        store1Settings: settings,
      ),
    );
    await tester.pumpAndSettle();

    // Verify sections
    expect(find.text('Day Shifts'), findsOneWidget);
    expect(find.text('Titles'), findsOneWidget);
    expect(find.text('Additional Tags'), findsOneWidget);

    // Verify "Trainer" is present under Additional Tags as well as "Day - Trainer" under Day Shifts
    expect(find.text('DAY - TRAINER'), findsOneWidget);
    expect(find.text('TRAINER'), findsOneWidget);

    // Standard position Front of House is added by default
    expect(find.text('Added'), findsWidgets);

    // Tap to add "DAY - TRAINER"
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();

    // Verify isolation dialog appears asking if members should also be in general roster
    expect(
      find.text('Include "Day - Trainer" in General Roster?'),
      findsOneWidget,
    );
    expect(find.text('Yes, Include in Both'), findsOneWidget);
    expect(find.text('No, Only on This Roster'), findsOneWidget);

    // Select "Yes, Include in Both" (Shared)
    await tester.tap(find.text('Yes, Include in Both'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    // Verify badge displays "Added (Shared)"
    expect(find.text('Added (Shared)'), findsOneWidget);

    // Switch back to normal Rosters view
    await tester.tap(find.byTooltip('Back to Rosters'));
    await tester.pumpAndSettle();

    // In shared mode: Tom Trainer should appear in BOTH Day - Trainer and Day - Front of House!
    // Since Tom is in both tiles, his name 'Tom Trainer' appears twice on the board
    expect(find.text('Tom Trainer'), findsNWidgets(2));
    expect(find.text('Sam Staff'), findsOneWidget);

    // Return to Config Mode
    await tester.tap(find.byIcon(Icons.dashboard_customize));
    await tester.pumpAndSettle();

    // Tap "DAY - TRAINER" badge to remove it
    await tester.tap(find.text('Added (Shared)'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Now it should show "Add" again
    expect(find.text('Added (Shared)'), findsNothing);

    // Tap "DAY - TRAINER" again to re-add
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();

    // Dialog appears again!
    expect(
      find.text('Include "Day - Trainer" in General Roster?'),
      findsOneWidget,
    );

    // This time, select "No, Only on This Roster" (Isolated)
    await tester.tap(find.text('No, Only on This Roster'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    // Verify badge displays "Added (Isolated)"
    expect(find.text('Added (Isolated)'), findsOneWidget);

    // Switch back to normal Rosters view
    await tester.tap(find.byTooltip('Back to Rosters'));
    await tester.pumpAndSettle();

    // In isolated mode: Tom Trainer is isolated from Day - Front of House!
    // He should appear ONLY in Day - Trainer (1 time total)
    expect(find.text('Tom Trainer'), findsOneWidget);
    expect(find.text('Sam Staff'), findsOneWidget);
  });

  testWidgets('Trainer appears under Additional Tags and can be selected/unselected',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const settings = StoreSettingsModel(
      workingTimes: ['Day'],
      positions: ['Front of House'],
      titles: [],
      tags: [
        TitleConfig(id: 'tg_truck', name: 'Truck', color: 'Blue'),
      ],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(
        isConfigMode: true,
        store1Settings: settings,
      ),
    );
    await tester.pumpAndSettle();

    // Verify "Additional Tags" section exists
    expect(find.text('Additional Tags'), findsOneWidget);

    // Verify Truck and Trainer both appear in Additional Tags
    expect(find.text('TRUCK'), findsOneWidget);
    expect(find.text('TRAINER'), findsOneWidget);

    // Tap "TRAINER" to add it
    await tester.tap(find.text('TRAINER'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Dialog appears!
    expect(
      find.text('Include "Trainer" in General Roster?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Yes, Include in Both'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    // Verify it is now Added (Shared)
    expect(find.text('Added (Shared)'), findsOneWidget);

    // Tap "TRAINER" again to unselect / remove it
    await tester.tap(find.text('TRAINER'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Verify it is unselected
    expect(find.text('Added (Shared)'), findsNothing);
  });

  testWidgets(
      'Configure Rosters scrollbar touches right screen edge and section headers remain pinned at top when scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const settings = StoreSettingsModel(
      workingTimes: ['Day', 'Night'],
      positions: ['Front of House', 'Kitchen'],
      titles: [
        TitleConfig(id: 't1', name: 'Director', color: 'Gold'),
      ],
      tags: [
        TitleConfig(id: 'tg1', name: 'Prep', color: 'Green'),
      ],
    );

    await tester.pumpWidget(
      createWidgetUnderTest(
        isConfigMode: true,
        store1Settings: settings,
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify scroll view / scrollbar extends all the way to the right edge (x == 1000)
    final customScrollView = find.byType(CustomScrollView);
    expect(customScrollView, findsOneWidget);
    final scrollViewRect = tester.getRect(customScrollView);
    expect(scrollViewRect.right, equals(1000.0));

    // 2. Section header is pinned to top of scroll area
    final headerFinder = find.text('Day Shifts');
    expect(headerFinder, findsOneWidget);
    final initialHeaderY = tester.getTopLeft(headerFinder).dy;

    // 3. Scroll down by 250px
    await tester.drag(customScrollView, const Offset(0, -250));
    await tester.pumpAndSettle();

    // 4. Header remains pinned at the top of the scroll viewport!
    expect(headerFinder, findsOneWidget);
    expect(tester.getTopLeft(headerFinder).dy, equals(initialHeaderY));
  });

  testWidgets(
      'When additional tag Trainer tile is isolated, trainers appear ONLY on that singular tile',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const settings = StoreSettingsModel(
      workingTimes: ['Day', 'Night'],
      positions: ['Front of House', 'Kitchen'],
      tags: [
        TitleConfig(id: 'tg1', name: 'Trainer', color: 'Purple'),
      ],
    );

    final users = [
      UserModel(
        id: 'u1',
        firstName: 'Alice',
        lastName: 'TrainerDay',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
        additionalTags: ['Trainer'],
      ),
      UserModel(
        id: 'u2',
        firstName: 'Bob',
        lastName: 'RegularDay',
        store: 'store_1',
        position: 'Kitchen',
        workingTime: 'Day',
        additionalTags: [],
      ),
      UserModel(
        id: 'u3',
        firstName: 'Charlie',
        lastName: 'TrainerNight',
        store: 'store_1',
        position: 'Kitchen',
        workingTime: 'Night',
        additionalTags: ['Trainer'],
      ),
    ];

    await tester.pumpWidget(
      createWidgetUnderTest(
        isConfigMode: true,
        useRouter: true,
        store1Settings: settings,
        users: users,
      ),
    );
    await tester.pumpAndSettle();

    // 1. Add "Day - Trainer" time-of-day tile
    final dayTrainerTile = find.text('DAY - TRAINER');
    expect(dayTrainerTile, findsWidgets);
    await tester.tap(dayTrainerTile.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Select "Yes, Include in Both" for Day - Trainer
    expect(find.text('Include "Day - Trainer" in General Roster?'), findsOneWidget);
    await tester.tap(find.text('Yes, Include in Both'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    // 2. Scroll down and tap Additional Tags TRAINER tile
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final tagTrainerTile = find.text('TRAINER');
    expect(tagTrainerTile, findsWidgets);
    await tester.tap(tagTrainerTile.last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // 3. Isolation dialog appears for Trainer
    expect(find.text('Include "Trainer" in General Roster?'), findsOneWidget);

    // Tap "No, Only on This Roster"
    await tester.tap(find.text('No, Only on This Roster'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    expect(find.text('Added (Isolated)'), findsOneWidget);

    // 4. Tap "Edit Roster Display" to navigate back to /rosters
    await tester.tap(find.text('Edit Roster Display'));
    await tester.pumpAndSettle();

    // 5. Verify members on board:
    // Alice TrainerDay should appear ONLY ONCE on the entire board
    expect(find.text('Alice TrainerDay'), findsOneWidget);

    // Charlie TrainerNight should appear ONLY ONCE on the entire board
    expect(find.text('Charlie TrainerNight'), findsOneWidget);

    // Bob RegularDay appears once on the board (under Kitchen)
    expect(find.text('Bob RegularDay'), findsOneWidget);
  });

  testWidgets(
      'When a tag tile (e.g. Seasonal) is isolated, those members appear ONLY in isolated tiles and NOT in time-of-day trainer tiles or standard positions',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const settings = StoreSettingsModel(
      workingTimes: ['Day'],
      positions: ['Front of House', 'Kitchen'],
      tags: [
        TitleConfig(id: 'tg_s', name: 'Seasonal', color: 'Green'),
        TitleConfig(id: 'tg_t', name: 'Trainer', color: 'Purple'),
      ],
    );

    final users = [
      UserModel(
        id: 'u1',
        firstName: 'Alice',
        lastName: 'SeasonalTrainer',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
        additionalTags: ['Seasonal', 'Trainer'],
      ),
      UserModel(
        id: 'u2',
        firstName: 'Bob',
        lastName: 'StandardTrainer',
        store: 'store_1',
        position: 'Front of House',
        workingTime: 'Day',
        additionalTags: ['Trainer'],
      ),
    ];

    await tester.pumpWidget(
      createWidgetUnderTest(
        isConfigMode: true,
        useRouter: true,
        store1Settings: settings,
        users: users,
      ),
    );
    await tester.pumpAndSettle();

    // 1. Add "Day - Trainer" time-of-day tile (shared / non-isolated)
    final dayTrainerTile = find.text('DAY - TRAINER');
    expect(dayTrainerTile, findsWidgets);
    await tester.tap(dayTrainerTile.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Include "Day - Trainer" in General Roster?'), findsOneWidget);
    await tester.tap(find.text('Yes, Include in Both'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    // 2. Scroll down and tap Additional Tags SEASONAL tile
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final seasonalTile = find.text('SEASONAL');
    expect(seasonalTile, findsWidgets);
    await tester.tap(seasonalTile.last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // 3. Isolation dialog appears for Seasonal
    expect(find.text('Include "Seasonal" in General Roster?'), findsOneWidget);

    // Tap "No, Only on This Roster" -> isolated!
    await tester.tap(find.text('No, Only on This Roster'));
    await tester.pumpAndSettle();
    await skipSplitQuestion(tester);

    expect(find.text('Added (Isolated)'), findsOneWidget);

    // 4. Tap "Edit Roster Display" to navigate back to /rosters
    await tester.tap(find.text('Edit Roster Display'));
    await tester.pumpAndSettle();

    // 5. Verify board placement:
    // Bob (not isolated) appears in BOTH Day - Trainer and Day - Front of House
    expect(find.text('Bob StandardTrainer'), findsNWidgets(2));

    // Alice (Seasonal is isolated) appears ONLY ONCE on the entire board (in Seasonal)
    // and NOT in Day - Trainer or Day - Front of House!
    expect(find.text('Alice SeasonalTrainer'), findsOneWidget);
  });
}
