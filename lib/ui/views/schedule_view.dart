import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule_models.dart';
import '../../models/store_settings_model.dart';
import '../../models/user_model.dart';
import '../../providers/app_providers.dart';
import '../../services/schedule_repository.dart';
import 'schedule/schedule_common.dart';
import 'schedule/ai_build_controller.dart';
import 'schedule/ai_scheduler.dart';
import 'schedule/ai_terminal.dart';
import 'schedule/member_grid.dart';
import 'schedule/position_ops.dart';
import 'schedule/schedule_ops.dart';
import 'schedule/schedule_settings_dialog.dart';
import 'schedule/training_flow.dart';
import 'schedule/training_review_dialog.dart';
import 'schedule/requests_dialog.dart';
import 'schedule/shift_dialogs.dart';
import 'schedule/template_editor.dart';

class ScheduleView extends ConsumerStatefulWidget {
  const ScheduleView({super.key});

  @override
  ConsumerState<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends ConsumerState<ScheduleView> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FocusNode _focus = FocusNode();

  /// Timeline scale, shared with "Who can work" so a dragged person shows as
  /// a true-to-scale 6-hour shift.
  final ValueNotifier<double> _ppm = ValueNotifier(1.0);

  DateTime _date = dateOnly(DateTime.now());
  String? _selectedShiftId;
  bool _showAvailable = false;

  /// Width of the right-hand panel; drag the divider to change it.
  double _panelWidth = 340;

  bool _posting = false;

  // AI scheduler panel.
  bool _showAi = false;

  final Map<String, List<ScheduleDay>> _undo = {};

  @override
  void dispose() {
    _focus.dispose();
    _ppm.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data helpers
  // ---------------------------------------------------------------------------

  String get _storeId => ref.read(currentStoreIdProvider)!;

  /// The schedule being viewed (a store can have several).
  /// (Falls back to the main one if the selected schedule was removed.)
  String get _boardId =>
      _config.boardById(ref.read(selectedBoardProvider(_storeId))).id;

  ScheduleRepository get _repo =>
      ref.read(boardRepositoryProvider((storeId: _storeId, boardId: _boardId)));

  ScheduleConfig get _config =>
      ref.read(scheduleConfigProvider(_storeId)).valueOrNull ??
      const ScheduleConfig();

  DateTime get _weekStart => weekStartFor(_date, _config.weekStart);

  Map<String, ScheduleDay> get _week =>
      ref
          .read(
            scheduleWeekProvider((
              storeId: _storeId,
              weekStart: dateKey(_weekStart),
              boardId: _boardId,
            )),
          )
          .valueOrNull ??
      const {};

  ScheduleDay _dayFor(DateTime d) =>
      _week[dateKey(d)] ?? ScheduleDay.empty(dateKey(d));

  ScheduleDay get _day => _dayFor(_date);

  List<UserModel> get _allUsers =>
      ref.read(usersStreamProvider).valueOrNull ?? const [];

  Map<String, UserModel> get _usersById => {
    for (final u in _allUsers)
      if (u.id != null) u.id!: u,
  };

  /// Store titles in their order (new-hire title first).
  List<String> get _titleOrder =>
      (ref.read(storeSettingsProvider).valueOrNull?.titles ?? const [])
          .map((t) => t.name)
          .where((n) => n.isNotEmpty)
          .toList();

  /// Has [u] reached the schedule's minimum title (when that rule is on)?
  bool _meetsTitleRule(UserModel u) {
    final c = _config;
    if (!c.minTitleEnabled || c.minTitle == null) return true;
    final order = _titleOrder;
    final min = order.indexOf(c.minTitle!);
    if (min < 0) return true;
    final mine = u.title == null ? -1 : order.indexOf(u.title!);
    return mine >= min;
  }

  /// People who can go on this schedule: active, past the title rule, and
  /// in one of the schedule's team areas.
  List<UserModel> get _people => _peopleFor(_boardId);

  List<UserModel> _peopleFor(String boardId) {
    final board = _config.boardById(boardId);
    return _allUsers
        .where(
          (u) =>
              u.id != null &&
              isSchedulable(u) &&
              _meetsTitleRule(u) &&
              board.includesArea(u.position),
        )
        .toList()
      ..sort((a, b) => personName(a).compareTo(personName(b)));
  }

  /// Training-flow labels ("Shift 2 · Train on Register") for new hires on
  /// the current day.
  Map<String, String> _trainingLabels(String storeId) {
    final shiftConfig =
        ref.watch(shiftConfigProvider(storeId)).valueOrNull ??
        const ShiftConfig();
    final steps = trainingStepsFor(
      ref,
      storeId: storeId,
      boardId: _boardId,
      date: _date,
      people: _people,
      config: _config,
      titleOrder: _titleOrder,
    );
    return {
      for (final e in steps.entries) e.key: trainingLabel(e.value, shiftConfig),
    };
  }

  List<TimeOffEntry> get _timeOff =>
      ref.read(approvedTimeOffProvider(_storeId)).valueOrNull ?? const [];

  List<TimeOffEntry> get _pendingTimeOff =>
      ref.read(pendingTimeOffProvider(_storeId)).valueOrNull ?? const [];

  List<String> get _allTitles {
    final s = ref.read(storeSettingsProvider).valueOrNull;
    if (s == null) return const [];
    return {
      ...s.titles.map((t) => t.name),
      ...s.tags.map((t) => t.name),
    }.where((n) => n.isNotEmpty).toList();
  }

  /// Keeps the posted stamp and flags the day as changed since posting.
  ScheduleDay _stamp(ScheduleDay d) {
    final postedAt = _week[d.date]?.postedAt;
    return postedAt == null
        ? d
        : d.copyWith(postedAt: postedAt, editedAfterPost: true);
  }

  Future<void> _commit(ScheduleDay before, ScheduleDay after) async {
    after = _stamp(after);
    (_undo[after.date] ??= []).add(before);
    if (_undo[after.date]!.length > 50) _undo[after.date]!.removeAt(0);
    setState(() {
      if (_selectedShiftId != null &&
          after.shiftById(_selectedShiftId!) == null) {
        _selectedShiftId = null;
      }
    });
    try {
      await _repo.saveDay(after);
    } catch (e) {
      _snack('Could not save the schedule: $e');
    }
  }

  void _apply(ScheduleDay Function(ScheduleDay) change) {
    final before = _day;
    _commit(before, change(before));
  }

  Future<void> _undoLast() async {
    final stack = _undo[dateKey(_date)];
    if (stack == null || stack.isEmpty) return;
    final previous = stack.removeLast();
    setState(() => _selectedShiftId = null);
    try {
      await _repo.saveDay(_stamp(previous));
    } catch (e) {
      _snack('Could not undo: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _goToDate(DateTime d) => setState(() {
    _date = dateOnly(d);
    _selectedShiftId = null;
  });

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _editPiece(Shift shift, ShiftPiece piece) async {
    final result = await showPieceDialog(
      context,
      day: _day,
      date: _date,
      people: _people,
      usersById: _usersById,
      timeOff: _timeOff,
      rowId: piece.rowId,
      start: piece.start,
      end: piece.end,
      fixedUserId: shift.userId,
      editingPieceId: piece.id,
    );
    if (result == null) return;
    _apply(
      (d) => updatePiece(
        d,
        piece.id,
        rowId: result.rowId,
        start: result.start,
        end: result.end,
      ),
    );
  }

  Future<void> _splitPiece(Shift shift, ShiftPiece piece) async {
    final r = await showSplitDialog(
      context,
      day: _day,
      shift: shift,
      piece: piece,
      usersById: _usersById,
    );
    if (r == null) return;
    _apply(
      (d) => splitPiece(
        d,
        piece.id,
        at: r.at,
        moveLater: r.moveLater,
        targetRowId: r.targetRowId,
      ),
    );
  }

  Future<void> _setTrainee(Shift shift) async {
    final id = await showTraineeDialog(
      context,
      day: _day,
      shift: shift,
      people: _people,
      usersById: _usersById,
    );
    if (id == null) return;
    final problem = id.isEmpty ? null : _trainerProblem(shift.userId);
    if (problem != null) {
      _snack(problem);
      return;
    }
    _apply((d) => setTrainee(d, shift.id, id));
  }

  /// Why [userId] can't train under "Who can train", or null.
  String? _trainerProblem(String userId) {
    final user = _usersById[userId];
    if (canTrain(user, _config)) return null;
    return '${personName(user, short: true)} can\'t train '
        '(only ${_config.trainerTags.join(', ')}).';
  }

  /// Asks whether to also add [bar] to the day's template (row [lane] there,
  /// or a new row like [kind] when that row is missing or full at that time).
  Future<void> _offerTemplateUpdate({
    required int lane,
    required TimeWindow bar,
    required ScheduleRow? kind,
    required String where,
  }) async {
    final template = _currentTemplate;
    if (template == null) return;
    final update = await _confirm(
      'Update the "${template.name}" template too?',
      'Add ${formatRange(bar.start, bar.end, compact: false)} to $where of the '
          'template, so days built from it get this bar as well. Days that are '
          'already built won\'t change.',
      'Update template',
      cancel: 'Just this day',
    );
    if (!update) return;
    final rows = [...template.rows];
    final merged = lane < rows.length ? addBarToRow(rows[lane], bar) : null;
    if (merged != null) {
      rows[lane] = merged;
    } else {
      rows.add(
        ScheduleRow(
          id: newScheduleId(),
          label: kind?.label ?? '',
          allowedTitles: kind?.allowedTitles ?? const [],
          windows: [bar],
        ),
      );
    }
    try {
      await _repo.saveTemplate(
        template.copyWith(rows: rows),
        previousStoreIds: template.storeIds,
      );
      _snack('"${template.name}" updated.');
    } catch (e) {
      _snack('Could not update the template: $e');
    }
  }

  Future<void> _deleteShift(Shift shift) async {
    final ok = await _confirm(
      'Remove shift?',
      'Remove ${personName(_usersById[shift.userId])}\'s shift '
          '(${formatRange(shift.start, shift.end)}) from this day?',
      'Remove',
    );
    if (ok) _apply((d) => removeShift(d, shift.id));
  }

  Future<void> _addRow() async {
    final row = await showRowEditor(
      context,
      row: ScheduleRow(
        id: newScheduleId(),
        label: 'Extra',
        windows: const [TimeWindow(11 * 60, 14 * 60)],
      ),
      allTitles: _allTitles,
      title: 'Add a row to this day',
    );
    if (row == null) return;
    final lane = _day.rows.length;
    _apply((d) => addRow(d, row));
    for (final w in row.windows) {
      await _offerTemplateUpdate(
        lane: lane,
        bar: w,
        kind: row,
        where: 'a new row',
      );
    }
  }

  Future<void> _applyTemplate(ScheduleTemplate t) async {
    final day = _day;
    if (day.shifts.isNotEmpty &&
        !await _confirm(
          'Switch template?',
          'People already scheduled stay in the same row positions '
              '(row 1 → row 1…). Extra rows are kept if the new template has '
              'fewer rows.',
          'Apply "${t.name}"',
        )) {
      return;
    }
    _apply((d) => applyTemplate(d, t));
  }

  Future<void> _applyTemplateToWeek(ScheduleTemplate t) async {
    if (!await _confirm(
      'Use "${t.name}" for the whole week?',
      'Applies to all 7 days of this week. Days that already have people keep '
          'them in the same row positions.',
      'Apply to week',
    )) {
      return;
    }
    for (var i = 0; i < 7; i++) {
      final d = addDays(_weekStart, i);
      final before = _dayFor(d);
      await _commit(before, applyTemplate(before, t));
    }
  }

  Future<void> _clearShifts() async {
    if (!await _confirm(
      'Clear everyone from this day?',
      'Removes all shifts on ${_longDate(_date)}. The rows stay.',
      'Clear shifts',
    )) {
      return;
    }
    _apply((d) => d.copyWith(shifts: const []));
  }

  Future<void> _clearWeekShifts() async {
    final weekStart = _weekStart;
    final weekEnd = addDays(weekStart, 6);
    if (!await _confirm(
      'Clear everyone from this week?',
      'Removes all shifts from ${monthShort[weekStart.month - 1]} '
          '${weekStart.day} – ${monthShort[weekEnd.month - 1]} ${weekEnd.day}. '
          'Templates stay. You can undo each day with Ctrl/Cmd+Z.',
      'Clear week',
    )) {
      return;
    }
    for (var i = 0; i < 7; i++) {
      final before = _dayFor(addDays(weekStart, i));
      if (before.shifts.isEmpty) continue;
      await _commit(before, before.copyWith(shifts: const []));
    }
  }

  /// Gives each day of this week the template (needed bars) its weekday had
  /// last week. People already scheduled stay in the same row positions.
  Future<void> _copyLastWeeksTemplates() async {
    final weekStart = _weekStart;
    final last = await _repo.getWeek(addDays(weekStart, -7));
    final withTemplate = [
      for (var i = 0; i < 7; i++)
        if (last[dateKey(addDays(weekStart, i - 7))] case final d?
            when d.hasTemplate)
          (i, d),
    ];
    if (withTemplate.isEmpty) {
      _snack('Last week has no templates to copy.');
      return;
    }
    if (!mounted ||
        !await _confirm(
          'Copy last week\'s templates?',
          'Each day of this week gets the template its weekday had last week '
              '(${withTemplate.length} ${withTemplate.length == 1 ? 'day' : 'days'}). '
              'People already scheduled stay in the same row positions.',
          'Copy templates',
        )) {
      return;
    }
    for (final (i, prev) in withTemplate) {
      final before = _dayFor(addDays(weekStart, i));
      final copied = applyTemplate(
        before,
        ScheduleTemplate(
          id: prev.templateId ?? newScheduleId(),
          name: prev.templateName ?? 'Last week',
          rows: prev.rows,
        ),
      );
      await _commit(before, copied);
    }
    _snack('Copied ${withTemplate.length} templates from last week.');
  }

  Future<void> _openTemplates() => showTemplateManager(
    context,
    storeId: _storeId,
    allTitles: _allTitles,
    initialTemplateId: _day.templateId,
  );

  Future<void> _postWeek() async {
    final weekStart = _weekStart;
    final days = [for (var i = 0; i < 7; i++) _dayFor(addDays(weekStart, i))];
    final built = days.where((d) => d.hasTemplate).toList();
    final closed = [
      for (var i = 0; i < 7; i++)
        if (!days[i].hasTemplate)
          weekdayShort[addDays(weekStart, i).weekday - 1],
    ];
    final shiftCount = built.fold<int>(0, (a, d) => a + d.shifts.length);
    final reposting = built.any((d) => d.postedAt != null);
    final weekEnd = addDays(weekStart, 6);
    final short = [
      for (final d in built)
        if (shortages(d) case final list when list.isNotEmpty)
          '• ${weekdayShort[DateTime.parse(d.date).weekday - 1]} '
              '${DateTime.parse(d.date).day}: ${describeShortages(list)}',
    ];
    if (!await _confirm(
      short.isNotEmpty
          ? 'This week isn\'t fully staffed'
          : (reposting
                ? 'Repost this week\'s schedule?'
                : 'Post this week\'s schedule?'),
      '${short.isEmpty ? '' : 'These times are still short of people:\n${short.join('\n')}\n\n'}'
      'Week of ${monthShort[weekStart.month - 1]} ${weekStart.day} – '
      '${monthShort[weekEnd.month - 1]} ${weekEnd.day}: $shiftCount shifts '
      'across ${built.length} days. Team members will be able to see it.'
      '${closed.isEmpty ? '' : '\n\nNo template (posted as closed): ${closed.join(', ')}.'}'
      '${reposting ? '\n\nThis replaces the version posted earlier.' : ''}',
      short.isNotEmpty
          ? (reposting ? 'Repost anyway' : 'Post anyway')
          : (reposting ? 'Repost' : 'Post schedule'),
    )) {
      return;
    }
    setState(() => _posting = true);
    try {
      await _repo.postWeek(
        weekStart,
        built,
        postedBy: ref.read(currentUserProvider)?['id'] as String?,
      );
      // This week's requests join "From past weeks" for next time.
      ref
          .read(scheduleRepositoryProvider(_storeId))
          .rememberWeekRequests(dateKey(weekStart))
          .catchError((_) {});
      _snack('Schedule posted.');
    } catch (e) {
      _snack('Could not post the schedule: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  /// Every shift board's positions (for the training flow's position
  /// picker), named "Board · Position" when there's more than one board.
  List<ShiftPosition> _allBoardPositions() {
    final shiftConfig =
        ref.read(shiftConfigProvider(_storeId)).valueOrNull ??
        const ShiftConfig();
    final boards = shiftConfig.boardsFor(_config);
    final seen = <String>{};
    return [
      for (final b in boards)
        for (final p in b.positions)
          if (seen.add(p.id))
            ShiftPosition(
              id: p.id,
              name: boards.length > 1 ? '${b.name} · ${p.name}' : p.name,
            ),
    ];
  }

  Future<void> _openSettings() async {
    final updated = await showScheduleSettings(
      context,
      config: _config,
      titles: _titleOrder,
      tags: (ref.read(storeSettingsProvider).valueOrNull?.tags ?? const [])
          .map((t) => t.name)
          .where((n) => n.isNotEmpty)
          .toList(),
      teamAreas:
          ref.read(storeSettingsProvider).valueOrNull?.positions ?? const [],
      designations:
          ref.read(storeSettingsProvider).valueOrNull?.designations ?? const [],
      positions: _allBoardPositions(),
    );
    if (updated == null) return;
    try {
      await _repo.saveConfig(updated);
    } catch (e) {
      _snack('Could not save settings: $e');
    }
  }

  Future<bool> _confirm(
    String title,
    String body,
    String action, {
    String cancel = 'Cancel',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// For everyone with shifts this week: which of their shifts the selected
  /// day is (0 when they're off that day) and how many they have in total.
  Map<String, (int, int)> _weekShiftCounts(Map<String, ScheduleDay> week) {
    final days = <String, List<String>>{};
    for (final date in week.keys.toList()..sort()) {
      for (final uid in {
        for (final s in week[date]!.shifts) ...[s.userId, ?s.traineeId],
      }) {
        (days[uid] ??= []).add(date);
      }
    }
    final today = dateKey(_date);
    return {
      for (final e in days.entries)
        e.key: (e.value.indexOf(today) + 1, e.value.length),
    };
  }

  /// Hours each person works on the selected day and in the week (as a
  /// trainee too).
  Map<String, (double, double)> _weekHours(Map<String, ScheduleDay> week) {
    final today = dateKey(_date);
    final day = <String, int>{};
    final total = <String, int>{};
    for (final d in week.values) {
      for (final s in d.shifts) {
        for (final uid in [s.userId, ?s.traineeId]) {
          total[uid] = (total[uid] ?? 0) + s.minutes;
          if (d.date == today) day[uid] = (day[uid] ?? 0) + s.minutes;
        }
      }
    }
    return {
      for (final e in total.entries)
        e.key: ((day[e.key] ?? 0) / 60, e.value / 60),
    };
  }

  /// Team view: why [userId] can't have block [w] (replacing [old]).
  String? _blockProblem(String userId, TimeWindow? old, TimeWindow w) {
    final day = _day;
    final user = _usersById[userId];
    for (final s in day.shifts.where((s) => s.involves(userId))) {
      for (final b in shiftBlocks(s)) {
        if (s.userId == userId && b == old) continue;
        if (b.overlaps(w.start, w.end)) {
          return '${personName(user, short: true)} already works '
              '${formatRange(b.start, b.end)}';
        }
      }
    }
    String? unavailable(String? uid) => uid == null || uid.isEmpty
        ? null
        : availabilityConflict(
            _usersById[uid],
            date: _date,
            start: w.start,
            end: w.end,
            timeOff: _timeOff,
          );
    return unavailable(userId) ??
        unavailable(day.shiftForUser(userId)?.traineeId);
  }

  void _setBlock(String userId, TimeWindow? old, TimeWindow w) {
    final problem = _blockProblem(userId, old, w);
    if (problem != null) {
      _snack(problem);
      return;
    }
    _apply(
      (d) =>
          setPersonBlock(d, userId: userId, w: w, users: _usersById, old: old),
    );
  }

  ScheduleTemplate? get _currentTemplate {
    final id = _day.templateId;
    return (ref.read(scheduleTemplatesProvider(_storeId)).valueOrNull ??
            const <ScheduleTemplate>[])
        .where((t) => t.id == id)
        .firstOrNull;
  }

  // ---------------------------------------------------------------------------
  // AI scheduler
  // ---------------------------------------------------------------------------

  /// The week of schedule [boardId] as the AI sees it ([days] = its 7
  /// days). Everything is read from the page right away, so a build keeps
  /// working if you leave the Schedule page.
  AiWeekContext _aiContext(
    String boardId,
    List<ScheduleDay> days, {
    Map<String, Map<String, List<TimeWindow>>> busyElsewhere = const {},
    Map<String, List<int>> trainingRemaining = const {},
    ({Map<String, List<(int, TimeWindow)>> shifts, int weeks}) history = (
      shifts: const {},
      weeks: 0,
    ),
    List<String> instructions = const [],
    Map<String, List<(String, TimeWindow)>> keep = const {},
  }) {
    final config = _config;
    final people = _peopleFor(boardId);
    final ids = {for (final u in people) u.id};
    return AiWeekContext(
      weekStart: _weekStart,
      days: days,
      people: people,
      timeOff: _timeOff,
      requestedOff: _pendingTimeOff,
      config: config,
      // Its shift board's positions; a board that combines schedules is
      // deployed as a whole after the build instead.
      positions: switch ((ref.read(shiftConfigProvider(_storeId)).valueOrNull ??
              const ShiftConfig())
          .boardForSchedule(config, boardId)) {
        final b? when b.scheduleIds.length == 1 => b.positions,
        _ => const [],
      },
      titleOrder: _titleOrder,
      trainingRemaining: {
        for (final e in trainingRemaining.entries)
          if (ids.contains(e.key)) e.key: e.value,
      },
      busyElsewhere: busyElsewhere,
      history: history.shifts,
      historyWeeks: history.weeks,
      instructions: instructions,
      keep: keep,
    );
  }

  /// Weeks looked back at to keep the schedule consistent.
  static const _historyWeeks = 4;

  /// Shifts each person worked on schedule [boardId] in the last
  /// [_historyWeeks] weeks before [weekStart] (uid → (weekday, times)), and
  /// how many of those weeks had any shifts (a new store has fewer).
  Future<({Map<String, List<(int, TimeWindow)>> shifts, int weeks})>
  _recentShifts(String storeId, String boardId, DateTime weekStart) async {
    final out = <String, List<(int, TimeWindow)>>{};
    final weeks = <String>{};
    try {
      final days = await ref
          .read(boardRepositoryProvider((storeId: storeId, boardId: boardId)))
          .daysBetween(addDays(weekStart, -7 * _historyWeeks), weekStart);
      for (final d in days) {
        final weekday = DateTime.parse(d.date).weekday;
        if (d.shifts.isNotEmpty) {
          weeks.add(
            dateKey(weekStartFor(DateTime.parse(d.date), _config.weekStart)),
          );
        }
        for (final s in d.shifts) {
          for (final b in shiftBlocks(s)) {
            (out[s.userId] ??= []).add((weekday, b));
          }
        }
      }
    } catch (_) {
      // No history: the build just won't prefer anyone's usual shifts.
    }
    return (shifts: out, weeks: weeks.length);
  }

  /// Training review before a build: who's in training and which steps
  /// they've done (checked from the schedule since the last review). Saves
  /// the review and returns each trainee's remaining steps, or null when
  /// cancelled.
  Future<Map<String, List<int>>?> _reviewTraining(
    List<String> boards, {
    bool ask = true,
  }) async {
    final config = _config;
    if (!config.trainingFlowEnabled || config.trainingDays.isEmpty)
      return const {};
    final storeId = _storeId;
    final weekStart = _weekStart;
    final people = {
      for (final b in boards)
        for (final u in _peopleFor(b)) u.id!: u,
    }.values.toList();
    final repo = ref.read(scheduleRepositoryProvider(storeId));
    final shiftConfig =
        ref.read(shiftConfigProvider(storeId)).valueOrNull ??
        const ShiftConfig();

    final Map<String, TrainingProgress> saved;
    final worked = <String, Set<String>>{}; // uid → dates worked (any schedule)
    try {
      saved = await repo.getTrainingProgress();
      // Look back to the oldest review (or about half a year).
      var from = addDays(weekStart, -182);
      for (final p in saved.values) {
        final d = p.asOf == null ? null : DateTime.tryParse(p.asOf!);
        if (d != null && d.isBefore(from)) from = d;
      }
      for (final b in config.allBoards) {
        final byUid = await ref
            .read(boardRepositoryProvider((storeId: storeId, boardId: b.id)))
            .datesWorked(from, weekStart);
        byUid.forEach((uid, dates) => (worked[uid] ??= {}).addAll(dates));
      }
    } catch (e) {
      _snack('Could not load training progress: $e');
      return null;
    }
    // Days since each person's last review (or all of them, if none).
    final workedSince = {
      for (final u in people)
        u.id!: (worked[u.id] ?? const <String>{})
            .where(
              (d) =>
                  saved[u.id]?.asOf == null ||
                  d.compareTo(saved[u.id]!.asOf!) >= 0,
            )
            .length,
    };
    if (!mounted) return null;
    // Chat changes: use the saved review as it is (no dialog).
    if (!ask) {
      return {
        for (final u in people)
          if (saved[u.id] case final p? when !p.notInTraining)
            if (remainingTrainingSteps(
                  config.trainingDays.length,
                  p.done,
                  workedSince[u.id] ?? 0,
                )
                case final left when left.isNotEmpty)
              u.id!: left,
      };
    }
    final reviewed = await showTrainingReview(
      context,
      weekStart: weekStart,
      people: people,
      config: config,
      shiftConfig: shiftConfig,
      saved: saved,
      workedSince: workedSince,
    );
    if (reviewed == null) return null;
    try {
      await repo.saveTrainingProgress(reviewed.values);
    } catch (e) {
      _snack('Could not save training progress: $e');
    }
    return {
      for (final p in reviewed.values)
        if (!p.notInTraining)
          if (remainingTrainingSteps(config.trainingDays.length, p.done, 0)
              case final left when left.isNotEmpty)
            p.userId: left,
    };
  }

  static String _dayShort(ScheduleDay d) {
    final date = DateTime.parse(d.date);
    return '${weekdayShort[date.weekday - 1]} ${date.day}';
  }

  /// What building [days] would do, for the confirm dialogs.
  static ({
    List<ScheduleDay> build,
    List<ScheduleDay> skip,
    List<ScheduleDay> replace,
  })
  _buildPlan(List<ScheduleDay> days) {
    final build = days.where((d) => d.hasTemplate).toList();
    return (
      build: build,
      skip: days.where((d) => !d.hasTemplate).toList(),
      replace: build.where((d) => d.shifts.isNotEmpty).toList(),
    );
  }

  Future<void> _aiBuild() async {
    final controller = ref.read(aiBuildProvider.notifier);
    if (ref.read(aiBuildProvider).busy) return;
    final weekStart = _weekStart;
    final config = _config;
    final currentBoard = _boardId;
    final storeId = _storeId;

    // This week of every schedule.
    final weeks = <String, List<ScheduleDay>>{};
    for (final b in config.allBoards) {
      final saved = b.id == currentBoard
          ? _week
          : await ref
                .read(
                  boardRepositoryProvider((storeId: storeId, boardId: b.id)),
                )
                .getWeek(weekStart);
      weeks[b.id] = [
        for (var i = 0; i < 7; i++)
          saved[dateKey(addDays(weekStart, i))] ??
              ScheduleDay.empty(dateKey(addDays(weekStart, i))),
      ];
    }
    if (!mounted) return;

    final List<String> boards;
    if (config.allBoards.length > 1) {
      final picked = await _pickBoardsToBuild(config, weeks, currentBoard);
      if (picked == null || picked.isEmpty) return;
      boards = picked;
    } else {
      final plan = _buildPlan(weeks[currentBoard]!);
      if (plan.build.isEmpty) {
        await _confirm(
          'No templates this week',
          'Pick a template for at least one day of this week first. The AI only '
              'builds days that have a template.',
          'OK',
        );
        return;
      }
      if (plan.skip.isNotEmpty || plan.replace.isNotEmpty) {
        final body = [
          if (plan.skip.isNotEmpty)
            'It will only generate a schedule for the days that have a template: '
                '${plan.build.map(_dayShort).join(', ')}.\n\n'
                'No template (skipped): ${plan.skip.map(_dayShort).join(', ')}.',
          if (plan.replace.isNotEmpty)
            'Shifts already on ${plan.replace.map(_dayShort).join(', ')} will be '
                'replaced. You can undo each day with Ctrl/Cmd+Z.',
        ].join('\n\n');
        if (!await _confirm(
          plan.skip.isNotEmpty
              ? 'Only days with a template'
              : 'Replace shifts?',
          body,
          'Continue',
        )) {
          return;
        }
      }
      boards = [currentBoard];
    }
    if (!mounted) return;

    final trainingRemaining = await _reviewTraining(boards);
    if (trainingRemaining == null || !mounted) return;
    final key = _instructionsKey(storeId, weekStart);
    final storeRepo = ref.read(scheduleRepositoryProvider(storeId));
    var saved = (week: controller.requestsFor(key), past: const <String>[]);
    try {
      final r = await storeRepo.getRequests(dateKey(weekStart));
      saved = (week: saved.week.isNotEmpty ? saved.week : r.week, past: r.past);
    } catch (_) {
      // Not loaded: just no suggestions.
    }
    if (!mounted) return;
    final asked = await showRequestsDialog(
      context,
      previous: saved.week,
      past: saved.past,
      onForget: (t) => storeRepo.forgetPastRequest(t).catchError((_) {}),
    );
    if (asked == null || !mounted) return;
    controller.setRequests(key, asked);
    storeRepo.saveWeekRequests(dateKey(weekStart), asked).catchError((_) {});
    await _runBuild(
      boards: boards,
      weeks: weeks,
      trainingRemaining: trainingRemaining,
      instructions: asked,
    );
  }

  /// Instructions are kept per store and week, so chat changes build on what
  /// was asked before.
  static String _instructionsKey(String storeId, DateTime weekStart) =>
      '$storeId|${dateKey(weekStart)}';

  /// A change asked for in the terminal chat: rebuilds the schedule on
  /// screen with it, keeping as much of the week as it can.
  Future<void> _aiChange(String request) async {
    final controller = ref.read(aiBuildProvider.notifier);
    if (ref.read(aiBuildProvider).busy || request.trim().isEmpty) return;
    final weekStart = _weekStart;
    final config = _config;
    final boardId = _boardId;
    final storeId = _storeId;
    final weeks = <String, List<ScheduleDay>>{};
    for (final b in config.allBoards) {
      final saved = b.id == boardId
          ? _week
          : await ref
                .read(
                  boardRepositoryProvider((storeId: storeId, boardId: b.id)),
                )
                .getWeek(weekStart);
      weeks[b.id] = [
        for (var i = 0; i < 7; i++)
          saved[dateKey(addDays(weekStart, i))] ??
              ScheduleDay.empty(dateKey(addDays(weekStart, i))),
      ];
    }
    if (!weeks[boardId]!.any((d) => d.hasTemplate)) {
      _snack('This week has no templates to change.');
      return;
    }
    final trainingRemaining = await _reviewTraining([boardId], ask: false);
    if (trainingRemaining == null || !mounted) return;
    final key = _instructionsKey(storeId, weekStart);
    var before = controller.requestsFor(key);
    if (before.isEmpty) {
      try {
        before =
            (await ref
                    .read(scheduleRepositoryProvider(storeId))
                    .getRequests(dateKey(weekStart)))
                .week;
      } catch (_) {}
    }
    final instructions = [...before, request.trim()];
    controller.setRequests(key, instructions);
    await _runBuild(
      boards: [boardId],
      weeks: weeks,
      trainingRemaining: trainingRemaining,
      instructions: instructions,
      request: request.trim(),
    );
  }

  /// Builds [boards] for the week on screen and saves them. With a chat
  /// [request], keeps the current schedule as much as it can. Afterwards the
  /// terminal offers to undo it.
  Future<void> _runBuild({
    required List<String> boards,
    required Map<String, List<ScheduleDay>> weeks,
    required Map<String, List<int>> trainingRemaining,
    required List<String> instructions,
    String? request,
  }) async {
    final controller = ref.read(aiBuildProvider.notifier);
    final weekStart = _weekStart;
    final config = _config;
    final storeId = _storeId;
    final history = {
      for (final b in boards) b: await _recentShifts(storeId, b, weekStart),
    };
    if (!mounted) return;

    // Read everything from the page now; the build may outlive it.
    final users = _usersById;
    final shiftBoards =
        (ref.read(shiftConfigProvider(storeId)).valueOrNull ??
                const ShiftConfig())
            .boardsFor(config);
    // The schedule as it is now (chat changes keep as much as they can).
    Map<String, List<(String, TimeWindow)>> keepOf(String boardId) {
      final out = <String, List<(String, TimeWindow)>>{};
      if (request == null) return out;
      for (final d in weeks[boardId]!) {
        for (final s in d.shifts) {
          for (final uid in [s.userId, ?s.traineeId]) {
            for (final b in shiftBlocks(s)) {
              (out[uid] ??= []).add((d.date, b));
            }
          }
        }
      }
      return out;
    }

    // Who works on the other schedules (filled in just before each build,
    // so a schedule built earlier in this run counts).
    final busy = {
      for (final b in boards) b: <String, Map<String, List<TimeWindow>>>{},
    };
    final contexts = {
      for (final b in boards)
        b: _aiContext(
          b,
          weeks[b]!,
          busyElsewhere: busy[b]!,
          trainingRemaining: trainingRemaining,
          history: history[b]!,
          instructions: instructions,
          keep: keepOf(b),
        ),
    };
    final built = <String>{};
    void fillBusy(String boardId) {
      final map = busy[boardId]!..clear();
      for (final entry in weeks.entries) {
        if (entry.key == boardId) continue;
        // A schedule still waiting to be rebuilt in this run: its template
        // days are about to be replaced, so they don't count.
        final pending =
            boards.contains(entry.key) && !built.contains(entry.key);
        for (final d in entry.value) {
          if (pending && d.hasTemplate) continue;
          for (final s in d.shifts) {
            for (final uid in [s.userId, ?s.traineeId]) {
              ((map[uid] ??= {})[d.date] ??= []).addAll(shiftBlocks(s));
            }
          }
        }
      }
    }

    // Each day as it was before this run (for undo), the first time it's saved.
    final before = <String, (ScheduleRepository, ScheduleDay)>{};
    Future<void> save(String boardId, ScheduleDay day, ScheduleDay old) async {
      final repo = ref.read(
        boardRepositoryProvider((storeId: storeId, boardId: boardId)),
      );
      before.putIfAbsent('$boardId|${day.date}', () => (repo, old));
      await repo.saveDay(day);
    }

    await controller.run((log) async {
      if (request != null) log((kind: AiLineKind.user, text: request));
      for (final boardId in boards) {
        final board = config.boardById(boardId);
        log((
          kind: AiLineKind.command,
          text:
              '${request == null ? 'build' : 'change'} schedule'
              '${boards.length > 1 || config.allBoards.length > 1 ? ' "${board.name}"' : ''} '
              '--week ${monthShort[weekStart.month - 1]} ${weekStart.day}',
        ));
        fillBusy(boardId);
        final ctx = contexts[boardId]!;
        final old = {for (final d in weeks[boardId]!) d.date: d};
        final result = await AiScheduler().buildWeek(
          ctx,
          users: users,
          log: log,
        );
        built.add(boardId);
        weeks[boardId] = [for (final d in weeks[boardId]!) result[d.date] ?? d];
        for (final date in result.keys.toList()..sort()) {
          final was = old[date] ?? ScheduleDay.empty(date);
          var day = result[date]!;
          if (was.postedAt != null) {
            day = day.copyWith(postedAt: was.postedAt, editedAfterPost: true);
          }
          await save(boardId, day, was);
          // Ctrl/Cmd+Z only covers the schedule on screen.
          if (mounted && _boardId == boardId) {
            setState(() => (_undo[date] ??= []).add(was));
          }
        }
        if (result.isNotEmpty) {
          log((
            kind: AiLineKind.success,
            text: boards.length > 1
                ? '${board.name} saved.'
                : 'Saved. Positions are on the Shift page.',
          ));
        }
      }
      // Shift boards that combine schedules: deploy their positions across
      // all of the board's shifts together.
      for (final sb in shiftBoards) {
        if (sb.scheduleIds.length < 2 || !sb.scheduleIds.any(built.contains))
          continue;
        var days = 0;
        for (var i = 0; i < 7; i++) {
          final date = dateKey(addDays(weekStart, i));
          final sources = {
            for (final sid in sb.scheduleIds)
              sid:
                  (weeks[sid] ?? const <ScheduleDay>[])
                      .where((d) => d.date == date)
                      .firstOrNull ??
                  ScheduleDay.empty(date),
          };
          final rebuilt = sb.scheduleIds.any(
            (sid) => built.contains(sid) && sources[sid]!.hasTemplate,
          );
          if (!rebuilt) continue;
          final m = mergeBoardDay(date, sources);
          final parts = splitBoardDay(
            deployPositions(m.day, sb.positions),
            sources,
            m.origin,
          );
          for (final e in parts.entries) {
            if (jsonEncode(e.value.toJson()) ==
                jsonEncode(sources[e.key]!.toJson()))
              continue;
            await save(e.key, e.value, sources[e.key]!);
            weeks[e.key] = [
              for (final d in weeks[e.key] ?? const <ScheduleDay>[])
                d.date == date ? e.value : d,
            ];
          }
          days++;
        }
        if (days > 0) {
          log((
            kind: AiLineKind.success,
            text:
                'Deployed positions on the ${sb.name} board (${sb.scheduleIds.length} schedules together).',
          ));
        }
      }
      if (boards.length > 1) {
        log((
          kind: AiLineKind.success,
          text: 'Done. Positions are on the Shift page.',
        ));
      }
    });

    if (before.isNotEmpty) {
      final restore = before.values.toList();
      controller.setUndo(
        request == null ? 'the AI build' : 'that change',
        () async {
          for (final (repo, day) in restore) {
            await repo.saveDay(day);
          }
          if (mounted) setState(() => _undo.clear());
        },
      );
    }
  }

  /// Undo from the terminal: asks first, then puts back what the last AI
  /// build or change replaced.
  Future<void> _confirmAiUndo() async {
    final label = ref.read(aiBuildProvider).undoLabel;
    if (label == null) return;
    if (!await _confirm(
      'Undo $label?',
      'The schedule goes back to how it was before $label.',
      'Undo',
    )) {
      return;
    }
    await ref.read(aiBuildProvider.notifier).undo();
  }

  /// Asks which schedules to build this week. Returns their ids, or null.
  Future<List<String>?> _pickBoardsToBuild(
    ScheduleConfig config,
    Map<String, List<ScheduleDay>> weeks,
    String currentBoard,
  ) {
    final buildable = {
      for (final b in config.allBoards)
        if (_buildPlan(weeks[b.id]!).build.isNotEmpty) b.id,
    };
    final selected = <String>{
      if (buildable.contains(currentBoard))
        currentBoard
      else
        ...buildable.take(1),
    };
    final ws = _weekStart;
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final theme = Theme.of(ctx);
          final muted = theme.textTheme.bodySmall?.color;
          return AlertDialog(
            backgroundColor: theme.cardColor,
            title: Text(
              'Build schedules · week of ${monthShort[ws.month - 1]} ${ws.day}',
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Pick the schedules to build. Each one only builds the '
                      'days that have a template.',
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                    const SizedBox(height: 12),
                    for (final b in config.allBoards)
                      () {
                        final plan = _buildPlan(weeks[b.id]!);
                        final can = buildable.contains(b.id);
                        final lines = [
                          if (!can)
                            'No templates this week'
                          else
                            'Builds ${plan.build.map(_dayShort).join(', ')}',
                          if (can && plan.skip.isNotEmpty)
                            'No template (skipped): ${plan.skip.map(_dayShort).join(', ')}',
                          if (can && plan.replace.isNotEmpty)
                            'Replaces shifts on ${plan.replace.map(_dayShort).join(', ')}',
                        ];
                        return CheckboxListTile(
                          value: selected.contains(b.id),
                          onChanged: can
                              ? (v) => setDialog(() {
                                  if (v == true) {
                                    selected.add(b.id);
                                  } else {
                                    selected.remove(b.id);
                                  }
                                })
                              : null,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(b.name),
                          subtitle: Text(
                            lines.join('\n'),
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        );
                      }(),
                    if (selected.any(
                      (id) => _buildPlan(weeks[id]!).replace.isNotEmpty,
                    )) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Replaced days on the schedule you\'re viewing can be '
                        'undone with Ctrl/Cmd+Z.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, [
                        for (final b in config.allBoards)
                          if (selected.contains(b.id)) b.id,
                      ]),
                child: Text(
                  selected.length > 1
                      ? 'Build ${selected.length} schedules'
                      : 'Build',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storeId = ref.watch(currentStoreIdProvider);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      endDrawer: _buildTimeOffDrawer(context),
      body: storeId == null
          ? _buildPickStore(theme)
          : _buildScheduler(context, theme, storeId),
    );
  }

  Widget _buildPickStore(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.store_outlined,
            size: 52,
            color: theme.textTheme.bodySmall?.color,
          ),
          const SizedBox(height: 12),
          Text(
            'Choose a store to build its schedule',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Schedules are built per store. Pick one from the store menu in the sidebar.',
            style: TextStyle(color: theme.textTheme.bodySmall?.color),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduler(
    BuildContext context,
    ThemeData theme,
    String storeId,
  ) {
    // Watch everything this screen depends on so it rebuilds live.
    final config =
        ref.watch(scheduleConfigProvider(storeId)).valueOrNull ??
        const ScheduleConfig();
    final weekStart = weekStartFor(_date, config.weekStart);
    final weekAsync = ref.watch(
      scheduleWeekProvider((
        storeId: storeId,
        weekStart: dateKey(weekStart),
        boardId: config.boardById(ref.watch(selectedBoardProvider(storeId))).id,
      )),
    );
    final templates =
        ref.watch(scheduleTemplatesProvider(storeId)).valueOrNull ??
        const <ScheduleTemplate>[];
    ref.watch(usersStreamProvider);
    ref.watch(approvedTimeOffProvider(storeId));
    ref.watch(pendingTimeOffProvider(storeId));
    final settings = ref.watch(storeSettingsProvider).valueOrNull;
    final pendingCount =
        ref.watch(allPendingTimeOffRequestsProvider).valueOrNull?.length ?? 0;

    final week = weekAsync.valueOrNull ?? const <String, ScheduleDay>{};
    final day = week[dateKey(_date)] ?? ScheduleDay.empty(dateKey(_date));
    final usersById = _usersById;
    final warnings = dayWarnings(
      day,
      date: _date,
      users: usersById,
      timeOff: _timeOff,
    );
    final selected = _selectedShiftId == null
        ? null
        : day.shiftById(_selectedShiftId!);
    final available = availablePeople(
      day,
      date: _date,
      people: _people,
      timeOff: [..._timeOff, ..._pendingTimeOff],
    );
    final trainingLabels = _trainingLabels(storeId);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _undoLast,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undoLast,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(() => _selectedShiftId = null),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _goToDate(addDays(_date, -1)),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _goToDate(addDays(_date, 1)),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: _scrollIfSmall(
          minWidth: 760,
          minHeight: 460,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _scrollIfNarrow(
                  1080,
                  _buildTopBar(theme, weekStart, week, pendingCount),
                ),
                const SizedBox(height: 6),
                _scrollIfNarrow(
                  1080,
                  _buildDayToolbar(
                    theme,
                    day,
                    templates,
                    available.people.length,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: weekAsync.isLoading && week.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : !day.hasTemplate
                              ? _buildNoTemplate(theme, templates)
                              : MemberScheduleGrid(
                                  day: day,
                                  date: _date,
                                  people: _people,
                                  users: usersById,
                                  settings: settings,
                                  timeOff: _timeOff,
                                  requestedOff: _pendingTimeOff,
                                  selectedShiftId: _selectedShiftId,
                                  warnings: warnings,
                                  onSelectShift: (id) =>
                                      setState(() => _selectedShiftId = id),
                                  blockProblem: _blockProblem,
                                  onSetBlock: _setBlock,
                                  trainingLabels: trainingLabels,
                                  weekShifts: _weekShiftCounts(week),
                                  weekHours: _weekHours(week),
                                  pixelsPerMinute: _ppm,
                                ),
                        ),
                      ),
                      if (selected != null || _showAvailable || _showAi) ...[
                        _PanelDivider(
                          onDrag: (dx) => setState(
                            () => _panelWidth = (_panelWidth - dx)
                                .clamp(260.0, 640.0)
                                .toDouble(),
                          ),
                        ),
                        SizedBox(
                          width: _panelWidth,
                          child: selected != null
                              ? _ShiftPanel(
                                  day: day,
                                  shift: selected,
                                  usersById: usersById,
                                  settings: settings,
                                  warnings: warnings,
                                  onClose: () =>
                                      setState(() => _selectedShiftId = null),
                                  onEditPiece: (p) => _editPiece(selected, p),
                                  onSplitPiece: (p) => _splitPiece(selected, p),
                                  onRemovePiece: (p) =>
                                      _apply((d) => removePiece(d, p.id)),
                                  onAddPiece: () {
                                    final s = selected.end;
                                    _setBlock(
                                      selected.userId,
                                      null,
                                      TimeWindow(
                                        s,
                                        (s + 120)
                                            .clamp(0, kMaxScheduleMinute)
                                            .toInt(),
                                      ),
                                    );
                                  },
                                  onTrainee: () => _setTrainee(selected),
                                  onDelete: () => _deleteShift(selected),
                                )
                              : _showAi
                              ? AiTerminalPanel(
                                  lines: ref.watch(aiBuildProvider).lines,
                                  busy: ref.watch(aiBuildProvider).busy,
                                  weekLabel:
                                      '${monthShort[weekStart.month - 1]} ${weekStart.day}',
                                  onBuild: _aiBuild,
                                  undoLabel: ref
                                      .watch(aiBuildProvider)
                                      .undoLabel,
                                  onUndo: _confirmAiUndo,
                                  onSend:
                                      _week.values.any(
                                        (d) => d.shifts.isNotEmpty,
                                      )
                                      ? _aiChange
                                      : null,
                                  onClear: () => ref
                                      .read(aiBuildProvider.notifier)
                                      .clear(),
                                  onClose: () =>
                                      setState(() => _showAi = false),
                                )
                              : _WhoCanWorkPanel(
                                  key: ValueKey(dateKey(_date)),
                                  trainingLabels: trainingLabels,
                                  day: day,
                                  available: available.people,
                                  timeOff: available.timeOff,
                                  hiddenUnavailable: available.unavailable,
                                  usersById: usersById,
                                  settings: settings,
                                  pixelsPerMinute: _ppm,
                                  onSelectShift: (id) =>
                                      setState(() => _selectedShiftId = id),
                                  onClose: () =>
                                      setState(() => _showAvailable = false),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps the page at least [minWidth] × [minHeight] and scrolls when the
  /// window is smaller, so nothing gets squeezed until it overflows.
  Widget _scrollIfSmall({
    required double minWidth,
    required double minHeight,
    required Widget child,
  }) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth < minWidth ? minWidth : c.maxWidth;
      final h = c.maxHeight < minHeight ? minHeight : c.maxHeight;
      Widget out = SizedBox(width: w, height: h, child: child);
      if (h > c.maxHeight) out = SingleChildScrollView(child: out);
      if (w > c.maxWidth) {
        out = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: out,
        );
      }
      return out;
    },
  );

  /// Lays [child] out at [minWidth] and scrolls it sideways when the page is
  /// narrower than that (instead of overflowing).
  Widget _scrollIfNarrow(double minWidth, Widget child) => LayoutBuilder(
    builder: (context, c) => c.maxWidth >= minWidth
        ? child
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: minWidth, child: child),
          ),
  );

  /// Week nav, the day tiles and the page actions, all on one line.
  Widget _buildTopBar(
    ThemeData theme,
    DateTime weekStart,
    Map<String, ScheduleDay> week,
    int pendingCount,
  ) {
    final undoCount = _undo[dateKey(_date)]?.length ?? 0;
    final today = dateOnly(DateTime.now());
    final weekEnd = addDays(weekStart, 6);
    final labor = week.values.fold<double>(0, (a, d) => a + d.laborHours);
    final open = week.values.fold<double>(0, (a, d) => a + d.openHours);
    final range = weekStart.month == weekEnd.month
        ? '${monthShort[weekStart.month - 1]} ${weekStart.day} – ${weekEnd.day}'
        : '${monthShort[weekStart.month - 1]} ${weekStart.day} – '
              '${monthShort[weekEnd.month - 1]} ${weekEnd.day}';
    final boards = _config.allBoards;
    return Row(
      children: [
        if (boards.length > 1) ...[
          BoardSwitcher(
            boards: [for (final b in boards) (id: b.id, name: b.name)],
            selectedId: _boardId,
            onChanged: (id) => setState(() {
              ref.read(selectedBoardProvider(_storeId).notifier).state = id;
              // Undo history belongs to the schedule it was made on.
              _undo.clear();
              _selectedShiftId = null;
            }),
          ),
          const SizedBox(width: 8),
        ],
        IconButton(
          tooltip: 'Previous week',
          visualDensity: VisualDensity.compact,
          onPressed: () => _goToDate(addDays(_date, -7)),
          icon: const Icon(Icons.chevron_left),
        ),
        Tooltip(
          message: 'Week of $range, ${weekEnd.year}',
          child: Text(
            range,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next week',
          visualDensity: VisualDensity.compact,
          onPressed: () => _goToDate(addDays(_date, 7)),
          icon: const Icon(Icons.chevron_right),
        ),
        TextButton(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => _goToDate(DateTime.now()),
          child: const Text('Today'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Builder(
                      builder: (context) {
                        final d = addDays(weekStart, i);
                        final saved = week[dateKey(d)];
                        return _DayTab(
                          date: d,
                          selected: d == _date,
                          isToday: d == today,
                          laborHours: saved?.laborHours ?? 0,
                          openHours: saved?.openHours ?? 0,
                          hasTemplate: saved?.hasTemplate ?? false,
                          onTap: () => _goToDate(d),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _StatChip(label: 'Week', value: '${formatHours(labor)} hrs'),
        const SizedBox(width: 6),
        _StatChip(
          label: 'Open',
          value: '${formatHours(open)} hrs',
          color: open > 0 ? AppTheme.red : AppTheme.green,
        ),
        const SizedBox(width: 8),
        _buildPostButton(week),
        const SizedBox(width: 6),
        if (undoCount > 0)
          IconButton(
            tooltip: 'Undo (Ctrl/Cmd+Z)',
            visualDensity: VisualDensity.compact,
            onPressed: _undoLast,
            icon: const Icon(Icons.undo),
          ),
        IconButton(
          tooltip: 'Templates',
          visualDensity: VisualDensity.compact,
          onPressed: _openTemplates,
          icon: const Icon(Icons.table_chart),
        ),
        IconButton(
          tooltip: 'Schedule settings',
          visualDensity: VisualDensity.compact,
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount'),
          backgroundColor: AppTheme.primaryRed,
          child: IconButton(
            tooltip: 'Time-off requests',
            visualDensity: VisualDensity.compact,
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: const Icon(Icons.event_busy),
          ),
        ),
      ],
    );
  }

  /// "Post schedule" once every slot this week is filled; "Posted" after.
  Widget _buildPostButton(Map<String, ScheduleDay> week) {
    final built = week.values.where((d) => d.hasTemplate).toList();
    final open = built.fold<double>(0, (a, d) => a + d.openHours);
    final everPosted = built.any((d) => d.postedAt != null);
    final posted = built.isNotEmpty && built.every((d) => d.isPosted);
    if (posted) {
      return Tooltip(
        message: 'This week is posted. Changes will need to be reposted.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.accent2.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.accent2.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 16, color: AppTheme.accent2),
              SizedBox(width: 6),
              Text(
                'Posted',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent2,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final label = everPosted ? 'Repost' : 'Post schedule';
    final ready = built.isNotEmpty && !_posting;
    return Tooltip(
      message: built.isEmpty
          ? 'Build the week first'
          : (open > 0
                ? 'Not fully staffed (${formatHours(open)} hrs open). You can '
                      'still post it.'
                : (everPosted
                      ? 'This week changed since it was posted'
                      : 'Post this week so the team can see it')),
      child: FilledButton.icon(
        onPressed: ready ? _postWeek : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
        icon: _posting
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.campaign, size: 18),
        label: Text(label),
      ),
    );
  }

  Widget _buildDayToolbar(
    ThemeData theme,
    ScheduleDay day,
    List<ScheduleTemplate> templates,
    int availableCount,
  ) {
    final current = templates.where((t) => t.id == day.templateId).firstOrNull;
    return Row(
      children: [
        Text(
          _longDate(_date),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: theme.textTheme.titleLarge?.color,
          ),
        ),
        const SizedBox(width: 16),
        PopupMenuButton<String>(
          tooltip: 'Choose a template for this day',
          color: theme.cardColor,
          onSelected: (v) {
            if (v == '__manage') {
              _openTemplates();
            } else if (v == '__week') {
              if (current != null) _applyTemplateToWeek(current);
            } else {
              final t = templates.where((t) => t.id == v).firstOrNull;
              if (t != null) _applyTemplate(t);
            }
          },
          itemBuilder: (_) => [
            for (final t in templates)
              PopupMenuItem(
                value: t.id,
                child: Row(
                  children: [
                    t.id == day.templateId
                        ? const Icon(Icons.check, size: 16)
                        : const Icon(Icons.table_chart, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.name)),
                    Text(
                      '${t.rows.length} rows',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            if (templates.isNotEmpty) const PopupMenuDivider(),
            PopupMenuItem(
              value: '__week',
              enabled: current != null,
              child: Text(
                current == null
                    ? 'Use this day\'s template for the whole week'
                    : 'Use "${current.name}" for the whole week',
              ),
            ),
            const PopupMenuItem(
              value: '__manage',
              child: Text('Create / edit templates…'),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.table_chart, size: 16),
                const SizedBox(width: 8),
                Text(
                  day.templateName ?? 'Pick a template',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (day.hasTemplate) ...[
          TextButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add row'),
          ),
        ],
        PopupMenuButton<String>(
          tooltip: 'More',
          color: theme.cardColor,
          icon: const Icon(Icons.more_horiz),
          onSelected: (v) {
            if (v == 'clear') _clearShifts();
            if (v == 'clear_week') _clearWeekShifts();
            if (v == 'copy_templates') _copyLastWeeksTemplates();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'clear',
              enabled: day.shifts.isNotEmpty,
              child: const Text('Clear all shifts on this day'),
            ),
            const PopupMenuItem(
              value: 'clear_week',
              child: Text('Clear all shifts this week'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'copy_templates',
              child: Text('Copy templates from last week'),
            ),
          ],
        ),
        const Spacer(),
        _StatChip(label: 'Labor', value: '${formatHours(day.laborHours)} hrs'),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Needed',
          value: '${formatHours(day.neededHours)} hrs',
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Open',
          value: '${formatHours(day.openHours)} hrs',
          color: day.openHours > 0 ? AppTheme.red : AppTheme.green,
        ),
        const SizedBox(width: 8),
        _StatChip(label: 'People', value: '${day.shifts.length}'),
        const SizedBox(width: 10),
        _PanelToggle(
          tooltip: 'AI scheduler',
          icon: const Icon(Icons.auto_awesome_rounded),
          count: 0,
          active: _showAi,
          onPressed: () => setState(() {
            _showAi = !_showAi;
            if (_showAi) {
              _showAvailable = false;
              _selectedShiftId = null;
            }
          }),
        ),
        _PanelToggle(
          tooltip: 'Who can work (drag onto the schedule)',
          icon: const Icon(Icons.person_add),
          count: availableCount,
          active: _showAvailable,
          onPressed: () => setState(() {
            _showAvailable = !_showAvailable;
            if (_showAvailable) {
              _showAi = false;
              _selectedShiftId = null;
            }
          }),
        ),
      ],
    );
  }

  Widget _buildNoTemplate(ThemeData theme, List<ScheduleTemplate> templates) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.table_chart,
              size: 52,
              color: theme.textTheme.bodySmall?.color,
            ),
            const SizedBox(height: 12),
            Text(
              'Pick a template for ${_longDate(_date)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              templates.isEmpty
                  ? 'Templates set the rows (slots) that need filling. Create '
                        'your first one to start building the schedule.'
                  : 'The template sets the rows (slots) that need filling. You '
                        'can still tweak rows for this day afterwards.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.textTheme.bodySmall?.color),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in templates)
                  OutlinedButton(
                    onPressed: () => _applyTemplate(t),
                    child: Text(t.name),
                  ),
                FilledButton.icon(
                  onPressed: _openTemplates,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(
                    templates.isEmpty ? 'Create a template' : 'New template',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _longDate(DateTime d) =>
      '${weekdayNames[d.weekday - 1]}, ${monthNames[d.month - 1]} ${d.day}';

  // ---------------------------------------------------------------------------
  // Time-off drawer (kept from the previous Schedule page)
  // ---------------------------------------------------------------------------

  Widget _buildTimeOffDrawer(BuildContext context) {
    final pendingRequestsAsync = ref.watch(allPendingTimeOffRequestsProvider);
    final usersAsync = ref.watch(usersStreamProvider);
    return Drawer(
      backgroundColor: Theme.of(context).cardColor,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: const Center(
              child: Text(
                'Pending Requests',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: pendingRequestsAsync.when(
              data: (requests) {
                if (requests.isEmpty) {
                  return const Center(child: Text('No pending requests.'));
                }
                return usersAsync.when(
                  data: (users) => ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final req = requests[index];
                      final userId = req['user_id'] as String?;
                      final user = users
                          .where((u) => u.id == userId)
                          .firstOrNull;
                      final name = user != null
                          ? '${user.firstName} ${user.lastName}'
                          : 'Unknown User';
                      final date = '${req['start_date']} - ${req['end_date']}';
                      final reason = req['reason'] ?? 'No reason provided';
                      return _buildRequestCard(
                        context,
                        req['id'],
                        name,
                        date,
                        reason,
                      );
                    },
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, st) =>
                      const Center(child: Text('Error loading users.')),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) =>
                  const Center(child: Text('Error loading requests.')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(
    BuildContext context,
    String requestId,
    String name,
    String date,
    String reason,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              date,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            Text(
              reason,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(firestoreServiceProvider)
                      .updateTimeOffRequestStatus(requestId, 'denied'),
                  child: const Text(
                    'Deny',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => ref
                      .read(firestoreServiceProvider)
                      .updateTimeOffRequestStatus(requestId, 'approved'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text(
                    'Approve',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Small widgets
// =============================================================================

/// The draggable line between the schedule and the right-hand panel.
class _PanelDivider extends StatelessWidget {
  final ValueChanged<double> onDrag;
  const _PanelDivider({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: SizedBox(
          width: 12,
          child: Center(
            child: Container(
              width: 6,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 3,
                      height: 3,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.textTheme.bodySmall?.color,
                        shape: BoxShape.circle,
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
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color == null
            ? theme.dividerColor.withValues(alpha: 0.15)
            : AppTheme.tint(color!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 12,
            color: theme.textTheme.bodySmall?.color,
          ),
          children: [
            TextSpan(text: '$label  '),
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color == null
                    ? theme.textTheme.bodyLarge?.color
                    : AppTheme.onTint(color!),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTab extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final bool isToday;
  final double laborHours;
  final double openHours;
  final bool hasTemplate;
  final VoidCallback onTap;

  const _DayTab({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.laborHours,
    required this.openHours,
    required this.hasTemplate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final statusColor = openHours > 0 ? AppTheme.red : AppTheme.green;
    final tooltip = [
      '${weekdayNames[date.weekday - 1]}, ${monthNames[date.month - 1]} ${date.day}',
      if (!hasTemplate) 'Not started',
      if (hasTemplate) '${formatHours(laborHours)} hrs scheduled',
      if (hasTemplate)
        openHours > 0 ? '${formatHours(openHours)} hrs open' : 'All filled',
    ].join('\n');
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : theme.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppTheme.accent : theme.dividerColor,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, c) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      '${weekdayShort[date.weekday - 1]} ${date.day}',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: selected
                            ? AppTheme.accent
                            : theme.textTheme.bodyLarge?.color,
                        decoration: isToday ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                  if (hasTemplate && c.maxWidth > 70) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${formatHours(laborHours)}h',
                      maxLines: 1,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                  if (hasTemplate) ...[
                    const SizedBox(width: 5),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShiftPanel extends StatelessWidget {
  final ScheduleDay day;
  final Shift shift;
  final Map<String, UserModel> usersById;
  final StoreSettingsModel? settings;
  final Map<String, String> warnings;
  final VoidCallback onClose;
  final ValueChanged<ShiftPiece> onEditPiece;
  final ValueChanged<ShiftPiece> onSplitPiece;
  final ValueChanged<ShiftPiece> onRemovePiece;
  final VoidCallback onAddPiece;
  final VoidCallback onTrainee;
  final VoidCallback onDelete;

  const _ShiftPanel({
    required this.day,
    required this.shift,
    required this.usersById,
    required this.settings,
    required this.warnings,
    required this.onClose,
    required this.onEditPiece,
    required this.onSplitPiece,
    required this.onRemovePiece,
    required this.onAddPiece,
    required this.onTrainee,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final user = usersById[shift.userId];
    final trainee = shift.isTraining ? usersById[shift.traineeId] : null;
    final color = colorForUser(user, settings);
    final pieces = [...shift.pieces]
      ..sort((a, b) => a.start.compareTo(b.start));
    final pieceWarnings = [
      for (final p in pieces)
        if (warnings[p.id] != null) warnings[p.id]!,
    ].toSet();

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      if (user?.id != null) {
                        context.go('/member/${user!.id}?from=/schedule');
                      }
                    },
                    child: Text(
                      personName(user),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.titleLarge?.color,
                        decoration: TextDecoration.underline,
                        decorationColor: theme.textTheme.titleLarge?.color
                            ?.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close (Esc)',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (user?.title != null)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(user!.title!, style: TextStyle(color: muted)),
            ),
          const SizedBox(height: 14),
          Text(
            formatRange(shift.start, shift.end, compact: false),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          Text(
            '${formatHours(shift.minutes / 60)} hrs'
            '${shift.pieces.length > 1 ? ' · split across ${shift.pieces.length} rows' : ''}',
            style: TextStyle(color: muted),
          ),
          if (trainee != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.school, size: 16, color: AppTheme.accent2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Training ${personName(trainee)}',
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'PIECES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: muted,
            ),
          ),
          const SizedBox(height: 6),
          for (final p in pieces)
            _PieceTile(
              day: day,
              piece: p,
              canSplit: p.minutes >= 30 && day.rows.length > 1,
              onEdit: () => onEditPiece(p),
              onSplit: () => onSplitPiece(p),
              onRemove: () => onRemovePiece(p),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onAddPiece,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another piece'),
          ),
          if (pieceWarnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final w in pieceWarnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        w,
                        style: TextStyle(fontSize: 12, color: AppTheme.accent),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onTrainee,
            icon: const Icon(Icons.school_outlined, size: 18),
            label: Text(
              shift.isTraining ? 'Change trainee' : 'Make it a training shift',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remove shift'),
          ),
        ],
      ),
    );
  }
}

class _PieceTile extends StatelessWidget {
  final ScheduleDay day;
  final ShiftPiece piece;
  final bool canSplit;
  final VoidCallback onEdit;
  final VoidCallback onSplit;
  final VoidCallback onRemove;

  const _PieceTile({
    required this.day,
    required this.piece,
    required this.canSplit,
    required this.onEdit,
    required this.onSplit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = day.rows.indexWhere((r) => r.id == piece.rowId);
    final row = index >= 0 ? day.rows[index] : null;
    final rowName = row == null
        ? 'Missing row'
        : 'Row ${index + 1}${row.label.isNotEmpty ? ' · ${row.label}' : ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatRange(piece.start, piece.end),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                Text(
                  rowName,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            iconSize: 18,
            color: theme.cardColor,
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'split') onSplit();
              if (v == 'remove') onRemove();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit times / row'),
              ),
              PopupMenuItem(
                value: 'split',
                enabled: canSplit,
                child: const Text('Move part to another row'),
              ),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove this piece'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Icon button that opens / closes the side panel, with a count badge.
class _PanelToggle extends StatelessWidget {
  final String tooltip;
  final Widget icon;
  final int count;
  final bool active;
  final VoidCallback onPressed;

  const _PanelToggle({
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      backgroundColor: AppTheme.accent2,
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        isSelected: active,
        style: IconButton.styleFrom(
          backgroundColor: active
              ? AppTheme.accent2.withValues(alpha: 0.15)
              : null,
        ),
        color: active ? AppTheme.accent2 : null,
        onPressed: onPressed,
        icon: icon,
      ),
    );
  }
}

/// Side panel: who can still work today (drag onto Open slots), then who's
/// already on the schedule, then a button to see who has the day off.
class _WhoCanWorkPanel extends StatefulWidget {
  final ScheduleDay day;
  final List<AvailablePerson> available;
  final List<UserModel> timeOff;
  final int hiddenUnavailable;
  final Map<String, UserModel> usersById;
  final StoreSettingsModel? settings;
  final ValueNotifier<double> pixelsPerMinute;
  final ValueChanged<String> onSelectShift;
  final VoidCallback onClose;

  final Map<String, String> trainingLabels;

  const _WhoCanWorkPanel({
    required this.trainingLabels,
    super.key,
    required this.day,
    required this.available,
    required this.timeOff,
    required this.hiddenUnavailable,
    required this.usersById,
    required this.settings,
    required this.pixelsPerMinute,
    required this.onSelectShift,
    required this.onClose,
  });

  @override
  State<_WhoCanWorkPanel> createState() => _WhoCanWorkPanelState();
}

class _WhoCanWorkPanelState extends State<_WhoCanWorkPanel> {
  bool _showTimeOff = false;

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
        color: theme.textTheme.bodySmall?.color,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final shifts = [...widget.day.shifts]
      ..sort((a, b) => a.start.compareTo(b.start));
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Who can work',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Drag someone onto the schedule.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              children: [
                if (widget.available.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'No one else can work today.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                for (final p in widget.available)
                  _AvailableTile(
                    trainingLabel: widget.trainingLabels[p.user.id],
                    person: p,
                    settings: widget.settings,
                    pixelsPerMinute: widget.pixelsPerMinute,
                  ),
                if (widget.hiddenUnavailable > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Text(
                      '${widget.hiddenUnavailable} more not available today',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                _heading(theme, 'ON THE SCHEDULE (${shifts.length})'),
                if (shifts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'No one scheduled yet.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                for (final s in shifts)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => widget.onSelectShift(s.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colorForUser(
                                widget.usersById[s.userId],
                                widget.settings,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  personName(widget.usersById[s.userId]) +
                                      (s.isTraining
                                          ? ' + ${personName(widget.usersById[s.traineeId], short: true)}'
                                          : ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                                Text(
                                  formatRange(s.start, s.end),
                                  style: TextStyle(fontSize: 12, color: muted),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${formatHours(s.laborMinutes / 60)}h',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showTimeOff = !_showTimeOff),
                  icon: _showTimeOff
                      ? const Icon(Icons.expand_less, size: 18)
                      : const Icon(Icons.event_busy, size: 18),
                  label: Text(
                    _showTimeOff
                        ? 'Hide time off'
                        : 'View people with time off (${widget.timeOff.length})',
                  ),
                ),
                if (_showTimeOff) ...[
                  const SizedBox(height: 8),
                  if (widget.timeOff.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'No one has the whole day off.',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  for (final u in widget.timeOff)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 5,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_busy, size: 14, color: AppTheme.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              personName(u),
                              style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                          if (u.title != null)
                            Text(
                              u.title!,
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableTile extends StatelessWidget {
  final AvailablePerson person;
  final String? trainingLabel;
  final StoreSettingsModel? settings;
  final ValueNotifier<double> pixelsPerMinute;

  const _AvailableTile({
    this.trainingLabel,
    required this.person,
    required this.settings,
    required this.pixelsPerMinute,
  });

  static const double _shiftHeight = 38;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = person.user;
    final color = colorForUser(user, settings);
    final canWork = person.canWork;

    Widget tile({bool dragging = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: dragging ? theme.cardColor : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dragging ? color : theme.dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            fit: dragging ? FlexFit.loose : FlexFit.tight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      if (user.id != null) {
                        context.go('/member/${user.id}?from=/schedule');
                      }
                    },
                    child: Text(
                      personName(user),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyLarge?.color,
                        decoration: TextDecoration.underline,
                        decorationColor: theme.textTheme.bodyLarge?.color
                            ?.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      if (user.title != null) TextSpan(text: user.title!),
                      if (user.title != null && canWork != null)
                        const TextSpan(text: '  ·  '),
                      if (canWork != null)
                        TextSpan(
                          text:
                              'Can work '
                              '${canWork.map((w) => formatRange(w.start, w.end)).join(', ')}',
                          style: TextStyle(color: AppTheme.accent2),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                if (trainingLabel != null) TrainingBadge(label: trainingLabel!),
              ],
            ),
          ),
          if (!dragging)
            Icon(
              Icons.drag_indicator,
              size: 16,
              color: theme.textTheme.bodySmall?.color,
            ),
        ],
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<PersonDrag>(
        data: PersonDrag(user.id!),
        // Hold the shift near its left edge so you place its start time.
        dragAnchorStrategy: (_, _, _) => const Offset(10, _shiftHeight / 2),
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: (6 * 60 * pixelsPerMinute.value).clamp(80.0, 2000.0),
            height: _shiftHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  personName(user, short: true),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: readableOn(color),
                  ),
                ),
                Text(
                  '6 hrs · drop on the schedule',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 10,
                    color: readableOn(color).withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: tile()),
        child: tile(),
      ),
    );
  }
}
