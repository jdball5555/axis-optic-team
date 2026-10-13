import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';
import 'schedule_common.dart';

/// Scheduled vs needed people per half hour; red when short.
class CoverageStrip extends StatelessWidget {
  static const double height = 24;

  final ScheduleDay day;
  final TimelineMetrics metrics;
  const CoverageStrip({super.key, required this.day, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = metrics;
    final blocks = <Widget>[];
    for (var t = m.start; t < m.end; t += 30) {
      // Worst of the two quarter hours in this half hour.
      var needed = 0;
      var have = 0;
      var worst = 1 << 30;
      for (final q in [t, t + 15]) {
        final n = day.neededAt(q);
        final h = day.scheduledAt(q);
        if (h - n < worst) {
          worst = h - n;
          needed = n;
          have = h;
        }
      }
      if (needed == 0 && have == 0) continue;
      final short = have < needed;
      final over = have > needed;
      final color = short
          ? AppTheme.red
          : (over ? AppTheme.lightBlue : AppTheme.green);
      final w = m.w(t, t + 30) - 2;
      blocks.add(
        Positioned(
          left: m.x(t) + 1,
          width: w,
          top: 2,
          bottom: 2,
          child: Tooltip(
            message:
                '${formatRange(t, t + 30, compact: false)}\n'
                '$have scheduled · $needed needed',
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: w < 26
                  ? null
                  : Text(
                      '$have/$needed',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: short ? AppTheme.red : theme.textTheme.bodyLarge?.color,
                      ),
                    ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: CoverageStrip.height,
      width: m.width,
      child: Stack(children: blocks),
    );
  }
}
