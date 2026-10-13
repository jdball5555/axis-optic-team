import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/schedule_models.dart';
import '../../../models/user_model.dart';
import '../../../services/schedule_repository.dart';
import 'position_ops.dart';

/// Training-flow steps for people in training on [date], by user id.
/// People in the last training review: their next step not done yet
/// (days worked since the review count as steps done). People never
/// reviewed: new hires (last 180 days, or still on the first title) by how
/// many days they've worked. Call from build: it watches the lookups.
Map<String, TrainingStep> trainingStepsFor(
  WidgetRef ref, {
  required String storeId,
  String boardId = kMainBoardId,
  required DateTime date,
  required Iterable<UserModel> people,
  required ScheduleConfig config,
  required List<String> titleOrder,
}) {
  if (!config.trainingFlowEnabled || config.trainingDays.isEmpty) {
    return const {};
  }
  final progress =
      ref.watch(trainingProgressProvider(storeId)).valueOrNull ??
      const <String, TrainingProgress>{};
  final firstTitle = titleOrder.firstOrNull;
  final recent = date.subtract(const Duration(days: 180));
  final out = <String, TrainingStep>{};
  for (final u in people) {
    final id = u.id;
    if (id == null) continue;
    final reviewed = progress[id];
    if (reviewed != null) {
      if (reviewed.notInTraining) continue;
      final since = reviewed.asOf == null
          ? 0
          : ref
                .watch(
                  scheduledDaysBetweenProvider((
                    storeId: storeId,
                    userId: id,
                    from: reviewed.asOf!,
                    before: dateKey(date),
                    boardId: boardId,
                  )),
                )
                .valueOrNull;
      if (since == null) continue;
      final left = remainingTrainingSteps(
        config.trainingDays.length,
        reviewed.done,
        since,
      );
      final step = left.isEmpty ? null : trainingStepFor(config, left.first);
      if (step != null) out[id] = step;
      continue;
    }
    final isNew =
        (u.startDate != null && u.startDate!.isAfter(recent)) ||
        (firstTitle != null && u.title == firstTitle);
    if (!isNew) continue;
    final prior = ref
        .watch(
          scheduledDaysBeforeProvider((
            storeId: storeId,
            userId: id,
            date: dateKey(date),
            boardId: boardId,
          )),
        )
        .valueOrNull;
    if (prior == null) continue;
    final step = trainingStepFor(config, prior);
    if (step != null) out[id] = step;
  }
  return out;
}
