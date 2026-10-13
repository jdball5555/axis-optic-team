// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'review_interval_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ReviewIntervalModel {

 String get id; String get reviewName; String get unit; double? get timeValue; int? get daysFromStart; bool get isRecurring; int? get repeatDays; String? get notes;
/// Create a copy of ReviewIntervalModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReviewIntervalModelCopyWith<ReviewIntervalModel> get copyWith => _$ReviewIntervalModelCopyWithImpl<ReviewIntervalModel>(this as ReviewIntervalModel, _$identity);

  /// Serializes this ReviewIntervalModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReviewIntervalModel&&(identical(other.id, id) || other.id == id)&&(identical(other.reviewName, reviewName) || other.reviewName == reviewName)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.timeValue, timeValue) || other.timeValue == timeValue)&&(identical(other.daysFromStart, daysFromStart) || other.daysFromStart == daysFromStart)&&(identical(other.isRecurring, isRecurring) || other.isRecurring == isRecurring)&&(identical(other.repeatDays, repeatDays) || other.repeatDays == repeatDays)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,reviewName,unit,timeValue,daysFromStart,isRecurring,repeatDays,notes);

@override
String toString() {
  return 'ReviewIntervalModel(id: $id, reviewName: $reviewName, unit: $unit, timeValue: $timeValue, daysFromStart: $daysFromStart, isRecurring: $isRecurring, repeatDays: $repeatDays, notes: $notes)';
}


}

/// @nodoc
abstract mixin class $ReviewIntervalModelCopyWith<$Res>  {
  factory $ReviewIntervalModelCopyWith(ReviewIntervalModel value, $Res Function(ReviewIntervalModel) _then) = _$ReviewIntervalModelCopyWithImpl;
@useResult
$Res call({
 String id, String reviewName, String unit, double? timeValue, int? daysFromStart, bool isRecurring, int? repeatDays, String? notes
});




}
/// @nodoc
class _$ReviewIntervalModelCopyWithImpl<$Res>
    implements $ReviewIntervalModelCopyWith<$Res> {
  _$ReviewIntervalModelCopyWithImpl(this._self, this._then);

  final ReviewIntervalModel _self;
  final $Res Function(ReviewIntervalModel) _then;

/// Create a copy of ReviewIntervalModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? reviewName = null,Object? unit = null,Object? timeValue = freezed,Object? daysFromStart = freezed,Object? isRecurring = null,Object? repeatDays = freezed,Object? notes = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,reviewName: null == reviewName ? _self.reviewName : reviewName // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,timeValue: freezed == timeValue ? _self.timeValue : timeValue // ignore: cast_nullable_to_non_nullable
as double?,daysFromStart: freezed == daysFromStart ? _self.daysFromStart : daysFromStart // ignore: cast_nullable_to_non_nullable
as int?,isRecurring: null == isRecurring ? _self.isRecurring : isRecurring // ignore: cast_nullable_to_non_nullable
as bool,repeatDays: freezed == repeatDays ? _self.repeatDays : repeatDays // ignore: cast_nullable_to_non_nullable
as int?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ReviewIntervalModel].
extension ReviewIntervalModelPatterns on ReviewIntervalModel {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReviewIntervalModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReviewIntervalModel() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReviewIntervalModel value)  $default,){
final _that = this;
switch (_that) {
case _ReviewIntervalModel():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReviewIntervalModel value)?  $default,){
final _that = this;
switch (_that) {
case _ReviewIntervalModel() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String reviewName,  String unit,  double? timeValue,  int? daysFromStart,  bool isRecurring,  int? repeatDays,  String? notes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReviewIntervalModel() when $default != null:
return $default(_that.id,_that.reviewName,_that.unit,_that.timeValue,_that.daysFromStart,_that.isRecurring,_that.repeatDays,_that.notes);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String reviewName,  String unit,  double? timeValue,  int? daysFromStart,  bool isRecurring,  int? repeatDays,  String? notes)  $default,) {final _that = this;
switch (_that) {
case _ReviewIntervalModel():
return $default(_that.id,_that.reviewName,_that.unit,_that.timeValue,_that.daysFromStart,_that.isRecurring,_that.repeatDays,_that.notes);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String reviewName,  String unit,  double? timeValue,  int? daysFromStart,  bool isRecurring,  int? repeatDays,  String? notes)?  $default,) {final _that = this;
switch (_that) {
case _ReviewIntervalModel() when $default != null:
return $default(_that.id,_that.reviewName,_that.unit,_that.timeValue,_that.daysFromStart,_that.isRecurring,_that.repeatDays,_that.notes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ReviewIntervalModel implements ReviewIntervalModel {
  const _ReviewIntervalModel({required this.id, required this.reviewName, required this.unit, this.timeValue, this.daysFromStart, this.isRecurring = false, this.repeatDays, this.notes});
  factory _ReviewIntervalModel.fromJson(Map<String, dynamic> json) => _$ReviewIntervalModelFromJson(json);

@override final  String id;
@override final  String reviewName;
@override final  String unit;
@override final  double? timeValue;
@override final  int? daysFromStart;
@override@JsonKey() final  bool isRecurring;
@override final  int? repeatDays;
@override final  String? notes;

/// Create a copy of ReviewIntervalModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReviewIntervalModelCopyWith<_ReviewIntervalModel> get copyWith => __$ReviewIntervalModelCopyWithImpl<_ReviewIntervalModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ReviewIntervalModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReviewIntervalModel&&(identical(other.id, id) || other.id == id)&&(identical(other.reviewName, reviewName) || other.reviewName == reviewName)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.timeValue, timeValue) || other.timeValue == timeValue)&&(identical(other.daysFromStart, daysFromStart) || other.daysFromStart == daysFromStart)&&(identical(other.isRecurring, isRecurring) || other.isRecurring == isRecurring)&&(identical(other.repeatDays, repeatDays) || other.repeatDays == repeatDays)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,reviewName,unit,timeValue,daysFromStart,isRecurring,repeatDays,notes);

@override
String toString() {
  return 'ReviewIntervalModel(id: $id, reviewName: $reviewName, unit: $unit, timeValue: $timeValue, daysFromStart: $daysFromStart, isRecurring: $isRecurring, repeatDays: $repeatDays, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$ReviewIntervalModelCopyWith<$Res> implements $ReviewIntervalModelCopyWith<$Res> {
  factory _$ReviewIntervalModelCopyWith(_ReviewIntervalModel value, $Res Function(_ReviewIntervalModel) _then) = __$ReviewIntervalModelCopyWithImpl;
@override @useResult
$Res call({
 String id, String reviewName, String unit, double? timeValue, int? daysFromStart, bool isRecurring, int? repeatDays, String? notes
});




}
/// @nodoc
class __$ReviewIntervalModelCopyWithImpl<$Res>
    implements _$ReviewIntervalModelCopyWith<$Res> {
  __$ReviewIntervalModelCopyWithImpl(this._self, this._then);

  final _ReviewIntervalModel _self;
  final $Res Function(_ReviewIntervalModel) _then;

/// Create a copy of ReviewIntervalModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? reviewName = null,Object? unit = null,Object? timeValue = freezed,Object? daysFromStart = freezed,Object? isRecurring = null,Object? repeatDays = freezed,Object? notes = freezed,}) {
  return _then(_ReviewIntervalModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,reviewName: null == reviewName ? _self.reviewName : reviewName // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String,timeValue: freezed == timeValue ? _self.timeValue : timeValue // ignore: cast_nullable_to_non_nullable
as double?,daysFromStart: freezed == daysFromStart ? _self.daysFromStart : daysFromStart // ignore: cast_nullable_to_non_nullable
as int?,isRecurring: null == isRecurring ? _self.isRecurring : isRecurring // ignore: cast_nullable_to_non_nullable
as bool,repeatDays: freezed == repeatDays ? _self.repeatDays : repeatDays // ignore: cast_nullable_to_non_nullable
as int?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
