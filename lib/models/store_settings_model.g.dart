// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'store_settings_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TitleConfig _$TitleConfigFromJson(Map<String, dynamic> json) => _TitleConfig(
  id: json['id'] as String,
  color: json['color'] as String? ?? 'Color',
  name: json['name'] as String? ?? '',
  isLeadership: json['isLeadership'] as bool? ?? false,
  splitInArea: json['splitInArea'] as bool? ?? false,
  isolatedRoster: json['isolatedRoster'] as bool? ?? false,
  linkChecklist: json['linkChecklist'] as bool? ?? false,
  mgrPermit: json['mgrPermit'] as bool? ?? false,
  linkedChecklistId: json['linkedChecklistId'] as String?,
  autoPromoteOnChecklist: json['autoPromoteOnChecklist'] as bool? ?? false,
);

Map<String, dynamic> _$TitleConfigToJson(_TitleConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'color': instance.color,
      'name': instance.name,
      'isLeadership': instance.isLeadership,
      'splitInArea': instance.splitInArea,
      'isolatedRoster': instance.isolatedRoster,
      'linkChecklist': instance.linkChecklist,
      'mgrPermit': instance.mgrPermit,
      'linkedChecklistId': instance.linkedChecklistId,
      'autoPromoteOnChecklist': instance.autoPromoteOnChecklist,
    };

_ChecklistTaskItem _$ChecklistTaskItemFromJson(Map<String, dynamic> json) =>
    _ChecklistTaskItem(
      id: json['id'] as String,
      text: json['text'] as String,
      positions:
          (json['positions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ChecklistTaskItemToJson(_ChecklistTaskItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'positions': instance.positions,
    };

_ChecklistConfig _$ChecklistConfigFromJson(Map<String, dynamic> json) =>
    _ChecklistConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as String? ?? 'Color',
      items:
          (json['items'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      tasks: json['tasks'] == null ? const [] : _tasksFromJson(json['tasks']),
    );

Map<String, dynamic> _$ChecklistConfigToJson(_ChecklistConfig instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'color': instance.color,
      'items': instance.items,
      'tasks': _tasksToJson(instance.tasks),
    };

_StoreSettingsModel _$StoreSettingsModelFromJson(
  Map<String, dynamic> json,
) => _StoreSettingsModel(
  titles: json['titles'] == null ? const [] : _titlesFromJson(json['titles']),
  tags: json['tags'] == null ? const [] : _titlesFromJson(json['tags']),
  workingTimes:
      (json['workingTimes'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  positions:
      (json['positions'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  designations:
      (json['designations'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  checklists: json['checklists'] == null
      ? const []
      : _checklistsFromJson(json['checklists']),
  autoPurgeFormer: json['autoPurgeFormer'] as bool? ?? false,
  purgeDaysGone: (json['purgeDaysGone'] as num?)?.toInt() ?? 0,
  isScheduleEnabled: json['isScheduleEnabled'] as bool? ?? false,
  isShiftBoardEnabled: json['isShiftBoardEnabled'] as bool? ?? false,
  employeeDataSummaryFields:
      (json['employeeDataSummaryFields'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  showOwnerInRoster: json['showOwnerInRoster'] as bool? ?? false,
);

Map<String, dynamic> _$StoreSettingsModelToJson(_StoreSettingsModel instance) =>
    <String, dynamic>{
      'titles': _titlesToJson(instance.titles),
      'tags': _titlesToJson(instance.tags),
      'workingTimes': instance.workingTimes,
      'positions': instance.positions,
      'designations': instance.designations,
      'checklists': _checklistsToJson(instance.checklists),
      'autoPurgeFormer': instance.autoPurgeFormer,
      'purgeDaysGone': instance.purgeDaysGone,
      'isScheduleEnabled': instance.isScheduleEnabled,
      'isShiftBoardEnabled': instance.isShiftBoardEnabled,
      'employeeDataSummaryFields': instance.employeeDataSummaryFields,
      'showOwnerInRoster': instance.showOwnerInRoster,
    };
