// Data for the phone app: who's signed in, what they can see, their own
// team-member record, and the posted / working schedules. Built on the same
// providers and Firestore layout as the desktop app (see firestore_schema.txt).

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../../models/schedule_models.dart';
import '../../models/title_journey.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/feature_providers.dart';
import '../../services/schedule_repository.dart';

// =============================================================================
// Layout
// =============================================================================

/// Use the phone app: team-member logins always (it's their app on any
/// screen), everyone else when the screen is phone-sized.
bool useMobileLayout(
  Map<String, dynamic>? user, {
  bool teamMemberView = false,
}) {
  if (teamMemberView || user?['role'] == 'team_member') return true;
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return false;
  final view = views.first;
  if (view.devicePixelRatio <= 0) return false;
  final size = view.physicalSize / view.devicePixelRatio;
  return size.shortestSide > 0 && size.shortestSide < 600;
}

// =============================================================================
// Who's signed in and what they can do
// =============================================================================

/// The stores this login can open on the phone: a team member's store, or
/// the stores an owner / bot account has.
final mobileStoreIdsProvider = Provider<List<String>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final own = user['storeId'];
  final owned = user['owned_stores'];
  final ids = <String>{
    if (own is String && own.isNotEmpty) own,
    if (owned is List)
      for (final s in owned)
        if (s is String && s.isNotEmpty) s,
  };
  if (ids.isNotEmpty) return ids.toList();
  // No stores on the login: fall back to every store (older owner accounts).
  final all = ref.watch(allStoresStreamProvider).valueOrNull ?? const [];
  return [
    for (final s in all)
      if (s['id'] is String) s['id'] as String,
  ];
});

/// The signed-in person's own team-member record in the current store:
/// linked by their login (team-member accounts), or matched by email (an
/// owner who is also on the team). Null when they aren't on the team table.
///
/// While a promotion is still a surprise (not sent yet, or the
/// congratulations screen hasn't been seen) this shows their old title.
final myMemberProvider = Provider<AsyncValue<UserModel?>>((ref) {
  final promotion = ref.watch(myPromotionProvider);
  return ref.watch(myTeamRecordProvider).whenData((m) {
    if (m == null || promotion == null || !promotion.hides(m.title)) return m;
    return m.copyWith(title: promotion.from);
  });
});

/// [myMemberProvider] as saved (the real, current title).
final myTeamRecordProvider = Provider<AsyncValue<UserModel?>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const AsyncValue.data(null);
  final uid = user['id'] as String?;
  final linkedId = user['userId'] as String?;
  final email = (user['email'] as String? ?? '').trim().toLowerCase();
  return ref.watch(allStoreUsersStreamProvider).whenData((users) {
    if (linkedId != null && linkedId.isNotEmpty) {
      final linked = users.where((u) => u.id == linkedId).firstOrNull;
      if (linked != null) return linked;
    }
    if (email.isEmpty) return null;
    return users.where((u) {
      // The owner's own login shows up in the list too (id = their uid).
      if (u.id == uid || u.title == 'Owner') return false;
      return (u.email ?? '').trim().toLowerCase() == email;
    }).firstOrNull;
  });
});

// =============================================================================
// Promotions
// =============================================================================

/// A team member's raw Firestore record (for fields the model doesn't carry:
/// promotion, fcm_tokens, notifications_enabled).
final memberDocProvider =
    StreamProvider.family<Map<String, dynamic>?, MemberKey>((ref, key) {
      if (key.storeId.isEmpty || key.memberId.isEmpty) {
        return Stream.value(null);
      }
      return FirebaseFirestore.instance
          .collection('stores')
          .doc(key.storeId)
          .collection('users')
          .doc(key.memberId)
          .snapshots()
          .map((d) => d.data());
    });

/// The latest promotion a leader recorded for someone (website → Promote).
/// Firestore: stores/{storeId}/users/{memberId}.promotion
class Promotion {
  const Promotion({
    required this.id,
    required this.from,
    required this.to,
    required this.revealAt,
    required this.seen,
    this.date,
  });

  final String id;
  final String from;
  final String to;
  final DateTime? date;

  /// When they find out (the notification's send time).
  final DateTime revealAt;

  /// They've seen the congratulations screen.
  final bool seen;

  bool get revealed => !DateTime.now().isBefore(revealAt);

  /// Time for the congratulations screen.
  bool get due => !seen && revealed;

  /// Keep showing the old title (still a surprise or not celebrated yet).
  /// Only while [title] is still the promoted one (a leader may have
  /// changed it again since).
  bool hides(String? title) =>
      !seen && from.isNotEmpty && from != to && title == to;

  static Promotion? fromJson(dynamic j) {
    if (j is! Map) return null;
    final to = j['to'];
    if (to is! String || to.isEmpty) return null;
    final reveal = j['reveal_at'];
    return Promotion(
      id: j['id'] as String? ?? '',
      from: j['from'] as String? ?? '',
      to: to,
      date: DateTime.tryParse(j['date'] as String? ?? ''),
      revealAt: reveal is Timestamp
          ? reveal.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      seen: j['seen'] == true,
    );
  }
}

/// The signed-in person's latest promotion in the current store.
final myPromotionProvider = Provider<Promotion?>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  final id = ref.watch(myTeamRecordProvider).valueOrNull?.id;
  if (storeId == null || id == null) return null;
  final doc = ref
      .watch(memberDocProvider((storeId: storeId, memberId: id)))
      .valueOrNull;
  return Promotion.fromJson(doc?['promotion']);
});

/// Set by the congratulations screen so Home plays the title change.
/// [test] = the Settings test (Home puts the real title back afterwards).
final titleSwapProvider = StateProvider<({String from, String to, bool test})?>(
  (ref) => null,
);

/// Settings → "Test the promotion": a pretend promotion for the
/// congratulations screen. Nothing is saved.
final promotionTestProvider = StateProvider<Promotion?>((ref) => null);

// =============================================================================
// Schedule preview (leaders): the Schedule tab with a sample team member
// =============================================================================

/// The sample team member while a leader previews the team member view:
/// in "View as team member" (the whole app), or set in a nested
/// ProviderScope for the Schedule tab preview. Nothing is saved meanwhile.
final schedulePreviewProvider = Provider<SchedulePreview?>((ref) {
  if (!ref.watch(teamMemberViewProvider)) return null;
  final user = ref.watch(currentUserProvider) ?? const <String, dynamic>{};
  final storeId = ref.watch(currentStoreIdProvider);
  final titles =
      ref.watch(storeSettingsProvider).valueOrNull?.titles ?? const [];
  final config =
      (storeId == null
          ? null
          : ref.watch(scheduleConfigProvider(storeId)).valueOrNull) ??
      const ScheduleConfig();
  final journey = journeyFor(
    storeId == null
        ? null
        : ref.watch(titleJourneyProvider(storeId)).valueOrNull,
    titles,
  );
  // A regular team member: the "Team Member" title, else where new hires start.
  final title =
      titles
          .where((t) => t.name.toLowerCase().contains('team member'))
          .firstOrNull
          ?.name ??
      titles.where((t) => t.id == journey.start).firstOrNull?.name ??
      titles.firstOrNull?.name ??
      'Team Member';
  String name(String key, String fallback) {
    final v = (user[key] as String? ?? '').trim();
    return v.isEmpty ? fallback : v;
  }

  return SchedulePreview.build(
    title: title,
    thisWeek: weekStartFor(DateTime.now(), config.weekStart),
    firstName: name('first_name', 'Jordan'),
    lastName: name('last_name', 'Sample'),
  );
});

/// "View as team member": an owner or leader sees the phone app exactly as
/// someone on the team does (as themselves, with a sample schedule), without
/// the website around it. Nothing is saved meanwhile. Turned off in
/// Settings, which goes back to the dashboard.
final teamMemberViewProvider = StateProvider<bool>((ref) => false);

/// Which part of the Schedule tab to open next (from Home's shortcuts):
/// 0 shifts, 1 availability, 2 time off.
final scheduleSectionRequestProvider = StateProvider<int?>((ref) => null);

/// Turns "View as team member" on or off.
void setTeamMemberView(WidgetRef ref, bool on) {
  MobileWrites.preview = on;
  ref.read(teamMemberViewProvider.notifier).state = on;
}

class SchedulePreview {
  SchedulePreview({required this.member, required this.thisWeek});

  /// The sample team member.
  final UserModel member;

  /// Start of the current week (the store's week start).
  final DateTime thisWeek;

  static const id = '__preview__';

  static SchedulePreview build({
    required String? title,
    required DateTime thisWeek,
    String firstName = 'Jordan',
    String lastName = 'Sample',
  }) {
    final now = DateTime.now();
    List<Map<String, String>> w(String a, String b) => [
      {'start': a, 'end': b},
    ];
    return SchedulePreview(
      thisWeek: thisWeek,
      member: UserModel(
        id: id,
        firstName: firstName,
        lastName: lastName,
        title: title,
        designation: 'Adult',
        foodHandlersExpiration: DateTime(now.year + 1, now.month, 1),
        position: 'Front of House',
        workingTime: 'Part Time',
        startDate: DateTime(now.year, now.month - 8, 14),
        activeAvailability: {
          'monday': w('10:00', '22:00'),
          'tuesday': <Map<String, String>>[],
          'wednesday': w('15:00', '23:00'),
          'thursday': w('15:00', '23:00'),
          'friday': w('10:00', '23:00'),
          'saturday': w('08:00', '23:00'),
          'sunday': <Map<String, String>>[],
        },
      ),
    );
  }

  /// Sample shifts: this week and next are posted, later weeks aren't yet.
  List<RosterEntry> shiftsFor(DateTime weekStart) {
    final weeks =
        dateOnly(weekStart).difference(dateOnly(thisWeek)).inDays ~/ 7;
    if (weeks > 1) return const [];
    const patterns = [
      [
        (0, 660, 1020, 'Front Counter'),
        (2, 960, 1320, 'Drive-Thru'),
        (4, 1020, 1380, 'Drive-Thru'),
        (5, 630, 990, 'Front Counter'),
      ],
      [
        (0, 960, 1320, 'Drive-Thru'),
        (3, 990, 1380, 'Front Counter'),
        (4, 660, 1020, 'Front Counter'),
        (5, 1020, 1380, 'Drive-Thru'),
      ],
    ];
    final p = patterns[weeks.abs() % 2];
    return [
      for (final (day, start, end, area) in p)
        RosterEntry(
          userId: id,
          date: dateKey(addDays(weekStart, day)),
          start: start,
          end: end,
          boardId: kMainBoardId,
          area: area,
        ),
    ];
  }

  /// Sample time off requests.
  List<TimeOffRequest> get timeOff => [
    TimeOffRequest(
      id: 'preview-1',
      startDate: dateKey(addDays(thisWeek, 15)),
      endDate: dateKey(addDays(thisWeek, 17)),
      status: 'approved',
      reason: 'Family trip',
    ),
    TimeOffRequest(
      id: 'preview-2',
      startDate: dateKey(addDays(thisWeek, 9)),
      endDate: dateKey(addDays(thisWeek, 9)),
      status: 'pending',
      reason: 'Dentist appointment',
      startTime: '13:00',
      endTime: '15:00',
    ),
  ];
}

/// What the signed-in person can see and do on the phone.
class MobileAccess {
  const MobileAccess({
    required this.role,
    required this.member,
    required this.levels,
    required this.scheduleOn,
    required this.shiftOn,
  });

  /// 'owner', 'bot' or 'team_member'.
  final String role;

  /// Their team-member record in the current store (null = not on the team).
  final UserModel? member;

  /// Access levels switched on for them (login and team record combined).
  final Map<String, bool> levels;

  /// The store has the Schedule / Shift board turned on.
  final bool scheduleOn;
  final bool shiftOn;

  bool get isOwner => role == 'owner';
  bool get isBot => role == 'bot';
  bool get isOnTeam => member != null;

  bool _has(String key) => isOwner || levels[key] == true;

  /// Their own shifts, availability and time off.
  bool get mySchedule => isOnTeam && scheduleOn;

  /// The team list and everyone's details.
  bool get team => isOwner || isBot || _has('Access Team Members');

  /// Schedules that aren't posted yet (managers).
  bool get draftSchedules => isOwner || isBot || _has('Access Schedule');

  /// Leadership numbers on the home page.
  bool get leadership => isOwner || isBot || levels.values.any((v) => v);

  bool get seeShiftBoard =>
      shiftOn && (isOwner || isBot || _has('Access Shift Board'));

  /// Bots are view only.
  bool get editShiftBoard => shiftOn && !isBot && _has('Access Shift Board');
}

final mobileAccessProvider = Provider<MobileAccess>((ref) {
  // "View as team member": exactly what someone on the team gets.
  if (ref.watch(teamMemberViewProvider)) {
    return MobileAccess(
      role: 'team_member',
      member: ref.watch(schedulePreviewProvider)?.member,
      levels: const {},
      scheduleOn: ref.watch(scheduleFeatureProvider),
      shiftOn: ref.watch(shiftFeatureProvider),
    );
  }
  final user = ref.watch(currentUserProvider) ?? const <String, dynamic>{};
  final member = ref.watch(myMemberProvider).valueOrNull;
  final levels = <String, bool>{};
  final raw = user['access_levels'];
  if (raw is Map) {
    raw.forEach((k, v) {
      if (k is String && v == true) levels[k] = true;
    });
  }
  member?.accessLevels?.forEach((k, v) {
    if (v == true) levels[k] = true;
  });
  final owned = user['owned_stores'];
  final role =
      user['role'] as String? ??
      ((owned is List && owned.isNotEmpty) ? 'owner' : 'team_member');
  return MobileAccess(
    role: role,
    member: member,
    levels: levels,
    scheduleOn: ref.watch(scheduleFeatureProvider),
    shiftOn: ref.watch(shiftFeatureProvider),
  );
});

// =============================================================================
// Schedules: one shape for posted and working (not posted) shifts
// =============================================================================

/// One person's time on the schedule for a day.
class RosterEntry {
  const RosterEntry({
    required this.userId,
    required this.date,
    required this.start,
    required this.end,
    required this.boardId,
    this.area = '',
    this.isAdmin = false,
    this.trainingWith,
    this.traineeId,
  });

  final String userId;
  final String date; // yyyy-MM-dd
  final int start; // minutes from midnight (can pass 1440)
  final int end;
  final String boardId;

  /// Row labels / titles ("Leader", "Front of house").
  final String area;

  /// Scheduled admin time (off the floor).
  final bool isAdmin;

  /// A trainee's shift: who they're training with.
  final String? trainingWith;

  /// A trainer's shift: who they're training.
  final String? traineeId;

  int get minutes => math.max(0, end - start);
  double get hours => minutes / 60;

  factory RosterEntry.fromPosted(Map<String, dynamic> j, String boardId) {
    int minute(String key, String fallbackKey) {
      final v = j[key];
      if (v is num) return v.toInt();
      final parts = j[fallbackKey]?.toString().split(':');
      if (parts == null || parts.length < 2) return 0;
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }

    final start = minute('start_minute', 'scheduled_start');
    var end = minute('end_minute', 'scheduled_end');
    if (end <= start) end += 1440;
    return RosterEntry(
      userId: j['user_id'] as String? ?? '',
      date: j['date'] as String? ?? '',
      start: start,
      end: end,
      boardId: boardId,
      area: j['assigned_area'] as String? ?? '',
      isAdmin: j['is_admin'] == true,
      trainingWith: j['training_with'] as String?,
    );
  }
}

/// A working schedule day as roster entries (the same split as posting:
/// floor time and admin time are separate, a trainee gets their own entry).
List<RosterEntry> entriesFromDay(ScheduleDay day, String boardId) {
  final out = <RosterEntry>[];
  for (final s in day.shifts) {
    final work = s.workPieces;
    if (work.isNotEmpty) {
      final start = work.map((p) => p.start).reduce(math.min);
      final end = work.map((p) => p.end).reduce(math.max);
      final areas = <String>{
        for (final p in work)
          if (day.rowById(p.rowId) case final r?)
            r.label.isNotEmpty ? r.label : r.allowedTitles.join(', '),
      }.where((a) => a.isNotEmpty).join(' / ');
      out.add(
        RosterEntry(
          userId: s.userId,
          date: day.date,
          start: start,
          end: end,
          boardId: boardId,
          area: areas,
          traineeId: s.isTraining ? s.traineeId : null,
        ),
      );
      if (s.isTraining) {
        out.add(
          RosterEntry(
            userId: s.traineeId!,
            date: day.date,
            start: start,
            end: end,
            boardId: boardId,
            area: areas,
            trainingWith: s.userId,
          ),
        );
      }
    }
    for (final a in s.adminPieces) {
      out.add(
        RosterEntry(
          userId: s.userId,
          date: day.date,
          start: a.start,
          end: a.end,
          boardId: boardId,
          area: 'Admin',
          isAdmin: true,
        ),
      );
    }
  }
  return out;
}

/// Doc id of a posted week (/stores/{id}/schedules/{weekId}).
String postedWeekDocId(String weekStart, String boardId) =>
    boardId == kMainBoardId ? weekStart : '${weekStart}__$boardId';

typedef PostedWeekKey = ({String storeId, String weekStart, String boards});

/// Every posted shift in a week, across the given schedules ([boards] is a
/// comma-separated list of schedule ids).
final postedWeekProvider =
    StreamProvider.family<List<RosterEntry>, PostedWeekKey>((ref, key) {
      final ids = key.boards.split(',').where((s) => s.isNotEmpty).toList();
      if (ids.isEmpty) return Stream.value(const <RosterEntry>[]);
      final store = FirebaseFirestore.instance
          .collection('stores')
          .doc(key.storeId);
      final streams = [
        for (final b in ids)
          store
              .collection('schedules')
              .doc(postedWeekDocId(key.weekStart, b))
              .collection('shifts')
              .snapshots()
              .map(
                (snap) => [
                  for (final d in snap.docs)
                    RosterEntry.fromPosted(d.data(), b),
                ],
              ),
      ];
      return Rx.combineLatestList(
        streams,
      ).map((lists) => [for (final l in lists) ...l]);
    });

/// Comma-separated ids of a store's schedules, for [postedWeekProvider].
String boardsKey(ScheduleConfig config) =>
    config.allBoards.map((b) => b.id).join(',');

// =============================================================================
// Time off and availability
// =============================================================================

class TimeOffRequest {
  const TimeOffRequest({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.reason = '',
    this.startTime,
    this.endTime,
  });

  final String id;
  final String startDate; // yyyy-MM-dd
  final String endDate;
  final String status; // pending | approved | denied
  final String reason;
  final String? startTime; // "HH:mm" for part-day requests
  final String? endTime;

  bool get isPending => status == 'pending';
  bool get isPartDay => startTime != null && endTime != null;

  factory TimeOffRequest.fromJson(String id, Map<String, dynamic> j) {
    String day(dynamic v) {
      if (v is Timestamp) return dateKey(v.toDate());
      final s = v?.toString() ?? '';
      return s.length >= 10 ? s.substring(0, 10) : s;
    }

    final start = day(j['start_date']);
    final end = day(j['end_date']);
    final st = j['start_time'] as String?;
    final et = j['end_time'] as String?;
    return TimeOffRequest(
      id: id,
      startDate: start,
      endDate: end.isEmpty ? start : end,
      status: (j['status'] as String? ?? 'pending').toLowerCase(),
      reason: j['reason'] as String? ?? '',
      startTime: (st?.isNotEmpty ?? false) ? st : null,
      endTime: (et?.isNotEmpty ?? false) ? et : null,
    );
  }
}

typedef MemberKey = ({String storeId, String memberId});

/// A team member's time off requests, newest start date first.
final memberTimeOffProvider =
    StreamProvider.family<List<TimeOffRequest>, MemberKey>((ref, key) {
      return FirebaseFirestore.instance
          .collection('stores')
          .doc(key.storeId)
          .collection('time_off_requests')
          .where('user_id', isEqualTo: key.memberId)
          .snapshots()
          .map((snap) {
            final list = [
              for (final d in snap.docs)
                TimeOffRequest.fromJson(d.id, d.data()),
            ]..sort((a, b) => b.startDate.compareTo(a.startDate));
            return list;
          });
    });

/// Approved time off in a store, with whose it is (for leaders' roster).
final storeApprovedTimeOffProvider =
    StreamProvider.family<
      List<({String userId, TimeOffRequest request})>,
      String
    >((ref, storeId) {
      return FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('time_off_requests')
          .where('status', isEqualTo: 'approved')
          .snapshots()
          .map(
            (snap) => [
              for (final d in snap.docs)
                (
                  userId: d.data()['user_id'] as String? ?? '',
                  request: TimeOffRequest.fromJson(d.id, d.data()),
                ),
            ],
          );
    });

/// Every pending time off request in a store (for leaders).
final storePendingTimeOffProvider = StreamProvider.family<int, String>((
  ref,
  storeId,
) {
  return FirebaseFirestore.instance
      .collection('stores')
      .doc(storeId)
      .collection('time_off_requests')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.length);
});

/// Weekday keys used by availability ("monday" … "sunday").
const availabilityDays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// Availability windows by weekday key, from a saved availability map.
/// Times are minutes from midnight; an end at or before the start runs past
/// midnight.
Map<String, List<TimeWindow>> parseAvailability(Map<String, dynamic>? data) {
  int? parse(dynamic v) {
    final parts = v?.toString().split(':');
    if (parts == null || parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  return {
    for (final day in availabilityDays)
      day: [
        for (final w in (data?[day] is List ? data![day] as List : const []))
          if (w is Map)
            if ((parse(w['start']), parse(w['end'])) case (final s?, final e?))
              TimeWindow(s, e <= s ? e + 1440 : e),
      ],
  };
}

String hhmm(int minutes) {
  final m = minutes % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// Writes for the phone app.
class MobileWrites {
  static final _db = FirebaseFirestore.instance;

  /// A leader is previewing the team member view: writes do nothing.
  static bool preview = false;

  static DocumentReference<Map<String, dynamic>> _store(String id) =>
      _db.collection('stores').doc(id);

  /// Saves a team member's availability where they enter it and where the
  /// schedule reads it.
  static Future<void> saveAvailability(
    String storeId,
    String memberId,
    Map<String, List<TimeWindow>> byDay,
  ) async {
    if (preview) return;
    final data = <String, dynamic>{
      for (final day in availabilityDays)
        day: [
          for (final w in byDay[day] ?? const <TimeWindow>[])
            {'start': hhmm(w.start), 'end': hhmm(w.end)},
        ],
    };
    final batch = _db.batch();
    batch.set(
      _store(storeId).collection('active_availability').doc(memberId),
      data,
    );
    batch.update(_store(storeId).collection('users').doc(memberId), {
      'active_availability': data,
    });
    await batch.commit();
  }

  static Future<void> requestTimeOff({
    required String storeId,
    required String memberId,
    required DateTime start,
    required DateTime end,
    String reason = '',
    int? startMinute,
    int? endMinute,
  }) async {
    if (preview) return;
    await _store(storeId).collection('time_off_requests').add({
      'user_id': memberId,
      'start_date': dateKey(start),
      'end_date': dateKey(end),
      if (startMinute != null && endMinute != null) ...{
        'start_time': hhmm(startMinute),
        'end_time': hhmm(endMinute),
      },
      'status': 'pending',
      'reason': reason,
      'approved_by': null,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  /// Takes back a request that hasn't been answered yet.
  static Future<void> cancelTimeOff(String storeId, String requestId) async {
    if (preview) return;
    await _store(
      storeId,
    ).collection('time_off_requests').doc(requestId).delete();
  }
}
