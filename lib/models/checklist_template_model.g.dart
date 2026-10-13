// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklist_template_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChecklistTask _$ChecklistTaskFromJson(Map<String, dynamic> json) =>
    _ChecklistTask(
      id: json['id'] as String,
      title: json['title'] as String,
      isCompleted: json['isCompleted'] as bool? ?? false,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$ChecklistTaskToJson(_ChecklistTask instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'isCompleted': instance.isCompleted,
      'notes': instance.notes,
    };

_ChecklistTemplateModel _$ChecklistTemplateModelFromJson(
  Map<String, dynamic> json,
) => _ChecklistTemplateModel(
  id: json['id'] as String,
  name: json['name'] as String,
  color: json['color'] as String,
  tasks:
      (json['tasks'] as List<dynamic>?)
          ?.map((e) => ChecklistTask.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$ChecklistTemplateModelToJson(
  _ChecklistTemplateModel instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'color': instance.color,
  'tasks': instance.tasks,
};
