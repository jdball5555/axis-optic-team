import 'package:flutter/material.dart';
import '../../models/store_settings_model.dart';
import '../../core/theme/app_theme.dart';
import 'title_journey_editor.dart';
import 'app_dropdown.dart';

class SettingsTitleTagCard extends StatefulWidget {
  final StoreSettingsModel settings;
  final Function(StoreSettingsModel) onUpdate;
  final Widget? copyButton;

  /// The store these settings belong to (for the team member journey).
  final String? storeId;

  /// Whether this card is rendered in All Stores mode.
  final bool isAllStoresMode;

  const SettingsTitleTagCard({
    super.key,
    required this.settings,
    required this.onUpdate,
    this.copyButton,
    this.storeId,
    this.isAllStoresMode = false,
  });

  @override
  State<SettingsTitleTagCard> createState() => _SettingsTitleTagCardState();
}

class _SettingsTitleTagCardState extends State<SettingsTitleTagCard> {
  int _activeTabIndex = 0; // 0 for Titles, 1 for Tags

  @override
  Widget build(BuildContext context) {
    final List<TitleConfig> currentList = _activeTabIndex == 0
        ? widget.settings.titles
        : widget.settings.tags;

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
                // Wraps the button under the heading in a narrow column
                // (All Stores shows each store's settings side by side).
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    const Text(
                      'Title & Additional Tag Configurations',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(
                          0xFF0F4C75,
                        ), // Dark blue from screenshot
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        final newItem = TitleConfig(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          name: 'New Item',
                        );
                        if (_activeTabIndex == 0) {
                          widget.onUpdate(
                            widget.settings.copyWith(
                              titles: [...widget.settings.titles, newItem],
                            ),
                          );
                        } else {
                          widget.onUpdate(
                            widget.settings.copyWith(
                              tags: [...widget.settings.tags, newItem],
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(
                        _activeTabIndex == 0 ? 'Add Title' : 'Add Tag',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildTab(0, 'Titles (${widget.settings.titles.length})'),
                    _buildTab(
                      1,
                      'Additional Tags (${widget.settings.tags.length})',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _activeTabIndex == 0
                      ? 'Use Up and Down arrows to order titles from top to bottom. The top title will always be default for new hires, and promoting an employee will default fill to the next title in line.'
                      : 'Drag tags by their numbers to put them in order.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                if (_activeTabIndex == 0)
                  // Titles: ordered by the journey (no dragging here).
                  Column(
                    children: [
                      for (var i = 0; i < currentList.length; i++)
                        Padding(
                          key: ValueKey(currentList[i].id),
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: _buildConfigRow(
                            currentList[i],
                            i,
                            currentList.length,
                            draggable: false,
                          ),
                        ),
                    ],
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: currentList.length,
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      if (oldIndex != newIndex) {
                        final newItems = List<TitleConfig>.from(
                          widget.settings.tags,
                        );
                        final item = newItems.removeAt(oldIndex);
                        newItems.insert(newIndex, item);
                        widget.onUpdate(
                          widget.settings.copyWith(tags: newItems),
                        );
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
                if (_activeTabIndex == 0 && widget.storeId != null) ...[
                  const SizedBox(height: 28),
                  Divider(color: Theme.of(context).dividerColor),
                  const SizedBox(height: 20),
                  TitleJourneyEditor(
                    storeId: widget.storeId!,
                    titles: widget.settings.titles,
                    onOrderChanged: (ordered) => widget.onUpdate(
                      widget.settings.copyWith(titles: ordered),
                    ),
                  ),
                ],
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

  Widget _buildTab(int index, String label) {
    final isActive = _activeTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0F4C75) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? const Color(0xFF0F4C75)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? Colors.white
                : Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildConfigRow(
    TitleConfig item,
    int index,
    int totalCount, {
    bool draggable = true,
  }) {
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 1050;
        final isVeryNarrow = box.maxWidth < 320;

        Widget upDownArrows = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: index > 0
                  ? () {
                      if (_activeTabIndex == 0) {
                        final newItems = List<TitleConfig>.from(
                          widget.settings.titles,
                        );
                        final moved = newItems.removeAt(index);
                        newItems.insert(index - 1, moved);
                        widget.onUpdate(
                          widget.settings.copyWith(titles: newItems),
                        );
                      } else {
                        final newItems = List<TitleConfig>.from(
                          widget.settings.tags,
                        );
                        final moved = newItems.removeAt(index);
                        newItems.insert(index - 1, moved);
                        widget.onUpdate(
                          widget.settings.copyWith(tags: newItems),
                        );
                      }
                    }
                  : null,
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 16,
                color: index > 0 ? Colors.grey.shade600 : Colors.grey.shade300,
              ),
            ),
            InkWell(
              onTap: index < totalCount - 1
                  ? () {
                      if (_activeTabIndex == 0) {
                        final newItems = List<TitleConfig>.from(
                          widget.settings.titles,
                        );
                        final moved = newItems.removeAt(index);
                        newItems.insert(index + 1, moved);
                        widget.onUpdate(
                          widget.settings.copyWith(titles: newItems),
                        );
                      } else {
                        final newItems = List<TitleConfig>.from(
                          widget.settings.tags,
                        );
                        final moved = newItems.removeAt(index);
                        newItems.insert(index + 1, moved);
                        widget.onUpdate(
                          widget.settings.copyWith(tags: newItems),
                        );
                      }
                    }
                  : null,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: index < totalCount - 1
                    ? Colors.grey.shade600
                    : Colors.grey.shade300,
              ),
            ),
          ],
        );

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isVeryNarrow ? 6 : 12,
            vertical: isVeryNarrow ? 6 : 8,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).cardColor,
          ),
          child: Row(
            children: [
              upDownArrows,
              SizedBox(width: isVeryNarrow ? 4 : 8),
              _buildColorPicker(item, compact: compact && box.maxWidth < 500),
              SizedBox(width: isVeryNarrow ? 6 : 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('name-${item.id}'),
                        initialValue: item.name,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          border: InputBorder.none,
                          hintText: 'Title name…',
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        onChanged: (val) =>
                            _updateItem(item.copyWith(name: val)),
                      ),
                    ),
                    if (index == 0 && _activeTabIndex == 0 && !isVeryNarrow)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0F4C75,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(
                              0xFF0F4C75,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text(
                          'DEFAULT',
                          style: TextStyle(
                            color: Color(0xFF0F4C75),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.isAllStoresMode && !compact) ...[
                const SizedBox(width: 8),
                Flexible(
                  fit: FlexFit.loose,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildInlineCheckbox(
                          'Leadership',
                          item.isLeadership,
                          (v) => _updateItem(item.copyWith(isLeadership: v)),
                        ),
                        const SizedBox(width: 6),
                        _buildLinkChecklistPill(item),
                        const SizedBox(width: 6),
                        _buildInlineCheckbox(
                          'Mgr Permit',
                          item.mgrPermit,
                          (v) => _updateItem(item.copyWith(mgrPermit: v)),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.grey,
                            size: 20,
                          ),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDelete(item),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(width: isVeryNarrow ? 4 : 8),
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(
                    Icons.settings,
                    color: Colors.grey,
                    size: 20,
                  ),
                  tooltip: 'Settings',
                  onPressed: () => _showSettingsDialog(item),
                ),
                const SizedBox(width: 4),
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.grey,
                    size: 20,
                  ),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(item),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInlineCheckbox(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppCheckbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: value
                    ? Theme.of(context).textTheme.bodyLarge?.color
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkChecklistPill(TitleConfig item) {
    final isChecked = item.linkChecklist;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        final willBeChecked = !isChecked;
        String? checklistId = item.linkedChecklistId;
        if (willBeChecked && (checklistId == null || checklistId.isEmpty)) {
          checklistId = widget.settings.checklists.firstOrNull?.id;
        }
        _updateItem(
          item.copyWith(
            linkChecklist: willBeChecked,
            linkedChecklistId: checklistId,
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isChecked
              ? (isDark
                    ? const Color(0xFF0F4C75).withValues(alpha: 0.3)
                    : const Color(0xFFE8F1F5))
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isChecked ? const Color(0xFF0F4C75) : Colors.grey.shade300,
            width: isChecked ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppCheckbox(
              value: isChecked,
              onChanged: (v) {
                final willBeChecked = v ?? false;
                String? checklistId = item.linkedChecklistId;
                if (willBeChecked &&
                    (checklistId == null || checklistId.isEmpty)) {
                  checklistId = widget.settings.checklists.firstOrNull?.id;
                }
                _updateItem(
                  item.copyWith(
                    linkChecklist: willBeChecked,
                    linkedChecklistId: checklistId,
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(
              'Link Checklist',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isChecked
                    ? (isDark ? Colors.white : const Color(0xFF0F4C75))
                    : Colors.grey.shade700,
              ),
            ),
            if (isChecked && widget.settings.checklists.length > 1) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Select linked checklist',
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: isChecked
                      ? (isDark ? Colors.white70 : const Color(0xFF0F4C75))
                      : Colors.grey,
                ),
                onSelected: (cid) {
                  _updateItem(item.copyWith(linkedChecklistId: cid));
                },
                itemBuilder: (context) {
                  return widget.settings.checklists.map((c) {
                    final selected = c.id == item.linkedChecklistId;
                    return PopupMenuItem(
                      value: c.id,
                      child: Row(
                        children: [
                          Text(c.name),
                          if (selected) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.check,
                              size: 16,
                              color: Color(0xFF0F4C75),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmDelete(TitleConfig item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(_activeTabIndex == 0 ? 'Delete Title' : 'Delete Tag'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_activeTabIndex == 0) {
                final newItems = List<TitleConfig>.from(widget.settings.titles)
                  ..removeWhere((e) => e.id == item.id);
                widget.onUpdate(widget.settings.copyWith(titles: newItems));
              } else {
                final newItems = List<TitleConfig>.from(widget.settings.tags)
                  ..removeWhere((e) => e.id == item.id);
                widget.onUpdate(widget.settings.copyWith(tags: newItems));
              }
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(TitleConfig item) {
    showDialog(
      context: context,
      builder: (context) {
        TitleConfig localItem =
            (_activeTabIndex == 0
                    ? widget.settings.titles
                    : widget.settings.tags)
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
              title: Text(
                '${localItem.name} Settings',
                style: TextStyle(
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('Leadership'),
                      value: localItem.isLeadership,
                      onChanged: (val) =>
                          updateAndSet(localItem.copyWith(isLeadership: val)),
                    ),
                    SwitchListTile(
                      title: const Text('Manager Permit Required'),
                      value: localItem.mgrPermit,
                      onChanged: (val) =>
                          updateAndSet(localItem.copyWith(mgrPermit: val)),
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
                    Navigator.of(context).pop();
                    _confirmDelete(item);
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
  }

  void _updateItem(TitleConfig newItem) {
    if (_activeTabIndex == 0) {
      final newItems = widget.settings.titles
          .map((e) => e.id == newItem.id ? newItem : e)
          .toList();
      widget.onUpdate(widget.settings.copyWith(titles: newItems));
    } else {
      final newItems = widget.settings.tags
          .map((e) => e.id == newItem.id ? newItem : e)
          .toList();
      widget.onUpdate(widget.settings.copyWith(tags: newItems));
    }
  }

  Widget _buildChecklistSection(
    TitleConfig item,
    Function(TitleConfig) updateAndSet,
  ) {
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
              value:
                  widget.settings.checklists.any(
                    (c) => c.id == item.linkedChecklistId,
                  )
                  ? item.linkedChecklistId
                  : null,
              items: widget.settings.checklists
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  )
                  .toList(),
              dropdownColor: Theme.of(context).cardColor,
              onChanged: (val) {
                if (val != null)
                  updateAndSet(item.copyWith(linkedChecklistId: val));
              },
            ),
          ),
          SwitchListTile(
            title: const Text(
              'Auto-promote on completion',
              style: TextStyle(fontSize: 14),
            ),
            value: item.autoPromoteOnChecklist,
            onChanged: (val) =>
                updateAndSet(item.copyWith(autoPromoteOnChecklist: val)),
          ),
        ],
      ],
    );
  }

  Widget _buildColorPicker(TitleConfig item, {bool compact = false}) {
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
          icon: const Icon(Icons.keyboard_arrow_down, size: 16),
          selectedItemBuilder: (_) => [
            for (final c in names) Center(child: dot(c)),
          ],
          items: names.map((c) {
            return DropdownMenuItem(
              value: c,
              child: Center(child: dot(c)),
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
