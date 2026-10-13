// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'checklist_template_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChecklistTask {

 String get id; String get title; bool get isCompleted; String? get notes;
/// Create a copy of ChecklistTask
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChecklistTaskCopyWith<ChecklistTask> get copyWith => _$ChecklistTaskCopyWithImpl<ChecklistTask>(this as ChecklistTask, _$identity);

  /// Serializes this ChecklistTask to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChecklistTask&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.isCompleted, isCompleted) || other.isCompleted == isCompleted)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,isCompleted,notes);

@override
String toString() {
  return 'ChecklistTask(id: $id, title: $title, isCompleted: $isCompleted, notes: $notes)';
}


}

/// @nodoc
abstract mixin class $ChecklistTaskCopyWith<$Res>  {
  factory $ChecklistTaskCopyWith(ChecklistTask value, $Res Function(ChecklistTask) _then) = _$ChecklistTaskCopyWithImpl;
@useResult
$Res call({
 String id, String title, bool isCompleted, String? notes
});




}
/// @nodoc
class _$ChecklistTaskCopyWithImpl<$Res>
    implements $ChecklistTaskCopyWith<$Res> {
  _$ChecklistTaskCopyWithImpl(this._self, this._then);

  final ChecklistTask _self;
  final $Res Function(ChecklistTask) _then;

/// Create a copy of ChecklistTask
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? isCompleted = null,Object? notes = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChecklistTask].
extension ChecklistTaskPatterns on ChecklistTask {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChecklistTask value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChecklistTask() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChecklistTask value)  $default,){
final _that = this;
switch (_that) {
case _ChecklistTask():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChecklistTask value)?  $default,){
final _that = this;
switch (_that) {
case _ChecklistTask() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  bool isCompleted,  String? notes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChecklistTask() when $default != null:
return $default(_that.id,_that.title,_that.isCompleted,_that.notes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  bool isCompleted,  String? notes)  $default,) {final _that = this;
switch (_that) {
case _ChecklistTask():
return $default(_that.id,_that.title,_that.isCompleted,_that.notes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  bool isCompleted,  String? notes)?  $default,) {final _that = this;
switch (_that) {
case _ChecklistTask() when $default != null:
return $default(_that.id,_that.title,_that.isCompleted,_that.notes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChecklistTask implements ChecklistTask {
  const _ChecklistTask({required this.id, required this.title, this.isCompleted = false, this.notes});
  factory _ChecklistTask.fromJson(Map<String, dynamic> json) => _$ChecklistTaskFromJson(json);

@override final  String id;
@override final  String title;
@override@JsonKey() final  bool isCompleted;
@override final  String? notes;

/// Create a copy of ChecklistTask
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChecklistTaskCopyWith<_ChecklistTask> get copyWith => __$ChecklistTaskCopyWithImpl<_ChecklistTask>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChecklistTaskToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChecklistTask&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.isCompleted, isCompleted) || other.isCompleted == isCompleted)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,isCompleted,notes);

@override
String toString() {
  return 'ChecklistTask(id: $id, title: $title, isCompleted: $isCompleted, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$ChecklistTaskCopyWith<$Res> implements $ChecklistTaskCopyWith<$Res> {
  factory _$ChecklistTaskCopyWith(_ChecklistTask value, $Res Function(_ChecklistTask) _then) = __$ChecklistTaskCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, bool isCompleted, String? notes
});




}
/// @nodoc
class __$ChecklistTaskCopyWithImpl<$Res>
    implements _$ChecklistTaskCopyWith<$Res> {
  __$ChecklistTaskCopyWithImpl(this._self, this._then);

  final _ChecklistTask _self;
  final $Res Function(_ChecklistTask) _then;

/// Create a copy of ChecklistTask
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? isCompleted = null,Object? notes = freezed,}) {
  return _then(_ChecklistTask(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ChecklistTemplateModel {

 String get id; String get name; String get color; List<ChecklistTask> get tasks;
/// Create a copy of ChecklistTemplateModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChecklistTemplateModelCopyWith<ChecklistTemplateModel> get copyWith => _$ChecklistTemplateModelCopyWithImpl<ChecklistTemplateModel>(this as ChecklistTemplateModel, _$identity);

  /// Serializes this ChecklistTemplateModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChecklistTemplateModel&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&const DeepCollectionEquality().equals(other.tasks, tasks));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,color,const DeepCollectionEquality().hash(tasks));

@override
String toString() {
  return 'ChecklistTemplateModel(id: $id, name: $name, color: $color, tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class $ChecklistTemplateModelCopyWith<$Res>  {
  factory $ChecklistTemplateModelCopyWith(ChecklistTemplateModel value, $Res Function(ChecklistTemplateModel) _then) = _$ChecklistTemplateModelCopyWithImpl;
@useResult
$Res call({
 String id, String name, String color, List<ChecklistTask> tasks
});




}
/// @nodoc
class _$ChecklistTemplateModelCopyWithImpl<$Res>
    implements $ChecklistTemplateModelCopyWith<$Res> {
  _$ChecklistTemplateModelCopyWithImpl(this._self, this._then);

  final ChecklistTemplateModel _self;
  final $Res Function(ChecklistTemplateModel) _then;

/// Create a copy of ChecklistTemplateModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? color = null,Object? tasks = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,tasks: null == tasks ? _self.tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ChecklistTask>,
  ));
}

}


/// Adds pattern-matching-related methods to [ChecklistTemplateModel].
extension ChecklistTemplateModelPatterns on ChecklistTemplateModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChecklistTemplateModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChecklistTemplateModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChecklistTemplateModel value)  $default,){
final _that = this;
switch (_that) {
case _ChecklistTemplateModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChecklistTemplateModel value)?  $default,){
final _that = this;
switch (_that) {
case _ChecklistTemplateModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String color,  List<ChecklistTask> tasks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChecklistTemplateModel() when $default != null:
return $default(_that.id,_that.name,_that.color,_that.tasks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String color,  List<ChecklistTask> tasks)  $default,) {final _that = this;
switch (_that) {
case _ChecklistTemplateModel():
return $default(_that.id,_that.name,_that.color,_that.tasks);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String color,  List<ChecklistTask> tasks)?  $default,) {final _that = this;
switch (_that) {
case _ChecklistTemplateModel() when $default != null:
return $default(_that.id,_that.name,_that.color,_that.tasks);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChecklistTemplateModel implements ChecklistTemplateModel {
  const _ChecklistTemplateModel({required this.id, required this.name, required this.color, final  List<ChecklistTask> tasks = const []}): _tasks = tasks;
  factory _ChecklistTemplateModel.fromJson(Map<String, dynamic> json) => _$ChecklistTemplateModelFromJson(json);

@override final  String id;
@override final  String name;
@override final  String color;
 final  List<ChecklistTask> _tasks;
@override@JsonKey() List<ChecklistTask> get tasks {
  if (_tasks is EqualUnmodifiableListView) return _tasks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tasks);
}


/// Create a copy of ChecklistTemplateModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChecklistTemplateModelCopyWith<_ChecklistTemplateModel> get copyWith => __$ChecklistTemplateModelCopyWithImpl<_ChecklistTemplateModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChecklistTemplateModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChecklistTemplateModel&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&const DeepCollectionEquality().equals(other._tasks, _tasks));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,color,const DeepCollectionEquality().hash(_tasks));

@override
String toString() {
  return 'ChecklistTemplateModel(id: $id, name: $name, color: $color, tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class _$ChecklistTemplateModelCopyWith<$Res> implements $ChecklistTemplateModelCopyWith<$Res> {
  factory _$ChecklistTemplateModelCopyWith(_ChecklistTemplateModel value, $Res Function(_ChecklistTemplateModel) _then) = __$ChecklistTemplateModelCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String color, List<ChecklistTask> tasks
});




}
/// @nodoc
class __$ChecklistTemplateModelCopyWithImpl<$Res>
    implements _$ChecklistTemplateModelCopyWith<$Res> {
  __$ChecklistTemplateModelCopyWithImpl(this._self, this._then);

  final _ChecklistTemplateModel _self;
  final $Res Function(_ChecklistTemplateModel) _then;

/// Create a copy of ChecklistTemplateModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? color = null,Object? tasks = null,}) {
  return _then(_ChecklistTemplateModel(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,tasks: null == tasks ? _self._tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ChecklistTask>,
  ));
}


}

// dart format on
