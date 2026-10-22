import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/ui/views/schedule/position_ops.dart';
import 'package:axis_team/ui/views/schedule/training_review_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remaining steps: what was reviewed, then one per day worked since', () {
    expect(remainingTrainingSteps(3, {}, 0), [0, 1, 2]);
    expect(remainingTrainingSteps(3, {0}, 0), [1, 2]);
    expect(remainingTrainingSteps(3, {1}, 1), [2]); // step 0 worked since
    expect(remainingTrainingSteps(3, {0, 1, 2}, 0), isEmpty);
    expect(remainingTrainingSteps(3, {}, 5), isEmpty);
  });

  testWidgets(
    'review: checks steps from the schedule, hides people not in training',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const config = ScheduleConfig(
        trainingFlowEnabled: true,
        trainingDays: [
          TrainingDay(),
          TrainingDay(),
          TrainingDay(training: false),
        ],
      );
      // Newest hires are listed first: Nia, then Max.
      final people = [
        UserModel(
          id: 'new',
          firstName: 'Nia',
          startDate: DateTime(2026, 10, 1),
        ), // worked 1 day, never reviewed
        UserModel(
          id: 'vet',
          firstName: 'Vic',
          startDate: DateTime(2020),
        ), // not in training
        UserModel(
          id: 'mid',
          firstName: 'Max',
          startDate: DateTime(2026, 9, 1),
        ), // reviewed: step 1 done
      ];
      Map<String, TrainingProgress>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showTrainingReview(
                context,
                weekStart: DateTime(2026, 10, 12),
                people: people,
                config: config,
                shiftConfig: const ShiftConfig(),
                saved: const {
                  'vet': TrainingProgress(
                    userId: 'vet',
                    notInTraining: true,
                    asOf: '2026-10-05',
                  ),
                  'mid': TrainingProgress(
                    userId: 'mid',
                    done: {0},
                    asOf: '2026-10-12',
                  ),
                },
                workedSince: const {'new': 1, 'vet': 4, 'mid': 0},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('2 in training'), findsOneWidget);
      // A column per training shift.
      expect(find.text('Shift 1'), findsOneWidget);
      expect(find.text('Shift 3'), findsOneWidget);
      expect(find.text('on their own'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(6)); // 2 people × 3 shifts
      expect(find.text('Vic'), findsNothing); // under "Not in training (1)"
      expect(find.text('Not in training (1)'), findsOneWidget);

      // Nia → not in training.
      await tester.tap(
        find.widgetWithText(TextButton, 'Not in training').first,
      );
      await tester.pump();
      expect(find.text('1 in training'), findsOneWidget);

      await tester.tap(find.text('Save & build'));
      await tester.pumpAndSettle();
      expect(result!['new']!.notInTraining, isTrue);
      expect(result!['new']!.done, {0}); // the day she worked
      expect(result!['mid']!.done, {0});
      expect(result!['mid']!.notInTraining, isFalse);
      expect(result!['vet']!.notInTraining, isTrue);
      expect(result!.values.every((p) => p.asOf == '2026-10-12'), isTrue);
    },
  );
}
