import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/services/firestore_service.dart';
import 'package:axis_team/ui/views/rosters_view.dart';
import 'package:axis_team/ui/views/settings_view.dart';
import 'package:axis_team/ui/widgets/settings_title_tag_card.dart';
import 'package:axis_team/ui/widgets/settings_checklists_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MockFirestoreService implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final mockFirestore = MockFirestoreService();

  group('Color dropdowns (no text names in dropdown menu items)', () {
    testWidgets(
      'SettingsTitleTagCard color picker shows only color dot without text',
      (tester) async {
        final settings = StoreSettingsModel(
          titles: [TitleConfig(id: 't1', name: 'Server', color: 'Purple')],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsTitleTagCard(settings: settings, onUpdate: (_) {}),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Find the dropdown button
        final dropdownFinder = find.byType(DropdownButton<String>);
        expect(dropdownFinder, findsOneWidget);

        // Open the dropdown
        await tester.tap(dropdownFinder);
        await tester.pumpAndSettle();

        // Verify that color name text like "Purple", "Red", "Teal" does NOT appear as menu item text
        expect(find.text('Purple'), findsNothing);
        expect(find.text('Red'), findsNothing);
        expect(find.text('Teal'), findsNothing);

        // But DropdownMenuItems are present
        final menuItems = find.byType(DropdownMenuItem<String>);
        expect(menuItems, findsWidgets);
      },
    );

    testWidgets(
      'SettingsChecklistsCard color picker shows only color dot without text',
      (tester) async {
        final settings = StoreSettingsModel(
          checklists: [
            ChecklistConfig(id: 'c1', name: 'Opening Checklist', color: 'Teal'),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsChecklistsCard(
                settings: settings,
                onUpdate: (_) {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final dropdownFinder = find.byType(DropdownButton<String>);
        expect(dropdownFinder, findsOneWidget);

        await tester.tap(dropdownFinder);
        await tester.pumpAndSettle();

        expect(find.text('Teal'), findsNothing);
        expect(find.text('Red'), findsNothing);
        expect(find.text('Purple'), findsNothing);

        final menuItems = find.byType(DropdownMenuItem<String>);
        expect(menuItems, findsWidgets);
      },
    );
  });

  group(
    'Single store view Title/Tag configuration shows settings icon instead of inline buttons',
    () {
      testWidgets(
        'Single store mode displays Icons.settings and delete, not inline buttons',
        (tester) async {
          final settings = StoreSettingsModel(
            titles: [TitleConfig(id: 't1', name: 'Cashier', color: 'Green')],
          );

          await tester.binding.setSurfaceSize(const Size(1400, 900));

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SettingsTitleTagCard(
                  settings: settings,
                  isAllStoresMode: false,
                  onUpdate: (_) {},
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          // In single store mode, inline buttons should NOT appear
          expect(find.text('Leadership'), findsNothing);
          expect(find.text('Split in Area'), findsNothing);
          expect(find.text('Isolated Roster'), findsNothing);
          expect(find.text('Mgr Permit'), findsNothing);

          // Settings gear icon and delete icon should appear
          expect(find.byIcon(Icons.settings), findsOneWidget);
          expect(find.byIcon(Icons.delete_outline), findsOneWidget);

          // Clicking settings gear opens dialog with configuration options
          await tester.tap(find.byIcon(Icons.settings));
          await tester.pumpAndSettle();

          expect(find.text('Cashier Settings'), findsOneWidget);
          expect(find.text('Leadership'), findsOneWidget);
          // Split in Area moved to the roster tile setup.
          expect(find.text('Split in Area'), findsNothing);
          // Isolated Roster button was removed from Title settings (configured on Roster customize page)
          expect(find.text('Isolated Roster'), findsNothing);
        },
      );
    },
  );

  group('Settings View All Stores 2D Scrolling', () {
    testWidgets(
      'All stores mode allows diagonal scrolling moving both horizontal and vertical',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 600));

        final stores = [
          {'id': 's1', 'name': 'Store 1', 'is_dev': false},
          {'id': 's2', 'name': 'Store 2', 'is_dev': false},
          {'id': 's3', 'name': 'Store 3', 'is_dev': false},
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
              firestoreServiceProvider.overrideWithValue(mockFirestore),
              allStoresStreamProvider.overrideWith(
                (ref) => Stream.value(stores),
              ),
              currentStoreIdProvider.overrideWith((ref) => null),
              currentUserProvider.overrideWith(
                (ref) => {
                  'id': 'owner_1',
                  'first_name': 'Alex',
                  'last_name': 'Owner',
                  'owned_stores': ['s1', 's2', 's3'],
                },
              ),
              specificStoreSettingsProvider('s1').overrideWith(
                (ref) => Stream.value(
                  StoreSettingsModel(
                    titles: List.generate(
                      20,
                      (i) => TitleConfig(id: 't_$i', name: 'Title $i'),
                    ),
                  ),
                ),
              ),
              specificStoreSettingsProvider('s2').overrideWith(
                (ref) => Stream.value(
                  StoreSettingsModel(
                    titles: List.generate(
                      20,
                      (i) => TitleConfig(id: 't_$i', name: 'Title $i'),
                    ),
                  ),
                ),
              ),
              specificStoreSettingsProvider('s3').overrideWith(
                (ref) => Stream.value(
                  StoreSettingsModel(
                    titles: List.generate(
                      20,
                      (i) => TitleConfig(id: 't_$i', name: 'Title $i'),
                    ),
                  ),
                ),
              ),
            ],
            child: const MaterialApp(home: SettingsView()),
          ),
        );

        await tester.pumpAndSettle();

        // Find controllers
        final horizontalScrollable = find.byType(SingleChildScrollView);
        expect(horizontalScrollable, findsWidgets);
        final customScrollable = find.byType(CustomScrollView);
        expect(customScrollable, findsOneWidget);

        final hController = tester
            .widget<SingleChildScrollView>(horizontalScrollable.first)
            .controller!;
        final vController = tester
            .widget<CustomScrollView>(customScrollable)
            .controller!;

        expect(hController.offset, 0.0);
        expect(vController.offset, 0.0);

        // Perform diagonal pointer scroll
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(const Offset(400, 300)));
        await tester.sendEventToBinding(pointer.scroll(const Offset(50, 75)));
        await tester.pump();

        expect(hController.offset, 50.0);
        expect(vController.offset, 75.0);
      },
    );
  });

  group('Rosters View Scrolling & Isolation', () {
    testWidgets(
      'Main canvas scrolls freely in 2D and scrolling over a tile isolates scrolling without moving canvas',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 800));

        final users = [
          for (int i = 0; i < 25; i++)
            UserModel(
              id: 'u_$i',
              firstName: 'Person',
              lastName: '$i',
              position: 'Cashier',
              store: 's1',
              title: 'Staff',
              avgShifts: '4',
            ),
        ];

        final stores = [
          {'id': 's1', 'name': 'Store 1', 'is_dev': false},
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
              firestoreServiceProvider.overrideWithValue(mockFirestore),
              allStoresStreamProvider.overrideWith(
                (ref) => Stream.value(stores),
              ),
              currentStoreIdProvider.overrideWith((ref) => 's1'),
              currentUserProvider.overrideWith(
                (ref) => {
                  'id': 'owner_1',
                  'first_name': 'Alex',
                  'last_name': 'Owner',
                  'owned_stores': ['s1'],
                },
              ),
              currentMembersProvider.overrideWith(
                (ref) => AsyncValue.data(users),
              ),
              rosterNeedsStreamProvider.overrideWith(
                (ref) => Stream.value({'s1_Cashier': 5}),
              ),
              specificStoreSettingsProvider('s1').overrideWith(
                (ref) => Stream.value(
                  StoreSettingsModel(
                    positions: [
                      'Cashier',
                      'Drive-Thru',
                      'Kitchen',
                      'Bake',
                      'Prep',
                    ],
                    titles: [
                      TitleConfig(id: 'st', name: 'Staff'),
                      TitleConfig(
                        id: 'iso',
                        name: 'Shift Lead',
                        isolatedRoster: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            child: const MaterialApp(home: RostersView()),
          ),
        );

        await tester.pumpAndSettle();

        // Find outer scroll controllers
        final singleChildScrollables = tester
            .widgetList<SingleChildScrollView>(
              find.byType(SingleChildScrollView),
            )
            .toList();
        final vCanvas = singleChildScrollables[0].controller!;
        final hCanvas = singleChildScrollables[1].controller!;

        final canvasTopLeft = tester.getTopLeft(find.byType(Stack).first);
        print(
          'DEBUG: canvasTopLeft=$canvasTopLeft, hMax=${hCanvas.position.maxScrollExtent}, vMax=${vCanvas.position.maxScrollExtent}',
        );
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          pointer.hover(canvasTopLeft + const Offset(450, 600)),
        );
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
        await tester.pump();
        expect(vCanvas.offset, 60.0);

        await tester.sendEventToBinding(pointer.scroll(const Offset(40, 0)));
        await tester.pump();
        expect(hCanvas.offset, 40.0);

        // Simultaneous diagonal scroll (moves both horizontal and vertical)
        await tester.sendEventToBinding(pointer.scroll(const Offset(40, 60)));
        await tester.pump();
        expect(vCanvas.offset, 120.0);
        expect(hCanvas.offset, 80.0);

        // While the canvas is still scrolling, a tile under the cursor
        // doesn't take over: the canvas keeps moving.
        final memberFinder = find.text('Person 0');
        expect(memberFinder, findsOneWidget);
        await tester.sendEventToBinding(
          pointer.hover(tester.getCenter(memberFinder)),
        );
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 30)));
        await tester.pump();
        expect(vCanvas.offset, 150.0);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -30)));
        await tester.pump();
        expect(vCanvas.offset, 120.0);

        // Once the canvas has settled, a scroll that starts on a tile
        // belongs to the tile.
        await tester.pump(const Duration(milliseconds: 400));

        // 2. Move pointer over a member in the roster tile and scroll
        final tileCenter = tester.getCenter(memberFinder);

        await tester.sendEventToBinding(pointer.hover(tileCenter));
        await tester.sendEventToBinding(pointer.scroll(const Offset(20, 30)));
        await tester.pump();

        // Canvas remains locked at its prior position because the tile intercepted the scroll!
        expect(hCanvas.offset, 80.0);
        expect(vCanvas.offset, 120.0);

        // 3. Scroll inside the tile downwards -> canvas STILL remains locked!
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
        await tester.pump();

        // Canvas remains locked at its prior position!
        expect(hCanvas.offset, 80.0);
        expect(vCanvas.offset, 120.0);
      },
    );
  });
}
