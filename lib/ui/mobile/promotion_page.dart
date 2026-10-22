// The promotion moment. A full-screen sequence (about 7 seconds):
//   1. Their old title sits alone in the middle.
//   2. It breaks into pieces that scatter.
//   3. The pieces fly back one by one and build a bigger tile in the new
//      title's color, bottom row first.
//   4. The finished tile swells, a shockwave rolls out, light sweeps across
//      it and the new title appears on it.
//   5. Congratulations, their name, and a button to their new title.
// Then Home plays the title change on their name.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'mobile_data.dart';
import 'mobile_shell.dart';
import 'mobile_ui.dart';

/// Full-screen congratulations for a new promotion (route /m/celebrate).
class PromotionCelebrationPage extends ConsumerStatefulWidget {
  const PromotionCelebrationPage({super.key});

  @override
  ConsumerState<PromotionCelebrationPage> createState() =>
      _PromotionCelebrationPageState();
}

// Timeline, in seconds.
const double _kTotal = 7.4;
const double _kOldIn = 0.2; // old title fades in
const double _kShatter = 1.5; // breaks apart
const double _kGather = 2.2; // pieces start coming back
const double _kBuilt = 3.9; // tile complete
const double _kSwell = 4.35; // tile at its biggest
const double _kSettle = 5.0; // back to size
const double _kWords = 5.0; // congratulations + name
const double _kButton = 6.6; // button

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

class _PromotionCelebrationPageState
    extends ConsumerState<PromotionCelebrationPage>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_kTotal * 1000).round()),
  );
  // Slow loops for after it's built: breathing glow, turning light rays.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();

  Promotion? _promotion;

  /// Settings → "Test the promotion" (nothing is saved).
  bool _test = false;
  bool _leaving = false;
  Timer? _start;
  final Set<int> _buzzed = {};

  @override
  void initState() {
    super.initState();
    _c.addListener(_haptics);
    _start = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _c.forward();
    });
  }

  void _haptics() {
    final t = _c.value * _kTotal;
    void at(int id, double sec, Future<void> Function() buzz) {
      if (t >= sec && _buzzed.add(id)) buzz();
    }

    at(0, _kShatter, HapticFeedback.mediumImpact);
    // Little ticks as the pieces land.
    for (var i = 0; i < 7; i++) {
      at(10 + i, _kGather + 0.55 + i * 0.17, HapticFeedback.selectionClick);
    }
    at(1, _kBuilt, HapticFeedback.heavyImpact);
    at(2, _kSwell + 0.05, HapticFeedback.mediumImpact);
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    _breath.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _continue() {
    if (_leaving) return;
    _leaving = true;
    final p = _promotion;
    final storeId = ref.read(currentStoreIdProvider);
    final memberId = ref.read(myTeamRecordProvider).valueOrNull?.id;
    if (p != null) {
      // Home plays the title change.
      ref.read(titleSwapProvider.notifier).state = (
        from: p.from,
        to: p.to,
        test: _test,
      );
    }
    if (_test) {
      ref.read(promotionTestProvider.notifier).state = null;
      TestPromotion.clear();
    } else if (p != null && storeId != null && memberId != null) {
      // Not awaited: works offline too (Firestore applies it right away).
      FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('users')
          .doc(memberId)
          .update({
            'promotion.seen': true,
            'promotion.seen_at': FieldValue.serverTimestamp(),
          })
          .catchError((Object e) => debugPrint('Promotion seen failed: $e'));
    }
    context.go(MobileTab.home.path);
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    if (_promotion == null) {
      final test = ref.read(promotionTestProvider);
      _test = test != null;
      _promotion = test ?? ref.watch(myPromotionProvider);
    }
    final p = _promotion;
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final member = ref.watch(myTeamRecordProvider).valueOrNull;
    final user = ref.watch(currentUserProvider);
    final name = member != null
        ? firstNameOf(member)
        : (user?['first_name'] as String? ?? '').trim();
    final to = p?.to ?? member?.title ?? '';
    final from = p?.from ?? '';
    final toColor = titleColor(to, settings);
    final fromColor = titleColor(from, settings);
    final safe = MediaQuery.paddingOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Back finishes it (only once the button is showing).
        if (!didPop && _c.value * _kTotal >= _kButton) _continue();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            final center = Offset(w / 2, h * 0.45);
            final tileW = math.min(w - 72, 300.0);
            const tileH = 118.0;
            final oldW = math.min(
              _textWidth(from.isEmpty ? '—' : from, _oldStyle) + 52,
              w - 80,
            );
            const oldH = 54.0;

            return AnimatedBuilder(
              animation: Listenable.merge([_c, _breath, _spin]),
              builder: (context, _) {
                final t = _c.value * _kTotal;
                final built = _seg(t, _kBuilt - 0.05, _kBuilt + 0.12);
                // Grows, swells past full size, settles.
                final swellUp = Curves.easeOutCubic.transform(
                  _seg(t, _kBuilt, _kSwell),
                );
                final settle = Curves.easeOutBack.transform(
                  _seg(t, _kSwell, _kSettle),
                );
                final tileScale = t < _kSwell
                    ? 1.0 + 0.2 * swellUp
                    : 1.2 - 0.2 * settle;
                final breath = t >= _kSettle ? _breath.value : 0.0;
                final word = Curves.easeOutCubic.transform(
                  _seg(t, _kSettle - 0.55, _kSettle + 0.15),
                );
                final top = Curves.easeOutCubic.transform(
                  _seg(t, _kWords, _kWords + 0.7),
                );
                final below = Curves.easeOutCubic.transform(
                  _seg(t, _kWords + 0.45, _kWords + 1.15),
                );
                final button = Curves.easeOutCubic.transform(
                  _seg(t, _kButton, _kButton + 0.6),
                );
                final oldIn = Curves.easeOutCubic.transform(
                  _seg(t, _kOldIn, _kOldIn + 0.7),
                );
                // The old title trembles just before it breaks.
                final tremble = _seg(t, _kShatter - 0.45, _kShatter);
                final shake = math.sin(t * 70) * 2.2 * tremble;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Glow, light rays, shockwaves.
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BackdropPainter(
                          t: t,
                          center: center,
                          color: toColor,
                          bg: c.bg,
                          tileW: tileW,
                          breath: breath,
                          spin: _spin.value,
                        ),
                      ),
                    ),
                    // The pieces.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _PiecesPainter(
                            t: t,
                            center: center,
                            from: Size(oldW, oldH),
                            to: Size(tileW, tileH),
                            fromColor: fromColor,
                            toColor: toColor,
                            spread: math.min(w, h) * 0.42,
                          ),
                        ),
                      ),
                    ),

                    // 1. The old title.
                    if (t < _kShatter && from.isNotEmpty)
                      Positioned(
                        left: center.dx - oldW / 2 + shake,
                        top: center.dy - oldH / 2,
                        width: oldW,
                        height: oldH,
                        child: Opacity(
                          opacity: oldIn,
                          child: Transform.scale(
                            scale: 0.92 + 0.08 * oldIn + 0.04 * tremble,
                            child: _OldTitle(
                              label: from,
                              color: fromColor,
                              glow: tremble,
                            ),
                          ),
                        ),
                      ),
                    if (t < _kShatter + 0.3 && from.isNotEmpty)
                      Positioned(
                        left: 24,
                        right: 24,
                        top: center.dy - oldH / 2 - 40,
                        child: Opacity(
                          opacity:
                              oldIn *
                              (1 - _seg(t, _kShatter - 0.2, _kShatter + 0.3)),
                          child: Text(
                            'YOUR TITLE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.4,
                              color: c.muted,
                            ),
                          ),
                        ),
                      ),

                    // 4. The new tile.
                    if (built > 0)
                      Positioned(
                        left: center.dx - tileW / 2,
                        top: center.dy - tileH / 2,
                        width: tileW,
                        height: tileH,
                        child: Opacity(
                          opacity: built,
                          child: Transform.scale(
                            scale: tileScale + breath * 0.015,
                            child: _NewTile(
                              label: to,
                              color: toColor,
                              word: word,
                              shine: _seg(t, _kSwell - 0.15, _kSettle + 0.35),
                              glow:
                                  0.45 +
                                  0.35 *
                                      (1 - _seg(t, _kBuilt, _kSettle + 0.6)) +
                                  breath * 0.15,
                            ),
                          ),
                        ),
                      ),

                    // 5. Words.
                    Positioned(
                      left: 28,
                      right: 28,
                      bottom: h - (center.dy - tileH / 2 - 46),
                      child: Opacity(
                        opacity: top,
                        child: Transform.translate(
                          offset: Offset(0, (1 - top) * 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'CONGRATULATIONS',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 3.6,
                                  color: AppTheme.onTint(toColor),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                name.isEmpty ? 'You earned it.' : '$name!',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: TextStyle(
                                  fontSize: 40,
                                  height: 1.05,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1,
                                  color: c.title,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 32,
                      right: 32,
                      top: center.dy + tileH / 2 + 48,
                      child: Opacity(
                        opacity: below,
                        child: Transform.translate(
                          offset: Offset(0, (1 - below) * 14),
                          child: Column(
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    const TextSpan(
                                      text: 'You\'ve been promoted',
                                    ),
                                    if (from.isNotEmpty) ...[
                                      const TextSpan(text: ' from '),
                                      TextSpan(
                                        text: from,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                    const TextSpan(text: ' to '),
                                    TextSpan(
                                      text: to,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.onTint(toColor),
                                      ),
                                    ),
                                    const TextSpan(text: '.'),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16.5,
                                  height: 1.4,
                                  color: c.text,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'You earned this. Keep leading the way.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 14, color: c.muted),
                              ),
                              if (p?.date != null && !_test) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Effective ${mediumDate(p!.date!)}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: c.muted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: safe.bottom + 24,
                      child: IgnorePointer(
                        ignoring: button < 0.5,
                        child: Opacity(
                          opacity: button,
                          child: Transform.translate(
                            offset: Offset(0, (1 - button) * 20),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 440,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: MButton(
                                    label: 'See my new title',
                                    icon: Icons.arrow_forward_rounded,
                                    color: MBrand.red,
                                    onPressed: _continue,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

const _oldStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.2,
);

double _textWidth(String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return tp.width;
}

/// The old title, as a big pill.
class _OldTitle extends StatelessWidget {
  const _OldTitle({
    required this.label,
    required this.color,
    required this.glow,
  });
  final String label;
  final Color color;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: Color.alphaBlend(AppTheme.tint(color), c.bg),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.edge(color), width: 2),
        boxShadow: [
          if (glow > 0)
            BoxShadow(
              color: color.withValues(alpha: 0.5 * glow),
              blurRadius: 26 * glow,
            ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _oldStyle.copyWith(color: AppTheme.onTint(color)),
      ),
    );
  }
}

/// The new title's tile: rich color, glow, a light sweep and the title.
class _NewTile extends StatelessWidget {
  const _NewTile({
    required this.label,
    required this.color,
    required this.word,
    required this.shine,
    required this.glow,
  });

  final String label;
  final Color color;

  /// 0..1: the title appearing on the tile.
  final double word;

  /// 0..1: the light sweeping across.
  final double shine;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.28)!;
    final dark = Color.lerp(color, Colors.black, 0.38)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: glow.clamp(0.0, 1.0)),
            blurRadius: 46,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [light, color, dark],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
            // Inner highlight edge.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 1.5,
                ),
              ),
            ),
            // Light sweep.
            if (shine > 0 && shine < 1)
              LayoutBuilder(
                builder: (context, box) {
                  final x = -box.maxWidth * 0.6 + shine * box.maxWidth * 2.0;
                  return Transform.translate(
                    offset: Offset(x, 0),
                    child: Transform.rotate(
                      angle: 0.35,
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        maxHeight: box.maxHeight * 3,
                        child: Container(
                          width: box.maxWidth * 0.32,
                          height: box.maxHeight * 3,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.45),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            // The title.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: word,
                    child: Text(
                      'NEW TITLE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.6,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Opacity(
                    opacity: word,
                    child: Transform.scale(
                      scale: 0.86 + 0.14 * word,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5 + 10 * (1 - word),
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
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
}

/// Glow behind everything, slow light rays once it's built, and the
/// shockwaves when the tile completes.
class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.t,
    required this.center,
    required this.color,
    required this.bg,
    required this.tileW,
    required this.breath,
    required this.spin,
  });

  final double t;
  final Offset center;
  final Color color;
  final Color bg;
  final double tileW;
  final double breath;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.longestSide * 0.75;
    // Glow builds with the tile, flashes when it completes.
    final build = _seg(t, _kGather, _kBuilt);
    final flash = t < _kBuilt ? 0.0 : math.max(0.0, 1 - (t - _kBuilt) / 0.9);
    final glow = (0.04 + 0.12 * build + 0.22 * flash + 0.04 * breath).clamp(
      0.0,
      0.5,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(center, r, [
          color.withValues(alpha: glow),
          color.withValues(alpha: 0),
        ]),
    );

    // Light rays.
    final rays = _seg(t, _kBuilt, _kSettle + 0.8);
    if (rays > 0) {
      const count = 14;
      final paint = Paint()
        ..shader = ui.Gradient.radial(center, r * 0.9, [
          color.withValues(alpha: 0.10 * rays),
          color.withValues(alpha: 0),
        ]);
      final turn = spin * math.pi * 2;
      for (var i = 0; i < count; i++) {
        final a = turn + i * math.pi * 2 / count;
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(
            center.dx + math.cos(a - 0.07) * r,
            center.dy + math.sin(a - 0.07) * r,
          )
          ..lineTo(
            center.dx + math.cos(a + 0.07) * r,
            center.dy + math.sin(a + 0.07) * r,
          )
          ..close();
        canvas.drawPath(path, paint);
      }
    }

    // Shockwaves.
    for (final (delay, strength) in [(0.0, 1.0), (0.18, 0.6)]) {
      final p = _seg(t, _kBuilt + delay, _kBuilt + delay + 1.0);
      if (p <= 0 || p >= 1) continue;
      final e = Curves.easeOutCubic.transform(p);
      final radius = tileW * 0.55 + e * size.longestSide * 0.7;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * (1 - e) + 0.5
          ..color = Color.lerp(
            color,
            Colors.white,
            0.3,
          )!.withValues(alpha: (1 - e) * 0.7 * strength),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => true;
}

/// The old title breaking into pieces, and the pieces building the new tile.
class _PiecesPainter extends CustomPainter {
  _PiecesPainter({
    required this.t,
    required this.center,
    required this.from,
    required this.to,
    required this.fromColor,
    required this.toColor,
    required this.spread,
  });

  final double t;
  final Offset center;
  final Size from;
  final Size to;
  final Color fromColor;
  final Color toColor;
  final double spread;

  static const _cols = 12;
  static const _rows = 5;

  @override
  void paint(Canvas canvas, Size size) {
    if (t < _kShatter || t > _kBuilt + 0.15) return;
    final fade = 1 - _seg(t, _kBuilt, _kBuilt + 0.15);
    final rnd = math.Random(11);
    final fromCell = Size(from.width / _cols, from.height / _rows);
    final toCell = Size(to.width / _cols, to.height / _rows);
    final fromOrigin = center - Offset(from.width / 2, from.height / 2);
    final toOrigin = center - Offset(to.width / 2, to.height / 2);
    final light = Color.lerp(toColor, Colors.white, 0.28)!;
    final dark = Color.lerp(toColor, Colors.black, 0.38)!;
    final paint = Paint();

    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _cols; col++) {
        // Same random numbers every frame.
        final angle = rnd.nextDouble() * math.pi * 2;
        final dist = spread * (0.45 + rnd.nextDouble() * 0.55);
        final spinA = (rnd.nextDouble() - 0.5) * 5;
        final jitter = rnd.nextDouble();
        final swirl = (rnd.nextDouble() - 0.5) * 2;

        final src =
            fromOrigin +
            Offset((col + 0.5) * fromCell.width, (row + 0.5) * fromCell.height);
        final dst =
            toOrigin +
            Offset((col + 0.5) * toCell.width, (row + 0.5) * toCell.height);
        // Scatter mostly sideways and up.
        final scatter =
            center +
            Offset(
              math.cos(angle) * dist,
              math.sin(angle) * dist * 0.75 - spread * 0.08,
            );

        // Build from the bottom row up, sweeping left to right.
        final stagger =
            (_rows - 1 - row) / _rows * 0.85 +
            col / _cols * 0.35 +
            jitter * 0.1;
        final start = _kGather + stagger;
        const travel = 0.5;

        Offset pos;
        double rot;
        double scale;
        Color color;
        Size cell;
        double spark = 0;

        if (t < start) {
          // Burst out from the old title and drift.
          final p = Curves.easeOutCubic.transform(
            _seg(t, _kShatter, _kShatter + 0.65),
          );
          final drift =
              Offset(math.cos(angle + 1.6), math.sin(angle + 1.6)) *
              (t - _kShatter) *
              6 *
              swirl;
          pos = Offset.lerp(src, scatter, p)! + drift;
          rot = spinA * p + (t - _kShatter) * swirl * 0.8;
          scale = 1 - 0.4 * p;
          color = fromColor;
          cell = fromCell;
        } else {
          // Swoop into place.
          final raw = _seg(t, start, start + travel);
          final e = Curves.easeInOutCubic.transform(raw);
          final drift =
              Offset(math.cos(angle + 1.6), math.sin(angle + 1.6)) *
              (start - _kShatter) *
              6 *
              swirl;
          final a = scatter + drift;
          final ctrl = Offset.lerp(a, dst, 0.5)! + Offset(swirl * 60, -50);
          final u = 1 - e;
          pos = a * (u * u) + ctrl * (2 * u * e) + dst * (e * e);
          final rot0 = spinA + (start - _kShatter) * swirl * 0.8;
          rot = rot0 * (1 - e);
          scale = 0.6 + 0.4 * e;
          final shade = Color.lerp(
            light,
            dark,
            (row + col * 0.4) / (_rows + _cols * 0.4),
          )!;
          color = Color.lerp(fromColor, shade, e)!;
          cell = Size.lerp(fromCell, toCell, e)!;
          // A flash as it lands.
          spark = raw > 0.8 ? 1 - (raw - 0.9).abs() * 10 : 0;
        }

        final wPiece = cell.width * scale - 1.2;
        final hPiece = cell.height * scale - 1.2;
        if (wPiece <= 0 || hPiece <= 0) continue;
        paint.color = Color.lerp(
          color,
          Colors.white,
          spark.clamp(0.0, 1.0) * 0.7,
        )!.withValues(alpha: 0.95 * fade);
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(rot);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: wPiece, height: hPiece),
            Radius.circular(math.min(wPiece, hPiece) * 0.18),
          ),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PiecesPainter old) => true;
}

/// Sparks bursting out from the new title.
class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    const count = 14;
    for (var i = 0; i < count; i++) {
      final a = i / count * math.pi * 2;
      // Wider than tall: the pill is wide.
      final dir = Offset(math.cos(a) * 1.7, math.sin(a));
      final inner = 40 + progress * 60;
      final outer = inner + 18 * (1 - progress);
      paint.color = (i.isEven ? color : AppTheme.yellow).withValues(
        alpha: (1 - progress) * 0.9,
      );
      canvas.drawLine(center + dir * inner, center + dir * outer, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.progress != progress;
}

// =============================================================================
// Home: the title pill changing to the new title
// =============================================================================

/// Plays the old title turning into the new one (after the congratulations
/// screen). Ends looking exactly like the normal title pill.
class TitleSwapPill extends StatefulWidget {
  const TitleSwapPill({
    super.key,
    required this.from,
    required this.to,
    required this.fromColor,
    required this.toColor,
    this.onDone,
  });

  final String from;
  final String to;
  final Color fromColor;
  final Color toColor;

  /// Called a moment after the change finishes.
  final VoidCallback? onDone;

  @override
  State<TitleSwapPill> createState() => _TitleSwapPillState();
}

class _TitleSwapPillState extends State<TitleSwapPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  Timer? _start;
  Timer? _done;
  bool _buzzed = false;

  @override
  void initState() {
    super.initState();
    _start = Timer(const Duration(milliseconds: 650), () {
      if (mounted) _c.forward();
    });
    _c.addListener(() {
      if (!_buzzed && _c.value >= 0.3) {
        _buzzed = true;
        HapticFeedback.mediumImpact();
      }
    });
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && widget.onDone != null) {
        _done = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) widget.onDone?.call();
        });
      }
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _done?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final out = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.28, curve: Curves.easeInBack),
    );
    final pop = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.24, 0.6, curve: Curves.elasticOut),
    );
    final ring = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.26, 0.7, curve: Curves.easeOut),
    );
    final glow = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );
    final caption = CurvedAnimation(parent: _c, curve: Curves.linear);

    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final showNew = _c.value >= 0.24;
        final glowAlpha = showNew ? (1 - glow.value) * 0.55 : 0.0;
        // "New title" shows up with the change and fades away at the end.
        final captionAlpha = _c.value < 0.35
            ? 0.0
            : _c.value < 0.5
            ? (caption.value - 0.35) / 0.15
            : _c.value > 0.85
            ? (1 - caption.value) / 0.15
            : 1.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (showNew)
                    CustomPaint(
                      size: const Size(10, 10),
                      painter: _SparkPainter(
                        progress: ring.value,
                        color: widget.toColor,
                      ),
                    ),
                  if (!showNew)
                    Opacity(
                      opacity: (1 - out.value).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: (1 - out.value * 0.5).clamp(0.3, 1.0),
                        child: MPill(
                          widget.from,
                          color: widget.fromColor,
                          large: true,
                        ),
                      ),
                    )
                  else
                    Transform.scale(
                      scale: 0.5 + pop.value * 0.5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            if (glowAlpha > 0)
                              BoxShadow(
                                color: widget.toColor.withValues(
                                  alpha: glowAlpha,
                                ),
                                blurRadius: 22,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: MPill(
                          widget.to,
                          color: widget.toColor,
                          large: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (captionAlpha > 0) ...[
              const SizedBox(width: 8),
              Opacity(
                opacity: captionAlpha.clamp(0.0, 1.0),
                child: Text(
                  'New title!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.onTint(widget.toColor),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A test promotion (Settings → "Test the promotion"), kept on the phone
/// until it plays, so it survives the app being closed.
class TestPromotion {
  static const _key = 'test_promotion';

  static Future<void> save(Promotion p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [
      p.id,
      p.from,
      p.to,
      '${p.revealAt.millisecondsSinceEpoch}',
    ]);
  }

  static Future<Promotion?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getStringList(_key);
      if (v == null || v.length < 4) return null;
      final now = DateTime.now();
      return Promotion(
        id: v[0],
        from: v[1],
        to: v[2],
        revealAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse(v[3]) ?? 0),
        seen: false,
        date: DateTime(now.year, now.month, now.day),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Opens the congratulations screen for a promotion when they open the app
/// (or come back to it, or tap the notification) after it was sent. One
/// that arrives while they're using the app waits for the next time they
/// open it. Shown once per promotion.
mixin PromotionWatcher<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  static final Set<String> _shown = {};
  static DateTime _openedAt = DateTime.now();

  /// The app was just opened / brought back / opened from a notification.
  static void appOpened() => _openedAt = DateTime.now();

  void watchPromotion() {
    final test = ref.watch(promotionTestProvider);
    final real = ref.watch(myPromotionProvider);
    final record = ref.watch(myTeamRecordProvider).valueOrNull;
    Promotion? p = test;
    if (p == null &&
        real != null &&
        !real.seen &&
        real.from != real.to &&
        record?.title == real.to) {
      p = real;
    }
    if (p == null) return;
    final key = '${p.id}|${p.to}|${p.revealAt.millisecondsSinceEpoch}';
    if (_shown.contains(key)) return;
    // Not sent yet when they last opened the app.
    if (p.revealAt.isAfter(_openedAt)) return;
    _shown.add(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.push(celebratePath);
    });
  }
}

const celebratePath = '/m/celebrate';
