// Home → "Your journey": your title big and front and center, then the whole
// journey (set up on the website: Settings → Titles) to scroll through,
// drawn the same way as on the website.

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/store_settings_model.dart';
import '../../models/title_journey.dart';
import '../../providers/app_providers.dart';
import '../widgets/journey_widgets.dart';
import 'mobile_ui.dart';

const _map = JourneyLayout(
  cellW: 118,
  cellH: 148,
  circle: 58,
  pad: 14,
  top: 12,
  gutter: 24,
);

/// Steps from [from] to every title ahead of it (fewest arrows).
Map<String, int> _stepsAhead(TitleJourney j, String from) {
  final steps = <String, int>{from: 0};
  final queue = Queue<String>()..add(from);
  while (queue.isNotEmpty) {
    final t = queue.removeFirst();
    for (final n in j.next(t)) {
      if (!steps.containsKey(n)) {
        steps[n] = steps[t]! + 1;
        queue.add(n);
      }
    }
  }
  return steps..remove(from);
}

class MyJourneySection extends ConsumerStatefulWidget {
  const MyJourneySection({
    super.key,
    required this.storeId,
    required this.title,
  });
  final String storeId;

  /// The title shown for them right now.
  final String? title;

  @override
  ConsumerState<MyJourneySection> createState() => _MyJourneySectionState();
}

class _MyJourneySectionState extends ConsumerState<MyJourneySection>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat();
  String? _selected;
  String? _scrolledTo;

  @override
  void dispose() {
    _scroll.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Brings your tile into view in the map (once per title).
  void _scrollToCurrent(String id, double x, double viewport) {
    if (_scrolledTo == id) return;
    _scrolledTo = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (x - viewport / 2).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final titles =
        ref.watch(storeSettingsProvider).valueOrNull?.titles ??
        const <TitleConfig>[];
    final saved = ref.watch(titleJourneyProvider(widget.storeId));
    if (titles.isEmpty || saved.isLoading && !saved.hasValue)
      return const SizedBox.shrink();
    final j = journeyFor(saved.valueOrNull, titles);
    final byId = {for (final t in titles) t.id: t};
    final currentId = titles
        .where((t) => t.name == widget.title)
        .firstOrNull
        ?.id;
    if (currentId == null ||
        !j.nodes.containsKey(currentId) ||
        j.nodes.length < 2) {
      return const SizedBox.shrink();
    }

    final current = byId[currentId]!;
    final color = journeyTitleColor(current);
    final behind = j.behind(currentId);
    final ahead = _stepsAhead(j, currentId);
    final nextIds = j.next(currentId);
    final step = j.stepOf(currentId);
    final total = math.max(j.longestPath, step);

    JourneyLook look(String id) => id == currentId
        ? JourneyLook.current
        : behind.contains(id)
        ? JourneyLook.done
        : ahead.containsKey(id)
        ? JourneyLook.normal
        : JourneyLook.faded;

    String names(List<String> ids) {
      final n = [
        for (final id in ids) byId[id]?.name ?? '',
      ].where((s) => s.isNotEmpty).toList();
      if (n.length <= 1) return n.join();
      return '${n.sublist(0, n.length - 1).join(', ')} or ${n.last}';
    }

    // The line under the map for a tapped tile.
    final focus = _selected ?? currentId;
    final String headline;
    final String detail;
    if (focus == currentId) {
      headline = nextIds.isEmpty
          ? 'You\'re at the top of the journey'
          : 'Next up: ${names(nextIds)}';
      detail = nextIds.isEmpty
          ? 'Keep leading the way.'
          : 'Tap any title to see how far it is.';
    } else if (behind.contains(focus)) {
      headline = byId[focus]?.name ?? '';
      detail = 'Done. You\'ve already moved past this one.';
    } else if (ahead[focus] case final n?) {
      headline = byId[focus]?.name ?? '';
      detail = n == 1 ? 'Your next step.' : '$n steps from where you are now.';
    } else {
      headline = byId[focus]?.name ?? '';
      detail = 'On a different path from yours.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MSection('Your journey'),

        // You, big: your bubble with its nameplate, and how far along you are.
        MCard(
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              // Your title's color washing in from the left, crossed by a few
              // hard lines.
              Positioned.fill(
                child: CustomPaint(painter: _YouAreHerePainter(color)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 18, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (_, _) => JourneyCircle(
                              color: color,
                              icon: journeyIconFor(current, j),
                              size: 96,
                              look: JourneyLook.current,
                              pulse: _pulse.value,
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(0, -14),
                            child: JourneyNameplate(
                              name: current.name,
                              color: color,
                              look: JourneyLook.current,
                              large: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOU ARE HERE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: AppTheme.onTint(color),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Step $step',
                                  style: TextStyle(
                                    fontSize: 32,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                    color: c.title,
                                  ),
                                ),
                                TextSpan(
                                  text: ' / $total',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: c.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // One block per step, filled up to you.
                          Row(
                            children: [
                              for (var i = 1; i <= total; i++)
                                Expanded(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin: EdgeInsets.only(
                                      right: i == total ? 0 : 4,
                                    ),
                                    height: i == step ? 10 : 6,
                                    decoration: BoxDecoration(
                                      color: i <= step ? color : c.raised,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (nextIds.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              'NEXT UP',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                                color: c.muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              names(nextIds),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: c.title,
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 14),
                            Text(
                              'Top of the journey',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: c.title,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // The whole journey.
        const SizedBox(height: 12),
        MCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Text(
                      'THE WHOLE JOURNEY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: c.muted,
                      ),
                    ),
                    const Spacer(),
                    if (ahead.isNotEmpty)
                      Text(
                        '${ahead.length} ${ahead.length == 1 ? 'title' : 'titles'} ahead',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.muted,
                        ),
                      ),
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (context, box) {
                  final natural = _map.size(math.max(j.columns, 1), 1).width;
                  final shift = math.max(0.0, (box.maxWidth - natural) / 2);
                  _scrollToCurrent(
                    currentId,
                    _map.center(j.nodes[currentId]!).dx + shift,
                    box.maxWidth,
                  );
                  return SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(top: 6),
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, _) => JourneyMapView(
                        journey: j,
                        titles: titles,
                        layout: _map,
                        minWidth: box.maxWidth,
                        lookFor: look,
                        selectedId: _selected,
                        highlightFrom: currentId,
                        pulse: _pulse.value,
                        badgeFor: (id) => id == currentId
                            ? JourneyBadge('YOU', color: color)
                            : null,
                        captionFor: (id) {
                          if (id == currentId) return 'You';
                          if (behind.contains(id)) return 'Done';
                          final n = ahead[id];
                          return n == null ? null : '+$n';
                        },
                        onTap: (id) => setState(
                          () => _selected = _selected == id ? null : id,
                        ),
                      ),
                    ),
                  );
                },
              ),
              Divider(height: 1, color: c.line.withValues(alpha: 0.6)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Padding(
                  key: ValueKey(headline + detail),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    children: [
                      if (byId[focus] case final f?)
                        JourneyCircle(
                          color: journeyTitleColor(f),
                          icon: journeyIconFor(f, j),
                          size: 30,
                          look: look(f.id) == JourneyLook.current
                              ? JourneyLook.normal
                              : look(f.id),
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              headline,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: c.title,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              style: TextStyle(fontSize: 12.5, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Behind "You are here": your title's color washing in from the left and
/// three hard diagonal lines in it.
class _YouAreHerePainter extends CustomPainter {
  _YouAreHerePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0.26), color.withValues(alpha: 0)],
          stops: const [0, 0.65],
        ).createShader(rect),
    );
    final line = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..strokeWidth = 1.2;
    for (final x in [0.62, 0.74, 0.86]) {
      canvas.drawLine(
        Offset(size.width * x, size.height),
        Offset(size.width * x + size.height * 0.7, 0),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _YouAreHerePainter old) => old.color != color;
}
