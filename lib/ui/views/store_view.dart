import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/store_settings_model.dart';

class StoreView extends ConsumerWidget {
  const StoreView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(allStoresStreamProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final firestoreService = ref.read(firestoreServiceProvider);
          await firestoreService.createNewStore();
        },
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Account',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).cardColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('App Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.titleLarge?.color)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.dark_mode, color: Theme.of(context).textTheme.bodySmall?.color),
                            const SizedBox(width: 16),
                            Text('Dark Mode', style: TextStyle(fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)),
                          ],
                        ),
                        Switch(
                          value: ref.watch(themeModeProvider) == ThemeMode.dark,
                          onChanged: (val) {
                            ref.read(themeModeProvider.notifier).state = val ? ThemeMode.dark : ThemeMode.light;
                            ref.read(brightColorsProvider.notifier).state = null;
                          },
                          activeColor: AppTheme.accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.palette_outlined, color: Theme.of(context).textTheme.bodySmall?.color),
                            const SizedBox(width: 16),
                            Text('Bright colors', style: TextStyle(fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)),
                          ],
                        ),
                        Switch(
                          value: ref.watch(effectiveBrightColorsProvider),
                          onChanged: (val) => ref.read(brightColorsProvider.notifier).state = val,
                          activeColor: AppTheme.accent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'My Stores',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Manage your stores and premium add-on features.',
              style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 16),
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: storesAsync.when(
                data: (stores) {
                  return ListView.builder(
                    itemCount: stores.length,
                    itemBuilder: (context, index) {
                      final storeId = stores[index]['id'] as String;
                      final storeName = stores[index]['name'] as String? ?? 'Untitled Store';
                      return StoreRow(storeId: storeId, initialStoreName: storeName);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StoreRow extends ConsumerStatefulWidget {
  final String storeId;
  final String initialStoreName;
  const StoreRow({super.key, required this.storeId, required this.initialStoreName});

  @override
  ConsumerState<StoreRow> createState() => _StoreRowState();
}

class _StoreRowState extends ConsumerState<StoreRow> {
  String? _localName;
  bool? _localSchedule;
  bool? _localShift;
  bool _hasUnsavedChanges = false;
  
  void _markUnsaved() {
    setState(() {
      _hasUnsavedChanges = true;
    });
    // Set global unsaved changes provider
    Future.microtask(() => ref.read(unsavedChangesProvider.notifier).state = true);
  }

  void _saveChanges(String defaultName, dynamic defaultSettings) async {
    try {
      final service = ref.read(firestoreServiceProvider);
      
      if (_localName != null && _localName != defaultName) {
        await service.updateStoreName(widget.storeId, _localName!);
      }
      
      if (_localSchedule != null || _localShift != null) {
        final currentSettings = defaultSettings ?? const StoreSettingsModel();
        final newSettings = currentSettings.copyWith(
          isScheduleEnabled: _localSchedule ?? currentSettings.isScheduleEnabled,
          isShiftBoardEnabled: _localShift ?? currentSettings.isShiftBoardEnabled,
        );
        await service.updateStoreSettingsForSpecificStore(widget.storeId, newSettings);
      }
      
      if (mounted) {
        setState(() {
          _hasUnsavedChanges = false;
          _localName = null;
          _localSchedule = null;
          _localShift = null;
        });
        ref.read(unsavedChangesProvider.notifier).state = false;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Changes saved successfully!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(storeStreamProvider(widget.storeId));
    final settingsAsync = ref.watch(specificStoreSettingsProvider(widget.storeId));

    final storeData = storeAsync.valueOrNull;
    final settingsData = settingsAsync.valueOrNull;

    final defaultName = storeData?['name'] as String? ?? widget.initialStoreName;
    final name = _localName ?? defaultName;
    final isScheduleEnabled = _localSchedule ?? (settingsData?.isScheduleEnabled ?? false);
    final isShiftEnabled = _localShift ?? (settingsData?.isShiftBoardEnabled ?? false);

    return Card(
      color: Theme.of(context).cardColor,
      margin: const EdgeInsets.only(bottom: 24),
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
                Icon(Icons.store, color: AppTheme.accent, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('store_name_${widget.storeId}'),
                    initialValue: name,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.titleLarge?.color),
                    decoration: const InputDecoration(
                      labelText: 'Store Name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      _localName = val;
                      _markUnsaved();
                    },
                  ),
                ),
                if (_hasUnsavedChanges) ...[
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () => _saveChanges(defaultName, settingsData),
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Schedule Add-on', style: TextStyle(fontWeight: FontWeight.bold)),
                    value: isScheduleEnabled,
                    activeTrackColor: AppTheme.accent,
                    onChanged: (val) {
                      _localSchedule = val;
                      _markUnsaved();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Shift Board Add-on', style: TextStyle(fontWeight: FontWeight.bold)),
                    value: isShiftEnabled,
                    activeTrackColor: AppTheme.accent,
                    onChanged: (val) {
                      _localShift = val;
                      _markUnsaved();
                    },
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
