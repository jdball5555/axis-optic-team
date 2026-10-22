import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/store_settings_model.dart';
import '../../core/theme/app_theme.dart';
import 'app_dropdown.dart';

class SettingsChecklistsCard extends StatefulWidget {
  final StoreSettingsModel settings;
  final Function(StoreSettingsModel) onUpdate;
  final Widget? copyButton;

  const SettingsChecklistsCard({
    super.key,
    required this.settings,
    required this.onUpdate,
    this.copyButton,
  });

  @override
  State<SettingsChecklistsCard> createState() => _SettingsChecklistsCardState();
}

class _SettingsChecklistsCardState extends State<SettingsChecklistsCard> {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final headerText = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_box_outlined,
                              color: Theme.of(
                                context,
                              ).textTheme.titleLarge?.color,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Checklist Configurations',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.titleLarge?.color,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add checklists and manage tasks for stores and positions.',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color ??
                                    Colors.grey,
                          ),
                        ),
                      ],
                    );

                    final addButton = ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4C75),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        final newId =
                            '${DateTime.now().microsecondsSinceEpoch}';
                        final newChecklist = ChecklistConfig(
                          id: newId,
                          name: 'Untitled Checklist',
                          items: [],
                        );
                        final newChecklists = List<ChecklistConfig>.from(
                          widget.settings.checklists,
                        )..add(newChecklist);
                        widget.onUpdate(
                          widget.settings.copyWith(checklists: newChecklists),
                        );
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Checklist'),
                    );

                    if (constraints.maxWidth < 450) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          headerText,
                          const SizedBox(height: 12),
                          addButton,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: headerText),
                        const SizedBox(width: 12),
                        addButton,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                if (widget.settings.checklists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text(
                        'No checklists configured.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.settings.checklists.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final checklist = widget.settings.checklists[index];
                    return _buildChecklistRow(checklist);
                  },
                ),
                if (widget.copyButton != null) const SizedBox(height: 24),
              ],
            ),
          ),
          if (widget.copyButton != null)
            Positioned(bottom: 0, right: 0, child: widget.copyButton!),
        ],
      ),
    );
  }

  Widget _buildChecklistRow(ChecklistConfig checklist) {
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 420;
        final isVeryNarrow = box.maxWidth < 320;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isVeryNarrow ? 8 : 16,
            vertical: isVeryNarrow ? 8 : 12,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _buildColorPicker(checklist, compact: compact),
              SizedBox(width: isVeryNarrow ? 8 : 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: checklist.name,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: isVeryNarrow ? 4 : 8,
                          ),
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        onChanged: (val) {
                          final updated = checklist.copyWith(name: val);
                          final newChecklists = widget.settings.checklists
                              .map((e) => e.id == updated.id ? updated : e)
                              .toList();
                          widget.onUpdate(
                            widget.settings.copyWith(checklists: newChecklists),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isVeryNarrow
                            ? '${checklist.items.length}'
                            : '${checklist.items.length} tasks',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isVeryNarrow ? 8 : 16),
              IconButton(
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                icon: const Icon(Icons.settings, color: Colors.grey, size: 20),
                onPressed: () {
                  _showManageChecklistDialog(context, checklist);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildColorPicker(ChecklistConfig item, {bool compact = false}) {
    Widget dot(String c) => Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: AppTheme.getColorFromName(c),
        shape: BoxShape.circle,
        border: c == 'Color'
            ? Border.all(color: Colors.grey.shade400, width: 1.5)
            : null,
      ),
    );
    final names = ['Color', ...AppTheme.colorNames];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: AppTheme.normalizeColorName(item.color),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: Colors.grey,
          ),
          selectedItemBuilder: (_) =>
              [for (final c in names) Center(child: dot(c))],
          items: names.map((c) {
            return DropdownMenuItem(
              value: c,
              child: Center(child: dot(c)),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              final updated = item.copyWith(color: val);
              final newChecklists = widget.settings.checklists
                  .map((e) => e.id == updated.id ? updated : e)
                  .toList();
              widget.onUpdate(
                widget.settings.copyWith(checklists: newChecklists),
              );
            }
          },
        ),
      ),
    );
  }

  void _showManageChecklistDialog(
    BuildContext context,
    ChecklistConfig checklist,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        ChecklistConfig localChecklist = widget.settings.checklists.firstWhere(
          (e) => e.id == checklist.id,
          orElse: () => checklist,
        );

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateAndSet(ChecklistConfig newChecklist) {
              setDialogState(() {
                localChecklist = newChecklist;
              });
              final newChecklists = widget.settings.checklists
                  .map((e) => e.id == newChecklist.id ? newChecklist : e)
                  .toList();
              widget.onUpdate(
                widget.settings.copyWith(checklists: newChecklists),
              );
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text(
                'Manage ${localChecklist.name}',
                style: TextStyle(
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              content: SizedBox(
                width: math.min(
                  MediaQuery.sizeOf(context).width - 48,
                  700.0,
                ),
                height: (MediaQuery.sizeOf(context).height - 120).clamp(
                  240.0,
                  540.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tasks',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            final newTask = ChecklistTaskItem(
                              id: '${DateTime.now().microsecondsSinceEpoch}',
                              text: 'New Task',
                              positions: const [],
                            );
                            final newTasks = [
                              ...localChecklist.effectiveTasks,
                              newTask,
                            ];
                            final updated = localChecklist.copyWith(
                              tasks: newTasks,
                              items: newTasks.map((t) => t.text).toList(),
                            );
                            updateAndSet(updated);
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Task'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Assign tasks to specific positions or leave on All Positions. Drag by the numbers to reorder.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    if (localChecklist.effectiveTasks.isEmpty)
                      const Text(
                        'No tasks added yet.',
                        style: TextStyle(color: Colors.grey),
                      )
                    else
                      Flexible(
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          itemCount: localChecklist.effectiveTasks.length,
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex -= 1;
                            if (oldIndex != newIndex) {
                              final newTasks = List<ChecklistTaskItem>.from(
                                localChecklist.effectiveTasks,
                              );
                              final item = newTasks.removeAt(oldIndex);
                              newTasks.insert(newIndex, item);
                              final updated = localChecklist.copyWith(
                                tasks: newTasks,
                                items: newTasks.map((t) => t.text).toList(),
                              );
                              updateAndSet(updated);
                            }
                          },
                          itemBuilder: (context, idx) {
                            final task = localChecklist.effectiveTasks[idx];
                            final availablePositions =
                                widget.settings.positions;
                            final selectedPositions = task.positions.isEmpty
                                ? availablePositions
                                : task.positions;

                            return Padding(
                              key: ValueKey(task.id),
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    ReorderableDragStartListener(
                                      index: idx,
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.grab,
                                        child: SizedBox(
                                          width: 24,
                                          child: Center(
                                            child: Text(
                                              '${idx + 1}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        key: ValueKey('text-${task.id}'),
                                        initialValue: task.text,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 8,
                                          ),
                                          border: InputBorder.none,
                                          hintText: 'Task description...',
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        onChanged: (val) {
                                          final newTasks =
                                              List<ChecklistTaskItem>.from(
                                            localChecklist.effectiveTasks,
                                          );
                                          newTasks[idx] = newTasks[idx].copyWith(
                                            text: val,
                                          );
                                          final updated = localChecklist
                                              .copyWith(
                                                tasks: newTasks,
                                                items: newTasks
                                                    .map((t) => t.text)
                                                    .toList(),
                                              );
                                          updateAndSet(updated);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Position Selector Dropdown
                                    SizedBox(
                                      width: 175,
                                      child: AppMultiSelectDropdown<String>(
                                        options: availablePositions,
                                        selected: selectedPositions,
                                        allLabel: 'All Positions',
                                        emptyText: 'All Positions',
                                        showAllOption: true,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (newPos) {
                                          final newTasks =
                                              List<ChecklistTaskItem>.from(
                                            localChecklist.effectiveTasks,
                                          );
                                          final isAll =
                                              newPos.length ==
                                                  availablePositions.length ||
                                              newPos.isEmpty;
                                          newTasks[idx] = newTasks[idx].copyWith(
                                            positions: isAll ? const [] : newPos,
                                          );
                                          final updated = localChecklist
                                              .copyWith(
                                                tasks: newTasks,
                                                items: newTasks
                                                    .map((t) => t.text)
                                                    .toList(),
                                              );
                                          updateAndSet(updated);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Copy / Duplicate Task Button
                                    IconButton(
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        color: Colors.blueGrey,
                                        size: 18,
                                      ),
                                      tooltip: 'Duplicate Task',
                                      onPressed: () {
                                        final dup = task.copyWith(
                                          id:
                                              '${DateTime.now().microsecondsSinceEpoch}_$idx',
                                        );
                                        final newTasks =
                                            List<ChecklistTaskItem>.from(
                                          localChecklist.effectiveTasks,
                                        );
                                        newTasks.insert(idx + 1, dup);
                                        final updated = localChecklist
                                            .copyWith(
                                              tasks: newTasks,
                                              items: newTasks
                                                  .map((t) => t.text)
                                                  .toList(),
                                            );
                                        updateAndSet(updated);
                                      },
                                    ),
                                    // Delete Task Button
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.grey,
                                        size: 20,
                                      ),
                                      tooltip: 'Delete Task',
                                      onPressed: () {
                                        final newTasks =
                                            List<ChecklistTaskItem>.from(
                                          localChecklist.effectiveTasks,
                                        )..removeAt(idx);
                                        final updated = localChecklist
                                            .copyWith(
                                              tasks: newTasks,
                                              items: newTasks
                                                  .map((t) => t.text)
                                                  .toList(),
                                            );
                                        updateAndSet(updated);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Theme.of(context).cardColor,
                        title: const Text('Delete Checklist'),
                        content: const Text(
                          'Are you sure you want to delete this checklist?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              final newChecklists = List<ChecklistConfig>.from(
                                widget.settings.checklists,
                              )..removeWhere((e) => e.id == checklist.id);
                              widget.onUpdate(
                                widget.settings.copyWith(
                                  checklists: newChecklists,
                                ),
                              );
                              Navigator.of(context).pop(); // Close confirmation
                              Navigator.of(
                                context,
                              ).pop(); // Close settings popup
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete Checklist'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
