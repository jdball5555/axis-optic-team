import 'dart:math';

import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/models/user_model.dart';
import 'package:axis_team/services/sample_data.dart';
import 'package:axis_team/ui/views/schedule/schedule_common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final seeder = SampleSeeder('store', today: DateTime(2026, 10, 10));
  final docs = seeder.memberDocs();
  final users = {
    for (final e in docs.entries)
      e.key: UserModel.fromJson({...e.value, 'id': e.key}),
  };

  test('everyone in the sample week is on the team', () {
    final missing = seeder.weekPeople
        .where((k) => !k.startsWith('house'))
        .where((k) => !docs.containsKey(seeder.memberId(k)));
    expect(missing, isEmpty);
    expect(docs.length, greaterThanOrEqualTo(60));
  });

  for (final board in [kMainBoardId, kitchenBoardId]) {
    test('$board: shifts fit the rows and nobody overlaps', () {
      for (var d = 0; d < 6; d++) {
        final day = seeder.buildDay(d, board);
        expect(day.rows, isNotEmpty);
        // Every piece sits inside its row's needed time, and pieces in a row
        // never overlap.
        for (final row in day.rows) {
          final pieces = day.piecesInRow(row.id).map((e) => e.$2).toList()
            ..sort((a, b) => a.start.compareTo(b.start));
          for (var i = 0; i < pieces.length; i++) {
            expect(
              row.windows.any(
                (w) => w.containsRange(pieces[i].start, pieces[i].end),
              ),
              isTrue,
            );
            if (i > 0) expect(pieces[i - 1].end <= pieces[i].start, isTrue);
          }
        }
        // Restricted rows only hold people allowed in them.
        for (final s in day.shifts) {
          for (final p in s.workPieces) {
            expect(
              userFitsRow(users[s.userId], day.rowById(p.rowId)!),
              isTrue,
              reason:
                  '${s.userId} in ${day.rowById(p.rowId)!.allowedTitles} on day $d',
            );
          }
        }
        // One shift per person (trainees may also have their own).
        final ids = day.shifts.map((s) => s.userId).toList();
        expect(ids.toSet().length, ids.length);
      }
    });
  }

  test('training pairs and the front-of-house truck bar', () {
    final mon = seeder.buildDay(0, kMainBoardId);
    final trainers = mon.shifts.where((s) => s.isTraining).map((s) => s.userId);
    expect(
      trainers,
      containsAll([seeder.memberId('p32'), seeder.memberId('p63')]),
    );
    final wed = seeder.buildDay(2, kMainBoardId);
    expect(
      wed.shifts
          .firstWhere((s) => s.userId == seeder.memberId('p44'))
          .traineeId,
      seeder.memberId('p03'),
    );
    expect(
      wed.rows.any(
        (r) => r.label == 'Truck' && r.allowedTitles.contains('Truck'),
      ),
      isTrue,
    );
    // Kitchen leaders get leader bars.
    final kitchenMon = seeder.buildDay(0, kitchenBoardId);
    expect(
      kitchenMon.rows.where((r) => r.isRestricted).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('availability covers every sample shift', () {
    final week = weekStartFor(DateTime(2026, 10, 10), DateTime.monday);
    for (final board in [kMainBoardId, kitchenBoardId]) {
      for (var d = 0; d < 6; d++) {
        final day = seeder.buildDay(d, board);
        final date = addDays(week, d);
        for (final s in day.shifts) {
          for (final uid in [s.userId, ?s.traineeId]) {
            final windows = availabilityFor(users[uid]!, date)!;
            for (final p in s.workPieces.where((p) => uid == s.userId)) {
              expect(
                windows.any((w) => w.containsRange(p.start, p.end)),
                isTrue,
                reason: '$uid on day $d ${p.start}-${p.end}: $windows',
              );
            }
          }
        }
      }
    }
  });

  test('seasonal people are unavailable, new hires are new', () {
    final p53 = users[seeder.memberId('p53')]!;
    expect(availabilityFor(p53, DateTime(2026, 10, 12)), isEmpty);
    expect(users[seeder.memberId('p11')]!.startDate, DateTime(2026, 10, 6));
  });

  test('names are random, different for everyone, and new each time', () {
    String full(UserModel u) => '${u.firstName} ${u.lastName}';
    expect(users.values.map(full).toSet(), hasLength(users.length));
    expect(
      users.values.map((u) => u.firstName).toSet(),
      hasLength(users.length),
    );
    expect(users.values.map((u) => u.email).toSet(), hasLength(users.length));
    for (final u in users.values) {
      final first = (u.preferredName ?? u.firstName)!.toLowerCase();
      expect(u.email, startsWith('$first.'));
    }
    // Another seeding (another store, or seeding again) is a new team.
    final again = SampleSeeder(
      'store2',
      today: DateTime(2026, 10, 10),
    ).memberDocs();
    final same = docs.entries.where((e) {
      final other =
          again['seed_store2_${e.key.substring('seed_store_'.length)}']!;
      return e.value['first_name'] == other['first_name'] &&
          e.value['last_name'] == other['last_name'];
    });
    expect(same.length, lessThan(5));
    // The same random seed gives the same names (tests can pin them).
    Map<String, dynamic> pinned(int seed) => SampleSeeder(
      'store',
      today: DateTime(2026, 10, 10),
      random: Random(seed),
    ).memberDocs()[seeder.memberId('p29')]!;
    expect(pinned(7)['first_name'], pinned(7)['first_name']);
  });

  test('each store gets its own team member ids and fake logins', () {
    // Shared ids would make the All Stores lists merge two stores' people.
    expect(
      SampleSeeder('a').memberId('p29'),
      isNot(SampleSeeder('b').memberId('p29')),
    );
    expect(
      SampleSeeder('a').loginId('p29'),
      isNot(SampleSeeder('b').loginId('p29')),
    );
  });
}
