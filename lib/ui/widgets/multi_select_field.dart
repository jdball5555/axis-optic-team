import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A dropdown where several options can be checked. The menu stays open
/// while you tick boxes; click outside to close it.
///
/// Looks exactly like a [DropdownButtonFormField] with the same
/// [decoration] (same height, underline and arrow); the menu just has a
/// checkbox by each option. Shows the picked ones separated by commas.
class MultiSelectField extends StatelessWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final String emptyText;

  const MultiSelectField({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.style,
    this.emptyText = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = style ?? theme.textTheme.titleMedium!;
    // Same as DropdownButtonFormField: dense button, arrow as suffix icon.
    final iconColor = theme.brightness == Brightness.light
        ? Colors.grey.shade700
        : Colors.white70;
    final effective = decoration.copyWith(
      suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      suffixIcon: Icon(Icons.arrow_drop_down, color: iconColor),
    );
    final height = math.max(
      MediaQuery.textScalerOf(context).scale(textStyle.fontSize ?? 14),
      24.0,
    );
    return _CheckboxMenu(
      options: options,
      selected: selected,
      onChanged: onChanged,
      builder: (context, toggle, picked) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: options.isEmpty ? null : toggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InputDecorator(
            decoration: effective,
            isEmpty: false,
            child: SizedBox(
              height: height,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  picked.isEmpty ? emptyText : picked.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A filter button (like the roster's filter dropdowns) where several
/// values can be checked. Empty = no filter.
class MultiSelectFilter extends StatelessWidget {
  final String label;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const MultiSelectFilter({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CheckboxMenu(
      options: options,
      selected: selected,
      onChanged: onChanged,
      builder: (context, toggle, picked) {
        final text = picked.isEmpty
            ? label
            : picked.length == 1
            ? '$label: ${picked.first}'
            : '$label (${picked.length})';
        return Material(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: options.isEmpty ? null : toggle,
            child: Container(
              height: 48,
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: picked.isEmpty ? FontWeight.normal : FontWeight.w600,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: theme.textTheme.bodySmall?.color),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The menu with a checkbox per option, under whatever [builder] draws.
class _CheckboxMenu extends StatefulWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final Widget Function(BuildContext, VoidCallback toggle, List<String> picked) builder;

  const _CheckboxMenu({
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.builder,
  });

  @override
  State<_CheckboxMenu> createState() => _CheckboxMenuState();
}

class _CheckboxMenuState extends State<_CheckboxMenu> {
  late List<String> _picked = [...widget.selected];

  @override
  void didUpdateWidget(_CheckboxMenu old) {
    super.didUpdateWidget(old);
    if (old.selected.join('\n') != widget.selected.join('\n')) {
      _picked = [...widget.selected];
    }
  }

  void _toggle(String option, bool on) {
    final options = widget.options.toSet().toList();
    setState(() {
      // Keep the options' order; keep picked ones that aren't options.
      _picked = [
        for (final o in options)
          if (o == option ? on : _picked.contains(o)) o,
        for (final o in _picked)
          if (!options.contains(o)) o,
      ];
    });
    widget.onChanged(_picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = widget.options.toSet().toList();
    return LayoutBuilder(
      builder: (context, constraints) => MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(theme.cardColor),
          minimumSize: WidgetStatePropertyAll(
            Size(constraints.maxWidth.isFinite ? constraints.maxWidth : 0, 0),
          ),
        ),
        menuChildren: [
          for (final o in options)
            CheckboxMenuButton(
              value: _picked.contains(o),
              closeOnActivate: false,
              onChanged: (v) => _toggle(o, v ?? false),
              child: Text(o),
            ),
        ],
        builder: (context, controller, _) => widget.builder(
          context,
          () => controller.isOpen ? controller.close() : controller.open(),
          _picked,
        ),
      ),
    );
  }
}
