// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'employee_review_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$EmployeeReviewModel {

 String get id; String get userId; String get actionItem; String get status; DateTime? get dateCompleted; String? get manager; String? get notes;
/// Create a copy of EmployeeReviewModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EmployeeReviewModelCopyWith<EmployeeReviewModel> get copyWith => _$EmployeeReviewModelCopyWithImpl<EmployeeReviewModel>(this as EmployeeReviewModel, _$identity);

  /// Serializes this EmployeeReviewModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EmployeeReviewModel&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.actionItem, actionItem) || other.actionItem == actionItem)&&(identical(other.status, status) || other.status == status)&&(identical(other.dateCompleted, dateCompleted) || other.dateCompleted == dateCompleted)&&(identical(other.manager, manager) || other.manager == manager)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,actionItem,status,dateCompleted,manager,notes);

@override
String toString() {
  return 'EmployeeReviewModel(id: $id, userId: $userId, actionItem: $actionItem, status: $status, dateCompleted: $dateCompleted, manager: $manager, notes: $notes)';
}


}

/// @nodoc
abstract mixin class $EmployeeReviewModelCopyWith<$Res>  {
  factory $EmployeeReviewModelCopyWith(EmployeeReviewModel value, $Res Function(EmployeeReviewModel) _then) = _$EmployeeReviewModelCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String actionItem, String status, DateTime? dateCompleted, String? manager, String? notes
});




}
/// @nodoc
class _$EmployeeReviewModelCopyWithImpl<$Res>
    implements $EmployeeReviewModelCopyWith<$Res> {
  _$EmployeeReviewModelCopyWithImpl(this._self, this._then);

  final EmployeeReviewModel _self;
  final $Res Function(EmployeeReviewModel) _then;

/// Create a copy of EmployeeReviewModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? actionItem = null,Object? status = null,Object? dateCompleted = freezed,Object? manager = freezed,Object? notes = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,actionItem: null == actionItem ? _self.actionItem : actionItem // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,dateCompleted: freezed == dateCompleted ? _self.dateCompleted : dateCompleted // ignore: cast_nullable_to_non_nullable
as DateTime?,manager: freezed == manager ? _self.manager : manager // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [EmployeeReviewModel].
extension EmployeeReviewModelPatterns on EmployeeReviewModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EmployeeReviewModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EmployeeReviewModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EmployeeReviewModel value)  $default,){
final _that = this;
switch (_that) {
case _EmployeeReviewModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EmployeeReviewModel value)?  $default,){
final _that = this;
switch (_that) {
case _EmployeeReviewModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String actionItem,  String status,  DateTime? dateCompleted,  String? manager,  String? notes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EmployeeReviewModel() when $default != null:
return $default(_that.id,_that.userId,_that.actionItem,_that.status,_that.dateCompleted,_that.manager,_that.notes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String actionItem,  String status,  DateTime? dateCompleted,  String? manager,  String? notes)  $default,) {final _that = this;
switch (_that) {
case _EmployeeReviewModel():
return $default(_that.id,_that.userId,_that.actionItem,_that.status,_that.dateCompleted,_that.manager,_that.notes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String actionItem,  String status,  DateTime? dateCompleted,  String? manager,  String? notes)?  $default,) {final _that = this;
switch (_that) {
case _EmployeeReviewModel() when $default != null:
return $default(_that.id,_that.userId,_that.actionItem,_that.status,_that.dateCompleted,_that.manager,_that.notes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EmployeeReviewModel implements EmployeeReviewModel {
  const _EmployeeReviewModel({required this.id, required this.userId, required this.actionItem, required this.status, this.dateCompleted, this.manager, this.notes});
  factory _EmployeeReviewModel.fromJson(Map<String, dynamic> json) => _$EmployeeReviewModelFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String actionItem;
@override final  String status;
@override final  DateTime? dateCompleted;
@override final  String? manager;
@override final  String? notes;

/// Create a copy of EmployeeReviewModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EmployeeReviewModelCopyWith<_EmployeeReviewModel> get copyWith => __$EmployeeReviewModelCopyWithImpl<_EmployeeReviewModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EmployeeReviewModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EmployeeReviewModel&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.actionItem, actionItem) || other.actionItem == actionItem)&&(identical(other.status, status) || other.status == status)&&(identical(other.dateCompleted, dateCompleted) || other.dateCompleted == dateCompleted)&&(identical(other.manager, manager) || other.manager == manager)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,actionItem,status,dateCompleted,manager,notes);

@override
String toString() {
  return 'EmployeeReviewModel(id: $id, userId: $userId, actionItem: $actionItem, status: $status, dateCompleted: $dateCompleted, manager: $manager, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$EmployeeReviewModelCopyWith<$Res> implements $EmployeeReviewModelCopyWith<$Res> {
  factory _$EmployeeReviewModelCopyWith(_EmployeeReviewModel value, $Res Function(_EmployeeReviewModel) _then) = __$EmployeeReviewModelCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String actionItem, String status, DateTime? dateCompleted, String? manager, String? notes
});




}
/// @nodoc
class __$EmployeeReviewModelCopyWithImpl<$Res>
    implements _$EmployeeReviewModelCopyWith<$Res> {
  __$EmployeeReviewModelCopyWithImpl(this._self, this._then);

  final _EmployeeReviewModel _self;
  final $Res Function(_EmployeeReviewModel) _then;

/// Create a copy of EmployeeReviewModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? actionItem = null,Object? status = null,Object? dateCompleted = freezed,Object? manager = freezed,Object? notes = freezed,}) {
  return _then(_EmployeeReviewModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,actionItem: null == actionItem ? _self.actionItem : actionItem // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,dateCompleted: freezed == dateCompleted ? _self.dateCompleted : dateCompleted // ignore: cast_nullable_to_non_nullable
as DateTime?,manager: freezed == manager ? _self.manager : manager // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
