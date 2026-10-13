import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';
import 'rules_dialog.dart';

/// Schedule settings: week start, the minimum title to be scheduled, and the
/// new-hire training flow. Returns the new config, or null when cancelled.
Future<ScheduleConfig?> showScheduleSettings(
  BuildContext context, {
  required ScheduleConfig config,
  required List<String> titles, // store titles, new-hire title first
  required List<String> tags, // additional tags
  List<String> teamAreas = const [], // roster areas (SVC, DT, KT, ...)
  List<String> designations = const [],
  required List<ShiftPosition> positions,
}) {
  return showDialog<ScheduleConfig>(
    context: context,
    builder: (_) => _ScheduleSettingsDialog(
      config: config,
      titles: titles,
      tags: tags,
      teamAreas: teamAreas,
      designations: designations,
      positions: positions,
    ),
  );
}

class _ScheduleSettingsDialog extends StatefulWidget {
  final ScheduleConfig config;
  final List<String> titles;
  final List<String> tags;
  final List<String> teamAreas;
  final List<String> designations;
  final List<ShiftPosition> positions;

  const _ScheduleSettingsDialog({
    required this.config,
    required this.titles,
    required this.tags,
    required this.teamAreas,
    required this.designations,
    required this.positions,
  });

  @override
  State<_ScheduleSettingsDialog> createState() => _ScheduleSettingsDialogState();
}

class _ScheduleSettingsDialogState extends State<_ScheduleSettingsDialog> {
  late ScheduleConfig _c = widget.config.copyWith(
    trainingDays: [...widget.config.trainingDays],
    trainerTags: [...widget.config.trainerTags],
    boards: widget.config.allBoards,
  );

  void _setBoard(int i, ScheduleBoard b) => setState(() {
    final boards = [..._c.boards];
    boards[i] = b;
    _c = _c.copyWith(boards: boards);
  });

  void _toggleTrainer(String name, bool on) => setState(() {
    final tags = [..._c.trainerTags]..remove(name);
    if (on) tags.add(name);
    _c = _c.copyWith(trainerTags: tags);
  });

  Widget _chips(ThemeData theme, String label, List<String> names) {
    if (names.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final n in names)
                FilterChip(
                  label: Text(n),
                  selected: _c.trainerTags.contains(n),
                  onSelected: (v) => _toggleTrainer(n, v),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _setDay(int i, TrainingDay d) => setState(() {
    final days = [..._c.trainingDays];
    days[i] = d;
    _c = _c.copyWith(trainingDays: days);
  });

  Widget _section(ThemeData theme, String title, String subtitle, Widget trailing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final minTitle = widget.titles.contains(_c.minTitle)
        ? _c.minTitle
        : widget.titles.firstOrNull;

    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: const Text('Schedule settings'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _c.weekStart,
                dropdownColor: theme.cardColor,
                decoration: const InputDecoration(
                  labelText: 'Week starts on',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var d = 1; d <= 7; d++)
                    DropdownMenuItem(value: d, child: Text(weekdayNames[d - 1])),
                ],
                onChanged: (v) =>
                    setState(() => _c = _c.copyWith(weekStart: v ?? _c.weekStart)),
              ),
              const SizedBox(height: 12),
              // --- Rules -----------------------------------------------------
              OutlinedButton.icon(
                onPressed: () async {
                  final rules = await showRulesDialog(
                    context,
                    rules: _c.rules,
                    designations: widget.designations,
                  );
                  if (rules != null) setState(() => _c = _c.copyWith(rules: rules));
                },
                icon: const Icon(Icons.rule, size: 18),
                label: const Text('Rules'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 20),
              Divider(color: theme.dividerColor),
              const SizedBox(height: 12),

              // --- Schedules -----------------------------------------------
              _section(
                theme,
                'Schedules',
                'Separate schedules (e.g. Front of house, Kitchen), each with '
                    'its own days and shifts. Pick the team areas whose people '
                    'go on each one (none picked = everyone). Positions are set '
                    'per board in the Shift page\'s settings.',
                const SizedBox.shrink(),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < _c.boards.length; i++)
                _boardRow(theme, i, _c.boards[i]),
              if (_c.boards.length == 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'You have one schedule. Add another to split the team, '
                    'e.g. Front of House (DT, SVC) and Kitchen (KT).',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _c = _c.copyWith(
                      boards: [
                        ..._c.boards,
                        ScheduleBoard(
                          id: newScheduleId(),
                          name: 'Schedule ${_c.boards.length + 1}',
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add a schedule'),
                ),
              ),
              const SizedBox(height: 20),
              Divider(color: theme.dividerColor),
              const SizedBox(height: 12),

              // --- Minimum title -------------------------------------------
              _section(
                theme,
                'Only schedule from a title up',
                'Team members show up for scheduling once they reach this '
                    'title (or one after it in your title order).',
                Switch(
                  value: _c.minTitleEnabled,
                  onChanged: (v) => setState(
                    () => _c = _c.copyWith(minTitleEnabled: v, minTitle: minTitle),
                  ),
                ),
              ),
              if (_c.minTitleEnabled) ...[
                const SizedBox(height: 12),
                if (widget.titles.isEmpty)
                  Text(
                    'No titles set up yet. Add them in Settings.',
                    style: TextStyle(color: muted),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: minTitle,
                    dropdownColor: theme.cardColor,
                    decoration: const InputDecoration(
                      labelText: 'Lowest title that gets scheduled',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var i = 0; i < widget.titles.length; i++)
                        DropdownMenuItem(
                          value: widget.titles[i],
                          child: Text('${i + 1}. ${widget.titles[i]}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _c = _c.copyWith(minTitle: v)),
                  ),
              ],
              const SizedBox(height: 20),
              Divider(color: theme.dividerColor),
              const SizedBox(height: 12),

              // --- Who can train --------------------------------------------
              _section(
                theme,
                'Who can train',
                _c.trainerTags.isEmpty
                    ? 'Anyone can train right now. Pick titles or additional '
                          'tags to limit it.'
                    : 'Only people with one of these titles or tags can have a '
                          'trainee (including in AI-built schedules).',
                _c.trainerTags.isEmpty
                    ? const SizedBox.shrink()
                    : TextButton(
                        onPressed: () => setState(
                          () => _c = _c.copyWith(trainerTags: const []),
                        ),
                        child: const Text('Anyone'),
                      ),
              ),
              if (widget.titles.isEmpty && widget.tags.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No titles or tags set up yet. Add them in Settings.',
                    style: TextStyle(color: muted),
                  ),
                ),
              _chips(theme, 'TITLES', widget.titles),
              _chips(theme, 'ADDITIONAL TAGS', widget.tags),
              const SizedBox(height: 20),
              Divider(color: theme.dividerColor),
              const SizedBox(height: 12),

              // --- Training flow -------------------------------------------
              _section(
                theme,
                'Training flow',
                'Plan a new hire\'s first shifts: who they train with and on '
                    'which position. Positions come from the Shift page.',
                Switch(
                  value: _c.trainingFlowEnabled,
                  onChanged: (v) => setState(() {
                    _c = _c.copyWith(
                      trainingFlowEnabled: v,
                      trainingDays: v && _c.trainingDays.isEmpty
                          ? const [TrainingDay()]
                          : _c.trainingDays,
                    );
                  }),
                ),
              ),
              if (_c.trainingFlowEnabled) ...[
                const SizedBox(height: 12),
                if (widget.positions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'No positions yet. Add them with the gear on the Shift page.',
                      style: TextStyle(fontSize: 12, color: AppTheme.accent),
                    ),
                  ),
                for (var i = 0; i < _c.trainingDays.length; i++)
                  _dayRow(theme, i, _c.trainingDays[i]),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _c = _c.copyWith(
                        trainingDays: [..._c.trainingDays, const TrainingDay()],
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add a shift'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _c.copyWith(minTitle: _c.minTitleEnabled ? minTitle : _c.minTitle),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _boardRow(ThemeData theme, int i, ScheduleBoard b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('board-name-${b.id}'),
                  initialValue: b.name,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: b.isMain ? 'Name (main schedule)' : 'Name',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => _setBoard(
                    i,
                    b.copyWith(name: v.trim().isEmpty ? 'Schedule' : v.trim()),
                  ),
                ),
              ),
              if (!b.isMain)
                IconButton(
                  tooltip: 'Remove schedule',
                  onPressed: () => setState(() {
                    final boards = [..._c.boards]..removeAt(i);
                    _c = _c.copyWith(boards: boards);
                  }),
                  icon: const Icon(Icons.delete_outline, size: 18),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
          if (widget.teamAreas.isNotEmpty) ...[
            const SizedBox(height: 10),
            _chipLabel(theme, 'Team areas on this schedule (none = everyone)'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in widget.teamAreas)
                  FilterChip(
                    label: Text(a),
                    selected: b.teamAreas.contains(a),
                    onSelected: (on) => _setBoard(
                      i,
                      b.copyWith(
                        teamAreas: [
                          for (final x in b.teamAreas)
                            if (x != a) x,
                          if (on) a,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipLabel(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
    ),
  );

  Widget _dayRow(ThemeData theme, int i, TrainingDay d) {
    final position = widget.positions.any((p) => p.id == d.positionId)
        ? d.positionId
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.accent2.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Shift ${i + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.accent2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Training with someone, or on their own.
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: true, label: Text('Training')),
              ButtonSegment(value: false, label: Text('Solo')),
            ],
            selected: {d.training},
            onSelectionChanged: (v) => _setDay(i, d.copyWith(training: v.first)),
          ),
          const SizedBox(width: 10),
          Text('on', style: TextStyle(color: theme.textTheme.bodySmall?.color)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              key: ValueKey('day-$i-$position'),
              initialValue: position,
              isExpanded: true,
              isDense: true,
              dropdownColor: theme.cardColor,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Any position')),
                for (final p in widget.positions)
                  DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) =>
                  _setDay(i, d.copyWith(positionId: v, clearPosition: v == null)),
            ),
          ),
          IconButton(
            tooltip: 'Remove shift',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
              final days = [..._c.trainingDays]..removeAt(i);
              _c = _c.copyWith(trainingDays: days);
            }),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
