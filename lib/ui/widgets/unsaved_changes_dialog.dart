import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

enum UnsavedChoice { save, discard }

/// Asks whether to save or discard unsaved changes. Returns null on Cancel.
Future<UnsavedChoice?> showUnsavedChangesDialog(BuildContext context) {
  final theme = Theme.of(context);
  return showDialog<UnsavedChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: theme.cardColor,
      title: Text(
        'Unsaved Changes',
        style: TextStyle(color: theme.textTheme.titleLarge?.color),
      ),
      content: Text(
        'You have unsaved changes. Do you want to save or discard them?',
        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(UnsavedChoice.discard),
          child: const Text('Discard', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(UnsavedChoice.save),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save Changes'),
        ),
      ],
    ),
  );
}
