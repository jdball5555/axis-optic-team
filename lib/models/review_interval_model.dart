import 'package:freezed_annotation/freezed_annotation.dart';

part 'review_interval_model.freezed.dart';
part 'review_interval_model.g.dart';

@freezed
abstract class ReviewIntervalModel with _$ReviewIntervalModel {
  const factory ReviewIntervalModel({
    required String id,
    required String reviewName,
    required String unit,
    double? timeValue,
    int? daysFromStart,
    @Default(false) bool isRecurring,
    int? repeatDays,
    String? notes,
  }) = _ReviewIntervalModel;

  factory ReviewIntervalModel.fromJson(Map<String, dynamic> json) => _$ReviewIntervalModelFromJson(json);
}
