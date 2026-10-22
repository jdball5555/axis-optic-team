import 'package:flutter/material.dart';
import 'app_dropdown.dart';

export 'app_dropdown.dart';

/// A dropdown where several options can be checked.
/// Looks exactly like a [DropdownButtonFormField] with the same decoration
/// and dropdown styling; the menu has a checkbox next to each option and stays open
/// so multiple items can be checked.
class MultiSelectField extends StatelessWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final String emptyText;
  final String allLabel;
  final bool showAllOption;

  const MultiSelectField({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.style,
    this.emptyText = '',
    this.allLabel = '',
    this.showAllOption = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppMultiSelectDropdown<String>(
      options: options,
      selected: selected,
      onChanged: onChanged,
      decoration: decoration,
      style: style,
      emptyText: emptyText.isNotEmpty ? emptyText : (decoration.hintText ?? ''),
      allLabel: allLabel.isNotEmpty ? allLabel : 'All',
      showAllOption: showAllOption,
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
    return AppMultiSelectDropdown<String>(
      options: options,
      selected: selected,
      onChanged: onChanged,
      allLabel: 'All $label',
      emptyText: label,
      showAllOption: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: theme.cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
