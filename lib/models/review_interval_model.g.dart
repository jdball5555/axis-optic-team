// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_interval_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ReviewIntervalModel _$ReviewIntervalModelFromJson(Map<String, dynamic> json) =>
    _ReviewIntervalModel(
      id: json['id'] as String,
      reviewName: json['reviewName'] as String,
      unit: json['unit'] as String,
      timeValue: (json['timeValue'] as num?)?.toDouble(),
      daysFromStart: (json['daysFromStart'] as num?)?.toInt(),
      isRecurring: json['isRecurring'] as bool? ?? false,
      repeatDays: (json['repeatDays'] as num?)?.toInt(),
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$ReviewIntervalModelToJson(
  _ReviewIntervalModel instance,
) => <String, dynamic>{
  'id': instance.id,
  'reviewName': instance.reviewName,
  'unit': instance.unit,
  'timeValue': instance.timeValue,
  'daysFromStart': instance.daysFromStart,
  'isRecurring': instance.isRecurring,
  'repeatDays': instance.repeatDays,
  'notes': instance.notes,
};
