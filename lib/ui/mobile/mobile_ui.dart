// Shared look for the phone app: big quiet headings, soft cards and tinted
// pills, in the same colors as the rest of Axis Team.

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/store_settings_model.dart';
import '../../models/user_model.dart';

// =============================================================================
// Colors and text helpers
// =============================================================================

class MColors {
  MColors(BuildContext context) : theme = Theme.of(context);
  final ThemeData theme;

  Color get bg => theme.scaffoldBackgroundColor;
  Color get card => theme.cardColor;
  Color get line => theme.dividerColor;
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
  final name = [firstNameOf(u), (u.lastName ?? '').trim()]
      .where((s) => s.isNotEmpty)
      .join(' ');
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
  if (days == 0) return (label: 'Expires today', color: AppTheme.orange, ok: false);
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

/// A page: big title, optional subtitle and actions, then content.
class MPage extends StatelessWidget {
  const MPage({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.header,
    required this.children,
    this.onRefresh,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;

  /// Replaces the standard title block.
  final Widget? header;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 18,
        20,
        32,
      ),
      children: [
        header ??
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) ...[
                        MEyebrow(eyebrow!),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 32,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: c.title,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 14, color: c.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
        const SizedBox(height: 22),
        ...children,
      ],
    );
    return ConstrainedPage(
      child: onRefresh == null
          ? list
          : RefreshIndicator(
              onRefresh: onRefresh!,
              color: AppTheme.accent,
              child: list,
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

/// Small spaced-out uppercase label (like the website's section labels).
class MEyebrow extends StatelessWidget {
  const MEyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
      color: color ?? MColors(context).muted,
    ),
  );
}

/// Section heading with an optional action on the right.
class MSection extends StatelessWidget {
  const MSection(this.title, {super.key, this.action, this.top = 26});
  final String title;
  final Widget? action;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 10, left: 2),
    child: Row(
      children: [
        Expanded(child: MEyebrow(title)),
        ?action,
      ],
    ),
  );
}

/// A soft rounded card.
class MCard extends StatelessWidget {
  const MCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
    this.color,
    this.glow,
    this.radius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;

  /// A soft colored glow around the card.
  final Color? glow;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color: borderColor ?? c.line.withValues(alpha: c.light ? 1 : 0.7),
        width: borderColor != null ? 1.4 : 1,
      ),
    );
    return Container(
      decoration: glow == null
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: glow!.withValues(alpha: c.light ? 0.18 : 0.22),
                  blurRadius: 28,
                  spreadRadius: -4,
                ),
              ],
            ),
      child: Material(
        color: color ?? c.card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Tinted pill, the same recipe as the app's title and tag bubbles.
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
    final fg = filled ? Colors.white : AppTheme.onTint(color);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 9,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: filled ? color : AppTheme.tint(color),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? color : AppTheme.edge(color),
          width: large ? 1.6 : 1.3,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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

/// Round initials in a person's title color.
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
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppTheme.tint(color),
      border: Border.all(color: AppTheme.edge(color), width: size > 60 ? 2 : 1.4),
    ),
    child: Text(
      initials,
      style: TextStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w800,
        color: AppTheme.onTint(color),
        letterSpacing: 0.5,
      ),
    ),
  );
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
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = MColors(context);
    final accent = color ?? c.title;
    return MCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color ?? c.muted),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
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
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: accent,
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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 18 : 48, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: compact ? 46 : 64,
            height: compact ? 46 : 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.card,
              border: Border.all(color: c.line),
            ),
            child: Icon(icon, size: compact ? 22 : 28, color: c.muted),
          ),
          SizedBox(height: compact ? 10 : 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 15 : 18,
              fontWeight: FontWeight.w700,
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

/// Pill-shaped segmented switch (Shifts / Availability / Time off).
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? AppTheme.tint(AppTheme.accent) : null,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: v == value
                          ? AppTheme.edge(AppTheme.accent)
                          : Colors.transparent,
                      width: 1.3,
                    ),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: v == value ? AppTheme.onTint(AppTheme.accent) : c.muted,
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
  const MField(this.label, this.value, {super.key, this.valueWidget, this.last = false});
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
  const MProgress({super.key, required this.value, required this.color, this.height = 8});
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
          Container(height: height, color: c.line.withValues(alpha: 0.6)),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0).toDouble(),
            child: Container(height: height, color: color),
          ),
        ],
      ),
    );
  }
}

/// Primary button in the accent color.
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
    final accent = color ?? AppTheme.accent;
    final child = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: secondary ? accent : Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ],
          );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    if (secondary) {
      return OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size.fromHeight(50),
          side: BorderSide(color: c.line),
          shape: shape,
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape: shape,
        elevation: 0,
      ),
      child: child,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}

/// A sub-page with a back button, pushed over the tabs.
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
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: c.title,
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
    );
  }
}
