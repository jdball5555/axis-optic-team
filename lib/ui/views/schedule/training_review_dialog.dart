import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';
import '../../../models/user_model.dart';
import 'position_ops.dart';
import 'schedule_common.dart';

/// Before building: who's in training and which training-flow steps they've
/// done. Steps worked on the schedule since the last review are checked for
/// you; "Not in training" takes someone off the list. Returns everyone's
/// reviewed progress (by uid), or null when cancelled.
Future<Map<String, TrainingProgress>?> showTrainingReview(
  BuildContext context, {
  required DateTime weekStart,
  required List<UserModel> people,
  required ScheduleConfig config,
  required ShiftConfig shiftConfig,

  /// Last saved review, by uid (none yet = everyone is listed).
  required Map<String, TrainingProgress> saved,

  /// Days each person worked since their last review (or ever, when they
  /// haven't been reviewed), by uid.
  required Map<String, int> workedSince,
}) => showDialog<Map<String, TrainingProgress>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _TrainingReviewDialog(
    weekStart: weekStart,
    people: people,
    config: config,
    shiftConfig: shiftConfig,
    saved: saved,
    workedSince: workedSince,
  ),
);

class _TrainingReviewDialog extends StatefulWidget {
  final DateTime weekStart;
  final List<UserModel> people;
  final ScheduleConfig config;
  final ShiftConfig shiftConfig;
  final Map<String, TrainingProgress> saved;
  final Map<String, int> workedSince;

  const _TrainingReviewDialog({
    required this.weekStart,
    required this.people,
    required this.config,
    required this.shiftConfig,
    required this.saved,
    required this.workedSince,
  });

  @override
  State<_TrainingReviewDialog> createState() => _TrainingReviewDialogState();
}

class _TrainingReviewDialogState extends State<_TrainingReviewDialog> {
  int get _steps => widget.config.trainingDays.length;

  /// Steps done per person (saved + worked since), and who's off the list.
  late final Map<String, Set<int>> _done;
  late final Map<String, Set<int>> _auto; // checked from the schedule
  late final Set<String> _notInTraining;
  bool _showOff = false;

  @override
  void initState() {
    super.initState();
    _done = {};
    _auto = {};
    _notInTraining = {};
    for (final u in widget.people) {
      final id = u.id!;
      final p = widget.saved[id];
      final saved = p?.done ?? const <int>{};
      final left = remainingTrainingSteps(
        _steps,
        saved,
        widget.workedSince[id] ?? 0,
      );
      final all = {for (var i = 0; i < _steps; i++) i};
      _done[id] = all.difference(left.toSet());
      _auto[id] = _done[id]!.difference(saved);
      // Off the list: marked so, or already through every step.
      if ((p?.notInTraining ?? false) || (p != null && left.isEmpty)) {
        _notInTraining.add(id);
      }
    }
  }

  List<UserModel> get _sorted => [...widget.people]
    ..sort((a, b) {
      // Newest hires first.
      final c = (b.startDate ?? DateTime(1900)).compareTo(
        a.startDate ?? DateTime(1900),
      );
      return c != 0 ? c : personName(a).compareTo(personName(b));
    });

  /// Column header: "Shift 1" over the position and who they're with.
  (String, String) _stepHeader(int i) {
    final d = widget.config.trainingDays[i];
    final position = widget.shiftConfig.positionById(d.positionId)?.name;
    return (
      'Shift ${i + 1}',
      [?position, d.training ? 'with trainer' : 'on their own'].join(' · '),
    );
  }

  static const double _nameWidth = 210;
  static const double _stepWidth = 112;
  static const double _actionWidth = 140;

  double get _tableWidth =>
      _nameWidth + _stepWidth * _steps + _actionWidth + 24;

  Map<String, TrainingProgress> _result() => {
    for (final u in widget.people)
      u.id!: TrainingProgress(
        userId: u.id!,
        done: _done[u.id!]!,
        notInTraining: _notInTraining.contains(u.id!),
        asOf: dateKey(widget.weekStart),
      ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final listed = _sorted
        .where((u) => !_notInTraining.contains(u.id))
        .toList();
    final off = _sorted.where((u) => _notInTraining.contains(u.id)).toList();
    final ws = widget.weekStart;
    final screen = MediaQuery.sizeOf(context);
    final width = (_tableWidth).clamp(560.0, screen.width - 80);

    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: Text(
        'Training review · week of ${monthShort[ws.month - 1]} ${ws.day}',
      ),
      content: SizedBox(
        width: width,
        height: (screen.height - 220).clamp(360.0, 640.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Check the training shifts each person has done. Ones they worked '
              'on the schedule since the last review are already checked (in '
              'teal). "Not in training" takes someone off the list. Anyone left '
              'with unchecked shifts gets their next ones this week.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 10),
            Text(
              '${listed.length} in training',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final tableWidth = _tableWidth < c.maxWidth
                      ? c.maxWidth
                      : _tableWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _headerRow(theme),
                          Divider(height: 1, color: theme.dividerColor),
                          Expanded(
                            child: ListView(
                              children: [
                                if (listed.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 24,
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Nobody is in training.',
                                        style: TextStyle(color: muted),
                                      ),
                                    ),
                                  ),
                                for (final u in listed) _row(theme, u),
                                const SizedBox(height: 8),
                                if (off.isNotEmpty)
                                  _offToggle(theme, off.length),
                                if (_showOff)
                                  for (final u in off) _offRow(theme, u),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _result()),
          child: const Text('Save & build'),
        ),
      ],
    );
  }

  Widget _headerRow(ThemeData theme) {
    final muted = theme.textTheme.bodySmall?.color;
    final bold = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: theme.textTheme.bodyLarge?.color,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: _nameWidth,
            child: Text('Team member', style: bold),
          ),
          for (var i = 0; i < _steps; i++)
            SizedBox(
              width: _stepWidth,
              child: Column(
                children: [
                  Text(_stepHeader(i).$1, style: bold),
                  Text(
                    _stepHeader(i).$2,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          const SizedBox(width: _actionWidth),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, UserModel u) {
    final id = u.id!;
    final muted = theme.textTheme.bodySmall?.color;
    final done = _done[id]!;
    void toggle(int i, bool on) => setState(() {
      if (on) {
        done.add(i);
      } else {
        done.remove(i);
      }
      _auto[id]!.remove(i);
    });
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _nameWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  personName(u),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                Text(
                  [
                    u.title ?? '',
                    if (u.startDate != null)
                      'started ${monthShort[u.startDate!.month - 1]} ${u.startDate!.day}',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
          for (var i = 0; i < _steps; i++)
            SizedBox(
              width: _stepWidth,
              child: Center(
                child: Tooltip(
                  message: _auto[id]!.contains(i)
                      ? 'Worked on the schedule'
                      : '',
                  child: Checkbox(
                    value: done.contains(i),
                    activeColor: _auto[id]!.contains(i)
                        ? AppTheme.accent2
                        : null,
                    onChanged: (v) => toggle(i, v ?? false),
                  ),
                ),
              ),
            ),
          SizedBox(
            width: _actionWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _notInTraining.add(id)),
                child: const Text('Not in training'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offToggle(ThemeData theme, int count) {
    final muted = theme.textTheme.bodySmall?.color;
    return InkWell(
      onTap: () => setState(() => _showOff = !_showOff),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(
              _showOff ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: muted,
            ),
            const SizedBox(width: 4),
            Text(
              'Not in training ($count)',
              style: TextStyle(
                fontSize: 13,
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _offRow(ThemeData theme, UserModel u) {
    final muted = theme.textTheme.bodySmall?.color;
    return Padding(
      padding: const EdgeInsets.only(left: 34, right: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              personName(u),
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _notInTraining.remove(u.id);
              // Back on the list with nothing done unless part way through.
              if (_done[u.id!]!.length >= _steps) _done[u.id!] = {};
            }),
            child: const Text('In training'),
          ),
        ],
      ),
    );
  }
}
