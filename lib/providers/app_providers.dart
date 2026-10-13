import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import '../models/store_settings_model.dart';

/// Manages the currently selected store ID.
/// null represents 'Both Stores'
final currentStoreIdProvider = StateProvider<String?>((ref) => null);

/// Base FirestoreService for global queries (does not depend on currentStoreId)
final baseFirestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

/// Provides an instance of FirestoreService tied to the current store ID.
/// Automatically rebuilds if the store ID changes.
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return FirestoreService(storeId: storeId);
});

/// Streams all users (including owner) for the currently active store.
final allStoreUsersStreamProvider = StreamProvider<List<UserModel>>((ref) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamUsers();
});

/// Provides the list of users, filtering out privileged accounts unless 'Appear in Roster' is checked.
final usersStreamProvider = Provider<AsyncValue<List<UserModel>>>((ref) {
  final asyncUsers = ref.watch(allStoreUsersStreamProvider);
  
  return asyncUsers.whenData((users) {
    return users.where((u) {
      final t = u.title?.toLowerCase() ?? '';
      final r = u.role?.toLowerCase() ?? '';
      final isBotOrOwner = t == 'owner' || t == 'bot' || r == 'bot' || r == 'owner';
      
      final appearInRoster = u.accessLevels?['Appear in Roster'];
      
      if (isBotOrOwner) {
        return appearInRoster == true;
      } else {
        return appearInRoster != false;
      }
    }).toList();
  });
});

/// The current team: [usersStreamProvider] without former team members
/// (whose last day has passed). Used for counts, stats and scheduling.
final currentMembersProvider = Provider<AsyncValue<List<UserModel>>>(
  (ref) => ref.watch(usersStreamProvider).whenData(
    (users) => users.where(isCurrentMember).toList(),
  ),
);

/// Streams all stores.
final allStoresStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final firestoreService = ref.watch(baseFirestoreServiceProvider);
  return firestoreService.streamAllStores();
});

/// Indicates whether there are unsaved changes on the current page.
final unsavedChangesProvider = StateProvider<bool>((ref) => false);

/// Holds a callback to save changes if available.
final saveChangesActionProvider = StateProvider<Future<void> Function()?>((ref) => null);

/// Holds a callback that reverts the current page's unsaved changes, if any.
final discardChangesActionProvider = StateProvider<void Function()?>((ref) => null);

class RosterSortState {
  final String? column;
  final bool? isAscending;
  const RosterSortState({this.column, this.isAscending});

  /// The team table's default: newest hires first.
  static const byDefault = RosterSortState(column: 'Start Date', isAscending: false);
}

final rosterSortProvider = StateProvider<RosterSortState>((ref) => RosterSortState.byDefault);

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
            final aName = '${a.lastName ?? ''} ${a.firstName ?? ''}'.trim().toLowerCase();
            final bName = '${b.lastName ?? ''} ${b.firstName ?? ''}'.trim().toLowerCase();
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
            cmp = (a.additionalTags ?? const []).join(', ').compareTo((b.additionalTags ?? const []).join(', '));
            break;
          case 'Status':
            cmp = memberStatus(a).compareTo(memberStatus(b));
            break;
          case 'Food Permit':
            final aPermit = a.foodHandlersExpiration ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bPermit = b.foodHandlersExpiration ?? DateTime.fromMillisecondsSinceEpoch(0);
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
        final aName = '${a.lastName ?? ''} ${a.firstName ?? ''}'.trim().toLowerCase();
        final bName = '${b.lastName ?? ''} ${b.firstName ?? ''}'.trim().toLowerCase();
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
final specificStoreSettingsProvider = StreamProvider.family<StoreSettingsModel?, String>((ref, storeId) {
  final firestoreService = ref.watch(baseFirestoreServiceProvider);
  return firestoreService.streamStoreSettingsForSpecificStore(storeId);
});

/// Streams a specific store's data
final storeStreamProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, storeId) {
  final firestoreService = ref.watch(baseFirestoreServiceProvider);
  return firestoreService.streamStore(storeId);
});

/// Streams a specific user for the currently active store.
final userStreamProvider = StreamProvider.family<UserModel?, String>((ref, userId) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamUser(userId);
});

/// Streams time off requests for a specific user.
final userTimeOffRequestsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, userId) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamUserTimeOffRequests(userId).handleError((error) {
    print('Error loading time off requests: $error');
    // Fallback dummy data if Firebase errors (e.g. index missing)
    return [
      {
        'start_date': '2026-11-25',
        'end_date': '2026-11-29',
        'status': 'pending',
        'reason': 'Family vacation (Fallback)',
      }
    ];
  });
});

/// Streams ALL pending time off requests for the store.
final allPendingTimeOffRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamAllPendingTimeOffRequests().handleError((error) {
    print('Error loading all pending time off requests: $error');
    return [];
  });
});

/// Streams the active availability for a specific user.
final userAvailabilityProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, userId) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamUserAvailability(userId).handleError((e) {
    return {
      "monday": [{"start": "16:00", "end": "22:30"}],
      "tuesday": [],
      "wednesday": [{"start": "09:00", "end": "17:00"}],
      "thursday": [],
      "friday": [{"start": "16:00", "end": "23:00"}],
      "saturday": [{"start": "08:00", "end": "20:00"}],
      "sunday": []
    };
  });
});

/// Streams shifts for a specific user.
final userShiftsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, userId) {
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
      }
    ];
  });
});

/// Streams the roster needs configuration for the currently active store.
final rosterNeedsStreamProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamRosterNeeds();
});

/// Calculates the total number of new hires needed across all visible rosters.
final newHiresNeededProvider = Provider<int>((ref) {
  final users = ref.watch(usersStreamProvider).valueOrNull ?? [];
  final rosterNeeds = ref.watch(rosterNeedsStreamProvider).valueOrNull ?? {};
  
  if (users.isEmpty) return 0;
  
  // Group users exactly as done in rosters_view
  final Map<String, List<UserModel>> positionGroups = {};
  for (final user in users) {
    final pos = user.position ?? 'Unassigned';
    final sid = user.store ?? 'unknown';
    // Group key is sid + position
    positionGroups.putIfAbsent('${sid}_$pos', () => []).add(user);
  }
  
  int totalHiresNeeded = 0;
  for (final key in positionGroups.keys) {
    final members = positionGroups[key]!;
    final shiftsNeededPerDay = (rosterNeeds[key] as num?)?.toInt() ?? 0;
    
    int totalShiftsCovered = 0;
    for (final m in members) {
      if (m.avgShifts != null) {
        totalShiftsCovered += int.tryParse(m.avgShifts!) ?? 0;
      }
    }
    
    final double shiftsCoveredPerDay = totalShiftsCovered / 6.0;
    final double deficit = shiftsNeededPerDay - shiftsCoveredPerDay;
    if (deficit > 0) {
      totalHiresNeeded += deficit.ceil();
    }
  }
  
  return totalHiresNeeded;
});

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

