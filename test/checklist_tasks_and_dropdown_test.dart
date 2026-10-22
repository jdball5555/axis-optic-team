import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/ui/widgets/app_dropdown.dart';
import 'package:axis_team/ui/widgets/settings_checklists_card.dart';

void main() {
  group('ChecklistConfig & ChecklistTaskItem model tests', () {
    test('legacy items fallback to effectiveTasks with all positions', () {
      const config = ChecklistConfig(
        id: 'cl_1',
        name: 'Opening Checklist',
        items: ['Unlock doors', 'Turn on lights'],
      );

      expect(config.effectiveTasks.length, 2);
      expect(config.effectiveTasks[0].text, 'Unlock doors');
      expect(config.effectiveTasks[0].positions, isEmpty);
      expect(config.effectiveTasks[1].text, 'Turn on lights');

      // Both apply to any position
      expect(config.tasksForPosition('SVC').length, 2);
      expect(config.tasksForPosition('KT').length, 2);
      expect(config.tasksForPosition(null).length, 2);
    });

    test('tasks with specific positions filter correctly', () {
      final config = ChecklistConfig(
        id: 'cl_2',
        name: 'Daily Prep',
        tasks: const [
          ChecklistTaskItem(id: 't1', text: 'Front Register Prep', positions: ['SVC']),
          ChecklistTaskItem(id: 't2', text: 'Fryer Setup', positions: ['KT']),
          ChecklistTaskItem(id: 't3', text: 'Wash Hands', positions: []), // All positions
          ChecklistTaskItem(id: 't4', text: 'Drive Thru Headset', positions: ['DT', 'SVC']),
        ],
      );

      // SVC should see t1, t3, t4
      final svcTasks = config.tasksForPosition('SVC');
      expect(svcTasks.map((t) => t.id).toList(), ['t1', 't3', 't4']);

      // KT should see t2, t3
      final ktTasks = config.tasksForPosition('KT');
      expect(ktTasks.map((t) => t.id).toList(), ['t2', 't3']);

      // DT should see t3, t4
      final dtTasks = config.tasksForPosition('DT');
      expect(dtTasks.map((t) => t.id).toList(), ['t3', 't4']);

      // Null or empty position should see all tasks
      expect(config.tasksForPosition(null).length, 4);
      expect(config.tasksForPosition('').length, 4);
    });

    test('JSON serialization maintains tasks and synced items', () {
      final config = ChecklistConfig(
        id: 'cl_3',
        name: 'Closing',
        tasks: const [
          ChecklistTaskItem(id: 't1', text: 'Mop floor', positions: ['KT']),
          ChecklistTaskItem(id: 't2', text: 'Count drawer', positions: ['SVC']),
        ],
      );

      final settings = StoreSettingsModel(checklists: [config]);
      final json = settings.toJson();

      final decoded = StoreSettingsModel.fromJson(json);
      expect(decoded.checklists.length, 1);
      final decodedCl = decoded.checklists.first;
      expect(decodedCl.id, 'cl_3');
      expect(decodedCl.tasks.length, 2);
      expect(decodedCl.tasks[0].positions, ['KT']);
      expect(decodedCl.items, ['Mop floor', 'Count drawer']);
    });
  });

  group('AppDropdown widget tests', () {
    testWidgets('renders label, selected value, and allows selection', (tester) async {
      String? selected = 'Option A';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: AppDropdown<String>(
                    label: 'POSITION',
                    value: selected,
                    items: const ['Option A', 'Option B', 'Option C'],
                    onChanged: (val) {
                      setState(() {
                        selected = val;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('POSITION'), findsOneWidget);
      expect(find.text('Option A'), findsOneWidget);

      // Tap trigger to open popup overlay
      await tester.tap(find.text('Option A'));
      await tester.pumpAndSettle();

      // Options should be visible in popup
      expect(find.text('Option B'), findsOneWidget);
      expect(find.text('Option C'), findsOneWidget);

      // Tap Option B
      await tester.tap(find.text('Option B'));
      await tester.pumpAndSettle();

      expect(selected, 'Option B');
      expect(find.text('Option B'), findsOneWidget);
    });
  });

  group('AppMultiSelectDropdown widget tests', () {
    testWidgets('renders multi-select dropdown with checkboxes matching regular dropdown', (tester) async {
      List<String> selected = ['SVC', 'DT'];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: AppMultiSelectDropdown<String>(
                    label: 'ROLE / POSITION(S)',
                    options: const ['SVC', 'DT', 'KT'],
                    selected: selected,
                    allLabel: 'All Positions',
                    showAllOption: true,
                    onChanged: (val) {
                      setState(() {
                        selected = val;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('ROLE / POSITION(S)'), findsOneWidget);
      expect(find.text('SVC, DT'), findsOneWidget);

      // Open popup
      await tester.tap(find.text('SVC, DT'));
      await tester.pumpAndSettle();

      // All Positions option at top
      expect(find.text('All Positions'), findsOneWidget);

      // Options listed
      expect(find.text('SVC'), findsWidgets);
      expect(find.text('DT'), findsWidgets);
      expect(find.text('KT'), findsOneWidget);

      // Tap KT to toggle it
      await tester.tap(find.text('KT'));
      await tester.pumpAndSettle();
      expect(selected, contains('KT'));

      // Tap All Positions to toggle all
      await tester.tap(find.text('All Positions').last);
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
    });
  });

  group('SettingsChecklistsCard duplicate and position assignment tests', () {
    testWidgets('can duplicate task and assign positions', (tester) async {
      StoreSettingsModel settings = StoreSettingsModel(
        positions: const ['SVC', 'DT', 'KT'],
        checklists: [
          ChecklistConfig(
            id: 'cl_10',
            name: 'Cashier List',
            tasks: const [
              ChecklistTaskItem(id: 't_original', text: 'Count register', positions: ['SVC']),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SettingsChecklistsCard(
                  settings: settings,
                  onUpdate: (updated) {
                    setState(() {
                      settings = updated;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Checklist Configurations'), findsOneWidget);
      expect(find.text('Cashier List'), findsOneWidget);

      // Open manage dialog
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Manage Cashier List'), findsOneWidget);
      expect(find.text('Count register'), findsOneWidget);
      expect(find.byTooltip('Duplicate Task'), findsOneWidget);

      // Tap Duplicate Task button
      await tester.tap(find.byTooltip('Duplicate Task'));
      await tester.pumpAndSettle();

      // Settings should now have 2 tasks
      expect(settings.checklists.first.effectiveTasks.length, 2);
      expect(settings.checklists.first.effectiveTasks[0].text, 'Count register');
      expect(settings.checklists.first.effectiveTasks[1].text, 'Count register');
      expect(settings.checklists.first.effectiveTasks[1].positions, ['SVC']);
    });
  });
}

