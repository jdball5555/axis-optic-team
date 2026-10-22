import 'package:flutter/material.dart';
import '../../models/store_settings_model.dart';
import '../../core/theme/app_theme.dart';

class SettingsEmployeeDataSummaryCard extends StatelessWidget {
  final StoreSettingsModel settings;
  final Function(StoreSettingsModel) onUpdate;
  final Widget? copyButton;

  const SettingsEmployeeDataSummaryCard({
    super.key,
    required this.settings,
    required this.onUpdate,
    this.copyButton,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final titleWidget = Text(
                      'Employee Data Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    );
                    final manageButton = OutlinedButton(
                      onPressed: () => _showManageSummaryDialog(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        side: BorderSide(color: AppTheme.accent),
                      ),
                      child: const Text('Manage Summary'),
                    );

                    if (constraints.maxWidth < 400) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          titleWidget,
                          const SizedBox(height: 8),
                          manageButton,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: titleWidget),
                        const SizedBox(width: 8),
                        manageButton,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Select the fields that will be included in the Employee Data Summary pop-up on the team member profile page.',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                if (settings.employeeDataSummaryFields.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: settings.employeeDataSummaryFields.map((field) {
                      return Chip(
                        label: Text(field),
                        backgroundColor: Theme.of(
                          context,
                        ).scaffoldBackgroundColor,
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      );
                    }).toList(),
                  ),
                ],
                if (copyButton != null) const SizedBox(height: 24),
              ],
            ),
          ),
          if (copyButton != null)
            Positioned(bottom: 0, right: 0, child: copyButton!),
        ],
      ),
    );
  }

  void _showManageSummaryDialog(BuildContext context) {
    final List<String> allFields = [
      'First Name',
      'Last Name',
      'Preferred Name',
      'Title',
      'Start Date',
      'End Date',
      'Store',
      'Position',
      'Designation',
      'Additional Tags',
      'Working Time',
      'Avg Shifts / Wk',
      'Pay (\$ / Hr)',
      'Food Permit Exp.',
      'Manager Permit Exp.',
      'General Notes & Comments',
      'Hiring Notes',
    ];

    List<String> selectedFields = List.from(settings.employeeDataSummaryFields);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text(
                'Manage Employee Data Summary',
                style: TextStyle(
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              content: SizedBox(
                width: 400,
                height: (MediaQuery.sizeOf(context).height - 120).clamp(
                  200.0,
                  450.0,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: allFields.map((field) {
                      return CheckboxListTile(
                        title: Text(
                          field,
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        value: selectedFields.contains(field),
                        activeColor: AppTheme.accent,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              selectedFields.add(field);
                            } else {
                              selectedFields.remove(field);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    onUpdate(
                      settings.copyWith(
                        employeeDataSummaryFields: selectedFields,
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
