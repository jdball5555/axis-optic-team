import 'package:freezed_annotation/freezed_annotation.dart';

part 'store_settings_model.freezed.dart';
part 'store_settings_model.g.dart';

@freezed
abstract class TitleConfig with _$TitleConfig {
  const factory TitleConfig({
    required String id,
    @Default('Color') String color,
    @Default('') String name,
    @Default(false) bool isLeadership,
    @Default(false) bool splitInArea,
    @Default(false) bool isolatedRoster,
    @Default(false) bool linkChecklist,
    @Default(false) bool mgrPermit,
    String? linkedChecklistId,
    @Default(false) bool autoPromoteOnChecklist,
  }) = _TitleConfig;

  factory TitleConfig.fromJson(Map<String, dynamic> json) =>
      _$TitleConfigFromJson(json);
}

List<TitleConfig> _titlesFromJson(dynamic json) {
  if (json == null) return [];
  if (json is List) {
    int _idCounter = 0;
    String _uniqueId() =>
        '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

    final list = json.map((e) {
      if (e is String) {
        return TitleConfig(id: _uniqueId(), name: e);
      } else if (e is Map<String, dynamic>) {
        return TitleConfig.fromJson(e);
      }
      return TitleConfig(id: _uniqueId(), name: 'Unknown');
    }).toList();

    // Deduplicate by ID to prevent DropdownButton crashes from corrupt data
    final Map<String, TitleConfig> uniqueMap = {};
    for (var item in list) {
      // If ID already exists (e.g. corrupt data), generate a new one
      if (uniqueMap.containsKey(item.id)) {
        final newItem = item.copyWith(id: _uniqueId());
        uniqueMap[newItem.id] = newItem;
      } else {
        uniqueMap[item.id] = item;
      }
    }
    return uniqueMap.values.toList();
  }
  return [];
}

List<Map<String, dynamic>> _titlesToJson(List<TitleConfig> titles) {
  return titles.map((e) => e.toJson()).toList();
}

@freezed
abstract class ChecklistTaskItem with _$ChecklistTaskItem {
  const factory ChecklistTaskItem({
    required String id,
    required String text,
    @Default([]) List<String> positions,
  }) = _ChecklistTaskItem;

  factory ChecklistTaskItem.fromJson(Map<String, dynamic> json) =>
      _$ChecklistTaskItemFromJson(json);
}

List<ChecklistTaskItem> _tasksFromJson(dynamic json) {
  if (json == null) return [];
  if (json is List) {
    return json.map((e) {
      if (e is Map<String, dynamic>) {
        return ChecklistTaskItem.fromJson(e);
      } else if (e is String) {
        return ChecklistTaskItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${e.hashCode}',
          text: e,
          positions: const [],
        );
      }
      return ChecklistTaskItem(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        text: '',
        positions: const [],
      );
    }).toList();
  }
  return [];
}

List<Map<String, dynamic>> _tasksToJson(List<ChecklistTaskItem> tasks) {
  return tasks.map((e) => e.toJson()).toList();
}

@freezed
abstract class ChecklistConfig with _$ChecklistConfig {
  const ChecklistConfig._();

  const factory ChecklistConfig({
    required String id,
    required String name,
    @Default('Color') String color,
    @Default([]) List<String> items,
    @JsonKey(fromJson: _tasksFromJson, toJson: _tasksToJson)
    @Default([])
    List<ChecklistTaskItem> tasks,
  }) = _ChecklistConfig;

  factory ChecklistConfig.fromJson(Map<String, dynamic> json) =>
      _$ChecklistConfigFromJson(json);

  List<ChecklistTaskItem> get effectiveTasks {
    if (tasks.isNotEmpty) return tasks;
    return items.asMap().entries.map((e) => ChecklistTaskItem(
      id: '${id}_${e.key}',
      text: e.value,
      positions: const [],
    )).toList();
  }

  List<ChecklistTaskItem> tasksForPosition(String? position) {
    final all = effectiveTasks;
    if (position == null || position.trim().isEmpty) return all;
    final posNorm = position.trim().toLowerCase();
    return all.where((t) {
      if (t.positions.isEmpty) return true;
      if (t.positions.any((p) {
        final pNorm = p.trim().toLowerCase();
        return pNorm == 'all' || pNorm == 'all positions';
      })) {
        return true;
      }
      return t.positions.any((p) => p.trim().toLowerCase() == posNorm);
    }).toList();
  }

  List<String> itemsForPosition(String? position) {
    return tasksForPosition(position).map((t) => t.text).toList();
  }
}

List<ChecklistConfig> _checklistsFromJson(dynamic json) {
  if (json == null) return [];
  if (json is List) {
    return json.map((e) {
      if (e is Map<String, dynamic>) {
        final config = ChecklistConfig.fromJson(e);
        if (config.tasks.isEmpty && config.items.isNotEmpty) {
          final syntheticTasks = config.items.asMap().entries.map((entry) => ChecklistTaskItem(
            id: '${config.id}_${entry.key}',
            text: entry.value,
            positions: const [],
          )).toList();
          return config.copyWith(tasks: syntheticTasks);
        }
        return config;
      }
      return ChecklistConfig(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        name: 'Unknown',
      );
    }).toList();
  }
  return [];
}

List<Map<String, dynamic>> _checklistsToJson(List<ChecklistConfig> checklists) {
  return checklists.map((e) {
    final effectiveItems = e.tasks.isNotEmpty ? e.tasks.map((t) => t.text).toList() : e.items;
    return e.copyWith(items: effectiveItems).toJson();
  }).toList();
}

@freezed
abstract class StoreSettingsModel with _$StoreSettingsModel {
  const factory StoreSettingsModel({
    @JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson)
    @Default([])
    List<TitleConfig> titles,
    @JsonKey(fromJson: _titlesFromJson, toJson: _titlesToJson)
    @Default([])
    List<TitleConfig> tags,
    @Default([]) List<String> workingTimes,
    @Default([]) List<String> positions,
    @Default([]) List<String> designations,
    @JsonKey(fromJson: _checklistsFromJson, toJson: _checklistsToJson)
    @Default([])
    List<ChecklistConfig> checklists,
    @Default(false) bool autoPurgeFormer,
    @Default(0) int purgeDaysGone,
    @Default(false) bool isScheduleEnabled,
    @Default(false) bool isShiftBoardEnabled,
    @Default([]) List<String> employeeDataSummaryFields,
    @Default(false) bool showOwnerInRoster,
  }) = _StoreSettingsModel;

  factory StoreSettingsModel.fromJson(Map<String, dynamic> json) =>
      _$StoreSettingsModelFromJson(json);
}
