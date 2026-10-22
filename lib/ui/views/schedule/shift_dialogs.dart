import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';
import '../../../models/user_model.dart';
import 'schedule_common.dart';
import 'schedule_ops.dart';

// =============================================================================
// Add / edit a piece
// =============================================================================

class PieceDialogResult {
  final String userId;
  final String? traineeId;
  final String rowId;
  final int start;
  final int end;
  const PieceDialogResult({
    required this.userId,
    required this.rowId,
    required this.start,
    required this.end,
    this.traineeId,
  });
}

Future<PieceDialogResult?> showPieceDialog(
  BuildContext context, {
  required ScheduleDay day,
  required DateTime date,
  required List<UserModel> people,
  required Map<String, UserModel> usersById,
  required List<TimeOffEntry> timeOff,
  required String rowId,
  required int start,
  required int end,
  String? fixedUserId,
  String? editingPieceId,
}) {
  return showDialog<PieceDialogResult>(
    context: context,
    builder: (_) => _PieceDialog(
      day: day,
      date: date,
      people: people,
      usersById: usersById,
      timeOff: timeOff,
      rowId: rowId,
      start: start,
      end: end,
      fixedUserId: fixedUserId,
      editingPieceId: editingPieceId,
    ),
  );
}

class _PieceDialog extends StatefulWidget {
  final ScheduleDay day;
  final DateTime date;
  final List<UserModel> people;
  final Map<String, UserModel> usersById;
  final List<TimeOffEntry> timeOff;
  final String rowId;
  final int start;
  final int end;
  final String? fixedUserId;
  final String? editingPieceId;

  const _PieceDialog({
    required this.day,
    required this.date,
    required this.people,
    required this.usersById,
    required this.timeOff,
    required this.rowId,
    required this.start,
    required this.end,
    this.fixedUserId,
    this.editingPieceId,
  });

  @override
  State<_PieceDialog> createState() => _PieceDialogState();
}

class _PieceDialogState extends State<_PieceDialog> {
  late String _rowId = widget.rowId;
  late int _start = widget.start;
  late int _end = widget.end;
  late String? _userId = widget.fixedUserId;
  bool _training = false;
  String? _traineeId;
  String _search = '';
  String? _error;

  bool get _editing => widget.editingPieceId != null;
  ScheduleRow? get _row => widget.day.rowById(_rowId);

  String? get _conflict {
    if (_userId == null) return null;
    String? unavailable(String? uid) => uid == null || uid.isEmpty
        ? null
        : availabilityConflict(
            widget.usersById[uid],
            date: widget.date,
            start: _start,
            end: _end,
            timeOff: widget.timeOff,
          );
    return pieceConflict(
          widget.day,
          userId: _userId!,
          traineeId: _training ? _traineeId : null,
          rowId: _rowId,
          start: _start,
          end: _end,
          ignorePieceId: widget.editingPieceId,
          users: widget.usersById,
        ) ??
        unavailable(_userId) ??
        (_training ? unavailable(_traineeId) : null);
  }

  void _save() {
    if (_userId == null) {
      setState(() => _error = 'Pick who is working this.');
      return;
    }
    if (_training && (_traineeId == null || _traineeId!.isEmpty)) {
      setState(() => _error = 'Pick the trainee, or turn off training.');
      return;
    }
    final c = _conflict;
    if (c != null) {
      setState(() => _error = c);
      return;
    }
    Navigator.pop(
      context,
      PieceDialogResult(
        userId: _userId!,
        traineeId: _training ? _traineeId : null,
        rowId: _rowId,
        start: _start,
        end: _end,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final user = _userId == null ? null : widget.usersById[_userId];
    final existingShift = _userId == null
        ? null
        : widget.day.shiftForUser(_userId!);
    final warnings = user == null
        ? const <String>[]
        : pieceWarnings(
            widget.day,
            date: widget.date,
            user: user,
            row: _row,
            start: _start,
            end: _end,
            timeOff: widget.timeOff,
          );
    final liveConflict = _conflict;

    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: Text(_editing ? 'Edit shift piece' : 'Add to schedule'),
      content: SizedBox(
        width: 720,
        height: 470,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------------- Left: where + when
            SizedBox(
              width: 280,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('row-$_rowId'),
                      initialValue: _rowId,
                      isExpanded: true,
                      dropdownColor: theme.cardColor,
                      decoration: const InputDecoration(
                        labelText: 'Row',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (var i = 0; i < widget.day.rows.length; i++)
                          DropdownMenuItem(
                            value: widget.day.rows[i].id,
                            child: Text(
                              _rowLabel(widget.day.rows[i], i),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _error = null;
                        _rowId = v ?? _rowId;
                      }),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TimeDropdown(
                            label: 'Start',
                            value: _start,
                            onChanged: (v) => setState(() {
                              _error = null;
                              _start = v;
                              if (_end <= _start) {
                                _end = math.min(
                                  _start + 60,
                                  kMaxScheduleMinute,
                                );
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TimeDropdown(
                            label: 'End',
                            value: _end,
                            onChanged: (v) => setState(() {
                              _error = null;
                              _end = v;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatHours(math.max(0, _end - _start) / 60)} hours',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    if (_row != null && _row!.windows.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Row needs: ${_row!.windows.map((w) => formatRange(w.start, w.end)).join(', ')}',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                    if (!_editing) ...[
                      const SizedBox(height: 18),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _training,
                        title: const Text('Training shift'),
                        subtitle: const Text('Two people in one slot'),
                        onChanged: (v) => setState(() {
                          _error = null;
                          _training = v;
                        }),
                      ),
                      if (_training)
                        DropdownButtonFormField<String>(
                          key: ValueKey('trainee-$_traineeId'),
                          initialValue: _traineeId,
                          isExpanded: true,
                          dropdownColor: theme.cardColor,
                          menuMaxHeight: 320,
                          decoration: const InputDecoration(
                            labelText: 'Trainee',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final p in widget.people)
                              if (p.id != _userId)
                                DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    '${personName(p)}${p.title == null ? '' : ' · ${p.title}'}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                          ],
                          onChanged: (v) => setState(() {
                            _error = null;
                            _traineeId = v;
                          }),
                        ),
                    ],
                    if (existingShift != null && !_editing) ...[
                      const SizedBox(height: 14),
                      _InfoBox(
                        icon: Icons.call_split,
                        color: AppTheme.accent2,
                        text:
                            'Adds to ${personName(user, short: true)}\'s shift '
                            '(${formatRange(existingShift.start, existingShift.end)}). '
                            'Their shift can span more than one row.',
                      ),
                    ],
                    for (final w in warnings.where(
                      (w) => w != liveConflict,
                    )) ...[
                      const SizedBox(height: 8),
                      _InfoBox(
                        icon: Icons.warning_amber_rounded,
                        color: AppTheme.accent,
                        text: w,
                      ),
                    ],
                    if ((_error ?? liveConflict) != null) ...[
                      const SizedBox(height: 8),
                      _InfoBox(
                        icon: Icons.block,
                        color: Colors.red,
                        text: (_error ?? liveConflict)!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            VerticalDivider(width: 1, color: theme.dividerColor),
            const SizedBox(width: 20),
            // ---------------- Right: who
            Expanded(
              child: widget.fixedUserId != null
                  ? _FixedPerson(user: user)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, size: 20),
                            hintText: 'Search team members',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              setState(() => _search = v.trim().toLowerCase()),
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: _buildPeopleList(theme)),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
          ),
          child: Text(_editing ? 'Save' : 'Add to schedule'),
        ),
      ],
    );
  }

  Widget _buildPeopleList(ThemeData theme) {
    final row = _row;
    final key = dateKey(widget.date);
    final list = widget.people.where((p) {
      if (_search.isEmpty) return true;
      return '${personName(p)} ${p.title ?? ''}'.toLowerCase().contains(
        _search,
      );
    }).toList();

    // People who fit the row first, then by name.
    list.sort((a, b) {
      final fa = row == null || userFitsRow(a, row) ? 0 : 1;
      final fb = row == null || userFitsRow(b, row) ? 0 : 1;
      if (fa != fb) return fa - fb;
      return personName(a).compareTo(personName(b));
    });

    if (list.isEmpty) {
      return Center(
        child: Text(
          'No team members match.',
          style: TextStyle(color: theme.textTheme.bodySmall?.color),
        ),
      );
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        final fits = row == null || userFitsRow(p, row);
        final shift = widget.day.shifts
            .where((s) => s.involves(p.id ?? ''))
            .firstOrNull;
        final off = widget.timeOff.any(
          (t) => t.userId == p.id && t.covers(key),
        );
        final avail = availabilityFor(p, widget.date);
        final unavailable =
            avail != null && !avail.any((w) => w.containsRange(_start, _end));
        final selected = p.id == _userId;

        final tags = <(String, Color)>[
          if (shift != null)
            (
              shift.userId == p.id
                  ? 'Scheduled ${formatRange(shift.start, shift.end)}'
                  : 'Training ${formatRange(shift.start, shift.end)}',
              AppTheme.accent2,
            ),
          if (off) ('Time off', Colors.red),
          if (unavailable) ('Not available', AppTheme.accent),
          if (!fits) ('Not allowed in this row', Colors.grey),
        ];

        return Opacity(
          opacity: fits ? 1 : 0.45,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: !fits
                ? null
                : () => setState(() {
                    _error = null;
                    _userId = p.id;
                  }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? AppTheme.accent : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: selected
                        ? AppTheme.accent
                        : theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          personName(p),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                        if (p.title != null)
                          Text(
                            p.title!,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final (label, color) in tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _rowLabel(ScheduleRow r, int i) {
  final name = r.label.isNotEmpty
      ? r.label
      : (r.isRestricted ? r.allowedTitles.join(', ') : 'Anyone');
  final when = r.windows.isEmpty
      ? ''
      : ' (${r.windows.map((w) => formatRange(w.start, w.end)).join(', ')})';
  return 'Row ${i + 1} · $name$when';
}

class _FixedPerson extends StatelessWidget {
  final UserModel? user;
  const _FixedPerson({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          personName(user),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: theme.textTheme.titleLarge?.color,
          ),
        ),
        if (user?.title != null)
          Text(
            user!.title!,
            style: TextStyle(color: theme.textTheme.bodySmall?.color),
          ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBox({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Move part of a piece into another row
// =============================================================================

class SplitResult {
  final int at;
  final bool moveLater;
  final String targetRowId;
  const SplitResult(this.at, this.moveLater, this.targetRowId);
}

Future<SplitResult?> showSplitDialog(
  BuildContext context, {
  required ScheduleDay day,
  required Shift shift,
  required ShiftPiece piece,
  required Map<String, UserModel> usersById,
}) {
  return showDialog<SplitResult>(
    context: context,
    builder: (_) => _SplitDialog(
      day: day,
      shift: shift,
      piece: piece,
      usersById: usersById,
    ),
  );
}

class _SplitDialog extends StatefulWidget {
  final ScheduleDay day;
  final Shift shift;
  final ShiftPiece piece;
  final Map<String, UserModel> usersById;
  const _SplitDialog({
    required this.day,
    required this.shift,
    required this.piece,
    required this.usersById,
  });

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  late int _at;
  bool _moveLater = true;
  String? _target;

  @override
  void initState() {
    super.initState();
    final p = widget.piece;
    // Default split: where this row's needed window ends, else the middle.
    final row = widget.day.rowById(p.rowId);
    final windowEnd = row?.windows
        .where((w) => w.end > p.start && w.end < p.end)
        .map((w) => w.end)
        .firstOrNull;
    final mid =
        p.start + ((p.end - p.start) ~/ 2 ~/ kScheduleStep) * kScheduleStep;
    _at = windowEnd ?? (mid <= p.start ? p.start + kScheduleStep : mid);
    _target = _suggestTarget();
  }

  (int, int) get _movedRange =>
      _moveLater ? (_at, widget.piece.end) : (widget.piece.start, _at);

  String? _suggestTarget() {
    final (s, e) = _movedRange;
    for (final r in widget.day.rows) {
      if (r.id == widget.piece.rowId) continue;
      final free = !widget.day
          .piecesInRow(r.id)
          .any((x) => x.$2.overlaps(s, e));
      if (free && r.windows.any((w) => w.containsRange(s, e))) return r.id;
    }
    return widget.day.rows
        .where((r) => r.id != widget.piece.rowId)
        .firstOrNull
        ?.id;
  }

  String? get _conflict {
    final t = _target;
    if (t == null) return 'Pick a row to move it to.';
    final (s, e) = _movedRange;
    final row = widget.day.rowById(t);
    if (row != null &&
        !userFitsRow(widget.usersById[widget.shift.userId], row)) {
      return 'Not allowed in that row (only ${row.allowedTitles.join(', ')}).';
    }
    for (final (sh, p) in widget.day.piecesInRow(t)) {
      if (p.overlaps(s, e)) {
        return 'That row already has '
            '${personName(widget.usersById[sh.userId])} '
            '${formatRange(p.start, p.end)}.';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.piece;
    final (s, e) = _movedRange;
    final conflict = _conflict;
    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: const Text('Move part of this shift to another row'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${personName(widget.usersById[widget.shift.userId])}: '
              '${formatRange(p.start, p.end, compact: false)}',
              style: TextStyle(color: theme.textTheme.bodySmall?.color),
            ),
            const SizedBox(height: 14),
            TimeDropdown(
              label: 'Split at',
              value: _at,
              min: p.start + kScheduleStep,
              max: p.end - kScheduleStep,
              onChanged: (v) => setState(() {
                _at = v;
                _target ??= _suggestTarget();
              }),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text('Move ${formatRange(_at, p.end)}'),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Move ${formatRange(p.start, _at)}'),
                ),
              ],
              selected: {_moveLater},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _moveLater = v.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('target-$_target'),
              initialValue: _target,
              isExpanded: true,
              dropdownColor: theme.cardColor,
              decoration: const InputDecoration(
                labelText: 'Into row',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (var i = 0; i < widget.day.rows.length; i++)
                  if (widget.day.rows[i].id != p.rowId)
                    DropdownMenuItem(
                      value: widget.day.rows[i].id,
                      child: Text(
                        _rowLabel(widget.day.rows[i], i),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (v) => setState(() => _target = v),
            ),
            const SizedBox(height: 8),
            Text(
              'Moves ${formatRange(s, e, compact: false)}.',
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
            if (conflict != null) ...[
              const SizedBox(height: 10),
              _InfoBox(icon: Icons.block, color: Colors.red, text: conflict),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: conflict != null
              ? null
              : () => Navigator.pop(
                  context,
                  SplitResult(_at, _moveLater, _target!),
                ),
          child: const Text('Move'),
        ),
      ],
    );
  }
}

// =============================================================================
// Trainee picker
// =============================================================================

/// Returns the trainee id, '' to remove the trainee, or null if cancelled.
Future<String?> showTraineeDialog(
  BuildContext context, {
  required ScheduleDay day,
  required Shift shift,
  required List<UserModel> people,
  required Map<String, UserModel> usersById,
}) {
  String? picked = shift.traineeId;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final theme = Theme.of(ctx);
        String? conflict;
        if (picked != null && picked!.isNotEmpty) {
          for (final s in day.shifts) {
            if (s.id == shift.id || !s.involves(picked!)) continue;
            if (s.pieces.any(
              (p) => shift.pieces.any((q) => p.overlaps(q.start, q.end)),
            )) {
              conflict =
                  '${personName(usersById[picked])} is already working '
                  '${formatRange(s.start, s.end)}.';
            }
          }
        }
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: const Text('Training shift'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'The trainee works the same slots as '
                  '${personName(usersById[shift.userId])} '
                  '(${formatRange(shift.start, shift.end)}). Both count toward '
                  'labor hours.',
                  style: TextStyle(color: theme.textTheme.bodySmall?.color),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: picked,
                  isExpanded: true,
                  menuMaxHeight: 320,
                  dropdownColor: theme.cardColor,
                  decoration: const InputDecoration(
                    labelText: 'Trainee',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final p in people)
                      if (p.id != shift.userId)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${personName(p)}${p.title == null ? '' : ' · ${p.title}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: (v) => setState(() => picked = v),
                ),
                if (conflict != null) ...[
                  const SizedBox(height: 10),
                  _InfoBox(
                    icon: Icons.block,
                    color: Colors.red,
                    text: conflict,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (shift.isTraining)
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text(
                  'Remove trainee',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: picked == null || conflict != null
                  ? null
                  : () => Navigator.pop(ctx, picked),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
