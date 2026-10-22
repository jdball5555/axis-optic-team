import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import '../models/store_settings_model.dart';
import '../models/user_model.dart';
import 'sample_data.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String? storeId;
  final List<String>? allowedStoreIds;

  FirestoreService({this.storeId, this.allowedStoreIds});

  List<Map<String, dynamic>> _filterAllowedStores(
    List<Map<String, dynamic>> stores,
  ) {
    if (allowedStoreIds != null && allowedStoreIds!.isNotEmpty) {
      return stores.where((s) => allowedStoreIds!.contains(s['id'])).toList();
    }
    return stores;
  }

  bool get isStoreAllowed {
    if (storeId == null) return true;
    if (allowedStoreIds == null || allowedStoreIds!.isEmpty) return true;
    return allowedStoreIds!.contains(storeId);
  }

  Stream<Map<String, dynamic>?> streamStore(String sid) {
    if (allowedStoreIds != null &&
        allowedStoreIds!.isNotEmpty &&
        !allowedStoreIds!.contains(sid)) {
      return Stream.value(null);
    }
    return _db
        .collection('stores')
        .doc(sid)
        .snapshots()
        .map((doc) => doc.data());
  }

  Stream<List<Map<String, dynamic>>> streamAllStores() {
    return _db.collection('stores').snapshots().map((snapshot) {
      final list =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      return _filterAllowedStores(list);
    });
  }

  Future<void> updateStoreName(String sid, String name) async {
    await _db.collection('stores').doc(sid).set({
      'name': name,
    }, SetOptions(merge: true));
  }

  Future<void> setStoreDevMode(String sid, bool isDev) async {
    await _db.collection('stores').doc(sid).set({
      'is_dev': isDev,
    }, SetOptions(merge: true));
  }

  Future<String> createNewStore() async {
    final docRef = _db.collection('stores').doc();
    await docRef.set({'name': 'Untitled Store'});
    // Create initial settings for the store
    int _idCounter = 0;
    String _uniqueId(String name) =>
        '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}_$name';

    final defaultSettings = StoreSettingsModel(
      positions: ['SVC', 'DT', 'KT', 'TRAINER', 'DIR', 'SEA'],
      titles: [
        'In Training',
        'Team Member',
        'Trainer',
        'Leader',
        'Director',
      ].map((e) => TitleConfig(id: _uniqueId(e), name: e)).toList(),
      workingTimes: ['Daytime', 'Night', 'Unassigned'],
      tags: [
        'Minor',
        'Key Holder',
      ].map((e) => TitleConfig(id: _uniqueId(e), name: e)).toList(),
      designations: ['Adult', 'College', 'High School'],
      isScheduleEnabled: true,
      isShiftBoardEnabled: false,
    );
    await _db
        .collection('stores')
        .doc(docRef.id)
        .collection('settings')
        .doc('global_config')
        .set(defaultSettings.toJson());
    return docRef.id;
  }

  // --- STORE SETTINGS ---

  /// Fetches the global configuration for the store.
  Future<StoreSettingsModel?> getStoreSettings() async {
    try {
      final doc = await _db
          .collection('stores')
          .doc(storeId ?? 'QYfhsc0dBHLBbgOflHsA')
          .collection('settings')
          .doc('global_config')
          .get();

      if (doc.exists && doc.data() != null) {
        return StoreSettingsModel.fromJson(doc.data()!);
      }
      return null;
    } catch (e) {
      print('Error fetching store settings: $e');
      return null;
    }
  }

  /// Streams the global configuration for the store.
  Stream<StoreSettingsModel?> streamStoreSettings() {
    if (!isStoreAllowed) return Stream.value(null);
    if (storeId == null) {
      return streamAllStores().switchMap((allStores) {
        final stores = _filterAllowedStores(allStores);
        if (stores.isEmpty) return Stream.value(null);

        final streams = stores.map(
          (s) => streamStoreSettingsForSpecificStore(s['id'] as String),
        );
        return Rx.combineLatest(streams, (
          List<StoreSettingsModel?> settingsList,
        ) {
          final nonNullSettings = settingsList
              .whereType<StoreSettingsModel>()
              .toList();
          if (nonNullSettings.isEmpty) return null;

          List<TitleConfig> titles = [];
          List<TitleConfig> tags = [];
          List<String> workingTimes = [];
          List<String> positions = [];
          List<String> designations = [];
          bool scheduleEnabled = false;
          bool shiftEnabled = false;

          for (var s in nonNullSettings) {
            titles.addAll(s.titles);
            tags.addAll(s.tags);
            workingTimes.addAll(s.workingTimes);
            positions.addAll(s.positions);
            designations.addAll(s.designations);
            scheduleEnabled = scheduleEnabled || s.isScheduleEnabled;
            shiftEnabled = shiftEnabled || s.isShiftBoardEnabled;
          }

          return StoreSettingsModel(
            titles: {for (var t in titles) t.name: t}.values.toList(),
            tags: {for (var t in tags) t.name: t}.values.toList(),
            workingTimes: workingTimes.toSet().toList(),
            positions: positions.toSet().toList(),
            designations: designations.toSet().toList(),
            isScheduleEnabled: scheduleEnabled,
            isShiftBoardEnabled: shiftEnabled,
          );
        });
      });
    }
    return streamStoreSettingsForSpecificStore(storeId!);
  }

  Stream<StoreSettingsModel?> streamStoreSettingsForSpecificStore(String sid) {
    return _db
        .collection('stores')
        .doc(sid)
        .collection('settings')
        .doc('global_config')
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            return StoreSettingsModel.fromJson(doc.data()!);
          }
          return null;
        });
  }

  /// Updates the global configuration for the store.
  Future<void> updateStoreSettings(StoreSettingsModel settings) async {
    if (storeId == null)
      throw StateError(
        'Cannot update global store settings when both stores are selected.',
      );
    await updateStoreSettingsForSpecificStore(storeId!, settings);
  }

  Future<void> updateStoreSettingsForSpecificStore(
    String sid,
    StoreSettingsModel settings,
  ) async {
    try {
      await _db
          .collection('stores')
          .doc(sid)
          .collection('settings')
          .doc('global_config')
          .set(settings.toJson(), SetOptions(merge: true));
    } catch (e) {
      print('Error updating store settings: $e');
      rethrow;
    }
  }

  /// Streams the roster needs configuration for the store.
  Stream<Map<String, dynamic>> streamRosterNeeds() {
    if (!isStoreAllowed) return Stream.value({});
    if (storeId == null) {
      return streamAllStores().switchMap((allStores) {
        final stores = _filterAllowedStores(allStores);
        if (stores.isEmpty) return Stream.value({});
        final streams = stores.map(
          (s) => _streamRosterNeedsForStore(s['id'] as String),
        );
        return Rx.combineLatest(streams, (List<Map<String, dynamic>> maps) {
          final result = <String, dynamic>{};
          for (final map in maps) {
            result.addAll(map);
          }
          return result;
        });
      });
    }
    return _streamRosterNeedsForStore(storeId!);
  }

  Stream<Map<String, dynamic>> _streamRosterNeedsForStore(String sid) {
    return _db
        .collection('stores')
        .doc(sid)
        .collection('settings')
        .doc('roster_needs')
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data() ?? {};
          return data.map((key, value) => MapEntry('${sid}_$key', value));
        });
  }

  /// Updates the roster needs for a specific position.
  Future<void> updateRosterNeeds(
    String specificStoreId,
    String position,
    int shiftsNeeded,
  ) async {
    try {
      await _db
          .collection('stores')
          .doc(specificStoreId)
          .collection('settings')
          .doc('roster_needs')
          .set({position: shiftsNeeded}, SetOptions(merge: true));
    } catch (e) {
      print('Error updating roster needs: $e');
      rethrow;
    }
  }

  /// Returns a real-time stream of all team members in the store.
  Stream<List<UserModel>> streamUsers() {
    if (!isStoreAllowed) return Stream.value([]);
    if (storeId == null) {
      return streamAllStores().switchMap((allStores) {
        final stores = _filterAllowedStores(allStores);
        if (stores.isEmpty) return Stream.value([]);
        final streams = stores.map(
          (s) => _streamUsersForStore(s['id'] as String),
        );
        return Rx.combineLatest(streams, (List<List<UserModel>> lists) {
          final allUsers = lists.expand((x) => x).toList();
          final uniqueUsers = <String, UserModel>{};
          for (final u in allUsers) {
            uniqueUsers[u.id!] = u;
          }
          return uniqueUsers.values.toList();
        });
      });
    }
    return _streamUsersForStore(storeId!);
  }

  Stream<List<UserModel>> _streamUsersForStore(String sid) {
    final teamStream = _db
        .collection('stores')
        .doc(sid)
        .collection('users')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            if (data['store'] == null || data['store'].isEmpty) {
              data['store'] = sid;
            }
            return UserModel.fromJson(data);
          }).toList(),
        );

    final ownerStream = _db
        .collection('users')
        .where('owned_stores', arrayContains: sid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            data['store'] = sid; // For local display purposes
            data['title'] = 'Owner';
            return UserModel.fromJson(data);
          }).toList(),
        );

    return Rx.combineLatest2(teamStream, ownerStream, (
      List<UserModel> team,
      List<UserModel> owners,
    ) {
      final uniqueMap = <String, UserModel>{};
      for (final u in team) {
        uniqueMap[u.id!] = u;
      }
      for (final o in owners) {
        uniqueMap[o.id!] = o;
      }
      return uniqueMap.values.toList();
    });
  }

  Stream<UserModel?> streamUser(String userId) {
    if (!isStoreAllowed) return Stream.value(null);
    if (storeId == null) {
      return streamAllStores().switchMap((allStores) {
        final stores = _filterAllowedStores(allStores);
        if (stores.isEmpty) return Stream.value(null);
        final streams = stores.map(
          (s) => _streamUserForStore(s['id'] as String, userId),
        );
        return Rx.combineLatest(streams, (List<UserModel?> users) {
          return users.firstWhere((u) => u != null, orElse: () => null);
        });
      });
    }
    return _streamUserForStore(storeId!, userId);
  }

  Stream<UserModel?> _streamUserForStore(String sid, String userId) {
    final teamStream = _db
        .collection('stores')
        .doc(sid)
        .collection('users')
        .doc(userId)
        .snapshots();

    final globalStream = _db.collection('users').doc(userId).snapshots();

    return Rx.combineLatest2(teamStream, globalStream, (
      DocumentSnapshot<Map<String, dynamic>> teamDoc,
      DocumentSnapshot<Map<String, dynamic>> globalDoc,
    ) {
      if (teamDoc.exists && teamDoc.data() != null) {
        final data = teamDoc.data()!;
        data['id'] = teamDoc.id;
        if (data['store'] == null || (data['store'] as String).isEmpty) {
          data['store'] = sid;
        }
        return UserModel.fromJson(data);
      }
      if (globalDoc.exists && globalDoc.data() != null) {
        final data = globalDoc.data()!;
        final ownedStores = List<String>.from(data['owned_stores'] ?? []);
        if (ownedStores.contains(sid)) {
          data['id'] = globalDoc.id;
          data['store'] = sid;
          data['title'] = 'Owner';
          return UserModel.fromJson(data);
        }
      }
      return null;
    });
  }

  Stream<List<Map<String, dynamic>>> streamUserTimeOffRequests(String userId) {
    if (!isStoreAllowed) return Stream.value([]);
    if (storeId == null) {
      return streamAllStores().switchMap((allStores) {
        final stores = _filterAllowedStores(allStores);
        if (stores.isEmpty) return Stream.value([]);
        final streams = stores.map(
          (s) => _streamUserTimeOffRequestsForStore(s['id'] as String, userId),
        );
        return Rx.combineLatest(streams, (
          List<List<Map<String, dynamic>>> lists,
        ) {
          return lists.expand((x) => x).toList();
        });
      });
    }
    return _streamUserTimeOffRequestsForStore(storeId!, userId);
  }

  Stream<List<Map<String, dynamic>>> _streamUserTimeOffRequestsForStore(
    String sid,
    String userId,
  ) {
    return _db
        .collection('stores')
        .doc(sid)
        .collection('time_off_requests')
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });
  }

  /// Returns a stream of ALL pending time off requests for the store.
  Stream<List<Map<String, dynamic>>> streamAllPendingTimeOffRequests() {
    if (!isStoreAllowed) return Stream.value([]);
    if (storeId == null) {
      return streamAllStores().switchMap((allStores) {
        final stores = _filterAllowedStores(allStores);
        if (stores.isEmpty) return Stream.value([]);
        final streams = stores.map(
          (s) => _streamAllPendingTimeOffRequestsForStore(s['id'] as String),
        );
        return Rx.combineLatest(streams, (List<List<Map<String, dynamic>>> lists) {
          final list = lists.expand((x) => x).toList();
          list.sort(
            (x, y) => (x['start_date'] as String? ?? '').compareTo(
              y['start_date'] as String? ?? '',
            ),
          );
          return list;
        });
      });
    }
    return _streamAllPendingTimeOffRequestsForStore(storeId!);
  }

  Stream<List<Map<String, dynamic>>> _streamAllPendingTimeOffRequestsForStore(
    String sid,
  ) {
    return _db
        .collection('stores')
        .doc(sid)
        .collection('time_off_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();

          // Sort oldest to newest start_date (as proxy for oldest recorded)
          list.sort(
            (a, b) => (a['start_date'] as String? ?? '').compareTo(
              b['start_date'] as String? ?? '',
            ),
          );
          return list;
        });
  }

  /// Update a time off request status
  Future<void> updateTimeOffRequestStatus(
    String requestId,
    String status,
  ) async {
    await _db
        .collection('stores')
        .doc(storeId)
        .collection('time_off_requests')
        .doc(requestId)
        .update({'status': status});
  }

  /// Returns a stream of shifts for a specific user across all schedules.
  Stream<List<Map<String, dynamic>>> streamUserShifts(String userId) {
    return _db
        .collectionGroup('shifts')
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Returns a stream of active availability for a specific user.
  Stream<Map<String, dynamic>?> streamUserAvailability(String userId) {
    if (!isStoreAllowed) return Stream.value(null);
    if (storeId == null) {
      return streamAllStores().switchMap((allStores) {
        final stores = _filterAllowedStores(allStores);
        if (stores.isEmpty) return Stream.value(null);
        final streams = stores.map(
          (s) => _streamUserAvailabilityForStore(s['id'] as String, userId),
        );
        return Rx.combineLatest(streams, (List<Map<String, dynamic>?> avails) {
          return avails.firstWhere((a) => a != null, orElse: () => null);
        });
      });
    }
    return _streamUserAvailabilityForStore(storeId!, userId);
  }

  Stream<Map<String, dynamic>?> _streamUserAvailabilityForStore(
    String sid,
    String userId,
  ) {
    return _db
        .collection('stores')
        .doc(sid)
        .collection('active_availability')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.data());
  }

  /// Updates an existing team member's profile.
  Future<void> updateUser(UserModel user) async {
    if (user.id == null || user.id!.isEmpty) {
      throw ArgumentError('User ID cannot be null or empty when updating');
    }

    // Determine the target store for the user document
    final targetStoreId = storeId ?? user.store ?? 'QYfhsc0dBHLBbgOflHsA';

    try {
      final data = user.toJson();
      data.remove('id');

      await _db
          .collection('stores')
          .doc(targetStoreId)
          .collection('users')
          .doc(user.id)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      print('Error updating user: $e');
      rethrow;
    }
  }

  /// Creates a new team member.
  Future<void> createUser(UserModel user) async {
    // Determine the target store for the user document
    final targetStoreId = storeId ?? user.store ?? 'QYfhsc0dBHLBbgOflHsA';

    try {
      final collection = _db
          .collection('stores')
          .doc(targetStoreId)
          .collection('users');
      final data = user.toJson();
      data.remove('id');

      if (user.id != null && user.id!.isNotEmpty) {
        await collection.doc(user.id).set(data);
      } else {
        await collection.add(data);
      }
    } catch (e) {
      print('Error creating user: $e');
      rethrow;
    }
  }

  /// Deletes a team member from the store, with their availability, time
  /// off requests and HR events. (Shifts already on the schedule stay until
  /// the schedule is changed.)
  Future<void> deleteUser(String userId, {String? userStore}) async {
    final store = _db.collection('stores').doc(storeId ?? userStore ?? 'QYfhsc0dBHLBbgOflHsA');
    final batch = _db.batch();
    batch.delete(store.collection('users').doc(userId));
    batch.delete(store.collection('active_availability').doc(userId));
    batch.delete(store.collection('training_progress').doc(userId));
    for (final name in ['time_off_requests', 'employee_infractions']) {
      final docs = await store
          .collection(name)
          .where('user_id', isEqualTo: userId)
          .get();
      for (final d in docs.docs) {
        batch.delete(d.reference);
      }
    }
    await batch.commit();
  }

  // --- TEMPORARY SEEDING ---

  /// TEMPORARY: deletes every team member of this store (or of every store
  /// when "All Stores" is selected) and everything tied to them:
  ///  * stores/{id}/users/*                 (the team members)
  ///  * stores/{id}/active_availability/*   (availability)
  ///  * stores/{id}/time_off_requests/*     (time off)
  ///  * stores/{id}/employee_infractions/*  (HR events)
  ///  * stores/{id}/training_progress/*     (training review)
  ///  * stores/{id}/schedules/* + shifts/*  (posted weeks)
  ///  * shifts on every schedule day (main + other schedules); the days'
  ///    templates stay
  ///  * fake logins from the sample data (/users docs marked seeded)
  /// Keeps settings, templates, positions, portal links and real /users
  /// login accounts. Returns how many documents were deleted / changed.
  Future<int> deleteAllData() async {
    final targetStores = storeId != null
        ? [storeId!]
        : (allowedStoreIds != null && allowedStoreIds!.isNotEmpty)
            ? allowedStoreIds!
            : (await _db.collection('stores').get()).docs.map((d) => d.id).toList();

    var count = 0;
    var batch = _db.batch();
    var pending = 0;
    Future<void> flush() async {
      if (pending == 0) return;
      await batch.commit();
      batch = _db.batch();
      pending = 0;
    }

    Future<void> deleteRef(DocumentReference<Map<String, dynamic>> ref) async {
      batch.delete(ref);
      count++;
      if (++pending >= 400) await flush();
    }

    Future<void> deleteAll(
      CollectionReference<Map<String, dynamic>> col,
    ) async {
      for (final doc in (await col.get()).docs) {
        await deleteRef(doc.reference);
      }
    }

    for (final sId in targetStores) {
      final store = _db.collection('stores').doc(sId);
      await deleteAll(store.collection('users'));
      await deleteAll(store.collection('active_availability'));
      await deleteAll(store.collection('time_off_requests'));
      await deleteAll(store.collection('employee_infractions'));
      await deleteAll(store.collection('training_progress'));

      // Fake logins made by "Seed Sample Store Data" (real ones stay).
      final logins = await _db
          .collection('users')
          .where('storeId', isEqualTo: sId)
          .get();
      for (final doc in logins.docs) {
        if (doc.data()['seeded'] == true) await deleteRef(doc.reference);
      }

      // Posted weeks: their shift docs first (deleting a doc doesn't delete
      // its subcollections), then the week docs.
      for (final week in (await store.collection('schedules').get()).docs) {
        await deleteAll(week.reference.collection('shifts'));
        await deleteRef(week.reference);
      }

      // Schedule days: take everyone off, keep the templates.
      final config =
          (await store.collection('settings').doc('schedule_config').get())
              .data();
      final boardIds = {
        'main',
        for (final b in (config?['boards'] as List? ?? const []))
          if (b is Map && b['id'] is String) b['id'] as String,
      };
      for (final boardId in boardIds) {
        final days = boardId == 'main'
            ? store.collection('schedule_days')
            : store
                  .collection('schedule_boards')
                  .doc(boardId)
                  .collection('days');
        for (final day in (await days.get()).docs) {
          final shifts = day.data()['shifts'];
          if (shifts is List && shifts.isEmpty) continue;
          batch.update(day.reference, {
            'shifts': <dynamic>[],
            'user_ids': <dynamic>[],
            'labor_hours': 0,
            'posted_at': null,
            'edited_after_post': false,
          });
          count++;
          if (++pending >= 400) await flush();
        }
      }
    }
    await flush();
    return count;
  }

  /// The stores "Seed Sample Store Data" fills: the selected store, or with
  /// "All Stores" selected every store (each gets its own team, with new
  /// random names).
  Future<List<({String id, String name})>> sampleStores() async {
    final stores = (await _db.collection('stores').get()).docs;
    return [
      for (final d in stores)
        if (storeId == null)
          if (allowedStoreIds == null ||
              allowedStoreIds!.isEmpty ||
              allowedStoreIds!.contains(d.id))
            (id: d.id, name: d.data()['name'] as String? ?? d.id)
        else if (d.id == storeId)
          (id: d.id, name: d.data()['name'] as String? ?? d.id),
    ];
  }

  /// TEMPORARY: replaces [targetStoreId]'s team with the sample team and
  /// sets up its schedules (see sample_data.dart). Returns a summary.
  Future<String> seedSampleData(String targetStoreId) async {
    await FirestoreService(storeId: targetStoreId).deleteAllData();
    return SampleSeeder(targetStoreId).seed();
  }
}
