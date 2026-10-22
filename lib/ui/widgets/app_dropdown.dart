import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Clean custom checkbox matching the design:
/// rounded corners (~4px), solid blue fill (#007AFF) with crisp white checkmark,
/// or clean light border when unchecked.
class AppCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final double size;

  const AppCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 18.0,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF007AFF);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: MouseRegion(
        cursor: onChanged != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: value ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: value ? activeColor : Colors.grey.shade400,
              width: 1.8,
            ),
          ),
          child: value
              ? Icon(
                  Icons.check,
                  size: size * 0.78,
                  color: Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

/// A standard dropdown widget that renders a regular DropdownButtonFormField,
/// ensuring consistent styling on the outside and inside across the app.
class AppDropdown<T> extends StatelessWidget {
  final String? label;
  final T? value;
  final List<T> items;
  final ValueChanged<T?>? onChanged;
  final String Function(T item)? itemToString;
  final Widget Function(T item)? itemBuilder;
  final String placeholder;
  final bool enabled;
  final double? width;
  final InputDecoration? decoration;
  final TextStyle? style;
  final EdgeInsetsGeometry? padding;

  const AppDropdown({
    super.key,
    this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemToString,
    this.itemBuilder,
    this.placeholder = 'Select…',
    this.enabled = true,
    this.width,
    this.decoration,
    this.style,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dropdown = DropdownButtonFormField<T>(
      value: value,
      items: items.map((item) {
        return DropdownMenuItem<T>(
          value: item,
          child: itemBuilder != null
              ? itemBuilder!(item)
              : Text(
                  itemToString != null ? itemToString!(item) : item.toString(),
                  style: style ??
                      TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                ),
        );
      }).toList(),
      onChanged: enabled ? onChanged : null,
      dropdownColor: theme.cardColor,
      decoration: decoration ?? const InputDecoration(),
      hint: Text(placeholder),
      style: style ??
          TextStyle(
            fontSize: 14,
            color: theme.textTheme.bodyLarge?.color,
          ),
    );

    final sized = width != null ? SizedBox(width: width, child: dropdown) : dropdown;

    if (label != null && label!.isNotEmpty && (decoration == null || decoration?.labelText == null)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label!,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 4),
          sized,
        ],
      );
    }

    return sized;
  }
}

/// A multi-select dropdown that looks identical on the outside and inside
/// to a regular dropdown, with the only difference being a checkbox next to each item
/// and staying open so the user can select multiple options.
class AppMultiSelectDropdown<T> extends StatefulWidget {
  final String? label;
  final List<T> options;
  final List<T> selected;
  final ValueChanged<List<T>> onChanged;
  final String Function(T item)? itemToString;
  final String allLabel;
  final String emptyText;
  final bool showAllOption;
  final bool enabled;
  final double? width;
  final double? minPopupWidth;
  final InputDecoration? decoration;
  final TextStyle? style;
  final EdgeInsetsGeometry? padding;

  const AppMultiSelectDropdown({
    super.key,
    this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.itemToString,
    this.allLabel = 'All',
    this.emptyText = '',
    this.showAllOption = false,
    this.enabled = true,
    this.width,
    this.minPopupWidth,
    this.decoration,
    this.style,
    this.padding,
  });

  @override
  State<AppMultiSelectDropdown<T>> createState() => _AppMultiSelectDropdownState<T>();
}

class _AppMultiSelectDropdownState<T> extends State<AppMultiSelectDropdown<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  late List<T> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<T>.from(widget.selected);
  }

  @override
  void didUpdateWidget(AppMultiSelectDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _selected = List<T>.from(widget.selected);
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
    super.dispose();
  }

  void _toggleMenu() {
    if (!widget.enabled || (widget.options.isEmpty && !widget.showAllOption)) return;
    if (_isOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    _closeMenu();
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final spaceBelow = screenHeight - (offset.dy + size.height);
    final showAbove = spaceBelow < 220 && offset.dy > spaceBelow;

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            // Backdrop to dismiss on outside click
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeMenu,
              ),
            ),
            Positioned(
              width: math.max(widget.minPopupWidth ?? 0, size.width),
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: showAbove
                    ? const Offset(0, -220)
                    : Offset(0, size.height + 2),
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.2),
                  color: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: _buildList(context),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted && _isOpen) {
      setState(() => _isOpen = false);
    }
  }

  void _toggleOption(T option) {
    final newSelected = List<T>.from(_selected);
    if (newSelected.contains(option)) {
      newSelected.remove(option);
    } else {
      newSelected.add(option);
    }
    setState(() {
      _selected = newSelected;
    });
    widget.onChanged(newSelected);
    _overlayEntry?.markNeedsBuild();
  }

  void _toggleAll() {
    final allSelected = widget.options.isNotEmpty &&
        widget.options.every((opt) => _selected.contains(opt));
    final newSelected = allSelected ? <T>[] : List<T>.from(widget.options);
    setState(() {
      _selected = newSelected;
    });
    widget.onChanged(newSelected);
    _overlayEntry?.markNeedsBuild();
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = widget.options.isNotEmpty &&
        widget.options.every((opt) => _selected.contains(opt));

    final totalCount = widget.options.length + (widget.showAllOption ? 1 : 0);

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: totalCount,
      itemBuilder: (ctx, index) {
        if (widget.showAllOption && index == 0) {
          return InkWell(
            onTap: _toggleAll,
            hoverColor: theme.hoverColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  AppCheckbox(
                    value: allSelected,
                    onChanged: (_) => _toggleAll(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.allLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final optIndex = widget.showAllOption ? index - 1 : index;
        final option = widget.options[optIndex];
        final isChecked = _selected.contains(option);
        final text = widget.itemToString != null
            ? widget.itemToString!(option)
            : option.toString();

        return InkWell(
          onTap: () => _toggleOption(option),
          hoverColor: theme.hoverColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                AppCheckbox(
                  value: isChecked,
                  onChanged: (_) => _toggleOption(option),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = widget.options.isNotEmpty &&
        widget.options.every((opt) => _selected.contains(opt));

    String displayText;
    if (_selected.isEmpty) {
      displayText = widget.emptyText.isNotEmpty ? widget.emptyText : 'Select…';
    } else if (allSelected && widget.showAllOption) {
      displayText = widget.allLabel;
    } else {
      displayText = _selected
          .map((e) => widget.itemToString != null ? widget.itemToString!(e) : e.toString())
          .join(', ');
    }

    final isNone = _selected.isEmpty;
    final textStyle = widget.style ??
        TextStyle(
          fontSize: 14,
          fontWeight: isNone ? FontWeight.normal : FontWeight.w500,
          color: isNone ? Colors.grey : theme.textTheme.bodyLarge?.color,
        );

    final baseDecoration = widget.decoration ?? const InputDecoration();
    final effectiveDecoration = baseDecoration.copyWith(
      suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      suffixIcon: Icon(
        Icons.arrow_drop_down,
        color: theme.brightness == Brightness.light
            ? Colors.grey.shade700
            : Colors.white70,
      ),
    );

    final height = math.max(
      MediaQuery.textScalerOf(context).scale(textStyle.fontSize ?? 14),
      24.0,
    );

    final trigger = CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: widget.enabled ? _toggleMenu : null,
        child: InputDecorator(
          decoration: effectiveDecoration,
          isEmpty: false,
          child: SizedBox(
            height: height,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                displayText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          ),
        ),
      ),
    );

    final sized = widget.width != null ? SizedBox(width: widget.width, child: trigger) : trigger;

    if (widget.label != null &&
        widget.label!.isNotEmpty &&
        (widget.decoration == null || widget.decoration?.labelText == null)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 4),
          sized,
        ],
      );
    }

    return sized;
  }
}
