// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_UserModel _$UserModelFromJson(Map<String, dynamic> json) => _UserModel(
  id: json['id'] as String?,
  firstName: json['first_name'] as String?,
  lastName: json['last_name'] as String?,
  preferredName: json['preferred_name'] as String?,
  email: json['email'] as String?,
  title: json['title'] as String?,
  startDate: json['start_date'] == null
      ? null
      : DateTime.parse(json['start_date'] as String),
  endDate: json['end_date'] == null
      ? null
      : DateTime.parse(json['end_date'] as String),
  store: json['store'] as String?,
  position: json['position'] as String?,
  designation: json['designation'] as String?,
  additionalTags:
      (json['additional_tags'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  workingTime: json['working_time'] as String?,
  avgShifts: json['avg_shifts'] as String?,
  payRate: (json['pay_rate'] as num?)?.toDouble(),
  foodHandlersExpiration: json['food_handlers_expiration'] == null
      ? null
      : DateTime.parse(json['food_handlers_expiration'] as String),
  managerPermitExpiration: json['manager_permit_expiration'] == null
      ? null
      : DateTime.parse(json['manager_permit_expiration'] as String),
  generalNotes: json['general_notes'] as String?,
  hiringNotes: json['hiring_notes'] as String?,
  status: json['status'] as String?,
  completedTasks:
      (json['completed_tasks'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  completedChecklists:
      (json['completed_checklists'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  certifications:
      (json['certifications'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  historyLogs:
      (json['history_logs'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ??
      const [],
  activeAvailability:
      json['active_availability'] as Map<String, dynamic>? ?? const {},
  assignedChecklists:
      (json['assigned_checklists'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  accessLevels:
      (json['access_levels'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as bool),
      ) ??
      const {},
  role: json['role'] as String?,
  isOpsOnly: json['is_ops_only'] as bool? ?? false,
);

Map<String, dynamic> _$UserModelToJson(_UserModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'first_name': instance.firstName,
      'last_name': instance.lastName,
      'preferred_name': instance.preferredName,
      'email': instance.email,
      'title': instance.title,
      'start_date': instance.startDate?.toIso8601String(),
      'end_date': instance.endDate?.toIso8601String(),
      'store': instance.store,
      'position': instance.position,
      'designation': instance.designation,
      'additional_tags': instance.additionalTags,
      'working_time': instance.workingTime,
      'avg_shifts': instance.avgShifts,
      'pay_rate': instance.payRate,
      'food_handlers_expiration': instance.foodHandlersExpiration
          ?.toIso8601String(),
      'manager_permit_expiration': instance.managerPermitExpiration
          ?.toIso8601String(),
      'general_notes': instance.generalNotes,
      'hiring_notes': instance.hiringNotes,
      'status': instance.status,
      'completed_tasks': instance.completedTasks,
      'completed_checklists': instance.completedChecklists,
      'certifications': instance.certifications,
      'history_logs': instance.historyLogs,
      'active_availability': instance.activeAvailability,
      'assigned_checklists': instance.assignedChecklists,
      'access_levels': instance.accessLevels,
      'role': instance.role,
      'is_ops_only': instance.isOpsOnly,
    };
