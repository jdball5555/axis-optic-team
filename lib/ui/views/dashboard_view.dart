import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:axis_team/ui/widgets/dashboard_widgets.dart';
import 'package:axis_team/core/theme/app_theme.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/models/store_settings_model.dart';
import 'package:axis_team/providers/app_providers.dart';

import 'dart:convert';
import 'dart:math';
import 'package:axis_team/ui/widgets/unsaved_changes_dialog.dart';

final dashboardConfigProvider = StateProvider<List<CustomDashboardItem>>(
  (ref) => [],
);
final dashboardEditModeProvider = StateProvider<bool>((ref) => false);

const double gridSize = 50.0;
double snap(double v) => (v / gridSize).roundToDouble() * gridSize;

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += gridSize) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += gridSize) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CustomDashboardItem {
  final String id;
  final String type;
  double x;
  double y;
  double width;
  double height;
  bool isSelected;

  double _startX = 0;
  double _startY = 0;
  double _startWidth = 0;
  double _startHeight = 0;

  CustomDashboardItem({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.isSelected = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory CustomDashboardItem.fromJson(Map<String, dynamic> json) {
    return CustomDashboardItem(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 300,
      height: (json['height'] as num?)?.toDouble() ?? 200,
    );
  }
}

class DashboardView extends ConsumerStatefulWidget {
  final bool isConfigMode;
  const DashboardView({super.key, this.isConfigMode = false});

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  bool _isDashboardEditing = false;
  bool _seeding = false;

  /// TEMPORARY: fills a store with the sample team and schedules.
  Future<void> _seedSampleData() async {
    final firestoreService = ref.read(firestoreServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final store = await firestoreService.sampleStore();
    if (!mounted) return;
    if (store == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Create a store first.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        title: Text('Fill ${store.name} with sample data?'),
        content: const Text(
          'This replaces the store\'s team with the sample team (each with a '
          'fake login), their availability and time off, and sets up titles, '
          'tags, positions and two schedules: Front of House and Kitchen.\n\n'
          'This week gets the sample schedule (posted). Next week gets the '
          'day templates with nobody on them, ready to build.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fill store'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _seeding = true);
    try {
      final summary = await firestoreService.seedSampleData(store.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${store.name}: $summary'),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t add the sample data: $e')),
      );
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }
  String? _loadedStoreKey;

  /// Layout as last loaded from / saved to Firestore, for change detection.
  String? _savedLayout;
  bool _reportedDirty = false;

  String _layoutJson() => jsonEncode(_items.map((e) => e.toJson()).toList());

  bool get _hasUnsavedLayout =>
      _isDashboardEditing && _savedLayout != null && _layoutJson() != _savedLayout;

  /// Tells the sidebar (store switcher + nav) whether to show the
  /// save / discard / cancel prompt.
  void _syncUnsavedState() {
    final dirty = _hasUnsavedLayout;
    if (dirty == _reportedDirty) return;
    _reportedDirty = dirty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(unsavedChangesProvider.notifier).state = dirty;
      ref.read(saveChangesActionProvider.notifier).state =
          dirty ? () => _saveLayout() : null;
      ref.read(discardChangesActionProvider.notifier).state =
          dirty ? _discardLayoutChanges : null;
    });
  }

  void _exitEditMode() {
    _isDashboardEditing = false;
    for (final i in _items) {
      i.isSelected = false;
    }
  }

  Future<void> _saveLayout({bool showMessage = false}) async {
    final currentUser = ref.read(currentUserProvider);
    final storeKey = ref.read(currentStoreIdProvider) ?? 'all';
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser['id'])
          .collection('dashboards')
          .doc(storeKey)
          .set({'items': _items.map((e) => e.toJson()).toList()});
      if (!mounted) return;
      setState(() {
        _savedLayout = _layoutJson();
        _exitEditMode();
      });
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dashboard saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  /// Back arrow while editing the layout: prompt if there are changes,
  /// otherwise just return to the normal dashboard.
  Future<void> _leaveEditMode() async {
    if (_hasUnsavedLayout) {
      final choice = await showUnsavedChangesDialog(context);
      if (choice == null) return;
      if (choice == UnsavedChoice.save) {
        await _saveLayout();
        return;
      }
      _discardLayoutChanges();
      return;
    }
    setState(_exitEditMode);
  }

  void _discardLayoutChanges() {
    if (!mounted) return;
    setState(() {
      final saved = _savedLayout;
      if (saved != null) {
        _items = (jsonDecode(saved) as List)
            .map((e) => CustomDashboardItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      _exitEditMode();
    });
  }

  final List<String> _validDashboardTypes = [
    'tenure',
    'deficits',
    'permit',
    'tenure_by_year',
    'welcome_quote',
    'tenure_dist',
    'working_time',
    'working_time_pie',
    'working_time_vertical',
    'title',
    'title_pie',
    'title_vertical',
    'position',
    'position_pie',
    'position_vertical',
    'designation',
    'designation_pie',
    'designation_vertical',
  ];

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final GlobalKey _dashboardViewKey = GlobalKey();

  List<CustomDashboardItem> _items = [];

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  List<CustomDashboardItem> _getDefaultItems() {
    return [
      CustomDashboardItem(
        id: '1',
        type: 'tenure',
        x: 50,
        y: 50,
        width: 350,
        height: 150,
      ),
      CustomDashboardItem(
        id: '2',
        type: 'deficits',
        x: 400,
        y: 50,
        width: 350,
        height: 150,
      ),
      CustomDashboardItem(
        id: '3',
        type: 'working_time',
        x: 50,
        y: 200,
        width: 350,
        height: 250,
      ),
      CustomDashboardItem(
        id: '4',
        type: 'position',
        x: 400,
        y: 200,
        width: 350,
        height: 250,
      ),
      CustomDashboardItem(
        id: '5',
        type: 'designation',
        x: 750,
        y: 200,
        width: 350,
        height: 250,
      ),
      CustomDashboardItem(
        id: '6',
        type: 'tenure_dist',
        x: 50,
        y: 450,
        width: 350,
        height: 250,
      ),
      CustomDashboardItem(
        id: '7',
        type: 'permit',
        x: 400,
        y: 450,
        width: 350,
        height: 250,
      ),
      CustomDashboardItem(
        id: '8',
        type: 'tenure_by_year',
        x: 750,
        y: 450,
        width: 350,
        height: 250,
      ),
    ];
  }

  void _loadDashboardConfig() async {
    final currentUser = ref.read(currentUserProvider);
    final currentStoreId = ref.read(currentStoreIdProvider);
    final storeKey = currentStoreId ?? 'all';

    if (currentUser == null) return;
    if (_loadedStoreKey == storeKey) return;

    _loadedStoreKey = storeKey;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser['id'])
          .collection('dashboards')
          .doc(storeKey)
          .get();

      if (doc.exists &&
          doc.data() != null &&
          doc.data()!.containsKey('items') &&
          doc.data()!['items'] != null) {
        final dynamic itemsData = doc.data()!['items'];
        if (itemsData is List) {
          final List<CustomDashboardItem> parsedItems = [];
          for (var e in itemsData) {
            try {
              if (e is Map) {
                final item = CustomDashboardItem.fromJson(
                  Map<String, dynamic>.from(e),
                );
                if (_validDashboardTypes.contains(item.type)) {
                  parsedItems.add(item);
                }
              }
            } catch (err) {
              debugPrint('Error parsing dashboard item: $err');
            }
          }
          if (mounted) {
            setState(() {
              if (parsedItems.isNotEmpty) {
                _items = parsedItems;
              } else {
                _items = _getDefaultItems();
              }
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _items = _getDefaultItems();
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _items = _getDefaultItems();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      if (mounted && _items.isEmpty) {
        setState(() {
          _items = _getDefaultItems();
        });
      }
    }
    if (mounted) setState(() => _savedLayout = _layoutJson());
  }

  bool _hasCollision(CustomDashboardItem item) {
    for (var other in _items) {
      if (other.id == item.id) continue;
      // Add a tiny tolerance for floating point inaccuracies
      if (item.x < other.x + other.width - 1 &&
          item.x + item.width > other.x + 1 &&
          item.y < other.y + other.height - 1 &&
          item.y + item.height > other.y + 1) {
        return true;
      }
    }
    return false;
  }

  Offset _findBestPosition(double w, double h) {
    for (double y = 50; y < 5000; y += gridSize) {
      for (double x = 50; x < 1200; x += gridSize) {
        final testItem = CustomDashboardItem(
          id: 'test',
          type: 'test',
          x: x,
          y: y,
          width: w,
          height: h,
        );
        if (!_hasCollision(testItem)) {
          return Offset(x, y);
        }
      }
    }
    double newY = 0;
    if (_items.isNotEmpty) {
      newY = _items.map((e) => e.y + e.height).reduce(max) + 50;
    }
    return Offset(50, newY);
  }

  void _spaceEvenly() {
    final selected = _items.where((i) => i.isSelected).toList();
    if (selected.length < 3) return;

    selected.sort((a, b) => a.x.compareTo(b.x));

    double minX = selected.first.x;
    double maxX = selected.last.x + selected.last.width;
    double totalWidth = selected.fold(0.0, (sum, item) => sum + item.width);

    double remainingSpace = (maxX - minX) - totalWidth;
    double gap = snap(remainingSpace / (selected.length - 1));

    double currentX = minX;
    setState(() {
      for (var item in selected) {
        item.x = snap(currentX);
        currentX += item.width + gap;
      }

      // Revert if collisions occur
      bool collision = false;
      for (var item in selected) {
        if (_hasCollision(item)) collision = true;
      }
      if (collision) {
        // Not perfect, but we just ignore space evenly if it causes collisions for now.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(dashboardEditModeProvider)) {
      _isDashboardEditing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(dashboardEditModeProvider.notifier).state = false;
        _loadedStoreKey = null; // force reload of items when coming back
        setState(() {});
      });
    }

    _loadDashboardConfig();
    _syncUnsavedState();
    final usersAsyncValue = ref.watch(currentMembersProvider);
    final rosterNeedsAsyncValue = ref.watch(rosterNeedsStreamProvider);
    final allStores = ref.watch(allStoresStreamProvider).valueOrNull ?? [];
    final currentStoreId = ref.watch(currentStoreIdProvider);
    final settings =
        ref.watch(storeSettingsProvider).valueOrNull ??
        const StoreSettingsModel();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: usersAsyncValue.when(
        skipLoadingOnReload: true,
        data: (users) {
          final rosterNeeds = rosterNeedsAsyncValue.valueOrNull ?? {};
          return _buildDashboard(
            context,
            ref,
            users,
            rosterNeeds,
            allStores,
            currentStoreId,
            settings,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    WidgetRef ref,
    List<UserModel> users,
    Map<String, dynamic> rosterNeeds,
    List<Map<String, dynamic>> allStores,
    String? currentStoreId,
    StoreSettingsModel settings,
  ) {
    final totalUsers = users.length;

    final timeItems = settings.workingTimes
        .map(
          (t) => BarChartItem(t, users.where((u) => u.workingTime == t).length),
        )
        .toList();
    final posItems = settings.positions
        .map((p) => BarChartItem(p, users.where((u) => u.position == p).length))
        .toList();
    final desItems = settings.designations
        .map(
          (d) => BarChartItem(d, users.where((u) => u.designation == d).length),
        )
        .toList();
    final titleItems = settings.titles
        .map(
          (t) => BarChartItem(
            t.name,
            users.where((u) => u.title == t.name).length,
            color: AppTheme.getColorFromName(t.color),
          ),
        )
        .toList();

    int totalDays = 0;
    int validTenureUsers = 0;
    for (final u in users) {
      if (u.startDate != null) {
        totalDays += DateTime.now().difference(u.startDate!).inDays;
        validTenureUsers++;
      }
    }

    String avgTenureText = '0 yrs, 0 mos, 0 days';
    if (validTenureUsers > 0) {
      final avgDays = totalDays ~/ validTenureUsers;
      final years = avgDays ~/ 365;
      final months = (avgDays % 365) ~/ 30;
      final days = (avgDays % 365) % 30;
      avgTenureText = '$years yrs, $months mos, $days days';
    }

    final noPermitCount = users
        .where((u) => u.foodHandlersExpiration == null)
        .length;
    final overduePermitCount = users
        .where(
          (u) =>
              u.foodHandlersExpiration != null &&
              u.foodHandlersExpiration!.isBefore(DateTime.now()),
        )
        .length;
    final goodPermitCount = users
        .where(
          (u) =>
              u.foodHandlersExpiration != null &&
              u.foodHandlersExpiration!.isAfter(DateTime.now()),
        )
        .length;

    final year0Count = users
        .where(
          (u) =>
              u.startDate != null &&
              DateTime.now().difference(u.startDate!).inDays < 365,
        )
        .length;
    final year1Count = users
        .where(
          (u) =>
              u.startDate != null &&
              DateTime.now().difference(u.startDate!).inDays >= 365 &&
              DateTime.now().difference(u.startDate!).inDays < 730,
        )
        .length;
    final year2PlusCount = users
        .where(
          (u) =>
              u.startDate != null &&
              DateTime.now().difference(u.startDate!).inDays >= 730,
        )
        .length;

    final usersWithTenure = users.where((u) => u.startDate != null).toList();
    usersWithTenure.sort((a, b) => a.startDate!.compareTo(b.startDate!));

    final Map<String, List<UserModel>> positionGroups = {};
    for (final user in users) {
      final pos = user.position ?? 'Unassigned';
      final sid = user.store ?? 'unknown';
      positionGroups.putIfAbsent('${sid}_$pos', () => []).add(user);
    }

    int totalHiresNeeded = 0;
    int totalShiftDeficit = 0;
    List<String> deficitPills = [];

    for (final entry in rosterNeeds.entries) {
      final key = entry.key;
      final parts = key.split('_');
      final posName = parts.length > 1 ? parts.sublist(1).join('_') : key;
      final neededShiftsPerDay =
          int.tryParse(entry.value?.toString() ?? '0') ?? 0;
      final neededShiftsPerWeek = neededShiftsPerDay * 6;

      final membersInPos = positionGroups[key] ?? [];
      int coveredShiftsPerWeek = 0;
      for (final m in membersInPos) {
        coveredShiftsPerWeek += int.tryParse(m.avgShifts ?? '0') ?? 0;
      }

      final deficit = neededShiftsPerWeek - coveredShiftsPerWeek;
      if (deficit > 0) {
        totalShiftDeficit += deficit;
        final hiresForPos = (deficit / 5).ceil();
        totalHiresNeeded += hiresForPos;
        deficitPills.add('$posName: Need $deficit shifts ($hiresForPos hires)');
      }
    }

    Widget buildItemContent(String type, {double? height}) {
      switch (type) {
        case 'tenure':
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AVERAGE TEAM MEMBER TENURE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          avgTenureText,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).textTheme.titleLarge?.color,
                          ),
                        ),
                      ),
                      Icon(Icons.access_time, color: AppTheme.accent),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Based on $validTenureUsers active team members with recorded start dates',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
          );
        case 'deficits':
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Listener(
              onPointerSignal: (PointerSignalEvent event) {
                if (event is PointerScrollEvent) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (PointerSignalEvent e) {},
                  );
                }
              },
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          totalShiftDeficit > 0
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          color: totalShiftDeficit > 0
                              ? AppTheme.primaryRed
                              : AppTheme.blue,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'ROSTER STAFFING DEFICITS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                        if (totalShiftDeficit > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryRed,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$totalHiresNeeded Hires Needed',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (totalShiftDeficit > 0) ...[
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 8,
                        children: [
                          Text(
                            '$totalHiresNeeded Hires',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryRed,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text(
                              '(-$totalShiftDeficit shifts/wk)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (height == null || height > 160) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: deficitPills
                              .map((pill) => _buildDeficitPill(context, pill))
                              .toList(),
                        ),
                      ],
                    ] else ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 24.0),
                          child: Text(
                            'Store is fully staffed!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.blue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        case 'working_time':
          return timeItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Working Time Distribution',
                  icon: Icons.access_time,
                  iconColor: AppTheme.primaryRed,
                  child: SimpleBarChart(total: totalUsers, items: timeItems),
                );
        case 'working_time_pie':
          return timeItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Working Time Distribution',
                  icon: Icons.access_time,
                  iconColor: AppTheme.primaryRed,
                  child: SimplePieChart(total: totalUsers, items: timeItems),
                );
        case 'working_time_vertical':
          return timeItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Working Time Distribution',
                  icon: Icons.access_time,
                  iconColor: AppTheme.primaryRed,
                  child: VerticalBarChart(total: totalUsers, items: timeItems),
                );
        case 'position':
          return posItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Position Distribution',
                  icon: Icons.work_outline,
                  iconColor: AppTheme.primaryRed,
                  child: SimpleBarChart(total: totalUsers, items: posItems),
                );
        case 'position_pie':
          return posItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Position Distribution',
                  icon: Icons.work_outline,
                  iconColor: AppTheme.primaryRed,
                  child: SimplePieChart(total: totalUsers, items: posItems),
                );
        case 'position_vertical':
          return posItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Position Distribution',
                  icon: Icons.work_outline,
                  iconColor: AppTheme.primaryRed,
                  child: VerticalBarChart(total: totalUsers, items: posItems),
                );
        case 'title':
          return titleItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Title Distribution',
                  icon: Icons.badge,
                  iconColor: AppTheme.primaryRed,
                  child: SimpleBarChart(total: totalUsers, items: titleItems),
                );
        case 'title_pie':
          return titleItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Title Distribution',
                  icon: Icons.badge,
                  iconColor: AppTheme.primaryRed,
                  child: SimplePieChart(total: totalUsers, items: titleItems),
                );
        case 'title_vertical':
          return titleItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Title Distribution',
                  icon: Icons.badge,
                  iconColor: AppTheme.primaryRed,
                  child: VerticalBarChart(total: totalUsers, items: titleItems),
                );
        case 'welcome_quote':
          final quotes = [
            "\"A leader is one who knows the way, goes the way, and shows the way.\" - John C. Maxwell",
            "\"The function of leadership is to produce more leaders, not more followers.\" - Ralph Nader",
            "\"Businesses don't succeed or fail, people do.\" - Truett Cathy",
            "\"If you want to go fast, go alone. If you want to go far, go together.\" - Truett Cathy",
            "\"To win in the marketplace you must first win in the workplace.\" - Doug Conant",
            "\"Your company’s culture is simply a combination of the behaviors you reward and the behaviors you tolerate.\" - Dave Ramsey",
            "\"Leaders are readers. If you want to lead, you must read.\" - Dave Ramsey",
          ];
          final userName =
              ref.read(currentUserProvider)?['first_name'] ?? 'there';
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Hello, $userName!',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).textTheme.titleLarge?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    quotes[DateTime.now().minute % quotes.length],
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
          );
        case 'designation':
          return desItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Designation Distribution',
                  icon: Icons.people,
                  iconColor: AppTheme.primaryRed,
                  child: SimpleBarChart(total: totalUsers, items: desItems),
                );
        case 'designation_pie':
          return desItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Designation Distribution',
                  icon: Icons.people,
                  iconColor: AppTheme.primaryRed,
                  child: SimplePieChart(total: totalUsers, items: desItems),
                );
        case 'designation_vertical':
          return desItems.isEmpty
              ? const SizedBox.shrink()
              : DashboardCard(
                  title: 'Designation Distribution',
                  icon: Icons.people,
                  iconColor: AppTheme.primaryRed,
                  child: VerticalBarChart(total: totalUsers, items: desItems),
                );
        case 'tenure_dist':
          return DashboardCard(
            title: 'Team Member Tenure',
            icon: Icons.bar_chart,
            iconColor: AppTheme.primaryRed,
            child: SimpleBarChart(
              total: usersWithTenure.isEmpty
                  ? 1
                  : usersWithTenure
                        .map(
                          (u) => DateTime.now().difference(u.startDate!).inDays,
                        )
                        .reduce((a, b) => a > b ? a : b),
              items: usersWithTenure.map((u) {
                final days = DateTime.now().difference(u.startDate!).inDays;
                final years = days ~/ 365;
                final months = (days % 365) ~/ 30;
                return BarChartItem(
                  '${u.lastName}, ${u.firstName}',
                  days,
                  customValueLabel:
                      "${years > 0 ? '$years yrs, ' : ''}$months mos",
                );
              }).toList(),
            ),
          );
        case 'permit':
          return DashboardCard(
            title: 'Permits',
            icon: Icons.check_box_outlined,
            iconColor: AppTheme.primaryRed,
            child: SimpleBarChart(
              total: totalUsers == 0 ? 1 : totalUsers,
              items: [
                BarChartItem('Don\'t Have One', noPermitCount),
                BarChartItem('Overdue', overduePermitCount),
                BarChartItem('Good', goodPermitCount),
              ],
            ),
          );
        case 'tenure_by_year':
          return DashboardCard(
            title: 'Tenure by Year',
            icon: Icons.calendar_today,
            iconColor: AppTheme.primaryRed,
            child: SimpleBarChart(
              total: validTenureUsers == 0 ? 1 : validTenureUsers,
              items: [
                BarChartItem('Year 0', year0Count),
                BarChartItem('Year 1', year1Count),
                BarChartItem('Year 2+', year2PlusCount),
              ],
            ),
          );
        default:
          return const SizedBox.shrink();
      }
    }

    final isShift =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (widget.isConfigMode) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back to Dashboard',
                        onPressed: () => context.go('/dashboard'),
                      ),
                      const SizedBox(width: 8),
                    ] else if (_isDashboardEditing) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back to Dashboard',
                        onPressed: _leaveEditMode,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (widget.isConfigMode) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          ref.read(dashboardEditModeProvider.notifier).state =
                              true;
                          context.go('/dashboard');
                        },
                        icon: const Icon(Icons.grid_view, size: 16),
                        label: const Text('Edit Dashboard Display'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    OutlinedButton.icon(
                      onPressed: () async {
                        final firestoreService = ref.read(
                          firestoreServiceProvider,
                        );
                        final allStores =
                            ref.read(currentStoreIdProvider) == null;
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: Theme.of(ctx).cardColor,
                            title: Text(
                              allStores
                                  ? 'Delete every team member in ALL stores?'
                                  : 'Delete every team member in this store?',
                            ),
                            content: const Text(
                              'This permanently deletes the team members and '
                              'everything tied to them: availability, time off, '
                              'HR events, posted schedules and their shifts on '
                              'every schedule day.\n\nSettings, templates, '
                              'positions, portal links and login accounts stay.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final n = await firestoreService.deleteAllData();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Deleted the team and their data ($n records).',
                              ),
                            ),
                          );
                        } catch (_) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Couldn\'t delete everything. Please try again.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_forever, size: 16),
                      label: const Text('Clear All'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryRed,
                        side: BorderSide(color: AppTheme.primaryRed),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _seeding ? null : _seedSampleData,
                      icon: _seeding
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.data_object, size: 16),
                      label: Text(
                        _seeding ? 'Seeding…' : 'Seed Sample Store Data',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryRed,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),

                    if (!_isDashboardEditing && !widget.isConfigMode)
                      IconButton(
                        onPressed: () {
                          ref.read(dashboardConfigProvider.notifier).state =
                              _items;
                          context.go('/dashboard/config');
                        },
                        icon: const Icon(Icons.settings),
                        tooltip: 'Configure Dashboard',
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      )
                    else if (_isDashboardEditing && !widget.isConfigMode) ...[
                      ElevatedButton.icon(
                        onPressed: () async {
                          if (_hasUnsavedLayout) {
                            final choice = await showUnsavedChangesDialog(
                              context,
                            );
                            if (choice == null) return;
                            if (choice == UnsavedChoice.save) {
                              await _saveLayout();
                            } else {
                              _discardLayoutChanges();
                            }
                            if (!context.mounted) return;
                          }
                          ref.read(dashboardConfigProvider.notifier).state =
                              _items;
                          context.go('/dashboard/config');
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add to Dashboard'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final currentUser = ref.read(currentUserProvider);
                          if (currentUser != null) {
                            try {
                              final itemsJson = _items
                                  .map((e) => e.toJson())
                                  .toList();

                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(currentUser['id'])
                                  .collection('dashboards')
                                  .doc('all')
                                  .set({'items': itemsJson});

                              final ownedStores = List<String>.from(
                                currentUser['owned_stores'] ?? [],
                              );
                              for (final sid in ownedStores) {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(currentUser['id'])
                                    .collection('dashboards')
                                    .doc(sid)
                                    .set({'items': itemsJson});
                              }

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Dashboard saved to all stores!',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error saving: $e')),
                                );
                              }
                            }
                          }

                          setState(() {
                            _savedLayout = _layoutJson();
                            _exitEditMode();
                          });
                        },
                        icon: const Icon(Icons.copy_all, size: 16),
                        label: const Text('Save to all stores'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _saveLayout(showMessage: true),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Save Layout'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (widget.isConfigMode)
            Expanded(child: _buildConfigUI(buildItemContent))
          else
            Expanded(
              child: LayoutBuilder(
                key: _dashboardViewKey,
                builder: (context, constraints) {
                  double maxX = _items.isEmpty
                      ? 0
                      : _items.map((i) => i.x + i.width).reduce(max);
                  double maxY = _items.isEmpty
                      ? 0
                      : _items.map((i) => i.y + i.height).reduce(max);

                  double scale = 1.0;
                  if (!_isDashboardEditing && maxX > 0) {
                    scale = constraints.maxWidth / maxX;
                    if (scale < 0.4) scale = 0.4;
                    if (scale > 3.0) scale = 3.0;
                  }

                  Widget canvasContent = DragTarget<String>(
                    onAcceptWithDetails: (details) {
                      final renderBox = context.findRenderObject() as RenderBox;
                      final localOffset = renderBox.globalToLocal(
                        details.offset,
                      );
                      double snappedX = snap(localOffset.dx - 24);
                      double snappedY = snap(localOffset.dy - 100);

                      final newItem = CustomDashboardItem(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        type: details.data,
                        x: snappedX,
                        y: snappedY,
                        width: snap(300),
                        height: snap(200),
                      );

                      if (!_hasCollision(newItem)) {
                        setState(() {
                          _items.add(newItem);
                        });
                      }
                    },
                    builder: (context, candidateData, rejectedData) {
                      return GestureDetector(
                        onTap: () {
                          if (_isDashboardEditing) {
                            setState(() {
                              for (var i in _items) {
                                i.isSelected = false;
                              }
                            });
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: candidateData.isNotEmpty
                                ? AppTheme.accent.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: _isDashboardEditing
                                ? Border.all(
                                    color: AppTheme.accent.withValues(
                                      alpha: 0.3,
                                    ),
                                    style: BorderStyle.solid,
                                  )
                                : null,
                          ),
                          child: ClipRect(
                            child: CustomPaint(
                              painter: _isDashboardEditing
                                  ? GridPainter()
                                  : null,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: _items.map((item) {
                                  final content = buildItemContent(
                                    item.type,
                                    height: item.height,
                                  );
                                  final isEmpty =
                                      content is SizedBox &&
                                      content.child == null;
                                  if (isEmpty && !_isDashboardEditing) {
                                    return const SizedBox.shrink();
                                  }

                                  Widget displayContent = content;
                                  if (isEmpty && _isDashboardEditing) {
                                    displayContent = Center(
                                      child: Text(
                                        'No Data',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).disabledColor,
                                        ),
                                      ),
                                    );
                                  }

                                  return Positioned(
                                    left: item.x,
                                    top: item.y,
                                    width: item.width,
                                    height: item.height,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10.0),
                                      child: GestureDetector(
                                        onTap: () {
                                          if (!_isDashboardEditing) return;
                                          setState(() {
                                            if (isShift) {
                                              item.isSelected =
                                                  !item.isSelected;
                                            } else {
                                              for (var i in _items) {
                                                i.isSelected = false;
                                              }
                                              item.isSelected = true;
                                            }
                                          });
                                        },
                                        onPanStart: _isDashboardEditing
                                            ? (details) {
                                                if (!item.isSelected) {
                                                  if (!isShift) {
                                                    for (var i in _items) {
                                                      i.isSelected = false;
                                                    }
                                                  }
                                                  item.isSelected = true;
                                                }
                                                for (var i in _items.where(
                                                  (e) => e.isSelected,
                                                )) {
                                                  i._startX = i.x;
                                                  i._startY = i.y;
                                                }
                                              }
                                            : null,
                                        onPanUpdate: _isDashboardEditing
                                            ? (details) {
                                                setState(() {
                                                  for (var i in _items.where(
                                                    (e) => e.isSelected,
                                                  )) {
                                                    i.x += details.delta.dx;
                                                    i.y += details.delta.dy;
                                                  }
                                                });

                                                // Auto-scroll
                                                final yPos =
                                                    details.globalPosition.dy;
                                                final xPos =
                                                    details.globalPosition.dx;
                                                final size = MediaQuery.of(
                                                  context,
                                                ).size;

                                                final renderBox =
                                                    _dashboardViewKey
                                                            .currentContext
                                                            ?.findRenderObject()
                                                        as RenderBox?;
                                                if (renderBox != null) {
                                                  final topLeft = renderBox
                                                      .localToGlobal(
                                                        Offset.zero,
                                                      );
                                                  final leftEdge = topLeft.dx;
                                                  final rightEdge =
                                                      leftEdge +
                                                      renderBox.size.width;
                                                  final topEdge = topLeft.dy;
                                                  final bottomEdge =
                                                      topEdge +
                                                      renderBox.size.height;

                                                  double dyScroll = 0;
                                                  if (yPos < topEdge + 80)
                                                    dyScroll = -10;
                                                  else if (yPos >
                                                      bottomEdge - 80)
                                                    dyScroll = 10;

                                                  double dxScroll = 0;
                                                  if (xPos < leftEdge + 80)
                                                    dxScroll = -10;
                                                  else if (xPos >
                                                      rightEdge - 80)
                                                    dxScroll = 10;

                                                  setState(() {
                                                    if (dyScroll != 0) {
                                                      double oldOffset =
                                                          _verticalScrollController
                                                              .offset;
                                                      _verticalScrollController.jumpTo(
                                                        (oldOffset + dyScroll).clamp(
                                                          0.0,
                                                          _verticalScrollController
                                                              .position
                                                              .maxScrollExtent,
                                                        ),
                                                      );
                                                      double actualScroll =
                                                          _verticalScrollController
                                                              .offset -
                                                          oldOffset;
                                                      for (var i
                                                          in _items.where(
                                                            (e) => e.isSelected,
                                                          ))
                                                        i.y += actualScroll;
                                                    }
                                                    if (dxScroll != 0) {
                                                      double oldOffset =
                                                          _horizontalScrollController
                                                              .offset;
                                                      _horizontalScrollController.jumpTo(
                                                        (oldOffset + dxScroll).clamp(
                                                          0.0,
                                                          _horizontalScrollController
                                                              .position
                                                              .maxScrollExtent,
                                                        ),
                                                      );
                                                      double actualScroll =
                                                          _horizontalScrollController
                                                              .offset -
                                                          oldOffset;
                                                      for (var i
                                                          in _items.where(
                                                            (e) => e.isSelected,
                                                          ))
                                                        i.x += actualScroll;
                                                    }
                                                  });
                                                }
                                              }
                                            : null,
                                        onPanEnd: _isDashboardEditing
                                            ? (details) {
                                                setState(() {
                                                  bool collision = false;
                                                  for (var i in _items.where(
                                                    (e) => e.isSelected,
                                                  )) {
                                                    i.x = max(0.0, snap(i.x));
                                                    i.y = max(0.0, snap(i.y));

                                                    final othersAtPos = _items
                                                        .where(
                                                          (o) =>
                                                              !o.isSelected &&
                                                              o.x == i.x &&
                                                              o.y == i.y,
                                                        )
                                                        .toList();
                                                    if (othersAtPos.length ==
                                                        1) {
                                                      final other =
                                                          othersAtPos.first;
                                                      other.x = i._startX;
                                                      other.y = i._startY;
                                                      double tempW =
                                                          other.width;
                                                      double tempH =
                                                          other.height;
                                                      other.width = i.width;
                                                      other.height = i.height;
                                                      i.width = tempW;
                                                      i.height = tempH;
                                                    }

                                                    if (_hasCollision(i)) {
                                                      collision = true;
                                                    }
                                                  }
                                                  if (collision) {
                                                    for (var i in _items.where(
                                                      (e) => e.isSelected,
                                                    )) {
                                                      i.x = i._startX;
                                                      i.y = i._startY;
                                                    }
                                                  }
                                                });
                                              }
                                            : null,
                                        child: Builder(
                                          builder: (context) {
                                            Color borderColor = Theme.of(
                                              context,
                                            ).dividerColor;
                                            double borderWidth = 1.0;

                                            if (item.isSelected &&
                                                _isDashboardEditing) {
                                              borderColor =
                                                  AppTheme.accent;
                                              borderWidth = 2.0;
                                            } else if (item.type ==
                                                'deficits') {
                                              // Fully staffed: the theme's blue.
                                              borderColor =
                                                  totalShiftDeficit > 0
                                                  ? AppTheme.primaryRed
                                                  : AppTheme.blue;
                                              borderWidth = 2.0;
                                            }

                                            final staffedTile =
                                                item.type == 'deficits' &&
                                                totalShiftDeficit == 0;
                                            return Container(
                                              decoration: BoxDecoration(
                                                color: staffedTile
                                                    ? Color.alphaBlend(
                                                        AppTheme.blue
                                                            .withValues(
                                                              alpha: 0.08,
                                                            ),
                                                        Theme.of(
                                                          context,
                                                        ).cardColor,
                                                      )
                                                    : Theme.of(
                                                        context,
                                                      ).cardColor,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: borderColor,
                                                  width: borderWidth,
                                                ),
                                                boxShadow:
                                                    item.isSelected &&
                                                        _isDashboardEditing
                                                    ? [
                                                        BoxShadow(
                                                          color: AppTheme
                                                              .accent
                                                              .withValues(
                                                                alpha: 0.2,
                                                              ),
                                                          blurRadius: 8,
                                                          spreadRadius: 2,
                                                        ),
                                                      ]
                                                    : [],
                                              ),
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
                                                    child: displayContent,
                                                  ),
                                                  if (item.isSelected &&
                                                      _isDashboardEditing)
                                                    Positioned(
                                                      right: 0,
                                                      bottom: 0,
                                                      child: GestureDetector(
                                                        onPanStart: (details) {
                                                          item._startWidth =
                                                              item.width;
                                                          item._startHeight =
                                                              item.height;
                                                        },
                                                        onPanUpdate: (details) {
                                                          setState(() {
                                                            item.width =
                                                                (item.width +
                                                                        details
                                                                            .delta
                                                                            .dx)
                                                                    .clamp(
                                                                      100.0,
                                                                      2000.0,
                                                                    );
                                                            item.height =
                                                                (item.height +
                                                                        details
                                                                            .delta
                                                                            .dy)
                                                                    .clamp(
                                                                      100.0,
                                                                      2000.0,
                                                                    );
                                                          });
                                                        },
                                                        onPanEnd: (details) {
                                                          setState(() {
                                                            item.width = snap(
                                                              item.width,
                                                            );
                                                            item.height = snap(
                                                              item.height,
                                                            );

                                                            double diffW =
                                                                item.width -
                                                                item._startWidth;
                                                            double diffH =
                                                                item.height -
                                                                item._startHeight;
                                                            Map<String, Offset>
                                                            originalPos = {
                                                              for (var i
                                                                  in _items)
                                                                i.id: Offset(
                                                                  i.x,
                                                                  i.y,
                                                                ),
                                                            };

                                                            if (_hasCollision(
                                                              item,
                                                            )) {
                                                              if (diffW > 0) {
                                                                for (var o
                                                                    in _items) {
                                                                  if (o.id !=
                                                                          item.id &&
                                                                      o.x >=
                                                                          item._startX +
                                                                              item._startWidth -
                                                                              1) {
                                                                    o.x +=
                                                                        diffW;
                                                                  }
                                                                }
                                                              }
                                                              if (diffH > 0) {
                                                                for (var o
                                                                    in _items) {
                                                                  if (o.id !=
                                                                          item.id &&
                                                                      o.y >=
                                                                          item._startY +
                                                                              item._startHeight -
                                                                              1) {
                                                                    o.y +=
                                                                        diffH;
                                                                  }
                                                                }
                                                              }
                                                            }

                                                            bool anyCollision =
                                                                false;
                                                            for (var i
                                                                in _items) {
                                                              if (_hasCollision(
                                                                i,
                                                              ))
                                                                anyCollision =
                                                                    true;
                                                            }

                                                            if (anyCollision) {
                                                              item.width = item
                                                                  ._startWidth;
                                                              item.height = item
                                                                  ._startHeight;
                                                              for (var i
                                                                  in _items) {
                                                                i.x =
                                                                    originalPos[i
                                                                            .id]!
                                                                        .dx;
                                                                i.y =
                                                                    originalPos[i
                                                                            .id]!
                                                                        .dy;
                                                              }
                                                            }
                                                          });
                                                        },
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: AppTheme
                                                                .accent,
                                                            borderRadius:
                                                                const BorderRadius.only(
                                                                  topLeft:
                                                                      Radius.circular(
                                                                        8,
                                                                      ),
                                                                  bottomRight:
                                                                      Radius.circular(
                                                                        8,
                                                                      ),
                                                                ),
                                                          ),
                                                          child: const Icon(
                                                            Icons
                                                                .drag_indicator,
                                                            size: 16,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );

                  if (_isDashboardEditing) {
                    return SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        scrollDirection: Axis.vertical,
                        child: SizedBox(
                          width: max(constraints.maxWidth, maxX + 800),
                          height: max(constraints.maxHeight, maxY + 800),
                          child: canvasContent,
                        ),
                      ),
                    );
                  } else {
                    return SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        scrollDirection: Axis.vertical,
                        child: SizedBox(
                          width: maxX * scale,
                          height: maxY * scale,
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: maxX,
                              height: maxY,
                              child: canvasContent,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeficitPill(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: AppTheme.accent,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _saveToFirestore() async {
    final currentUser = ref.read(currentUserProvider);
    final currentStoreId = ref.read(currentStoreIdProvider);
    final storeKey = currentStoreId ?? 'all';
    if (currentUser != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser['id'])
            .collection('dashboards')
            .doc(storeKey)
            .set({'items': _items.map((e) => e.toJson()).toList()});
      } catch (e) {
        debugPrint('Error saving config dashboard layout: $e');
      }
    }
  }

  Widget _buildConfigUI(Widget Function(String type) buildItemContent) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConfigSection(null, [
                    'tenure',
                    'deficits',
                    'permit',
                    'tenure_by_year',
                    'welcome_quote',
                    'tenure_dist',
                  ], buildItemContent),
                  _buildConfigSection('Working Time Charts', [
                    'working_time',
                    'working_time_pie',
                    'working_time_vertical',
                  ], buildItemContent),
                  _buildConfigSection('Title Charts', [
                    'title',
                    'title_pie',
                    'title_vertical',
                  ], buildItemContent),
                  _buildConfigSection('Position Charts', [
                    'position',
                    'position_pie',
                    'position_vertical',
                  ], buildItemContent),
                  _buildConfigSection('Designation Charts', [
                    'designation',
                    'designation_pie',
                    'designation_vertical',
                  ], buildItemContent),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigSection(
    String? header,
    List<String> types,
    Widget Function(String type) buildItemContent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null) ...[
          const SizedBox(height: 32),
          Text(
            header,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: types
              .map((t) => _buildConfigTile(t, buildItemContent))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildConfigTile(
    String type,
    Widget Function(String type) buildItemContent,
  ) {
    final isAdded = _items.any((i) => i.type == type);

    return InkWell(
      onTap: () async {
        setState(() {
          if (isAdded) {
            _items.removeWhere((i) => i.type == type);
          } else {
            final pos = _findBestPosition(350, 250);
            _items.add(
              CustomDashboardItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                type: type,
                x: pos.dx,
                y: pos.dy,
                width: 350,
                height: 250,
              ),
            );
          }
        });
        _saveToFirestore();
      },
      child: Container(
        width: 350,
        height: 250,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isAdded
                ? AppTheme.accent
                : Theme.of(context).dividerColor,
            width: isAdded ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: AbsorbPointer(child: buildItemContent(type)),
        ),
      ),
    );
  }
}
