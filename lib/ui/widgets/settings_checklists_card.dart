import 'package:flutter/material.dart';
import '../../models/store_settings_model.dart';
import '../../core/theme/app_theme.dart';

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_box_outlined, color: Theme.of(context).textTheme.titleLarge?.color, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                'Checklist Configurations',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.titleLarge?.color),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Add checklists and manage tasks for stores and positions.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4C75),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        final newId = '${DateTime.now().microsecondsSinceEpoch}';
                        final newChecklist = ChecklistConfig(id: newId, name: 'Untitled Checklist', items: []);
                        final newChecklists = List<ChecklistConfig>.from(widget.settings.checklists)..add(newChecklist);
                        widget.onUpdate(widget.settings.copyWith(checklists: newChecklists));
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Checklist'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (widget.settings.checklists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(child: Text('No checklists configured.', style: TextStyle(color: Colors.grey))),
                  ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.settings.checklists.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
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
            Positioned(
              bottom: 0,
              right: 0,
              child: widget.copyButton!,
            ),
        ],
      ),
    );
  }

  Widget _buildChecklistRow(ChecklistConfig checklist) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildColorPicker(checklist),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: checklist.name,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    onChanged: (val) {
                      final updated = checklist.copyWith(name: val);
                      final newChecklists = widget.settings.checklists.map((e) => e.id == updated.id ? updated : e).toList();
                      widget.onUpdate(widget.settings.copyWith(checklists: newChecklists));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${checklist.items.length} tasks',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodySmall?.color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey, size: 20),
            onPressed: () {
              _showManageChecklistDialog(context, checklist);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker(ChecklistConfig item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: AppTheme.normalizeColorName(item.color),
          icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
          items: ['Color', ...AppTheme.colorNames].map((c) {
            return DropdownMenuItem(
              value: c,
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.getColorFromName(c),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              final updated = item.copyWith(color: val);
              final newChecklists = widget.settings.checklists.map((e) => e.id == updated.id ? updated : e).toList();
              widget.onUpdate(widget.settings.copyWith(checklists: newChecklists));
            }
          },
        ),
      ),
    );
  }

  void _showManageChecklistDialog(BuildContext context, ChecklistConfig checklist) {
    showDialog(
      context: context,
      builder: (context) {
        ChecklistConfig localChecklist = widget.settings.checklists.firstWhere((e) => e.id == checklist.id, orElse: () => checklist);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateAndSet(ChecklistConfig newChecklist) {
              setDialogState(() {
                localChecklist = newChecklist;
              });
              final newChecklists = widget.settings.checklists.map((e) => e.id == newChecklist.id ? newChecklist : e).toList();
              widget.onUpdate(widget.settings.copyWith(checklists: newChecklists));
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text('Manage ${localChecklist.name}', style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color)),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tasks', style: TextStyle(fontWeight: FontWeight.bold)),
                        ElevatedButton.icon(
                          onPressed: () {
                            final updated = localChecklist.copyWith(items: [...localChecklist.items, 'New Task']);
                            updateAndSet(updated);
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Task'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Drag and drop tasks by holding the numbers to reorder them.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    if (localChecklist.items.isEmpty)
                      const Text('No tasks added yet.', style: TextStyle(color: Colors.grey))
                    else
                      Flexible(
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          itemCount: localChecklist.items.length,
                          onReorder: (oldIndex, newIndex) {
                            if (newIndex > oldIndex) newIndex -= 1;
                            if (oldIndex != newIndex) {
                              final newItems = List<String>.from(localChecklist.items);
                              final item = newItems.removeAt(oldIndex);
                              newItems.insert(newIndex, item);
                              final updated = localChecklist.copyWith(items: newItems);
                              updateAndSet(updated);
                            }
                          },
                          itemBuilder: (context, idx) {
                            return Padding(
                              key: ValueKey('$idx-${localChecklist.id}'),
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Theme.of(context).dividerColor),
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
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: localChecklist.items[idx],
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                          border: InputBorder.none,
                                        ),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        onChanged: (val) {
                                          final newItems = List<String>.from(localChecklist.items);
                                          newItems[idx] = val;
                                          final updated = localChecklist.copyWith(items: newItems);
                                          updateAndSet(updated);
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                                      onPressed: () {
                                        final newItems = List<String>.from(localChecklist.items)..removeAt(idx);
                                        final updated = localChecklist.copyWith(items: newItems);
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
                        content: const Text('Are you sure you want to delete this checklist?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              final newChecklists = List<ChecklistConfig>.from(widget.settings.checklists)..removeWhere((e) => e.id == checklist.id);
                              widget.onUpdate(widget.settings.copyWith(checklists: newChecklists));
                              Navigator.of(context).pop(); // Close confirmation
                              Navigator.of(context).pop(); // Close settings popup
                            },
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
          }
        );
      },
    );
  }
}
