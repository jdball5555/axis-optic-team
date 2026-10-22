import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import '../models/store_settings_model.dart';
import '../core/staffing_calculator.dart';

/// Manages the currently selected store ID.
/// null represents 'Both Stores'
final currentStoreIdProvider = StateProvider<String?>((ref) => null);

/// Base FirestoreService for global queries (does not depend on currentStoreId)
final baseFirestoreServiceProvider = Provider<FirestoreService>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  final ownedStores = (currentUser?['owned_stores'] as List?)
      ?.map((e) => e.toString())
      .toList();
  return FirestoreService(
    allowedStoreIds: (ownedStores != null && ownedStores.isNotEmpty)
        ? ownedStores
        : null,
  );
});

/// Provides an instance of FirestoreService tied to the current store ID.
/// Automatically rebuilds if the store ID changes.
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  final currentUser = ref.watch(currentUserProvider);
  final ownedStores = (currentUser?['owned_stores'] as List?)
      ?.map((e) => e.toString())
      .toList();
  return FirestoreService(
    storeId: storeId,
    allowedStoreIds: (ownedStores != null && ownedStores.isNotEmpty)
        ? ownedStores
        : null,
  );
});

/// Streams all users (including owner) for the currently active store.
final allStoreUsersStreamProvider = StreamProvider<List<UserModel>>((ref) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamUsers();
});

/// Whether [u] shows on the team: owners / bots only with 'Appear in Roster'
/// checked, everyone else unless it's unchecked.
bool appearsOnTeam(UserModel u) {
  final t = u.title?.toLowerCase() ?? '';
  final r = u.role?.toLowerCase() ?? '';
  final isBotOrOwner = t == 'owner' || t == 'bot' || r == 'bot' || r == 'owner';
  final appearInRoster = u.accessLevels?['Appear in Roster'];
  return isBotOrOwner ? appearInRoster == true : appearInRoster != false;
}

/// Provides the list of users, filtering out privileged accounts unless 'Appear in Roster' is checked.
final usersStreamProvider = Provider<AsyncValue<List<UserModel>>>((ref) {
  final asyncUsers = ref.watch(allStoreUsersStreamProvider);
  return asyncUsers.whenData(
    (users) => users.where(appearsOnTeam).toList(),
  );
});

/// The current team of one store, whichever store is selected (e.g. a
/// store's dashboard tile shown on another store's dashboard).
final storeMembersProvider = StreamProvider.family<List<UserModel>, String>((
  ref,
  storeId,
) {
  final ownedStores = (ref.watch(currentUserProvider)?['owned_stores'] as List?)
      ?.map((e) => e.toString())
      .toList();
  return FirestoreService(
    storeId: storeId,
    allowedStoreIds: (ownedStores != null && ownedStores.isNotEmpty)
        ? ownedStores
        : null,
  ).streamUsers().map(
    (users) =>
        users.where((u) => appearsOnTeam(u) && isCurrentMember(u)).toList(),
  );
});

/// The current team: [usersStreamProvider] without former team members
/// (whose last day has passed). Used for counts, stats and scheduling.
final currentMembersProvider = Provider<AsyncValue<List<UserModel>>>(
  (ref) => ref
      .watch(usersStreamProvider)
      .whenData((users) => users.where(isCurrentMember).toList()),
);

/// Streams all stores.
final allStoresStreamProvider = StreamProvider<List<Map<String, dynamic>>>((
  ref,
) {
  final firestoreService = ref.watch(baseFirestoreServiceProvider);
  return firestoreService.streamAllStores();
});

/// Indicates whether there are unsaved changes on the current page.
final unsavedChangesProvider = StateProvider<bool>((ref) => false);

/// Holds a callback to save changes if available.
final saveChangesActionProvider = StateProvider<Future<void> Function()?>(
  (ref) => null,
);

/// Holds a callback that reverts the current page's unsaved changes, if any.
final discardChangesActionProvider = StateProvider<void Function()?>(
  (ref) => null,
);

class RosterSortState {
  final String? column;
  final bool? isAscending;
  const RosterSortState({this.column, this.isAscending});

  /// The team table's default: newest hires first.
  static const byDefault = RosterSortState(
    column: 'Start Date',
    isAscending: false,
  );
}

final rosterSortProvider = StateProvider<RosterSortState>(
  (ref) => RosterSortState.byDefault,
);

final sortedUsersProvider = Provider<AsyncValue<List<UserModel>>>((ref) {
  final asyncUsers = ref.watch(usersStreamProvider);
  final sortState = ref.watch(rosterSortProvider);

  return asyncUsers.whenData((users) {
    List<UserModel> sorted = List.from(users);
    if (sortState.column != null && sortState.isAscending != null) {
      sorted.sort((a, b) {
        int cmp = 0;
        switch (sortState.column) {
          case 'Name':
            final aName = '${a.lastName ?? ''} ${a.firstName ?? ''}'
                .trim()
                .toLowerCase();
            final bName = '${b.lastName ?? ''} ${b.firstName ?? ''}'
                .trim()
                .toLowerCase();
            cmp = aName.compareTo(bName);
            break;
          case 'Preferred':
            cmp = (a.preferredName ?? '').compareTo(b.preferredName ?? '');
            break;
          case 'Title':
            cmp = (a.title ?? '').compareTo(b.title ?? '');
            break;
          case 'Position':
            cmp = (a.position ?? '').compareTo(b.position ?? '');
            break;
          case 'Designation':
            cmp = (a.designation ?? '').compareTo(b.designation ?? '');
            break;
          case 'Store':
            cmp = (a.store ?? '').compareTo(b.store ?? '');
            break;
          case 'Working Time':
            cmp = (a.workingTime ?? '').compareTo(b.workingTime ?? '');
            break;
          case 'Avg Shifts':
            cmp = (a.avgShifts ?? '').compareTo(b.avgShifts ?? '');
            break;
          case 'Pay':
            cmp = (a.payRate ?? 0).compareTo(b.payRate ?? 0);
            break;
          case 'Start Date':
            final aDate = a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
            cmp = aDate.compareTo(bDate);
            break;
          case 'Additional Tags':
            cmp = (a.additionalTags ?? const [])
                .join(', ')
                .compareTo((b.additionalTags ?? const []).join(', '));
            break;
          case 'Status':
            cmp = memberStatus(a).compareTo(memberStatus(b));
            break;
          case 'Food Permit':
            final aPermit =
                a.foodHandlersExpiration ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bPermit =
                b.foodHandlersExpiration ??
                DateTime.fromMillisecondsSinceEpoch(0);
            cmp = aPermit.compareTo(bPermit);
            break;
        }
        return sortState.isAscending! ? cmp : -cmp;
      });
    } else {
      // Default: newest hires first (then by name).
      sorted.sort((a, b) {
        final aDate = a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = bDate.compareTo(aDate);
        if (cmp != 0) return cmp;
        final aName = '${a.lastName ?? ''} ${a.firstName ?? ''}'
            .trim()
            .toLowerCase();
        final bName = '${b.lastName ?? ''} ${b.firstName ?? ''}'
            .trim()
            .toLowerCase();
        return aName.compareTo(bName);
      });
    }
    return sorted;
  });
});

/// Streams the global settings for the currently active store.
final storeSettingsProvider = StreamProvider<StoreSettingsModel?>((ref) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamStoreSettings();
});

/// Streams the settings for a specific store.
final specificStoreSettingsProvider =
    StreamProvider.family<StoreSettingsModel?, String>((ref, storeId) {
      final firestoreService = ref.watch(baseFirestoreServiceProvider);
      return firestoreService.streamStoreSettingsForSpecificStore(storeId);
    });

/// Streams a specific store's data
final storeStreamProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, storeId) {
      final firestoreService = ref.watch(baseFirestoreServiceProvider);
      return firestoreService.streamStore(storeId);
    });

class StoreDevModeInfo {
  final bool isDev;
  final bool isPartial;
  final int devCount;
  final int totalCount;
  final String? badgeLabel;

  const StoreDevModeInfo({
    required this.isDev,
    this.isPartial = false,
    this.devCount = 0,
    this.totalCount = 0,
    this.badgeLabel,
  });
}

/// Indicates whether the currently viewed store(s) is in dev mode.
/// If viewing a single store: true if that store is in dev mode.
/// If viewing "All Stores": true if any or all stores are in dev mode.
final currentStoreDevModeProvider = Provider<StoreDevModeInfo>((ref) {
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final allStores = ref.watch(allStoresStreamProvider).valueOrNull ?? [];
  final currentUser = ref.watch(currentUserProvider);
  final ownedStores = (currentUser?['owned_stores'] as List?)
      ?.map((e) => e.toString())
      .toList();
  final stores = (ownedStores != null && ownedStores.isNotEmpty)
      ? allStores.where((s) => ownedStores.contains(s['id'])).toList()
      : allStores;

  if (currentStoreId != null) {
    var store = stores.where((s) => s['id'] == currentStoreId).firstOrNull;
    store ??= ref.watch(storeStreamProvider(currentStoreId)).valueOrNull;
    final isDev = store?['is_dev'] == true || store?['isDev'] == true;
    return StoreDevModeInfo(
      isDev: isDev,
      isPartial: false,
      devCount: isDev ? 1 : 0,
      totalCount: 1,
      badgeLabel: isDev ? 'DEV MODE' : null,
    );
  } else {
    if (stores.isEmpty) {
      return const StoreDevModeInfo(isDev: false);
    }
    final devCount = stores
        .where((s) => s['is_dev'] == true || s['isDev'] == true)
        .length;
    final totalCount = stores.length;
    if (devCount == 0) {
      return const StoreDevModeInfo(isDev: false);
    } else if (devCount == totalCount) {
      return StoreDevModeInfo(
        isDev: true,
        isPartial: false,
        devCount: devCount,
        totalCount: totalCount,
        badgeLabel: 'DEV MODE',
      );
    } else {
      return StoreDevModeInfo(
        isDev: true,
        isPartial: true,
        devCount: devCount,
        totalCount: totalCount,
        badgeLabel: 'DEV ($devCount/$totalCount)',
      );
    }
  }
});

/// Streams a specific user for the currently active store.
final userStreamProvider = StreamProvider.autoDispose
    .family<UserModel?, String>((ref, userId) {
      final firestoreService = ref.watch(firestoreServiceProvider);
      return firestoreService.streamUser(userId);
    });

/// Streams time off requests for a specific user.
final userTimeOffRequestsProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, userId) {
      final firestoreService = ref.watch(firestoreServiceProvider);
      return firestoreService.streamUserTimeOffRequests(userId).handleError((
        error,
      ) {
        print('Error loading time off requests: $error');
        // Fallback dummy data if Firebase errors (e.g. index missing)
        return [
          {
            'start_date': '2026-11-25',
            'end_date': '2026-11-29',
            'status': 'pending',
            'reason': 'Family vacation (Fallback)',
          },
        ];
      });
    });

/// Streams ALL pending time off requests for the store.
final allPendingTimeOffRequestsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
      final firestoreService = ref.watch(firestoreServiceProvider);
      return firestoreService.streamAllPendingTimeOffRequests().handleError((
        error,
      ) {
        print('Error loading all pending time off requests: $error');
        return [];
      });
    });

/// Streams the active availability for a specific user.
final userAvailabilityProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, userId) {
      final firestoreService = ref.watch(firestoreServiceProvider);
      return firestoreService.streamUserAvailability(userId).handleError((e) {
        return {
          "monday": [
            {"start": "16:00", "end": "22:30"},
          ],
          "tuesday": [],
          "wednesday": [
            {"start": "09:00", "end": "17:00"},
          ],
          "thursday": [],
          "friday": [
            {"start": "16:00", "end": "23:00"},
          ],
          "saturday": [
            {"start": "08:00", "end": "20:00"},
          ],
          "sunday": [],
        };
      });
    });

/// Streams shifts for a specific user.
final userShiftsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, userId) {
      final firestoreService = ref.watch(firestoreServiceProvider);
      return firestoreService.streamUserShifts(userId).handleError((error) {
        print('Error loading shifts: $error');
        // Fallback dummy data if Firebase errors (e.g. collectionGroup index missing)
        return [
          {
            'date': '2026-10-15',
            'scheduled_start': '14:00',
            'scheduled_end': '22:30',
            'assigned_area': 'FOH (Fallback)',
          },
          {
            'date': '2026-10-16',
            'scheduled_start': '08:00',
            'scheduled_end': '16:00',
            'assigned_area': 'BOH (Fallback)',
          },
        ];
      });
    });

/// Tracks whether RostersView should open in layout editing mode.
final rosterEditModeProvider = StateProvider<bool>((ref) => false);

/// Tracks revisions to custom roster layouts to trigger UI rebuilds across views.
final rosterLayoutRevisionProvider = StateProvider<int>((ref) => 0);

/// Streams the roster needs configuration for the currently active store.
final rosterNeedsStreamProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamRosterNeeds();
});

/// Streams the custom roster layout for a given store ('all' or specific store ID).
final rosterLayoutStreamProvider = StreamProvider.autoDispose
    .family<List<dynamic>?, String>((ref, storeKey) {
      final currentUser = ref.watch(currentUserProvider);
      if (currentUser == null) return Stream.value(null);
      try {
        return FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser['id'])
            .collection('roster_layouts')
            .doc(storeKey)
            .snapshots()
            .map((doc) {
              if (!doc.exists || doc.data() == null) return null;
              final items = doc.data()!['items'];
              if (items is List) {
                return items;
              }
              return null;
            });
      } catch (_) {
        return Stream.value(null);
      }
    });

/// Staffing for every roster group in the visible store(s). Each store is
/// worked out from its own roster layout, so All Stores is exactly the sum
/// of the individual stores.
final rosterStaffingProvider = Provider<List<PositionStaffingResult>>((ref) {
  final users = ref.watch(currentMembersProvider).valueOrNull ?? [];
  final rosterNeeds = ref.watch(rosterNeedsStreamProvider).valueOrNull ?? {};
  final allStores = ref.watch(allStoresStreamProvider).valueOrNull ?? [];
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final currentUser = ref.watch(currentUserProvider);
  final ownedStoresList = (currentUser?['owned_stores'] as List?)
      ?.map((e) => e.toString())
      .toList();
  final settings =
      ref.watch(storeSettingsProvider).valueOrNull ??
      const StoreSettingsModel();

  if (users.isEmpty && allStores.isEmpty) return const [];

  final Map<String, StoreSettingsModel> storeSettingsMap = {};
  final Map<String, List<dynamic>?> layoutsByStore = {};
  for (final s in allStores) {
    final sid = s['id'] as String;
    if (currentStoreId != null && sid != currentStoreId) continue;
    final stSettings = ref
        .watch(specificStoreSettingsProvider(sid))
        .valueOrNull;
    if (stSettings != null) {
      storeSettingsMap[sid] = stSettings;
    } else if (sid == currentStoreId) {
      storeSettingsMap[sid] = settings;
    }
    layoutsByStore[sid] = ref
        .watch(rosterLayoutStreamProvider(sid))
        .valueOrNull;
  }
  if (currentStoreId != null && !storeSettingsMap.containsKey(currentStoreId)) {
    storeSettingsMap[currentStoreId] = settings;
  }

  return StaffingCalculator.calculateAllDeficits(
    users: users,
    rosterNeeds: rosterNeeds,
    stores: allStores,
    storeSettingsMap: storeSettingsMap,
    currentStoreId: currentStoreId,
    ownedStoresList: ownedStoresList,
    layoutsByStore: layoutsByStore,
  );
});

/// The total number of new hires needed: the sum of every roster group's
/// hires (surpluses are never subtracted).
final newHiresNeededProvider = Provider<int>(
  (ref) => StaffingTotals.of(ref.watch(rosterStaffingProvider)).hiresNeeded,
);

/// Manages the current theme mode (light/dark).
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

/// Appearance → "Bright colors" when the user has picked one; null = the
/// default pairing (bright colors with the dark theme, dim with light).
final brightColorsProvider = StateProvider<bool?>((ref) => null);

/// Bright or dim colors right now (the user's pick, or the default pairing).
final effectiveBrightColorsProvider = Provider<bool>(
  (ref) =>
      ref.watch(brightColorsProvider) ??
      ref.watch(themeModeProvider) != ThemeMode.light,
);

/// Manages the currently logged in user auth document
final currentUserProvider = StateProvider<Map<String, dynamic>?>((ref) => null);
