import 'dart:math';
import '../models/store_settings_model.dart';
import '../models/user_model.dart';

/// Staffing for one roster tile (group).
class PositionStaffingResult {
  final String key;
  final String storeId;
  final String displayName;
  final int dailyShiftsNeeded;

  /// dailyShiftsNeeded × 6.
  final int weeklyShiftsNeeded;

  /// Sum of the members' average shifts per week.
  final double shiftsCovered;

  /// Shifts per week short of what's needed (0 when covered).
  final double shiftDeficit;

  /// Shifts per week over what's needed (0 when short).
  final double shiftSurplus;

  /// Deficit ÷ the group's average shifts per person, rounded up.
  final int hiresNeeded;

  /// Surplus ÷ the group's average shifts per person, rounded down: how many
  /// people more than needed. Never subtracted from anyone's hires.
  final int surplusPeople;

  final double avgShiftsPerMember;
  final int memberCount;

  const PositionStaffingResult({
    required this.key,
    required this.storeId,
    required this.displayName,
    required this.dailyShiftsNeeded,
    required this.weeklyShiftsNeeded,
    required this.shiftsCovered,
    required this.shiftDeficit,
    this.shiftSurplus = 0,
    required this.hiresNeeded,
    this.surplusPeople = 0,
    this.avgShiftsPerMember = 0.0,
    this.memberCount = 0,
  });
}

/// Totals across roster groups: each is a plain sum of the groups. Surpluses
/// are never netted against shortages.
class StaffingTotals {
  final int hiresNeeded;
  final int weeklyShiftsNeeded;
  final double shiftDeficit;

  const StaffingTotals({
    required this.hiresNeeded,
    required this.weeklyShiftsNeeded,
    required this.shiftDeficit,
  });

  factory StaffingTotals.of(Iterable<PositionStaffingResult> results) {
    var hires = 0;
    var weekly = 0;
    var deficit = 0.0;
    for (final r in results) {
      hires += r.hiresNeeded;
      weekly += r.weeklyShiftsNeeded;
      deficit += r.shiftDeficit;
    }
    return StaffingTotals(
      hiresNeeded: hires,
      weeklyShiftsNeeded: weekly,
      shiftDeficit: deficit,
    );
  }
}

class StaffingCalculator {
  /// Shifts per person used when a short group has nobody in it yet (or
  /// nobody with any shifts) to average from.
  static const double fallbackAvgShifts = 4.0;

  /// A member's average shifts per week ("4", "4.5"); 0 if blank or invalid.
  static double avgShiftsOf(UserModel m) =>
      double.tryParse((m.avgShifts ?? '').trim()) ?? 0;

  /// Sums the average shifts per week across all provided team members.
  static double calculateCoveredShifts(Iterable<UserModel> members) {
    var total = 0.0;
    for (final m in members) {
      total += avgShiftsOf(m);
    }
    return total;
  }

  /// Shifts as a short label: whole numbers without ".0", else one decimal.
  static String formatShifts(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Staffing for one roster group:
  /// * weekly needed = daily needed × 6
  /// * covered = sum of the members' average shifts per week
  /// * average = covered ÷ number of members
  /// * short → hires = shortage ÷ average, rounded up (so at least 1)
  /// * over → surplus people = extra ÷ average, rounded down
  static PositionStaffingResult evaluateGroup({
    required String key,
    required String storeId,
    required String displayName,
    required int dailyShiftsNeeded,
    required List<UserModel> members,
  }) {
    final weekly = dailyShiftsNeeded * 6;
    final covered = calculateCoveredShifts(members);
    final avg = members.isNotEmpty ? covered / members.length : 0.0;
    final perPerson = avg > 0 ? avg : fallbackAvgShifts;

    var deficit = 0.0;
    var surplus = 0.0;
    var hires = 0;
    var surplusPeople = 0;
    if (weekly > 0) {
      if (covered < weekly) {
        deficit = weekly - covered;
        hires = (deficit / perPerson - 1e-9).ceil();
      } else if (covered > weekly) {
        surplus = covered - weekly;
        surplusPeople = (surplus / perPerson + 1e-9).floor();
      }
    }

    return PositionStaffingResult(
      key: key,
      storeId: storeId,
      displayName: displayName,
      dailyShiftsNeeded: dailyShiftsNeeded,
      weeklyShiftsNeeded: weekly,
      shiftsCovered: covered,
      shiftDeficit: deficit,
      shiftSurplus: surplus,
      hiresNeeded: hires,
      surplusPeople: surplusPeople,
      avgShiftsPerMember: avg,
      memberCount: members.length,
    );
  }

  /// Hires needed for one roster group (see [evaluateGroup]).
  static int calculateHiresNeeded({
    required int dailyShiftsNeeded,
    required List<UserModel> members,
  }) => evaluateGroup(
    key: '',
    storeId: '',
    displayName: '',
    dailyShiftsNeeded: dailyShiftsNeeded,
    members: members,
  ).hiresNeeded;

  /// The roster_needs key for a tile id ("sid|title|pos|isolated|wt").
  static String needsKeyForTile(String tileKey) {
    final p = tileKey.split('|');
    final sid = p[0];
    final rawPos = p.length > 2 ? p[2] : '';
    final wt = p.length > 4 ? p[4] : '';
    return (wt.isNotEmpty && wt != 'Other')
        ? '${sid}_${rawPos}_$wt'
        : '${sid}_$rawPos';
  }

  /// Helper to get active working times for a store (omitting 'Other' and 'Unassigned').
  static List<String> getWorkingTimesForStore(
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

  /// The tiles a store's roster shows before its layout has been customized:
  /// every position (per working time) plus each isolated title / tag.
  static List<String> defaultRosterKeys({
    required String storeId,
    required String storeName,
    required StoreSettingsModel? settings,
    required List<String> workingTimes,
    required bool showStoreName,
  }) {
    if (settings == null) return [];
    String title(String t) => showStoreName ? '$storeName - $t' : t;
    final keys = <String>[];
    final isolated = [
      ...settings.titles.where((t) => t.isolatedRoster),
      ...settings.tags.where((t) => t.isolatedRoster),
    ];
    if (workingTimes.isNotEmpty) {
      for (final wt in workingTimes) {
        for (final pos in settings.positions) {
          keys.add('$storeId|${title('$wt - $pos')}|$pos|false|$wt');
        }
      }
      for (final t in isolated) {
        keys.add('$storeId|${title(t.name)}|${t.name}|true|Other');
      }
    } else {
      for (final pos in settings.positions) {
        keys.add('$storeId|${title(pos)}|$pos|false');
      }
      for (final t in isolated) {
        keys.add('$storeId|${title(t.name)}|${t.name}|true');
      }
    }
    return keys.toSet().toList();
  }

  /// Who appears in which roster tile. [tileKeys] are the tile ids
  /// ("sid|title|pos|isolated|wt") on the roster. This is the one place that
  /// decides it, so the roster page and every hires total agree.
  static Map<String, List<UserModel>> groupRosterMembers({
    required List<String> tileKeys,
    required List<UserModel> users,
    required Map<String, StoreSettingsModel> storeSettingsMap,
  }) {
    final Map<String, List<UserModel>> positionGroups = {
      for (final k in tileKeys) k: [],
    };

    bool isTileIsolated(String key) {
      final p = key.split('|');
      if (p.length > 3 && p[3] == 'true') return true;
      final sid = p[0];
      final rawPos = p[2].trim().toLowerCase();
      // A time-of-day Trainer tile carries its own Shared / Isolated choice
      // (picked when it was added). A Shared one keeps trainers in their
      // normal time-of-day position tile too, even if the Trainer title or
      // tag is set to isolated.
      final wt = p.length > 4 ? p[4].trim() : '';
      if (rawPos == 'trainer' && wt.isNotEmpty && wt != 'Other') return false;
      final settings = storeSettingsMap[sid];
      if (settings != null) {
        final isStandardPos = settings.positions.any(
          (pos) => pos.trim().toLowerCase() == rawPos,
        );
        if (!isStandardPos) {
          final tConfig =
              settings.titles
                  .where((t) => t.name.trim().toLowerCase() == rawPos)
                  .firstOrNull ??
              settings.tags
                  .where((t) => t.name.trim().toLowerCase() == rawPos)
                  .firstOrNull;
          if (tConfig?.isolatedRoster == true) return true;
        }
      }
      return false;
    }

    final keysByStore = <String, List<String>>{};
    for (final k in tileKeys) {
      keysByStore.putIfAbsent(k.split('|')[0], () => []).add(k);
    }

    for (final user in users) {
      final sid = user.store ?? 'unknown';
      final activeKeys = keysByStore[sid] ?? const <String>[];
      if (activeKeys.isEmpty) continue;

      final List<String> matchedSpecialKeys = [];

      // 1. Title match
      if (user.title != null && user.title!.trim().isNotEmpty) {
        final userTitle = user.title!.trim().toLowerCase();
        for (final k in activeKeys) {
          final p = k.split('|');
          if (p[2].trim().toLowerCase() == userTitle &&
              p[2].trim().toLowerCase() != 'trainer') {
            if (!matchedSpecialKeys.contains(k)) {
              matchedSpecialKeys.add(k);
            }
          }
        }
      }

      // 2. Trainer match
      final isTrainer =
          (user.title?.trim().toLowerCase() == 'trainer') ||
          ((user.additionalTags ?? []).any(
            (t) => t.trim().toLowerCase() == 'trainer',
          )) ||
          ((user.position ?? '').trim().toLowerCase() == 'trainer');
      if (isTrainer) {
        final userWt = (user.workingTime ?? '').trim().toLowerCase();
        for (final k in activeKeys) {
          final p = k.split('|');
          if (p[2].trim().toLowerCase() == 'trainer') {
            final wt = p.length > 4 ? p[4].trim().toLowerCase() : '';
            if (wt.isNotEmpty && wt != 'other') {
              if (wt == userWt) {
                if (!matchedSpecialKeys.contains(k)) {
                  matchedSpecialKeys.add(k);
                }
              }
            } else {
              if (!matchedSpecialKeys.contains(k)) {
                matchedSpecialKeys.add(k);
              }
            }
          }
        }
      }

      // 3. Tag match
      if ((user.additionalTags ?? []).isNotEmpty) {
        for (final tag in user.additionalTags!) {
          final tagName = tag.trim().toLowerCase();
          if (tagName == 'trainer') continue;
          for (final k in activeKeys) {
            final p = k.split('|');
            if (p[2].trim().toLowerCase() == tagName) {
              if (!matchedSpecialKeys.contains(k)) {
                matchedSpecialKeys.add(k);
              }
            }
          }
        }
      }

      // 4. Universal Isolation Check:
      // If ANY matched special tile is isolated, user appears ONLY in matched isolated tiles.
      // They do NOT appear in non-isolated special tiles (e.g. time-of-day trainer tiles)
      // or standard general positions.
      final isolatedSpecialKeys = matchedSpecialKeys
          .where((k) => isTileIsolated(k))
          .toList();

      if (isolatedSpecialKeys.isNotEmpty) {
        for (final isoKey in isolatedSpecialKeys) {
          positionGroups.putIfAbsent(isoKey, () => []).add(user);
        }
      } else {
        // No isolated tiles matched:
        // User appears in all matched special tiles (e.g. time-of-day trainer, shared tags)
        for (final specialKey in matchedSpecialKeys) {
          positionGroups.putIfAbsent(specialKey, () => []).add(user);
        }

        // And user also appears in their standard position tile (e.g. Cook Day)
        final userPos = (user.position ?? 'Unassigned').trim();
        final userWt = (user.workingTime ?? '').trim();
        String? targetStandardKey = activeKeys.where((k) {
          if (isTileIsolated(k)) return false;
          final p = k.split('|');
          if (p[2].trim().toLowerCase() == 'trainer') return false;
          if (p[2].trim().toLowerCase() != userPos.toLowerCase()) {
            return false;
          }
          final wt = p.length > 4 ? p[4] : '';
          if (wt.isNotEmpty && wt != 'Other') {
            return wt.toLowerCase() == userWt.toLowerCase();
          }
          return true;
        }).firstOrNull;

        targetStandardKey ??= activeKeys.where((k) {
          if (isTileIsolated(k)) return false;
          final p = k.split('|');
          if (p[2].trim().toLowerCase() == 'trainer') return false;
          return p[2].trim().toLowerCase() == userPos.toLowerCase();
        }).firstOrNull;

        if (targetStandardKey == null && matchedSpecialKeys.isEmpty) {
          targetStandardKey =
              activeKeys.where((k) {
                if (isTileIsolated(k)) return false;
                final p = k.split('|');
                return p.length > 3 &&
                    p[3] == 'false' &&
                    p[2].trim().toLowerCase() != 'trainer';
              }).firstOrNull ??
              activeKeys.firstOrNull;
        }

        if (targetStandardKey != null) {
          positionGroups.putIfAbsent(targetStandardKey, () => []).add(user);
        }
      }
    }
    return positionGroups;
  }

  /// Tile ids from a saved roster layout (items are maps or roster items).
  static List<String> layoutTileKeys(List<dynamic> layoutItems) => [
    for (final item in layoutItems)
      if (((item is Map) ? item['id'] : item.id) case final String id
          when id.isNotEmpty)
        id,
  ];

  /// Staffing for every roster group in the visible stores. Each store is
  /// worked out on its own, from its own roster ([layoutsByStore][storeId],
  /// or its default tiles if it hasn't been customized), so the All Stores
  /// totals are exactly the sum of each store's totals.
  static List<PositionStaffingResult> calculateAllDeficits({
    required List<UserModel> users,
    required Map<String, dynamic> rosterNeeds,
    required List<Map<String, dynamic>> stores,
    required Map<String, StoreSettingsModel> storeSettingsMap,
    String? currentStoreId,
    List<String>? ownedStoresList,
    Map<String, List<dynamic>?> layoutsByStore = const {},
  }) {
    final List<PositionStaffingResult> results = [];
    final activeStores = stores.where((s) {
      final sid = s['id'] as String;
      if (ownedStoresList != null &&
          ownedStoresList.isNotEmpty &&
          !ownedStoresList.contains(sid)) {
        return false;
      }
      if (currentStoreId != null && sid != currentStoreId) {
        return false;
      }
      return true;
    }).toList();

    for (final store in activeStores) {
      final sid = store['id'] as String;
      final storeName = (store['name'] as String?) ?? sid;
      final settings = storeSettingsMap[sid];
      final storeUsers = users.where((u) => u.store == sid).toList();

      final saved = layoutsByStore[sid];
      // This store's tiles, each once (a roster saved wrongly could have the
      // same tile twice, which would count its shortage twice).
      final seenTiles = <String>{};
      var tileKeys = saved == null
          ? <String>[]
          : layoutTileKeys(saved).where((k) {
              if (!k.startsWith('$sid|')) return false;
              final p = k.split('|');
              final wt = p.length > 4 ? p[4] : '';
              return seenTiles.add(
                '${p[0]}|${p.length > 2 ? p[2].trim().toLowerCase() : k}|$wt',
              );
            }).toList();
      if (tileKeys.isEmpty) {
        tileKeys = defaultRosterKeys(
          storeId: sid,
          storeName: storeName,
          settings: settings,
          workingTimes: getWorkingTimesForStore(settings, storeUsers),
          showStoreName: currentStoreId == null,
        );
      }

      final groups = groupRosterMembers(
        tileKeys: tileKeys,
        users: storeUsers,
        storeSettingsMap: storeSettingsMap,
      );

      for (final entry in groups.entries) {
        final needsKey = needsKeyForTile(entry.key);
        final parts = entry.key.split('|');
        var displayName = parts.length > 1 ? parts[1] : entry.key;
        if (currentStoreId == null && !displayName.startsWith(storeName)) {
          displayName = '$storeName - $displayName';
        }
        results.add(
          evaluateGroup(
            key: needsKey,
            storeId: sid,
            displayName: displayName,
            dailyShiftsNeeded: max(
              0,
              (rosterNeeds[needsKey] as num?)?.toInt() ?? 0,
            ),
            members: entry.value,
          ),
        );
      }
    }

    return results;
  }
}
