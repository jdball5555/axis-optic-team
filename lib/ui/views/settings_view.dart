import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/settings_title_tag_card.dart';
import '../widgets/settings_checklists_card.dart';

import '../widgets/settings_manage_history_logs_card.dart';
import '../widgets/settings_employee_data_summary_card.dart';
import '../widgets/settings_access_card.dart';
import '../widgets/equal_height_row.dart';

import '../../models/store_settings_model.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStoreId = ref.watch(currentStoreIdProvider);
    final allStoresAsync = ref.watch(allStoresStreamProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: currentStoreId != null
          ? _buildSingleStore(context, ref, currentStoreId, null)
          : allStoresAsync.when(
              data: (stores) {
                if (stores.isEmpty) return const Center(child: Text('No stores'));
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = stores.length <= 2 ? constraints.maxWidth : stores.length * 500.0;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        child: CustomScrollView(
                          slivers: [
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _StoreHeadersDelegate(stores),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              sliver: SliverToBoxAdapter(
                                child: _buildAlignedStores(context, ref, stores),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            ),
    );
  }

  /// "All Stores": one row per settings card, each store's card as tall as
  /// the tallest one in that row.
  Widget _buildAlignedStores(BuildContext context, WidgetRef ref, List<Map<String, dynamic>> stores) {
    final perStore = [for (final s in stores) _sectionsFor(context, ref, s['id'] as String)];
    final rows = perStore.map((l) => l.length).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          EqualHeightRow(
            spacing: 16,
            children: [
              for (final sections in perStore)
                i < sections.length ? sections[i] : const SizedBox.shrink(),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSingleStore(BuildContext context, WidgetRef ref, String storeId, String? storeName) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (storeName != null) ...[
            Text(storeName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 24),
          ],
          _buildSingleStoreBody(context, ref, storeId),
        ],
      ),
    );
  }

  Widget _buildSingleStoreBody(BuildContext context, WidgetRef ref, String storeId) {
    final sections = _sectionsFor(context, ref, storeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          sections[i],
        ],
      ],
    );
  }

  /// The settings cards of one store, in order (one placeholder while it
  /// loads). In "All Stores" each card is lined up with the same card of the
  /// other stores.
  List<Widget> _sectionsFor(BuildContext context, WidgetRef ref, String storeId) {
    final settingsAsync = ref.watch(specificStoreSettingsProvider(storeId));
    final isAllStoresMode = ref.watch(currentStoreIdProvider) == null;
    final List<Map<String, dynamic>> allStores = isAllStoresMode ? (ref.watch(allStoresStreamProvider).valueOrNull ?? []) : [];
    
    return settingsAsync.when(
      data: (settings) {
        if (settings == null) return const [Center(child: Text('Settings not available'))];
        
        bool titlesTagsDiffer = false;
        bool checklistsDiffer = false;
        bool positionsDiffer = false;
        bool workingTimesDiffer = false;
        bool designationsDiffer = false;
        bool employeeDataSummaryFieldsDiffer = false;
        bool showOwnerInRosterDiffer = false;

        if (isAllStoresMode) {
          for (final store in allStores) {
            final sid = store['id'] as String;
            if (sid == storeId) continue;
            final otherSettings = ref.watch(specificStoreSettingsProvider(sid)).valueOrNull;
            if (otherSettings != null) {
              if (!listEquals(settings.titles, otherSettings.titles) || !listEquals(settings.tags, otherSettings.tags)) {
                titlesTagsDiffer = true;
              }
              if (!listEquals(settings.checklists, otherSettings.checklists)) {
                checklistsDiffer = true;
              }
              if (!listEquals(settings.positions, otherSettings.positions)) {
                positionsDiffer = true;
              }
              if (!listEquals(settings.workingTimes, otherSettings.workingTimes)) {
                workingTimesDiffer = true;
              }
              if (!listEquals(settings.designations, otherSettings.designations)) {
                designationsDiffer = true;
              }
              if (!listEquals(settings.employeeDataSummaryFields, otherSettings.employeeDataSummaryFields)) {
                employeeDataSummaryFieldsDiffer = true;
              }
              if (settings.showOwnerInRoster != otherSettings.showOwnerInRoster) {
                showOwnerInRosterDiffer = true;
              }
            }
          }
        }

        Widget? buildCopyButton(String fieldName, StoreSettingsModel Function(StoreSettingsModel, StoreSettingsModel) updateFn) {
          return InkWell(
            onTap: () {
              _showCopyDialog(context, ref, storeId, fieldName, allStores, settings, updateFn);
            },
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                  left: BorderSide(color: Theme.of(context).dividerColor),
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: const Icon(Icons.copy, color: Colors.grey, size: 14),
            ),
          );
        }

        return [
            SettingsTitleTagCard(
              settings: settings,
              onUpdate: (newSettings) {
                ref.read(firestoreServiceProvider).updateStoreSettingsForSpecificStore(storeId, newSettings);
              },
              copyButton: titlesTagsDiffer ? buildCopyButton('Titles & Tags', (current, dest) => dest.copyWith(titles: current.titles, tags: current.tags)) : null,
            ),
            SettingsAccessCard(
              settings: settings,
              onUpdate: (newSettings) {
                ref.read(firestoreServiceProvider).updateStoreSettingsForSpecificStore(storeId, newSettings);
              },
              copyButton: showOwnerInRosterDiffer ? buildCopyButton('Access', (current, dest) => dest.copyWith(showOwnerInRoster: current.showOwnerInRoster)) : null,
            ),
            SettingsChecklistsCard(
              settings: settings,
              onUpdate: (newSettings) {
                ref.read(firestoreServiceProvider).updateStoreSettingsForSpecificStore(storeId, newSettings);
              },
              copyButton: checklistsDiffer ? buildCopyButton('Checklists', (current, dest) => dest.copyWith(checklists: current.checklists)) : null,
            ),
            SettingsManageHistoryLogsCard(storeId: storeId),
            SettingsEmployeeDataSummaryCard(
              settings: settings,
              onUpdate: (newSettings) {
                ref.read(firestoreServiceProvider).updateStoreSettingsForSpecificStore(storeId, newSettings);
              },
              copyButton: employeeDataSummaryFieldsDiffer ? buildCopyButton('Data Summary', (current, dest) => dest.copyWith(employeeDataSummaryFields: current.employeeDataSummaryFields)) : null,
            ),
            _buildListEditor(context, ref, 'Positions', settings.positions, (newItems) {
              ref.read(firestoreServiceProvider).updateStoreSettingsForSpecificStore(storeId, settings.copyWith(positions: newItems));
            }, copyButton: positionsDiffer ? buildCopyButton('Positions', (current, dest) => dest.copyWith(positions: current.positions)) : null),
            _buildListEditor(context, ref, 'Working Times', settings.workingTimes, (newItems) {
              ref.read(firestoreServiceProvider).updateStoreSettingsForSpecificStore(storeId, settings.copyWith(workingTimes: newItems));
            }, copyButton: workingTimesDiffer ? buildCopyButton('Working Times', (current, dest) => dest.copyWith(workingTimes: current.workingTimes)) : null),
            _buildListEditor(context, ref, 'Designations', settings.designations, (newItems) {
              ref.read(firestoreServiceProvider).updateStoreSettingsForSpecificStore(storeId, settings.copyWith(designations: newItems));
            }, copyButton: designationsDiffer ? buildCopyButton('Designations', (current, dest) => dest.copyWith(designations: current.designations)) : null),
        ];
      },
      loading: () => const [SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))],
      error: (e, st) => [SizedBox(height: 200, child: Center(child: Text('Error: $e')))],
    );
  }

  void _showCopyDialog(BuildContext context, WidgetRef ref, String sourceStoreId, String fieldName, List<Map<String, dynamic>> allStores, StoreSettingsModel sourceSettings, StoreSettingsModel Function(StoreSettingsModel, StoreSettingsModel) updateFn) {
    final otherStores = allStores.where((s) => s['id'] != sourceStoreId).toList();
    final selectedStores = <String>{};

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              title: Text('Copy $fieldName settings to other stores?', style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color)),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: otherStores.map((store) {
                    final sid = store['id'] as String;
                    return CheckboxListTile(
                      title: Text('${store['name']}', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                      value: selectedStores.contains(sid),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            selectedStores.add(sid);
                          } else {
                            selectedStores.remove(sid);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedStores.isEmpty ? null : () {
                    for (final sid in selectedStores) {
                      final destSettings = ref.read(specificStoreSettingsProvider(sid)).valueOrNull;
                      if (destSettings != null) {
                        final newSettings = updateFn(sourceSettings, destSettings);
                        ref.read(firestoreServiceProvider).updateStoreSettingsForSpecificStore(sid, newSettings);
                      }
                    }
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $fieldName to ${selectedStores.length} store(s)')));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
                  child: const Text('Copy'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildListEditor(BuildContext context, WidgetRef ref, String title, List<String> items, Function(List<String>) onChanged, {Widget? copyButton}) {
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
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                    IconButton(
                      icon: Icon(Icons.add_circle, color: AppTheme.accent),
                      onPressed: () {
                        _showAddItemDialog(context, title, (newItem) {
                          if (newItem.isNotEmpty && !items.contains(newItem)) {
                            onChanged([...items, newItem]);
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: items.map((item) {
                    return Chip(
                      label: Text(item),
                      onDeleted: () {
                        final newItems = List<String>.from(items)..remove(item);
                        onChanged(newItems);
                      },
                      deleteIconColor: AppTheme.primaryRed,
                      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    );
                  }).toList(),
                ),
                if (copyButton != null) const SizedBox(height: 24),
              ],
            ),
          ),
          if (copyButton != null)
            Positioned(
              bottom: 0,
              right: 0,
              child: copyButton,
            ),
        ],
      ),
    );
  }

  void _showAddItemDialog(BuildContext context, String title, Function(String) onAdd) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text('Add to $title', style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
            decoration: const InputDecoration(
              hintText: 'Enter value',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                onAdd(controller.text.trim());
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

}

class _StoreHeadersDelegate extends SliverPersistentHeaderDelegate {
  final List<Map<String, dynamic>> stores;

  _StoreHeadersDelegate(this.stores);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: EqualHeightRow(
          spacing: 16,
          children: [
            for (final store in stores)
              Container(
                alignment: Alignment.center,
                child: Text(
                  '${store['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  double get maxExtent => 100.0;

  @override
  double get minExtent => 100.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
}
