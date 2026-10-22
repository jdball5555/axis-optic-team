// Shared look for the phone app: every page opens on a deep crimson-to-indigo
// gradient header with white type (it shrinks into a bar that stays when you
// scroll), and its content sits on tiles that slide up over the header. The
// header is the only gradient: the rest is layered grays, solid inverse
// pills for what's picked, and red as a small solid accent.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/store_settings_model.dart';
import '../../models/user_model.dart';

// =============================================================================
// Brand and theme: one deep gradient (the header), everything else in grays
// =============================================================================

class MBrand {
  static const red = Color(0xFFE8304B);
  static const blue = Color(0xFF3F6BFF);

  /// The page header (and the bar it shrinks into): deep crimson into wine
  /// into deep indigo. The only gradient in the app.
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC3132F), Color(0xFF6B1446), Color(0xFF19247E)],
    stops: [0, 0.5, 1],
  );

  /// Red into blue (the website's "View as team member" button).
  static const accent = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [red, blue],
  );
}

/// The phone app's grays, darkest to lightest (light mode flips them).
class _Grays {
  const _Grays({
    required this.bg,
    required this.band,
    required this.card,
    required this.raised,
    required this.sunken,
    required this.line,
    required this.inverse,
    required this.onInverse,
  });
  final Color bg, band, card, raised, sunken, line, inverse, onInverse;

  static const dark = _Grays(
    bg: Color(0xFF0D0E12),
    band: Color(0xFF17191F),
    card: Color(0xFF1D2027),
    raised: Color(0xFF2A2D36),
    sunken: Color(0xFF111216),
    line: Color(0xFF2E313B),
    inverse: Color(0xFFF4F5F7),
    onInverse: Color(0xFF0D0E12),
  );
  static const light = _Grays(
    bg: Color(0xFFE5E7ED),
    band: Color(0xFFF2F3F6),
    card: Color(0xFFFFFFFF),
    raised: Color(0xFFEEF0F4),
    sunken: Color(0xFFE9EBF0),
    line: Color(0xFFD8DBE3),
    inverse: Color(0xFF15171C),
    onInverse: Color(0xFFFFFFFF),
  );

  static _Grays of(ThemeData theme) =>
      theme.brightness == Brightness.dark ? dark : light;
}

/// The phone app's surfaces: layered grays so pages aren't just black and
/// the gradient header.
ThemeData mobileTheme(ThemeData base) {
  final g = _Grays.of(base);
  final dark = base.brightness == Brightness.dark;
  return base.copyWith(
    scaffoldBackgroundColor: g.bg,
    cardColor: g.card,
    canvasColor: g.card,
    dividerColor: g.line,
    colorScheme: base.colorScheme.copyWith(
      surface: g.card,
      primary: MBrand.red,
      secondary: MBrand.blue,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: MBrand.red),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: g.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: g.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: dark ? g.raised : g.inverse,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      actionTextColor: const Color(0xFFFF8094),
    ),
  );
}

/// Gives everything under it the phone app's look (pages, sheets, dialogs).
class MobileTheme extends StatelessWidget {
  const MobileTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: mobileTheme(Theme.of(context)), child: child);
}

// =============================================================================
// Colors and text helpers
// =============================================================================

class MColors {
  MColors(BuildContext context) : theme = Theme.of(context);
  final ThemeData theme;

  _Grays get _g => _Grays.of(theme);

  Color get bg => theme.scaffoldBackgroundColor;
  Color get card => theme.cardColor;
  Color get line => theme.dividerColor;

  /// A lighter gray than [card] (chips, icon squares, nested tiles).
  Color get raised => _g.raised;

  /// A darker gray than [card] (inset areas).
  Color get sunken => _g.sunken;

  /// The full-width bands between parts of a page.
  Color get band => _g.band;

  /// Picked things: white on dark, near-black on light, and what's on it.
  Color get inverse => _g.inverse;
  Color get onInverse => _g.onInverse;
  Color get text => theme.textTheme.bodyLarge?.color ?? Colors.white;
  Color get title => theme.textTheme.titleLarge?.color ?? text;
  Color get muted => theme.textTheme.bodySmall?.color ?? Colors.grey;
  bool get light => theme.brightness == Brightness.light;
}

/// A title's color from store settings (blue when none is set).
Color titleColor(String? title, StoreSettingsModel? settings) {
  if (title == null || settings == null) return AppTheme.blue;
  final conf =
      settings.titles.where((t) => t.name == title).firstOrNull ??
      settings.tags.where((t) => t.name == title).firstOrNull;
  if (conf == null || conf.color == 'Color') return AppTheme.blue;
  final c = AppTheme.getColorFromName(conf.color);
  return c == Colors.grey ? AppTheme.blue : c;
}

/// An additional tag's color from store settings.
Color tagColor(String tag, StoreSettingsModel? settings) {
  final conf = settings?.tags.where((t) => t.name == tag).firstOrNull;
  if (conf == null || conf.color == 'Color') return AppTheme.blue;
  final c = AppTheme.getColorFromName(conf.color);
  return c == Colors.grey ? AppTheme.blue : c;
}

/// "Jamie" (preferred name first) / "Jamie Reyes".
String firstNameOf(UserModel? u) {
  if (u == null) return '';
  final p = u.preferredName?.trim() ?? '';
  return p.isNotEmpty ? p : (u.firstName ?? '').trim();
}

String fullNameOf(UserModel? u) {
  if (u == null) return 'Unknown';
  final name = [
    firstNameOf(u),
    (u.lastName ?? '').trim(),
  ].where((s) => s.isNotEmpty).join(' ');
  return name.isEmpty ? 'Unnamed' : name;
}

String initialsOf(UserModel? u) {
  final f = firstNameOf(u);
  final l = (u?.lastName ?? '').trim();
  final s = '${f.isEmpty ? '' : f[0]}${l.isEmpty ? '' : l[0]}'.toUpperCase();
  return s.isEmpty ? '?' : s;
}

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Good evening';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// "Monday, October 12"
String longDate(DateTime d) =>
    '${weekdayNames[d.weekday - 1]}, ${monthNames[d.month - 1]} ${d.day}';

/// "Mon, Oct 12"
String shortDate(DateTime d) =>
    '${weekdayShort[d.weekday - 1]}, ${monthShort[d.month - 1]} ${d.day}';

/// "Today", "Tomorrow", "Yesterday" or "Mon, Oct 12".
String relativeDay(DateTime d) {
  final today = dateOnly(DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return shortDate(d);
}

/// "Oct 12 – 18" / "Oct 26 – Nov 1"
String weekRange(DateTime start) {
  final end = addDays(start, 6);
  final a = '${monthShort[start.month - 1]} ${start.day}';
  return start.month == end.month
      ? '$a – ${end.day}'
      : '$a – ${monthShort[end.month - 1]} ${end.day}';
}

DateTime? parseDateKey(String? key) {
  if (key == null || key.length < 10) return null;
  return DateTime.tryParse(key.substring(0, 10));
}

/// "Oct 12, 2026"
String mediumDate(DateTime d) =>
    '${monthShort[d.month - 1]} ${d.day}, ${d.year}';

/// "2 yrs, 3 mos" since [start].
String tenureSince(DateTime start, {DateTime? now}) {
  final n = now ?? DateTime.now();
  var months = (n.year - start.year) * 12 + n.month - start.month;
  if (n.day < start.day) months--;
  if (months < 0) return 'Starts ${mediumDate(start)}';
  final y = months ~/ 12;
  final m = months % 12;
  if (y == 0 && m == 0) {
    final days = dateOnly(n).difference(dateOnly(start)).inDays;
    return days <= 1 ? 'New this week' : '$days days';
  }
  return [
    if (y > 0) '$y ${y == 1 ? 'yr' : 'yrs'}',
    if (m > 0) '$m ${m == 1 ? 'mo' : 'mos'}',
  ].join(', ');
}

/// A permit's state: label and color.
({String label, Color color, bool ok}) permitStatus(DateTime? expires) {
  if (expires == null) {
    return (label: 'No permit on file', color: AppTheme.red, ok: false);
  }
  final days = dateOnly(expires).difference(dateOnly(DateTime.now())).inDays;
  if (days < 0) return (label: 'Expired', color: AppTheme.red, ok: false);
  if (days == 0)
    return (label: 'Expires today', color: AppTheme.orange, ok: false);
  if (days <= 30) {
    return (
      label: 'Expires in $days ${days == 1 ? 'day' : 'days'}',
      color: AppTheme.orange,
      ok: false,
    );
  }
  return (label: 'Valid', color: AppTheme.green, ok: true);
}

// =============================================================================
// Building blocks
// =============================================================================

/// The deep gradient block at the top of a page: white text, a few crisp
/// diagonal lines and soft glows. The page's tiles slide up over its bottom.
class MHero extends StatelessWidget {
  const MHero({super.key, required this.child, this.bottom = 52});
  final Widget child;

  /// Room under the content (the tiles below overlap part of it).
  final double bottom;

  /// Whether [context] is on a hero (widgets switch to white-on-color).
  static bool on(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OnHero>() != null;

  /// White text and icons for what sits on the gradient.
  static Widget onGradient(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    return _OnHero(
      child: Theme(
        data: theme.copyWith(
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: IconTheme.merge(
            data: const IconThemeData(color: Colors.white),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hero = DecoratedBox(
      decoration: const BoxDecoration(gradient: MBrand.hero),
      child: CustomPaint(
        painter: const _HeroPainter(),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.paddingOf(context).top + 16,
            20,
            bottom,
          ),
          child: onGradient(context, child),
        ),
      ),
    );
    // Dark: the glows fade out into the page. Light: a crisp edge.
    return Theme.of(context).brightness == Brightness.light
        ? ClipRect(child: hero)
        : hero;
  }
}

class _OnHero extends InheritedWidget {
  const _OnHero({required super.child});
  @override
  bool updateShouldNotify(_OnHero old) => false;
}

class _HeroPainter extends CustomPainter {
  const _HeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Soft glows: blue top right, red bottom left.
    void glow(Offset c, double r, Color color) => canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    glow(
      Offset(size.width * 0.92, size.height * 0.05),
      size.width * 0.6,
      const Color(0x664F7BFF),
    );
    glow(
      Offset(size.width * 0.05, size.height * 1.0),
      size.width * 0.55,
      const Color(0x44FF3B5C),
    );
    // Hard diagonal lines.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (final x in [0.58, 0.7, 0.82]) {
      canvas.drawLine(
        Offset(size.width * x, size.height),
        Offset(size.width * x + size.height * 0.9, 0),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeroPainter old) => false;
}

/// The deep gradient behind the top of a page: a few crisp diagonal lines
/// and soft glows ([height] tall).
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final panel = SizedBox(
      height: height,
      child: const DecoratedBox(
        decoration: BoxDecoration(gradient: MBrand.hero),
        child: CustomPaint(painter: _HeroPainter(), child: SizedBox.expand()),
      ),
    );
    // Dark: the glows fade out into the page. Light: a crisp edge.
    return Theme.of(context).brightness == Brightness.light
        ? ClipRect(child: panel)
        : panel;
  }
}

/// The top [visible] pixels of a [_HeroPanel] of [height] (for the bar, so
/// it lines up with the panel under it).
class _HeroSlice extends StatelessWidget {
  const _HeroSlice({required this.height, required this.visible});
  final double height;
  final double visible;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: SizedBox(
      height: visible,
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: height,
        maxHeight: height,
        child: SizedBox(
          height: height,
          child: const DecoratedBox(
            decoration: BoxDecoration(gradient: MBrand.hero),
            child: CustomPaint(
              painter: _HeroPainter(),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A page: the gradient header (big white title, optional subtitle and
/// actions), then the content as tiles that overlap the bottom of it.
///
/// Scrolling: the colored panel stays put while the tiles slide up over it,
/// pushing the header's text up into a slim bar at the top; once the tiles
/// reach the bar, the rest of the panel scrolls up under it. The bar stays.
class MPage extends StatefulWidget {
  const MPage({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.header,
    this.compactTitle,
    this.compactLeading,
    required this.children,
    this.onRefresh,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;

  /// Replaces the standard title block (drawn on the gradient).
  final Widget? header;

  /// The bar's title once scrolled (default [title]) and what's before it.
  final String? compactTitle;
  final Widget? compactLeading;

  /// Page content. [MBand]s run edge to edge; everything else is inset.
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  /// How far the panel reaches under the first tiles.
  static const overlap = 30.0;

  /// The bar's height under the status bar.
  static const barHeight = 58.0;

  @override
  State<MPage> createState() => _MPageState();
}

class _MPageState extends State<MPage> {
  /// How far the page is scrolled.
  final _scroll = ValueNotifier<double>(0);

  /// The header block's height (measured; a guess until then).
  double? _headerHeight;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical)
      _scroll.value = n.metrics.pixels;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final top = MediaQuery.paddingOf(context).top;
    final barH = top + MPage.barHeight;
    final headerH = _headerHeight ?? top + 140;
    final panelH = headerH + MPage.overlap;
    // The panel holds still until the tiles reach the bar, then follows.
    double panelShift(double s) =>
        (s - (headerH - barH)).clamp(0.0, panelH - barH);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(20, top + 16, 20, 52 - MPage.overlap),
      child: MHero.onGradient(
        context,
        w.header ??
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (w.eyebrow != null) ...[
                        MEyebrow(w.eyebrow!),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        w.title,
                        style: const TextStyle(
                          fontSize: 34,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: Colors.white,
                        ),
                      ),
                      if (w.subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          w.subtitle!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?w.trailing,
              ],
            ),
      ),
    );

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // The header scrolls with the tiles (they push it up) and fades as
        // it goes into the bar.
        _SizeReporter(
          onSize: (size) {
            if (mounted && (size.height - (_headerHeight ?? 0)).abs() > 0.5) {
              setState(() => _headerHeight = size.height);
            }
          },
          child: ValueListenableBuilder<double>(
            valueListenable: _scroll,
            child: header,
            builder: (context, s, child) =>
                Opacity(opacity: (1 - s / 60).clamp(0.0, 1.0), child: child),
          ),
        ),
        for (final child in w.children)
          child is MBand
              ? child
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: child,
                ),
      ],
    );

    final title = w.compactTitle ?? w.title;
    return ConstrainedPage(
      child: Stack(
        children: [
          // The colored panel, under everything.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _scroll,
              builder: (context, s, _) => Transform.translate(
                offset: Offset(0, -panelShift(s)),
                // Pulled down past the top: it stretches.
                child: _HeroPanel(height: panelH + math.max(0.0, -s)),
              ),
            ),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: w.onRefresh == null
                ? list
                : RefreshIndicator(
                    onRefresh: w.onRefresh!,
                    color: MBrand.red,
                    child: list,
                  ),
          ),
          // The bar, over everything.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _scroll,
              builder: (context, s, _) {
                final t = ((s - 30) / 40).clamp(0.0, 1.0);
                final docked = panelShift(s) > 0;
                return IgnorePointer(
                  // Nothing to tap until something scrolls under it.
                  ignoring: s <= 0,
                  child: SizedBox(
                    height: barH,
                    child: Stack(
                      children: [
                        // Solid as soon as anything scrolls up under it (it
                        // matches the panel, so it doesn't show until then).
                        if (s > 0)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                boxShadow: docked
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 14,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              // Solid: taps don't reach what's hidden under it.
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                child: _HeroSlice(
                                  height: panelH,
                                  visible: barH,
                                ),
                              ),
                            ),
                          ),
                        // The title slides in as the header's goes under.
                        Padding(
                          padding: EdgeInsets.fromLTRB(20, top + 9, 12, 9),
                          child: IgnorePointer(
                            ignoring: t < 0.6,
                            child: Opacity(
                              opacity: t,
                              child: Transform.translate(
                                offset: Offset(0, 10 * (1 - t)),
                                child: MHero.onGradient(
                                  context,
                                  Row(
                                    children: [
                                      if (w.compactLeading != null) ...[
                                        w.compactLeading!,
                                        const SizedBox(width: 10),
                                      ],
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.4,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      ?w.trailing,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Tells [onSize] its child's size after each layout that changes it.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);
  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _reported) {
      _reported = size;
      final s = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
    }
  }
}

/// A full-width band in a lighter gray, with hard edges: breaks a page into
/// parts. Its content is inset like the rest of the page.
class MBand extends StatelessWidget {
  const MBand({
    super.key,
    required this.child,
    this.title,
    this.margin = const EdgeInsets.only(top: 26),
  });
  final Widget child;
  final String? title;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      decoration: BoxDecoration(
        color: c.band,
        border: Border.symmetric(horizontal: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            MSection(title!, top: 14)
          else
            const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Keeps pages a comfortable width on tablets and desktops.
class ConstrainedPage extends StatelessWidget {
  const ConstrainedPage({super.key, required this.child, this.maxWidth = 680});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Small spaced-out uppercase label.
class MEyebrow extends StatelessWidget {
  const MEyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.8,
      color:
          color ??
          (MHero.on(context)
              ? Colors.white.withValues(alpha: 0.72)
              : MColors(context).muted),
    ),
  );
}

/// Section heading: a short red line, the label, an optional action.
class MSection extends StatelessWidget {
  const MSection(this.title, {super.key, this.action, this.top = 26});
  final String title;
  final Widget? action;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 12, left: 2),
    child: Row(
      children: [
        Container(width: 12, height: 3, color: MBrand.red),
        const SizedBox(width: 8),
        Expanded(
          child: MEyebrow(
            title,
            color: MColors(context).title.withValues(alpha: 0.85),
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// A tile: hairline edge, soft depth. [tone] picks the gray ([MTone.raised]
/// for a lighter one); [glow] gives it a colored edge and glow (the one
/// thing on a page to look at first).
class MCard extends StatelessWidget {
  const MCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
    this.color,
    this.glow,
    this.tone = MTone.card,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;
  final Color? glow;
  final MTone tone;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final fill =
        color ??
        switch (tone) {
          MTone.card => c.card,
          MTone.raised => c.raised,
          MTone.sunken => c.sunken,
        };
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          if (glow != null)
            BoxShadow(
              color: glow!.withValues(alpha: c.light ? 0.18 : 0.22),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 10),
            ),
          if (tone != MTone.sunken)
            BoxShadow(
              color: Colors.black.withValues(alpha: c.light ? 0.06 : 0.3),
              blurRadius: c.light ? 16 : 12,
              offset: const Offset(0, 5),
            ),
        ],
      ),
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color:
                borderColor ??
                (glow != null ? glow!.withValues(alpha: 0.7) : c.line),
            width: borderColor != null || glow != null ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Which gray a tile is.
enum MTone { card, raised, sunken }

/// Tinted pill, the same recipe as the app's title and tag bubbles. On the
/// gradient header it turns into frosted glass with a colored dot.
class MPill extends StatelessWidget {
  const MPill(
    this.label, {
    super.key,
    required this.color,
    this.icon,
    this.large = false,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool large;

  /// Solid color with white text (for warnings).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final glass = MHero.on(context) && !filled;
    final fg = glass || filled ? Colors.white : AppTheme.onTint(color);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 9,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: glass
            ? Colors.white.withValues(alpha: 0.14)
            : (filled ? color : AppTheme.tint(color)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: glass
              ? Colors.white.withValues(alpha: 0.32)
              : (filled ? color : AppTheme.edge(color)),
          width: large ? 1.4 : 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glass && icon == null) ...[
            Container(
              width: large ? 8 : 7,
              height: large ? 8 : 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.8),
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: large ? 15 : 13, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: large ? 13.5 : 11.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round initials in a person's title color (solid with a white ring on
/// the header).
class MAvatar extends StatelessWidget {
  const MAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.size = 42,
  });

  final String initials;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final onHero = MHero.on(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onHero ? color : AppTheme.tint(color),
        border: Border.all(
          color: onHero
              ? Colors.white.withValues(alpha: 0.9)
              : AppTheme.edge(color),
          width: size > 60 ? 2.5 : 1.4,
        ),
        boxShadow: onHero
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
          color: onHero
              ? (color.computeLuminance() > 0.55
                    ? Color.lerp(color, Colors.black, 0.7)
                    : Colors.white)
              : AppTheme.onTint(color),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A small rounded square in a lighter gray with an icon in a color (red
/// unless given).
class MIconBadge extends StatelessWidget {
  const MIconBadge(this.icon, {super.key, this.color, this.size = 36});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final tint = color ?? MBrand.red;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color == null ? c.raised : AppTheme.tint(tint),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(
          color: color == null
              ? c.line
              : AppTheme.edge(tint).withValues(alpha: 0.6),
        ),
      ),
      child: Icon(
        icon,
        size: size * 0.52,
        color: color == null ? tint : AppTheme.onTint(tint),
      ),
    );
  }
}

/// A number with a label, for the stat grids.
class MStat extends StatelessWidget {
  const MStat({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.color,
    this.onTap,
    this.tone = MTone.card,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  final MTone tone;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return MCard(
      onTap: onTap,
      tone: tone,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
              ),
              if (icon != null)
                Icon(
                  icon,
                  size: 18,
                  color: color == null ? c.muted : AppTheme.onTint(color!),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                color: color == null ? c.title : AppTheme.onTint(color!),
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-column grid of stat tiles.
class MStatGrid extends StatelessWidget {
  const MStatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

/// Icon, title and a line of text, for empty states.
class MEmpty extends StatelessWidget {
  const MEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return MCard(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 20 : 40,
        horizontal: 20,
      ),
      child: Column(
        children: [
          MIconBadge(icon, color: c.muted, size: compact ? 42 : 56),
          SizedBox(height: compact ? 12 : 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w800,
              color: c.title,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Segmented switch (Shifts / Availability / Time off): the picked one as a
/// solid inverse pill (white on dark, black on light).
class MSegmented<T> extends StatelessWidget {
  const MSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.light ? 0.06 : 0.3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? c.inverse : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: v == value ? c.onInverse : c.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Label / value row for detail lists.
class MField extends StatelessWidget {
  const MField(
    this.label,
    this.value, {
    super.key,
    this.valueWidget,
    this.last = false,
  });
  final String label;
  final String? value;
  final Widget? valueWidget;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final v = value == null || value!.trim().isEmpty ? '—' : value!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.6))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: c.muted),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  valueWidget ??
                  Text(
                    v,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin progress bar.
class MProgress extends StatelessWidget {
  const MProgress({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
  });
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: c.raised),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0).toDouble(),
            child: Container(height: height, color: color),
          ),
        ],
      ),
    );
  }
}

/// Primary button in solid red (or a color of its own).
class MButton extends StatelessWidget {
  const MButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.secondary = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool secondary;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final enabled = onPressed != null && !busy;
    final fill = secondary ? c.raised : (color ?? MBrand.red);
    final fg = secondary ? c.title : Colors.white;
    final child = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: secondary ? MBrand.red : Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: fg,
                  ),
                ),
              ),
            ],
          );
    final radius = BorderRadius.circular(16);
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: secondary ? BorderSide(color: c.line) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: SizedBox(height: 52, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Snackbar helper.
void mSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}

/// A sub-page with a back button, pushed over the tabs (its bar is the
/// header's gradient).
class MSubPage extends StatelessWidget {
  const MSubPage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.bottom,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  /// Pinned under the content (e.g. a Save button).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    return MobileTheme(
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: MBrand.hero),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          actions: actions,
        ),
        body: ConstrainedPage(child: child),
        bottomNavigationBar: bottom == null
            ? null
            : SafeArea(
                top: false,
                child: ConstrainedPage(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: bottom,
                  ),
                ),
              ),
      ),
    );
  }
}

/// The week's days as tappable tiles, with arrows for other weeks (the
/// picked day as a solid inverse tile).
class MDayStrip extends StatelessWidget {
  const MDayStrip({
    super.key,
    required this.weekStart,
    required this.selected,
    required this.onSelect,
    required this.onWeek,
  });

  final DateTime weekStart;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onWeek;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final today = dateOnly(DateTime.now());
    return MCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          _StripArrow(icon: Icons.chevron_left, onTap: () => onWeek(-1)),
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final d = addDays(weekStart, i);
                  final isSel = d == selected;
                  final isToday = d == today;
                  return GestureDetector(
                    onTap: () => onSelect(d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSel ? c.inverse : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            weekdayShort[d.weekday - 1]
                                .substring(0, 2)
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: isSel
                                  ? c.onInverse.withValues(alpha: 0.7)
                                  : c.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: isSel ? c.onInverse : c.title,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isToday ? MBrand.red : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          _StripArrow(icon: Icons.chevron_right, onTap: () => onWeek(1)),
        ],
      ),
    );
  }
}

class _StripArrow extends StatelessWidget {
  const _StripArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
      child: Icon(icon, color: MColors(context).muted),
    ),
  );
}
