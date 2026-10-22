// Loading animation: the Axis Team icon (three people over the glowing arc)
// with the people bobbing up one at a time: one, two, three, pause.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand red from the app icon.
const Color kAxisRed = Color(0xFFFF4C52);

class AxisLoader extends StatefulWidget {
  const AxisLoader({super.key, this.size = 120, this.background});

  /// Width of the icon (it's about half as tall).
  final double size;

  /// What's behind it (for the thin gaps between the people). Defaults to
  /// the page background.
  final Color? background;

  @override
  State<AxisLoader> createState() => _AxisLoaderState();
}

class _AxisLoaderState extends State<AxisLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? Colors.black;
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.size,
        height: widget.size * 0.62,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: AxisIconPainter(t: _c.value, background: bg),
          ),
        ),
      ),
    );
  }
}

/// A full screen with the loader in the middle on an all-black background.
class AxisLoadingScreen extends StatelessWidget {
  const AxisLoadingScreen({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AxisLoader(size: 132, background: Colors.black),
            if (message != null) ...[
              const SizedBox(height: 22),
              Text(
                message!,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC9C9C9),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Draws the icon in its own 1080-unit space (measured from
/// branding/app_icon_square.png).
class AxisIconPainter extends CustomPainter {
  const AxisIconPainter({required this.t, required this.background});

  /// 0..1 through one loop.
  final double t;
  final Color background;

  // How far each person rises at the top of their bob (icon units).
  static const _lift = 64.0;

  /// Person 0, 1, 2 (left, middle, right) rise in turn, then a pause.
  double _bob(int i) {
    const start = [0.0, 0.17, 0.34];
    const length = 0.34;
    final p = (t - start[i]) / length;
    if (p <= 0 || p >= 1) return 0;
    // Quick up, softer landing.
    return math.sin(math.pi * math.pow(p, 0.85));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The artwork spans x 130..951, y 299..704 → fit the width.
    const left = 120.0, right = 960.0, top = 260.0, bottom = 720.0;
    final s = math.min(
      size.width / (right - left),
      size.height / (bottom - top),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-(left + right) / 2, -(top + bottom) / 2);

    final red = Paint()..color = kAxisRed;
    final gap = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28;

    final up = [for (var i = 0; i < 3; i++) -_bob(i) * _lift];

    // Bodies rise out of the "ground" just above the arc.
    canvas.save();
    canvas.clipPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(1080, 0)
        ..lineTo(1080, 672)
        ..quadraticBezierTo(540, 520, 0, 672)
        ..close(),
    );
    RRect body(double l, double tp, double r, double radius, double dy) =>
        RRect.fromLTRBAndCorners(
          l,
          tp + dy,
          r,
          900 + dy,
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        );
    // Side people sit behind the middle one.
    canvas.drawRRect(body(235, 489, 456, 110, up[0]), red);
    canvas.drawRRect(body(624, 489, 845, 110, up[2]), red);
    final middle = body(409, 464, 671, 131, up[1]);
    canvas.drawRRect(middle, gap);
    canvas.drawRRect(middle, red);
    canvas.restore();

    // Heads lead the bob a little.
    canvas.drawCircle(Offset(345.5, 407 + up[0] * 1.12), 63, red);
    canvas.drawCircle(Offset(734.5, 407 + up[2] * 1.12), 63, red);
    canvas.drawCircle(Offset(539.5, 371 + up[1] * 1.12), 72, red);

    // The glowing arc.
    final arc = Path()
      ..moveTo(130, 677)
      ..quadraticBezierTo(540, 540, 951, 677)
      ..lineTo(951, 681)
      ..quadraticBezierTo(540, 593, 130, 681)
      ..close();
    canvas.drawPath(
      arc,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );
    canvas.drawPath(
      arc,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawPath(arc, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AxisIconPainter old) =>
      old.t != t || old.background != background;
}
