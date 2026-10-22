// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'store_settings_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TitleConfig {

 String get id; String get color; String get name; bool get isLeadership; bool get splitInArea; bool get isolatedRoster; bool get linkChecklist; bool get mgrPermit; String? get linkedChecklistId; bool get autoPromoteOnChecklist;
/// Create a copy of TitleConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TitleConfigCopyWith<TitleConfig> get copyWith => _$TitleConfigCopyWithImpl<TitleConfig>(this as TitleConfig, _$identity);

  /// Serializes this TitleConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TitleConfig&&(identical(other.id, id) || other.id == id)&&(identical(other.color, color) || other.color == color)&&(identical(other.name, name) || other.name == name)&&(identical(other.isLeadership, isLeadership) || other.isLeadership == isLeadership)&&(identical(other.splitInArea, splitInArea) || other.splitInArea == splitInArea)&&(identical(other.isolatedRoster, isolatedRoster) || other.isolatedRoster == isolatedRoster)&&(identical(other.linkChecklist, linkChecklist) || other.linkChecklist == linkChecklist)&&(identical(other.mgrPermit, mgrPermit) || other.mgrPermit == mgrPermit)&&(identical(other.linkedChecklistId, linkedChecklistId) || other.linkedChecklistId == linkedChecklistId)&&(identical(other.autoPromoteOnChecklist, autoPromoteOnChecklist) || other.autoPromoteOnChecklist == autoPromoteOnChecklist));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,color,name,isLeadership,splitInArea,isolatedRoster,linkChecklist,mgrPermit,linkedChecklistId,autoPromoteOnChecklist);

@override
String toString() {
  return 'TitleConfig(id: $id, color: $color, name: $name, isLeadership: $isLeadership, splitInArea: $splitInArea, isolatedRoster: $isolatedRoster, linkChecklist: $linkChecklist, mgrPermit: $mgrPermit, linkedChecklistId: $linkedChecklistId, autoPromoteOnChecklist: $autoPromoteOnChecklist)';
}


}

/// @nodoc
abstract mixin class $TitleConfigCopyWith<$Res>  {
  factory $TitleConfigCopyWith(TitleConfig value, $Res Function(TitleConfig) _then) = _$TitleConfigCopyWithImpl;
@useResult
$Res call({
 String id, String color, String name, bool isLeadership, bool splitInArea, bool isolatedRoster, bool linkChecklist, bool mgrPermit, String? linkedChecklistId, bool autoPromoteOnChecklist
});




}
/// @nodoc
class _$TitleConfigCopyWithImpl<$Res>
    implements $TitleConfigCopyWith<$Res> {
  _$TitleConfigCopyWithImpl(this._self, this._then);

  final TitleConfig _self;
  final $Res Function(TitleConfig) _then;

/// Create a copy of TitleConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? color = null,Object? name = null,Object? isLeadership = null,Object? splitInArea = null,Object? isolatedRoster = null,Object? linkChecklist = null,Object? mgrPermit = null,Object? linkedChecklistId = freezed,Object? autoPromoteOnChecklist = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,isLeadership: null == isLeadership ? _self.isLeadership : isLeadership // ignore: cast_nullable_to_non_nullable
as bool,splitInArea: null == splitInArea ? _self.splitInArea : splitInArea // ignore: cast_nullable_to_non_nullable
as bool,isolatedRoster: null == isolatedRoster ? _self.isolatedRoster : isolatedRoster // ignore: cast_nullable_to_non_nullable
as bool,linkChecklist: null == linkChecklist ? _self.linkChecklist : linkChecklist // ignore: cast_nullable_to_non_nullable
as bool,mgrPermit: null == mgrPermit ? _self.mgrPermit : mgrPermit // ignore: cast_nullable_to_non_nullable
as bool,linkedChecklistId: freezed == linkedChecklistId ? _self.linkedChecklistId : linkedChecklistId // ignore: cast_nullable_to_non_nullable
as String?,autoPromoteOnChecklist: null == autoPromoteOnChecklist ? _self.autoPromoteOnChecklist : autoPromoteOnChecklist // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [TitleConfig].
extension TitleConfigPatterns on TitleConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TitleConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TitleConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TitleConfig value)  $default,){
final _that = this;
switch (_that) {
case _TitleConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TitleConfig value)?  $default,){
final _that = this;
switch (_that) {
case _TitleConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String color,  String name,  bool isLeadership,  bool splitInArea,  bool isolatedRoster,  bool linkChecklist,  bool mgrPermit,  String? linkedChecklistId,  bool autoPromoteOnChecklist)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TitleConfig() when $default != null:
return $default(_that.id,_that.color,_that.name,_that.isLeadership,_that.splitInArea,_that.isolatedRoster,_that.linkChecklist,_that.mgrPermit,_that.linkedChecklistId,_that.autoPromoteOnChecklist);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String color,  String name,  bool isLeadership,  bool splitInArea,  bool isolatedRoster,  bool linkChecklist,  bool mgrPermit,  String? linkedChecklistId,  bool autoPromoteOnChecklist)  $default,) {final _that = this;
switch (_that) {
case _TitleConfig():
return $default(_that.id,_that.color,_that.name,_that.isLeadership,_that.splitInArea,_that.isolatedRoster,_that.linkChecklist,_that.mgrPermit,_that.linkedChecklistId,_that.autoPromoteOnChecklist);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String color,  String name,  bool isLeadership,  bool splitInArea,  bool isolatedRoster,  bool linkChecklist,  bool mgrPermit,  String? linkedChecklistId,  bool autoPromoteOnChecklist)?  $default,) {final _that = this;
switch (_that) {
case _TitleConfig() when $default != null:
return $default(_that.id,_that.color,_that.name,_that.isLeadership,_that.splitInArea,_that.isolatedRoster,_that.linkChecklist,_that.mgrPermit,_that.linkedChecklistId,_that.autoPromoteOnChecklist);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TitleConfig implements TitleConfig {
  const _TitleConfig({required this.id, this.color = 'Color', this.name = '', this.isLeadership = false, this.splitInArea = false, this.isolatedRoster = false, this.linkChecklist = false, this.mgrPermit = false, this.linkedChecklistId, this.autoPromoteOnChecklist = false});
  factory _TitleConfig.fromJson(Map<String, dynamic> json) => _$TitleConfigFromJson(json);

@override final  String id;
@override@JsonKey() final  String color;
@override@JsonKey() final  String name;
@override@JsonKey() final  bool isLeadership;
@override@JsonKey() final  bool splitInArea;
@override@JsonKey() final  bool isolatedRoster;
@override@JsonKey() final  bool linkChecklist;
@override@JsonKey() final  bool mgrPermit;
@override final  String? linkedChecklistId;
@override@JsonKey() final  bool autoPromoteOnChecklist;

/// Create a copy of TitleConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TitleConfigCopyWith<_TitleConfig> get copyWith => __$TitleConfigCopyWithImpl<_TitleConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TitleConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TitleConfig&&(identical(other.id, id) || other.id == id)&&(identical(other.color, color) || other.color == color)&&(identical(other.name, name) || other.name == name)&&(identical(other.isLeadership, isLeadership) || other.isLeadership == isLeadership)&&(identical(other.splitInArea, splitInArea) || other.splitInArea == splitInArea)&&(identical(other.isolatedRoster, isolatedRoster) || other.isolatedRoster == isolatedRoster)&&(identical(other.linkChecklist, linkChecklist) || other.linkChecklist == linkChecklist)&&(identical(other.mgrPermit, mgrPermit) || other.mgrPermit == mgrPermit)&&(identical(other.linkedChecklistId, linkedChecklistId) || other.linkedChecklistId == linkedChecklistId)&&(identical(other.autoPromoteOnChecklist, autoPromoteOnChecklist) || other.autoPromoteOnChecklist == autoPromoteOnChecklist));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,color,name,isLeadership,splitInArea,isolatedRoster,linkChecklist,mgrPermit,linkedChecklistId,autoPromoteOnChecklist);

@override
String toString() {
  return 'TitleConfig(id: $id, color: $color, name: $name, isLeadership: $isLeadership, splitInArea: $splitInArea, isolatedRoster: $isolatedRoster, linkChecklist: $linkChecklist, mgrPermit: $mgrPermit, linkedChecklistId: $linkedChecklistId, autoPromoteOnChecklist: $autoPromoteOnChecklist)';
}


}

/// @nodoc
abstract mixin class _$TitleConfigCopyWith<$Res> implements $TitleConfigCopyWith<$Res> {
  factory _$TitleConfigCopyWith(_TitleConfig value, $Res Function(_TitleConfig) _then) = __$TitleConfigCopyWithImpl;
@override @useResult
$Res call({
 String id, String color, String name, bool isLeadership, bool splitInArea, bool isolatedRoster, bool linkChecklist, bool mgrPermit, String? linkedChecklistId, bool autoPromoteOnChecklist
});




}
/// @nodoc
class __$TitleConfigCopyWithImpl<$Res>
    implements _$TitleConfigCopyWith<$Res> {
  __$TitleConfigCopyWithImpl(this._self, this._then);

  final _TitleConfig _self;
  final $Res Function(_TitleConfig) _then;

/// Create a copy of TitleConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? color = null,Object? name = null,Object? isLeadership = null,Object? splitInArea = null,Object? isolatedRoster = null,Object? linkChecklist = null,Object? mgrPermit = null,Object? linkedChecklistId = freezed,Object? autoPromoteOnChecklist = null,}) {
  return _then(_TitleConfig(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,isLeadership: null == isLeadership ? _self.isLeadership : isLeadership // ignore: cast_nullable_to_non_nullable
as bool,splitInArea: null == splitInArea ? _self.splitInArea : splitInArea // ignore: cast_nullable_to_non_nullable
as bool,isolatedRoster: null == isolatedRoster ? _self.isolatedRoster : isolatedRoster // ignore: cast_nullable_to_non_nullable
as bool,linkChecklist: null == linkChecklist ? _self.linkChecklist : linkChecklist // ignore: cast_nullable_to_non_nullable
as bool,mgrPermit: null == mgrPermit ? _self.mgrPermit : mgrPermit // ignore: cast_nullable_to_non_nullable
as bool,linkedChecklistId: freezed == linkedChecklistId ? _self.linkedChecklistId : linkedChecklistId // ignore: cast_nullable_to_non_nullable
as String?,autoPromoteOnChecklist: null == autoPromoteOnChecklist ? _self.autoPromoteOnChecklist : autoPromoteOnChecklist // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$ChecklistTaskItem {

 String get id; String get text; List<String> get positions;
/// Create a copy of ChecklistTaskItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChecklistTaskItemCopyWith<ChecklistTaskItem> get copyWith => _$ChecklistTaskItemCopyWithImpl<ChecklistTaskItem>(this as ChecklistTaskItem, _$identity);

  /// Serializes this ChecklistTaskItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChecklistTaskItem&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text)&&const DeepCollectionEquality().equals(other.positions, positions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,text,const DeepCollectionEquality().hash(positions));

@override
String toString() {
  return 'ChecklistTaskItem(id: $id, text: $text, positions: $positions)';
}


}

/// @nodoc
abstract mixin class $ChecklistTaskItemCopyWith<$Res>  {
  factory $ChecklistTaskItemCopyWith(ChecklistTaskItem value, $Res Function(ChecklistTaskItem) _then) = _$ChecklistTaskItemCopyWithImpl;
@useResult
$Res call({
 String id, String text, List<String> positions
});




}
/// @nodoc
class _$ChecklistTaskItemCopyWithImpl<$Res>
    implements $ChecklistTaskItemCopyWith<$Res> {
  _$ChecklistTaskItemCopyWithImpl(this._self, this._then);

  final ChecklistTaskItem _self;
  final $Res Function(ChecklistTaskItem) _then;

/// Create a copy of ChecklistTaskItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? text = null,Object? positions = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,positions: null == positions ? _self.positions : positions // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [ChecklistTaskItem].
extension ChecklistTaskItemPatterns on ChecklistTaskItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChecklistTaskItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChecklistTaskItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChecklistTaskItem value)  $default,){
final _that = this;
switch (_that) {
case _ChecklistTaskItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChecklistTaskItem value)?  $default,){
final _that = this;
switch (_that) {
case _ChecklistTaskItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String text,  List<String> positions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChecklistTaskItem() when $default != null:
return $default(_that.id,_that.text,_that.positions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String text,  List<String> positions)  $default,) {final _that = this;
switch (_that) {
case _ChecklistTaskItem():
return $default(_that.id,_that.text,_that.positions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String text,  List<String> positions)?  $default,) {final _that = this;
switch (_that) {
case _ChecklistTaskItem() when $default != null:
return $default(_that.id,_that.text,_that.positions);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChecklistTaskItem implements ChecklistTaskItem {
  const _ChecklistTaskItem({required this.id, required this.text, final  List<String> positions = const []}): _positions = positions;
  factory _ChecklistTaskItem.fromJson(Map<String, dynamic> json) => _$ChecklistTaskItemFromJson(json);

@override final  String id;
@override final  String text;
 final  List<String> _positions;
@override@JsonKey() List<String> get positions {
  if (_positions is EqualUnmodifiableListView) return _positions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_positions);
}


/// Create a copy of ChecklistTaskItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChecklistTaskItemCopyWith<_ChecklistTaskItem> get copyWith => __$ChecklistTaskItemCopyWithImpl<_ChecklistTaskItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChecklistTaskItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChecklistTaskItem&&(identical(other.id, id) || other.id == id)&&(identical(other.text, text) || other.text == text)&&const DeepCollectionEquality().equals(other._positions, _positions));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,text,const DeepCollectionEquality().hash(_positions));

@override
String toString() {
  return 'ChecklistTaskItem(id: $id, text: $text, positions: $positions)';
}


}

/// @nodoc
abstract mixin class _$ChecklistTaskItemCopyWith<$Res> implements $ChecklistTaskItemCopyWith<$Res> {
  factory _$ChecklistTaskItemCopyWith(_ChecklistTaskItem value, $Res Function(_ChecklistTaskItem) _then) = __$ChecklistTaskItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String text, List<String> positions
});




}
/// @nodoc
class __$ChecklistTaskItemCopyWithImpl<$Res>
    implements _$ChecklistTaskItemCopyWith<$Res> {
  __$ChecklistTaskItemCopyWithImpl(this._self, this._then);

  final _ChecklistTaskItem _self;
  final $Res Function(_ChecklistTaskItem) _then;

/// Create a copy of ChecklistTaskItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? text = null,Object? positions = null,}) {
  return _then(_ChecklistTaskItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,positions: null == positions ? _self._positions : positions // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}


/// @nodoc
mixin _$ChecklistConfig {

 String get id; String get name; String get color; List<String> get items;@JsonKey(fromJson: _tasksFromJson, toJson: _tasksToJson) List<ChecklistTaskItem> get tasks;
/// Create a copy of ChecklistConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChecklistConfigCopyWith<ChecklistConfig> get copyWith => _$ChecklistConfigCopyWithImpl<ChecklistConfig>(this as ChecklistConfig, _$identity);

  /// Serializes this ChecklistConfig to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChecklistConfig&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&const DeepCollectionEquality().equals(other.items, items)&&const DeepCollectionEquality().equals(other.tasks, tasks));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,color,const DeepCollectionEquality().hash(items),const DeepCollectionEquality().hash(tasks));

@override
String toString() {
  return 'ChecklistConfig(id: $id, name: $name, color: $color, items: $items, tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class $ChecklistConfigCopyWith<$Res>  {
  factory $ChecklistConfigCopyWith(ChecklistConfig value, $Res Function(ChecklistConfig) _then) = _$ChecklistConfigCopyWithImpl;
@useResult
$Res call({
 String id, String name, String color, List<String> items,@JsonKey(fromJson: _tasksFromJson, toJson: _tasksToJson) List<ChecklistTaskItem> tasks
});




}
/// @nodoc
class _$ChecklistConfigCopyWithImpl<$Res>
    implements $ChecklistConfigCopyWith<$Res> {
  _$ChecklistConfigCopyWithImpl(this._self, this._then);

  final ChecklistConfig _self;
  final $Res Function(ChecklistConfig) _then;

/// Create a copy of ChecklistConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? color = null,Object? items = null,Object? tasks = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<String>,tasks: null == tasks ? _self.tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ChecklistTaskItem>,
  ));
}

}


/// Adds pattern-matching-related methods to [ChecklistConfig].
extension ChecklistConfigPatterns on ChecklistConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChecklistConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChecklistConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChecklistConfig value)  $default,){
final _that = this;
switch (_that) {
case _ChecklistConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChecklistConfig value)?  $default,){
final _that = this;
switch (_that) {
case _ChecklistConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String color,  List<String> items, @JsonKey(fromJson: _tasksFromJson, toJson: _tasksToJson)  List<ChecklistTaskItem> tasks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChecklistConfig() when $default != null:
return $default(_that.id,_that.name,_that.color,_that.items,_that.tasks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String color,  List<String> items, @JsonKey(fromJson: _tasksFromJson, toJson: _tasksToJson)  List<ChecklistTaskItem> tasks)  $default,) {final _that = this;
switch (_that) {
case _ChecklistConfig():
return $default(_that.id,_that.name,_that.color,_that.items,_that.tasks);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String color,  List<String> items, @JsonKey(fromJson: _tasksFromJson, toJson: _tasksToJson)  List<ChecklistTaskItem> tasks)?  $default,) {final _that = this;
switch (_that) {
case _ChecklistConfig() when $default != null:
return $default(_that.id,_that.name,_that.color,_that.items,_that.tasks);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChecklistConfig extends ChecklistConfig {
  const _ChecklistConfig({required this.id, required this.name, this.color = 'Color', final  List<String> items = const [], @JsonKey(fromJson: _tasksFromJson, toJson: _tasksToJson) final  List<ChecklistTaskItem> tasks = const []}): _items = items,_tasks = tasks,super._();
  factory _ChecklistConfig.fromJson(Map<String, dynamic> json) => _$ChecklistConfigFromJson(json);

@override final  String id;
@override final  String name;
@override@JsonKey() final  String color;
 final  List<String> _items;
@override@JsonKey() List<String> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

 final  List<ChecklistTaskItem> _tasks;
@override@JsonKey(fromJson: _tasksFromJson, toJson: _tasksToJson) List<ChecklistTaskItem> get tasks {
  if (_tasks is EqualUnmodifiableListView) return _tasks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tasks);
}


/// Create a copy of ChecklistConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChecklistConfigCopyWith<_ChecklistConfig> get copyWith => __$ChecklistConfigCopyWithImpl<_ChecklistConfig>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChecklistConfigToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChecklistConfig&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&const DeepCollectionEquality().equals(other._items, _items)&&const DeepCollectionEquality().equals(other._tasks, _tasks));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,color,const DeepCollectionEquality().hash(_items),const DeepCollectionEquality().hash(_tasks));

@override
String toString() {
  return 'ChecklistConfig(id: $id, name: $name, color: $color, items: $items, tasks: $tasks)';
}


}

/// @nodoc
abstract mixin class _$ChecklistConfigCopyWith<$Res> implements $ChecklistConfigCopyWith<$Res> {
  factory _$ChecklistConfigCopyWith(_ChecklistConfig value, $Res Function(_ChecklistConfig) _then) = __$ChecklistConfigCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String color, List<String> items,@JsonKey(fromJson: _tasksFromJson, toJson: _tasksToJson) List<ChecklistTaskItem> tasks
});




}
/// @nodoc
class __$ChecklistConfigCopyWithImpl<$Res>
    implements _$ChecklistConfigCopyWith<$Res> {
  __$ChecklistConfigCopyWithImpl(this._self, this._then);

  final _ChecklistConfig _self;
  final $Res Function(_ChecklistConfig) _then;

/// Create a copy of ChecklistConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? color = null,Object? items = null,Object? tasks = null,}) {
  return _then(_ChecklistConfig(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<String>,tasks: null == tasks ? _self._tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<ChecklistTaskItem>,
  ));
}


}


/// @nodoc
mixin _$StoreSettingsModel {

@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) List<TitleConfig> get titles;@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) List<TitleConfig> get tags; List<String> get workingTimes; List<String> get positions; List<String> get designations;@JsonKey(fromJson: _checklistsFromJson, toJson: _checklistsToJson) List<ChecklistConfig> get checklists; bool get autoPurgeFormer; int get purgeDaysGone; bool get isScheduleEnabled; bool get isShiftBoardEnabled; List<String> get employeeDataSummaryFields; bool get showOwnerInRoster;
/// Create a copy of StoreSettingsModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoreSettingsModelCopyWith<StoreSettingsModel> get copyWith => _$StoreSettingsModelCopyWithImpl<StoreSettingsModel>(this as StoreSettingsModel, _$identity);

  /// Serializes this StoreSettingsModel to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StoreSettingsModel&&const DeepCollectionEquality().equals(other.titles, titles)&&const DeepCollectionEquality().equals(other.tags, tags)&&const DeepCollectionEquality().equals(other.workingTimes, workingTimes)&&const DeepCollectionEquality().equals(other.positions, positions)&&const DeepCollectionEquality().equals(other.designations, designations)&&const DeepCollectionEquality().equals(other.checklists, checklists)&&(identical(other.autoPurgeFormer, autoPurgeFormer) || other.autoPurgeFormer == autoPurgeFormer)&&(identical(other.purgeDaysGone, purgeDaysGone) || other.purgeDaysGone == purgeDaysGone)&&(identical(other.isScheduleEnabled, isScheduleEnabled) || other.isScheduleEnabled == isScheduleEnabled)&&(identical(other.isShiftBoardEnabled, isShiftBoardEnabled) || other.isShiftBoardEnabled == isShiftBoardEnabled)&&const DeepCollectionEquality().equals(other.employeeDataSummaryFields, employeeDataSummaryFields)&&(identical(other.showOwnerInRoster, showOwnerInRoster) || other.showOwnerInRoster == showOwnerInRoster));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(titles),const DeepCollectionEquality().hash(tags),const DeepCollectionEquality().hash(workingTimes),const DeepCollectionEquality().hash(positions),const DeepCollectionEquality().hash(designations),const DeepCollectionEquality().hash(checklists),autoPurgeFormer,purgeDaysGone,isScheduleEnabled,isShiftBoardEnabled,const DeepCollectionEquality().hash(employeeDataSummaryFields),showOwnerInRoster);

@override
String toString() {
  return 'StoreSettingsModel(titles: $titles, tags: $tags, workingTimes: $workingTimes, positions: $positions, designations: $designations, checklists: $checklists, autoPurgeFormer: $autoPurgeFormer, purgeDaysGone: $purgeDaysGone, isScheduleEnabled: $isScheduleEnabled, isShiftBoardEnabled: $isShiftBoardEnabled, employeeDataSummaryFields: $employeeDataSummaryFields, showOwnerInRoster: $showOwnerInRoster)';
}


}

/// @nodoc
abstract mixin class $StoreSettingsModelCopyWith<$Res>  {
  factory $StoreSettingsModelCopyWith(StoreSettingsModel value, $Res Function(StoreSettingsModel) _then) = _$StoreSettingsModelCopyWithImpl;
@useResult
$Res call({
@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) List<TitleConfig> titles,@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) List<TitleConfig> tags, List<String> workingTimes, List<String> positions, List<String> designations,@JsonKey(fromJson: _checklistsFromJson, toJson: _checklistsToJson) List<ChecklistConfig> checklists, bool autoPurgeFormer, int purgeDaysGone, bool isScheduleEnabled, bool isShiftBoardEnabled, List<String> employeeDataSummaryFields, bool showOwnerInRoster
});




}
/// @nodoc
class _$StoreSettingsModelCopyWithImpl<$Res>
    implements $StoreSettingsModelCopyWith<$Res> {
  _$StoreSettingsModelCopyWithImpl(this._self, this._then);

  final StoreSettingsModel _self;
  final $Res Function(StoreSettingsModel) _then;

/// Create a copy of StoreSettingsModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? titles = null,Object? tags = null,Object? workingTimes = null,Object? positions = null,Object? designations = null,Object? checklists = null,Object? autoPurgeFormer = null,Object? purgeDaysGone = null,Object? isScheduleEnabled = null,Object? isShiftBoardEnabled = null,Object? employeeDataSummaryFields = null,Object? showOwnerInRoster = null,}) {
  return _then(_self.copyWith(
titles: null == titles ? _self.titles : titles // ignore: cast_nullable_to_non_nullable
as List<TitleConfig>,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<TitleConfig>,workingTimes: null == workingTimes ? _self.workingTimes : workingTimes // ignore: cast_nullable_to_non_nullable
as List<String>,positions: null == positions ? _self.positions : positions // ignore: cast_nullable_to_non_nullable
as List<String>,designations: null == designations ? _self.designations : designations // ignore: cast_nullable_to_non_nullable
as List<String>,checklists: null == checklists ? _self.checklists : checklists // ignore: cast_nullable_to_non_nullable
as List<ChecklistConfig>,autoPurgeFormer: null == autoPurgeFormer ? _self.autoPurgeFormer : autoPurgeFormer // ignore: cast_nullable_to_non_nullable
as bool,purgeDaysGone: null == purgeDaysGone ? _self.purgeDaysGone : purgeDaysGone // ignore: cast_nullable_to_non_nullable
as int,isScheduleEnabled: null == isScheduleEnabled ? _self.isScheduleEnabled : isScheduleEnabled // ignore: cast_nullable_to_non_nullable
as bool,isShiftBoardEnabled: null == isShiftBoardEnabled ? _self.isShiftBoardEnabled : isShiftBoardEnabled // ignore: cast_nullable_to_non_nullable
as bool,employeeDataSummaryFields: null == employeeDataSummaryFields ? _self.employeeDataSummaryFields : employeeDataSummaryFields // ignore: cast_nullable_to_non_nullable
as List<String>,showOwnerInRoster: null == showOwnerInRoster ? _self.showOwnerInRoster : showOwnerInRoster // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [StoreSettingsModel].
extension StoreSettingsModelPatterns on StoreSettingsModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StoreSettingsModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StoreSettingsModel() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StoreSettingsModel value)  $default,){
final _that = this;
switch (_that) {
case _StoreSettingsModel():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StoreSettingsModel value)?  $default,){
final _that = this;
switch (_that) {
case _StoreSettingsModel() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson)  List<TitleConfig> titles, @JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson)  List<TitleConfig> tags,  List<String> workingTimes,  List<String> positions,  List<String> designations, @JsonKey(fromJson: _checklistsFromJson, toJson: _checklistsToJson)  List<ChecklistConfig> checklists,  bool autoPurgeFormer,  int purgeDaysGone,  bool isScheduleEnabled,  bool isShiftBoardEnabled,  List<String> employeeDataSummaryFields,  bool showOwnerInRoster)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StoreSettingsModel() when $default != null:
return $default(_that.titles,_that.tags,_that.workingTimes,_that.positions,_that.designations,_that.checklists,_that.autoPurgeFormer,_that.purgeDaysGone,_that.isScheduleEnabled,_that.isShiftBoardEnabled,_that.employeeDataSummaryFields,_that.showOwnerInRoster);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson)  List<TitleConfig> titles, @JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson)  List<TitleConfig> tags,  List<String> workingTimes,  List<String> positions,  List<String> designations, @JsonKey(fromJson: _checklistsFromJson, toJson: _checklistsToJson)  List<ChecklistConfig> checklists,  bool autoPurgeFormer,  int purgeDaysGone,  bool isScheduleEnabled,  bool isShiftBoardEnabled,  List<String> employeeDataSummaryFields,  bool showOwnerInRoster)  $default,) {final _that = this;
switch (_that) {
case _StoreSettingsModel():
return $default(_that.titles,_that.tags,_that.workingTimes,_that.positions,_that.designations,_that.checklists,_that.autoPurgeFormer,_that.purgeDaysGone,_that.isScheduleEnabled,_that.isShiftBoardEnabled,_that.employeeDataSummaryFields,_that.showOwnerInRoster);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson)  List<TitleConfig> titles, @JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson)  List<TitleConfig> tags,  List<String> workingTimes,  List<String> positions,  List<String> designations, @JsonKey(fromJson: _checklistsFromJson, toJson: _checklistsToJson)  List<ChecklistConfig> checklists,  bool autoPurgeFormer,  int purgeDaysGone,  bool isScheduleEnabled,  bool isShiftBoardEnabled,  List<String> employeeDataSummaryFields,  bool showOwnerInRoster)?  $default,) {final _that = this;
switch (_that) {
case _StoreSettingsModel() when $default != null:
return $default(_that.titles,_that.tags,_that.workingTimes,_that.positions,_that.designations,_that.checklists,_that.autoPurgeFormer,_that.purgeDaysGone,_that.isScheduleEnabled,_that.isShiftBoardEnabled,_that.employeeDataSummaryFields,_that.showOwnerInRoster);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StoreSettingsModel implements StoreSettingsModel {
  const _StoreSettingsModel({@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) final  List<TitleConfig> titles = const [], @JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) final  List<TitleConfig> tags = const [], final  List<String> workingTimes = const [], final  List<String> positions = const [], final  List<String> designations = const [], @JsonKey(fromJson: _checklistsFromJson, toJson: _checklistsToJson) final  List<ChecklistConfig> checklists = const [], this.autoPurgeFormer = false, this.purgeDaysGone = 0, this.isScheduleEnabled = false, this.isShiftBoardEnabled = false, final  List<String> employeeDataSummaryFields = const [], this.showOwnerInRoster = false}): _titles = titles,_tags = tags,_workingTimes = workingTimes,_positions = positions,_designations = designations,_checklists = checklists,_employeeDataSummaryFields = employeeDataSummaryFields;
  factory _StoreSettingsModel.fromJson(Map<String, dynamic> json) => _$StoreSettingsModelFromJson(json);

 final  List<TitleConfig> _titles;
@override@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) List<TitleConfig> get titles {
  if (_titles is EqualUnmodifiableListView) return _titles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_titles);
}

 final  List<TitleConfig> _tags;
@override@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) List<TitleConfig> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

 final  List<String> _workingTimes;
@override@JsonKey() List<String> get workingTimes {
  if (_workingTimes is EqualUnmodifiableListView) return _workingTimes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_workingTimes);
}

 final  List<String> _positions;
@override@JsonKey() List<String> get positions {
  if (_positions is EqualUnmodifiableListView) return _positions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_positions);
}

 final  List<String> _designations;
@override@JsonKey() List<String> get designations {
  if (_designations is EqualUnmodifiableListView) return _designations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_designations);
}

 final  List<ChecklistConfig> _checklists;
@override@JsonKey(fromJson: _checklistsFromJson, toJson: _checklistsToJson) List<ChecklistConfig> get checklists {
  if (_checklists is EqualUnmodifiableListView) return _checklists;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_checklists);
}

@override@JsonKey() final  bool autoPurgeFormer;
@override@JsonKey() final  int purgeDaysGone;
@override@JsonKey() final  bool isScheduleEnabled;
@override@JsonKey() final  bool isShiftBoardEnabled;
 final  List<String> _employeeDataSummaryFields;
@override@JsonKey() List<String> get employeeDataSummaryFields {
  if (_employeeDataSummaryFields is EqualUnmodifiableListView) return _employeeDataSummaryFields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_employeeDataSummaryFields);
}

@override@JsonKey() final  bool showOwnerInRoster;

/// Create a copy of StoreSettingsModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StoreSettingsModelCopyWith<_StoreSettingsModel> get copyWith => __$StoreSettingsModelCopyWithImpl<_StoreSettingsModel>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StoreSettingsModelToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StoreSettingsModel&&const DeepCollectionEquality().equals(other._titles, _titles)&&const DeepCollectionEquality().equals(other._tags, _tags)&&const DeepCollectionEquality().equals(other._workingTimes, _workingTimes)&&const DeepCollectionEquality().equals(other._positions, _positions)&&const DeepCollectionEquality().equals(other._designations, _designations)&&const DeepCollectionEquality().equals(other._checklists, _checklists)&&(identical(other.autoPurgeFormer, autoPurgeFormer) || other.autoPurgeFormer == autoPurgeFormer)&&(identical(other.purgeDaysGone, purgeDaysGone) || other.purgeDaysGone == purgeDaysGone)&&(identical(other.isScheduleEnabled, isScheduleEnabled) || other.isScheduleEnabled == isScheduleEnabled)&&(identical(other.isShiftBoardEnabled, isShiftBoardEnabled) || other.isShiftBoardEnabled == isShiftBoardEnabled)&&const DeepCollectionEquality().equals(other._employeeDataSummaryFields, _employeeDataSummaryFields)&&(identical(other.showOwnerInRoster, showOwnerInRoster) || other.showOwnerInRoster == showOwnerInRoster));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_titles),const DeepCollectionEquality().hash(_tags),const DeepCollectionEquality().hash(_workingTimes),const DeepCollectionEquality().hash(_positions),const DeepCollectionEquality().hash(_designations),const DeepCollectionEquality().hash(_checklists),autoPurgeFormer,purgeDaysGone,isScheduleEnabled,isShiftBoardEnabled,const DeepCollectionEquality().hash(_employeeDataSummaryFields),showOwnerInRoster);

@override
String toString() {
  return 'StoreSettingsModel(titles: $titles, tags: $tags, workingTimes: $workingTimes, positions: $positions, designations: $designations, checklists: $checklists, autoPurgeFormer: $autoPurgeFormer, purgeDaysGone: $purgeDaysGone, isScheduleEnabled: $isScheduleEnabled, isShiftBoardEnabled: $isShiftBoardEnabled, employeeDataSummaryFields: $employeeDataSummaryFields, showOwnerInRoster: $showOwnerInRoster)';
}


}

/// @nodoc
abstract mixin class _$StoreSettingsModelCopyWith<$Res> implements $StoreSettingsModelCopyWith<$Res> {
  factory _$StoreSettingsModelCopyWith(_StoreSettingsModel value, $Res Function(_StoreSettingsModel) _then) = __$StoreSettingsModelCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) List<TitleConfig> titles,@JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson) List<TitleConfig> tags, List<String> workingTimes, List<String> positions, List<String> designations,@JsonKey(fromJson: _checklistsFromJson, toJson: _checklistsToJson) List<ChecklistConfig> checklists, bool autoPurgeFormer, int purgeDaysGone, bool isScheduleEnabled, bool isShiftBoardEnabled, List<String> employeeDataSummaryFields, bool showOwnerInRoster
});




}
/// @nodoc
class __$StoreSettingsModelCopyWithImpl<$Res>
    implements _$StoreSettingsModelCopyWith<$Res> {
  __$StoreSettingsModelCopyWithImpl(this._self, this._then);

  final _StoreSettingsModel _self;
  final $Res Function(_StoreSettingsModel) _then;

/// Create a copy of StoreSettingsModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? titles = null,Object? tags = null,Object? workingTimes = null,Object? positions = null,Object? designations = null,Object? checklists = null,Object? autoPurgeFormer = null,Object? purgeDaysGone = null,Object? isScheduleEnabled = null,Object? isShiftBoardEnabled = null,Object? employeeDataSummaryFields = null,Object? showOwnerInRoster = null,}) {
  return _then(_StoreSettingsModel(
titles: null == titles ? _self._titles : titles // ignore: cast_nullable_to_non_nullable
as List<TitleConfig>,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<TitleConfig>,workingTimes: null == workingTimes ? _self._workingTimes : workingTimes // ignore: cast_nullable_to_non_nullable
as List<String>,positions: null == positions ? _self._positions : positions // ignore: cast_nullable_to_non_nullable
as List<String>,designations: null == designations ? _self._designations : designations // ignore: cast_nullable_to_non_nullable
as List<String>,checklists: null == checklists ? _self._checklists : checklists // ignore: cast_nullable_to_non_nullable
as List<ChecklistConfig>,autoPurgeFormer: null == autoPurgeFormer ? _self.autoPurgeFormer : autoPurgeFormer // ignore: cast_nullable_to_non_nullable
as bool,purgeDaysGone: null == purgeDaysGone ? _self.purgeDaysGone : purgeDaysGone // ignore: cast_nullable_to_non_nullable
as int,isScheduleEnabled: null == isScheduleEnabled ? _self.isScheduleEnabled : isScheduleEnabled // ignore: cast_nullable_to_non_nullable
as bool,isShiftBoardEnabled: null == isShiftBoardEnabled ? _self.isShiftBoardEnabled : isShiftBoardEnabled // ignore: cast_nullable_to_non_nullable
as bool,employeeDataSummaryFields: null == employeeDataSummaryFields ? _self._employeeDataSummaryFields : employeeDataSummaryFields // ignore: cast_nullable_to_non_nullable
as List<String>,showOwnerInRoster: null == showOwnerInRoster ? _self.showOwnerInRoster : showOwnerInRoster // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
