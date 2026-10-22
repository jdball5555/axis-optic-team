import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule_models.dart';

class ScheduleRepository {
  ScheduleRepository(this.storeId, {this.boardId = kMainBoardId});
  final String storeId;

  /// Which schedule's days / posts this works on (templates and settings are
  /// shared by all of a store's schedules).
  final String boardId;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _store =>
      _db.collection('stores').doc(storeId);

  CollectionReference<Map<String, dynamic>> get _templates =>
      _templatesFor(storeId);

  CollectionReference<Map<String, dynamic>> _templatesFor(String sid) =>
      _db.collection('stores').doc(sid).collection('schedule_templates');

  /// The main schedule keeps its original location; others get their own.
  CollectionReference<Map<String, dynamic>> get _days => boardId == kMainBoardId
      ? _store.collection('schedule_days')
      : _store.collection('schedule_boards').doc(boardId).collection('days');

  DocumentReference<Map<String, dynamic>> get _config =>
      _store.collection('settings').doc('schedule_config');

  DocumentReference<Map<String, dynamic>> get _shiftConfig =>
      _store.collection('settings').doc('shift_config');

  // --- Config ---------------------------------------------------------------

  Stream<ScheduleConfig> streamConfig() =>
      _config.snapshots().map((d) => ScheduleConfig.fromJson(d.data()));

  Future<void> saveConfig(ScheduleConfig config) =>
      _config.set(config.toJson(), SetOptions(merge: true));

  Stream<ShiftConfig> streamShiftConfig() =>
      _shiftConfig.snapshots().map((d) => ShiftConfig.fromJson(d.data()));

  Future<void> saveShiftConfig(ShiftConfig config) =>
      _shiftConfig.set(config.toJson(), SetOptions(merge: true));

  /// How many days [userId] was on the schedule before [date] (counts days
  /// as a trainee too). Stops counting at [limit], which is all the training
  /// flow needs.
  Future<int> scheduledDaysBefore(
    String userId,
    String date, {
    int limit = 60,
  }) async {
    final snap = await _days
        .where('user_ids', arrayContains: userId)
        .limit(limit)
        .get();
    return snap.docs.where((d) => d.id.compareTo(date) < 0).length;
  }

  /// This schedule's saved days from [from] up to (not including) [before].
  Future<List<ScheduleDay>> daysBetween(DateTime from, DateTime before) async {
    final snap = await _days
        .where('date', isGreaterThanOrEqualTo: dateKey(from))
        .where('date', isLessThan: dateKey(before))
        .get();
    return [for (final d in snap.docs) ScheduleDay.fromJson(d.id, d.data())];
  }

  /// How many days each person was on this schedule from [from] up to (not
  /// including) [before], by uid. Counts days as a trainee too.
  Future<Map<String, Set<String>>> datesWorked(
    DateTime from,
    DateTime before,
  ) async {
    final snap = await _days
        .where('date', isGreaterThanOrEqualTo: dateKey(from))
        .where('date', isLessThan: dateKey(before))
        .get();
    final out = <String, Set<String>>{};
    for (final d in snap.docs) {
      for (final uid in (d.data()['user_ids'] as List? ?? const [])) {
        if (uid is String) (out[uid] ??= {}).add(d.id);
      }
    }
    return out;
  }

  // --- Requests for the AI (store-wide) -----------------------------------------

  DocumentReference<Map<String, dynamic>> get _requests =>
      _store.collection('settings').doc('schedule_requests');

  /// This week's requests (as last typed) and requests from weeks that were
  /// posted, newest first.
  Future<({List<String> week, List<String> past})> getRequests(
    String weekId,
  ) async {
    final data = (await _requests.get()).data() ?? const {};
    final weeks = data['weeks'] is Map ? data['weeks'] as Map : const {};
    return (
      week: [
        for (final t in (weeks[weekId] as List? ?? const []))
          if (t is String) t,
      ],
      past: [
        for (final p in (data['past'] as List? ?? const []))
          if (p is Map && p['text'] is String) p['text'] as String,
      ],
    );
  }

  /// Saves the requests typed for a week (before it's posted).
  Future<void> saveWeekRequests(String weekId, List<String> requests) =>
      _requests.set({
        'weeks': {weekId: requests},
      }, SetOptions(merge: true));

  /// When a week is posted, its requests join the "From past weeks" list
  /// (newest first, no repeats, the last 40).
  Future<void> rememberWeekRequests(String weekId) async {
    final data = (await _requests.get()).data() ?? const {};
    final weeks = data['weeks'] is Map ? data['weeks'] as Map : const {};
    final week = [
      for (final t in (weeks[weekId] as List? ?? const []))
        if (t is String) t.trim(),
    ];
    if (week.isEmpty) return;
    final past = [
      for (final p in (data['past'] as List? ?? const []))
        if (p is Map && p['text'] is String) Map<String, dynamic>.from(p),
    ];
    final now = DateTime.now().toIso8601String();
    final merged = <Map<String, dynamic>>[
      for (final t in week) {'text': t, 'used_at': now, 'week': weekId},
      for (final p in past)
        if (!week.any(
          (t) => t.toLowerCase() == (p['text'] as String).trim().toLowerCase(),
        ))
          p,
    ];
    await _requests.set({
      'past': merged.take(40).toList(),
    }, SetOptions(merge: true));
  }

  /// Removes a request from the "From past weeks" list.
  Future<void> forgetPastRequest(String text) async {
    final data = (await _requests.get()).data() ?? const {};
    final past = [
      for (final p in (data['past'] as List? ?? const []))
        if (p is Map && p['text'] != text) p,
    ];
    await _requests.set({'past': past}, SetOptions(merge: true));
  }

  // --- Training progress (store-wide) ----------------------------------------

  CollectionReference<Map<String, dynamic>> get _training =>
      _store.collection('training_progress');

  Stream<Map<String, TrainingProgress>> streamTrainingProgress() =>
      _training.snapshots().map(
        (snap) => {
          for (final d in snap.docs)
            d.id: TrainingProgress.fromJson(d.id, d.data()),
        },
      );

  Future<Map<String, TrainingProgress>> getTrainingProgress() async {
    final snap = await _training.get();
    return {
      for (final d in snap.docs)
        d.id: TrainingProgress.fromJson(d.id, d.data()),
    };
  }

  Future<void> saveTrainingProgress(Iterable<TrainingProgress> list) async {
    var batch = _db.batch();
    var n = 0;
    for (final p in list) {
      batch.set(_training.doc(p.userId), {
        ...p.toJson(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (++n % 400 == 0) {
        await batch.commit();
        batch = _db.batch();
      }
    }
    await batch.commit();
  }

  // --- Templates ------------------------------------------------------------

  Stream<List<ScheduleTemplate>> streamTemplates() =>
      _templates.snapshots().map((snap) {
        final list = snap.docs
            .map((d) => ScheduleTemplate.fromJson(d.id, d.data()))
            .toList();
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return list;
      });

  /// Writes the template to every store in [ScheduleTemplate.storeIds] (same
  /// doc id) and removes it from stores it was shared with before but isn't
  /// any more ([previousStoreIds]).
  Future<void> saveTemplate(
    ScheduleTemplate t, {
    List<String> previousStoreIds = const [],
  }) async {
    final targets = t.storeIds.isEmpty ? [storeId] : t.storeIds;
    final saved = t.copyWith(storeIds: targets);
    final batch = _db.batch();
    for (final sid in targets) {
      batch.set(_templatesFor(sid).doc(t.id), {
        ...saved.toJson(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    for (final sid in previousStoreIds) {
      if (!targets.contains(sid)) batch.delete(_templatesFor(sid).doc(t.id));
    }
    await batch.commit();
  }

  /// Deletes the template from this store and every store it's shared with.
  Future<void> deleteTemplate(ScheduleTemplate t) async {
    final batch = _db.batch();
    for (final sid in {storeId, ...t.storeIds}) {
      batch.delete(_templatesFor(sid).doc(t.id));
    }
    await batch.commit();
  }

  // --- Days -----------------------------------------------------------------

  /// All saved days in the 7-day week starting at [weekStart], keyed by date.
  Stream<Map<String, ScheduleDay>> streamWeek(DateTime weekStart) {
    final from = dateKey(weekStart);
    final to = dateKey(addDays(weekStart, 6));
    return _days
        .where('date', isGreaterThanOrEqualTo: from)
        .where('date', isLessThanOrEqualTo: to)
        .snapshots()
        .map(
          (snap) => {
            for (final d in snap.docs)
              d.id: ScheduleDay.fromJson(d.id, d.data()),
          },
        );
  }

  /// One-off read of a week (e.g. to copy last week's templates).
  Future<Map<String, ScheduleDay>> getWeek(DateTime weekStart) async {
    final snap = await _days
        .where('date', isGreaterThanOrEqualTo: dateKey(weekStart))
        .where('date', isLessThanOrEqualTo: dateKey(addDays(weekStart, 6)))
        .get();
    return {
      for (final d in snap.docs) d.id: ScheduleDay.fromJson(d.id, d.data()),
    };
  }

  Future<void> saveDay(ScheduleDay day) => _days.doc(day.date).set({
    ...day.toJson(),
    'updated_at': FieldValue.serverTimestamp(),
  });

  // --- Posting --------------------------------------------------------------

  /// Posts a week: stamps each day as posted and publishes one shift doc per
  /// person per day to /schedules/{weekStart}/shifts (the layout team-member
  /// screens read), replacing whatever was posted for that week before.
  Future<void> postWeek(
    DateTime weekStart,
    List<ScheduleDay> days, {
    String? postedBy,
  }) async {
    final weekId = dateKey(weekStart);
    final week = _store
        .collection('schedules')
        .doc(boardId == kMainBoardId ? weekId : '${weekId}__$boardId');
    final shiftsRef = week.collection('shifts');
    final postedAt = DateTime.now().toIso8601String();
    String hhmm(int minutes) {
      final m = minutes % 1440;
      return '${(m ~/ 60).toString().padLeft(2, '0')}:'
          '${(m % 60).toString().padLeft(2, '0')}';
    }

    final old = await shiftsRef.get();
    final batch = _db.batch();
    for (final d in old.docs) {
      batch.delete(d.reference);
    }
    batch.set(week, {
      'start_date': weekId,
      'board_id': boardId,
      'status': 'published',
      'posted_at': postedAt,
      'posted_by': postedBy,
    }, SetOptions(merge: true));

    for (final day in days) {
      batch.set(_days.doc(day.date), {
        ...day.copyWith(postedAt: postedAt, editedAfterPost: false).toJson(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      for (final s in day.shifts) {
        if (s.pieces.isEmpty) continue;
        // Floor time and admin time are posted as separate shifts.
        final work = s.workPieces;
        if (work.isNotEmpty) {
          final start = work.map((p) => p.start).reduce(math.min);
          final end = work.map((p) => p.end).reduce(math.max);
          final areas = {for (final p in work) ?day.rowById(p.rowId)}.map(
            (r) => r.label.isNotEmpty ? r.label : r.allowedTitles.join(', '),
          );
          final doc = {
            'date': day.date,
            'scheduled_start': hhmm(start),
            'scheduled_end': hhmm(end),
            'start_minute': start,
            'end_minute': end,
            'assigned_area': areas.where((a) => a.isNotEmpty).join(' / '),
            'pieces': work.map((p) => p.toJson()).toList(),
            'store_id': storeId,
          };
          batch.set(shiftsRef.doc(), {...doc, 'user_id': s.userId});
          if (s.isTraining) {
            batch.set(shiftsRef.doc(), {
              ...doc,
              'user_id': s.traineeId,
              'training_with': s.userId,
            });
          }
        }
        for (final a in s.adminPieces) {
          batch.set(shiftsRef.doc(), {
            'date': day.date,
            'user_id': s.userId,
            'scheduled_start': hhmm(a.start),
            'scheduled_end': hhmm(a.end),
            'start_minute': a.start,
            'end_minute': a.end,
            'assigned_area': 'Admin',
            'is_admin': true,
            'pieces': [a.toJson()],
            'store_id': storeId,
          });
        }
      }
    }
    await batch.commit();
  }

  // --- Time off -------------------------------------------------------------

  Stream<List<TimeOffEntry>> streamApprovedTimeOff() =>
      _streamTimeOff('approved');

  Stream<List<TimeOffEntry>> streamPendingTimeOff() =>
      _streamTimeOff('pending');

  Stream<List<TimeOffEntry>> _streamTimeOff(String status) => _store
      .collection('time_off_requests')
      .where('status', isEqualTo: status)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) {
              final data = d.data();
              String day(dynamic v) {
                if (v is Timestamp) return dateKey(v.toDate());
                final s = v?.toString() ?? '';
                return s.length >= 10 ? s.substring(0, 10) : s;
              }

              // Optional "HH:mm" times make it a part-day request.
              int? minute(dynamic v) {
                final parts = v?.toString().split(':');
                if (parts == null || parts.length < 2) return null;
                final h = int.tryParse(parts[0]);
                final m = int.tryParse(parts[1]);
                return h == null || m == null ? null : h * 60 + m;
              }

              final start = day(data['start_date']);
              final end = day(data['end_date']);
              final startMinute = minute(data['start_time']);
              var endMinute = minute(data['end_time']);
              if (startMinute != null &&
                  endMinute != null &&
                  endMinute <= startMinute) {
                endMinute += 1440;
              }
              return TimeOffEntry(
                userId: data['user_id'] as String? ?? '',
                startDate: start,
                endDate: end.isEmpty ? start : end,
                reason: data['reason'] as String? ?? '',
                startMinute: startMinute,
                endMinute: endMinute,
              );
            })
            .where((e) => e.userId.isNotEmpty && e.startDate.isNotEmpty)
            .toList(),
      );
}

// --- Providers (all keyed by store id) ---------------------------------------

final scheduleRepositoryProvider = Provider.family<ScheduleRepository, String>(
  (ref, storeId) => ScheduleRepository(storeId),
);

typedef BoardKey = ({String storeId, String boardId});

/// Repository for one of a store's schedules.
final boardRepositoryProvider = Provider.family<ScheduleRepository, BoardKey>(
  (ref, key) => ScheduleRepository(key.storeId, boardId: key.boardId),
);

/// The schedule being viewed on the Schedule and Shift pages, per store.
final selectedBoardProvider = StateProvider.family<String, String>(
  (ref, storeId) => kMainBoardId,
);

/// The board being viewed on the Shift page, per store (null = the one
/// showing the schedule open on the Schedule page).
final selectedShiftBoardProvider = StateProvider.family<String?, String>(
  (ref, storeId) => null,
);

final scheduleConfigProvider = StreamProvider.family<ScheduleConfig, String>(
  (ref, storeId) =>
      ref.watch(scheduleRepositoryProvider(storeId)).streamConfig(),
);

final shiftConfigProvider = StreamProvider.family<ShiftConfig, String>(
  (ref, storeId) =>
      ref.watch(scheduleRepositoryProvider(storeId)).streamShiftConfig(),
);

typedef PriorDaysKey = ({
  String storeId,
  String userId,
  String date,
  String boardId,
});

/// Days someone was scheduled before a date (for the training flow).
final scheduledDaysBeforeProvider = FutureProvider.family<int, PriorDaysKey>(
  (ref, key) => ref
      .watch(
        boardRepositoryProvider((storeId: key.storeId, boardId: key.boardId)),
      )
      .scheduledDaysBefore(key.userId, key.date),
);

/// Everyone's reviewed training progress for a store, by member id.
final trainingProgressProvider =
    StreamProvider.family<Map<String, TrainingProgress>, String>(
      (ref, storeId) => ref
          .watch(scheduleRepositoryProvider(storeId))
          .streamTrainingProgress(),
    );

typedef DaysBetweenKey = ({
  String storeId,
  String userId,
  String from,
  String before,
  String boardId,
});

/// Days someone was on a schedule in [from, before) (for the training flow
/// after a review).
final scheduledDaysBetweenProvider = FutureProvider.family<int, DaysBetweenKey>(
  (ref, key) async {
    if (key.from.compareTo(key.before) >= 0) return 0;
    final worked = await ref
        .watch(
          boardRepositoryProvider((storeId: key.storeId, boardId: key.boardId)),
        )
        .datesWorked(DateTime.parse(key.from), DateTime.parse(key.before));
    return worked[key.userId]?.length ?? 0;
  },
);

final scheduleTemplatesProvider =
    StreamProvider.family<List<ScheduleTemplate>, String>(
      (ref, storeId) =>
          ref.watch(scheduleRepositoryProvider(storeId)).streamTemplates(),
    );

typedef ScheduleWeekKey = ({String storeId, String weekStart, String boardId});

final scheduleWeekProvider =
    StreamProvider.family<Map<String, ScheduleDay>, ScheduleWeekKey>((
      ref,
      key,
    ) {
      final start = DateTime.parse(key.weekStart);
      return ref
          .watch(
            boardRepositoryProvider((
              storeId: key.storeId,
              boardId: key.boardId,
            )),
          )
          .streamWeek(start);
    });

final approvedTimeOffProvider =
    StreamProvider.family<List<TimeOffEntry>, String>(
      (ref, storeId) => ref
          .watch(scheduleRepositoryProvider(storeId))
          .streamApprovedTimeOff(),
    );

final pendingTimeOffProvider =
    StreamProvider.family<List<TimeOffEntry>, String>(
      (ref, storeId) =>
          ref.watch(scheduleRepositoryProvider(storeId)).streamPendingTimeOff(),
    );
