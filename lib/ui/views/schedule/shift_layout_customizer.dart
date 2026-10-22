import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';

/// Painter for the 50px grid lines, matching the dashboard page layout customizer.
class ShiftGridPainter extends CustomPainter {
  final double gridSize;
  final Color? color;
  const ShiftGridPainter({this.gridSize = 50.0, this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color ?? Colors.grey.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += gridSize) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += gridSize) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dialog to customize where position tiles appear on the shift board via a visual grid,
/// similar to the dashboard page customization.
Future<void> showShiftLayoutCustomizer(
  BuildContext context, {
  required ShiftConfig config,
  required ShiftBoard board,
  required ScheduleConfig schedules,
  required Future<void> Function(ShiftConfig) onSave,
}) => showDialog<void>(
  context: context,
  builder: (_) => ShiftLayoutCustomizerDialog(
    config: config,
    board: board,
    schedules: schedules,
    onSave: onSave,
  ),
);

class ShiftLayoutCustomizerDialog extends StatefulWidget {
  final ShiftConfig config;
  final ShiftBoard board;
  final ScheduleConfig schedules;
  final Future<void> Function(ShiftConfig) onSave;

  const ShiftLayoutCustomizerDialog({
    super.key,
    required this.config,
    required this.board,
    required this.schedules,
    required this.onSave,
  });

  @override
  State<ShiftLayoutCustomizerDialog> createState() =>
      _ShiftLayoutCustomizerDialogState();
}

class _ShiftLayoutCustomizerDialogState
    extends State<ShiftLayoutCustomizerDialog> {
  static const double gridSize = 50.0;
  static const double tileWidth = 200.0;
  static const double tileHeight = 50.0;

  static double snap(double v) => (v / gridSize).roundToDouble() * gridSize;

  late ShiftBoard _currentBoard = widget.board;
  late List<ShiftPosition> _positions;
  late List<ShiftPosition> _originalPositions;
  String? _selectedId;
  bool _saving = false;

  List<ShiftBoard> get _boards => widget.config.boardsFor(widget.schedules);

  @override
  void initState() {
    super.initState();
    _loadPositionsForBoard(_currentBoard);
  }

  void _loadPositionsForBoard(ShiftBoard board) {
    _currentBoard = board;
    _positions = [
      for (var i = 0; i < board.positions.length; i++)
        board.positions[i].copyWith(
          x: snap(board.positions[i].x ?? (50.0 + (i % 4) * 250.0)),
          y: snap(board.positions[i].y ?? (50.0 + (i ~/ 4) * 100.0)),
        ),
    ];
    _originalPositions = [for (final p in _positions) p.copyWith()];
  }

  void _autoArrange() {
    setState(() {
      const cols = 4;
      for (var i = 0; i < _positions.length; i++) {
        final col = i % cols;
        final row = i ~/ cols;
        _positions[i] = _positions[i].copyWith(
          x: 50.0 + col * 250.0,
          y: 50.0 + row * 100.0,
        );
      }
    });
  }

  void _reset() {
    setState(() {
      _positions = [for (final p in _originalPositions) p.copyWith()];
    });
  }

  Offset? _dragStartPos;
  bool _hasDragged = false;

  void _onPanStart(String id) {
    final idx = _positions.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      _hasDragged = false;
      _dragStartPos = Offset(
        _positions[idx].x ?? 0.0,
        _positions[idx].y ?? 0.0,
      );
      setState(() => _selectedId = id);
    }
  }

  void _onPanEnd(String id) {
    final idx = _positions.indexWhere((p) => p.id == id);
    if (idx >= 0 && _dragStartPos != null) {
      if (!_hasDragged) {
        // User merely clicked/tapped the tile; keep its position completely unchanged.
        setState(() {
          _selectedId = null;
          _dragStartPos = null;
        });
        return;
      }

      final current = _positions[idx];
      final snappedX = snap(math.max(0.0, current.x ?? 0.0));
      final snappedY = snap(math.max(0.0, current.y ?? 0.0));

      // Check if it overlaps any other tile at the snapped coordinates
      final overlapsOther = _positions.any((other) {
        if (other.id == id) return false;
        final ox = other.x ?? 0.0;
        final oy = other.y ?? 0.0;
        return (snappedX < ox + tileWidth &&
            snappedX + tileWidth > ox &&
            snappedY < oy + tileHeight &&
            snappedY + tileHeight > oy);
      });

      setState(() {
        if (overlapsOther) {
          // Revert to start position so tiles never sit on top of each other
          _positions[idx] = current.copyWith(
            x: _dragStartPos!.dx,
            y: _dragStartPos!.dy,
          );
        } else {
          _positions[idx] = current.copyWith(x: snappedX, y: snappedY);
        }
        _selectedId = null;
        _dragStartPos = null;
      });
    } else {
      setState(() {
        _selectedId = null;
        _dragStartPos = null;
      });
    }
  }

  void _updatePosition(String id, double dx, double dy) {
    final idx = _positions.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _hasDragged = true;
    setState(() {
      final cur = _positions[idx];
      final newX = math.max(0.0, (cur.x ?? 0.0) + dx);
      final newY = math.max(0.0, (cur.y ?? 0.0) + dy);
      _positions[idx] = cur.copyWith(x: newX, y: newY);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    ShiftConfig newConfig;
    if (widget.config.layout == ShiftBoardLayout.custom) {
      newConfig = widget.config.copyWith(
        customBoards: [
          for (final b in widget.config.customBoards)
            b.id == _currentBoard.id ? b.copyWith(positions: _positions) : b,
        ],
      );
    } else {
      newConfig = widget.config.copyWith(
        scheduleBoards: {
          ...widget.config.scheduleBoards,
          _currentBoard.id: _positions,
        },
      );
    }

    try {
      await widget.onSave(newConfig);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved layout for ${_currentBoard.name.isEmpty ? 'shift board' : _currentBoard.name}.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t save layout. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;

    double maxX = 1200.0;
    double maxY = 800.0;
    for (final p in _positions) {
      if ((p.x ?? 0) + tileWidth + 100 > maxX) {
        maxX = (p.x ?? 0) + tileWidth + 100;
      }
      if ((p.y ?? 0) + tileHeight + 100 > maxY) {
        maxY = (p.y ?? 0) + tileHeight + 100;
      }
    }

    return Dialog(
      backgroundColor: theme.cardColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dialogWidth = math.min(1100.0, constraints.maxWidth);
          final dialogHeight = math.min(750.0, constraints.maxHeight);
          return Container(
            width: dialogWidth,
            height: dialogHeight,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.grid_view_rounded,
                      color: AppTheme.accent2,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customize Tile Layout — ${_currentBoard.name.isEmpty ? 'Shift Board' : _currentBoard.name}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.titleLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Drag position tiles to rearrange their layout. Tiles snap to the 50px grid.',
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                    ),
                    if (_boards.length > 1) ...[
                      DropdownButton<String>(
                        value: _currentBoard.id,
                        underline: const SizedBox.shrink(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                        items: [
                          for (final b in _boards)
                            DropdownMenuItem(
                              value: b.id,
                              child: Text(b.name.isEmpty ? 'Untitled' : b.name),
                            ),
                        ],
                        onChanged: (id) {
                          if (id == null) return;
                          final target = _boards
                              .where((b) => b.id == id)
                              .firstOrNull;
                          if (target != null) {
                            setState(() => _loadPositionsForBoard(target));
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _autoArrange,
                      icon: const Icon(
                        Icons.auto_awesome_mosaic_outlined,
                        size: 16,
                      ),
                      label: const Text('Auto-arrange'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(onPressed: _reset, child: const Text('Reset')),
                  ],
                ),
                const SizedBox(height: 14),
                // Grid Canvas
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: _positions.isEmpty
                        ? Center(
                            child: Text(
                              'No positions on this board yet. Add positions in Shift board settings.',
                              style: TextStyle(color: muted),
                            ),
                          )
                        : Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: SizedBox(
                                  width: maxX,
                                  height: maxY,
                                  child: Stack(
                                    children: [
                                      // Grid Background
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          size: Size(maxX, maxY),
                                          painter: ShiftGridPainter(
                                            gridSize: gridSize,
                                            color: theme.dividerColor
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                      ),
                                      // Movable Position Tiles
                                      for (
                                        var i = 0;
                                        i < _positions.length;
                                        i++
                                      )
                                        _buildMovableTile(i, theme, muted),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                // Bottom Action Bar
                Row(
                  children: [
                    Text(
                      '${_positions.length} position tiles · Drag to position',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 16),
                      label: const Text('Save Layout'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMovableTile(int i, ThemeData theme, Color? muted) {
    final p = _positions[i];
    final isSelected = _selectedId == p.id;
    final x = p.x ?? 0.0;
    final y = p.y ?? 0.0;

    return Positioned(
      key: ValueKey(p.id),
      left: x,
      top: y,
      width: tileWidth,
      height: tileHeight,
      child: RepaintBoundary(
        child: GestureDetector(
          onPanStart: (_) => _onPanStart(p.id),
          onPanUpdate: (d) => _updatePosition(p.id, d.delta.dx, d.delta.dy),
          onPanEnd: (_) => _onPanEnd(p.id),
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.accent.withValues(alpha: 0.15)
                    : theme.cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppTheme.accent : theme.dividerColor,
                  width: isSelected ? 2 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? AppTheme.accent.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.08),
                    blurRadius: isSelected ? 10 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator,
                    size: 16,
                    color: isSelected ? AppTheme.accent : muted,
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.tint(AppTheme.accent2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#${i + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.onTint(AppTheme.accent2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.name.isEmpty ? 'Untitled' : p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${x.toInt()},${y.toInt()}',
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
