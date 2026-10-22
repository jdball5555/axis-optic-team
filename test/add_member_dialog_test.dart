import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/providers/app_providers.dart';
import 'package:axis_team/services/firestore_service.dart';
import 'package:axis_team/ui/views/team_roster_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MockFirestoreService implements FirestoreService {
  UserModel? savedUser;

  @override
  Future<void> createUser(UserModel user) async {
    savedUser = user;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final sampleStores = [
    {'id': 'store_1', 'name': 'Main Street Store'},
  ];

  final sampleSettings = const StoreSettingsModel(
    positions: ['Front Counter', 'Drive Thru', 'Kitchen'],
    designations: ['Full Time', 'Part Time'],
    workingTimes: ['Morning', 'Day', 'Night'],
    titles: [
      TitleConfig(id: 't1', name: 'Team Member', color: 'Blue'),
      TitleConfig(id: 't2', name: 'Trainer', color: 'Red'),
    ],
    tags: [
      TitleConfig(id: 'tag1', name: 'Opening Expert', color: 'Green'),
      TitleConfig(id: 'tag2', name: 'Closing Expert', color: 'Purple'),
    ],
  );

  Widget createTestWidget({required MockFirestoreService mockFirestore}) {
    return ProviderScope(
      overrides: [
        baseFirestoreServiceProvider.overrideWithValue(mockFirestore),
        firestoreServiceProvider.overrideWithValue(mockFirestore),
        currentStoreIdProvider.overrideWith((ref) => 'store_1'),
        allStoresStreamProvider.overrideWith((ref) => Stream.value(sampleStores)),
        storeSettingsProvider.overrideWith((ref) => Stream.value(sampleSettings)),
        specificStoreSettingsProvider('store_1').overrideWith((ref) => Stream.value(sampleSettings)),
        allStoreUsersStreamProvider.overrideWith((ref) => Stream.value([
          UserModel(
            id: 'u1',
            firstName: 'Alice',
            lastName: 'Smith',
            store: 'store_1',
            title: 'Team Member',
            position: 'Front Counter',
            designation: 'Full Time',
            workingTime: 'Morning',
            status: 'Active',
          ),
        ])),
        usersStreamProvider.overrideWith((ref) => AsyncValue.data([
          UserModel(
            id: 'u1',
            firstName: 'Alice',
            lastName: 'Smith',
            store: 'store_1',
            title: 'Team Member',
            position: 'Front Counter',
            designation: 'Full Time',
            workingTime: 'Morning',
            status: 'Active',
          ),
        ])),
        sortedUsersProvider.overrideWith((ref) => AsyncValue.data([
          UserModel(
            id: 'u1',
            firstName: 'Alice',
            lastName: 'Smith',
            store: 'store_1',
            title: 'Team Member',
            position: 'Front Counter',
            designation: 'Full Time',
            workingTime: 'Morning',
            status: 'Active',
          ),
        ])),
      ],
      child: const MaterialApp(
        home: TeamRosterView(),
      ),
    );
  }

  testWidgets('Add Team Member button is in the top bar and no FloatingActionButton exists', (tester) async {
    final mockFirestore = MockFirestoreService();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createTestWidget(mockFirestore: mockFirestore));
    await tester.pumpAndSettle();

    // Verify FAB does not exist in the view
    expect(find.byType(FloatingActionButton), findsNothing);

    // Verify Add Team Member button exists in the top action area
    expect(find.text('Add Team Member'), findsOneWidget);
    expect(find.byIcon(Icons.person_add_rounded), findsOneWidget);
  });

  testWidgets('Add Team Member dialog opens with all form fields and no store selector', (tester) async {
    final mockFirestore = MockFirestoreService();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createTestWidget(mockFirestore: mockFirestore));
    await tester.pumpAndSettle();

    // Tap Add Team Member button
    await tester.tap(find.text('Add Team Member'));
    await tester.pumpAndSettle();

    // Verify Header and Close button
    expect(find.text('Add Team Member'), findsNWidgets(2)); // Button + Dialog header
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Verify Row 1: First Name, Preferred Name toggle, Last Name, Title, Start Date
    expect(find.text('FIRST NAME'), findsOneWidget);
    expect(find.text('Preferred Name?'), findsOneWidget);
    expect(find.text('LAST NAME'), findsOneWidget);
    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('START DATE'), findsOneWidget);

    // Verify Row 2: Position, Designation, Working Time, Additional Tags
    expect(find.text('POSITION'), findsOneWidget);
    expect(find.text('DESIGNATION'), findsOneWidget);
    expect(find.text('WORKING TIME'), findsOneWidget);
    expect(find.text('ADDITIONAL TAGS'), findsOneWidget);

    // Verify Row 3: Avg Shifts, Pay, Food Permit
    expect(find.text('AVG SHIFTS / WK'), findsOneWidget);
    expect(find.text('PAY (\$ / HR)'), findsOneWidget);
    expect(find.text('FOOD PERMIT EXP.'), findsOneWidget);

    // Verify Row 4: Notes
    expect(find.text('GENERAL NOTES'), findsOneWidget);
    expect(find.text('HIRING NOTES'), findsOneWidget);

    // Verify Action buttons
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save Member'), findsOneWidget);

    // Verify STORE dropdown is NOT present
    expect(find.text('STORE'), findsNothing);
    expect(find.text('-- Select Store --'), findsNothing);
  });

  testWidgets('Preferred Name toggle shows and hides preferred name input', (tester) async {
    final mockFirestore = MockFirestoreService();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createTestWidget(mockFirestore: mockFirestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Team Member'));
    await tester.pumpAndSettle();

    // Initially PREFERRED NAME field is hidden
    expect(find.text('PREFERRED NAME'), findsNothing);

    // Tap Preferred Name? toggle
    await tester.tap(find.text('Preferred Name?'));
    await tester.pumpAndSettle();

    // Now PREFERRED NAME field is shown with Hide button
    expect(find.text('PREFERRED NAME'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);

    // Tap Hide
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();

    // It is hidden again
    expect(find.text('PREFERRED NAME'), findsNothing);
    expect(find.text('Preferred Name?'), findsOneWidget);
  });

  testWidgets('Validation error is shown when required fields are missing', (tester) async {
    final mockFirestore = MockFirestoreService();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createTestWidget(mockFirestore: mockFirestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Team Member'));
    await tester.pumpAndSettle();

    // Tap Save Member without entering required fields
    await tester.tap(find.text('Save Member'));
    await tester.pumpAndSettle();

    // Should display validation errors on required fields
    expect(find.text('First name is required'), findsOneWidget);
    expect(find.text('Last name is required'), findsOneWidget);
    expect(find.text('Position is required'), findsOneWidget);
    expect(find.text('Designation is required'), findsOneWidget);
    expect(find.text('Working time is required'), findsOneWidget);
    expect(mockFirestore.savedUser, isNull);
  });

  testWidgets('Filling out member fields saves UserModel to Firestore', (tester) async {
    final mockFirestore = MockFirestoreService();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createTestWidget(mockFirestore: mockFirestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Team Member'));
    await tester.pumpAndSettle();

    // Enter First Name (descendant of innermost column containing 'FIRST NAME')
    final firstNameCol = find.ancestor(of: find.text('FIRST NAME'), matching: find.byType(Column)).first;
    final firstNameField = find.descendant(of: firstNameCol, matching: find.byType(TextFormField)).first;
    await tester.enterText(firstNameField, 'John');

    // Fill in last name
    final lastNameCol = find.ancestor(of: find.text('LAST NAME'), matching: find.byType(Column)).first;
    final lastNameField = find.descendant(of: lastNameCol, matching: find.byType(TextFormField)).first;
    await tester.enterText(lastNameField, 'Doe');

    // Select Position dropdown
    await tester.tap(find.text('-- Select Position --'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Front Counter').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Select Designation dropdown
    await tester.tap(find.text('-- Select Designation --'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Time').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Select Working Time dropdown
    await tester.tap(find.text('-- Select Working Time --'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Enter Avg shifts
    final avgShiftsCol = find.ancestor(of: find.text('AVG SHIFTS / WK'), matching: find.byType(Column)).first;
    final avgShiftsField = find.descendant(of: avgShiftsCol, matching: find.byType(TextFormField)).first;
    await tester.enterText(avgShiftsField, '4');

    // Enter Pay
    final payCol = find.ancestor(of: find.text('PAY (\$ / HR)'), matching: find.byType(Column)).first;
    final payField = find.descendant(of: payCol, matching: find.byType(TextFormField)).first;
    await tester.enterText(payField, '\$16.50');

    // Enter General Notes
    final generalNotesCol = find.ancestor(of: find.text('GENERAL NOTES'), matching: find.byType(Column)).first;
    final generalNotesField = find.descendant(of: generalNotesCol, matching: find.byType(TextFormField)).first;
    await tester.enterText(generalNotesField, 'Great team player');

    // Enter Hiring Notes
    final hiringNotesCol = find.ancestor(of: find.text('HIRING NOTES'), matching: find.byType(Column)).first;
    final hiringNotesField = find.descendant(of: hiringNotesCol, matching: find.byType(TextFormField)).first;
    await tester.enterText(hiringNotesField, 'Referral from Sarah');

    // Tap Save Member
    await tester.tap(find.text('Save Member'));
    await tester.pumpAndSettle();

    // Dialog should dismiss and member saved
    expect(mockFirestore.savedUser, isNotNull);
    final saved = mockFirestore.savedUser!;
    expect(saved.firstName, 'John');
    expect(saved.lastName, 'Doe');
    expect(saved.position, 'Front Counter');
    expect(saved.designation, 'Full Time');
    expect(saved.workingTime, 'Morning');
    expect(saved.avgShifts, '4');
    expect(saved.payRate, 16.50);
    expect(saved.generalNotes, 'Great team player');
    expect(saved.hiringNotes, 'Referral from Sarah');
    expect(saved.store, 'store_1');
    expect(saved.status, 'Active');

    // Success snackbar
    expect(find.text('Added John Doe to team'), findsOneWidget);
  });
}
