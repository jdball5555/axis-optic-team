import 'package:axis_team/models/schedule_models.dart';
import 'package:axis_team/ui/views/schedule/position_ops.dart';
import 'package:axis_team/ui/views/schedule/shift_board_settings_dialog.dart';
import 'package:axis_team/ui/views/schedule/shift_layout_customizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _schedules = ScheduleConfig(
  boards: [
    ScheduleBoard(
      id: 'main',
      name: 'Front of House',
      positionIds: ['fc', 'dt'],
    ),
    ScheduleBoard(id: 'kitchen', name: 'Kitchen', positionIds: ['fry']),
  ],
);

const _fc = ShiftPosition(id: 'fc', name: 'Front Counter');
const _dt = ShiftPosition(id: 'dt', name: 'Drive-thru');
const _fry = ShiftPosition(id: 'fry', name: 'Fries');

void main() {
  test('older store-wide positions become one board per schedule', () {
    final config = ShiftConfig.fromJson({
      'positions': [_dt.toJson(), _fry.toJson(), _fc.toJson()],
    });
    final boards = config.boardsFor(_schedules);
    expect(boards.map((b) => b.name), ['Front of House', 'Kitchen']);
    // Keeps the old priority order.
    expect(boards[0].positions.map((p) => p.id), ['dt', 'fc']);
    expect(boards[1].positions.map((p) => p.id), ['fry']);
  });

  test('both layouts save and load, with each board\'s order', () {
    const config = ShiftConfig(
      layout: ShiftBoardLayout.custom,
      scheduleBoards: {
        'main': [_fc, _dt],
        'kitchen': [_fry],
      },
      customBoards: [
        ShiftBoard(
          id: 'all',
          name: 'Everyone',
          scheduleIds: ['main', 'kitchen'],
          positions: [_fry, _fc, _dt],
        ),
      ],
    );
    final back = ShiftConfig.fromJson(config.toJson());
    expect(back.layout, ShiftBoardLayout.custom);
    final custom = back.boardsFor(_schedules);
    expect(custom.single.scheduleIds, ['main', 'kitchen']);
    expect(custom.single.positions.map((p) => p.id), ['fry', 'fc', 'dt']);
    // The per-schedule boards are kept for switching back.
    final per = back
        .copyWith(layout: ShiftBoardLayout.perSchedule)
        .boardsFor(_schedules);
    expect(per[0].positions.map((p) => p.id), ['fc', 'dt']);
    expect(back.boardForSchedule(_schedules, 'kitchen')!.id, 'all');
    expect(back.positionById('fry')!.name, 'Fries');
  });

  test('a combined board day merges schedules and splits back', () {
    Shift shift(String id, String row, int s, int e) => Shift(
      id: id,
      userId: id,
      pieces: [ShiftPiece(id: '$id-p', rowId: row, start: s * 60, end: e * 60)],
    );
    // Both schedules use row id r1.
    final front = ScheduleDay(
      date: '2026-10-12',
      templateId: 'tf',
      rows: const [
        ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
      ],
      shifts: [shift('ivy', 'r1', 6, 14)],
    );
    final kitchen = ScheduleDay(
      date: '2026-10-12',
      templateId: 'tk',
      rows: const [
        ScheduleRow(id: 'r1', windows: [TimeWindow(360, 840)]),
      ],
      shifts: [shift('ben', 'r1', 8, 14)],
    );
    final sources = {'main': front, 'kitchen': kitchen};
    final m = mergeBoardDay('2026-10-12', sources);
    expect(m.day.shifts, hasLength(2));
    expect(m.day.rows.map((r) => r.id).toSet(), hasLength(2));
    // Deploy both schedules' people onto one board's positions.
    final deployed = deployPositions(m.day, const [_fry, _fc]);
    final parts = splitBoardDay(deployed, sources, m.origin);
    final a = parts['main']!.shifts.single;
    final b = parts['kitchen']!.shifts.single;
    expect(a.userId, 'ivy');
    expect(b.userId, 'ben');
    expect(a.pieces.single.rowId, 'r1');
    expect(b.pieces.single.rowId, 'r1');
    expect(parts['main']!.templateId, 'tf');
    // Ivy (longest) gets the top position; Ben the next one.
    expect(positionAt(a, 9 * 60), 'fry');
    expect(positionAt(b, 9 * 60), 'fc');
  });

  testWidgets(
    'settings: combining schedules and ranking a board\'s positions save',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final saved = <ShiftConfig>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftBoardSettingsDialog(
              config: const ShiftConfig(
                scheduleBoards: {
                  'main': [_fc, _dt],
                  'kitchen': [_fry],
                },
              ),
              schedules: _schedules,
              onSave: (c) async => saved.add(c),
            ),
          ),
        ),
      );
      expect(find.text('Front of House'), findsOneWidget);

      await tester.tap(find.text('Combine schedules'));
      await tester.pumpAndSettle();
      final combined = saved.last;
      expect(combined.layout, ShiftBoardLayout.custom);
      final board = combined.boardsFor(_schedules).single;
      expect(board.scheduleIds, ['main', 'kitchen']);
      expect(board.positions.map((p) => p.id), ['fc', 'dt', 'fry']);

      // Back to a board per schedule: their positions are still there.
      await tester.tap(find.text('A board for each schedule'));
      await tester.pumpAndSettle();
      expect(saved.last.layout, ShiftBoardLayout.perSchedule);
      expect(saved.last.boardsFor(_schedules)[0].positions.map((p) => p.id), [
        'fc',
        'dt',
      ]);
    },
  );

  testWidgets('ShiftLayoutCustomizerDialog renders tiles and saves layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final saved = <ShiftConfig>[];
    const config = ShiftConfig(
      scheduleBoards: {
        'main': [_fc, _dt],
      },
    );
    final board = config.boardsFor(_schedules).first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShiftLayoutCustomizerDialog(
            config: config,
            board: board,
            schedules: _schedules,
            onSave: (c) async => saved.add(c),
          ),
        ),
      ),
    );

    expect(find.textContaining('Customize Tile Layout'), findsOneWidget);
    expect(find.text('Front Counter'), findsOneWidget);
    expect(find.text('Drive-thru'), findsOneWidget);

    // Save layout
    await tester.tap(find.text('Save Layout'));
    await tester.pumpAndSettle();
    expect(saved, isNotEmpty);
  });
}
