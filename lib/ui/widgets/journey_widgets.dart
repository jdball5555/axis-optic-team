// Shared pieces of the team member journey: the icon list, the round title
// tiles and the read-only journey map. Used by Settings → Titles on the
// website and by "Your journey" in the phone app.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/store_settings_model.dart';
import '../../models/title_journey.dart';

// =============================================================================
// Colors and icons
// =============================================================================

Color journeyTitleColor(TitleConfig t) {
  if (t.color == 'Color') return AppTheme.blue;
  final c = AppTheme.getColorFromName(t.color);
  return c == Colors.grey ? AppTheme.blue : c;
}

/// Icons a title can use on the journey (saved by key).
const List<(String, String, IconData)> kJourneyIcons = [
  ('eco', 'New start', Icons.eco_rounded),
  ('school', 'Training', Icons.school_rounded),
  ('person', 'Team member', Icons.person_rounded),
  ('co_present', 'Trainer', Icons.co_present_rounded),
  ('record_voice', 'Coach', Icons.record_voice_over_rounded),
  ('star', 'Leader', Icons.star_rounded),
  ('stars', 'Rising star', Icons.stars_rounded),
  ('supervisor', 'Supervisor', Icons.supervisor_account_rounded),
  ('badge', 'Manager', Icons.badge_rounded),
  ('shield', 'Shield', Icons.shield_rounded),
  ('verified', 'Certified', Icons.verified_rounded),
  ('military_tech', 'Medal', Icons.military_tech_rounded),
  ('workspace_premium', 'Director', Icons.workspace_premium_rounded),
  ('emoji_events', 'Trophy', Icons.emoji_events_rounded),
  ('diamond', 'Diamond', Icons.diamond_rounded),
  ('storefront', 'Operator', Icons.storefront_rounded),
  ('business', 'Business', Icons.business_center_rounded),
  ('groups', 'Team', Icons.groups_rounded),
  ('handshake', 'Hospitality', Icons.handshake_rounded),
  ('support_agent', 'Guest care', Icons.support_agent_rounded),
  ('point_of_sale', 'Front counter', Icons.point_of_sale_rounded),
  ('drive', 'Drive-thru', Icons.directions_car_rounded),
  ('delivery', 'Delivery', Icons.delivery_dining_rounded),
  ('restaurant', 'Dining', Icons.restaurant_rounded),
  ('fastfood', 'Food', Icons.fastfood_rounded),
  ('soup', 'Kitchen', Icons.soup_kitchen_rounded),
  ('cafe', 'Drinks', Icons.local_cafe_rounded),
  ('cleaning', 'Cleaning', Icons.cleaning_services_rounded),
  ('inventory', 'Inventory', Icons.inventory_2_rounded),
  ('schedule', 'Scheduling', Icons.schedule_rounded),
  ('payments', 'Cash', Icons.payments_rounded),
  ('assignment', 'Checklists', Icons.assignment_turned_in_rounded),
  ('insights', 'Insights', Icons.insights_rounded),
  ('psychology', 'Mindset', Icons.psychology_rounded),
  ('lightbulb', 'Ideas', Icons.lightbulb_rounded),
  ('trending_up', 'Growth', Icons.trending_up_rounded),
  ('rocket', 'Launch', Icons.rocket_launch_rounded),
  ('bolt', 'Energy', Icons.bolt_rounded),
  ('fire', 'On fire', Icons.local_fire_department_rounded),
  ('flag', 'Goal', Icons.flag_rounded),
  ('favorite', 'Heart', Icons.favorite_rounded),
  ('celebration', 'Celebrate', Icons.celebration_rounded),
];

IconData? journeyIconByKey(String? key) {
  if (key == null) return null;
  for (final (k, _, icon) in kJourneyIcons) {
    if (k == key) return icon;
  }
  return null;
}

/// A sensible icon from the title's name when none was picked.
String journeyDefaultIconKey(String name) {
  final n = name.toLowerCase();
  bool has(String s) => n.contains(s);
  if (has('in training') || has('trainee') || has('new hire')) return 'school';
  if (has('trainer') || has('coach')) return 'co_present';
  if (has('director')) return 'workspace_premium';
  if (has('operator') || has('owner')) return 'storefront';
  if (has('manager')) return 'badge';
  if (has('supervis')) return 'supervisor';
  if (has('lead')) return 'star';
  if (has('kitchen') || has('cook') || has('boh')) return 'soup';
  if (has('drive')) return 'drive';
  if (has('front') || has('cashier') || has('foh')) return 'point_of_sale';
  if (has('host') || has('hospitality')) return 'handshake';
  if (has('catering') || has('delivery')) return 'delivery';
  if (has('team')) return 'person';
  return 'person';
}

IconData journeyIconFor(TitleConfig t, TitleJourney j) =>
    journeyIconByKey(j.icons[t.id]) ??
    journeyIconByKey(journeyDefaultIconKey(t.name)) ??
    Icons.person_rounded;

// =============================================================================
// A title as a round tile
// =============================================================================

enum JourneyLook {
  /// A title on the journey.
  normal,

  /// Where you are now (ring + soft pulse).
  current,

  /// Already done (quiet, with a check).
  done,

  /// Not on your path (faded).
  faded,
}

/// Room around a tile's circle for the "you are here" / selected ring.
double journeyRingGap(double size) => size * 0.09;

class JourneyCircle extends StatelessWidget {
  const JourneyCircle({
    super.key,
    required this.color,
    required this.icon,
    this.size = 84,
    this.look = JourneyLook.normal,
    this.selected = false,
    this.hovered = false,
    this.pulse,
  });

  final Color color;
  final IconData icon;
  final double size;
  final JourneyLook look;

  /// Picked in the editor (ring in the text color).
  final bool selected;
  final bool hovered;

  /// 0..1 for the current title's expanding ring (null = no ring animation).
  final double? pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final card = theme.cardColor;
    final done = look == JourneyLook.done;
    final current = look == JourneyLook.current;
    // Light title colors get a dark icon so it stays readable.
    final iconColor = done
        ? AppTheme.onTint(color)
        : (color.computeLuminance() > 0.5
              ? Color.lerp(color, Colors.black, 0.62)!
              : Colors.white);
    final lifted = hovered || current;

    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? Color.alphaBlend(
                color.withValues(alpha: dark ? 0.18 : 0.14),
                card,
              )
            : null,
        gradient: done
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(color, Colors.white, 0.10)!,
                  Color.lerp(color, Colors.black, 0.06)!,
                ],
              ),
        border: done
            ? Border.all(color: color.withValues(alpha: 0.35), width: 1.2)
            : null,
        boxShadow: done
            ? null
            : [
                BoxShadow(
                  color: color.withValues(
                    alpha: dark ? 0.22 : (lifted ? 0.34 : 0.22),
                  ),
                  blurRadius: size * (lifted ? 0.28 : 0.18),
                  offset: Offset(0, size * 0.06),
                ),
              ],
      ),
      child: Icon(icon, size: size * 0.42, color: iconColor),
    );

    final ringGap = journeyRingGap(size);
    final ring = size + ringGap * 2;
    return Opacity(
      opacity: look == JourneyLook.faded ? 0.42 : 1,
      child: SizedBox(
        width: ring + 8,
        height: ring + 8,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (current && pulse != null)
              Container(
                width: ring + pulse! * size * 0.3,
                height: ring + pulse! * size * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: (1 - pulse!) * 0.4),
                    width: 1.5,
                  ),
                ),
              ),
            if (current || selected)
              Container(
                width: ring,
                height: ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? theme.colorScheme.onSurface : color,
                    width: 2,
                  ),
                ),
              ),
            AnimatedScale(
              scale: hovered ? 1.05 : 1,
              duration: const Duration(milliseconds: 160),
              child: circle,
            ),
            if (done)
              Positioned(
                right: ringGap + size * 0.02,
                top: ringGap + size * 0.02,
                child: Container(
                  width: size * 0.3,
                  height: size * 0.3,
                  decoration: BoxDecoration(
                    color: AppTheme.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: card, width: 2),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: size * 0.2,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A title's name as a pill hooked onto the bottom of its bubble: outlined
/// in the title's color, solid for where you are, quiet with a check once
/// done.
class JourneyNameplate extends StatelessWidget {
  const JourneyNameplate({
    super.key,
    required this.name,
    required this.color,
    this.look = JourneyLook.normal,
    this.selected = false,
    this.small = false,
    this.large = false,
  });

  final String name;
  final Color color;
  final JourneyLook look;
  final bool selected;
  final bool small;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final card = theme.cardColor;
    final text = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final muted = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final current = look == JourneyLook.current;
    final done = look == JourneyLook.done;
    final onColor = color.computeLuminance() > 0.5
        ? Color.lerp(color, Colors.black, 0.7)!
        : Colors.white;
    final fill = current
        ? color
        : done
        ? Color.alphaBlend(
            (dark ? Colors.white : Colors.black).withValues(alpha: 0.05),
            card,
          )
        : card;
    final fg = current ? onColor : (done ? muted : text);
    final double fontSize = large ? 15 : (small ? 11.5 : 13);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : (small ? 8 : 10),
        vertical: large ? 6 : (small ? 4 : 5),
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(large ? 14 : 10),
        border: Border.all(
          color: selected
              ? theme.colorScheme.onSurface
              : (done ? theme.dividerColor : color),
          width: selected ? 2 : 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: (current ? color : Colors.black).withValues(
              alpha: current ? 0.4 : (dark ? 0.35 : 0.08),
            ),
            blurRadius: current ? 14 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done) ...[
            Icon(
              Icons.check_rounded,
              size: fontSize + 1,
              color: AppTheme.green,
            ),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              name.isEmpty ? 'Untitled' : name,
              textAlign: TextAlign.center,
              maxLines: large ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: large ? -0.2 : 0,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill above a tile ("NEW HIRES", "YOU").
class JourneyBadge extends StatelessWidget {
  const JourneyBadge(this.label, {super.key, this.color, this.icon});
  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? Theme.of(context).colorScheme.onSurface;
    final fg = color == null
        ? Theme.of(context).scaffoldBackgroundColor
        : (bg.computeLuminance() > 0.5
              ? Color.lerp(bg, Colors.black, 0.7)!
              : Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).cardColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Map geometry and arrows
// =============================================================================

/// Sizes of the journey map (one cell per title). Each cell holds a tile
/// (badge, circle, name, caption); the strips between columns and between
/// rows are kept empty for the arrows.
class JourneyLayout {
  const JourneyLayout({
    this.cellW = 176,
    this.cellH = 186,
    this.circle = 84,
    this.pad = 20,
    this.top = 14,
    this.gutter = 28,
  });

  final double cellW;
  final double cellH;
  final double circle;
  final double pad;

  /// Room above the first row (for badges / step labels).
  final double top;

  /// Space between two names side by side (arrows run down the middle).
  final double gutter;

  /// Width of a title's name under its circle.
  double get labelW => cellW - gutter;

  /// The circle with its ring and padding (the tile's top part).
  double get outer => circle + journeyRingGap(circle) * 2 + 8;

  /// Where arrows start and end: just outside the circle's ring.
  double get port => circle / 2 + journeyRingGap(circle) + 4;

  Offset center(JourneyCell c) => Offset(
    pad + c.x * cellW + cellW / 2,
    pad + top + c.y * cellH + circle / 2 + 10,
  );

  Size size(int cols, int rows) =>
      Size(pad * 2 + cols * cellW, pad * 2 + top + rows * cellH);

  /// Top of row [row]'s tiles (badge included) and bottom of its names
  /// (two lines and a caption).
  double _tilesTop(int row) => center(JourneyCell(0, row)).dy - outer / 2 - 10;
  double _tilesBottom(int row) =>
      center(JourneyCell(0, row)).dy +
      outer / 2 +
      6 +
      (circle >= 70 ? 14 : 12.5) * 1.2 * 2 +
      18;

  /// The empty strip above row [k] (k = rows: below the last row).
  double laneY(int k) =>
      k <= 0 ? _tilesTop(0) - 10 : (_tilesBottom(k - 1) + _tilesTop(k)) / 2;
}

/// One arrow on the map: straight lines with rounded corners from one tile's
/// side to another's.
class JourneyRoute {
  JourneyRoute(List<Offset> points) : points = _simplify(points);

  final List<Offset> points;

  static List<Offset> _simplify(List<Offset> pts) {
    final out = <Offset>[];
    for (final p in pts) {
      if (out.isNotEmpty && (out.last - p).distance < 0.5) continue;
      // Drop the middle of three points in a line.
      if (out.length >= 2) {
        final a = out[out.length - 2], b = out.last;
        if (((a.dx - b.dx).abs() < 0.5 && (b.dx - p.dx).abs() < 0.5) ||
            ((a.dy - b.dy).abs() < 0.5 && (b.dy - p.dy).abs() < 0.5)) {
          out.removeLast();
        }
      }
      out.add(p);
    }
    return out;
  }

  Offset get _dir {
    final d = points.last - points[points.length - 2];
    return d / (d.distance == 0 ? 1 : d.distance);
  }

  /// The line, stopping where the arrowhead [head] begins.
  Path path({double corner = 12, double head = 8}) {
    final p = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1], cur = points[i], next = points[i + 1];
      final r = math.min(
        corner,
        math.min((cur - prev).distance, (next - cur).distance) / 2,
      );
      final a = cur + (prev - cur) / (prev - cur).distance * r;
      final b = cur + (next - cur) / (next - cur).distance * r;
      p
        ..lineTo(a.dx, a.dy)
        ..quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    final lastSeg = points.last - points[points.length - 2];
    final lastDist = lastSeg.distance;
    final headOffset = math.min(head * 0.72, math.max(0.0, lastDist - 1.0));
    final end = points.last - _dir * headOffset;
    return p..lineTo(end.dx, end.dy);
  }

  /// A small rounded arrowhead at the end.
  Path head(double size) {
    final dir = _dir;
    final tip = points.last;
    final n = Offset(-dir.dy, dir.dx);
    final base = tip - dir * size;
    final l = base + n * size * 0.62, r = base - n * size * 0.62;
    final notch = tip - dir * size * 0.72;
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(l.dx, l.dy)
      ..quadraticBezierTo(notch.dx, notch.dy, r.dx, r.dy)
      ..close();
  }
}

/// Routes every arrow of [journey] on [layout] (moved right by [shift]).
/// Arrows leave a tile from its side, turn only in the empty strips between
/// columns and rows, and come into the next tile's side, so they never run
/// over a name or another tile. Arrows from the same title share their
/// branch; different titles get their own track in a strip.
List<(JourneyLink, JourneyRoute)> routeJourney(
  TitleJourney journey,
  JourneyLayout layout, {
  double shift = 0,
}) {
  final l = layout;
  final occupied = journey.nodes.values.toSet();
  final links = [
    for (final link in journey.links)
      if (journey.nodes.containsKey(link.from) &&
          journey.nodes.containsKey(link.to))
        link,
  ];
  double cx(int x) => l.pad + shift + x * l.cellW + l.cellW / 2;
  double cy(int y) => l.center(JourneyCell(0, y)).dy;
  double gx(int k) => l.pad + shift + k * l.cellW;
  bool clear(int y, int x0, int x1) {
    for (var x = math.min(x0, x1) + 1; x < math.max(x0, x1); x++) {
      if (occupied.contains(JourneyCell(x, y))) return false;
    }
    return true;
  }

  List<Offset> plan(
    JourneyLink link,
    double Function(int gutter, String owner) gutterX,
    double Function(int lane, int index) laneY,
    int index,
  ) {
    final a = journey.nodes[link.from]!, b = journey.nodes[link.to]!;
    final ya = cy(a.y), yb = cy(b.y);
    if (a.x == b.x) {
      if (b.y > a.y) {
        bool vClear = true;
        for (var y = a.y + 1; y < b.y; y++) {
          if (occupied.contains(JourneyCell(a.x, y))) {
            vClear = false;
            break;
          }
        }
        if (vClear) {
          return [
            Offset(cx(a.x), ya + l.port),
            Offset(cx(b.x), yb - l.port),
          ];
        }
      }
      final g = gutterX(a.x + 1, link.from);
      final exit = Offset(cx(a.x) + l.port, ya);
      return [exit, Offset(g, ya), Offset(g, yb), Offset(cx(b.x) + l.port, yb)];
    }
    final dir = b.x > a.x ? 1 : -1;
    final exit = Offset(cx(a.x) + dir * l.port, ya);
    final enter = Offset(cx(b.x) - dir * l.port, yb);
    final g1k = dir > 0 ? a.x + 1 : a.x;
    final g2k = dir > 0 ? b.x : b.x + 1;
    if (a.y == b.y && clear(a.y, a.x, b.x)) return [exit, enter];
    if (g1k == g2k || clear(b.y, a.x, b.x)) {
      // Turn in the strip next to the first title, then along the second's
      // row (empty between them).
      final g = gutterX(g1k, link.from);
      return [exit, Offset(g, ya), Offset(g, yb), enter];
    }
    if (clear(a.y, a.x, b.x)) {
      // Along the first title's row (empty), turn next to the second.
      final g = gutterX(g2k, link.to);
      return [exit, Offset(g, ya), Offset(g, yb), enter];
    }
    // Both rows are in the way: over to the strip between the rows.
    final lane = laneY(
      b.y > a.y ? a.y + 1 : (b.y < a.y ? a.y : a.y + 1),
      index,
    );
    final g1 = gutterX(g1k, link.from), g2 = gutterX(g2k, link.to);
    return [
      exit,
      Offset(g1, ya),
      Offset(g1, lane),
      Offset(g2, lane),
      Offset(g2, yb),
      enter,
    ];
  }

  // First pass: who uses which strip. Second: give each its track.
  final gutterUse = <int, Set<String>>{};
  final laneUse = <int, List<int>>{};
  for (var i = 0; i < links.length; i++) {
    plan(
      links[i],
      (k, owner) {
        (gutterUse[k] ??= {}).add(owner);
        return gx(k);
      },
      (k, index) {
        (laneUse[k] ??= []).add(index);
        return l.laneY(k);
      },
      i,
    );
  }
  const track = 7.0;
  final maxOffset = l.gutter / 2 - 4;
  double gutterX(int k, String owner) {
    final owners = gutterUse[k]!.toList()
      ..sort((p, q) {
        final cp = journey.nodes[p]!, cq = journey.nodes[q]!;
        return cp.y != cq.y ? cp.y.compareTo(cq.y) : cp.x.compareTo(cq.x);
      });
    final i = owners.indexOf(owner);
    return gx(k) +
        ((i - (owners.length - 1) / 2) * track).clamp(-maxOffset, maxOffset);
  }

  double laneY(int k, int index) {
    final users = laneUse[k]!;
    final i = users.indexOf(index);
    return l.laneY(k) + (i - (users.length - 1) / 2) * 6;
  }

  return [
    for (var i = 0; i < links.length; i++)
      (links[i], JourneyRoute(plan(links[i], gutterX, laneY, i))),
  ];
}

class JourneyPainter extends CustomPainter {
  JourneyPainter({
    required this.routes,
    required this.arrowColor,
    this.dimmed = const {},
    this.highlighted = const {},
    this.highlightColor,
    this.slots = const [],
    this.slotColor,
    this.slotRadius = 0,
    this.activeSlot,
    this.activeColor,
  });

  final List<JourneyRoute> routes;
  final Color arrowColor;

  /// Indexes of arrows drawn faint / in the highlight color.
  final Set<int> dimmed;
  final Set<int> highlighted;
  final Color? highlightColor;

  /// Empty grid spots drawn as dashed rings (editor).
  final List<Offset> slots;
  final Color? slotColor;
  final double slotRadius;
  final Offset? activeSlot;
  final Color? activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (slotColor != null) {
      final dash = Paint()
        ..color = slotColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      for (final c in slots) {
        const n = 28;
        for (var i = 0; i < n; i += 2) {
          final a0 = i / n * math.pi * 2, a1 = (i + 1) / n * math.pi * 2;
          canvas.drawArc(
            Rect.fromCircle(center: c, radius: slotRadius),
            a0,
            a1 - a0,
            false,
            dash,
          );
        }
      }
    }
    if (activeSlot != null && activeColor != null) {
      canvas.drawCircle(
        activeSlot!,
        slotRadius,
        Paint()..color = activeColor!.withValues(alpha: 0.18),
      );
      canvas.drawCircle(
        activeSlot!,
        slotRadius,
        Paint()
          ..color = activeColor!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    final normalRoutes = <JourneyRoute>[];
    final dimmedRoutes = <JourneyRoute>[];
    final highRoutes = <JourneyRoute>[];

    for (var i = 0; i < routes.length; i++) {
      if (highlighted.contains(i) && highlightColor != null) {
        highRoutes.add(routes[i]);
      } else if (dimmed.contains(i)) {
        dimmedRoutes.add(routes[i]);
      } else {
        normalRoutes.add(routes[i]);
      }
    }

    void drawRouteList(
      List<JourneyRoute> list,
      Color color,
      double opacity,
      double strokeWidth,
      double headSize,
    ) {
      if (list.isEmpty) return;
      if (opacity < 1.0) {
        canvas.saveLayer(
          null,
          Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
        );
      }
      final strokePaint = Paint()
        ..color = color.withValues(alpha: 1.0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 1.0)
        ..style = PaintingStyle.fill;

      for (final r in list) {
        canvas.drawPath(r.path(head: headSize), strokePaint);
        canvas.drawPath(r.head(headSize), fillPaint);
      }

      if (opacity < 1.0) {
        canvas.restore();
      }
    }

    drawRouteList(dimmedRoutes, arrowColor, 0.22, 1.8, 8.0);
    drawRouteList(normalRoutes, arrowColor, 0.50, 1.8, 8.0);
    if (highlightColor != null) {
      drawRouteList(highRoutes, highlightColor!, 1.0, 2.4, 9.0);
    }
  }

  @override
  bool shouldRepaint(covariant JourneyPainter old) => true;
}

// =============================================================================
// Read-only journey map
// =============================================================================

/// The whole journey: round tiles on a grid, arrows between them, names
/// under each tile. Scroll it sideways when it's wider than the screen.
class JourneyMapView extends StatelessWidget {
  const JourneyMapView({
    super.key,
    required this.journey,
    required this.titles,
    this.layout = const JourneyLayout(),
    this.lookFor,
    this.captionFor,
    this.badgeFor,
    this.selectedId,
    this.hoveredId,
    this.onTap,
    this.onHover,
    this.highlightFrom,
    this.pulse,
    this.minWidth = 0,
  });

  final TitleJourney journey;
  final List<TitleConfig> titles;
  final JourneyLayout layout;

  final JourneyLook Function(String id)? lookFor;
  final String? Function(String id)? captionFor;
  final Widget? Function(String id)? badgeFor;
  final String? selectedId;
  final String? hoveredId;
  final ValueChanged<String>? onTap;
  final ValueChanged<String?>? onHover;

  /// Arrows leaving this title are drawn in its color.
  final String? highlightFrom;

  /// Animation value for the current title's ring.
  final double? pulse;

  /// Stretch the canvas to at least this width (keeps it centered).
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final j = journey;
    final byId = {for (final t in titles) t.id: t};
    final cols = math.max(j.columns, 1);
    final rows = math.max(j.rows, 1);
    final natural = layout.size(cols, rows);
    final width = math.max(natural.width, minWidth);
    final shift = (width - natural.width) / 2;
    Offset at(JourneyCell c) => layout.center(c) + Offset(shift, 0);

    final routes = <JourneyRoute>[];
    final dimmed = <int>{};
    final highlighted = <int>{};
    for (final (link, route) in routeJourney(j, layout, shift: shift)) {
      final i = routes.length;
      routes.add(route);
      if (link.from == highlightFrom) highlighted.add(i);
      final lf = lookFor;
      if (lf != null &&
          (lf(link.to) == JourneyLook.faded ||
              lf(link.to) == JourneyLook.done)) {
        dimmed.add(i);
      }
    }
    final highlightColor = highlightFrom == null
        ? null
        : (byId[highlightFrom] == null
              ? null
              : journeyTitleColor(byId[highlightFrom]!));

    final labelW = layout.labelW;
    return SizedBox(
      width: width,
      height: natural.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: JourneyPainter(
                routes: routes,
                arrowColor: muted,
                dimmed: dimmed,
                highlighted: highlighted,
                highlightColor: highlightColor,
              ),
            ),
          ),
          for (final e in j.nodes.entries)
            if (byId[e.key] case final t?)
              Builder(
                builder: (context) {
                  final c = at(e.value);
                  final look = lookFor?.call(t.id) ?? JourneyLook.normal;
                  final caption = captionFor?.call(t.id);
                  final badge = badgeFor?.call(t.id);
                  return Positioned(
                    left: c.dx - labelW / 2,
                    top: c.dy - layout.outer / 2,
                    width: labelW,
                    child: MouseRegion(
                      cursor: onTap == null
                          ? MouseCursor.defer
                          : SystemMouseCursors.click,
                      onEnter: onHover == null ? null : (_) => onHover!(t.id),
                      onExit: onHover == null ? null : (_) => onHover!(null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onTap == null ? null : () => onTap!(t.id),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.topCenter,
                              children: [
                                JourneyCircle(
                                  color: journeyTitleColor(t),
                                  icon: journeyIconFor(t, j),
                                  size: layout.circle,
                                  look: look,
                                  selected: selectedId == t.id,
                                  hovered: hoveredId == t.id,
                                  pulse: look == JourneyLook.current
                                      ? pulse
                                      : null,
                                ),
                                if (badge != null)
                                  Positioned(top: -6, child: badge),
                              ],
                            ),
                            // The name as a plate hooked onto the bubble.
                            Transform.translate(
                              offset: Offset(0, -layout.circle * 0.2),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  JourneyNameplate(
                                    name: t.name,
                                    color: journeyTitleColor(t),
                                    look: look,
                                    selected: selectedId == t.id,
                                    small: layout.circle < 70,
                                  ),
                                  if (caption != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      caption,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}
