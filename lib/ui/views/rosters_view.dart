import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../models/store_settings_model.dart';

class RostersView extends ConsumerWidget {
  const RostersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsyncValue = ref.watch(currentMembersProvider);
    final rosterNeedsAsyncValue = ref.watch(rosterNeedsStreamProvider);
    final storesAsync = ref.watch(allStoresStreamProvider);
    final currentStoreId = ref.watch(currentStoreIdProvider);
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: usersAsyncValue.when(
        data: (users) {
          final rosterNeeds = rosterNeedsAsyncValue.valueOrNull ?? {};
          final allStores = storesAsync.valueOrNull ?? [];
          
          if (users.isEmpty) {
            return const Center(child: Text('No team members found.'));
          }

          final Map<String, StoreSettingsModel> storeSettingsMap = {};
          for (final store in allStores) {
            final sid = store['id'] as String;
            final settings = ref.watch(specificStoreSettingsProvider(sid)).valueOrNull;
            if (settings != null) {
              storeSettingsMap[sid] = settings;
            }
          }

          // Group by Store and Position
          final Map<String, List<UserModel>> positionGroups = {};
          for (final user in users) {
            final sid = user.store ?? 'unknown';
            final settings = storeSettingsMap[sid];
            
            bool isIsolated = false;
            if (settings != null && user.title != null) {
               TitleConfig? titleConfig = settings.titles.where((t) => t.name == user.title).firstOrNull;
               titleConfig ??= settings.tags.where((t) => t.name == user.title).firstOrNull;
               if (titleConfig?.isolatedRoster == true) {
                  isIsolated = true;
               }
            }

            final pos = isIsolated ? (user.title ?? 'Unassigned') : (user.position ?? 'Unassigned');
            
            String storeName = '';
            if (currentStoreId == null) {
              final storeObj = allStores.where((s) => s['id'] == sid).firstOrNull;
              storeName = storeObj?['name'] ?? 'Store';
            }
            
            final groupKey = currentStoreId == null ? '$sid|$storeName - $pos|$pos|$isIsolated' : '$sid|$pos|$pos|$isIsolated';
            positionGroups.putIfAbsent(groupKey, () => []).add(user);
          }

          final sortedKeys = positionGroups.keys.toList()..sort((a, b) {
            final titleA = a.split('|')[1];
            final titleB = b.split('|')[1];
            return titleA.compareTo(titleB);
          });

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Store Rosters & Staffing (6 Days/Week)',
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.bold, 
                        color: Theme.of(context).textTheme.titleLarge?.color
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.lightBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.accent),
                      ),
                      child: Text('Active: Standard Roster', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 12)),
                    )
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: sortedKeys.map((key) {
                        final parts = key.split('|');
                        final sid = parts[0];
                        final displayTitle = parts[1];
                        final rawPos = parts[2];
                        final isIsolatedTitle = parts.length > 3 && parts[3] == 'true';
                        final needsKey = '${sid}_$rawPos';
                        final shiftsNeeded = (rosterNeeds[needsKey] as num?)?.toInt() ?? 0;
                        return _buildPositionColumn(context, ref, sid, displayTitle, rawPos, positionGroups[key]!, shiftsNeeded, isIsolatedTitle);
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _editShiftsNeeded(BuildContext context, WidgetRef ref, String storeId, String position, int currentNeeds) {
    final controller = TextEditingController(text: currentNeeds.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Edit Shifts Needed ($position)', style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
          decoration: const InputDecoration(
            labelText: 'Shifts Needed Per Day',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
            onPressed: () async {
              final val = int.tryParse(controller.text) ?? 0;
              final firestoreService = ref.read(baseFirestoreServiceProvider);
              await firestoreService.updateRosterNeeds(storeId, position, val);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionColumn(BuildContext context, WidgetRef ref, String storeId, String displayTitle, String rawPos, List<UserModel> members, int shiftsNeededPerDay, bool isIsolatedTitle) {
    members.sort((a, b) => (a.firstName ?? '').compareTo(b.firstName ?? ''));
    
    int totalShiftsCovered = 0;
    for (final m in members) {
      if (m.avgShifts != null) {
        totalShiftsCovered += int.tryParse(m.avgShifts!) ?? 0;
      }
    }
    
    final double shiftsCoveredPerDay = totalShiftsCovered / 6.0;
    final double pctCovered = shiftsNeededPerDay == 0 ? 1.0 : shiftsCoveredPerDay / shiftsNeededPerDay;
    final color = pctCovered >= 1.0 ? AppTheme.accent : AppTheme.primaryRed;
    
    final double deficit = shiftsNeededPerDay - shiftsCoveredPerDay;
    final int newHiresNeeded = deficit > 0 ? deficit.ceil() : 0;

    final storeSettings = ref.watch(specificStoreSettingsProvider(storeId)).valueOrNull;

    Color columnColor = AppTheme.accent;
    if (storeSettings != null && isIsolatedTitle) {
      final config = storeSettings.titles.where((t) => t.name == rawPos).firstOrNull ?? 
                     storeSettings.tags.where((t) => t.name == rawPos).firstOrNull;
      if (config != null) {
        columnColor = AppTheme.getColorFromName(config.color);
      }
    }

    final Map<String, List<UserModel>> splitGroups = {};
    final List<UserModel> regularMembers = [];

    for (final user in members) {
      bool isSplit = false;
      if (storeSettings != null && user.title != null) {
        TitleConfig? titleConfig = storeSettings.titles.where((t) => t.name == user.title).firstOrNull;
        titleConfig ??= storeSettings.tags.where((t) => t.name == user.title).firstOrNull;
        if (titleConfig?.splitInArea == true) {
          isSplit = true;
          splitGroups.putIfAbsent(user.title!, () => []).add(user);
        }
      }
      if (!isSplit) {
        regularMembers.add(user);
      }
    }

    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _wash(columnColor),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: _line(columnColor))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayTitle.toUpperCase(),
                          style: TextStyle(color: AppTheme.onTint(columnColor), fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isIsolatedTitle)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: _wash(columnColor),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _line(columnColor)),
                          ),
                          child: Text('TITLE', style: TextStyle(color: AppTheme.onTint(columnColor), fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
                if (newHiresNeeded > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('+$newHiresNeeded HIRE', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          // Subheader
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Shifts Needed / Day:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                    InkWell(
                      onTap: () => _editShiftsNeeded(context, ref, storeId, rawPos, shiftsNeededPerDay),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                        child: Row(
                          children: [
                            Text('$shiftsNeededPerDay', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: columnColor)),
                            const SizedBox(width: 4),
                            Icon(Icons.edit, size: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 4,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: pctCovered > 1.0 ? 1.0 : pctCovered,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Covered: ${shiftsCoveredPerDay.toStringAsFixed(1)} / day', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                    Text('(=$totalShiftsCovered/wk)', style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color)),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          // List of members
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...splitGroups.entries.map((e) {
                  final titleName = e.key;
                  final groupMembers = e.value;
                  
                  Color groupColor = columnColor;
                  if (storeSettings != null) {
                    final tConfig = storeSettings.titles.where((t) => t.name == titleName).firstOrNull ?? 
                                    storeSettings.tags.where((t) => t.name == titleName).firstOrNull;
                    if (tConfig != null) {
                      groupColor = AppTheme.getColorFromName(tConfig.color);
                    }
                  }
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _line(groupColor)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _wash(groupColor),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                            border: Border(bottom: BorderSide(color: _line(groupColor))),
                          ),
                          child: Text('${titleName.toUpperCase()} (${groupMembers.length})', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.onTint(groupColor))),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: Column(
                            children: groupMembers.map((u) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildMemberTile(context, u, storeSettings),
                            )).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                ...regularMembers.map((u) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: _buildMemberTile(context, u, storeSettings),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Rosters use softer color than the rest of the app: a faint wash behind
  /// and a thin border, so a page full of titles isn't overwhelming.
  static Color _wash(Color c) => c.withValues(alpha: AppTheme.isLightTheme ? 0.10 : 0.07);
  static Color _line(Color c) => c.withValues(alpha: AppTheme.isLightTheme ? 0.6 : 0.5);

  Widget _buildMemberTile(BuildContext context, UserModel user, StoreSettingsModel? storeSettings) {
    Color titleColor = AppTheme.primaryRed;
    if (storeSettings != null && user.title != null) {
      TitleConfig? titleConfig = storeSettings.titles.where((t) => t.name == user.title).firstOrNull;
      titleConfig ??= storeSettings.tags.where((t) => t.name == user.title).firstOrNull;
      if (titleConfig != null && titleConfig.color != null) {
        titleColor = AppTheme.getColorFromName(titleConfig.color!);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _wash(titleColor),
          Theme.of(context).scaffoldBackgroundColor,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line(titleColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              '${user.firstName} ${user.lastName}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            user.avgShifts ?? '0',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.titleLarge?.color),
          ),
        ],
      ),
    );
  }
}
