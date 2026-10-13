// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee_review_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_EmployeeReviewModel _$EmployeeReviewModelFromJson(Map<String, dynamic> json) =>
    _EmployeeReviewModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      actionItem: json['actionItem'] as String,
      status: json['status'] as String,
      dateCompleted: json['dateCompleted'] == null
          ? null
          : DateTime.parse(json['dateCompleted'] as String),
      manager: json['manager'] as String?,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$EmployeeReviewModelToJson(
  _EmployeeReviewModel instance,
) => <String, dynamic>{
  'id': instance.id,
  'userId': instance.userId,
  'actionItem': instance.actionItem,
  'status': instance.status,
  'dateCompleted': instance.dateCompleted?.toIso8601String(),
  'manager': instance.manager,
  'notes': instance.notes,
};
