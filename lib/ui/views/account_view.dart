import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'store_view.dart';

class AccountView extends ConsumerWidget {
  const AccountView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);
    final allStoresAsync = ref.watch(allStoresStreamProvider);

    if (currentUser == null) {
      return const Center(child: Text('Not logged in'));
    }

    final ownedStoreIds = List<String>.from(currentUser['owned_stores'] ?? []);
    final isOwner = ownedStoreIds.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        backgroundColor: Theme.of(context).cardColor,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Theme.of(context).dividerColor, height: 1),
        ),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account Information Section
            Text('Account Information', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.titleLarge?.color)),
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildInfoField(context, 'First Name', currentUser['first_name'] ?? '')),
                        const SizedBox(width: 16),
                        Expanded(child: _buildInfoField(context, 'Last Name', currentUser['last_name'] ?? '')),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildInfoField(context, 'Email', currentUser['email'] ?? ''),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Password', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                        ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Change password coming soon!')));
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Appearance Section
            Text('Appearance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.titleLarge?.color)),
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text('Dark Mode', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                      value: themeMode == ThemeMode.dark,
                      onChanged: (val) {
                        ref.read(themeModeProvider.notifier).state = val ? ThemeMode.dark : ThemeMode.light;
                            ref.read(brightColorsProvider.notifier).state = null;
                      },
                      activeColor: AppTheme.accent,
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: Text('Bright colors', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                      subtitle: Text(
                        'Use the bright shades of the accent colors instead of the dim ones',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                      value: ref.watch(effectiveBrightColorsProvider),
                      onChanged: (val) => ref.read(brightColorsProvider.notifier).state = val,
                      activeColor: AppTheme.accent,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            
            if (isOwner) ...[
              const SizedBox(height: 32),
              // My Stores Section
              Text('My Stores', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.titleLarge?.color)),
              const SizedBox(height: 16),
              allStoresAsync.when(
                data: (stores) {
                  final ownedStores = stores.where((s) => ownedStoreIds.contains(s['id'] as String)).toList();
                  
                  if (ownedStores.isEmpty) {
                    return const Text('No stores found.');
                  }

                  return Column(
                    children: ownedStores.map((store) {
                      final storeName = store['name'] as String? ?? 'Untitled Store';
                      return StoreRow(storeId: store['id'] as String, initialStoreName: storeName);
                    }).toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Text('Error loading stores: $e'),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('saved_email');
                  await prefs.remove('saved_password');
                  ref.read(currentUserProvider.notifier).state = null;
                  if (context.mounted) {
                    context.go('/auth');
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Log Out', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.1),
                  foregroundColor: Colors.red,
                  elevation: 0,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoField(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Text(value, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
        ),
      ],
    );
  }
}
