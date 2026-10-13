// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$UserModel {

 String? get id;@JsonKey(name: 'first_name') String? get firstName;@JsonKey(name: 'last_name') String? get lastName;@JsonKey(name: 'preferred_name') String? get preferredName; String? get email; String? get title;@JsonKey(name: 'start_date') DateTime? get startDate;@JsonKey(name: 'end_date') DateTime? get endDate; String? get store; String? get position; String? get designation;@JsonKey(name: 'additional_tags') List<String>? get additionalTags;@JsonKey(name: 'working_time') String? get workingTime;@JsonKey(name: 'avg_shifts') String? get avgShifts;@JsonKey(name: 'pay_rate') double? get payRate;@JsonKey(name: 'food_handlers_expiration') DateTime? get foodHandlersExpiration;@JsonKey(name: 'manager_permit_expiration') DateTime? get managerPermitExpiration;@JsonKey(name: 'general_notes') String? get generalNotes;@JsonKey(name: 'hiring_notes') String? get hiringNotes; String? get status;@JsonKey(name: 'completed_tasks') List<String>? get completedTasks;@JsonKey(name: 'completed_checklists') List<String>? get completedChecklists; List<String>? get certifications;@JsonKey(name: 'history_logs') List<Map<String, dynamic>>? get historyLogs;@JsonKey(name: 'active_availability') Map<String, dynamic>? get activeAvailability;@JsonKey(name: 'assigned_checklists') List<String>? get assignedChecklists;@JsonKey(name: 'access_levels') Map<String, bool>? get accessLevels; String? get role;@JsonKey(name: 'is_ops_only') bool? get isOpsOnly;
/// Create a copy of UserModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserModelCopyWith<UserModel> get copyWith => _$UserModelCopyWithImpl<UserModel>(this as UserModel, _$identity);

  /// Serializes this UserModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserModel&&(identical(other.id, id) || other.id == id)&&(identical(other.firstName, firstName) || other.firstName == firstName)&&(identical(other.lastName, lastName) || other.lastName == lastName)&&(identical(other.preferredName, preferredName) || other.preferredName == preferredName)&&(identical(other.email, email) || other.email == email)&&(identical(other.title, title) || other.title == title)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.store, store) || other.store == store)&&(identical(other.position, position) || other.position == position)&&(identical(other.designation, designation) || other.designation == designation)&&const DeepCollectionEquality().equals(other.additionalTags, additionalTags)&&(identical(other.workingTime, workingTime) || other.workingTime == workingTime)&&(identical(other.avgShifts, avgShifts) || other.avgShifts == avgShifts)&&(identical(other.payRate, payRate) || other.payRate == payRate)&&(identical(other.foodHandlersExpiration, foodHandlersExpiration) || other.foodHandlersExpiration == foodHandlersExpiration)&&(identical(other.managerPermitExpiration, managerPermitExpiration) || other.managerPermitExpiration == managerPermitExpiration)&&(identical(other.generalNotes, generalNotes) || other.generalNotes == generalNotes)&&(identical(other.hiringNotes, hiringNotes) || other.hiringNotes == hiringNotes)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.completedTasks, completedTasks)&&const DeepCollectionEquality().equals(other.completedChecklists, completedChecklists)&&const DeepCollectionEquality().equals(other.certifications, certifications)&&const DeepCollectionEquality().equals(other.historyLogs, historyLogs)&&const DeepCollectionEquality().equals(other.activeAvailability, activeAvailability)&&const DeepCollectionEquality().equals(other.assignedChecklists, assignedChecklists)&&const DeepCollectionEquality().equals(other.accessLevels, accessLevels)&&(identical(other.role, role) || other.role == role)&&(identical(other.isOpsOnly, isOpsOnly) || other.isOpsOnly == isOpsOnly));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,firstName,lastName,preferredName,email,title,startDate,endDate,store,position,designation,const DeepCollectionEquality().hash(additionalTags),workingTime,avgShifts,payRate,foodHandlersExpiration,managerPermitExpiration,generalNotes,hiringNotes,status,const DeepCollectionEquality().hash(completedTasks),const DeepCollectionEquality().hash(completedChecklists),const DeepCollectionEquality().hash(certifications),const DeepCollectionEquality().hash(historyLogs),const DeepCollectionEquality().hash(activeAvailability),const DeepCollectionEquality().hash(assignedChecklists),const DeepCollectionEquality().hash(accessLevels),role,isOpsOnly]);

@override
String toString() {
  return 'UserModel(id: $id, firstName: $firstName, lastName: $lastName, preferredName: $preferredName, email: $email, title: $title, startDate: $startDate, endDate: $endDate, store: $store, position: $position, designation: $designation, additionalTags: $additionalTags, workingTime: $workingTime, avgShifts: $avgShifts, payRate: $payRate, foodHandlersExpiration: $foodHandlersExpiration, managerPermitExpiration: $managerPermitExpiration, generalNotes: $generalNotes, hiringNotes: $hiringNotes, status: $status, completedTasks: $completedTasks, completedChecklists: $completedChecklists, certifications: $certifications, historyLogs: $historyLogs, activeAvailability: $activeAvailability, assignedChecklists: $assignedChecklists, accessLevels: $accessLevels, role: $role, isOpsOnly: $isOpsOnly)';
}


}

/// @nodoc
abstract mixin class $UserModelCopyWith<$Res>  {
  factory $UserModelCopyWith(UserModel value, $Res Function(UserModel) _then) = _$UserModelCopyWithImpl;
@useResult
$Res call({
 String? id,@JsonKey(name: 'first_name') String? firstName,@JsonKey(name: 'last_name') String? lastName,@JsonKey(name: 'preferred_name') String? preferredName, String? email, String? title,@JsonKey(name: 'start_date') DateTime? startDate,@JsonKey(name: 'end_date') DateTime? endDate, String? store, String? position, String? designation,@JsonKey(name: 'additional_tags') List<String>? additionalTags,@JsonKey(name: 'working_time') String? workingTime,@JsonKey(name: 'avg_shifts') String? avgShifts,@JsonKey(name: 'pay_rate') double? payRate,@JsonKey(name: 'food_handlers_expiration') DateTime? foodHandlersExpiration,@JsonKey(name: 'manager_permit_expiration') DateTime? managerPermitExpiration,@JsonKey(name: 'general_notes') String? generalNotes,@JsonKey(name: 'hiring_notes') String? hiringNotes, String? status,@JsonKey(name: 'completed_tasks') List<String>? completedTasks,@JsonKey(name: 'completed_checklists') List<String>? completedChecklists, List<String>? certifications,@JsonKey(name: 'history_logs') List<Map<String, dynamic>>? historyLogs,@JsonKey(name: 'active_availability') Map<String, dynamic>? activeAvailability,@JsonKey(name: 'assigned_checklists') List<String>? assignedChecklists,@JsonKey(name: 'access_levels') Map<String, bool>? accessLevels, String? role,@JsonKey(name: 'is_ops_only') bool? isOpsOnly
});




}
/// @nodoc
class _$UserModelCopyWithImpl<$Res>
    implements $UserModelCopyWith<$Res> {
  _$UserModelCopyWithImpl(this._self, this._then);

  final UserModel _self;
  final $Res Function(UserModel) _then;

/// Create a copy of UserModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? firstName = freezed,Object? lastName = freezed,Object? preferredName = freezed,Object? email = freezed,Object? title = freezed,Object? startDate = freezed,Object? endDate = freezed,Object? store = freezed,Object? position = freezed,Object? designation = freezed,Object? additionalTags = freezed,Object? workingTime = freezed,Object? avgShifts = freezed,Object? payRate = freezed,Object? foodHandlersExpiration = freezed,Object? managerPermitExpiration = freezed,Object? generalNotes = freezed,Object? hiringNotes = freezed,Object? status = freezed,Object? completedTasks = freezed,Object? completedChecklists = freezed,Object? certifications = freezed,Object? historyLogs = freezed,Object? activeAvailability = freezed,Object? assignedChecklists = freezed,Object? accessLevels = freezed,Object? role = freezed,Object? isOpsOnly = freezed,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,firstName: freezed == firstName ? _self.firstName : firstName // ignore: cast_nullable_to_non_nullable
as String?,lastName: freezed == lastName ? _self.lastName : lastName // ignore: cast_nullable_to_non_nullable
as String?,preferredName: freezed == preferredName ? _self.preferredName : preferredName // ignore: cast_nullable_to_non_nullable
as String?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,startDate: freezed == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,store: freezed == store ? _self.store : store // ignore: cast_nullable_to_non_nullable
as String?,position: freezed == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as String?,designation: freezed == designation ? _self.designation : designation // ignore: cast_nullable_to_non_nullable
as String?,additionalTags: freezed == additionalTags ? _self.additionalTags : additionalTags // ignore: cast_nullable_to_non_nullable
as List<String>?,workingTime: freezed == workingTime ? _self.workingTime : workingTime // ignore: cast_nullable_to_non_nullable
as String?,avgShifts: freezed == avgShifts ? _self.avgShifts : avgShifts // ignore: cast_nullable_to_non_nullable
as String?,payRate: freezed == payRate ? _self.payRate : payRate // ignore: cast_nullable_to_non_nullable
as double?,foodHandlersExpiration: freezed == foodHandlersExpiration ? _self.foodHandlersExpiration : foodHandlersExpiration // ignore: cast_nullable_to_non_nullable
as DateTime?,managerPermitExpiration: freezed == managerPermitExpiration ? _self.managerPermitExpiration : managerPermitExpiration // ignore: cast_nullable_to_non_nullable
as DateTime?,generalNotes: freezed == generalNotes ? _self.generalNotes : generalNotes // ignore: cast_nullable_to_non_nullable
as String?,hiringNotes: freezed == hiringNotes ? _self.hiringNotes : hiringNotes // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,completedTasks: freezed == completedTasks ? _self.completedTasks : completedTasks // ignore: cast_nullable_to_non_nullable
as List<String>?,completedChecklists: freezed == completedChecklists ? _self.completedChecklists : completedChecklists // ignore: cast_nullable_to_non_nullable
as List<String>?,certifications: freezed == certifications ? _self.certifications : certifications // ignore: cast_nullable_to_non_nullable
as List<String>?,historyLogs: freezed == historyLogs ? _self.historyLogs : historyLogs // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>?,activeAvailability: freezed == activeAvailability ? _self.activeAvailability : activeAvailability // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,assignedChecklists: freezed == assignedChecklists ? _self.assignedChecklists : assignedChecklists // ignore: cast_nullable_to_non_nullable
as List<String>?,accessLevels: freezed == accessLevels ? _self.accessLevels : accessLevels // ignore: cast_nullable_to_non_nullable
as Map<String, bool>?,role: freezed == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String?,isOpsOnly: freezed == isOpsOnly ? _self.isOpsOnly : isOpsOnly // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [UserModel].
extension UserModelPatterns on UserModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UserModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UserModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UserModel value)  $default,){
final _that = this;
switch (_that) {
case _UserModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UserModel value)?  $default,){
final _that = this;
switch (_that) {
case _UserModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? id, @JsonKey(name: 'first_name')  String? firstName, @JsonKey(name: 'last_name')  String? lastName, @JsonKey(name: 'preferred_name')  String? preferredName,  String? email,  String? title, @JsonKey(name: 'start_date')  DateTime? startDate, @JsonKey(name: 'end_date')  DateTime? endDate,  String? store,  String? position,  String? designation, @JsonKey(name: 'additional_tags')  List<String>? additionalTags, @JsonKey(name: 'working_time')  String? workingTime, @JsonKey(name: 'avg_shifts')  String? avgShifts, @JsonKey(name: 'pay_rate')  double? payRate, @JsonKey(name: 'food_handlers_expiration')  DateTime? foodHandlersExpiration, @JsonKey(name: 'manager_permit_expiration')  DateTime? managerPermitExpiration, @JsonKey(name: 'general_notes')  String? generalNotes, @JsonKey(name: 'hiring_notes')  String? hiringNotes,  String? status, @JsonKey(name: 'completed_tasks')  List<String>? completedTasks, @JsonKey(name: 'completed_checklists')  List<String>? completedChecklists,  List<String>? certifications, @JsonKey(name: 'history_logs')  List<Map<String, dynamic>>? historyLogs, @JsonKey(name: 'active_availability')  Map<String, dynamic>? activeAvailability, @JsonKey(name: 'assigned_checklists')  List<String>? assignedChecklists, @JsonKey(name: 'access_levels')  Map<String, bool>? accessLevels,  String? role, @JsonKey(name: 'is_ops_only')  bool? isOpsOnly)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UserModel() when $default != null:
return $default(_that.id,_that.firstName,_that.lastName,_that.preferredName,_that.email,_that.title,_that.startDate,_that.endDate,_that.store,_that.position,_that.designation,_that.additionalTags,_that.workingTime,_that.avgShifts,_that.payRate,_that.foodHandlersExpiration,_that.managerPermitExpiration,_that.generalNotes,_that.hiringNotes,_that.status,_that.completedTasks,_that.completedChecklists,_that.certifications,_that.historyLogs,_that.activeAvailability,_that.assignedChecklists,_that.accessLevels,_that.role,_that.isOpsOnly);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? id, @JsonKey(name: 'first_name')  String? firstName, @JsonKey(name: 'last_name')  String? lastName, @JsonKey(name: 'preferred_name')  String? preferredName,  String? email,  String? title, @JsonKey(name: 'start_date')  DateTime? startDate, @JsonKey(name: 'end_date')  DateTime? endDate,  String? store,  String? position,  String? designation, @JsonKey(name: 'additional_tags')  List<String>? additionalTags, @JsonKey(name: 'working_time')  String? workingTime, @JsonKey(name: 'avg_shifts')  String? avgShifts, @JsonKey(name: 'pay_rate')  double? payRate, @JsonKey(name: 'food_handlers_expiration')  DateTime? foodHandlersExpiration, @JsonKey(name: 'manager_permit_expiration')  DateTime? managerPermitExpiration, @JsonKey(name: 'general_notes')  String? generalNotes, @JsonKey(name: 'hiring_notes')  String? hiringNotes,  String? status, @JsonKey(name: 'completed_tasks')  List<String>? completedTasks, @JsonKey(name: 'completed_checklists')  List<String>? completedChecklists,  List<String>? certifications, @JsonKey(name: 'history_logs')  List<Map<String, dynamic>>? historyLogs, @JsonKey(name: 'active_availability')  Map<String, dynamic>? activeAvailability, @JsonKey(name: 'assigned_checklists')  List<String>? assignedChecklists, @JsonKey(name: 'access_levels')  Map<String, bool>? accessLevels,  String? role, @JsonKey(name: 'is_ops_only')  bool? isOpsOnly)  $default,) {final _that = this;
switch (_that) {
case _UserModel():
return $default(_that.id,_that.firstName,_that.lastName,_that.preferredName,_that.email,_that.title,_that.startDate,_that.endDate,_that.store,_that.position,_that.designation,_that.additionalTags,_that.workingTime,_that.avgShifts,_that.payRate,_that.foodHandlersExpiration,_that.managerPermitExpiration,_that.generalNotes,_that.hiringNotes,_that.status,_that.completedTasks,_that.completedChecklists,_that.certifications,_that.historyLogs,_that.activeAvailability,_that.assignedChecklists,_that.accessLevels,_that.role,_that.isOpsOnly);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? id, @JsonKey(name: 'first_name')  String? firstName, @JsonKey(name: 'last_name')  String? lastName, @JsonKey(name: 'preferred_name')  String? preferredName,  String? email,  String? title, @JsonKey(name: 'start_date')  DateTime? startDate, @JsonKey(name: 'end_date')  DateTime? endDate,  String? store,  String? position,  String? designation, @JsonKey(name: 'additional_tags')  List<String>? additionalTags, @JsonKey(name: 'working_time')  String? workingTime, @JsonKey(name: 'avg_shifts')  String? avgShifts, @JsonKey(name: 'pay_rate')  double? payRate, @JsonKey(name: 'food_handlers_expiration')  DateTime? foodHandlersExpiration, @JsonKey(name: 'manager_permit_expiration')  DateTime? managerPermitExpiration, @JsonKey(name: 'general_notes')  String? generalNotes, @JsonKey(name: 'hiring_notes')  String? hiringNotes,  String? status, @JsonKey(name: 'completed_tasks')  List<String>? completedTasks, @JsonKey(name: 'completed_checklists')  List<String>? completedChecklists,  List<String>? certifications, @JsonKey(name: 'history_logs')  List<Map<String, dynamic>>? historyLogs, @JsonKey(name: 'active_availability')  Map<String, dynamic>? activeAvailability, @JsonKey(name: 'assigned_checklists')  List<String>? assignedChecklists, @JsonKey(name: 'access_levels')  Map<String, bool>? accessLevels,  String? role, @JsonKey(name: 'is_ops_only')  bool? isOpsOnly)?  $default,) {final _that = this;
switch (_that) {
case _UserModel() when $default != null:
return $default(_that.id,_that.firstName,_that.lastName,_that.preferredName,_that.email,_that.title,_that.startDate,_that.endDate,_that.store,_that.position,_that.designation,_that.additionalTags,_that.workingTime,_that.avgShifts,_that.payRate,_that.foodHandlersExpiration,_that.managerPermitExpiration,_that.generalNotes,_that.hiringNotes,_that.status,_that.completedTasks,_that.completedChecklists,_that.certifications,_that.historyLogs,_that.activeAvailability,_that.assignedChecklists,_that.accessLevels,_that.role,_that.isOpsOnly);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _UserModel implements UserModel {
  const _UserModel({this.id, @JsonKey(name: 'first_name') this.firstName, @JsonKey(name: 'last_name') this.lastName, @JsonKey(name: 'preferred_name') this.preferredName, this.email, this.title, @JsonKey(name: 'start_date') this.startDate, @JsonKey(name: 'end_date') this.endDate, this.store, this.position, this.designation, @JsonKey(name: 'additional_tags') final  List<String>? additionalTags = const [], @JsonKey(name: 'working_time') this.workingTime, @JsonKey(name: 'avg_shifts') this.avgShifts, @JsonKey(name: 'pay_rate') this.payRate, @JsonKey(name: 'food_handlers_expiration') this.foodHandlersExpiration, @JsonKey(name: 'manager_permit_expiration') this.managerPermitExpiration, @JsonKey(name: 'general_notes') this.generalNotes, @JsonKey(name: 'hiring_notes') this.hiringNotes, this.status, @JsonKey(name: 'completed_tasks') final  List<String>? completedTasks = const [], @JsonKey(name: 'completed_checklists') final  List<String>? completedChecklists = const [], final  List<String>? certifications = const [], @JsonKey(name: 'history_logs') final  List<Map<String, dynamic>>? historyLogs = const [], @JsonKey(name: 'active_availability') final  Map<String, dynamic>? activeAvailability = const {}, @JsonKey(name: 'assigned_checklists') final  List<String>? assignedChecklists = const [], @JsonKey(name: 'access_levels') final  Map<String, bool>? accessLevels = const {}, this.role, @JsonKey(name: 'is_ops_only') this.isOpsOnly = false}): _additionalTags = additionalTags,_completedTasks = completedTasks,_completedChecklists = completedChecklists,_certifications = certifications,_historyLogs = historyLogs,_activeAvailability = activeAvailability,_assignedChecklists = assignedChecklists,_accessLevels = accessLevels;
  factory _UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);

@override final  String? id;
@override@JsonKey(name: 'first_name') final  String? firstName;
@override@JsonKey(name: 'last_name') final  String? lastName;
@override@JsonKey(name: 'preferred_name') final  String? preferredName;
@override final  String? email;
@override final  String? title;
@override@JsonKey(name: 'start_date') final  DateTime? startDate;
@override@JsonKey(name: 'end_date') final  DateTime? endDate;
@override final  String? store;
@override final  String? position;
@override final  String? designation;
 final  List<String>? _additionalTags;
@override@JsonKey(name: 'additional_tags') List<String>? get additionalTags {
  final value = _additionalTags;
  if (value == null) return null;
  if (_additionalTags is EqualUnmodifiableListView) return _additionalTags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override@JsonKey(name: 'working_time') final  String? workingTime;
@override@JsonKey(name: 'avg_shifts') final  String? avgShifts;
@override@JsonKey(name: 'pay_rate') final  double? payRate;
@override@JsonKey(name: 'food_handlers_expiration') final  DateTime? foodHandlersExpiration;
@override@JsonKey(name: 'manager_permit_expiration') final  DateTime? managerPermitExpiration;
@override@JsonKey(name: 'general_notes') final  String? generalNotes;
@override@JsonKey(name: 'hiring_notes') final  String? hiringNotes;
@override final  String? status;
 final  List<String>? _completedTasks;
@override@JsonKey(name: 'completed_tasks') List<String>? get completedTasks {
  final value = _completedTasks;
  if (value == null) return null;
  if (_completedTasks is EqualUnmodifiableListView) return _completedTasks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<String>? _completedChecklists;
@override@JsonKey(name: 'completed_checklists') List<String>? get completedChecklists {
  final value = _completedChecklists;
  if (value == null) return null;
  if (_completedChecklists is EqualUnmodifiableListView) return _completedChecklists;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<String>? _certifications;
@override@JsonKey() List<String>? get certifications {
  final value = _certifications;
  if (value == null) return null;
  if (_certifications is EqualUnmodifiableListView) return _certifications;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<Map<String, dynamic>>? _historyLogs;
@override@JsonKey(name: 'history_logs') List<Map<String, dynamic>>? get historyLogs {
  final value = _historyLogs;
  if (value == null) return null;
  if (_historyLogs is EqualUnmodifiableListView) return _historyLogs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  Map<String, dynamic>? _activeAvailability;
@override@JsonKey(name: 'active_availability') Map<String, dynamic>? get activeAvailability {
  final value = _activeAvailability;
  if (value == null) return null;
  if (_activeAvailability is EqualUnmodifiableMapView) return _activeAvailability;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

 final  List<String>? _assignedChecklists;
@override@JsonKey(name: 'assigned_checklists') List<String>? get assignedChecklists {
  final value = _assignedChecklists;
  if (value == null) return null;
  if (_assignedChecklists is EqualUnmodifiableListView) return _assignedChecklists;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  Map<String, bool>? _accessLevels;
@override@JsonKey(name: 'access_levels') Map<String, bool>? get accessLevels {
  final value = _accessLevels;
  if (value == null) return null;
  if (_accessLevels is EqualUnmodifiableMapView) return _accessLevels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  String? role;
@override@JsonKey(name: 'is_ops_only') final  bool? isOpsOnly;

/// Create a copy of UserModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UserModelCopyWith<_UserModel> get copyWith => __$UserModelCopyWithImpl<_UserModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$UserModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UserModel&&(identical(other.id, id) || other.id == id)&&(identical(other.firstName, firstName) || other.firstName == firstName)&&(identical(other.lastName, lastName) || other.lastName == lastName)&&(identical(other.preferredName, preferredName) || other.preferredName == preferredName)&&(identical(other.email, email) || other.email == email)&&(identical(other.title, title) || other.title == title)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.store, store) || other.store == store)&&(identical(other.position, position) || other.position == position)&&(identical(other.designation, designation) || other.designation == designation)&&const DeepCollectionEquality().equals(other._additionalTags, _additionalTags)&&(identical(other.workingTime, workingTime) || other.workingTime == workingTime)&&(identical(other.avgShifts, avgShifts) || other.avgShifts == avgShifts)&&(identical(other.payRate, payRate) || other.payRate == payRate)&&(identical(other.foodHandlersExpiration, foodHandlersExpiration) || other.foodHandlersExpiration == foodHandlersExpiration)&&(identical(other.managerPermitExpiration, managerPermitExpiration) || other.managerPermitExpiration == managerPermitExpiration)&&(identical(other.generalNotes, generalNotes) || other.generalNotes == generalNotes)&&(identical(other.hiringNotes, hiringNotes) || other.hiringNotes == hiringNotes)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other._completedTasks, _completedTasks)&&const DeepCollectionEquality().equals(other._completedChecklists, _completedChecklists)&&const DeepCollectionEquality().equals(other._certifications, _certifications)&&const DeepCollectionEquality().equals(other._historyLogs, _historyLogs)&&const DeepCollectionEquality().equals(other._activeAvailability, _activeAvailability)&&const DeepCollectionEquality().equals(other._assignedChecklists, _assignedChecklists)&&const DeepCollectionEquality().equals(other._accessLevels, _accessLevels)&&(identical(other.role, role) || other.role == role)&&(identical(other.isOpsOnly, isOpsOnly) || other.isOpsOnly == isOpsOnly));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,firstName,lastName,preferredName,email,title,startDate,endDate,store,position,designation,const DeepCollectionEquality().hash(_additionalTags),workingTime,avgShifts,payRate,foodHandlersExpiration,managerPermitExpiration,generalNotes,hiringNotes,status,const DeepCollectionEquality().hash(_completedTasks),const DeepCollectionEquality().hash(_completedChecklists),const DeepCollectionEquality().hash(_certifications),const DeepCollectionEquality().hash(_historyLogs),const DeepCollectionEquality().hash(_activeAvailability),const DeepCollectionEquality().hash(_assignedChecklists),const DeepCollectionEquality().hash(_accessLevels),role,isOpsOnly]);

@override
String toString() {
  return 'UserModel(id: $id, firstName: $firstName, lastName: $lastName, preferredName: $preferredName, email: $email, title: $title, startDate: $startDate, endDate: $endDate, store: $store, position: $position, designation: $designation, additionalTags: $additionalTags, workingTime: $workingTime, avgShifts: $avgShifts, payRate: $payRate, foodHandlersExpiration: $foodHandlersExpiration, managerPermitExpiration: $managerPermitExpiration, generalNotes: $generalNotes, hiringNotes: $hiringNotes, status: $status, completedTasks: $completedTasks, completedChecklists: $completedChecklists, certifications: $certifications, historyLogs: $historyLogs, activeAvailability: $activeAvailability, assignedChecklists: $assignedChecklists, accessLevels: $accessLevels, role: $role, isOpsOnly: $isOpsOnly)';
}


}

/// @nodoc
abstract mixin class _$UserModelCopyWith<$Res> implements $UserModelCopyWith<$Res> {
  factory _$UserModelCopyWith(_UserModel value, $Res Function(_UserModel) _then) = __$UserModelCopyWithImpl;
@override @useResult
$Res call({
 String? id,@JsonKey(name: 'first_name') String? firstName,@JsonKey(name: 'last_name') String? lastName,@JsonKey(name: 'preferred_name') String? preferredName, String? email, String? title,@JsonKey(name: 'start_date') DateTime? startDate,@JsonKey(name: 'end_date') DateTime? endDate, String? store, String? position, String? designation,@JsonKey(name: 'additional_tags') List<String>? additionalTags,@JsonKey(name: 'working_time') String? workingTime,@JsonKey(name: 'avg_shifts') String? avgShifts,@JsonKey(name: 'pay_rate') double? payRate,@JsonKey(name: 'food_handlers_expiration') DateTime? foodHandlersExpiration,@JsonKey(name: 'manager_permit_expiration') DateTime? managerPermitExpiration,@JsonKey(name: 'general_notes') String? generalNotes,@JsonKey(name: 'hiring_notes') String? hiringNotes, String? status,@JsonKey(name: 'completed_tasks') List<String>? completedTasks,@JsonKey(name: 'completed_checklists') List<String>? completedChecklists, List<String>? certifications,@JsonKey(name: 'history_logs') List<Map<String, dynamic>>? historyLogs,@JsonKey(name: 'active_availability') Map<String, dynamic>? activeAvailability,@JsonKey(name: 'assigned_checklists') List<String>? assignedChecklists,@JsonKey(name: 'access_levels') Map<String, bool>? accessLevels, String? role,@JsonKey(name: 'is_ops_only') bool? isOpsOnly
});




}
/// @nodoc
class __$UserModelCopyWithImpl<$Res>
    implements _$UserModelCopyWith<$Res> {
  __$UserModelCopyWithImpl(this._self, this._then);

  final _UserModel _self;
  final $Res Function(_UserModel) _then;

/// Create a copy of UserModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? firstName = freezed,Object? lastName = freezed,Object? preferredName = freezed,Object? email = freezed,Object? title = freezed,Object? startDate = freezed,Object? endDate = freezed,Object? store = freezed,Object? position = freezed,Object? designation = freezed,Object? additionalTags = freezed,Object? workingTime = freezed,Object? avgShifts = freezed,Object? payRate = freezed,Object? foodHandlersExpiration = freezed,Object? managerPermitExpiration = freezed,Object? generalNotes = freezed,Object? hiringNotes = freezed,Object? status = freezed,Object? completedTasks = freezed,Object? completedChecklists = freezed,Object? certifications = freezed,Object? historyLogs = freezed,Object? activeAvailability = freezed,Object? assignedChecklists = freezed,Object? accessLevels = freezed,Object? role = freezed,Object? isOpsOnly = freezed,}) {
  return _then(_UserModel(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,firstName: freezed == firstName ? _self.firstName : firstName // ignore: cast_nullable_to_non_nullable
as String?,lastName: freezed == lastName ? _self.lastName : lastName // ignore: cast_nullable_to_non_nullable
as String?,preferredName: freezed == preferredName ? _self.preferredName : preferredName // ignore: cast_nullable_to_non_nullable
as String?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,startDate: freezed == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,store: freezed == store ? _self.store : store // ignore: cast_nullable_to_non_nullable
as String?,position: freezed == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as String?,designation: freezed == designation ? _self.designation : designation // ignore: cast_nullable_to_non_nullable
as String?,additionalTags: freezed == additionalTags ? _self._additionalTags : additionalTags // ignore: cast_nullable_to_non_nullable
as List<String>?,workingTime: freezed == workingTime ? _self.workingTime : workingTime // ignore: cast_nullable_to_non_nullable
as String?,avgShifts: freezed == avgShifts ? _self.avgShifts : avgShifts // ignore: cast_nullable_to_non_nullable
as String?,payRate: freezed == payRate ? _self.payRate : payRate // ignore: cast_nullable_to_non_nullable
as double?,foodHandlersExpiration: freezed == foodHandlersExpiration ? _self.foodHandlersExpiration : foodHandlersExpiration // ignore: cast_nullable_to_non_nullable
as DateTime?,managerPermitExpiration: freezed == managerPermitExpiration ? _self.managerPermitExpiration : managerPermitExpiration // ignore: cast_nullable_to_non_nullable
as DateTime?,generalNotes: freezed == generalNotes ? _self.generalNotes : generalNotes // ignore: cast_nullable_to_non_nullable
as String?,hiringNotes: freezed == hiringNotes ? _self.hiringNotes : hiringNotes // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String?,completedTasks: freezed == completedTasks ? _self._completedTasks : completedTasks // ignore: cast_nullable_to_non_nullable
as List<String>?,completedChecklists: freezed == completedChecklists ? _self._completedChecklists : completedChecklists // ignore: cast_nullable_to_non_nullable
as List<String>?,certifications: freezed == certifications ? _self._certifications : certifications // ignore: cast_nullable_to_non_nullable
as List<String>?,historyLogs: freezed == historyLogs ? _self._historyLogs : historyLogs // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>?,activeAvailability: freezed == activeAvailability ? _self._activeAvailability : activeAvailability // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,assignedChecklists: freezed == assignedChecklists ? _self._assignedChecklists : assignedChecklists // ignore: cast_nullable_to_non_nullable
as List<String>?,accessLevels: freezed == accessLevels ? _self._accessLevels : accessLevels // ignore: cast_nullable_to_non_nullable
as Map<String, bool>?,role: freezed == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String?,isOpsOnly: freezed == isOpsOnly ? _self.isOpsOnly : isOpsOnly // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

// dart format on
