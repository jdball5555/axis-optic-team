import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../models/store_settings_model.dart';
import '../../core/staffing_calculator.dart';

const double gridSize = 50.0;
double snap(double v) => (v / gridSize).roundToDouble() * gridSize;

class GridPainter extends CustomPainter {
  const GridPainter();

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

class CustomRosterItem {
  final String id;
  double x;
  double y;
  double width;
  double height;
  bool isSelected;

  /// Titles / additional tags shown as their own group inside this tile,
  /// chosen when the tile was added. Null for tiles added before that
  /// existed: they keep using the old per-title "Split in Area" setting.
  List<String>? splitTitles;

  double _startX = 0;
  double _startY = 0;
  double _startWidth = 0;
  double _startHeight = 0;

  CustomRosterItem({
    required this.id,
    required this.x,
    required this.y,
    this.width = 350.0,
    this.height = 550.0,
    this.isSelected = false,
    this.splitTitles,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (splitTitles != null) 'splitTitles': splitTitles,
  };

  factory CustomRosterItem.fromJson(Map<String, dynamic> json) {
    return CustomRosterItem(
      id: json['id'] ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 350.0,
      height: (json['height'] as num?)?.toDouble() ?? 550.0,
      splitTitles: (json['splitTitles'] as List?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }
}

class AvailableRosterTile {
  final String id;
  final String storeId;
  final String displayTitle;
  final String rawPos;
  final String workingTime;
  final bool isTrainer;
  final bool isIsolatedTitle;
  final String sectionHeader;

  const AvailableRosterTile({
    required this.id,
    required this.storeId,
    required this.displayTitle,
    required this.rawPos,
    this.workingTime = '',
    this.isTrainer = false,
    this.isIsolatedTitle = false,
    required this.sectionHeader,
  });
}

class RostersView extends ConsumerStatefulWidget {
  final bool isConfigMode;
  const RostersView({super.key, this.isConfigMode = false});

  @visibleForTesting
  static void clearSessionCache() => _RostersViewState.clearSessionCache();

  @override
  ConsumerState<RostersView> createState() => _RostersViewState();
}

class _RostersViewState extends ConsumerState<RostersView> {
  static final Map<String, List<CustomRosterItem>> _sessionLayoutCache = {};
  @visibleForTesting
  static void clearSessionCache() => _sessionLayoutCache.clear();

  bool _isEditingLayout = false;
  List<CustomRosterItem> _items = [];
  String? _loadedStoreKey;

  /// Store id → name for the stores on screen (kept from the last build).
  Map<String, String> _storeNames = {};
  String? _savedLayout;
  bool _isLoadingFirestore = false;
  String _lastActiveKeysSignature = '';
  int _lastUsersHash = 0;
  Map<String, List<UserModel>> _cachedPositionGroups = {};

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _configScrollController = ScrollController();
  final GlobalKey _rosterViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.isConfigMode && ref.read(rosterEditModeProvider)) {
        setState(() {
          _isEditingLayout = true;
        });
        ref.read(rosterEditModeProvider.notifier).state = false;
      }
    });
  }

  @override
  void didUpdateWidget(covariant RostersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isConfigMode && !widget.isConfigMode) {
      if (ref.read(rosterEditModeProvider)) {
        _isEditingLayout = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(rosterEditModeProvider.notifier).state = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _configScrollController.dispose();
    _canvasLatchTimer?.cancel();
    _canvasScrollLatched.dispose();
    super.dispose();
  }

  int _hoveredTileCount = 0;

  /// True while the canvas itself is scrolling (and briefly after). Tiles
  /// ignore the pointer then, so a scroll that started on empty canvas keeps
  /// moving the canvas when a tile slides under the cursor instead of
  /// switching to that tile's list.
  final ValueNotifier<bool> _canvasScrollLatched = ValueNotifier(false);
  Timer? _canvasLatchTimer;

  bool _onCanvasScrollNotification(ScrollNotification n) {
    // Depth 0 is the vertical canvas scroll view, 1 the horizontal one.
    if (n is ScrollUpdateNotification && n.depth <= 1) _latchCanvasScroll();
    return false;
  }

  void _latchCanvasScroll() {
    _canvasLatchTimer?.cancel();
    _canvasLatchTimer = Timer(const Duration(milliseconds: 350), () {
      _canvasScrollLatched.value = false;
    });
    if (_canvasScrollLatched.value) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _canvasLatchTimer?.isActive == true) {
          _canvasScrollLatched.value = true;
        }
      });
    } else {
      _canvasScrollLatched.value = true;
    }
  }

  void _moveBy(ScrollController c, double delta) {
    if (!c.hasClients || delta == 0) return;
    final p = c.position;
    final to = (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to != p.pixels) c.jumpTo(to);
  }

  void _onCanvasPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    if (_hoveredTileCount > 0) return;
    final dx = e.scrollDelta.dx;
    final dy = e.scrollDelta.dy;
    if (dx != 0 && dy != 0) {
      _moveBy(_verticalScrollController, dy);
    }
  }

  String _layoutJson() => jsonEncode(_items.map((e) => e.toJson()).toList());

  bool _hasCollision(CustomRosterItem item, [List<CustomRosterItem>? items]) =>
      _collides(item, items ?? _items);

  static bool _collides(CustomRosterItem item, List<CustomRosterItem> items) {
    for (var other in items) {
      if (other.id == item.id) continue;
      if (item.x < other.x + other.width - 1 &&
          item.x + item.width > other.x + 1 &&
          item.y < other.y + other.height - 1 &&
          item.y + item.height > other.y + 1) {
        return true;
      }
    }
    return false;
  }

  bool _isStandardPositionTile(
    AvailableRosterTile tile,
    StoreSettingsModel? settings,
  ) {
    if (tile.isTrainer) return false;
    if (tile.isIsolatedTitle) return false;
    if (settings != null && !settings.positions.contains(tile.rawPos)) {
      return false;
    }
    return true;
  }

  bool _isSameTile(String itemId, AvailableRosterTile tile) {
    final p1 = itemId.split('|');
    final p2 = tile.id.split('|');
    if (p1.length < 3 || p2.length < 3) return itemId == tile.id;
    if (p1[0] != p2[0]) return false;
    if (p1[1] != p2[1]) return false;
    if (p1[2] != p2[2]) return false;
    final wt1 = p1.length > 4 ? p1[4] : '';
    final wt2 = p2.length > 4 ? p2[4] : '';
    return wt1 == wt2;
  }

  String _buildItemId(AvailableRosterTile tile, bool isIsolated) {
    final parts = tile.id.split('|');
    if (parts.length >= 4) {
      parts[3] = isIsolated.toString();
      return parts.join('|');
    }
    final wtSuffix = tile.workingTime.isNotEmpty ? '|${tile.workingTime}' : '';
    return '${tile.storeId}|${tile.displayTitle}|${tile.rawPos}|$isIsolated$wtSuffix';
  }

  /// Asks whether any title / additional tag should be split into its own
  /// group inside the tile, and if so which. Returns the chosen names
  /// (empty for no split), or null if cancelled.
  Future<List<String>?> _askRosterSplitTitles(
    BuildContext context,
    AvailableRosterTile tile,
    StoreSettingsModel? settings,
  ) async {
    final List<String> options = [];
    for (final t in [...?settings?.titles, ...?settings?.tags]) {
      final name = t.name.trim();
      if (name.isEmpty) continue;
      if (name.toLowerCase() == tile.rawPos.trim().toLowerCase()) continue;
      if (options.any((o) => o.toLowerCase() == name.toLowerCase())) continue;
      options.add(name);
    }
    if (options.isEmpty) return const [];

    final wantsSplit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Split anyone within "${tile.displayTitle}"?'),
        content: Text(
          'Do you want team members with a certain title or additional tag '
          'grouped separately inside this roster tile?'
          '\n\nThis tile and its settings change on ${_bothRostersLabel(tile.storeId)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Choose Which'),
          ),
        ],
      ),
    );
    if (wantsSplit == null) return null;
    if (!wantsSplit) return const [];
    if (!context.mounted) return null;

    final selected = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Split Within This Area'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final name in options)
                  CheckboxListTile(
                    title: Text(name),
                    value: selected.contains(name),
                    activeColor: AppTheme.accent,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setDialogState(() {
                      if (v == true) {
                        selected.add(name);
                      } else {
                        selected.remove(name);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(
                      ctx,
                    ).pop(options.where(selected.contains).toList()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showRosterIsolationDialog(
    BuildContext context,
    AvailableRosterTile tile,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Include "${tile.displayTitle}" in General Roster?'),
          content: Text(
            'Do you want team members on the "${tile.displayTitle}" roster '
            'to also be included in their general roster tile, or only appear on this roster?'
            '\n\nThis tile and its settings change on ${_bothRostersLabel(tile.storeId)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('No, Only on This Roster'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, Include in Both'),
            ),
          ],
        );
      },
    );
  }

  Offset _findSlotForTile(
    AvailableRosterTile tile,
    double width,
    double height,
  ) => _findSlot(
    storeId: tile.storeId,
    workingTime: tile.workingTime,
    id: tile.id,
    width: width,
    height: height,
    items: _items,
  );

  /// Where a new tile goes in [items]: at the end of its store's row for
  /// that working time (or titles / tags row), else on a new row below.
  static Offset _findSlot({
    required String storeId,
    required String workingTime,
    required String id,
    required double width,
    required double height,
    required List<CustomRosterItem> items,
  }) {
    final sid = storeId;
    final wt = workingTime;

    if (wt.isNotEmpty && wt != 'Other') {
      // Find all items in items matching this store and working time
      final matchingItems = items.where((i) {
        final p = i.id.split('|');
        final itemSid = p[0];
        final itemWt = p.length > 4 ? p[4] : '';
        return itemSid == sid && itemWt == wt;
      }).toList();

      if (matchingItems.isNotEmpty) {
        // Find row Y for this working time
        final rowY = snap(matchingItems.map((e) => e.y).reduce(max));
        // All items currently sitting on this row
        final rowItems = items
            .where((e) => (e.y - rowY).abs() < (height / 2))
            .toList();
        final maxX = rowItems.map((e) => e.x + e.width).reduce(max);
        double newX = snap(maxX);
        double newY = rowY;

        final candidate = CustomRosterItem(
          id: id,
          x: newX,
          y: newY,
          width: width,
          height: height,
        );
        while (_collides(candidate, items)) {
          newX += snap(width);
          candidate.x = newX;
        }
        return Offset(newX, newY);
      } else {
        // No items yet for this working time in this store.
        final storeItems = items
            .where((i) => i.id.startsWith('$sid|'))
            .toList();
        if (storeItems.isNotEmpty) {
          final maxStoreY = storeItems.map((e) => e.y + e.height).reduce(max);
          return Offset(0, snap(maxStoreY));
        } else {
          double maxY = 0;
          if (items.isNotEmpty) {
            maxY = items.map((e) => e.y + e.height).reduce(max);
          }
          return Offset(0, snap(maxY));
        }
      }
    } else {
      // For titles / tags / isolated / 'Other' tiles:
      final nonWtStoreItems = items.where((i) {
        final p = i.id.split('|');
        final itemWt = p.length > 4 ? p[4] : '';
        return p[0] == sid && (itemWt.isEmpty || itemWt == 'Other');
      }).toList();

      if (nonWtStoreItems.isNotEmpty) {
        final rowY = snap(nonWtStoreItems.map((e) => e.y).reduce(max));
        final rowItems = items
            .where((e) => (e.y - rowY).abs() < (height / 2))
            .toList();
        final maxX = rowItems.map((e) => e.x + e.width).reduce(max);
        double newX = snap(maxX);
        double newY = rowY;
        final candidate = CustomRosterItem(
          id: id,
          x: newX,
          y: newY,
          width: width,
          height: height,
        );
        while (_collides(candidate, items)) {
          newX += snap(width);
          candidate.x = newX;
        }
        return Offset(newX, newY);
      } else {
        final storeItems = items
            .where((i) => i.id.startsWith('$sid|'))
            .toList();
        if (storeItems.isNotEmpty) {
          final maxStoreY = storeItems.map((e) => e.y + e.height).reduce(max);
          return Offset(0, snap(maxStoreY));
        } else {
          double maxY = 0;
          if (items.isNotEmpty) {
            maxY = items.map((e) => e.y + e.height).reduce(max);
          }
          return Offset(0, snap(maxY));
        }
      }
    }
  }

  void _alignMisplacedTrainerTiles(List<CustomRosterItem> items) {
    final Map<String, List<CustomRosterItem>> wtGroups = {};
    for (final item in items) {
      final p = item.id.split('|');
      if (p.length > 4 && p[4].isNotEmpty && p[4] != 'Other') {
        final key = '${p[0]}|${p[4]}';
        wtGroups.putIfAbsent(key, () => []).add(item);
      }
    }

    for (final entry in wtGroups.entries) {
      final group = entry.value;
      final nonTrainers = group.where((i) {
        final p = i.id.split('|');
        return p[2].trim().toLowerCase() != 'trainer';
      }).toList();
      final trainers = group.where((i) {
        final p = i.id.split('|');
        return p[2].trim().toLowerCase() == 'trainer';
      }).toList();

      if (nonTrainers.isNotEmpty && trainers.isNotEmpty) {
        final dominantY = snap(nonTrainers.map((e) => e.y).reduce(max));
        for (final tr in trainers) {
          if ((tr.y - dominantY).abs() >= 50) {
            final rowItems = items
                .where(
                  (e) =>
                      e.id != tr.id &&
                      (e.y - dominantY).abs() < (tr.height / 2),
                )
                .toList();
            double maxX = rowItems.isNotEmpty
                ? rowItems.map((e) => e.x + e.width).reduce(max)
                : 0.0;
            tr.y = dominantY;
            tr.x = snap(maxX);
          }
        }
      }
    }
  }

  List<CustomRosterItem> _generateDefaultLayout({
    required List<Map<String, dynamic>> stores,
    required Map<String, StoreSettingsModel> storeSettingsMap,
    required Map<String, List<UserModel>> positionGroups,
    required String? currentStoreId,
  }) {
    final List<CustomRosterItem> defaultItems = [];
    int currentRow = 0;

    final activeStores = currentStoreId != null
        ? stores.where((s) => s['id'] == currentStoreId).toList()
        : stores;

    for (final store in activeStores) {
      final sid = store['id'] as String;
      final settings = storeSettingsMap[sid];

      // All keys for this store
      final allStoreKeys = positionGroups.keys
          .where((k) => k.startsWith('$sid|'))
          .toList();

      // Check if working times are used in this store's keys
      final hasWorkingTimes = allStoreKeys.any((k) {
        final parts = k.split('|');
        return parts.length > 4 && parts[4].isNotEmpty;
      });

      if (hasWorkingTimes) {
        // Collect all distinct working times for this store in order:
        // configured working times first, then 'Other'
        final configuredWts =
            (settings != null && settings.workingTimes.isNotEmpty)
            ? settings.workingTimes.where((w) {
                final l = w.trim().toLowerCase();
                return l != 'other' && l != 'unassigned';
              }).toList()
            : <String>[];

        final distinctWts = <String>[];
        for (final wt in configuredWts) {
          if (!distinctWts.contains(wt)) distinctWts.add(wt);
        }
        for (final k in allStoreKeys) {
          final parts = k.split('|');
          if (parts.length > 4 && parts[4].isNotEmpty && parts[4] != 'Other') {
            if (!distinctWts.contains(parts[4])) distinctWts.add(parts[4]);
          }
        }
        if (!distinctWts.contains('Other')) distinctWts.add('Other');

        for (final wt in distinctWts) {
          final keysForWt = allStoreKeys.where((k) {
            final parts = k.split('|');
            return parts.length > 4 && parts[4] == wt;
          }).toList();

          if (keysForWt.isEmpty) continue;

          // Sort keys: standard positions first (ordered by settings.positions),
          // with Trainer tiles at the very end of their working time row,
          // then isolated custom roles alphabetically
          keysForWt.sort((a, b) {
            final partsA = a.split('|');
            final partsB = b.split('|');
            final isIsoA = partsA.length > 3 && partsA[3] == 'true';
            final isIsoB = partsB.length > 3 && partsB[3] == 'true';
            if (isIsoA != isIsoB) {
              return isIsoA ? 1 : -1;
            }
            final posA = partsA[2];
            final posB = partsB[2];
            final isTrA = posA.trim().toLowerCase() == 'trainer';
            final isTrB = posB.trim().toLowerCase() == 'trainer';
            if (isTrA != isTrB) {
              return isTrA ? 1 : -1;
            }
            if (!isIsoA && settings != null && settings.positions.isNotEmpty) {
              final idxA = settings.positions.indexOf(posA);
              final idxB = settings.positions.indexOf(posB);
              if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
              if (idxA != -1) return -1;
              if (idxB != -1) return 1;
            }
            return posA.compareTo(posB);
          });

          for (int col = 0; col < keysForWt.length; col++) {
            defaultItems.add(
              CustomRosterItem(
                id: keysForWt[col],
                x: col * 350.0,
                y: currentRow * 550.0,
                width: 350.0,
                height: 550.0,
              ),
            );
          }
          currentRow++;
        }
      } else {
        // Standard keys: isIsolated == false
        final standardKeys = allStoreKeys.where((k) {
          final parts = k.split('|');
          return parts.length > 3 && parts[3] == 'false';
        }).toList();

        // Custom keys: isIsolated == true
        final customKeys = allStoreKeys.where((k) {
          final parts = k.split('|');
          return parts.length > 3 && parts[3] == 'true';
        }).toList();

        // Order standard keys according to settings.positions if present, else by display name,
        // with Trainer tiles placed at the end
        if (settings != null && settings.positions.isNotEmpty) {
          standardKeys.sort((a, b) {
            final posA = a.split('|')[2];
            final posB = b.split('|')[2];
            final isTrA = posA.trim().toLowerCase() == 'trainer';
            final isTrB = posB.trim().toLowerCase() == 'trainer';
            if (isTrA != isTrB) {
              return isTrA ? 1 : -1;
            }
            final idxA = settings.positions.indexOf(posA);
            final idxB = settings.positions.indexOf(posB);
            if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
            if (idxA != -1) return -1;
            if (idxB != -1) return 1;
            return posA.compareTo(posB);
          });
        } else {
          standardKeys.sort((a, b) {
            final posA = a.split('|')[2];
            final posB = b.split('|')[2];
            final isTrA = posA.trim().toLowerCase() == 'trainer';
            final isTrB = posB.trim().toLowerCase() == 'trainer';
            if (isTrA != isTrB) {
              return isTrA ? 1 : -1;
            }
            return a.split('|')[1].compareTo(b.split('|')[1]);
          });
        }

        // Order custom keys alphabetically by role/title name
        customKeys.sort((a, b) {
          final titleA = a.split('|')[2];
          final titleB = b.split('|')[2];
          return titleA.compareTo(titleB);
        });

        // 1. Standard roster tiles row for this store
        if (standardKeys.isNotEmpty) {
          for (int col = 0; col < standardKeys.length; col++) {
            defaultItems.add(
              CustomRosterItem(
                id: standardKeys[col],
                x: col * 350.0,
                y: currentRow * 550.0,
                width: 350.0,
                height: 550.0,
              ),
            );
          }
          currentRow++;
        }

        // 2. Custom roster tiles row for this store
        if (customKeys.isNotEmpty) {
          for (int col = 0; col < customKeys.length; col++) {
            defaultItems.add(
              CustomRosterItem(
                id: customKeys[col],
                x: col * 350.0,
                y: currentRow * 550.0,
                width: 350.0,
                height: 550.0,
              ),
            );
          }
          currentRow++;
        }
      }

      // Anything else of this store's gets a row right under its tiles
      // (never another store's tiles), so a store lays out the same on its
      // own roster as it does on All Stores.
      final placedIds = defaultItems.map((e) => e.id).toSet();
      final leftover = allStoreKeys
          .where((k) => !placedIds.contains(k))
          .toList();
      if (leftover.isNotEmpty) {
        for (int col = 0; col < leftover.length; col++) {
          defaultItems.add(
            CustomRosterItem(
              id: leftover[col],
              x: col * 350.0,
              y: currentRow * 550.0,
              width: 350.0,
              height: 550.0,
            ),
          );
        }
        currentRow++;
      }
    }

    return defaultItems;
  }

  // --- All Stores is made of the stores' own rosters ---
  //
  // Each store's roster (its tiles, their settings and layout) is saved under
  // that store. The All Stores roster isn't saved on its own: it shows each
  // store's roster exactly as it is, one store below the other, and anything
  // changed there is saved back to the store it belongs to.

  /// The same tile on the All Stores and single-store rosters: store,
  /// position / title / tag and working time. (Only the display title
  /// differs: All Stores puts the store name in front.)
  static String _tileIdentity(String id) {
    final p = id.split('|');
    if (p.length < 3) return id;
    final wt = p.length > 4 ? p[4] : '';
    return '${p[0]}|${p[2].trim().toLowerCase()}|$wt';
  }

  /// [id] as the All Stores roster names it ("Store - Day - Cook").
  static String _allStoresId(String id, String storeName) {
    final p = id.split('|');
    if (p.length < 2 || p[1].startsWith('$storeName - ')) return id;
    p[1] = '$storeName - ${p[1]}';
    return p.join('|');
  }

  /// [id] as the store's own roster names it ("Day - Cook").
  static String _storeId(String id, String storeName) {
    final p = id.split('|');
    if (p.length < 2 || !p[1].startsWith('$storeName - ')) return id;
    p[1] = p[1].substring(storeName.length + 3);
    return p.join('|');
  }

  CollectionReference<Map<String, dynamic>>? _layoutsCollection() {
    final userId = ref.read(currentUserProvider)?['id'] as String?;
    if (userId == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('roster_layouts');
  }

  static List<CustomRosterItem> _parseItems(Map<String, dynamic>? data) => [
    if (data?['items'] is List)
      for (final e in data!['items'] as List)
        if (e is Map) CustomRosterItem.fromJson(Map<String, dynamic>.from(e)),
  ];

  /// Where each store's roster starts on the All Stores board (how far down),
  /// from the last time it was put together.
  Map<String, double> _allStoresOffsets = {};

  /// Puts the All Stores board together from [boards] (each store's own
  /// roster), in store order.
  List<CustomRosterItem> _composeAll(
    Map<String, List<CustomRosterItem>> boards,
  ) {
    final composed = composeAllStoresBoard([
      for (final sid in _storeNames.keys)
        (id: sid, name: _storeNames[sid]!, board: boards[sid] ?? const []),
    ]);
    _allStoresOffsets = composed.offsets;
    return composed.items;
  }

  /// A store's own board made from its tiles on the All Stores board
  /// [allItems] (store name taken off the titles, moved to the top-left).
  List<CustomRosterItem> _storeBoardFromAll(
    String storeId,
    List<CustomRosterItem> allItems,
  ) {
    final storeName = _storeNames[storeId] ?? '';
    final mine = allItems.where((i) => i.id.startsWith('$storeId|')).toList();
    if (mine.isEmpty) return [];
    final minX = mine.map((i) => i.x).reduce(min);
    final minY = mine.map((i) => i.y).reduce(min);
    return [
      for (final i in mine)
        CustomRosterItem(
          id: _storeId(i.id, storeName),
          x: i.x - minX,
          y: i.y - minY,
          width: i.width,
          height: i.height,
          splitTitles: i.splitTitles,
        ),
    ];
  }

  /// "the Main St and All Stores rosters" for messages.
  String _bothRostersLabel(String storeId) {
    final name = _storeNames[storeId];
    return name == null
        ? 'this store\'s roster and the All Stores roster'
        : 'the $name roster and the All Stores roster';
  }

  Future<void> _loadLayout(
    String storeKey,
    List<CustomRosterItem> defaultLayout,
  ) async {
    if (_isEditingLayout) return;

    if (_sessionLayoutCache.containsKey(storeKey)) {
      final cached = _sessionLayoutCache[storeKey]!;
      if (_items.length != cached.length || _loadedStoreKey != storeKey) {
        _loadedStoreKey = storeKey;
        _items = List.of(cached);
        _savedLayout = _layoutJson();
      }
      return;
    }

    if (_loadedStoreKey != storeKey ||
        (!_isEditingLayout && _savedLayout == null)) {
      _loadedStoreKey = storeKey;
      _items = List.of(defaultLayout);
      _alignMisplacedTrainerTiles(_items);
    }

    if (_isLoadingFirestore) return;

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    _isLoadingFirestore = true;
    // Taken now: by the time Firestore answers, the screen may be showing a
    // different store, and that store's board must never be saved here.
    final names = Map.of(_storeNames);
    final storeDefault = List.of(defaultLayout);
    _alignMisplacedTrainerTiles(storeDefault);
    try {
      final col = _layoutsCollection()!;
      var changed = false;

      /// A store's roster as saved (cleaned of any tiles that don't belong
      /// to it), or its default if it was never saved. A roster that was
      /// never saved, or needed cleaning, is saved now, so later changes to
      /// the default layout never change a roster that already exists.
      Future<List<CustomRosterItem>> storeBoard(
        String sid,
        List<CustomRosterItem> fallback,
      ) async {
        final saved = _parseItems((await col.doc(sid).get()).data());
        final board = saved.isNotEmpty
            ? cleanStoreRosterBoard(sid, names[sid] ?? '', saved)
            : fallback;
        final savedJson = jsonEncode(saved.map((e) => e.toJson()).toList());
        final boardJson = jsonEncode(board.map((e) => e.toJson()).toList());
        if (board.isNotEmpty && boardJson != savedJson) {
          await col.doc(sid).set({
            'items': board.map((e) => e.toJson()).toList(),
          });
          changed = true;
        }
        _sessionLayoutCache[sid] = List.of(board);
        return board;
      }

      final List<CustomRosterItem> board;
      if (storeKey == 'all') {
        // Each store's own roster, one below the other.
        final boards = <String, List<CustomRosterItem>>{};
        for (final sid in names.keys) {
          boards[sid] = await storeBoard(
            sid,
            _storeBoardFromAll(sid, storeDefault),
          );
        }
        board = _composeAll(boards);
      } else {
        board = await storeBoard(storeKey, storeDefault);
      }
      if (changed) ref.read(rosterLayoutRevisionProvider.notifier).state++;

      if (mounted && _loadedStoreKey == storeKey && !_isEditingLayout) {
        _sessionLayoutCache[storeKey] = List.of(board);
        setState(() {
          _items = board;
          _savedLayout = _layoutJson();
        });
      }
    } catch (e) {
      debugPrint('Error loading roster layout: $e');
    } finally {
      _isLoadingFirestore = false;
      // Switched to another store while this was loading: load that one.
      if (mounted && _loadedStoreKey != storeKey) setState(() {});
    }
  }

  Future<void> _saveLayout({bool showMessage = false}) async {
    final currentUser = ref.read(currentUserProvider);
    final storeKey = ref.read(currentStoreIdProvider) ?? 'all';
    // On All Stores, each store's part is saved back to that store's roster
    // (and the board is put together again, so the stores stay stacked).
    final Map<String, List<CustomRosterItem>> boards = storeKey == 'all'
        ? splitAllStoresBoard(_items, _storeNames, _allStoresOffsets)
        : {storeKey: List.of(_items)};
    if (storeKey == 'all') _items = _composeAll(boards);
    boards.forEach((sid, board) => _sessionLayoutCache[sid] = List.of(board));
    _sessionLayoutCache[storeKey] = List.of(_items);
    // All Stores is put together again from this store the next time.
    if (storeKey != 'all') _sessionLayoutCache.remove('all');
    _savedLayout = _layoutJson();
    ref.read(rosterLayoutRevisionProvider.notifier).state++;
    if (currentUser == null) return;
    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser['id'])
          .collection('roster_layouts');
      for (final e in boards.entries) {
        await col.doc(e.key).set({
          'items': e.value.map((i) => i.toJson()).toList(),
        });
      }
      if (!mounted) return;
      setState(() {
        _isEditingLayout = false;
        for (final i in _items) {
          i.isSelected = false;
        }
      });
      if (showMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Roster layout saved!')));
      }
    } catch (e) {
      if (mounted && showMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  void _cancelEditing() {
    setState(() {
      final saved = _savedLayout;
      if (saved != null) {
        try {
          _items = (jsonDecode(saved) as List)
              .map(
                (e) => CustomRosterItem.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList();
        } catch (_) {}
      }
      _isEditingLayout = false;
      for (final i in _items) {
        i.isSelected = false;
      }
    });
  }

  List<AvailableRosterTile> _getAvailableTiles({
    required List<Map<String, dynamic>> stores,
    required Map<String, StoreSettingsModel> storeSettingsMap,
    required String? currentStoreId,
    required List<UserModel> users,
  }) {
    final List<AvailableRosterTile> tiles = [];
    final activeStores = currentStoreId != null
        ? stores.where((s) => s['id'] == currentStoreId).toList()
        : stores;

    for (final store in activeStores) {
      final sid = store['id'] as String;
      final settings = storeSettingsMap[sid];
      if (settings == null) continue;

      final storeUsers = users.where((u) => u.store == sid).toList();
      final storeWts = StaffingCalculator.getWorkingTimesForStore(
        settings,
        storeUsers,
      );

      String storeName = '';
      if (currentStoreId == null) {
        storeName = (store['name'] as String?) ?? sid;
      }

      if (storeWts.isNotEmpty) {
        for (final wt in storeWts) {
          final header = currentStoreId == null
              ? '$storeName - $wt Shifts'
              : '$wt Shifts';
          // Standard positions
          for (final pos in settings.positions) {
            final displayTitle = currentStoreId == null
                ? '$storeName - $wt - $pos'
                : '$wt - $pos';
            tiles.add(
              AvailableRosterTile(
                id: '$sid|$displayTitle|$pos|false|$wt',
                storeId: sid,
                displayTitle: displayTitle,
                rawPos: pos,
                workingTime: wt,
                isTrainer: false,
                isIsolatedTitle: false,
                sectionHeader: header,
              ),
            );
          }
          // Trainer tile for this working time
          final trainerTitle = currentStoreId == null
              ? '$storeName - $wt - Trainer'
              : '$wt - Trainer';
          tiles.add(
            AvailableRosterTile(
              id: '$sid|$trainerTitle|Trainer|false|$wt',
              storeId: sid,
              displayTitle: trainerTitle,
              rawPos: 'Trainer',
              workingTime: wt,
              isTrainer: true,
              isIsolatedTitle: false,
              sectionHeader: header,
            ),
          );
        }
      } else {
        final header = currentStoreId == null
            ? '$storeName - Standard Positions'
            : 'Standard Positions';
        for (final pos in settings.positions) {
          final displayTitle = currentStoreId == null
              ? '$storeName - $pos'
              : pos;
          tiles.add(
            AvailableRosterTile(
              id: '$sid|$displayTitle|$pos|false',
              storeId: sid,
              displayTitle: displayTitle,
              rawPos: pos,
              workingTime: '',
              isTrainer: false,
              isIsolatedTitle: false,
              sectionHeader: header,
            ),
          );
        }
        final trainerTitle = currentStoreId == null
            ? '$storeName - Trainer'
            : 'Trainer';
        tiles.add(
          AvailableRosterTile(
            id: '$sid|$trainerTitle|Trainer|false',
            storeId: sid,
            displayTitle: trainerTitle,
            rawPos: 'Trainer',
            workingTime: '',
            isTrainer: true,
            isIsolatedTitle: false,
            sectionHeader: header,
          ),
        );
      }

      // Titles section
      if (settings.titles.isNotEmpty) {
        final header = currentStoreId == null
            ? '$storeName - Titles'
            : 'Titles';
        for (final t in settings.titles) {
          final displayTitle = currentStoreId == null
              ? '$storeName - ${t.name}'
              : t.name;
          final id = storeWts.isNotEmpty
              ? '$sid|$displayTitle|${t.name}|false|Other'
              : '$sid|$displayTitle|${t.name}|false';
          tiles.add(
            AvailableRosterTile(
              id: id,
              storeId: sid,
              displayTitle: displayTitle,
              rawPos: t.name,
              workingTime: storeWts.isNotEmpty ? 'Other' : '',
              isTrainer: t.name.trim().toLowerCase() == 'trainer',
              isIsolatedTitle: true,
              sectionHeader: header,
            ),
          );
        }
      }

      // Additional Tags section
      final header = currentStoreId == null
          ? '$storeName - Additional Tags'
          : 'Additional Tags';
      final List<String> tagNames = [];
      for (final t in settings.tags) {
        final name = t.name.trim();
        if (name.isNotEmpty &&
            !tagNames.any((n) => n.toLowerCase() == name.toLowerCase())) {
          if (!settings.titles.any(
            (title) => title.name.trim().toLowerCase() == name.toLowerCase(),
          )) {
            tagNames.add(name);
          }
        }
      }
      if (!tagNames.any((n) => n.toLowerCase() == 'trainer') &&
          !settings.titles.any(
            (title) => title.name.trim().toLowerCase() == 'trainer',
          )) {
        tagNames.add('Trainer');
      }

      for (final tagName in tagNames) {
        final displayTitle = currentStoreId == null
            ? '$storeName - $tagName'
            : tagName;
        final id = storeWts.isNotEmpty
            ? '$sid|$displayTitle|$tagName|false|Other'
            : '$sid|$displayTitle|$tagName|false';
        tiles.add(
          AvailableRosterTile(
            id: id,
            storeId: sid,
            displayTitle: displayTitle,
            rawPos: tagName,
            workingTime: storeWts.isNotEmpty ? 'Other' : '',
            isTrainer: tagName.toLowerCase() == 'trainer',
            isIsolatedTitle: true,
            sectionHeader: header,
          ),
        );
      }
    }
    return tiles;
  }

  List<UserModel> _getMembersForTilePreview(
    AvailableRosterTile tile,
    List<UserModel> allUsers,
  ) {
    final storeUsers = allUsers.where((u) => u.store == tile.storeId).toList();
    if (tile.isTrainer) {
      return storeUsers.where((u) {
        final isTrainer =
            (u.title?.trim().toLowerCase() == 'trainer') ||
            ((u.additionalTags ?? []).any(
              (t) => t.trim().toLowerCase() == 'trainer',
            )) ||
            ((u.position ?? '').trim().toLowerCase() == 'trainer');
        if (!isTrainer) return false;
        if (tile.workingTime.isNotEmpty && tile.workingTime != 'Other') {
          return (u.workingTime ?? '').trim().toLowerCase() ==
              tile.workingTime.trim().toLowerCase();
        }
        return true;
      }).toList();
    }

    if (tile.isIsolatedTitle) {
      return storeUsers.where((u) {
        if (u.title != null &&
            u.title!.trim().toLowerCase() == tile.rawPos.trim().toLowerCase()) {
          return true;
        }
        if ((u.additionalTags ?? []).any(
          (t) => t.trim().toLowerCase() == tile.rawPos.trim().toLowerCase(),
        )) {
          return true;
        }
        return false;
      }).toList();
    }

    return storeUsers.where((u) {
      if ((u.position ?? '').trim().toLowerCase() !=
          tile.rawPos.trim().toLowerCase()) {
        return false;
      }
      if (tile.workingTime.isNotEmpty && tile.workingTime != 'Other') {
        return (u.workingTime ?? '').trim().toLowerCase() ==
            tile.workingTime.trim().toLowerCase();
      }
      return true;
    }).toList();
  }

  Widget _buildConfigUI({
    required List<AvailableRosterTile> availableTiles,
    required List<UserModel> users,
    required Map<String, dynamic> rosterNeeds,
    required Map<String, StoreSettingsModel> storeSettingsMap,
  }) {
    final Map<String, List<AvailableRosterTile>> sections = {};
    for (final tile in availableTiles) {
      sections.putIfAbsent(tile.sectionHeader, () => []).add(tile);
    }

    return Scrollbar(
      controller: _configScrollController,
      thumbVisibility: true,
      child: CustomScrollView(
        controller: _configScrollController,
        cacheExtent: 500,
        slivers: sections.entries.map((entry) {
          return SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _ConfigSectionHeaderDelegate(title: entry.key),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    children: entry.value
                        .map(
                          (t) => RepaintBoundary(
                            child: _buildConfigTile(
                              t,
                              users: users,
                              rosterNeeds: rosterNeeds,
                              settings: storeSettingsMap[t.storeId],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildConfigTile(
    AvailableRosterTile tile, {
    required List<UserModel> users,
    required Map<String, dynamic> rosterNeeds,
    required StoreSettingsModel? settings,
  }) {
    final addedItem = _items.where((i) => _isSameTile(i.id, tile)).firstOrNull;
    final isAdded = addedItem != null;
    final itemIsIsolated =
        addedItem != null &&
        addedItem.id.split('|').length > 3 &&
        addedItem.id.split('|')[3] == 'true';

    String badgeText = 'Add';
    if (isAdded) {
      if (_isStandardPositionTile(tile, settings)) {
        badgeText = 'Added';
      } else {
        badgeText = itemIsIsolated ? 'Added (Isolated)' : 'Added (Shared)';
      }
      if (addedItem.splitTitles?.isNotEmpty == true) badgeText += ' · Split';
    }

    // Saving writes the change to the store's own roster (also from All
    // Stores, which shows the stores' rosters).
    Future<void> toggleTile() async {
      if (isAdded) {
        setState(() {
          _items.removeWhere((i) => _isSameTile(i.id, tile));
        });
        _saveLayout(showMessage: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Removed "${tile.displayTitle}" from ${_bothRostersLabel(tile.storeId)}.',
            ),
          ),
        );
        return;
      }

      bool isIsolated = false;
      if (!_isStandardPositionTile(tile, settings)) {
        final choice = await _showRosterIsolationDialog(context, tile);
        if (choice == null) return;
        isIsolated = choice;
      }
      if (!mounted) return;
      final splitTitles = await _askRosterSplitTitles(context, tile, settings);
      if (splitTitles == null || !mounted) return;

      final finalId = _buildItemId(tile, isIsolated);
      final pos = _findSlotForTile(tile, 350.0, 550.0);
      final newItem = CustomRosterItem(
        id: finalId,
        x: pos.dx,
        y: pos.dy,
        width: 350.0,
        height: 550.0,
        splitTitles: splitTitles,
      );
      setState(() => _items.add(newItem));
      _saveLayout(showMessage: false);
    }

    final members = _getMembersForTilePreview(tile, users);
    final needsKey =
        (tile.workingTime.isNotEmpty && tile.workingTime != 'Other')
        ? '${tile.storeId}_${tile.rawPos}_${tile.workingTime}'
        : '${tile.storeId}_${tile.rawPos}';
    final shiftsNeeded = (rosterNeeds[needsKey] as num?)?.toInt() ?? 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: toggleTile,
      child: Container(
        width: 350,
        height: 550,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isAdded ? AppTheme.accent : Theme.of(context).dividerColor,
            width: isAdded ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (PointerSignalEvent event) {
                    if (event is PointerScrollEvent) {
                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (PointerSignalEvent e) {},
                      );
                    }
                  },
                  child: PrimaryScrollController.none(
                    child: IgnorePointer(
                      ignoring: true,
                      child: _buildPositionColumn(
                        context,
                        ref,
                        tile.storeId,
                        tile.displayTitle,
                        tile.rawPos,
                        tile.workingTime,
                        members,
                        shiftsNeeded,
                        tile.isIsolatedTitle,
                        addedItem?.splitTitles,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: toggleTile,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isAdded
                          ? AppTheme.accent
                          : Theme.of(context).cardColor.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isAdded
                            ? AppTheme.accent
                            : Theme.of(context).dividerColor,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAdded ? Icons.check : Icons.add,
                          size: 14,
                          color: isAdded ? Colors.white : AppTheme.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isAdded
                                ? Colors.white
                                : Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, List<UserModel>> _computePositionGroups({
    required List<CustomRosterItem> activeItems,
    required List<AvailableRosterTile> availableTiles,
    required List<UserModel> users,
    required Map<String, StoreSettingsModel> storeSettingsMap,
  }) {
    final groups = StaffingCalculator.groupRosterMembers(
      tileKeys: activeItems.map((i) => i.id).toList(),
      users: users,
      storeSettingsMap: storeSettingsMap,
    );
    return {
      for (final tile in availableTiles) tile.id: <UserModel>[],
      ...groups,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(rosterEditModeProvider, (prev, next) {
      if (next && !widget.isConfigMode) {
        setState(() {
          _isEditingLayout = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(rosterEditModeProvider.notifier).state = false;
        });
      }
    });

    if (!widget.isConfigMode && ref.watch(rosterEditModeProvider)) {
      _isEditingLayout = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(rosterEditModeProvider.notifier).state = false;
        if (mounted) setState(() {});
      });
    }

    final usersAsyncValue = ref.watch(currentMembersProvider);
    final rosterNeedsAsyncValue = ref.watch(rosterNeedsStreamProvider);
    final storesAsync = ref.watch(allStoresStreamProvider);
    final currentStoreId = ref.watch(currentStoreIdProvider);
    ref.watch(rosterLayoutRevisionProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: usersAsyncValue.when(
        data: (users) {
          final rosterNeeds = rosterNeedsAsyncValue.valueOrNull ?? {};
          final allStores = storesAsync.valueOrNull ?? [];
          final currentUser = ref.watch(currentUserProvider);
          final ownedStoresList =
              (currentUser?['owned_stores'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          final stores = ownedStoresList.isNotEmpty
              ? allStores
                    .where((s) => ownedStoresList.contains(s['id']))
                    .toList()
              : allStores;
          _storeNames = {
            for (final s in stores)
              if (currentStoreId == null || s['id'] == currentStoreId)
                s['id'] as String: (s['name'] as String?) ?? s['id'] as String,
          };

          if (users.isEmpty) {
            return const Center(child: Text('No team members found.'));
          }

          final Map<String, StoreSettingsModel> storeSettingsMap = {};
          for (final store in stores) {
            final sid = store['id'] as String;
            final settings = ref
                .watch(specificStoreSettingsProvider(sid))
                .valueOrNull;
            if (settings != null) {
              storeSettingsMap[sid] = settings;
            }
          }

          final availableTiles = _getAvailableTiles(
            stores: stores,
            storeSettingsMap: storeSettingsMap,
            currentStoreId: currentStoreId,
            users: users,
          );

          // Populate initial default layout groups
          final Map<String, List<UserModel>> defaultPositionGroups = {};

          List<String> getWorkingTimesForStore(
            StoreSettingsModel? settings,
            List<UserModel> storeUsers,
          ) {
            if (settings != null && settings.workingTimes.isNotEmpty) {
              final list = settings.workingTimes.where((w) {
                final l = w.trim().toLowerCase();
                return l != 'other' && l != 'unassigned';
              }).toList();
              if (list.isNotEmpty) return list;
            }
            final userWts = storeUsers
                .map((u) => u.workingTime?.trim() ?? '')
                .where(
                  (w) =>
                      w.isNotEmpty &&
                      w.toLowerCase() != 'other' &&
                      w.toLowerCase() != 'unassigned',
                )
                .toSet()
                .toList();
            if (userWts.isNotEmpty) return userWts;
            return [];
          }

          // Only the stores on screen (one store, or all of them for All
          // Stores), so a store's default tiles are the same either way.
          for (final store in stores.where(
            (s) => currentStoreId == null || s['id'] == currentStoreId,
          )) {
            final sid = store['id'] as String;
            final settings = storeSettingsMap[sid];
            if (settings == null) continue;

            final storeUsers = users.where((u) => u.store == sid).toList();
            final storeWts = getWorkingTimesForStore(settings, storeUsers);

            String storeName = '';
            if (currentStoreId == null) {
              final storeObj = allStores
                  .where((s) => s['id'] == sid)
                  .firstOrNull;
              storeName = storeObj?['name'] ?? 'Store';
            }

            if (storeWts.isNotEmpty) {
              for (final wt in storeWts) {
                for (final pos in settings.positions) {
                  final displayTitle = currentStoreId == null
                      ? '$storeName - $wt - $pos'
                      : '$wt - $pos';
                  final groupKey = '$sid|$displayTitle|$pos|false|$wt';
                  defaultPositionGroups.putIfAbsent(groupKey, () => []);
                }
              }

              for (final t in settings.titles.where((t) => t.isolatedRoster)) {
                final displayTitle = currentStoreId == null
                    ? '$storeName - ${t.name}'
                    : t.name;
                final groupKey = '$sid|$displayTitle|${t.name}|true|Other';
                defaultPositionGroups.putIfAbsent(groupKey, () => []);
              }

              for (final t in settings.tags.where((t) => t.isolatedRoster)) {
                final displayTitle = currentStoreId == null
                    ? '$storeName - ${t.name}'
                    : t.name;
                final groupKey = '$sid|$displayTitle|${t.name}|true|Other';
                defaultPositionGroups.putIfAbsent(groupKey, () => []);
              }
            } else {
              for (final pos in settings.positions) {
                final groupKey = currentStoreId == null
                    ? '$sid|$storeName - $pos|$pos|false'
                    : '$sid|$pos|$pos|false';
                defaultPositionGroups.putIfAbsent(groupKey, () => []);
              }

              for (final t in settings.titles.where((t) => t.isolatedRoster)) {
                final groupKey = currentStoreId == null
                    ? '$sid|$storeName - ${t.name}|${t.name}|true'
                    : '$sid|${t.name}|${t.name}|true';
                defaultPositionGroups.putIfAbsent(groupKey, () => []);
              }

              for (final t in settings.tags.where((t) => t.isolatedRoster)) {
                final groupKey = currentStoreId == null
                    ? '$sid|$storeName - ${t.name}|${t.name}|true'
                    : '$sid|${t.name}|${t.name}|true';
                defaultPositionGroups.putIfAbsent(groupKey, () => []);
              }
            }
          }

          for (final user in users) {
            final sid = user.store ?? 'unknown';
            final settings = storeSettingsMap[sid];

            bool isIsolated = false;
            String? isolatedName;
            if (settings != null) {
              if (user.title != null && user.title!.trim().isNotEmpty) {
                TitleConfig? titleConfig = settings.titles
                    .where(
                      (t) =>
                          t.name.trim().toLowerCase() ==
                          user.title!.trim().toLowerCase(),
                    )
                    .firstOrNull;
                titleConfig ??= settings.tags
                    .where(
                      (t) =>
                          t.name.trim().toLowerCase() ==
                          user.title!.trim().toLowerCase(),
                    )
                    .firstOrNull;
                if (titleConfig?.isolatedRoster == true) {
                  isIsolated = true;
                  isolatedName = user.title;
                }
              }
              if (!isIsolated && (user.additionalTags ?? []).isNotEmpty) {
                for (final tag in user.additionalTags!) {
                  final tagConfig = settings.tags
                      .where(
                        (t) =>
                            t.name.trim().toLowerCase() ==
                            tag.trim().toLowerCase(),
                      )
                      .firstOrNull;
                  if (tagConfig?.isolatedRoster == true) {
                    isIsolated = true;
                    isolatedName = tag;
                    break;
                  }
                }
              }
            }

            final pos = isIsolated
                ? (isolatedName ?? 'Unassigned')
                : (user.position ?? 'Unassigned');

            String storeName = '';
            if (currentStoreId == null) {
              final storeObj = allStores
                  .where((s) => s['id'] == sid)
                  .firstOrNull;
              storeName = storeObj?['name'] ?? 'Store';
            }

            final storeUsers = users.where((u) => u.store == sid).toList();
            final storeWts = getWorkingTimesForStore(settings, storeUsers);

            if (storeWts.isNotEmpty) {
              String targetWt = 'Other';
              if (!isIsolated) {
                final userWt = (user.workingTime ?? '').trim().toLowerCase();
                for (final wt in storeWts) {
                  if (userWt == wt.trim().toLowerCase()) {
                    targetWt = wt;
                    break;
                  }
                }
              }

              String displayTitle;
              if (isIsolated) {
                displayTitle = currentStoreId == null
                    ? '$storeName - $pos'
                    : pos;
              } else if (targetWt == 'Other') {
                displayTitle = currentStoreId == null
                    ? '$storeName - $pos'
                    : pos;
              } else {
                displayTitle = currentStoreId == null
                    ? '$storeName - $targetWt - $pos'
                    : '$targetWt - $pos';
              }

              final groupKey = '$sid|$displayTitle|$pos|$isIsolated|$targetWt';
              defaultPositionGroups.putIfAbsent(groupKey, () => []).add(user);
            } else {
              final groupKey = currentStoreId == null
                  ? '$sid|$storeName - $pos|$pos|$isIsolated'
                  : '$sid|$pos|$pos|$isIsolated';
              defaultPositionGroups.putIfAbsent(groupKey, () => []).add(user);
            }
          }

          final defaultLayout = _generateDefaultLayout(
            stores: stores,
            storeSettingsMap: storeSettingsMap,
            positionGroups: defaultPositionGroups,
            currentStoreId: currentStoreId,
          );

          final storeKey = currentStoreId ?? 'all';
          _loadLayout(storeKey, defaultLayout);

          // Position groups for active layout items and available tiles
          final activeItems = _items.isNotEmpty ? _items : defaultLayout;
          final activeKeysSignature = activeItems.map((i) => i.id).join(';');
          int usersHash = Object.hash(
            users.length,
            currentStoreId,
            storeSettingsMap.length,
          );
          for (final u in users) {
            usersHash = Object.hash(
              usersHash,
              u.id,
              u.position,
              u.title,
              u.workingTime,
              u.additionalTags?.join(','),
            );
          }

          final Map<String, List<UserModel>> positionGroups;
          if (activeKeysSignature == _lastActiveKeysSignature &&
              usersHash == _lastUsersHash &&
              _cachedPositionGroups.isNotEmpty) {
            positionGroups = _cachedPositionGroups;
          } else {
            positionGroups = _computePositionGroups(
              activeItems: activeItems,
              availableTiles: availableTiles,
              users: users,
              storeSettingsMap: storeSettingsMap,
            );
            _lastActiveKeysSignature = activeKeysSignature;
            _lastUsersHash = usersHash;
            _cachedPositionGroups = positionGroups;
          }

          if (widget.isConfigMode) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              tooltip: 'Back to Rosters',
                              onPressed: () => context.go('/rosters'),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Configure Rosters',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.titleLarge?.color,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          ref.read(rosterEditModeProvider.notifier).state =
                              true;
                          context.go('/rosters');
                        },
                        icon: const Icon(Icons.grid_view, size: 16),
                        label: const Text('Edit Roster Display'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sync_alt,
                        size: 16,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentStoreId == null
                              ? 'All Stores shows each store\'s own roster, one below the other. Changes here are saved to that store\'s roster.'
                              : 'Changes here also show on the All Stores roster, which shows each store\'s roster one below the other.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildConfigUI(
                    availableTiles: availableTiles,
                    users: users,
                    rosterNeeds: rosterNeeds,
                    storeSettingsMap: storeSettingsMap,
                  ),
                ),
              ],
            );
          }

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (_isEditingLayout) ...[
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              tooltip: 'Exit Layout Editing',
                              onPressed: _cancelEditing,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              'Store Rosters & Staffing (6 Days/Week)',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.color,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      children: [
                        if (!_isEditingLayout) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.lightBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.accent),
                            ),
                            child: Text(
                              'Active: Standard Roster',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.dashboard_customize),
                            tooltip: 'Configure Rosters',
                            onPressed: () {
                              if (GoRouter.maybeOf(context) != null) {
                                context.go('/rosters/config');
                              } else {
                                setState(() {
                                  _isEditingLayout = true;
                                });
                              }
                            },
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            onPressed: () {
                              if (GoRouter.maybeOf(context) != null) {
                                context.go('/rosters/config');
                              }
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add to Roster'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _items = _generateDefaultLayout(
                                  stores: stores,
                                  storeSettingsMap: storeSettingsMap,
                                  positionGroups: defaultPositionGroups,
                                  currentStoreId: currentStoreId,
                                );
                                _sessionLayoutCache[currentStoreId ?? 'all'] =
                                    List.of(_items);
                              });
                            },
                            icon: const Icon(Icons.restart_alt, size: 16),
                            label: const Text('Reset to Default'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _cancelEditing,
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Cancel'),
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
                const SizedBox(height: 24),
                Expanded(
                  child: LayoutBuilder(
                    key: _rosterViewKey,
                    builder: (context, constraints) {
                      double maxX = _items.isEmpty
                          ? 0
                          : _items.map((i) => i.x + i.width).reduce(max);
                      double maxY = _items.isEmpty
                          ? 0
                          : _items.map((i) => i.y + i.height).reduce(max);

                      // Extra room past the last tile only while editing (to
                      // drag tiles into); otherwise the canvas ends where the
                      // tiles do, so there's no empty space to scroll into.
                      final extra = _isEditingLayout ? 100.0 : 0.0;
                      final canvasWidth = max(
                        constraints.maxWidth,
                        maxX + extra,
                      );
                      final canvasHeight = max(
                        constraints.maxHeight,
                        maxY + extra,
                      );

                      return NotificationListener<ScrollNotification>(
                        onNotification: _onCanvasScrollNotification,
                        child: Scrollbar(
                          controller: _verticalScrollController,
                          thumbVisibility: true,
                          // Only the canvas's own scroll views; a tile's list
                          // must never drive these bars.
                          notificationPredicate: (n) =>
                              n.depth == 0 && n.metrics.axis == Axis.vertical,
                          child: Scrollbar(
                            controller: _horizontalScrollController,
                            thumbVisibility: true,
                            notificationPredicate: (n) =>
                                n.depth == 1 &&
                                n.metrics.axis == Axis.horizontal,
                            child: SingleChildScrollView(
                              controller: _verticalScrollController,
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: Listener(
                                  onPointerSignal: _onCanvasPointerSignal,
                                  child: Container(
                                    width: canvasWidth,
                                    height: canvasHeight,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: _isEditingLayout
                                          ? Border.all(
                                              color: AppTheme.accent.withValues(
                                                alpha: 0.3,
                                              ),
                                            )
                                          : null,
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        if (_isEditingLayout)
                                          Positioned(
                                            width: canvasWidth,
                                            height: canvasHeight,
                                            child: const RepaintBoundary(
                                              child: CustomPaint(
                                                painter: GridPainter(),
                                              ),
                                            ),
                                          ),
                                        ..._items.map((item) {
                                          final key = item.id;
                                          final members =
                                              positionGroups[key] ?? [];
                                          final parts = key.split('|');
                                          final sid = parts[0];
                                          final displayTitle = parts[1];
                                          final rawPos = parts[2];
                                          final isIsolatedTitle =
                                              (parts.length > 3 &&
                                                  parts[3] == 'true') ||
                                              (storeSettingsMap[sid]?.titles.any(
                                                    (t) =>
                                                        t.name
                                                            .trim()
                                                            .toLowerCase() ==
                                                        rawPos
                                                            .trim()
                                                            .toLowerCase(),
                                                  ) ==
                                                  true) ||
                                              (storeSettingsMap[sid]?.tags.any(
                                                    (t) =>
                                                        t.name
                                                            .trim()
                                                            .toLowerCase() ==
                                                        rawPos
                                                            .trim()
                                                            .toLowerCase(),
                                                  ) ==
                                                  true);
                                          final workingTime = parts.length > 4
                                              ? parts[4]
                                              : '';
                                          final needsKey =
                                              (workingTime.isNotEmpty &&
                                                  workingTime != 'Other')
                                              ? '${sid}_${rawPos}_$workingTime'
                                              : '${sid}_$rawPos';
                                          final shiftsNeeded =
                                              (rosterNeeds[needsKey] as num?)
                                                  ?.toInt() ??
                                              0;

                                          final content = _buildPositionColumn(
                                            context,
                                            ref,
                                            sid,
                                            displayTitle,
                                            rawPos,
                                            workingTime,
                                            members,
                                            shiftsNeeded,
                                            isIsolatedTitle,
                                            item.splitTitles,
                                          );

                                          return Positioned(
                                            left: item.x,
                                            top: item.y,
                                            width: item.width,
                                            height: item.height,
                                            child: ValueListenableBuilder<bool>(
                                              valueListenable:
                                                  _canvasScrollLatched,
                                              builder:
                                                  (context, latched, child) =>
                                                      IgnorePointer(
                                                        ignoring: latched,
                                                        child: child,
                                                      ),
                                              child: MouseRegion(
                                                onEnter: (_) =>
                                                    _hoveredTileCount++,
                                                onExit: (_) {
                                                  if (_hoveredTileCount > 0)
                                                    _hoveredTileCount--;
                                                },
                                                child: RepaintBoundary(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          10.0,
                                                        ),
                                                    child: GestureDetector(
                                                      onTap: () {
                                                        if (!_isEditingLayout)
                                                          return;
                                                        setState(() {
                                                          for (var i
                                                              in _items) {
                                                            i.isSelected =
                                                                false;
                                                          }
                                                          item.isSelected =
                                                              true;
                                                        });
                                                      },
                                                      onPanStart:
                                                          _isEditingLayout
                                                          ? (details) {
                                                              if (!item
                                                                  .isSelected) {
                                                                for (var i
                                                                    in _items) {
                                                                  i.isSelected =
                                                                      false;
                                                                }
                                                                item.isSelected =
                                                                    true;
                                                              }
                                                              for (var i
                                                                  in _items.where(
                                                                    (e) => e
                                                                        .isSelected,
                                                                  )) {
                                                                i._startX = i.x;
                                                                i._startY = i.y;
                                                              }
                                                            }
                                                          : null,
                                                      onPanUpdate:
                                                          _isEditingLayout
                                                          ? (details) {
                                                              setState(() {
                                                                for (var i
                                                                    in _items.where(
                                                                      (e) => e
                                                                          .isSelected,
                                                                    )) {
                                                                  i.x += details
                                                                      .delta
                                                                      .dx;
                                                                  i.y += details
                                                                      .delta
                                                                      .dy;
                                                                }
                                                              });

                                                              // Auto-scroll
                                                              final yPos = details
                                                                  .globalPosition
                                                                  .dy;
                                                              final xPos = details
                                                                  .globalPosition
                                                                  .dx;
                                                              final renderBox =
                                                                  _rosterViewKey
                                                                          .currentContext
                                                                          ?.findRenderObject()
                                                                      as RenderBox?;
                                                              if (renderBox !=
                                                                  null) {
                                                                final topLeft =
                                                                    renderBox
                                                                        .localToGlobal(
                                                                          Offset
                                                                              .zero,
                                                                        );
                                                                final leftEdge =
                                                                    topLeft.dx;
                                                                final rightEdge =
                                                                    leftEdge +
                                                                    renderBox
                                                                        .size
                                                                        .width;
                                                                final topEdge =
                                                                    topLeft.dy;
                                                                final bottomEdge =
                                                                    topEdge +
                                                                    renderBox
                                                                        .size
                                                                        .height;

                                                                double
                                                                dyScroll = 0;
                                                                if (yPos <
                                                                    topEdge +
                                                                        80) {
                                                                  dyScroll =
                                                                      -10;
                                                                } else if (yPos >
                                                                    bottomEdge -
                                                                        80) {
                                                                  dyScroll = 10;
                                                                }

                                                                double
                                                                dxScroll = 0;
                                                                if (xPos <
                                                                    leftEdge +
                                                                        80) {
                                                                  dxScroll =
                                                                      -10;
                                                                } else if (xPos >
                                                                    rightEdge -
                                                                        80) {
                                                                  dxScroll = 10;
                                                                }

                                                                setState(() {
                                                                  if (dyScroll !=
                                                                          0 &&
                                                                      _verticalScrollController
                                                                          .hasClients) {
                                                                    double
                                                                    oldOffset =
                                                                        _verticalScrollController
                                                                            .offset;
                                                                    _verticalScrollController.jumpTo(
                                                                      (oldOffset +
                                                                              dyScroll)
                                                                          .clamp(
                                                                            0.0,
                                                                            _verticalScrollController.position.maxScrollExtent,
                                                                          ),
                                                                    );
                                                                    double
                                                                    actualScroll =
                                                                        _verticalScrollController
                                                                            .offset -
                                                                        oldOffset;
                                                                    for (var i
                                                                        in _items.where(
                                                                          (
                                                                            e,
                                                                          ) => e
                                                                              .isSelected,
                                                                        )) {
                                                                      i.y +=
                                                                          actualScroll;
                                                                    }
                                                                  }
                                                                  if (dxScroll !=
                                                                          0 &&
                                                                      _horizontalScrollController
                                                                          .hasClients) {
                                                                    double
                                                                    oldOffset =
                                                                        _horizontalScrollController
                                                                            .offset;
                                                                    _horizontalScrollController.jumpTo(
                                                                      (oldOffset +
                                                                              dxScroll)
                                                                          .clamp(
                                                                            0.0,
                                                                            _horizontalScrollController.position.maxScrollExtent,
                                                                          ),
                                                                    );
                                                                    double
                                                                    actualScroll =
                                                                        _horizontalScrollController
                                                                            .offset -
                                                                        oldOffset;
                                                                    for (var i
                                                                        in _items.where(
                                                                          (
                                                                            e,
                                                                          ) => e
                                                                              .isSelected,
                                                                        )) {
                                                                      i.x +=
                                                                          actualScroll;
                                                                    }
                                                                  }
                                                                });
                                                              }
                                                            }
                                                          : null,
                                                      onPanEnd: _isEditingLayout
                                                          ? (details) {
                                                              setState(() {
                                                                bool collision =
                                                                    false;
                                                                for (var i
                                                                    in _items.where(
                                                                      (e) => e
                                                                          .isSelected,
                                                                    )) {
                                                                  i.x = max(
                                                                    0.0,
                                                                    snap(i.x),
                                                                  );
                                                                  i.y = max(
                                                                    0.0,
                                                                    snap(i.y),
                                                                  );

                                                                  final othersAtPos = _items
                                                                      .where(
                                                                        (o) =>
                                                                            !o.isSelected &&
                                                                            o.x ==
                                                                                i.x &&
                                                                            o.y ==
                                                                                i.y,
                                                                      )
                                                                      .toList();
                                                                  if (othersAtPos
                                                                          .length ==
                                                                      1) {
                                                                    final other =
                                                                        othersAtPos
                                                                            .first;
                                                                    other.x = i
                                                                        ._startX;
                                                                    other.y = i
                                                                        ._startY;
                                                                  }

                                                                  if (_hasCollision(
                                                                    i,
                                                                  )) {
                                                                    collision =
                                                                        true;
                                                                  }
                                                                }
                                                                if (collision) {
                                                                  for (var i
                                                                      in _items.where(
                                                                        (e) => e
                                                                            .isSelected,
                                                                      )) {
                                                                    i.x = i
                                                                        ._startX;
                                                                    i.y = i
                                                                        ._startY;
                                                                  }
                                                                }
                                                              });
                                                            }
                                                          : null,
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                          border:
                                                              item.isSelected &&
                                                                  _isEditingLayout
                                                              ? Border.all(
                                                                  color: AppTheme
                                                                      .accent,
                                                                  width: 2.5,
                                                                )
                                                              : null,
                                                        ),
                                                        child: Stack(
                                                          children: [
                                                            Positioned.fill(
                                                              child: content,
                                                            ),
                                                            if (item.isSelected &&
                                                                _isEditingLayout)
                                                              Positioned(
                                                                right: 0,
                                                                bottom: 0,
                                                                child: GestureDetector(
                                                                  behavior:
                                                                      HitTestBehavior
                                                                          .opaque,
                                                                  onPanStart: (details) {
                                                                    item._startX =
                                                                        item.x;
                                                                    item._startY =
                                                                        item.y;
                                                                    item._startWidth =
                                                                        item.width;
                                                                    item._startHeight =
                                                                        item.height;
                                                                  },
                                                                  onPanUpdate: (details) {
                                                                    setState(() {
                                                                      item.width =
                                                                          (item.width +
                                                                                  details.delta.dx)
                                                                              .clamp(
                                                                                200.0,
                                                                                2000.0,
                                                                              );
                                                                      item.height =
                                                                          (item.height +
                                                                                  details.delta.dy)
                                                                              .clamp(
                                                                                200.0,
                                                                                2000.0,
                                                                              );
                                                                    });
                                                                  },
                                                                  onPanEnd: (details) {
                                                                    setState(() {
                                                                      item.width =
                                                                          snap(
                                                                            item.width,
                                                                          );
                                                                      item.height =
                                                                          snap(
                                                                            item.height,
                                                                          );

                                                                      double
                                                                      diffW =
                                                                          item.width -
                                                                          item._startWidth;
                                                                      double
                                                                      diffH =
                                                                          item.height -
                                                                          item._startHeight;
                                                                      Map<
                                                                        String,
                                                                        Offset
                                                                      >
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
                                                                        if (diffW >
                                                                            0) {
                                                                          for (var o
                                                                              in _items) {
                                                                            if (o.id !=
                                                                                    item.id &&
                                                                                o.x >=
                                                                                    item._startX +
                                                                                        item._startWidth -
                                                                                        1) {
                                                                              o.x += diffW;
                                                                            }
                                                                          }
                                                                        }
                                                                        if (diffH >
                                                                            0) {
                                                                          for (var o
                                                                              in _items) {
                                                                            if (o.id !=
                                                                                    item.id &&
                                                                                o.y >=
                                                                                    item._startY +
                                                                                        item._startHeight -
                                                                                        1) {
                                                                              o.y += diffH;
                                                                            }
                                                                          }
                                                                        }
                                                                      }

                                                                      bool
                                                                      anyCollision =
                                                                          false;
                                                                      for (var i
                                                                          in _items) {
                                                                        if (_hasCollision(
                                                                          i,
                                                                        )) {
                                                                          anyCollision =
                                                                              true;
                                                                        }
                                                                      }

                                                                      if (anyCollision) {
                                                                        item.width =
                                                                            item._startWidth;
                                                                        item.height =
                                                                            item._startHeight;
                                                                        for (var i
                                                                            in _items) {
                                                                          i.x =
                                                                              originalPos[i.id]!.dx;
                                                                          i.y =
                                                                              originalPos[i.id]!.dy;
                                                                        }
                                                                      }
                                                                    });
                                                                  },
                                                                  child: MouseRegion(
                                                                    cursor: SystemMouseCursors
                                                                        .resizeDownRight,
                                                                    child: Container(
                                                                      padding:
                                                                          const EdgeInsets.all(
                                                                            4,
                                                                          ),
                                                                      decoration: BoxDecoration(
                                                                        color: AppTheme
                                                                            .accent,
                                                                        borderRadius: const BorderRadius.only(
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
                                                                        size:
                                                                            16,
                                                                        color: Colors
                                                                            .white,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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

  Widget _buildPositionColumn(
    BuildContext context,
    WidgetRef ref,
    String storeId,
    String displayTitle,
    String rawPos,
    String workingTime,
    List<UserModel> members,
    int shiftsNeeded,
    bool isIsolatedTitle, [
    List<String>? splitTitles,
  ]) {
    return _RosterPositionColumnTile(
      key: ValueKey('$storeId|$displayTitle|$rawPos|$workingTime'),
      storeId: storeId,
      displayTitle: displayTitle,
      rawPos: rawPos,
      workingTime: workingTime,
      members: members,
      shiftsNeeded: shiftsNeeded,
      isIsolatedTitle: isIsolatedTitle,
      splitTitles: splitTitles,
    );
  }

  /// Rosters use softer color than the rest of the app: a faint wash behind
  /// and a thin border, so a page full of titles isn't overwhelming.
  static Color _wash(Color c) =>
      c.withValues(alpha: AppTheme.isLightTheme ? 0.10 : 0.07);
  static Color _line(Color c) =>
      c.withValues(alpha: AppTheme.isLightTheme ? 0.6 : 0.5);
}

class _RosterPositionColumnTile extends ConsumerStatefulWidget {
  final String storeId;
  final String displayTitle;
  final String rawPos;
  final String workingTime;
  final List<UserModel> members;
  final int shiftsNeeded;
  final bool isIsolatedTitle;
  final List<String>? splitTitles;

  const _RosterPositionColumnTile({
    super.key,
    required this.storeId,
    required this.displayTitle,
    required this.rawPos,
    this.workingTime = '',
    required this.members,
    required this.shiftsNeeded,
    required this.isIsolatedTitle,
    this.splitTitles,
  });

  @override
  ConsumerState<_RosterPositionColumnTile> createState() =>
      _RosterPositionColumnTileState();
}

class _RosterPositionColumnTileState
    extends ConsumerState<_RosterPositionColumnTile> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildCoverageBanner(
    BuildContext context,
    PositionStaffingResult staffing,
  ) {
    final bool hasDeficit = staffing.hiresNeeded > 0;
    final Color bgColor = hasDeficit
        ? AppTheme.primaryRed
        : (AppTheme.isLightTheme
              ? const Color(0xFFF1F5F9)
              : const Color(0xFF334155));

    final Color textColor = hasDeficit
        ? Colors.white
        : (AppTheme.isLightTheme ? const Color(0xFF334155) : Colors.white);

    final fmt = StaffingCalculator.formatShifts;
    final covered =
        'Covered: ${fmt(staffing.shiftsCovered)}/${staffing.weeklyShiftsNeeded}';
    String bannerText;
    if (staffing.shiftDeficit > 0) {
      final hires = staffing.hiresNeeded;
      bannerText =
          '$covered (-${fmt(staffing.shiftDeficit)}) • Need $hires ${hires == 1 ? 'hire' : 'hires'}';
    } else if (staffing.shiftSurplus > 0) {
      final people = staffing.surplusPeople;
      bannerText = people > 0
          ? '$covered (+${fmt(staffing.shiftSurplus)}) • Surplus $people ${people == 1 ? 'person' : 'people'}'
          : '$covered (+${fmt(staffing.shiftSurplus)} surplus shifts)';
    } else {
      bannerText = covered;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        bannerText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = [...widget.members];
    members.sort((a, b) => (a.firstName ?? '').compareTo(b.firstName ?? ''));

    final int dailyShiftsNeeded = widget.shiftsNeeded;
    final staffing = StaffingCalculator.evaluateGroup(
      key: widget.rawPos,
      storeId: widget.storeId,
      displayName: widget.displayTitle,
      dailyShiftsNeeded: dailyShiftsNeeded,
      members: members,
    );
    final int weeklyShiftsNeeded = staffing.weeklyShiftsNeeded;

    final savePos =
        (widget.workingTime.isNotEmpty && widget.workingTime != 'Other')
        ? '${widget.rawPos}_${widget.workingTime}'
        : widget.rawPos;

    final storeSettings = ref
        .watch(specificStoreSettingsProvider(widget.storeId))
        .valueOrNull;

    Color columnColor = AppTheme.accent;
    if (storeSettings != null && widget.isIsolatedTitle) {
      final config =
          storeSettings.titles
              .where((t) => t.name == widget.rawPos)
              .firstOrNull ??
          storeSettings.tags.where((t) => t.name == widget.rawPos).firstOrNull;
      if (config != null) {
        columnColor = AppTheme.getColorFromName(config.color);
      }
    }

    final Map<String, List<UserModel>> splitGroups = {};
    final List<UserModel> regularMembers = [];
    final split = widget.splitTitles;

    /// The split group [user] belongs in, or null to list them normally.
    String? splitGroupFor(UserModel user) {
      if (split != null) {
        // Chosen when the tile was added: title first, then additional tags.
        final title = (user.title ?? '').trim().toLowerCase();
        final tags = (user.additionalTags ?? [])
            .map((t) => t.trim().toLowerCase())
            .toSet();
        return split
                .where((s) => s.trim().toLowerCase() == title)
                .firstOrNull ??
            split
                .where((s) => tags.contains(s.trim().toLowerCase()))
                .firstOrNull;
      }
      // Older tiles: the per-title "Split in Area" setting.
      if (storeSettings == null || user.title == null) return null;
      final titleConfig =
          storeSettings.titles.where((t) => t.name == user.title).firstOrNull ??
          storeSettings.tags.where((t) => t.name == user.title).firstOrNull;
      return titleConfig?.splitInArea == true ? user.title : null;
    }

    // Groups appear in the order they were chosen.
    for (final s in split ?? const <String>[]) {
      splitGroups[s] = [];
    }
    for (final user in members) {
      final group = splitGroupFor(user);
      if (group != null) {
        splitGroups.putIfAbsent(group, () => []).add(user);
      } else {
        regularMembers.add(user);
      }
    }
    splitGroups.removeWhere((_, v) => v.isEmpty);

    return RepaintBoundary(
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) => true,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) => true,
          child: Listener(
            onPointerSignal: (PointerSignalEvent event) {
              if (event is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(
                  event,
                  (PointerSignalEvent e) {},
                );
              }
            },
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _RostersViewState._wash(columnColor),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(11),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: _RostersViewState._line(columnColor),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.displayTitle.toUpperCase(),
                                  style: TextStyle(
                                    color: AppTheme.onTint(columnColor),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.isIsolatedTitle)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _RostersViewState._wash(columnColor),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: _RostersViewState._line(
                                        columnColor,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'TITLE',
                                    style: TextStyle(
                                      color: AppTheme.onTint(columnColor),
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${members.length} staff',
                            style: TextStyle(
                              color: AppTheme.onTint(columnColor),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Subheader
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'Shifts/Day:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _RosterNeedHoverAdjuster(
                                  key: ValueKey(
                                    'roster_need_adjuster_$savePos',
                                  ),
                                  storeId: widget.storeId,
                                  savePos: savePos,
                                  count: dailyShiftsNeeded,
                                  color: columnColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '(=$weeklyShiftsNeeded/wk)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildCoverageBanner(context, staffing),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  // List of members
                  Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      child: ListView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.all(16),
                        children: [
                          ...splitGroups.entries.map((e) {
                            final titleName = e.key;
                            final groupMembers = e.value;

                            Color groupColor = columnColor;
                            if (storeSettings != null) {
                              final tConfig =
                                  storeSettings.titles
                                      .where((t) => t.name == titleName)
                                      .firstOrNull ??
                                  storeSettings.tags
                                      .where((t) => t.name == titleName)
                                      .firstOrNull;
                              if (tConfig != null) {
                                groupColor = AppTheme.getColorFromName(
                                  tConfig.color,
                                );
                              }
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _RostersViewState._line(groupColor),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _RostersViewState._wash(
                                        groupColor,
                                      ),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(7),
                                      ),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: _RostersViewState._line(
                                            groupColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '${titleName.toUpperCase()} (${groupMembers.length})',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.onTint(groupColor),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      8,
                                      0,
                                    ),
                                    child: Column(
                                      children: groupMembers
                                          .map(
                                            (u) => Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8.0,
                                              ),
                                              child: _buildMemberTile(
                                                context,
                                                u,
                                                storeSettings,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          ...regularMembers.map(
                            (u) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildMemberTile(
                                context,
                                u,
                                storeSettings,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberTile(
    BuildContext context,
    UserModel user,
    StoreSettingsModel? storeSettings,
  ) {
    Color titleColor = AppTheme.primaryRed;
    if (storeSettings != null && user.title != null) {
      TitleConfig? titleConfig = storeSettings.titles
          .where((t) => t.name == user.title)
          .firstOrNull;
      titleConfig ??= storeSettings.tags
          .where((t) => t.name == user.title)
          .firstOrNull;
      if (titleConfig != null) {
        titleColor = AppTheme.getColorFromName(titleConfig.color);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _RostersViewState._wash(titleColor),
          Theme.of(context).scaffoldBackgroundColor,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _RostersViewState._line(titleColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: _HoverableMemberName(
              name: '${user.firstName} ${user.lastName}',
              onTap: () {
                if (user.id != null) {
                  context.go('/member/${user.id}?from=/rosters');
                }
              },
            ),
          ),
          _ShiftCountHoverAdjuster(user: user),
        ],
      ),
    );
  }
}

class _RosterNeedHoverAdjuster extends ConsumerStatefulWidget {
  final String storeId;
  final String savePos;
  final int count;
  final Color color;

  const _RosterNeedHoverAdjuster({
    super.key,
    required this.storeId,
    required this.savePos,
    required this.count,
    required this.color,
  });

  @override
  ConsumerState<_RosterNeedHoverAdjuster> createState() =>
      _RosterNeedHoverAdjusterState();
}

class _RosterNeedHoverAdjusterState
    extends ConsumerState<_RosterNeedHoverAdjuster> {
  bool _isHovered = false;
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = widget.count;
  }

  @override
  void didUpdateWidget(covariant _RosterNeedHoverAdjuster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count) {
      _count = widget.count;
    }
  }

  Future<void> _adjust(int delta) async {
    final newCount = (_count + delta).clamp(0, 999);
    if (newCount == _count) return;
    setState(() => _count = newCount);
    try {
      final firestoreService = ref.read(baseFirestoreServiceProvider);
      await firestoreService.updateRosterNeeds(
        widget.storeId,
        widget.savePos,
        newCount,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _count = widget.count);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$_count',
            key: ValueKey('roster_need_count_${widget.savePos}'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: widget.color,
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
                          size: 14,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      InkWell(
                        onTap: _count > 0 ? () => _adjust(-1) : null,
                        borderRadius: BorderRadius.circular(2),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 14,
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
    );
  }
}

class _ShiftCountHoverAdjuster extends ConsumerStatefulWidget {
  final UserModel user;
  const _ShiftCountHoverAdjuster({required this.user});

  @override
  ConsumerState<_ShiftCountHoverAdjuster> createState() =>
      _ShiftCountHoverAdjusterState();
}

class _ShiftCountHoverAdjusterState
    extends ConsumerState<_ShiftCountHoverAdjuster> {
  bool _isHovered = false;
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = int.tryParse(widget.user.avgShifts ?? '0') ?? 0;
  }

  @override
  void didUpdateWidget(covariant _ShiftCountHoverAdjuster oldWidget) {
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$_count',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
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
                          size: 14,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      InkWell(
                        onTap: _count > 0 ? () => _adjust(-1) : null,
                        borderRadius: BorderRadius.circular(2),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 14,
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
    );
  }
}

class _HoverableMemberName extends StatefulWidget {
  final String name;
  final VoidCallback onTap;

  const _HoverableMemberName({required this.name, required this.onTap});

  @override
  State<_HoverableMemberName> createState() => _HoverableMemberNameState();
}

class _HoverableMemberNameState extends State<_HoverableMemberName> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: theme.textTheme.bodyLarge?.color,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.centerLeft,
          child: Text(
            widget.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: defaultStyle.copyWith(
              color: _hovered ? theme.colorScheme.primary : defaultStyle.color,
              decoration: _hovered
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfigSectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;

  _ConfigSectionHeaderDelegate({required this.title});

  @override
  double get minExtent => 48.0;

  @override
  double get maxExtent => 48.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return Container(
      height: 48.0,
      color: theme.scaffoldBackgroundColor,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: theme.textTheme.bodyLarge?.color,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ConfigSectionHeaderDelegate oldDelegate) {
    return oldDelegate.title != title;
  }
}

CustomRosterItem _moved(CustomRosterItem i, {String? id, double dy = 0}) =>
    CustomRosterItem(
      id: id ?? i.id,
      x: i.x,
      y: i.y + dy,
      width: i.width,
      height: i.height,
      splitTitles: i.splitTitles,
    );

/// A store's own roster with anything that doesn't belong on it taken off:
/// other stores' tiles, the store's name in front of a title (that's how
/// All Stores names tiles) and repeats of the same tile.
@visibleForTesting
List<CustomRosterItem> cleanStoreRosterBoard(
  String storeId,
  String storeName,
  List<CustomRosterItem> items,
) {
  final seen = <String>{};
  return [
    for (final i in items)
      if (i.id.startsWith('$storeId|') &&
          seen.add(_RostersViewState._tileIdentity(i.id)))
        _moved(i, id: _RostersViewState._storeId(i.id, storeName)),
  ];
}

/// The All Stores board: each store's own roster, exactly as laid out, one
/// store below the other (first store at the top), with the store's name in
/// front of its tile titles. Also gives how far down each store starts.
@visibleForTesting
({List<CustomRosterItem> items, Map<String, double> offsets})
composeAllStoresBoard(
  List<({String id, String name, List<CustomRosterItem> board})> stores,
) {
  final items = <CustomRosterItem>[];
  final offsets = <String, double>{};
  var top = 0.0;
  for (final s in stores) {
    final board = cleanStoreRosterBoard(s.id, s.name, s.board);
    offsets[s.id] = top;
    for (final i in board) {
      items.add(
        _moved(i, id: _RostersViewState._allStoresId(i.id, s.name), dy: top),
      );
    }
    if (board.isNotEmpty) {
      top += board.map((i) => i.y + i.height).reduce(max);
    }
  }
  return (items: items, offsets: offsets);
}

/// The All Stores board split back into each store's own roster (the
/// reverse of [composeAllStoresBoard]).
@visibleForTesting
Map<String, List<CustomRosterItem>> splitAllStoresBoard(
  List<CustomRosterItem> items,
  Map<String, String> storeNames,
  Map<String, double> offsets,
) => {
  for (final sid in storeNames.keys)
    sid: cleanStoreRosterBoard(sid, storeNames[sid]!, [
      for (final i in items)
        if (i.id.startsWith('$sid|'))
          _moved(i, dy: -min(i.y, offsets[sid] ?? 0)),
    ]),
};
