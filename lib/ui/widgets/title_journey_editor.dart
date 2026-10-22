// Settings → Titles → Team member journey.
//
// Shows the journey as round title tiles joined by arrows. "Edit journey"
// opens the editor: drag tiles to move them (drop on another tile to swap),
// click a tile to pick its icon, choose which titles it leads to, nudge it,
// or take it off the journey. Nothing is saved until Save.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/store_settings_model.dart';
import '../../models/title_journey.dart';
import 'journey_widgets.dart';

export 'journey_widgets.dart';

class TitleJourneyEditor extends ConsumerStatefulWidget {
  const TitleJourneyEditor({
    super.key,
    required this.storeId,
    required this.titles,
    required this.onOrderChanged,
  });

  final String storeId;
  final List<TitleConfig> titles;

  /// Called with the titles in journey order when it changes.
  final ValueChanged<List<TitleConfig>> onOrderChanged;

  @override
  ConsumerState<TitleJourneyEditor> createState() => _TitleJourneyEditorState();
}

class _TitleJourneyEditorState extends ConsumerState<TitleJourneyEditor> {
  /// Shown right after saving, until Firestore sends the saved copy back.
  TitleJourney? _local;
  String? _hover;

  TitleJourney _journey() {
    final saved = ref.watch(titleJourneyProvider(widget.storeId)).valueOrNull;
    return _local ?? journeyFor(saved, widget.titles);
  }

  Future<void> _save(TitleJourney j) async {
    setState(() => _local = j);
    final ordered = j.orderTitles(widget.titles);
    try {
      await saveTitleJourney(widget.storeId, j);
      final same =
          ordered.length == widget.titles.length &&
          [
            for (var i = 0; i < ordered.length; i++)
              ordered[i].id == widget.titles[i].id,
          ].every((b) => b);
      if (!same) widget.onOrderChanged(ordered);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t save the journey. Please try again.'),
          ),
        );
      }
    }
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _local = null);
    });
  }

  Future<void> _openEditor({String? select}) async {
    final result = await showDialog<TitleJourney>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _JourneyEditDialog(
        journey: _journey(),
        titles: widget.titles,
        initialSelection: select,
      ),
    );
    if (result != null) await _save(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.textTheme.bodySmall?.color;
    final j = _journey();
    final offJourney = widget.titles
        .where((t) => !j.nodes.containsKey(t.id))
        .toList();
    final start = j.start;

    final editButton = FilledButton.icon(
      onPressed: () => _openEditor(),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.edit_rounded, size: 17),
      label: const Text(
        'Edit journey',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    final heading = Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.tint(AppTheme.accent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.route_rounded,
            size: 20,
            color: AppTheme.onTint(AppTheme.accent),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Team member journey',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Where new hires start and how they move up. Promote suggests the next titles.',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
            ],
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Button beside the heading, or under it when the card is narrow
        // (All Stores puts each store's settings side by side).
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 480
              ? Row(
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 12),
                    editButton,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [heading, const SizedBox(height: 12), editButton],
                ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: dark ? 0.5 : 0.7),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: j.nodes.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(36),
                  child: Center(
                    child: Text(
                      'No titles on the journey yet. Click Edit journey to add them.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: JourneyMapView(
                      journey: j,
                      titles: widget.titles,
                      minWidth: box.maxWidth,
                      hoveredId: _hover,
                      onHover: (id) => setState(() => _hover = id),
                      onTap: (id) => _openEditor(select: id),
                      captionFor: (id) => 'Step ${j.stepOf(id)}',
                      badgeFor: (id) => id == start
                          ? JourneyBadge(
                              'NEW HIRES',
                              color: AppTheme.green,
                              icon: Icons.star_rounded,
                            )
                          : null,
                    ),
                  ),
                ),
        ),
        if (offJourney.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Not on the journey: ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: offJourney
                      .map((t) => t.name.isEmpty ? 'Untitled' : t.name)
                      .join(', '),
                ),
              ],
            ),
            style: TextStyle(fontSize: 12.5, color: muted),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// The editor
// =============================================================================

class _JourneyEditDialog extends StatefulWidget {
  const _JourneyEditDialog({
    required this.journey,
    required this.titles,
    this.initialSelection,
  });

  final TitleJourney journey;
  final List<TitleConfig> titles;
  final String? initialSelection;

  @override
  State<_JourneyEditDialog> createState() => _JourneyEditDialogState();
}

class _JourneyEditDialogState extends State<_JourneyEditDialog> {
  static const _layout = JourneyLayout(
    cellW: 160,
    cellH: 172,
    circle: 76,
    top: 26,
  );

  late TitleJourney _j = widget.journey;
  late String? _selected = widget.initialSelection;
  bool _changed = false;
  String? _hover;
  JourneyCell? _dropCell;
  String? _dragging;
  final ScrollController _canvasHController = ScrollController();
  final ScrollController _canvasVController = ScrollController();

  @override
  void dispose() {
    _canvasHController.dispose();
    _canvasVController.dispose();
    super.dispose();
  }

  Map<String, TitleConfig> get _byId => {
    for (final t in widget.titles) t.id: t,
  };

  void _update(TitleJourney j) => setState(() {
    _j = j.copyWith(nodes: _compact(j.nodes));
    _changed = true;
  });

  /// Moves everything so the top-left title sits in the first column / row.
  Map<String, JourneyCell> _compact(Map<String, JourneyCell> nodes) {
    if (nodes.isEmpty) return nodes;
    final minX = nodes.values.map((c) => c.x).reduce(math.min);
    final minY = nodes.values.map((c) => c.y).reduce(math.min);
    if (minX == 0 && minY == 0) return nodes;
    return {
      for (final e in nodes.entries)
        e.key: JourneyCell(e.value.x - minX, e.value.y - minY),
    };
  }

  /// Puts [id] in [cell]; whoever was there takes [id]'s old spot.
  void _place(String id, JourneyCell cell) {
    final nodes = {..._j.nodes};
    final old = nodes[id];
    final other = _j.titleAt(cell);
    if (other == id) return;
    if (other != null) {
      if (old != null) {
        nodes[other] = old;
      } else {
        var y = cell.y + 1;
        while (_j.titleAt(JourneyCell(cell.x, y)) != null) {
          y++;
        }
        nodes[other] = JourneyCell(cell.x, y);
      }
    }
    nodes[id] = cell;
    _update(_j.copyWith(nodes: nodes));
  }

  void _nudge(String id, int dx, int dy) {
    final c = _j.nodes[id];
    if (c == null) return;
    final to = JourneyCell(c.x + dx, c.y + dy);
    if (to.x < 0 || to.y < 0) {
      // Make room on the left / top by shifting everyone else.
      final nodes = {
        for (final e in _j.nodes.entries)
          e.key: e.key == id
              ? JourneyCell(math.max(0, to.x), math.max(0, to.y))
              : JourneyCell(
                  e.value.x + (to.x < 0 ? 1 : 0),
                  e.value.y + (to.y < 0 ? 1 : 0),
                ),
      };
      _update(_j.copyWith(nodes: nodes));
      return;
    }
    _place(id, to);
  }

  void _addToJourney(String id) {
    // Next free spot after the last column, on the top row if possible.
    final x = _j.columns;
    var y = 0;
    while (_j.titleAt(JourneyCell(x, y)) != null) {
      y++;
    }
    final nodes = {..._j.nodes, id: JourneyCell(x, y)};
    // Connect it after the last title on the top row, so it's on a path.
    final links = [..._j.links];
    final prev = _j.nodes.entries
        .where((e) => e.value.y == 0 && e.value.x == x - 1)
        .firstOrNull
        ?.key;
    if (prev != null && !_j.wouldLoop(prev, id))
      links.add(JourneyLink(prev, id));
    _update(_j.copyWith(nodes: nodes, links: links));
    setState(() => _selected = id);
  }

  void _remove(String id) {
    _update(
      _j.copyWith(
        nodes: {..._j.nodes}..remove(id),
        links: [
          for (final l in _j.links)
            if (l.from != id && l.to != id) l,
        ],
      ),
    );
    setState(() => _selected = null);
  }

  void _toggleLink(String from, String to, bool on) {
    final links = [
      for (final l in _j.links)
        if (!(l.from == from && l.to == to)) l,
    ];
    if (on) links.add(JourneyLink(from, to));
    _update(_j.copyWith(links: links));
  }

  void _setIcon(String id, String key) =>
      _update(_j.copyWith(icons: {..._j.icons, id: key}));

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start over as a straight line?'),
        content: const Text(
          'Every title goes back into one line in the current title order. Icons stay the same.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _update(
        TitleJourney.fromTitleOrder(widget.titles).copyWith(icons: _j.icons),
      );
    }
  }

  Future<void> _cancel() async {
    if (!_changed) {
      Navigator.pop(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard your changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: theme.cardColor,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(1220, size.width - 48),
        height: math.min(780, size.height - 48),
        child: Column(
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
              child: Row(
                children: [
                  Icon(Icons.route_rounded, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Edit team member journey',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reset to a straight line'),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _cancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _canvas(context, dark, muted)),
                  Container(width: 1, color: theme.dividerColor),
                  SizedBox(width: 330, child: _panel(context, muted)),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            // Footer.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 20, 14),
              child: Row(
                children: [
                  Icon(Icons.pan_tool_alt_outlined, size: 16, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Drag a title to move it (drop it on another to swap). Click one to change its icon and where it leads.',
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ),
                  TextButton(onPressed: _cancel, child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _j),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                    ),
                    child: const Text(
                      'Save journey',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Canvas: tiles on a grid; empty spots show as dashed rings while dragging.
  // ---------------------------------------------------------------------------

  Widget _canvas(BuildContext context, bool dark, Color muted) {
    final l = _layout;
    final j = _j;
    final byId = _byId;
    final cols = math.max(j.columns + 1, 4);
    final rows = math.max(j.rows + 1, 3);
    final canvas = l.size(cols, rows);
    final start = j.start;

    final routes = <JourneyRoute>[];
    final highlighted = <int>{};
    for (final (link, route) in routeJourney(j, l)) {
      if (link.from == _selected) highlighted.add(routes.length);
      routes.add(route);
    }
    final empty = <Offset>[
      for (var x = 0; x < cols; x++)
        for (var y = 0; y < rows; y++)
          if (j.titleAt(JourneyCell(x, y)) == null ||
              j.titleAt(JourneyCell(x, y)) == _dragging)
            l.center(JourneyCell(x, y)),
    ];
    final selColor = _selected != null && byId[_selected] != null
        ? journeyTitleColor(byId[_selected]!)
        : null;

    return Container(
      color: Theme.of(context).cardColor,
      child: Scrollbar(
        controller: _canvasHController,
        child: SingleChildScrollView(
          controller: _canvasHController,
          scrollDirection: Axis.horizontal,
          child: Scrollbar(
            controller: _canvasVController,
            notificationPredicate: (notif) =>
                notif.metrics.axis == Axis.vertical,
            child: SingleChildScrollView(
              controller: _canvasVController,
              scrollDirection: Axis.vertical,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _selected = null),
                child: SizedBox(
                  width: canvas.width + 40,
                  height: canvas.height + 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Step labels.
                    for (var x = 0; x < cols; x++)
                      Positioned(
                        left: l.pad + x * l.cellW,
                        width: l.cellW,
                        top: 10,
                        child: Text(
                          'STEP ${x + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: muted.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: JourneyPainter(
                          routes: routes,
                          arrowColor: muted,
                          highlighted: highlighted,
                          highlightColor: selColor,
                          slots: _dragging == null ? const [] : empty,
                          slotColor: muted.withValues(alpha: 0.45),
                          slotRadius: l.circle / 2,
                          activeSlot: _dropCell == null
                              ? null
                              : l.center(_dropCell!),
                          activeColor: AppTheme.accent,
                        ),
                      ),
                    ),
                    // Drop spots (every cell).
                    for (var x = 0; x < cols; x++)
                      for (var y = 0; y < rows; y++)
                        Positioned(
                          left: l.pad + x * l.cellW,
                          top: l.pad + l.top + y * l.cellH,
                          width: l.cellW,
                          height: l.cellH,
                          child: DragTarget<String>(
                            onWillAcceptWithDetails: (d) {
                              setState(() => _dropCell = JourneyCell(x, y));
                              return true;
                            },
                            onLeave: (_) => setState(() {
                              if (_dropCell == JourneyCell(x, y))
                                _dropCell = null;
                            }),
                            onAcceptWithDetails: (d) {
                              setState(() {
                                _dropCell = null;
                                _selected = d.data;
                              });
                              _place(d.data, JourneyCell(x, y));
                            },
                            builder: (_, _, _) => const SizedBox.expand(),
                          ),
                        ),
                    // Tiles.
                    for (final e in j.nodes.entries)
                      if (byId[e.key] case final t?)
                        _tile(t, e.value, t.id == start, muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _tile(TitleConfig t, JourneyCell cell, bool isStart, Color muted) {
    final l = _layout;
    final c = l.center(cell);
    final labelW = l.labelW;
    final outer = l.outer;
    final color = journeyTitleColor(t);
    final icon = journeyIconFor(t, _j);
    final selected = _selected == t.id;

    Widget circle({bool lifted = false}) => JourneyCircle(
      color: color,
      icon: icon,
      size: l.circle,
      selected: selected && !lifted,
      hovered: _hover == t.id || lifted,
    );

    return Positioned(
      left: c.dx - labelW / 2,
      top: c.dy - outer / 2,
      width: labelW,
      child: IgnorePointer(
        // Let drops land on the cell under a tile while dragging.
        ignoring: _dragging != null,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          onEnter: (_) => setState(() => _hover = t.id),
          onExit: (_) => setState(() {
            if (_hover == t.id) _hover = null;
          }),
          child: Draggable<String>(
            data: t.id,
            onDragStarted: () => setState(() {
              _dragging = t.id;
              _selected = t.id;
            }),
            onDragEnd: (_) => setState(() {
              _dragging = null;
              _dropCell = null;
            }),
            feedback: Material(
              color: Colors.transparent,
              child: circle(lifted: true),
            ),
            childWhenDragging: Opacity(
              opacity: 0.25,
              child: _tileBody(t, circle(), isStart, muted),
            ),
            child: GestureDetector(
              onTap: () => setState(() => _selected = t.id),
              child: _tileBody(t, circle(), isStart, muted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tileBody(TitleConfig t, Widget circle, bool isStart, Color muted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            circle,
            if (isStart)
              Positioned(
                top: -6,
                child: JourneyBadge(
                  'NEW HIRES',
                  color: AppTheme.green,
                  icon: Icons.star_rounded,
                ),
              ),
          ],
        ),
        Transform.translate(
          offset: Offset(0, -_layout.circle * 0.2),
          child: JourneyNameplate(
            name: t.name,
            color: journeyTitleColor(t),
            selected: _selected == t.id,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Side panel: the selected title, or what's not on the journey.
  // ---------------------------------------------------------------------------

  Widget _panel(BuildContext context, Color muted) {
    final byId = _byId;
    final t = _selected == null ? null : byId[_selected];
    final off = widget.titles
        .where((x) => !_j.nodes.containsKey(x.id))
        .toList();

    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(
        s,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: muted,
        ),
      ),
    );

    if (t == null || !_j.nodes.containsKey(t.id)) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        children: [
          Icon(Icons.touch_app_outlined, size: 30, color: muted),
          const SizedBox(height: 10),
          const Text(
            'Pick a title',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Click a title on the left to choose its icon, set which titles it leads to, or move it.',
            style: TextStyle(fontSize: 13, color: muted, height: 1.4),
          ),
          if (off.isNotEmpty) ...[
            label('NOT ON THE JOURNEY'),
            for (final x in off)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OffJourneyRow(
                  title: x,
                  icon: journeyIconFor(x, _j),
                  onAdd: () => _addToJourney(x.id),
                ),
              ),
          ],
        ],
      );
    }

    final color = journeyTitleColor(t);
    final cell = _j.nodes[t.id]!;
    final next = _j.next(t.id).toSet();
    final currentKey = _j.icons[t.id] ?? journeyDefaultIconKey(t.name);
    final others =
        [
          for (final x in widget.titles)
            if (x.id != t.id && _j.nodes.containsKey(x.id)) x,
        ]..sort((a, b) {
          final ca = _j.nodes[a.id]!, cb = _j.nodes[b.id]!;
          return ca.x != cb.x ? ca.x.compareTo(cb.x) : ca.y.compareTo(cb.y);
        });

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      children: [
        Row(
          children: [
            JourneyCircle(color: color, icon: journeyIconFor(t, _j), size: 56),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name.isEmpty ? 'Untitled' : t.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Step ${cell.x + 1}${cell.y > 0 ? ' · row ${cell.y + 1}' : ''}',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),

        label('ICON'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (key, name, icon) in kJourneyIcons)
              Tooltip(
                message: name,
                waitDuration: const Duration(milliseconds: 400),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _setIcon(t.id, key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: key == currentKey
                          ? color
                          : color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: key == currentKey
                            ? color
                            : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 21,
                      color: key == currentKey
                          ? Colors.white
                          : AppTheme.onTint(color),
                    ),
                  ),
                ),
              ),
          ],
        ),

        label('LEADS TO'),
        if (others.isEmpty)
          Text(
            'Add more titles to the journey first.',
            style: TextStyle(fontSize: 13, color: muted),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final x in others)
                Builder(
                  builder: (context) {
                    final on = next.contains(x.id);
                    final loop = !on && _j.wouldLoop(t.id, x.id);
                    final xc = journeyTitleColor(x);
                    final chip = FilterChip(
                      selected: on,
                      showCheckmark: false,
                      avatar: Icon(
                        journeyIconFor(x, _j),
                        size: 16,
                        color: on ? Colors.white : AppTheme.onTint(xc),
                      ),
                      label: Text(x.name.isEmpty ? 'Untitled' : x.name),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: on ? Colors.white : null,
                      ),
                      selectedColor: xc,
                      side: BorderSide(
                        color: on ? xc : Theme.of(context).dividerColor,
                      ),
                      onSelected: loop
                          ? null
                          : (v) => _toggleLink(t.id, x.id, v),
                    );
                    return loop
                        ? Tooltip(
                            message:
                                '${x.name} already leads here, so this would make a loop.',
                            child: chip,
                          )
                        : chip;
                  },
                ),
            ],
          ),

        label('MOVE'),
        Row(
          children: [
            _NudgeButton(
              icon: Icons.west_rounded,
              tip: 'Earlier step',
              onTap: () => _nudge(t.id, -1, 0),
            ),
            const SizedBox(width: 6),
            _NudgeButton(
              icon: Icons.east_rounded,
              tip: 'Later step',
              onTap: () => _nudge(t.id, 1, 0),
            ),
            const SizedBox(width: 6),
            _NudgeButton(
              icon: Icons.north_rounded,
              tip: 'Up a row',
              onTap: () => _nudge(t.id, 0, -1),
            ),
            const SizedBox(width: 6),
            _NudgeButton(
              icon: Icons.south_rounded,
              tip: 'Down a row',
              onTap: () => _nudge(t.id, 0, 1),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _remove(t.id),
            style: TextButton.styleFrom(foregroundColor: AppTheme.red),
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('Take off the journey'),
          ),
        ),
        if (off.isNotEmpty) ...[
          label('NOT ON THE JOURNEY'),
          for (final x in off)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _OffJourneyRow(
                title: x,
                icon: journeyIconFor(x, _j),
                onAdd: () => _addToJourney(x.id),
              ),
            ),
        ],
      ],
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({
    required this.icon,
    required this.tip,
    required this.onTap,
  });
  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(46, 40),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Icon(icon, size: 18),
    ),
  );
}

class _OffJourneyRow extends StatelessWidget {
  const _OffJourneyRow({
    required this.title,
    required this.icon,
    required this.onAdd,
  });
  final TitleConfig title;
  final IconData icon;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final color = journeyTitleColor(title);
    return Row(
      children: [
        JourneyCircle(
          color: color,
          icon: icon,
          size: 30,
          look: JourneyLook.faded,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title.name.isEmpty ? 'Untitled' : title.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add'),
        ),
      ],
    );
  }
}
