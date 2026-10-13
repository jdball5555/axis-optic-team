import 'package:freezed_annotation/freezed_annotation.dart';

part 'checklist_template_model.freezed.dart';
part 'checklist_template_model.g.dart';

@freezed
abstract class ChecklistTask with _$ChecklistTask {
  const factory ChecklistTask({
    required String id,
    required String title,
    @Default(false) bool isCompleted,
    String? notes,
  }) = _ChecklistTask;

  factory ChecklistTask.fromJson(Map<String, dynamic> json) => _$ChecklistTaskFromJson(json);
}

@freezed
abstract class ChecklistTemplateModel with _$ChecklistTemplateModel {
  const factory ChecklistTemplateModel({
    required String id,
    required String name,
    required String color,
    @Default([]) List<ChecklistTask> tasks,
  }) = _ChecklistTemplateModel;

  factory ChecklistTemplateModel.fromJson(Map<String, dynamic> json) => _$ChecklistTemplateModelFromJson(json);
}
