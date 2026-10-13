import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/store_settings_model.dart';

import '../../providers/app_providers.dart';

class SettingsAccessCard extends ConsumerWidget {
  final StoreSettingsModel settings;
  final Function(StoreSettingsModel) onUpdate;
  final Widget? copyButton;

  const SettingsAccessCard({
    super.key,
    required this.settings,
    required this.onUpdate,
    this.copyButton,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allUsersAsync = ref.watch(allStoreUsersStreamProvider);

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Access', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                          const SizedBox(height: 4),
                          Text('Manage access for members who have more than standard team member permissions.', style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        context.go('/settings/access');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Manage Access'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Store Owners', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                const SizedBox(height: 8),
                
                allUsersAsync.when(
                  data: (users) {
                    final owners = users.where((u) => u.title?.toLowerCase() == 'owner').toList();
                    if (owners.isEmpty) {
                      return Text('No owners found.', style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Theme.of(context).textTheme.bodySmall?.color));
                    }
                    return Column(
                      children: owners.map((owner) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Text(owner.firstName?.substring(0, 1).toUpperCase() ?? '?'),
                          ),
                          title: Text('${owner.firstName} ${owner.lastName}', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                          subtitle: Text(owner.email ?? 'No email', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
                          trailing: Chip(label: Text('Owner', style: TextStyle(fontSize: 10))),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const SizedBox(height: 50, child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('Error: $e'),
                ),
                
                if (copyButton != null) const SizedBox(height: 24),
              ],
            ),
          ),
          if (copyButton != null)
            Positioned(
              bottom: 0,
              right: 0,
              child: copyButton!,
            ),
        ],
      ),
    );
  }
}
