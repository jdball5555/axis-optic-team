import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final headerText = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Access',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Manage access for members who have more than standard team member permissions.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    );

                    final manageButton = ElevatedButton(
                      onPressed: () {
                        context.go('/settings/access');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: const Text('Manage Access'),
                    );

                    if (constraints.maxWidth < 420) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          headerText,
                          const SizedBox(height: 12),
                          manageButton,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: headerText),
                        const SizedBox(width: 12),
                        manageButton,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Store Owners',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 8),
                allUsersAsync.when(
                  data: (users) {
                    final owners = users
                        .where((u) => u.title?.toLowerCase() == 'owner')
                        .toList();
                    if (owners.isEmpty) {
                      return Text(
                        'No owners found.',
                        style: TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      );
                    }
                    return Column(
                      children: owners.map((owner) {
                        final fullName = [owner.firstName, owner.lastName]
                            .whereType<String>()
                            .where((s) => s.trim().isNotEmpty)
                            .join(' ');
                        final initial =
                            (owner.firstName != null &&
                                owner.firstName!.isNotEmpty)
                            ? owner.firstName![0].toUpperCase()
                            : (fullName.isNotEmpty
                                  ? fullName[0].toUpperCase()
                                  : '?');

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.5),
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final showBadge = box.maxWidth >= 200;
                              return Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: AppTheme.accent.withValues(
                                      alpha: 0.15,
                                    ),
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          fullName.isEmpty ? 'Owner' : fullName,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).textTheme.bodyLarge?.color,
                                          ),
                                        ),
                                        if (owner.email != null &&
                                            owner.email!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            owner.email!,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.color,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (showBadge) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.tint(AppTheme.accent),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Owner',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.onTint(AppTheme.accent),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const SizedBox(
                    height: 50,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Error: $e'),
                ),
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
}
