import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
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
  bool _showFilters = false;

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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onHeaderTap(text),
          child: Container(
            height: 36,
            padding: const EdgeInsets.only(right: 8.0),
            alignment: Alignment.centerLeft,
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

  Widget _buildAvgShiftsCell(UserModel user, int flex) {
    return Expanded(
      flex: flex,
      child: _RosterShiftAdjuster(user: user),
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

    int activeDropdownFilterCount = 0;
    if (_filterTitle.isNotEmpty) activeDropdownFilterCount++;
    if (_filterPosition.isNotEmpty) activeDropdownFilterCount++;
    if (_filterDesignation.isNotEmpty) activeDropdownFilterCount++;
    if (_filterWorkingTime.isNotEmpty) activeDropdownFilterCount++;
    if (_filterStatus.toSet().difference(_defaultStatus.toSet()).isNotEmpty ||
        _defaultStatus.toSet().difference(_filterStatus.toSet()).isNotEmpty) {
      activeDropdownFilterCount++;
    }

    const double controlHeight = 44.0;

    final addButton = SizedBox(
      height: controlHeight,
      child: ElevatedButton.icon(
        onPressed: () => _showAddMemberDialog(context, ref),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F4C75),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        icon: const Icon(Icons.person_add_rounded, size: 18),
        label: const Text(
          'Add Team Member',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );

    final filterButton = SizedBox(
      height: controlHeight,
      child: ElevatedButton.icon(
        onPressed: () {
          setState(() {
            _showFilters = !_showFilters;
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _showFilters
              ? const Color(0xFF0F4C75).withValues(alpha: 0.12)
              : Theme.of(context).cardColor,
          foregroundColor: _showFilters
              ? const Color(0xFF0F4C75)
              : Theme.of(context).textTheme.bodyLarge?.color,
          elevation: 0,
          side: BorderSide(
            color: _showFilters
                ? const Color(0xFF0F4C75)
                : Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(
          Icons.filter_list_rounded,
          size: 18,
          color: _showFilters
              ? const Color(0xFF0F4C75)
              : Theme.of(context).textTheme.bodyLarge?.color,
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Filter',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            if (activeDropdownFilterCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F4C75),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activeDropdownFilterCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final searchField = SizedBox(
      height: controlHeight,
      child: TextField(
        controller: _searchController,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyLarge?.color,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Search team members...',
          hintStyle: const TextStyle(fontSize: 14),
          prefixIcon: const Icon(Icons.search, size: 20),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  splashRadius: 16,
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          isDense: true,
        ),
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
      ),
    );

    return Container(
      // Matches the gap under the table header (6 cell + 8 table gap) so the
      // header text has equal space above and below.
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 12),
              addButton,
              const SizedBox(width: 12),
              filterButton,
            ],
          ),
          if (_showFilters) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final filterItems = [
                  MultiSelectFilter(
                    label: 'Title',
                    options: uniqueTitles,
                    selected: _filterTitle,
                    onChanged: (v) => setState(() => _filterTitle = v),
                  ),
                  MultiSelectFilter(
                    label: 'Position',
                    options: uniquePositions,
                    selected: _filterPosition,
                    onChanged: (v) => setState(() => _filterPosition = v),
                  ),
                  MultiSelectFilter(
                    label: 'Designation',
                    options: uniqueDesignations,
                    selected: _filterDesignation,
                    onChanged: (v) => setState(() => _filterDesignation = v),
                  ),
                  MultiSelectFilter(
                    label: 'Working Time',
                    options: uniqueWorkingTimes,
                    selected: _filterWorkingTime,
                    onChanged: (v) => setState(() => _filterWorkingTime = v),
                  ),
                  MultiSelectFilter(
                    label: 'Status',
                    options: uniqueStatuses,
                    selected: _filterStatus,
                    onChanged: (v) => setState(() => _filterStatus = v),
                  ),
                ];

                final clearButton = IconButton(
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
                );

                // Filters share the full width evenly; once each would be
                // narrower than 140 the row scrolls sideways instead.
                const gap = 8.0;
                const minFilterWidth = 140.0;
                final clearWidth = hasActiveFilters ? gap + 48.0 : 0.0;
                final filterWidth = max(
                  minFilterWidth,
                  (box.maxWidth - gap * (filterItems.length - 1) - clearWidth) /
                      filterItems.length,
                );

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < filterItems.length; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        SizedBox(width: filterWidth, child: filterItems[i]),
                      ],
                      if (hasActiveFilters) ...[
                        const SizedBox(width: gap),
                        SizedBox(width: 48, child: clearButton),
                      ],
                    ],
                  ),
                );
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
            final currentUser = ref.watch(currentUserProvider);
            final ownedStoresList =
                (currentUser?['owned_stores'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            final visibleStores = ownedStoresList.isNotEmpty
                ? allStores
                      .where((s) => ownedStoresList.contains(s['id']))
                      .toList()
                : allStores;

            if (currentStoreId != null) {
              if (settingsAsync.isLoading) isLoadingSettings = true;
              if (settings != null) {
                showManagerPermit =
                    settings.titles.any((t) => t.mgrPermit) ||
                    settings.tags.any((t) => t.mgrPermit);
              }
            } else {
              for (final store in visibleStores) {
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
                  if (active.isEmpty) return '';
                  final raw = active.first.name;
                  final clean = raw
                      .replaceAll(
                        RegExp(r'\bchecklist\b', caseSensitive: false),
                        '',
                      )
                      .trim();
                  return clean.isNotEmpty ? clean : (user.title ?? raw);
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
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                                context.go('/member/${user.id}?from=/');
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
                                          final applicable = userChecklist
                                              .tasksForPosition(user.position);
                                          final completedCount = applicable
                                              .where(
                                                (i) => done.contains(
                                                  i.text.trim(),
                                                ),
                                              )
                                              .length;
                                          final totalCount = applicable.length;
                                          final extraCount =
                                              activeChecklists.length - 1;

                                          String checklistTitle = userChecklist
                                              .name
                                              .replaceAll(
                                                RegExp(
                                                  r'\bchecklist\b',
                                                  caseSensitive: false,
                                                ),
                                                '',
                                              )
                                              .trim();
                                          if (checklistTitle.isEmpty) {
                                            checklistTitle =
                                                (user.title != null &&
                                                    user.title!
                                                        .trim()
                                                        .isNotEmpty)
                                                ? user.title!.trim()
                                                : userChecklist.name;
                                          }

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
                                                          checklistTitle,
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
                                            titleConfig.color.isNotEmpty) {
                                          titleColor =
                                              AppTheme.getColorFromName(
                                                titleConfig.color,
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
                                  _buildAvgShiftsCell(user, 6),
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
  final _preferredNameController = TextEditingController();
  bool _showPreferredName = false;

  String? _selectedTitle;
  DateTime _startDate = DateTime.now();
  final _startDateController = TextEditingController();

  String? _selectedPosition;
  String? _selectedDesignation;
  String? _selectedWorkingTime;
  List<String> _selectedTags = [];

  final _avgShiftsController = TextEditingController();
  final _payRateController = TextEditingController();
  DateTime? _foodPermitDate;
  final _foodPermitController = TextEditingController();

  final _generalNotesController = TextEditingController();
  final _hiringNotesController = TextEditingController();

  bool _isLoading = false;
  bool _initializedDefaults = false;

  @override
  void initState() {
    super.initState();
    _startDateController.text = _formatDate(_startDate);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _preferredNameController.dispose();
    _startDateController.dispose();
    _avgShiftsController.dispose();
    _payRateController.dispose();
    _foodPermitController.dispose();
    _generalNotesController.dispose();
    _hiringNotesController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  DateTime? _parseDate(String s) {
    final trimmed = s.trim();
    final parts = trimmed.split('/');
    if (parts.length == 3) {
      final m = int.tryParse(parts[0]);
      final d = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (m != null && d != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return DateTime.tryParse(trimmed);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      final currentStoreId = ref.read(currentStoreIdProvider);
      final currentUser = ref.read(currentUserProvider);
      final ownedStoresList =
          (currentUser?['owned_stores'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final storeId =
          currentStoreId ??
          (ownedStoresList.isNotEmpty
              ? ownedStoresList.first
              : (ref
                            .read(allStoresStreamProvider)
                            .valueOrNull
                            ?.firstOrNull?['id']
                        as String? ??
                    'QYfhsc0dBHLBbgOflHsA'));

      DateTime? foodPermit;
      if (_foodPermitController.text.trim().isNotEmpty) {
        foodPermit =
            _foodPermitDate ?? _parseDate(_foodPermitController.text.trim());
      }

      double? payRate;
      final payText = _payRateController.text.replaceAll(r'$', '').trim();
      if (payText.isNotEmpty) {
        payRate = double.tryParse(payText);
      }

      final parsedStartDate =
          _parseDate(_startDateController.text) ?? _startDate;

      final newUser = UserModel(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        preferredName: _preferredNameController.text.trim().isEmpty
            ? null
            : _preferredNameController.text.trim(),
        title: _selectedTitle,
        startDate: parsedStartDate,
        position: _selectedPosition,
        designation: _selectedDesignation,
        workingTime: _selectedWorkingTime,
        additionalTags: _selectedTags,
        avgShifts: _avgShiftsController.text.trim().isEmpty
            ? null
            : _avgShiftsController.text.trim(),
        payRate: payRate,
        foodHandlersExpiration: foodPermit,
        generalNotes: _generalNotesController.text.trim().isEmpty
            ? null
            : _generalNotesController.text.trim(),
        hiringNotes: _hiringNotesController.text.trim().isEmpty
            ? null
            : _hiringNotesController.text.trim(),
        store: storeId,
        status: 'Active',
      );

      await firestoreService.createUser(newUser);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added ${newUser.firstName} ${newUser.lastName} to team',
            ),
          ),
        );
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

  Widget _buildFieldLabel(String text, {bool isRequired = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color:
                  Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withValues(alpha: 0.85) ??
                  Colors.grey.shade600,
            ),
          ),
          if (isRequired) ...[
            const SizedBox(width: 3),
            const Text(
              '*',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F4C75),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    String? hintText,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    VoidCallback? onTap,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      readOnly: readOnly,
      onTap: onTap,
      style: TextStyle(
        fontSize: 14,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        suffixIcon: suffixIcon,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        filled: true,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF0F4C75), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primaryRed),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<String> options,
    required String placeholder,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      value: options.contains(value) ? value : null,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
      dropdownColor: Theme.of(context).cardColor,
      style: TextStyle(
        fontSize: 14,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
      hint: Text(
        placeholder,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        filled: true,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF0F4C75), width: 1.5),
        ),
      ),
      items: options.map((opt) {
        return DropdownMenuItem<String>(
          value: opt,
          child: Text(opt, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(storeSettingsProvider).value ?? const StoreSettingsModel();

    if (!_initializedDefaults) {
      _initializedDefaults = true;
      if (settings.titles.isNotEmpty) {
        _selectedTitle = settings.titles.first.name;
      }
    }

    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Add Team Member',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.titleLarge?.color,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: Colors.grey,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: theme.dividerColor),

              // Scrollable content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final isWide = box.maxWidth >= 680;

                      Widget col(Widget child, {int flex = 1}) =>
                          Expanded(flex: flex, child: child);

                      // Row 1: First Name (+ preferred name pill), Last Name, Title, Start Date
                      final firstNameField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('FIRST NAME', isRequired: true),
                          _buildTextInput(
                            controller: _firstNameController,
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? 'First name is required'
                                : null,
                          ),
                          if (!_showPreferredName &&
                              _preferredNameController.text.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: InkWell(
                                  onTap: () =>
                                      setState(() => _showPreferredName = true),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF0F4C75,
                                      ).withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF0F4C75,
                                        ).withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 13,
                                          color: Color(0xFF0F4C75),
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Preferred Name?',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F4C75),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildFieldLabel('PREFERRED NAME'),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _preferredNameController.clear();
                                            _showPreferredName = false;
                                          });
                                        },
                                        child: Text(
                                          'Hide',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  _buildTextInput(
                                    controller: _preferredNameController,
                                    hintText: 'e.g. Alex',
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );

                      final lastNameField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('LAST NAME', isRequired: true),
                          _buildTextInput(
                            controller: _lastNameController,
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? 'Last name is required'
                                : null,
                          ),
                        ],
                      );

                      final titleField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('TITLE'),
                          _buildDropdown(
                            value: _selectedTitle,
                            options: settings.titles
                                .map((e) => e.name)
                                .toList(),
                            placeholder: '-- Select Title --',
                            onChanged: (val) =>
                                setState(() => _selectedTitle = val),
                          ),
                        ],
                      );

                      final startDateField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('START DATE'),
                          _buildTextInput(
                            controller: _startDateController,
                            readOnly: true,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _startDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() {
                                  _startDate = picked;
                                  _startDateController.text = _formatDate(
                                    picked,
                                  );
                                });
                              }
                            },
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                                color: Colors.grey,
                              ),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _startDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _startDate = picked;
                                    _startDateController.text = _formatDate(
                                      picked,
                                    );
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      );

                      // Row 2: Position, Designation, Working Time, Additional Tags
                      final positionField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('POSITION', isRequired: true),
                          _buildDropdown(
                            value: _selectedPosition,
                            options: settings.positions,
                            placeholder: '-- Select Position --',
                            validator: (val) =>
                                settings.positions.isNotEmpty &&
                                    (val == null || val.isEmpty)
                                ? 'Position is required'
                                : null,
                            onChanged: (val) =>
                                setState(() => _selectedPosition = val),
                          ),
                        ],
                      );

                      final designationField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('DESIGNATION', isRequired: true),
                          _buildDropdown(
                            value: _selectedDesignation,
                            options: settings.designations,
                            placeholder: '-- Select Designation --',
                            validator: (val) =>
                                settings.designations.isNotEmpty &&
                                    (val == null || val.isEmpty)
                                ? 'Designation is required'
                                : null,
                            onChanged: (val) =>
                                setState(() => _selectedDesignation = val),
                          ),
                        ],
                      );

                      final workingTimeField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('WORKING TIME', isRequired: true),
                          _buildDropdown(
                            value: _selectedWorkingTime,
                            options: settings.workingTimes,
                            placeholder: '-- Select Working Time --',
                            validator: (val) =>
                                settings.workingTimes.isNotEmpty &&
                                    (val == null || val.isEmpty)
                                ? 'Working time is required'
                                : null,
                            onChanged: (val) =>
                                setState(() => _selectedWorkingTime = val),
                          ),
                        ],
                      );

                      final tagsField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('ADDITIONAL TAGS'),
                          MultiSelectField(
                            options: settings.tags.map((e) => e.name).toList(),
                            selected: _selectedTags,
                            emptyText: '-- Select Additional Tags --',
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).scaffoldBackgroundColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF0F4C75),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onChanged: (tags) =>
                                setState(() => _selectedTags = tags),
                          ),
                        ],
                      );

                      // Row 3: Avg Shifts / Wk, Pay ($ / Hr), Food Permit Exp.
                      final avgShiftsField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('AVG SHIFTS / WK'),
                          _buildTextInput(
                            controller: _avgShiftsController,
                            hintText: 'e.g. 4',
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      );

                      final payRateField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('PAY (\$ / HR)'),
                          _buildTextInput(
                            controller: _payRateController,
                            hintText: 'e.g. \$15.00',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ],
                      );

                      final foodPermitField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('FOOD PERMIT EXP.'),
                          _buildTextInput(
                            controller: _foodPermitController,
                            hintText: 'mm/dd/yyyy',
                            readOnly: true,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _foodPermitDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() {
                                  _foodPermitDate = picked;
                                  _foodPermitController.text = _formatDate(
                                    picked,
                                  );
                                });
                              }
                            },
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_foodPermitDate != null)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _foodPermitDate = null;
                                        _foodPermitController.clear();
                                      });
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _foodPermitDate ?? DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        _foodPermitDate = picked;
                                        _foodPermitController.text =
                                            _formatDate(picked);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );

                      // Row 4: General Notes, Hiring Notes
                      final generalNotesField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('GENERAL NOTES'),
                          _buildTextInput(
                            controller: _generalNotesController,
                            hintText: 'Member notes...',
                            minLines: 3,
                            maxLines: 4,
                          ),
                        ],
                      );

                      final hiringNotesField = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('HIRING NOTES'),
                          _buildTextInput(
                            controller: _hiringNotesController,
                            hintText: 'Hiring notes, availability...',
                            minLines: 3,
                            maxLines: 4,
                          ),
                        ],
                      );

                      if (isWide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                col(firstNameField),
                                const SizedBox(width: 16),
                                col(lastNameField),
                                const SizedBox(width: 16),
                                col(titleField),
                                const SizedBox(width: 16),
                                col(startDateField),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                col(positionField),
                                const SizedBox(width: 16),
                                col(designationField),
                                const SizedBox(width: 16),
                                col(workingTimeField),
                                const SizedBox(width: 16),
                                col(tagsField),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                col(avgShiftsField),
                                const SizedBox(width: 16),
                                col(payRateField),
                                const SizedBox(width: 16),
                                col(foodPermitField),
                                const SizedBox(width: 16),
                                col(const SizedBox.shrink()),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                col(generalNotesField),
                                const SizedBox(width: 16),
                                col(hiringNotesField),
                              ],
                            ),
                          ],
                        );
                      }

                      // Responsive 2-column or 1-column layout for narrower dialogs
                      final isTablet = box.maxWidth >= 460;
                      if (isTablet) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                col(firstNameField),
                                const SizedBox(width: 14),
                                col(lastNameField),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                col(titleField),
                                const SizedBox(width: 14),
                                col(startDateField),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                col(positionField),
                                const SizedBox(width: 14),
                                col(designationField),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                col(workingTimeField),
                                const SizedBox(width: 14),
                                col(tagsField),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                col(avgShiftsField),
                                const SizedBox(width: 14),
                                col(payRateField),
                              ],
                            ),
                            const SizedBox(height: 16),
                            foodPermitField,
                            const SizedBox(height: 16),
                            generalNotesField,
                            const SizedBox(height: 16),
                            hiringNotesField,
                          ],
                        );
                      }

                      // Narrow 1-column layout
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          firstNameField,
                          const SizedBox(height: 14),
                          lastNameField,
                          const SizedBox(height: 14),
                          titleField,
                          const SizedBox(height: 14),
                          startDateField,
                          const SizedBox(height: 14),
                          positionField,
                          const SizedBox(height: 14),
                          designationField,
                          const SizedBox(height: 14),
                          workingTimeField,
                          const SizedBox(height: 14),
                          tagsField,
                          const SizedBox(height: 14),
                          avgShiftsField,
                          const SizedBox(height: 14),
                          payRateField,
                          const SizedBox(height: 14),
                          foodPermitField,
                          const SizedBox(height: 14),
                          generalNotesField,
                          const SizedBox(height: 14),
                          hiringNotesField,
                        ],
                      );
                    },
                  ),
                ),
              ),

              // Footer
              Divider(height: 1, thickness: 1, color: theme.dividerColor),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(color: theme.dividerColor),
                        foregroundColor: theme.textTheme.bodyLarge?.color,
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4C75),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
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
                          : const Text(
                              'Save Member',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
      .where(
        (c) =>
            c.tasksForPosition(user.position).isNotEmpty &&
            !completed.contains(c.id),
      )
      .toList();
}

class _RosterShiftAdjuster extends ConsumerStatefulWidget {
  final UserModel user;
  const _RosterShiftAdjuster({required this.user});

  @override
  ConsumerState<_RosterShiftAdjuster> createState() =>
      _RosterShiftAdjusterState();
}

class _RosterShiftAdjusterState extends ConsumerState<_RosterShiftAdjuster> {
  bool _isHovered = false;
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = int.tryParse(widget.user.avgShifts ?? '0') ?? 0;
  }

  @override
  void didUpdateWidget(covariant _RosterShiftAdjuster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user.avgShifts != oldWidget.user.avgShifts) {
      _count = int.tryParse(widget.user.avgShifts ?? '0') ?? 0;
    }
  }

  Future<void> _adjust(int delta) async {
    final newCount = (_count + delta).clamp(0, 99);
    if (newCount == _count) return;
    setState(() => _count = newCount);
    try {
      final updatedUser = widget.user.copyWith(avgShifts: '$newCount');
      final firestoreService = ref.read(baseFirestoreServiceProvider);
      await firestoreService.updateUser(updatedUser);
    } catch (e) {
      if (mounted) {
        setState(() {
          _count = int.tryParse(widget.user.avgShifts ?? '0') ?? 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$_count',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 18,
              height: 28,
              child: _isHovered
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => _adjust(1),
                          borderRadius: BorderRadius.circular(2),
                          child: Icon(
                            Icons.keyboard_arrow_up,
                            size: 13,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        InkWell(
                          onTap: _count > 0 ? () => _adjust(-1) : null,
                          borderRadius: BorderRadius.circular(2),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 13,
                            color: _count > 0
                                ? Theme.of(context).textTheme.bodyLarge?.color
                                : Theme.of(context).disabledColor,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
