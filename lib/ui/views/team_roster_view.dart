import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import 'settings_view.dart';
import '../../models/store_settings_model.dart';
import '../widgets/multi_select_field.dart';
import '../widgets/scroll_table.dart';

class TeamRosterView extends ConsumerStatefulWidget {
  const TeamRosterView({super.key});

  @override
  ConsumerState<TeamRosterView> createState() => _TeamRosterViewState();
}

class _TeamRosterViewState extends ConsumerState<TeamRosterView> {
  String _searchQuery = '';
  List<String> _filterTitle = [];
  List<String> _filterWorkingTime = [];
  List<String> _filterPosition = [];
  List<String> _filterDesignation = [];

  /// By default former team members (last day passed) are hidden.
  static const _defaultStatus = ['Active', 'Leaving'];
  List<String> _filterStatus = [..._defaultStatus];

  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Tapping a header: ascending, then descending, then back to the
  /// default (newest hires first). Start Date just flips direction.
  void _onHeaderTap(String column) {
    final sortState = ref.read(rosterSortProvider);
    final RosterSortState newState;
    if (sortState.column != column || sortState.isAscending == null) {
      newState = RosterSortState(
        column: column,
        isAscending: column != RosterSortState.byDefault.column,
      );
    } else if (column == RosterSortState.byDefault.column) {
      newState = RosterSortState(
        column: column,
        isAscending: !sortState.isAscending!,
      );
    } else if (sortState.isAscending!) {
      newState = RosterSortState(column: column, isAscending: false);
    } else {
      newState = RosterSortState.byDefault;
    }
    ref.read(rosterSortProvider.notifier).state = newState;
  }

  Widget _buildHeaderCell(BuildContext context, String text, int flex) {
    final sortState = ref.watch(rosterSortProvider);
    return Expanded(
      flex: flex,
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _onHeaderTap(text),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (sortState.column == text &&
                    sortState.isAscending != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    sortState.isAscending == true
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 14,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataCell(
    BuildContext context,
    String text,
    int flex, {
    bool isBold = false,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  /// Everything about a member the search bar can match on, lowercased.
  String _searchText(UserModel u, Map<String, String> storeNames) {
    String date(DateTime? d) =>
        d == null ? '' : '${d.month}/${d.day}/${d.year}';
    return [
      u.firstName,
      u.lastName,
      u.preferredName,
      u.email,
      u.title,
      u.position,
      u.designation,
      ...?u.additionalTags,
      if (u.store != null) storeNames[u.store],
      u.workingTime,
      u.avgShifts,
      if (u.payRate != null) '\$${u.payRate}',
      date(u.startDate),
      date(u.endDate),
      date(u.foodHandlersExpiration),
      date(u.managerPermitExpiration),
      u.generalNotes,
      u.hiringNotes,
      memberStatus(u),
      ...?u.certifications,
      u.role,
    ].whereType<String>().join(' ').toLowerCase();
  }

  Widget _buildStoreCell(String? storeId, int flex) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Consumer(
          builder: (context, ref, _) {
            if (storeId == null) {
              return Text(
                '-',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  fontSize: 14,
                ),
              );
            }
            final allStores =
                ref.watch(allStoresStreamProvider).valueOrNull ?? [];
            final storeData = allStores
                .where((s) => s['id'] == storeId)
                .firstOrNull;
            final name = storeData?['name'] as String? ?? 'Untitled Store';
            return Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 14,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPermitCell(
    BuildContext context,
    DateTime? expiration,
    int flex, {
    bool isRequired = true,
  }) {
    if (!isRequired) {
      return _buildDataCell(context, '', flex);
    }
    if (expiration == null) {
      return _buildPillCell('No Permit', AppTheme.primaryRed, flex);
    }

    final difference = expiration.difference(DateTime.now()).inDays;

    if (difference < 0) {
      return _buildPillCell('Expired', AppTheme.primaryRed, flex);
    } else if (difference <= 30) {
      String label;
      if (difference > 21) {
        label = '1 month left';
      } else if (difference > 14) {
        label = '3 weeks left';
      } else if (difference > 7) {
        label = '2 weeks left';
      } else if (difference == 7) {
        label = '1 week left';
      } else if (difference == 1) {
        label = '1 day left';
      } else {
        label = '$difference days left';
      }
      return _buildPillCell(label, AppTheme.orange, flex);
    } else {
      return _buildDataCell(
        context,
        expiration.toIso8601String().split('T').first,
        flex,
      );
    }
  }

  Widget _buildPillCell(String label, Color color, int flex) {
    return Expanded(
      flex: flex,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.tint(color),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.edge(color), width: 1.5),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.onTint(color),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// The member's additional tags as small bubbles in their tag colors.
  Widget _buildTagsCell(
    UserModel user,
    StoreSettingsModel? settings,
    int flex,
  ) {
    final tags = (user.additionalTags ?? const <String>[])
        .where((t) => t.trim().isNotEmpty)
        .toList();
    return Expanded(
      flex: flex,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final tag in tags)
                () {
                  final conf = settings?.tags
                      .where((t) => t.name == tag)
                      .firstOrNull;
                  final color = conf == null || conf.color == 'Color'
                      ? AppTheme.lightBlue
                      : AppTheme.getColorFromName(conf.color);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.tint(color),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.edge(color)),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: AppTheme.onTint(color),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddMemberDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const _AddMemberDialog(),
    );
  }

  Widget _buildTopBar(BuildContext context, List<UserModel> allUsers) {
    final uniqueTitles =
        allUsers
            .map((u) => u.title ?? '')
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final uniquePositions =
        allUsers
            .map((u) => u.position ?? '')
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final uniqueDesignations =
        allUsers
            .map((u) => u.designation ?? '')
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final uniqueWorkingTimes =
        allUsers
            .map((u) => u.workingTime ?? '')
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final uniqueStatuses = {
      ..._defaultStatus,
      'Former',
      ...allUsers.map(memberStatus),
    }.toList();
    final hasActiveFilters =
        _searchQuery.isNotEmpty ||
        _filterTitle.isNotEmpty ||
        _filterPosition.isNotEmpty ||
        _filterDesignation.isNotEmpty ||
        _filterWorkingTime.isNotEmpty ||
        _filterStatus.join(',') != _defaultStatus.join(',');

    return Container(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              decoration: InputDecoration(
                hintText: 'Search team members...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: MultiSelectFilter(
              label: 'Title',
              options: uniqueTitles,
              selected: _filterTitle,
              onChanged: (v) => setState(() => _filterTitle = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: MultiSelectFilter(
              label: 'Position',
              options: uniquePositions,
              selected: _filterPosition,
              onChanged: (v) => setState(() => _filterPosition = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: MultiSelectFilter(
              label: 'Designation',
              options: uniqueDesignations,
              selected: _filterDesignation,
              onChanged: (v) => setState(() => _filterDesignation = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: MultiSelectFilter(
              label: 'Working Time',
              options: uniqueWorkingTimes,
              selected: _filterWorkingTime,
              onChanged: (v) => setState(() => _filterWorkingTime = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: MultiSelectFilter(
              label: 'Status',
              options: uniqueStatuses,
              selected: _filterStatus,
              onChanged: (v) => setState(() => _filterStatus = v),
            ),
          ),
          if (hasActiveFilters) ...[
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              color: AppTheme.primaryRed,
              tooltip: 'Clear Filters',
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _filterTitle = [];
                  _filterPosition = [];
                  _filterDesignation = [];
                  _filterWorkingTime = [];
                  _filterStatus = [..._defaultStatus];
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedUsersAsync = ref.watch(sortedUsersProvider);
    final currentStoreId = ref.watch(currentStoreIdProvider);
    final settingsAsync = ref.watch(storeSettingsProvider);
    final settings = settingsAsync.valueOrNull;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMemberDialog(context, ref),
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('New Team Member'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: sortedUsersAsync.when(
          skipLoadingOnReload: true,
          data: (sortedUsers) {
            final storeNames = {
              for (final s
                  in ref.watch(allStoresStreamProvider).valueOrNull ?? [])
                s['id'] as String: (s['name'] as String?) ?? '',
            };
            final queryTerms = _searchQuery
                .toLowerCase()
                .split(RegExp(r'\s+'))
                .where((t) => t.isNotEmpty)
                .toList();
            final List<UserModel> filteredUsers = sortedUsers.where((user) {
              if (queryTerms.isNotEmpty) {
                final haystack = _searchText(user, storeNames);
                if (!queryTerms.every(haystack.contains)) return false;
              }
              if (_filterTitle.isNotEmpty && !_filterTitle.contains(user.title))
                return false;
              if (_filterPosition.isNotEmpty &&
                  !_filterPosition.contains(user.position))
                return false;
              if (_filterDesignation.isNotEmpty &&
                  !_filterDesignation.contains(user.designation))
                return false;
              if (_filterWorkingTime.isNotEmpty &&
                  !_filterWorkingTime.contains(user.workingTime))
                return false;
              if (_filterStatus.isNotEmpty &&
                  !_filterStatus.contains(memberStatus(user)))
                return false;
              return true;
            }).toList();

            if (filteredUsers.isEmpty && sortedUsers.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(context, sortedUsers),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'No team members found.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              );
            }

            bool showManagerPermit = false;
            bool showChecklist = false;
            bool isLoadingSettings = false;

            final allStoresAsync = ref.watch(allStoresStreamProvider);
            if (allStoresAsync.isLoading) {
              isLoadingSettings = true;
            }
            final allStores = allStoresAsync.valueOrNull ?? [];

            if (currentStoreId != null) {
              if (settingsAsync.isLoading) isLoadingSettings = true;
              if (settings != null) {
                showManagerPermit =
                    settings.titles.any((t) => t.mgrPermit) ||
                    settings.tags.any((t) => t.mgrPermit);
              }
            } else {
              for (final store in allStores) {
                final sid = store['id'] as String;
                final asyncStoreSettings = ref.watch(
                  specificStoreSettingsProvider(sid),
                );
                if (asyncStoreSettings.isLoading) {
                  isLoadingSettings = true;
                }
                final sSettings = asyncStoreSettings.valueOrNull;
                if (sSettings != null) {
                  if (sSettings.titles.any((t) => t.mgrPermit) ||
                      sSettings.tags.any((t) => t.mgrPermit)) {
                    showManagerPermit = true;
                  }
                }
              }
            }

            if (isLoadingSettings) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(context, sortedUsers),
                  Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.accent),
                    ),
                  ),
                ],
              );
            }

            StoreSettingsModel? settingsFor(UserModel u) => u.store != null
                ? ref.watch(specificStoreSettingsProvider(u.store!)).valueOrNull
                : settings;
            for (final u in filteredUsers) {
              if (activeChecklistsFor(u, settingsFor(u)).isNotEmpty) {
                showChecklist = true;
              }
            }

            final sortState = ref.watch(rosterSortProvider);
            if (sortState.column == 'Checklists' &&
                sortState.isAscending != null) {
              filteredUsers.sort((a, b) {
                String getChecklistName(UserModel user) {
                  final active = activeChecklistsFor(user, settingsFor(user));
                  return active.isEmpty ? '' : active.first.name;
                }

                final aChecklist = getChecklistName(a).toLowerCase();
                final bChecklist = getChecklistName(b).toLowerCase();

                if (aChecklist.isEmpty && bChecklist.isEmpty) return 0;
                if (aChecklist.isEmpty) return sortState.isAscending! ? 1 : -1;
                if (bChecklist.isEmpty) return sortState.isAscending! ? -1 : 1;

                return sortState.isAscending!
                    ? aChecklist.compareTo(bChecklist)
                    : bChecklist.compareTo(aChecklist);
              });
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(context, sortedUsers),
                if (filteredUsers.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'No matches found.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  )
                else
                  Expanded(
                    // Scrolls up/down and side to side at once; the sideways
                    // scrollbar stays at the bottom of the screen.
                    child: ScrollTable(
                      width: MediaQuery.of(context).size.width > 1850
                          ? MediaQuery.of(context).size.width - 240 - 48
                          : 1850,
                      header: // Header row
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          children: [
                            _buildHeaderCell(context, 'Name', 8),
                            if (showChecklist)
                              _buildHeaderCell(context, 'Checklists', 10),
                            _buildHeaderCell(context, 'Title', 10),
                            _buildHeaderCell(context, 'Position', 8),
                            _buildHeaderCell(context, 'Additional Tags', 10),
                            _buildHeaderCell(context, 'Designation', 8),
                            if (currentStoreId == null)
                              _buildHeaderCell(context, 'Store', 8),
                            _buildHeaderCell(context, 'Working Time', 8),
                            _buildHeaderCell(context, 'Avg Shifts', 6),
                            _buildHeaderCell(context, 'Pay', 6),
                            _buildHeaderCell(context, 'Food Permit', 8),
                            if (showManagerPermit)
                              _buildHeaderCell(context, 'Manager Permit', 8),
                            _buildHeaderCell(context, 'Start Date', 8),
                            _buildHeaderCell(context, 'Status', 6),
                          ],
                        ),
                      ),
                      body: (vertical) => ListView.separated(
                        controller: vertical,
                        itemCount: filteredUsers.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          String name =
                              '${user.lastName ?? ''}, ${user.firstName ?? ''}'
                                  .trim();
                          if (name.startsWith(','))
                            name = name.substring(1).trim();
                          if (name.endsWith(','))
                            name = name.substring(0, name.length - 1).trim();
                          if (user.preferredName != null &&
                              user.preferredName!.trim().isNotEmpty) {
                            name += ' (${user.preferredName})';
                          }

                          return InkWell(
                            onTap: () {
                              if (user.id != null) {
                                context.go('/member/${user.id}');
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 8.0,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  _buildDataCell(
                                    context,
                                    name.isEmpty ? '' : name,
                                    8,
                                    isBold: true,
                                  ),
                                  if (showChecklist)
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final userStoreSettings =
                                            user.store != null
                                            ? ref
                                                  .watch(
                                                    specificStoreSettingsProvider(
                                                      user.store!,
                                                    ),
                                                  )
                                                  .valueOrNull
                                            : settings;
                                        final activeChecklists =
                                            activeChecklistsFor(
                                              user,
                                              userStoreSettings,
                                            );
                                        final userChecklist =
                                            activeChecklists.firstOrNull;

                                        if (userChecklist != null) {
                                          final color =
                                              AppTheme.getColorFromName(
                                                userChecklist.color,
                                              );
                                          final done =
                                              (user.completedTasks ?? [])
                                                  .map((t) => t.trim())
                                                  .toSet();
                                          final completedCount = userChecklist
                                              .items
                                              .where(
                                                (i) => done.contains(i.trim()),
                                              )
                                              .length;
                                          final totalCount =
                                              userChecklist.items.length;
                                          final extraCount =
                                              activeChecklists.length - 1;

                                          return Expanded(
                                            flex: 10,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8.0,
                                              ),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: color.withValues(
                                                      alpha: 0.1,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: color.withValues(
                                                        alpha: 0.3,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          '${userChecklist.name}',
                                                          style: TextStyle(
                                                            color: color,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        ': $completedCount/$totalCount${extraCount > 0 ? '  +$extraCount' : ''}',
                                                        style: TextStyle(
                                                          color: color,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        } else {
                                          return _buildDataCell(
                                            context,
                                            '',
                                            10,
                                          );
                                        }
                                      },
                                    ),
                                  Consumer(
                                    builder: (context, ref, _) {
                                      Color titleColor =
                                          AppTheme.lightBlue; // Default
                                      final userStoreSettings =
                                          user.store != null
                                          ? ref
                                                .watch(
                                                  specificStoreSettingsProvider(
                                                    user.store!,
                                                  ),
                                                )
                                                .valueOrNull
                                          : settings; // fallback to the global one if no store set

                                      if (userStoreSettings != null &&
                                          user.title != null) {
                                        // First check titles
                                        TitleConfig? titleConfig =
                                            userStoreSettings.titles
                                                .where(
                                                  (t) => t.name == user.title,
                                                )
                                                .firstOrNull;
                                        // If not in titles, check tags
                                        titleConfig ??= userStoreSettings.tags
                                            .where((t) => t.name == user.title)
                                            .firstOrNull;

                                        if (titleConfig != null &&
                                            titleConfig.color != null) {
                                          titleColor =
                                              AppTheme.getColorFromName(
                                                titleConfig.color!,
                                              );
                                        }
                                      }

                                      if (user.title == null ||
                                          user.title!.isEmpty) {
                                        return _buildDataCell(context, '', 10);
                                      }
                                      return _buildPillCell(
                                        user.title!,
                                        titleColor,
                                        10,
                                      );
                                    },
                                  ),
                                  _buildDataCell(
                                    context,
                                    user.position ?? '',
                                    8,
                                  ),
                                  _buildTagsCell(user, settingsFor(user), 10),
                                  _buildDataCell(
                                    context,
                                    user.designation ?? '',
                                    8,
                                  ),
                                  if (currentStoreId == null)
                                    _buildStoreCell(user.store, 8),
                                  _buildDataCell(
                                    context,
                                    user.workingTime ?? '',
                                    8,
                                  ),
                                  _buildDataCell(
                                    context,
                                    user.avgShifts ?? '',
                                    6,
                                  ),
                                  _buildDataCell(
                                    context,
                                    user.payRate != null
                                        ? '\$${user.payRate}'
                                        : '',
                                    6,
                                  ),
                                  _buildPermitCell(
                                    context,
                                    user.foodHandlersExpiration,
                                    8,
                                  ),
                                  if (showManagerPermit)
                                    Consumer(
                                      builder: (context, ref, _) {
                                        bool requiresPermit = false;
                                        final userStoreSettings =
                                            user.store != null
                                            ? ref
                                                  .watch(
                                                    specificStoreSettingsProvider(
                                                      user.store!,
                                                    ),
                                                  )
                                                  .valueOrNull
                                            : settings;
                                        if (userStoreSettings != null &&
                                            user.title != null) {
                                          TitleConfig? titleConfig =
                                              userStoreSettings.titles
                                                  .where(
                                                    (t) => t.name == user.title,
                                                  )
                                                  .firstOrNull;
                                          titleConfig ??= userStoreSettings.tags
                                              .where(
                                                (t) => t.name == user.title,
                                              )
                                              .firstOrNull;
                                          requiresPermit =
                                              titleConfig?.mgrPermit == true;
                                        }

                                        return _buildPermitCell(
                                          context,
                                          user.managerPermitExpiration,
                                          8,
                                          isRequired: requiresPermit,
                                        );
                                      },
                                    ),
                                  _buildDataCell(
                                    context,
                                    user.startDate != null
                                        ? user.startDate!
                                              .toIso8601String()
                                              .split('T')
                                              .first
                                        : '',
                                    8,
                                  ),
                                  _buildPillCell(
                                    memberStatus(user),
                                    switch (memberStatus(user)) {
                                      'Active' => AppTheme.green,
                                      'Leaving' => AppTheme.primaryRed,
                                      _ => Colors.grey,
                                    },
                                    6,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () =>
              Center(child: CircularProgressIndicator(color: AppTheme.accent)),
          error: (e, st) => Center(
            child: Text(
              'Error loading users: $e',
              style: TextStyle(color: AppTheme.primaryRed),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddMemberDialog extends ConsumerStatefulWidget {
  const _AddMemberDialog();

  @override
  ConsumerState<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<_AddMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _positionController = TextEditingController();
  final _designationController = TextEditingController();
  final _workingTimeController = TextEditingController();
  final _titleController = TextEditingController();
  List<String> _tags = [];
  final _storeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _positionController.dispose();
    _designationController.dispose();
    _workingTimeController.dispose();
    _titleController.dispose();
    _storeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      final currentStoreId = ref.read(currentStoreIdProvider);

      final newUser = UserModel(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        position: _positionController.text.trim(),
        designation: _designationController.text.trim(),
        workingTime: _workingTimeController.text.trim(),
        title: _titleController.text.trim(),
        additionalTags: _tags,
        store: currentStoreId == null ? _storeController.text.trim() : null,
        status: 'Active',
      );

      await firestoreService.createUser(newUser);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating member: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSettingsDropdown({
    required BuildContext context,
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    if (options.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const SizedBox(
                    width: 800,
                    height: 600,
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      child: SettingsView(),
                    ),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            label: Text('Add $label in Settings'),
          ),
        ],
      );
    }

    final uniqueOptions = options.toSet().toList();
    return DropdownButtonFormField<String>(
      initialValue: uniqueOptions.contains(value)
          ? value
          : (uniqueOptions.isNotEmpty ? uniqueOptions.first : null),
      onChanged: onChanged,
      items: uniqueOptions
          .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
          .toList(),
      decoration: InputDecoration(labelText: label),
      style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
      dropdownColor: Theme.of(context).cardColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(storeSettingsProvider).value ?? StoreSettingsModel();
    final currentStoreId = ref.watch(currentStoreIdProvider);

    return AlertDialog(
      title: Text(
        'New Team Member',
        style: TextStyle(
          color: Theme.of(context).textTheme.titleLarge?.color,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: Theme.of(context).cardColor,
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _firstNameController,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  decoration: const InputDecoration(labelText: 'First Name'),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lastNameController,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  decoration: const InputDecoration(labelText: 'Last Name'),
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                if (currentStoreId == null) ...[
                  Builder(
                    builder: (context) {
                      final allStoresAsync = ref.watch(allStoresStreamProvider);
                      return allStoresAsync.when(
                        data: (stores) {
                          if (stores.isEmpty) return const SizedBox.shrink();

                          // Ensure _storeController.text is valid, else default to first store
                          if (!stores.any(
                            (s) => s['id'] == _storeController.text,
                          )) {
                            _storeController.text =
                                stores.first['id'] as String;
                          }

                          return DropdownButtonFormField<String>(
                            initialValue: _storeController.text,
                            onChanged: (val) {
                              if (val != null) _storeController.text = val;
                            },
                            items: stores.map((s) {
                              return DropdownMenuItem(
                                value: s['id'] as String,
                                child: Text(
                                  s['name'] as String? ?? 'Untitled Store',
                                ),
                              );
                            }).toList(),
                            decoration: const InputDecoration(
                              labelText: 'Store',
                            ),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                            dropdownColor: Theme.of(context).cardColor,
                          );
                        },
                        loading: () => const CircularProgressIndicator(),
                        error: (e, st) => Text('Error loading stores: $e'),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                _buildSettingsDropdown(
                  context: context,
                  label: 'Position',
                  value: _positionController.text,
                  options: settings.positions,
                  onChanged: (val) {
                    if (val != null) _positionController.text = val;
                  },
                ),
                const SizedBox(height: 16),
                _buildSettingsDropdown(
                  context: context,
                  label: 'Designation',
                  value: _designationController.text,
                  options: settings.designations,
                  onChanged: (val) {
                    if (val != null) _designationController.text = val;
                  },
                ),
                const SizedBox(height: 16),
                _buildSettingsDropdown(
                  context: context,
                  label: 'Title',
                  value: _titleController.text,
                  options: settings.titles.map((e) => e.name).toList(),
                  onChanged: (val) {
                    if (val != null) _titleController.text = val;
                  },
                ),
                const SizedBox(height: 16),
                _buildSettingsDropdown(
                  context: context,
                  label: 'Working Time',
                  value: _workingTimeController.text,
                  options: settings.workingTimes,
                  onChanged: (val) {
                    if (val != null) _workingTimeController.text = val;
                  },
                ),
                const SizedBox(height: 16),
                MultiSelectField(
                  decoration: const InputDecoration(
                    labelText: 'Additional tags',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontSize: 16,
                  ),
                  options: settings.tags.map((e) => e.name).toList(),
                  selected: _tags,
                  onChanged: (tags) => setState(() => _tags = tags),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save Member'),
        ),
      ],
    );
  }
}

/// Checklists a team member is currently working on: the one linked to their
/// title/tag plus any assigned directly, excluding completed or empty ones.
/// Mirrors the logic on the member detail page.
List<ChecklistConfig> activeChecklistsFor(
  UserModel user,
  StoreSettingsModel? settings,
) {
  if (settings == null) return const [];
  final result = <ChecklistConfig>[];

  if (user.title != null) {
    TitleConfig? titleConfig = settings.titles
        .where((t) => t.name == user.title)
        .firstOrNull;
    titleConfig ??= settings.tags
        .where((t) => t.name == user.title)
        .firstOrNull;
    if (titleConfig != null &&
        titleConfig.linkChecklist &&
        titleConfig.linkedChecklistId != null) {
      final cl = settings.checklists
          .where((c) => c.id == titleConfig!.linkedChecklistId)
          .firstOrNull;
      if (cl != null) result.add(cl);
    }
  }

  for (final cid in user.assignedChecklists ?? const <String>[]) {
    final cl = settings.checklists.where((c) => c.id == cid).firstOrNull;
    if (cl != null && !result.any((c) => c.id == cl.id)) result.add(cl);
  }

  final completed = user.completedChecklists ?? const <String>[];
  return result
      .where((c) => c.items.isNotEmpty && !completed.contains(c.id))
      .toList();
}
