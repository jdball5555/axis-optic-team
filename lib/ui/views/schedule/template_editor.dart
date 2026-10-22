import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';
import '../../../models/store_settings_model.dart';
import '../../../providers/app_providers.dart';
import '../../../services/schedule_repository.dart';
import '../../widgets/unsaved_changes_dialog.dart';
import 'schedule_common.dart';
import 'schedule_ops.dart';

/// Full-screen-ish dialog to create and edit staffing templates.
Future<void> showTemplateManager(
  BuildContext context, {
  required String storeId,
  required List<String> allTitles,
  String? initialTemplateId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TemplateManager(
      storeId: storeId,
      allTitles: allTitles,
      initialTemplateId: initialTemplateId,
    ),
  );
}

class _TemplateManager extends ConsumerStatefulWidget {
  final String storeId;
  final List<String> allTitles;
  final String? initialTemplateId;

  const _TemplateManager({
    required this.storeId,
    required this.allTitles,
    this.initialTemplateId,
  });

  @override
  ConsumerState<_TemplateManager> createState() => _TemplateManagerState();
}

class _TemplateManagerState extends ConsumerState<_TemplateManager> {
  ScheduleTemplate? _draft;
  bool _isNew = false;
  bool _dirty = false;
  bool _saving = false;
  bool _initialized = false;

  /// Stores the selected template was saved to, so a save can remove it from
  /// stores that were unticked.
  List<String> _savedStoreIds = const [];

  // Quick-add bar
  int _qaCount = 1;
  int _qaStart = 5 * 60 + 15;
  int _qaEnd = 22 * 60 + 45;
  List<String> _qaTitles = const [];
  bool _qaCombine = true;

  ScheduleRepository get _repo =>
      ref.read(scheduleRepositoryProvider(widget.storeId));

  void _edit(ScheduleTemplate t) => setState(() {
    _draft = t;
    _dirty = true;
  });

  Future<bool> _confirmLeaveDraft() async {
    if (!_dirty || _draft == null) return true;
    final choice = await showUnsavedChangesDialog(context);
    if (choice == null) return false;
    if (choice == UnsavedChoice.save) return _save();
    return true;
  }

  Future<void> _select(ScheduleTemplate? t, {bool isNew = false}) async {
    if (!await _confirmLeaveDraft()) return;
    setState(() {
      _draft = _normalized(t);
      _isNew = isNew;
      _dirty = isNew;
      _savedStoreIds = isNew ? const [] : _storesOf(t);
    });
  }

  /// Older templates may have bars that touch; show them as one.
  ScheduleTemplate? _normalized(ScheduleTemplate? t) => t?.copyWith(
    rows: [
      for (final r in t.rows) r.copyWith(windows: mergeWindows(r.windows)),
    ],
  );

  List<String> _storesOf(ScheduleTemplate? t) => t == null
      ? const []
      : (t.storeIds.isEmpty ? [widget.storeId] : t.storeIds);

  List<({String id, String name})> get _allStores {
    final list = [
      for (final s in ref.read(allStoresStreamProvider).valueOrNull ?? const [])
        if (s['id'] is String)
          (
            id: s['id'] as String,
            name: (s['name'] as String?)?.trim().isNotEmpty == true
                ? (s['name'] as String).trim()
                : 'Untitled Store',
          ),
    ];
    if (!list.any((s) => s.id == widget.storeId)) {
      list.add((id: widget.storeId, name: 'This store'));
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<bool> _save() async {
    final draft = _draft;
    if (draft == null) return true;
    if (draft.name.trim().isEmpty) {
      _snack('Give the template a name first.');
      return false;
    }
    final storeIds = draft.allStores
        ? [for (final s in _allStores) s.id]
        : _storesOf(draft);
    final toSave = draft.copyWith(name: draft.name.trim(), storeIds: storeIds);
    setState(() => _saving = true);
    try {
      await _repo.saveTemplate(toSave, previousStoreIds: _savedStoreIds);
      if (!mounted) return true;
      final leftThisStore = !storeIds.contains(widget.storeId);
      setState(() {
        _dirty = false;
        _isNew = false;
        _saving = false;
        _savedStoreIds = storeIds;
        _draft = leftThisStore ? null : toSave;
      });
      if (leftThisStore) {
        _snack(
          'Saved. It\'s no longer shared with this store, so it\'s hidden here.',
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Could not save template: $e');
      }
      return false;
    }
  }

  Future<void> _delete() async {
    final draft = _draft;
    if (draft == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text('Delete template?'),
        content: Text(
          'Delete "${draft.name}"? Days already built from it keep their rows '
          'and shifts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!_isNew) {
      await _repo.deleteTemplate(draft.copyWith(storeIds: _savedStoreIds));
    }
    setState(() {
      _draft = null;
      _dirty = false;
      _isNew = false;
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // --- Row operations -------------------------------------------------------

  /// Saves rows into the draft, joining bars in a row that touch.
  void _setRows(List<ScheduleRow> rows) => _edit(
    _draft!.copyWith(
      rows: [
        for (final r in rows) r.copyWith(windows: mergeWindows(r.windows)),
      ],
    ),
  );

  void _quickAdd() {
    if (_qaEnd <= _qaStart) {
      _snack('End time must be after the start time.');
      return;
    }
    final added = [
      for (var i = 0; i < _qaCount; i++)
        ScheduleRow(
          id: newScheduleId(),
          label: _qaTitles.isNotEmpty ? 'Leader' : '',
          windows: [TimeWindow(_qaStart, _qaEnd)],
          allowedTitles: _qaTitles,
        ),
    ];
    _setRows(
      _qaCombine ? packRows(_draft!.rows, added) : [..._draft!.rows, ...added],
    );
  }

  void _combineRows() {
    final before = _draft!.rows.length;
    final packed = compactRows(_draft!.rows);
    _setRows(packed);
    final saved = before - packed.length;
    _snack('Combined into ${packed.length} rows ($saved fewer).');
  }

  Future<void> _editRow(int i) async {
    final rows = [..._draft!.rows];
    final updated = await showRowEditor(
      context,
      row: rows[i],
      allTitles: widget.allTitles,
      title: 'Row ${i + 1}',
    );
    if (updated == null) return;
    rows[i] = updated;
    _setRows(rows);
  }

  void _duplicateRow(int i) {
    final rows = [..._draft!.rows];
    rows.insert(i + 1, rows[i].copyWith(id: newScheduleId()));
    _setRows(rows);
  }

  void _moveRow(int i, int delta) {
    final rows = [..._draft!.rows];
    final j = i + delta;
    if (j < 0 || j >= rows.length) return;
    final r = rows.removeAt(i);
    rows.insert(j, r);
    _setRows(rows);
  }

  void _removeRow(int i) {
    final rows = [..._draft!.rows]..removeAt(i);
    _setRows(rows);
  }

  void _removeWindow(int i, TimeWindow w) {
    final rows = [..._draft!.rows];
    rows[i] = rows[i].copyWith(
      windows: rows[i].windows.where((x) => x != w).toList(),
    );
    _setRows(rows);
  }

  /// Adds a drawn slot to row [lane], or as a new row when [lane] is past the
  /// last row.
  void _addWindow(int lane, TimeWindow w) {
    final rows = [..._draft!.rows];
    if (lane >= rows.length) {
      final row = ScheduleRow(
        id: newScheduleId(),
        label: _qaTitles.isNotEmpty ? 'Leader' : '',
        windows: [w],
        allowedTitles: _qaTitles,
      );
      _setRows(_qaCombine ? packRows(rows, [row]) : [...rows, row]);
      return;
    }
    if (rows[lane].windows.any((x) => x.overlaps(w.start, w.end))) {
      _snack('That overlaps a time already in this row.');
      return;
    }
    rows[lane] = rows[lane].copyWith(
      windows: [...rows[lane].windows, w]
        ..sort((a, b) => a.start.compareTo(b.start)),
    );
    _setRows(rows);
  }

  /// Moves / resizes a slot, possibly into another row (or a new one when
  /// [to] is past the last row). A row left with no times is removed.
  void _changeWindow(int from, TimeWindow old, int to, TimeWindow updated) {
    final rows = [..._draft!.rows];
    final source = rows[from];
    final remaining = source.windows.where((x) => x != old).toList();
    List<TimeWindow> withUpdated(List<TimeWindow> ws) =>
        [...ws, updated]..sort((a, b) => a.start.compareTo(b.start));

    if (to == from) {
      if (remaining.any((x) => x.overlaps(updated.start, updated.end))) {
        _snack('That overlaps another time in this row.');
        return;
      }
      rows[from] = source.copyWith(windows: withUpdated(remaining));
      _setRows(rows);
      return;
    }
    if (to >= rows.length) {
      rows.add(source.copyWith(id: newScheduleId(), windows: [updated]));
    } else {
      if (rows[to].windows.any((x) => x.overlaps(updated.start, updated.end))) {
        _snack('That overlaps a time already in that row.');
        return;
      }
      rows[to] = rows[to].copyWith(windows: withUpdated(rows[to].windows));
    }
    rows[from] = source.copyWith(windows: remaining);
    if (remaining.isEmpty) rows.removeAt(from);
    _setRows(rows);
  }

  Future<void> _pickStores() async {
    final draft = _draft!;
    final result = await showDialog<({bool all, List<String> ids})>(
      context: context,
      builder: (_) => _StoreScopeDialog(
        stores: _allStores,
        currentStoreId: widget.storeId,
        allStores: draft.allStores,
        selected: _storesOf(draft),
      ),
    );
    if (result == null) return;
    _edit(draft.copyWith(allStores: result.all, storeIds: result.ids));
  }

  String _scopeLabel(ScheduleTemplate t) {
    if (t.allStores) return 'All stores';
    final ids = _storesOf(t);
    if (ids.length == 1 && ids.first == widget.storeId)
      return 'This store only';
    final names = {for (final s in _allStores) s.id: s.name};
    if (ids.length <= 2) {
      return ids.map((id) => names[id] ?? 'Unknown store').join(', ');
    }
    return '${ids.length} stores';
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(scheduleTemplatesProvider(widget.storeId));
    final templates = templatesAsync.valueOrNull ?? const <ScheduleTemplate>[];

    if (!_initialized && templatesAsync.hasValue) {
      _initialized = true;
      final initial =
          templates
              .where((t) => t.id == widget.initialTemplateId)
              .firstOrNull ??
          templates.firstOrNull;
      if (initial != null) {
        _draft = _normalized(initial);
        _savedStoreIds = _storesOf(initial);
      }
    }

    return Dialog(
      backgroundColor: theme.scaffoldBackgroundColor,
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 1280,
        height: 860,
        child: Column(
          children: [
            _buildTopBar(theme),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTemplateList(theme, templates),
                  VerticalDivider(width: 1, color: theme.dividerColor),
                  Expanded(
                    child: _draft == null
                        ? _buildNoSelection(theme)
                        : _buildEditor(theme, _draft!),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Icon(Icons.table_chart, color: AppTheme.accent2),
          const SizedBox(width: 10),
          Text(
            'Staffing templates',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.titleLarge?.color,
            ),
          ),
          const Spacer(),
          if (_draft != null) ...[
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red,
              ),
              label: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _saving || !_dirty ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green,
                foregroundColor: Colors.white,
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(_dirty ? 'Save template' : 'Saved'),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (await _confirmLeaveDraft() && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateList(ThemeData theme, List<ScheduleTemplate> templates) {
    final draft = _draft;
    final items = [...templates, if (draft != null && _isNew) draft];
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => _select(
                ScheduleTemplate(id: newScheduleId(), name: 'New template'),
                isNew: true,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New template'),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No templates yet.',
                      style: TextStyle(color: theme.textTheme.bodySmall?.color),
                    ),
                  )
                : ListView(
                    children: [
                      for (final t in items)
                        _TemplateListTile(
                          name: draft?.id == t.id ? draft!.name : t.name,
                          subtitle:
                              '${(draft?.id == t.id ? draft! : t).rows.length} rows · '
                              '${formatHours((draft?.id == t.id ? draft! : t).neededHours)} hrs',
                          selected: draft?.id == t.id,
                          unsaved: draft?.id == t.id && _dirty,
                          onTap: () {
                            if (draft?.id == t.id) return;
                            _select(t);
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelection(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.table_chart,
            size: 52,
            color: theme.textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 12),
          Text(
            'Build a template for the slots you need filled each day',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Each row is one person-slot. A row can need coverage all day or '
            'only during certain windows.',
            style: TextStyle(color: theme.textTheme.bodySmall?.color),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _select(
              ScheduleTemplate(id: newScheduleId(), name: 'New template'),
              isNew: true,
            ),
            icon: const Icon(Icons.add),
            label: const Text('Create a template'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(ThemeData theme, ScheduleTemplate t) {
    final muted = theme.textTheme.bodySmall?.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            children: [
              SizedBox(
                width: 320,
                child: TextFormField(
                  key: ValueKey('name-${t.id}'),
                  initialValue: t.name,
                  decoration: const InputDecoration(
                    labelText: 'Template name',
                    hintText: 'e.g. Weekday, Saturday, Catering day',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _edit(_draft!.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Which stores can use this template',
                child: OutlinedButton.icon(
                  onPressed: _pickStores,
                  icon: const Icon(Icons.store_outlined, size: 18),
                  label: Text(_scopeLabel(t)),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t.rows.length} rows · ${formatHours(t.neededHours)} '
                      'labor hours needed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.rows.isEmpty
                          ? 'Blank: no one is required at any hour. Save it '
                                'as is, or drag on the timeline to add slots.'
                          : 'People needed: ${staffingSummary(t.rows)}',
                      style: TextStyle(fontSize: 12, color: muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (compactRows(t.rows).length < t.rows.length)
                Tooltip(
                  message:
                      'Put rows whose times don\'t overlap on the same line '
                      '(e.g. 11a–5p and 6p–10p)',
                  child: OutlinedButton.icon(
                    onPressed: _combineRows,
                    icon: const Icon(Icons.merge_type, size: 18),
                    label: const Text('Combine rows'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildQuickAdd(theme),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _TemplateTimeline(
              rows: t.rows,
              settings: ref.watch(storeSettingsProvider).valueOrNull,
              newRowHint: _qaTitles.isEmpty
                  ? 'Drag across the timeline to add a slot'
                  : 'Drag across the timeline to add a slot '
                        '(only ${_qaTitles.join(', ')})',
              onEdit: _editRow,
              onRemoveWindow: _removeWindow,
              onDuplicate: _duplicateRow,
              onMove: _moveRow,
              onRemove: _removeRow,
              onAddWindow: _addWindow,
              onChangeWindow: _changeWindow,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAdd(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Text(
            'Add',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          SizedBox(
            width: 80,
            child: DropdownButtonFormField<int>(
              key: ValueKey('qa-count-$_qaCount'),
              initialValue: _qaCount,
              isDense: true,
              dropdownColor: theme.cardColor,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (var i = 1; i <= 15; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) => setState(() => _qaCount = v ?? 1),
            ),
          ),
          Text(
            _qaCount == 1 ? 'row from' : 'rows from',
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
          SizedBox(
            width: 150,
            child: TimeDropdown(
              label: 'Start',
              value: _qaStart,
              onChanged: (v) => setState(() => _qaStart = v),
            ),
          ),
          Text('to', style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
          SizedBox(
            width: 150,
            child: TimeDropdown(
              label: 'End',
              value: _qaEnd,
              onChanged: (v) => setState(() => _qaEnd = v),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showTitlePicker(
                context,
                allTitles: widget.allTitles,
                selected: _qaTitles,
              );
              if (picked != null) setState(() => _qaTitles = picked);
            },
            icon: _qaTitles.isEmpty
                ? const Icon(Icons.people_outline, size: 16)
                : const Icon(Icons.star, size: 16),
            label: Text(
              _qaTitles.isEmpty ? 'Anyone' : 'Only ${_qaTitles.join(', ')}',
            ),
          ),
          Tooltip(
            message:
                'Fill gaps in existing rows instead of always adding new ones',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _qaCombine = !_qaCombine),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _qaCombine,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() => _qaCombine = v ?? true),
                  ),
                  Text(
                    'Share rows',
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _quickAdd,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add rows'),
          ),
        ],
      ),
    );
  }
}

class _TemplateListTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool selected;
  final bool unsaved;
  final VoidCallback onTap;

  const _TemplateListTile({
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.unsaved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? AppTheme.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Untitled' : name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            if (unsaved)
              Tooltip(
                message: 'Unsaved changes',
                child: Icon(Icons.circle, size: 8, color: AppTheme.accent),
              ),
          ],
        ),
      ),
    );
  }
}

/// Template rows on a timeline.
///  * Drag across empty space in a row to add a time to it, or across the
///    last (dashed) lane to add a new row.
///  * Drag a slot's edges to change its times; drag its middle to move it,
///    including up / down into another row.
///  * Click a slot or row for its options.
class _TemplateTimeline extends StatefulWidget {
  final List<ScheduleRow> rows;
  final StoreSettingsModel? settings;
  final String newRowHint;
  final ValueChanged<int> onEdit;
  final void Function(int index, TimeWindow window) onRemoveWindow;
  final ValueChanged<int> onDuplicate;
  final void Function(int index, int delta) onMove;
  final ValueChanged<int> onRemove;
  final void Function(int lane, TimeWindow window) onAddWindow;
  final void Function(int from, TimeWindow old, int to, TimeWindow updated)
  onChangeWindow;

  const _TemplateTimeline({
    required this.rows,
    required this.settings,
    required this.newRowHint,
    required this.onEdit,
    required this.onRemoveWindow,
    required this.onDuplicate,
    required this.onMove,
    required this.onRemove,
    required this.onAddWindow,
    required this.onChangeWindow,
  });

  @override
  State<_TemplateTimeline> createState() => _TemplateTimelineState();
}

enum _SlotDrag { move, resizeStart, resizeEnd }

class _TemplateTimelineState extends State<_TemplateTimeline> {
  static const double _rowH = 36;
  static const double _laneH = _rowH + 6;
  static const double _edge = 8;

  // Drawing a new slot.
  int? _drawLane;
  int? _drawFrom;
  int? _drawTo;

  // Moving / resizing an existing slot.
  int? _dragRow;
  TimeWindow? _dragWindow;
  _SlotDrag? _dragMode;
  Offset _delta = Offset.zero;

  List<ScheduleRow> get rows => widget.rows;

  int _snap(double minutes) =>
      (minutes / kScheduleStep).round() * kScheduleStep;

  int _minuteAt(TimelineMetrics m, double dx) =>
      (m.start + _snap(dx / m.ppm)).clamp(m.start, m.end).toInt();

  /// Where the slot being dragged would land: (row, window).
  (int, TimeWindow)? _preview(TimelineMetrics m) {
    final w = _dragWindow;
    if (w == null) return null;
    final shift = _snap(_delta.dx / m.ppm);
    switch (_dragMode!) {
      case _SlotDrag.move:
        final s = (w.start + shift).clamp(m.start, m.end - w.minutes).toInt();
        final row = (_dragRow! + (_delta.dy / _laneH).round())
            .clamp(0, rows.length)
            .toInt();
        return (row, TimeWindow(s, s + w.minutes));
      case _SlotDrag.resizeStart:
        final s = (w.start + shift)
            .clamp(m.start, w.end - kScheduleStep)
            .toInt();
        return (_dragRow!, TimeWindow(s, w.end));
      case _SlotDrag.resizeEnd:
        final e = (w.end + shift).clamp(w.start + kScheduleStep, m.end).toInt();
        return (_dragRow!, TimeWindow(w.start, e));
    }
  }

  bool _overlapsIn(int row, TimeWindow w) {
    if (row >= rows.length) return false;
    return rows[row].windows.any(
      (x) =>
          !(row == _dragRow && x == _dragWindow) && x.overlaps(w.start, w.end),
    );
  }

  void _endSlotDrag(TimelineMetrics m) {
    final p = _preview(m);
    final from = _dragRow;
    final old = _dragWindow;
    setState(() {
      _dragRow = null;
      _dragWindow = null;
      _dragMode = null;
      _delta = Offset.zero;
    });
    if (p == null || from == null || old == null) return;
    final (to, updated) = p;
    if (to == from && updated == old) return;
    widget.onChangeWindow(from, old, to, updated);
  }

  void _endDraw() {
    final lane = _drawLane;
    final a = _drawFrom;
    final b = _drawTo;
    setState(() {
      _drawLane = null;
      _drawFrom = null;
      _drawTo = null;
    });
    if (lane == null || a == null || b == null) return;
    final w = TimeWindow(a < b ? a : b, a < b ? b : a);
    if (w.minutes >= kScheduleStep) widget.onAddWindow(lane, w);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (s0, e0) = timelineRange(rows);
    final start = s0 < 5 * 60 ? s0 : 5 * 60;
    final end = e0 > 23 * 60 ? e0 : 23 * 60;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final m = TimelineMetrics(
            start: start,
            end: end,
            width: c.maxWidth.clamp(200.0, 4000.0).toDouble(),
          );
          final preview = _preview(m);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TimelineHeader(metrics: m),
              Expanded(
                child: SingleChildScrollView(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: TimelineGridPainter(
                            m,
                            theme.dividerColor.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          for (var i = 0; i <= rows.length; i++)
                            _lane(context, theme, m, i, preview),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showMenu(
    BuildContext context,
    int i,
    Offset at,
    TimeWindow? window,
  ) async {
    final r = rows[i];
    final v = await showMenuAt<String>(context, at, [
      const PopupMenuItem(
        value: 'edit',
        child: ListTile(
          dense: true,
          leading: Icon(Icons.edit_outlined, size: 18),
          title: Text('Edit times / who can fill it'),
        ),
      ),
      if (window != null && r.windows.length > 1)
        PopupMenuItem(
          value: 'remove_window',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.content_cut, size: 18),
            title: Text('Remove ${formatRange(window.start, window.end)} only'),
          ),
        ),
      const PopupMenuItem(
        value: 'duplicate',
        child: ListTile(
          dense: true,
          leading: Icon(Icons.copy, size: 18),
          title: Text('Duplicate row'),
        ),
      ),
      PopupMenuItem(
        value: 'up',
        enabled: i > 0,
        child: const ListTile(
          dense: true,
          leading: Icon(Icons.arrow_upward, size: 18),
          title: Text('Move up'),
        ),
      ),
      PopupMenuItem(
        value: 'down',
        enabled: i < rows.length - 1,
        child: const ListTile(
          dense: true,
          leading: Icon(Icons.arrow_downward, size: 18),
          title: Text('Move down'),
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'remove',
        child: ListTile(
          dense: true,
          leading: Icon(Icons.delete_outline, size: 18, color: Colors.red),
          title: Text('Remove row', style: TextStyle(color: Colors.red)),
        ),
      ),
    ]);
    switch (v) {
      case 'edit':
        widget.onEdit(i);
      case 'remove_window':
        widget.onRemoveWindow(i, window!);
      case 'duplicate':
        widget.onDuplicate(i);
      case 'up':
        widget.onMove(i, -1);
      case 'down':
        widget.onMove(i, 1);
      case 'remove':
        widget.onRemove(i);
    }
  }

  Widget _tile(
    ThemeData theme,
    TimelineMetrics m,
    ScheduleRow? row,
    TimeWindow w, {
    Color? highlight,
  }) {
    final slot = slotColors(theme);
    final titleColor = row != null && row.isRestricted
        ? colorForRow(row, widget.settings)
        : null;
    final tag = row == null ? null : rowTag(row);
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: slot.fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight ?? titleColor ?? slot.border,
          width: highlight != null || titleColor != null ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              formatRange(w.start, w.end),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: slot.text,
              ),
            ),
          ),
          if (tag != null && m.w(w.start, w.end) > 120) ...[
            const SizedBox(width: 6),
            Flexible(
              child: SlotTag(text: tag, color: titleColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lane(
    BuildContext context,
    ThemeData theme,
    TimelineMetrics m,
    int i,
    (int, TimeWindow)? preview,
  ) {
    final isNewLane = i == rows.length;
    final r = isNewLane ? null : rows[i];
    final muted = theme.textTheme.bodySmall?.color;

    TimeWindow? windowAt(double dx) {
      final minute = m.start + dx / m.ppm;
      return r?.windows
          .where((w) => minute >= w.start && minute < w.end)
          .firstOrNull;
    }

    return SizedBox(
      height: _laneH,
      width: m.width,
      child: Stack(
        children: [
          // Empty space: drag to draw a slot, click for row options.
          Positioned(
            left: 0,
            right: 0,
            top: 4,
            bottom: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.precise,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: isNewLane
                    ? null
                    : (d) => _showMenu(
                        context,
                        i,
                        d.globalPosition,
                        windowAt(d.localPosition.dx),
                      ),
                onPanStart: (d) => setState(() {
                  _drawLane = i;
                  _drawFrom = _minuteAt(m, d.localPosition.dx);
                  _drawTo = _drawFrom;
                }),
                onPanUpdate: (d) =>
                    setState(() => _drawTo = _minuteAt(m, d.localPosition.dx)),
                onPanEnd: (_) => _endDraw(),
                onPanCancel: _endDraw,
                child: Container(
                  alignment: Alignment.center,
                  decoration: isNewLane
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: theme.dividerColor,
                            style: BorderStyle.solid,
                          ),
                          color: theme.dividerColor.withValues(alpha: 0.12),
                        )
                      : null,
                  child: isNewLane && _drawLane != i
                      ? Text(
                          widget.newRowHint,
                          style: TextStyle(fontSize: 11, color: muted),
                        )
                      : (r != null && r.windows.isEmpty && _drawLane != i
                            ? Text(
                                'No times set — drag across to add one',
                                style: TextStyle(fontSize: 11, color: muted),
                              )
                            : null),
                ),
              ),
            ),
          ),
          // Existing slots.
          if (r != null)
            for (final w in r.windows)
              Positioned(
                left: m.x(w.start),
                width: m.w(w.start, w.end),
                top: 4,
                bottom: 6,
                child: Opacity(
                  opacity: i == _dragRow && w == _dragWindow ? 0.25 : 1,
                  child: _slotHandle(context, theme, m, i, r, w),
                ),
              ),
          // Slot being drawn.
          if (_drawLane == i && _drawFrom != null && _drawTo != null)
            Builder(
              builder: (_) {
                final a = _drawFrom!;
                final b = _drawTo!;
                final w = TimeWindow(a < b ? a : b, a < b ? b : a);
                return Positioned(
                  left: m.x(w.start),
                  width: m.w(w.start, w.end),
                  top: 4,
                  bottom: 6,
                  child: IgnorePointer(
                    child: _tile(
                      theme,
                      m,
                      r,
                      w,
                      highlight: _overlapsIn(i, w)
                          ? AppTheme.red
                          : AppTheme.accent2,
                    ),
                  ),
                );
              },
            ),
          // Where a dragged slot will land.
          if (preview != null && preview.$1 == i)
            Positioned(
              left: m.x(preview.$2.start),
              width: m.w(preview.$2.start, preview.$2.end),
              top: 4,
              bottom: 6,
              child: IgnorePointer(
                child: _tile(
                  theme,
                  m,
                  r ?? rows[_dragRow!],
                  preview.$2,
                  highlight: _overlapsIn(i, preview.$2)
                      ? AppTheme.red
                      : AppTheme.accent2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A slot you can click (options), drag by its edges (resize) or drag by
  /// its middle (move).
  Widget _slotHandle(
    BuildContext context,
    ThemeData theme,
    TimelineMetrics m,
    int i,
    ScheduleRow r,
    TimeWindow w,
  ) {
    final width = m.w(w.start, w.end);
    return Tooltip(
      message:
          '${formatRange(w.start, w.end, compact: false)}\n'
          'Drag to move · drag the edges to change times · click for options',
      waitDuration: const Duration(milliseconds: 700),
      child: GestureDetector(
        onTapUp: (d) => _showMenu(context, i, d.globalPosition, w),
        onPanStart: (d) => setState(() {
          final x = d.localPosition.dx;
          _dragRow = i;
          _dragWindow = w;
          _delta = Offset.zero;
          _dragMode = x <= _edge
              ? _SlotDrag.resizeStart
              : (x >= width - _edge ? _SlotDrag.resizeEnd : _SlotDrag.move);
        }),
        onPanUpdate: (d) => setState(() => _delta += d.delta),
        onPanEnd: (_) => _endSlotDrag(m),
        onPanCancel: () => _endSlotDrag(m),
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Stack(
            children: [
              Positioned.fill(child: _tile(theme, m, r, w)),
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _edge,
                child: MouseRegion(cursor: SystemMouseCursors.resizeLeftRight),
              ),
              const Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _edge,
                child: MouseRegion(cursor: SystemMouseCursors.resizeLeftRight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick which stores can use a template.
class _StoreScopeDialog extends StatefulWidget {
  final List<({String id, String name})> stores;
  final String currentStoreId;
  final bool allStores;
  final List<String> selected;

  const _StoreScopeDialog({
    required this.stores,
    required this.currentStoreId,
    required this.allStores,
    required this.selected,
  });

  @override
  State<_StoreScopeDialog> createState() => _StoreScopeDialogState();
}

enum _Scope { thisStore, all, specific }

class _StoreScopeDialogState extends State<_StoreScopeDialog> {
  late _Scope _scope = widget.allStores
      ? _Scope.all
      : (widget.selected.length == 1 &&
                widget.selected.first == widget.currentStoreId
            ? _Scope.thisStore
            : _Scope.specific);
  late final Set<String> _ids = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: const Text('Which stores can use this template?'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: RadioGroup<_Scope>(
            groupValue: _scope,
            onChanged: (v) => setState(() => _scope = v ?? _scope),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RadioListTile(
                  value: _Scope.thisStore,
                  contentPadding: EdgeInsets.zero,
                  title: Text('This store only'),
                ),
                const RadioListTile(
                  value: _Scope.all,
                  contentPadding: EdgeInsets.zero,
                  title: Text('All stores'),
                ),
                const RadioListTile(
                  value: _Scope.specific,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Specific stores'),
                ),
                if (_scope == _Scope.specific)
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Column(
                      children: [
                        for (final s in widget.stores)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: _ids.contains(s.id),
                            title: Text(
                              s.id == widget.currentStoreId
                                  ? '${s.name} (this store)'
                                  : s.name,
                            ),
                            onChanged: (v) => setState(
                              () => v == true
                                  ? _ids.add(s.id)
                                  : _ids.remove(s.id),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _scope == _Scope.specific && _ids.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  all: _scope == _Scope.all,
                  ids: switch (_scope) {
                    _Scope.thisStore => [widget.currentStoreId],
                    _Scope.all => [for (final s in widget.stores) s.id],
                    _Scope.specific => [
                      for (final s in widget.stores)
                        if (_ids.contains(s.id)) s.id,
                    ],
                  },
                )),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
