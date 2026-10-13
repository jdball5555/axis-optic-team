import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

@freezed
abstract class UserModel with _$UserModel {
  const factory UserModel({
    String? id,
    @JsonKey(name: 'first_name') String? firstName,
    @JsonKey(name: 'last_name') String? lastName,
    @JsonKey(name: 'preferred_name') String? preferredName,
    String? email,
    String? title,
    @JsonKey(name: 'start_date') DateTime? startDate,
    @JsonKey(name: 'end_date') DateTime? endDate,
    String? store,
    String? position,
    String? designation,
    @JsonKey(name: 'additional_tags') @Default([]) List<String>? additionalTags,
    @JsonKey(name: 'working_time') String? workingTime,
    @JsonKey(name: 'avg_shifts') String? avgShifts,
    @JsonKey(name: 'pay_rate') double? payRate,
    @JsonKey(name: 'food_handlers_expiration') DateTime? foodHandlersExpiration,
    @JsonKey(name: 'manager_permit_expiration') DateTime? managerPermitExpiration,
    @JsonKey(name: 'general_notes') String? generalNotes,
    @JsonKey(name: 'hiring_notes') String? hiringNotes,
    String? status,
    @JsonKey(name: 'completed_tasks') @Default([]) List<String>? completedTasks,
    @JsonKey(name: 'completed_checklists') @Default([]) List<String>? completedChecklists,
    @Default([]) List<String>? certifications,
    @JsonKey(name: 'history_logs') @Default([]) List<Map<String, dynamic>>? historyLogs,
    @JsonKey(name: 'active_availability') @Default({}) Map<String, dynamic>? activeAvailability,
    @JsonKey(name: 'assigned_checklists') @Default([]) List<String>? assignedChecklists,
    @JsonKey(name: 'access_levels') @Default({}) Map<String, bool>? accessLevels,
    String? role,
    @JsonKey(name: 'is_ops_only') @Default(false) bool? isOpsOnly,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);
}

/// Status shown on the roster: "Former" once their last day (end date) has
/// passed, "Leaving" while it's still to come, otherwise "Active" (or a
/// saved status like "Former" / "Inactive").
String memberStatus(UserModel u, {DateTime? today}) {
  final s = (u.status ?? '').trim();
  final lower = s.toLowerCase();
  if (lower.contains('former') || lower.contains('terminat') || lower.contains('inactive')) {
    return s;
  }
  final end = u.endDate;
  if (end == null) return 'Active';
  final now = today ?? DateTime.now();
  final lastDay = DateTime(end.year, end.month, end.day);
  return DateTime(now.year, now.month, now.day).isAfter(lastDay) ? 'Former' : 'Leaving';
}

/// Still part of the team (Active or Leaving). Former team members aren't
/// counted, scheduled or shown by default.
bool isCurrentMember(UserModel u) {
  final status = memberStatus(u);
  return status == 'Active' || status == 'Leaving';
}
