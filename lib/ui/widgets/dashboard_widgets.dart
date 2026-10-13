import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../core/theme/app_theme.dart';

class DashboardCard extends StatefulWidget {
  final String title;
  final Widget child;
  final IconData? icon;
  final Color? iconColor;

  const DashboardCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.iconColor,
  });

  @override
  State<DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<DashboardCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => true, // Stop bubbling
        child: Scrollbar(
          controller: _scrollController,
          child: Listener(
            onPointerSignal: (PointerSignalEvent event) {
              if (event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(
                  event,
                  (PointerSignalEvent e) {},
                );
              }
            },
            child: ListView(
              controller: _scrollController,
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: [
                Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: 16,
                        color:
                            widget.iconColor ??
                            Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                widget.child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SimpleBarChart extends StatelessWidget {
  final List<BarChartItem> items;
  final int total;

  const SimpleBarChart({super.key, required this.items, required this.total});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items.map((item) {
        double pct = total == 0 ? 0.0 : item.count / total;
        if (pct > 1.0) pct = 1.0;
        if (pct < 0.0) pct = 0.0;

        final valueText =
            item.customValueLabel ??
            '${item.count} (${(pct * 100).toStringAsFixed(0)}%)';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: Text(
                      valueText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: pct,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: item.color ?? AppTheme.primaryRed,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Distinct colors for charts whose items don't carry their own color.
final List<Color> _chartPalette = [
  AppTheme.lightBlue,
  AppTheme.red,
  AppTheme.yellow,
  AppTheme.green,
  AppTheme.purple,
  AppTheme.orange,
  AppTheme.teal,
  AppTheme.darkBlue,
];

Color _chartColor(BarChartItem item, int index) =>
    item.color ?? _chartPalette[index % _chartPalette.length];

class VerticalBarChart extends StatelessWidget {
  final List<BarChartItem> items;
  final int total;

  const VerticalBarChart({super.key, required this.items, required this.total});

  static const double _chartHeight = 150;

  @override
  Widget build(BuildContext context) {
    if (total == 0 || items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final track = theme.dividerColor.withValues(alpha: 0.45);
    final maxCount = math.max(1, items.map((e) => e.count).reduce(math.max));

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final item in items)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final barWidth = math.min(c.maxWidth, 40.0);
                          final pct = item.count / total;
                          // leave room for the value label above the bar
                          final usable = c.maxHeight - 40;
                          final target = usable * (item.count / maxCount);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                item.customValueLabel ?? '${item.count}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                              ),
                              Text(
                                '${(pct * 100).toStringAsFixed(0)}%',
                                style: TextStyle(fontSize: 10, color: muted),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: barWidth,
                                height: usable,
                                alignment: Alignment.bottomCenter,
                                decoration: BoxDecoration(
                                  color: track,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: target),
                                  duration: const Duration(milliseconds: 450),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, h, _) => Container(
                                    width: barWidth,
                                    height: h,
                                    decoration: BoxDecoration(
                                      color: item.color ?? AppTheme.primaryRed,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: item.label,
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class BarChartItem {
  final String label;
  final int count;
  final String? customValueLabel;
  final Color? color;

  BarChartItem(this.label, this.count, {this.customValueLabel, this.color});
}

class SimplePieChart extends StatelessWidget {
  final List<BarChartItem> items;
  final int total;
  const SimplePieChart({super.key, required this.items, required this.total});

  @override
  Widget build(BuildContext context) {
    if (total == 0 || items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = [
      for (var i = 0; i < items.length; i++) _chartColor(items[i], i),
    ];

    final donut = SizedBox(
      width: 140,
      height: 140,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, progress, _) => CustomPaint(
          painter: _DonutPainter(
            values: items.map((e) => e.count.toDouble()).toList(),
            colors: colors,
            track: theme.dividerColor.withValues(alpha: 0.45),
            gapColor: theme.cardColor,
            progress: progress,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$total',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.titleLarge?.color,
                  ),
                ),
                Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          _LegendRow(
            item: items[i],
            color: colors[i],
            pct: items[i].count / total,
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 320) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [donut, const SizedBox(height: 16), legend],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            donut,
            const SizedBox(width: 24),
            Expanded(child: legend),
          ],
        );
      },
    );
  }
}

class _LegendRow extends StatelessWidget {
  final BarChartItem item;
  final Color color;
  final double pct;

  const _LegendRow({
    required this.item,
    required this.color,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZero = item.count == 0;
    return Opacity(
      opacity: isZero ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item.customValueLabel ??
                  '${item.count} (${(pct * 100).toStringAsFixed(0)}%)',
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final Color track;
  final Color gapColor;
  final double progress;

  _DonutPainter({
    required this.values,
    required this.colors,
    required this.track,
    required this.gapColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sum = values.fold<double>(0, (a, b) => a + b);
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final stroke = radius * 0.28;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    // Background ring
    canvas.drawCircle(
      center,
      radius - stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (sum <= 0) return;

    final nonZero = values.where((v) => v > 0).length;
    final fullSweep = 2 * math.pi * progress;
    var start = -math.pi / 2;

    final slices = <(double, double)>[];
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = fullSweep * (values[i] / sum);
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = colors[i],
      );
      slices.add((start, sweep));
      start += sweep;
    }

    // Thin separators between slices, drawn in the card color.
    if (nonZero > 1) {
      final sep = Paint()
        ..color = gapColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.butt;
      final inner = radius - stroke - 1;
      final outer = radius + 1;
      for (final (s, _) in slices) {
        final dir = Offset(math.cos(s), math.sin(s));
        canvas.drawLine(center + dir * inner, center + dir * outer, sep);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.gapColor != gapColor ||
      !_listEq(old.values, values) ||
      !_listEq(old.colors, colors);

  static bool _listEq<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
