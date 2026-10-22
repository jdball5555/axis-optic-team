import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/schedule_models.dart';
import 'positions_editor.dart';
import 'shift_layout_customizer.dart';

/// Shift board settings: a board for each schedule, or boards that combine
/// schedules, and each board's ranked positions. Every change is saved
/// right away through [onSave] (however the dialog is closed).
Future<void> showShiftBoardSettings(
  BuildContext context, {
  required ShiftConfig config,
  required ScheduleConfig schedules,
  String? boardId,
  required Future<void> Function(ShiftConfig) onSave,
}) => showDialog<void>(
  context: context,
  builder: (_) => ShiftBoardSettingsDialog(
    config: config,
    schedules: schedules,
    boardId: boardId,
    onSave: onSave,
  ),
);

class ShiftBoardSettingsDialog extends StatefulWidget {
  final ShiftConfig config;
  final ScheduleConfig schedules;
  final String? boardId;
  final Future<void> Function(ShiftConfig) onSave;

  const ShiftBoardSettingsDialog({
    super.key,
    required this.config,
    required this.schedules,
    this.boardId,
    required this.onSave,
  });

  @override
  State<ShiftBoardSettingsDialog> createState() =>
      _ShiftBoardSettingsDialogState();
}

class _ShiftBoardSettingsDialogState extends State<ShiftBoardSettingsDialog> {
  late ShiftConfig _c = _materialize(widget.config);
  late String? _selected = widget.boardId;
  Timer? _debounce;

  List<ScheduleBoard> get _schedules => widget.schedules.allBoards;
  List<ShiftBoard> get _boards => _c.boardsFor(widget.schedules);

  ShiftBoard? get _board =>
      _boards.where((b) => b.id == _selected).firstOrNull ??
      _boards.firstOrNull;

  /// Every schedule's board written out, so nothing depends on the older
  /// store-wide position list any more once saved.
  ShiftConfig _materialize(ShiftConfig c) => c.copyWith(
    scheduleBoards: {
      for (final b
          in c
              .copyWith(layout: ShiftBoardLayout.perSchedule)
              .boardsFor(widget.schedules))
        b.id: b.positions,
    },
  );

  void _update(ShiftConfig c, {bool now = false}) {
    setState(() => _c = c);
    _debounce?.cancel();
    if (now) {
      widget.onSave(_c);
    } else {
      _debounce = Timer(
        const Duration(milliseconds: 400),
        () => widget.onSave(_c),
      );
    }
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      widget.onSave(_c);
    }
    super.dispose();
  }

  void _setLayout(ShiftBoardLayout layout) {
    var c = _c.copyWith(layout: layout);
    if (layout == ShiftBoardLayout.custom && c.customBoards.isEmpty) {
      // Start with one board for every schedule, with their positions.
      final perSchedule = _c
          .copyWith(layout: ShiftBoardLayout.perSchedule)
          .boardsFor(widget.schedules);
      final seen = <String>{};
      c = c.copyWith(
        customBoards: [
          ShiftBoard(
            id: newScheduleId(),
            name: _schedules.length > 1
                ? 'All schedules'
                : _schedules.first.name,
            scheduleIds: [for (final s in _schedules) s.id],
            positions: [
              for (final b in perSchedule)
                for (final p in b.positions)
                  if (seen.add(p.id)) p,
            ],
          ),
        ],
      );
    }
    _selected = null;
    _update(c, now: true);
  }

  void _setPositions(ShiftBoard board, List<ShiftPosition> positions) {
    if (_c.layout == ShiftBoardLayout.custom) {
      _update(
        _c.copyWith(
          customBoards: [
            for (final b in _c.customBoards)
              b.id == board.id ? b.copyWith(positions: positions) : b,
          ],
        ),
      );
    } else {
      _update(
        _c.copyWith(
          scheduleBoards: {..._c.scheduleBoards, board.id: positions},
        ),
      );
    }
  }

  void _setCustom(ShiftBoard board, {String? name, List<String>? scheduleIds}) {
    _update(
      _c.copyWith(
        customBoards: [
          for (final b in _c.customBoards)
            b.id == board.id
                ? b.copyWith(name: name, scheduleIds: scheduleIds)
                : b,
        ],
      ),
      now: name == null,
    );
  }

  void _addBoard() {
    final used = {for (final b in _c.customBoards) ...b.scheduleIds};
    final free = [
      for (final s in _schedules)
        if (!used.contains(s.id)) s.id,
    ];
    final board = ShiftBoard(
      id: newScheduleId(),
      name: 'Board ${_c.customBoards.length + 1}',
      scheduleIds: free,
    );
    _selected = board.id;
    _update(_c.copyWith(customBoards: [..._c.customBoards, board]), now: true);
  }

  void _removeBoard(ShiftBoard board) {
    _selected = null;
    _update(
      _c.copyWith(
        customBoards: [
          for (final b in _c.customBoards)
            if (b.id != board.id) b,
        ],
      ),
      now: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final custom = _c.layout == ShiftBoardLayout.custom;
    final boards = _boards;
    final board = _board;
    final onBoards = {for (final b in boards) ...b.scheduleIds};
    final missing = [
      for (final s in _schedules)
        if (!onBoards.contains(s.id)) s.name,
    ];

    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: const Text('Shift board settings'),
      content: SizedBox(
        width: 560,
        height: math.min(600.0, MediaQuery.sizeOf(context).height - 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Boards',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<ShiftBoardLayout>(
              segments: const [
                ButtonSegment(
                  value: ShiftBoardLayout.perSchedule,
                  icon: Icon(Icons.view_agenda_outlined, size: 18),
                  label: Text('A board for each schedule'),
                ),
                ButtonSegment(
                  value: ShiftBoardLayout.custom,
                  icon: Icon(Icons.merge_type, size: 18),
                  label: Text('Combine schedules'),
                ),
              ],
              selected: {_c.layout},
              onSelectionChanged: (v) => _setLayout(v.first),
            ),
            const SizedBox(height: 6),
            Text(
              custom
                  ? 'Each board shows the shifts of the schedules you pick, so one '
                        'board can cover several schedules (e.g. Front of House and '
                        'Kitchen together).'
                  : 'Every schedule gets its own board with its own positions.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final b in boards)
                  ChoiceChip(
                    label: Text(b.name.isEmpty ? 'Untitled' : b.name),
                    selected: b.id == board?.id,
                    onSelected: (_) => setState(() => _selected = b.id),
                  ),
                if (custom)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Add board'),
                    onPressed: _addBoard,
                  ),
              ],
            ),
            if (custom && missing.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Not on any board: ${missing.join(', ')}.',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            const Divider(height: 24),
            if (board == null)
              Expanded(
                child: Center(
                  child: Text('No boards yet.', style: TextStyle(color: muted)),
                ),
              )
            else ...[
              if (custom) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('board-name-${board.id}'),
                        initialValue: board.name,
                        decoration: const InputDecoration(
                          labelText: 'Board name',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => _setCustom(board, name: v.trim()),
                      ),
                    ),
                    if (_c.customBoards.length > 1)
                      IconButton(
                        tooltip: 'Remove board',
                        onPressed: () => _removeBoard(board),
                        icon: const Icon(Icons.delete_outline, size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Schedules on this board',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in _schedules)
                      () {
                        final elsewhere = boards
                            .where(
                              (b) =>
                                  b.id != board.id &&
                                  b.scheduleIds.contains(s.id),
                            )
                            .firstOrNull;
                        return Tooltip(
                          message: elsewhere == null
                              ? ''
                              : 'On ${elsewhere.name}',
                          child: FilterChip(
                            label: Text(s.name),
                            selected: board.scheduleIds.contains(s.id),
                            onSelected: elsewhere != null
                                ? null
                                : (on) => _setCustom(
                                    board,
                                    scheduleIds: [
                                      for (final x in _schedules)
                                        if (x.id == s.id
                                            ? on
                                            : board.scheduleIds.contains(x.id))
                                          x.id,
                                    ],
                                  ),
                          ),
                        );
                      }(),
                  ],
                ),
                const SizedBox(height: 12),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Shows the ${board.name} schedule.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Positions on ${board.name.isEmpty ? 'this board' : board.name}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                    ),
                    onPressed: () => showShiftLayoutCustomizer(
                      context,
                      config: _c,
                      board: board,
                      schedules: widget.schedules,
                      onSave: (c) async {
                        _update(c, now: true);
                      },
                    ),
                    icon: const Icon(Icons.grid_view_rounded, size: 15),
                    label: const Text(
                      'Customize layout',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: PositionsEditor(
                  key: ValueKey('positions-${_c.layout.name}-${board.id}'),
                  positions: board.positions,
                  onChanged: (list) => _setPositions(board, list),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Text(
          'Changes save automatically',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
