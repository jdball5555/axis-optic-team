import 'package:flutter/material.dart';
import '../../models/store_settings_model.dart';
import '../../core/theme/app_theme.dart';

class SettingsTitleTagCard extends StatefulWidget {
  final StoreSettingsModel settings;
  final Function(StoreSettingsModel) onUpdate;
  final Widget? copyButton;

  const SettingsTitleTagCard({
    super.key,
    required this.settings,
    required this.onUpdate,
    this.copyButton,
  });

  @override
  State<SettingsTitleTagCard> createState() => _SettingsTitleTagCardState();
}

class _SettingsTitleTagCardState extends State<SettingsTitleTagCard> {
  int _activeTabIndex = 0; // 0 for Titles, 1 for Tags

  @override
  Widget build(BuildContext context) {
    final List<TitleConfig> currentList = _activeTabIndex == 0 ? widget.settings.titles : widget.settings.tags;

    return Card(
      color: Theme.of(context).cardColor,
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
                  children: [
                    const Expanded(
                      child: Text(
                        'Title & Additional Tag Configurations',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4C75), // Dark blue from screenshot
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        final newItem = TitleConfig(id: DateTime.now().microsecondsSinceEpoch.toString(), name: 'New Item');
                        if (_activeTabIndex == 0) {
                          widget.onUpdate(widget.settings.copyWith(titles: [...widget.settings.titles, newItem]));
                        } else {
                          widget.onUpdate(widget.settings.copyWith(tags: [...widget.settings.tags, newItem]));
                        }
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(_activeTabIndex == 0 ? 'Add Title' : 'Add Tag'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildTab(0, 'Titles (${widget.settings.titles.length})'),
                    const SizedBox(width: 8),
                    _buildTab(1, 'Additional Tags (${widget.settings.tags.length})'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Drag and drop titles by holding their numbers to order them from top to bottom. The top title will always be default for new hires, and promoting an employee will default fill to the next title in line.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: currentList.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex -= 1;
                    if (oldIndex != newIndex) {
                      if (_activeTabIndex == 0) {
                        final newItems = List<TitleConfig>.from(widget.settings.titles);
                        final item = newItems.removeAt(oldIndex);
                        newItems.insert(newIndex, item);
                        widget.onUpdate(widget.settings.copyWith(titles: newItems));
                      } else {
                        final newItems = List<TitleConfig>.from(widget.settings.tags);
                        final item = newItems.removeAt(oldIndex);
                        newItems.insert(newIndex, item);
                        widget.onUpdate(widget.settings.copyWith(tags: newItems));
                      }
                    }
                  },
                  itemBuilder: (context, index) {
                    final item = currentList[index];
                    return Padding(
                      key: ValueKey(item.id),
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: _buildConfigRow(item, index, currentList.length),
                    );
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

  Widget _buildTab(int index, String label) {
    final isActive = _activeTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0F4C75) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? const Color(0xFF0F4C75) : Theme.of(context).dividerColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildConfigRow(TitleConfig item, int index, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: SizedBox(
                width: 24,
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildColorPicker(item),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.name,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    onChanged: (val) => _updateItem(item.copyWith(name: val)),
                  ),
                ),
                if (index == 0 && _activeTabIndex == 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('DEFAULT', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey, size: 20),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  TitleConfig localItem = (_activeTabIndex == 0 ? widget.settings.titles : widget.settings.tags)
                      .firstWhere((e) => e.id == item.id, orElse: () => item);

                  return StatefulBuilder(
                    builder: (context, setDialogState) {
                      void updateAndSet(TitleConfig newItem) {
                        setDialogState(() {
                          localItem = newItem;
                        });
                        _updateItem(newItem);
                      }

                      return AlertDialog(
                        backgroundColor: Theme.of(context).cardColor,
                        title: Text('${localItem.name} Settings', style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color)),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SwitchListTile(
                                title: const Text('Split in Area'),
                                value: localItem.splitInArea,
                                onChanged: (val) => updateAndSet(localItem.copyWith(splitInArea: val)),
                              ),
                              SwitchListTile(
                                title: const Text('Isolated Roster'),
                                value: localItem.isolatedRoster,
                                onChanged: (val) => updateAndSet(localItem.copyWith(isolatedRoster: val)),
                              ),
                              SwitchListTile(
                                title: const Text('Manager Permit Required'),
                                value: localItem.mgrPermit,
                                onChanged: (val) => updateAndSet(localItem.copyWith(mgrPermit: val)),
                              ),
                              const Divider(),
                              _buildChecklistSection(localItem, updateAndSet),
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
                                  title: const Text('Delete Title'),
                                  content: const Text('Are you sure you want to delete this title?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        if (_activeTabIndex == 0) {
                                          final newItems = List<TitleConfig>.from(widget.settings.titles)..removeWhere((e) => e.id == item.id);
                                          widget.onUpdate(widget.settings.copyWith(titles: newItems));
                                        } else {
                                          final newItems = List<TitleConfig>.from(widget.settings.tags)..removeWhere((e) => e.id == item.id);
                                          widget.onUpdate(widget.settings.copyWith(tags: newItems));
                                        }
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
                            child: const Text('Delete'),
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
            },
          ),
        ],
      ),
    );
  }

  void _updateItem(TitleConfig newItem) {
    if (_activeTabIndex == 0) {
      final newItems = widget.settings.titles.map((e) => e.id == newItem.id ? newItem : e).toList();
      widget.onUpdate(widget.settings.copyWith(titles: newItems));
    } else {
      final newItems = widget.settings.tags.map((e) => e.id == newItem.id ? newItem : e).toList();
      widget.onUpdate(widget.settings.copyWith(tags: newItems));
    }
  }

  Widget _buildCheckbox(TitleConfig item, String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            visualDensity: VisualDensity.compact,
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildChecklistSection(TitleConfig item, Function(TitleConfig) updateAndSet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Link a Checklist'),
          value: item.linkChecklist,
          onChanged: (val) => updateAndSet(item.copyWith(linkChecklist: val)),
        ),
        if (item.linkChecklist) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Select Checklist'),
              value: widget.settings.checklists.any((c) => c.id == item.linkedChecklistId) ? item.linkedChecklistId : null,
              items: widget.settings.checklists.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              dropdownColor: Theme.of(context).cardColor,
              onChanged: (val) {
                if (val != null) updateAndSet(item.copyWith(linkedChecklistId: val));
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Auto-promote on completion', style: TextStyle(fontSize: 14)),
            value: item.autoPromoteOnChecklist,
            onChanged: (val) => updateAndSet(item.copyWith(autoPromoteOnChecklist: val)),
          ),
        ],
      ],
    );
  }

  Widget _buildColorPicker(TitleConfig item) {
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
          icon: const Icon(Icons.keyboard_arrow_down, size: 16),
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
                  Text(c, style: const TextStyle(fontSize: 10)),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) _updateItem(item.copyWith(color: val));
          },
        ),
      ),
    );
  }
}
