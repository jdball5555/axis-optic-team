import 'package:freezed_annotation/freezed_annotation.dart';

part 'employee_review_model.freezed.dart';
part 'employee_review_model.g.dart';

@freezed
abstract class EmployeeReviewModel with _$EmployeeReviewModel {
  const factory EmployeeReviewModel({
    required String id,
    required String userId,
    required String actionItem,
    required String status,
    DateTime? dateCompleted,
    String? manager,
    String? notes,
  }) = _EmployeeReviewModel;

  factory EmployeeReviewModel.fromJson(Map<String, dynamic> json) =>
      _$EmployeeReviewModelFromJson(json);
}
