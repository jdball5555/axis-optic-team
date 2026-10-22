import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../services/store_takeout_service.dart';

class SettingsTakeoutCard extends ConsumerStatefulWidget {
  final String storeId;
  final String? storeName;

  const SettingsTakeoutCard({
    super.key,
    required this.storeId,
    this.storeName,
  });

  @override
  ConsumerState<SettingsTakeoutCard> createState() => _SettingsTakeoutCardState();
}

class _SettingsTakeoutCardState extends ConsumerState<SettingsTakeoutCard> {
  bool _isExporting = false;

  Future<void> _handleTakeout(String name) async {
    setState(() => _isExporting = true);
    try {
      await StoreTakeoutService.exportStoreTakeout(
        storeId: widget.storeId,
        storeName: name,
      );
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Takeout data downloaded for "$name"'),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export takeout: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sName = widget.storeName ?? widget.storeId;
    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final titleWidget = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_download_outlined, size: 16, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Store Data Takeout',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Download CSV file containing team rosters, configs, checklists, and portal links.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            );

            final downloadButton = ElevatedButton.icon(
              onPressed: _isExporting ? null : () => _handleTakeout(sName),
              icon: _isExporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 16),
              label: Text(_isExporting ? 'Exporting...' : 'Takeout Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );

            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleWidget,
                  const SizedBox(height: 10),
                  downloadButton,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleWidget),
                const SizedBox(width: 12),
                downloadButton,
              ],
            );
          },
        ),
      ),
    );
  }
}
