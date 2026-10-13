import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';

/// A board's positions, ranked (top = highest priority): drag to reorder,
/// rename, add, delete. [onChanged] gets the named positions, in order,
/// after every change (unnamed new ones are left out until named).
class PositionsEditor extends StatefulWidget {
  final List<ShiftPosition> positions;
  final ValueChanged<List<ShiftPosition>> onChanged;

  const PositionsEditor({
    super.key,
    required this.positions,
    required this.onChanged,
  });

  @override
  State<PositionsEditor> createState() => _PositionsEditorState();
}

class _PositionsEditorState extends State<PositionsEditor> {
  late final List<ShiftPosition> _items = [...widget.positions];

  void _changed() => widget.onChanged([
    for (final p in _items)
      if (p.name.trim().isNotEmpty) p.copyWith(name: p.name.trim()),
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Drag to rank them: the top position is the highest priority, and '
          'Auto-fill fills from the top down. Each position is one person; '
          'for a second spot add another position (e.g. "Front Counter 2") '
          'and rank it where it belongs.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Text(
                    'No positions yet.',
                    style: TextStyle(color: muted),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: _items.length,
                  onReorder: (from, to) {
                    setState(() {
                      if (to > from) to--;
                      _items.insert(to, _items.removeAt(from));
                    });
                    _changed();
                  },
                  itemBuilder: (context, i) {
                    final p = _items[i];
                    return Container(
                      key: ValueKey(p.id),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Icon(Icons.drag_indicator, color: muted),
                              ),
                            ),
                          ),
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.accent2.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              initialValue: p.name,
                              autofocus: p.name.isEmpty,
                              decoration: const InputDecoration(
                                hintText: 'e.g. Register, Drive-thru',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                // Find it by id: the list may have been
                                // reordered since this row was built.
                                final at = _items.indexWhere(
                                  (x) => x.id == p.id,
                                );
                                if (at < 0) return;
                                _items[at] = _items[at].copyWith(name: v);
                                _changed();
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () {
                              setState(
                                () => _items.removeWhere((x) => x.id == p.id),
                              );
                              _changed();
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(
              () => _items.add(ShiftPosition(id: newScheduleId(), name: '')),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add position'),
          ),
        ),
      ],
    );
  }
}
