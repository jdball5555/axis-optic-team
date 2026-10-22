import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/services/firestore_service.dart';
import 'package:axis_team/ui/views/member_detail_view.dart';
import 'package:axis_team/ui/views/team_roster_view.dart';
import 'package:axis_team/ui/widgets/multi_select_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockFirestoreService implements FirestoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sampleSettings = const StoreSettingsModel(
    positions: ['FOH', 'BOH'],
    designations: ['Full Time'],
    workingTimes: ['Morning'],
    titles: [
      TitleConfig(id: 't1', name: 'Shift Lead', color: 'Blue'),
      TitleConfig(id: 't2', name: 'Crew', color: 'Green'),
    ],
  );

  group('TeamRosterView Top Bar & Filter Button', () {
    testWidgets('Top bar has Search, Add Team Member, and Filter buttons at height 44, and filters collapsed by default', (tester) async {
      final mockFirestore = _MockFirestoreService();
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testUsers = [
        UserModel(
          id: 'u1',
          firstName: 'Alice',
          lastName: 'Smith',
          title: 'Shift Lead',
          position: 'FOH',
          store: 'store-1',
          status: 'Active',
        ),
        UserModel(
          id: 'u2',
          firstName: 'Bob',
          lastName: 'Jones',
          title: 'Crew',
          position: 'BOH',
          store: 'store-1',
          status: 'Active',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
            firestoreServiceProvider.overrideWithValue(mockFirestore),
            currentStoreIdProvider.overrideWith((ref) => 'store-1'),
            allStoresStreamProvider.overrideWith((ref) => Stream.value([
              {'id': 'store-1', 'name': 'Main Store'}
            ])),
            storeSettingsProvider.overrideWith((ref) => Stream.value(sampleSettings)),
            specificStoreSettingsProvider('store-1').overrideWith((ref) => Stream.value(sampleSettings)),
            allStoreUsersStreamProvider.overrideWith((ref) => Stream.value(testUsers)),
            usersStreamProvider.overrideWith((ref) => AsyncValue.data(testUsers)),
            sortedUsersProvider.overrideWith((ref) => AsyncValue.data(testUsers)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TeamRosterView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Search bar exists
      final searchFinder = find.byType(TextField);
      expect(searchFinder, findsOneWidget);

      // Verify Add Team Member button exists
      final addTextFinder = find.text('Add Team Member');
      expect(addTextFinder, findsOneWidget);
      expect(find.byIcon(Icons.person_add_rounded), findsOneWidget);

      // Verify Filter button exists
      final filterTextFinder = find.text('Filter');
      expect(filterTextFinder, findsOneWidget);
      expect(find.byIcon(Icons.filter_list_rounded), findsOneWidget);

      final addBtnFinder = find.ancestor(of: addTextFinder, matching: find.byType(SizedBox)).first;
      final filterBtnFinder = find.ancestor(of: filterTextFinder, matching: find.byType(SizedBox)).first;

      // Verify heights of Search, Add, and Filter are 44.0
      final searchBox = tester.getRect(searchFinder);
      expect(searchBox.height, 44.0);

      final addBox = tester.getRect(addBtnFinder);
      expect(addBox.height, 44.0);

      final filterBox = tester.getRect(filterBtnFinder);
      expect(filterBox.height, 44.0);

      // Verify relative positions: Search is on the left, Add is next, Filter is on the right
      expect(searchBox.left < addBox.left, isTrue);
      expect(addBox.left < filterBox.left, isTrue);

      // By default, filters row is collapsed (no MultiSelectFilter dropdowns)
      expect(find.byType(MultiSelectFilter), findsNothing);

      // Tap Filter button to expand
      await tester.tap(filterTextFinder);
      await tester.pumpAndSettle();

      // Filters row should now be visible (5 MultiSelectFilter widgets: Title, Position, Designation, Working Time, Status)
      expect(find.byType(MultiSelectFilter), findsNWidgets(5));

      // Tap Filter button again to collapse
      await tester.tap(filterTextFinder);
      await tester.pumpAndSettle();

      // Filters row should be hidden again
      expect(find.byType(MultiSelectFilter), findsNothing);
    });

    testWidgets('Table column headers align with data cells', (tester) async {
      final mockFirestore = _MockFirestoreService();
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testUsers = [
        UserModel(
          id: 'u1',
          firstName: 'Alice',
          lastName: 'Smith',
          title: 'Shift Lead',
          position: 'FOH',
          store: 'store-1',
          status: 'Active',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
            firestoreServiceProvider.overrideWithValue(mockFirestore),
            currentStoreIdProvider.overrideWith((ref) => 'store-1'),
            allStoresStreamProvider.overrideWith((ref) => Stream.value([
              {'id': 'store-1', 'name': 'Main Store'}
            ])),
            storeSettingsProvider.overrideWith((ref) => Stream.value(sampleSettings)),
            specificStoreSettingsProvider('store-1').overrideWith((ref) => Stream.value(sampleSettings)),
            allStoreUsersStreamProvider.overrideWith((ref) => Stream.value(testUsers)),
            usersStreamProvider.overrideWith((ref) => AsyncValue.data(testUsers)),
            sortedUsersProvider.overrideWith((ref) => AsyncValue.data(testUsers)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TeamRosterView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Name header aligns horizontally with member name data cell
      final nameHeader = tester.getTopLeft(find.text('Name'));
      final memberName = tester.getTopLeft(find.text('Smith, Alice'));
      expect(nameHeader.dx, equals(memberName.dx));

      // Verify Position header aligns horizontally with member position data cell
      final positionHeader = tester.getTopLeft(find.text('Position'));
      final memberPosition = tester.getTopLeft(find.text('FOH'));
      expect(positionHeader.dx, equals(memberPosition.dx));
    });
  });

  group('MemberDetailView Arrow Navigation Gating', () {
    testWidgets('Arrow navigation is hidden when opened from other pages (returnPath != /)', (tester) async {
      final mockFirestore = _MockFirestoreService();
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final user = UserModel(
        id: 'u1',
        firstName: 'Alice',
        lastName: 'Smith',
        store: 'store-1',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
            firestoreServiceProvider.overrideWithValue(mockFirestore),
            sortedUsersProvider.overrideWith((ref) => AsyncValue.data([user])),
            userStreamProvider('u1').overrideWith((ref) => Stream.value(user)),
            userTimeOffRequestsProvider('u1').overrideWith((ref) => Stream.value([])),
            userAvailabilityProvider('u1').overrideWith((ref) => Stream.value(null)),
            storeSettingsProvider.overrideWith((ref) => Stream.value(const StoreSettingsModel())),
            specificStoreSettingsProvider('store-1').overrideWith((ref) => Stream.value(const StoreSettingsModel())),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MemberDetailView(userId: 'u1', returnPath: '/rosters'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top navigation forward arrow and '1 of N' must NOT be present
      expect(find.byIcon(Icons.arrow_forward), findsNothing);
      expect(find.text('1 of 1'), findsNothing);
    });

    testWidgets('Arrow navigation is visible when opened from team member table (returnPath == /)', (tester) async {
      final mockFirestore = _MockFirestoreService();
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final user1 = UserModel(
        id: 'u1',
        firstName: 'Alice',
        lastName: 'Smith',
        store: 'store-1',
      );
      final user2 = UserModel(
        id: 'u2',
        firstName: 'Bob',
        lastName: 'Jones',
        store: 'store-1',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
            firestoreServiceProvider.overrideWithValue(mockFirestore),
            sortedUsersProvider.overrideWith((ref) => AsyncValue.data([user1, user2])),
            userStreamProvider('u1').overrideWith((ref) => Stream.value(user1)),
            userStreamProvider('u2').overrideWith((ref) => Stream.value(user2)),
            userTimeOffRequestsProvider('u1').overrideWith((ref) => Stream.value([])),
            userTimeOffRequestsProvider('u2').overrideWith((ref) => Stream.value([])),
            userAvailabilityProvider('u1').overrideWith((ref) => Stream.value(null)),
            userAvailabilityProvider('u2').overrideWith((ref) => Stream.value(null)),
            storeSettingsProvider.overrideWith((ref) => Stream.value(const StoreSettingsModel())),
            specificStoreSettingsProvider('store-1').overrideWith((ref) => Stream.value(const StoreSettingsModel())),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MemberDetailView(userId: 'u1', returnPath: '/'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top navigation forward arrow and '1 of 2' should be present
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
    });
  });

  group('Checklist Multi-Column Layout on MemberDetailView', () {
    testWidgets('Member checklist tasks render in Wrap layout with responsive columns', (tester) async {
      final mockFirestore = _MockFirestoreService();
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const checklistSettings = StoreSettingsModel(
        checklists: [
          ChecklistConfig(
            id: 'c1',
            name: 'Opening Checklist',
            tasks: [
              ChecklistTaskItem(id: 't1', text: 'Task 1'),
              ChecklistTaskItem(id: 't2', text: 'Task 2'),
              ChecklistTaskItem(id: 't3', text: 'Task 3'),
            ],
          ),
        ],
      );

      final user = UserModel(
        id: 'u1',
        firstName: 'Alice',
        lastName: 'Smith',
        store: 'store-1',
        assignedChecklists: ['c1'],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
            firestoreServiceProvider.overrideWithValue(mockFirestore),
            sortedUsersProvider.overrideWith((ref) => AsyncValue.data([user])),
            userStreamProvider('u1').overrideWith((ref) => Stream.value(user)),
            userTimeOffRequestsProvider('u1').overrideWith((ref) => Stream.value([])),
            userAvailabilityProvider('u1').overrideWith((ref) => Stream.value(null)),
            storeSettingsProvider.overrideWith((ref) => Stream.value(checklistSettings)),
            specificStoreSettingsProvider('store-1').overrideWith((ref) => Stream.value(checklistSettings)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MemberDetailView(userId: 'u1', returnPath: '/'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the tasks are rendered inside a Wrap widget (multi-column responsive)
      expect(find.byType(Wrap), findsWidgets);
      expect(find.text('Task 1'), findsOneWidget);
      expect(find.text('Task 2'), findsOneWidget);
      expect(find.text('Task 3'), findsOneWidget);
    });
  });

  group('Checklist Bubble Text Formatting', () {
    test('Checklist title regex strips the word Checklist regardless of casing', () {
      String cleanChecklistTitle(String raw) {
        final clean = raw.replaceAll(RegExp(r'\bchecklist\b', caseSensitive: false), '').trim();
        return clean.isNotEmpty ? clean : raw;
      }

      expect(cleanChecklistTitle('Opening Checklist'), 'Opening');
      expect(cleanChecklistTitle('closing checklist'), 'closing');
      expect(cleanChecklistTitle('Mid-Day CHECKLIST'), 'Mid-Day');
      expect(cleanChecklistTitle('Drive Thru Checklist'), 'Drive Thru');
      expect(cleanChecklistTitle('Checklist'), 'Checklist'); // Fallback if solely "Checklist"
    });
  });
}
