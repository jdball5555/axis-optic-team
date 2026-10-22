import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';

class SettingsManageHistoryLogsCard extends ConsumerWidget {
  final String storeId;

  const SettingsManageHistoryLogsCard({super.key, required this.storeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            final titleWidget = Text(
              'Manage History Logs',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            );
            final viewButton = ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) =>
                      _ManageHistoryLogsDialog(storeId: storeId),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: const Text('View Logs'),
            );

            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleWidget,
                  const SizedBox(height: 8),
                  viewButton,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleWidget),
                const SizedBox(width: 8),
                viewButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ManageHistoryLogsDialog extends ConsumerStatefulWidget {
  final String storeId;
  const _ManageHistoryLogsDialog({required this.storeId});

  @override
  ConsumerState<_ManageHistoryLogsDialog> createState() =>
      _ManageHistoryLogsDialogState();
}

class _ManageHistoryLogsDialogState
    extends ConsumerState<_ManageHistoryLogsDialog> {
  @override
  Widget build(BuildContext context) {
    // We can fetch all users globally and filter by store, since usersStreamProvider loads current store users
    // If the user is an admin viewing all stores, it might load all users.
    final usersAsync = ref.watch(usersStreamProvider);

    return AlertDialog(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: Text(
        'Store History Logs',
        style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color),
      ),
      content: SizedBox(
        width: 600,
        height: (MediaQuery.sizeOf(context).height - 120).clamp(200.0, 500.0),
        child: usersAsync.when(
          data: (users) {
            final storeUsers = users
                .where((u) => u.store == widget.storeId)
                .toList();
            // Aggregate all history logs
            final List<Map<String, dynamic>> allLogs = [];
            for (var user in storeUsers) {
              if (user.historyLogs != null) {
                for (var log in user.historyLogs!) {
                  allLogs.add({
                    'user': user,
                    'log': log,
                    'date': log['date'] ?? '',
                  });
                }
              }
            }

            // Sort by date descending
            allLogs.sort((a, b) {
              final dateA =
                  DateTime.tryParse(a['date'] ?? '') ?? DateTime(2000);
              final dateB =
                  DateTime.tryParse(b['date'] ?? '') ?? DateTime(2000);
              return dateB.compareTo(dateA);
            });

            if (allLogs.isEmpty) {
              return Center(
                child: Text(
                  'No history logs found for this store.',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              );
            }

            return ListView.separated(
              itemCount: allLogs.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final item = allLogs[index];
                final UserModel user = item['user'];
                final Map<String, dynamic> log = item['log'];
                final String date = item['date'];
                final String event = log['event'] ?? 'Event';
                final String userName =
                    '${user.firstName ?? ''} ${user.lastName ?? ''}'.trim();

                return ListTile(
                  title: Text(
                    event,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  subtitle: Text(
                    '$userName • $date',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: AppTheme.primaryRed,
                    ),
                    onPressed: () {
                      _confirmDelete(context, user, log);
                    },
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(
            child: Text(
              'Error loading logs: $e',
              style: TextStyle(color: AppTheme.primaryRed),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ],
    );
  }

  void _confirmDelete(
    BuildContext context,
    UserModel user,
    Map<String, dynamic> logToRemove,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            'Delete History Log',
            style: TextStyle(
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          content: Text(
            'Are you sure you want to delete this log?\n\n"${logToRemove['event']}"',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Close confirmation

                final newLogs = List<Map<String, dynamic>>.from(
                  user.historyLogs ?? [],
                );
                // Remove the exact matching log by properties (since it might be an unmodifiable map from freeze)
                newLogs.removeWhere(
                  (l) =>
                      l['event'] == logToRemove['event'] &&
                      l['date'] == logToRemove['date'],
                );

                final updatedUser = user.copyWith(historyLogs: newLogs);
                await ref
                    .read(firestoreServiceProvider)
                    .updateUser(updatedUser);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
