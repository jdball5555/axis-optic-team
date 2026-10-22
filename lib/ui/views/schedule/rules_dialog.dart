import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/schedule_models.dart';

/// The scheduler's rules: hard rules (never broken) and what it tries to do.
/// Turn a rule on to set it. Returns the new rules, or null when cancelled.
Future<ScheduleRules?> showRulesDialog(
  BuildContext context, {
  required ScheduleRules rules,
  required List<String> designations,
}) => showDialog<ScheduleRules>(
  context: context,
  builder: (_) => _RulesDialog(rules: rules, designations: designations),
);

class _RulesDialog extends StatefulWidget {
  final ScheduleRules rules;
  final List<String> designations;
  const _RulesDialog({required this.rules, required this.designations});

  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<_RulesDialog> {
  late ScheduleRules _r = widget.rules;

  void _set(ScheduleRules r) => setState(() => _r = r);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: const Text('Scheduling rules'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section(
                theme,
                'Hard rules',
                'Never broken. A shift that would break one is left open instead '
                    '(your own instructions to the AI can still override them).',
                AppTheme.red,
              ),
              _locked(
                theme,
                'Availability',
                'Only when people said they can work.',
              ),
              _locked(
                theme,
                'Title / tag bars',
                'Only people with that title or tag.',
              ),
              _locked(
                theme,
                'One shift a day',
                'Short bars (Truck, Prep…) can join onto it.',
              ),
              _locked(
                theme,
                'Who can train',
                'Set in Schedule settings → Who can train.',
              ),
              _locked(
                theme,
                'Training flow',
                'When enabled in Schedule settings, new hire training steps and trainer pairings cannot be violated.',
              ),
              _rule(
                theme,
                title: 'Time off',
                subtitle:
                    'Approved time off always counts. Turn on to treat requested '
                    '(pending) time off as off too.',
                hard: true,
                value: _r.requestedOffIsOff,
                onChanged: (v) => _set(_r.copyWith(requestedOffIsOff: v)),
              ),
              _rule(
                theme,
                title: 'Most shifts a week',
                subtitle:
                    'Nobody gets more, unless their "avg shifts" says more.',
                hard: true,
                value: true,
                locked: true,
                setting: _number(
                  value: _r.maxShiftsPerWeek.toDouble(),
                  options: const [3, 4, 5, 6, 7],
                  suffix: 'shifts',
                  onChanged: (v) =>
                      _set(_r.copyWith(maxShiftsPerWeek: v.round())),
                ),
              ),
              _rule(
                theme,
                title: 'Most hours a day',
                subtitle: 'Longer bars are split between people.',
                hard: true,
                value: _r.maxHoursPerDayOn,
                onChanged: (v) => _set(_r.copyWith(maxHoursPerDayOn: v)),
                setting: _number(
                  value: _r.maxHoursPerDay,
                  options: const [6, 7, 8, 9, 10, 11, 12],
                  suffix: 'hours',
                  enabled: _r.maxHoursPerDayOn,
                  onChanged: (v) => _set(_r.copyWith(maxHoursPerDay: v)),
                ),
              ),
              _rule(
                theme,
                title: 'Rest between shifts',
                subtitle:
                    'Hours off between one day\'s shift and the next day\'s.',
                hard: true,
                value: _r.restOn,
                onChanged: (v) => _set(_r.copyWith(restOn: v)),
                setting: _number(
                  value: _r.restHours,
                  options: const [8, 9, 10, 11, 12],
                  suffix: 'hours',
                  enabled: _r.restOn,
                  onChanged: (v) => _set(_r.copyWith(restHours: v)),
                ),
              ),
              _rule(
                theme,
                title: 'Days in a row',
                subtitle: 'Most days someone works without a day off.',
                hard: true,
                value: _r.maxDaysInRowOn,
                onChanged: (v) => _set(_r.copyWith(maxDaysInRowOn: v)),
                setting: _number(
                  value: _r.maxDaysInRow.toDouble(),
                  options: const [3, 4, 5, 6],
                  suffix: 'days',
                  enabled: _r.maxDaysInRowOn,
                  onChanged: (v) => _set(_r.copyWith(maxDaysInRow: v.round())),
                ),
              ),
              _rule(
                theme,
                title: 'Minors',
                subtitle:
                    'For one designation: a latest time on school nights, and most '
                    'hours a day.',
                hard: true,
                value: _r.minorsOn,
                onChanged: (v) => _set(_r.copyWith(minorsOn: v)),
                below: _r.minorsOn ? _minors(theme) : null,
              ),
              const SizedBox(height: 16),
              _section(
                theme,
                'Try to',
                'Preferences used to choose between people. They can give way when '
                    'covering the schedule needs it.',
                AppTheme.accent2,
              ),
              _rule(
                theme,
                title: 'Match shifts to profile',
                subtitle:
                    'Try to match the number of shifts a person gets a week with the shifts they want to work in their profile.',
                value: _r.usualShifts,
                onChanged: (v) =>
                    _set(_r.copyWith(usualShifts: v, hoursMatchUsual: v)),
              ),
              _rule(
                theme,
                title: 'Average shift length',
                subtitle:
                    'Keep shifts within a target length range on average.',
                value: _r.shiftLengthRangeOn,
                onChanged: (v) => _set(_r.copyWith(shiftLengthRangeOn: v)),
                setting: _rangeSelector(
                  min: _r.minShiftHours,
                  max: _r.maxShiftHours,
                  minOptions: const [2, 3, 4, 5, 6],
                  maxOptions: const [6, 7, 8, 9, 10, 11],
                  enabled: _r.shiftLengthRangeOn,
                  onChanged: (min, max) => _set(
                    _r.copyWith(
                      minShiftHours: min,
                      maxShiftHours: max < min ? min : max,
                    ),
                  ),
                ),
              ),
              _rule(
                theme,
                title: 'Same shifts as recent weeks',
                subtitle:
                    'Keep people on the days and times they\'ve been working.',
                value: _r.consistency,
                onChanged: (v) => _set(_r.copyWith(consistency: v)),
              ),
              _rule(
                theme,
                title: 'Daytime / Night',
                subtitle:
                    'Daytime people in the morning, Night people in the evening.',
                value: _r.dayNight,
                onChanged: (v) => _set(_r.copyWith(dayNight: v)),
              ),
              _rule(
                theme,
                title: 'No close then open',
                subtitle: 'Nobody closes one night and opens the next morning.',
                value: _r.avoidClopen,
                onChanged: (v) => _set(_r.copyWith(avoidClopen: v)),
              ),
              const SizedBox(height: 4),
              Text(
                'Covering the template always comes first.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
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
          onPressed: () => Navigator.pop(context, _r),
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _section(
    ThemeData theme,
    String title,
    String subtitle,
    Color color,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: theme.textTheme.bodySmall?.color,
          ),
        ),
      ],
    ),
  );

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: AppTheme.tint(color),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: AppTheme.onTint(color),
      ),
    ),
  );

  Widget _locked(ThemeData theme, String title, String subtitle) => _rule(
    theme,
    title: title,
    subtitle: subtitle,
    hard: true,
    value: true,
    locked: true,
  );

  Widget _rule(
    ThemeData theme, {
    required String title,
    required String subtitle,
    bool hard = false,
    required bool value,
    bool locked = false,
    ValueChanged<bool>? onChanged,
    Widget? setting,
    Widget? below,
  }) {
    final muted = theme.textTheme.bodySmall?.color;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        hard
                            ? _tag('Hard rule', AppTheme.red)
                            : _tag('Try to', AppTheme.accent2),
                      ],
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              ?setting,
              const SizedBox(width: 6),
              if (locked)
                Tooltip(
                  message: 'Always on',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.lock_outline, size: 18, color: muted),
                  ),
                )
              else
                Switch(value: value, onChanged: onChanged),
            ],
          ),
          ?below,
        ],
      ),
    );
  }

  Widget _number({
    required double value,
    required List<double> options,
    required String suffix,
    bool enabled = true,
    required ValueChanged<double> onChanged,
  }) {
    final all = {...options, value}.toList()..sort();
    return SizedBox(
      width: 120,
      child: DropdownButtonFormField<double>(
        initialValue: value,
        isDense: true,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          for (final o in all)
            DropdownMenuItem(
              value: o,
              child: Text('${o == o.roundToDouble() ? o.round() : o} $suffix'),
            ),
        ],
        onChanged: enabled ? (v) => onChanged(v ?? value) : null,
      ),
    );
  }

  Widget _rangeSelector({
    required double min,
    required double max,
    required List<double> minOptions,
    required List<double> maxOptions,
    bool enabled = true,
    required void Function(double min, double max) onChanged,
  }) {
    final allMin = {...minOptions, min}.toList()..sort();
    final allMax = {...maxOptions, max}.toList()..sort();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 82,
          child: DropdownButtonFormField<double>(
            initialValue: min,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
            items: [
              for (final o in allMin)
                DropdownMenuItem(
                  value: o,
                  child: Text('${o == o.roundToDouble() ? o.round() : o}h'),
                ),
            ],
            onChanged: enabled ? (v) => onChanged(v ?? min, max) : null,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('–', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          width: 82,
          child: DropdownButtonFormField<double>(
            initialValue: max,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
            items: [
              for (final o in allMax)
                DropdownMenuItem(
                  value: o,
                  child: Text('${o == o.roundToDouble() ? o.round() : o}h'),
                ),
            ],
            onChanged: enabled ? (v) => onChanged(min, v ?? max) : null,
          ),
        ),
      ],
    );
  }

  Widget _minors(ThemeData theme) {
    final designations = {...widget.designations, _r.minorDesignation}.toList();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  initialValue: _r.minorDesignation,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Designation',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final d in designations)
                      DropdownMenuItem(value: d, child: Text(d)),
                  ],
                  onChanged: (v) => _set(_r.copyWith(minorDesignation: v)),
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  initialValue: _r.minorLatestEnd,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Latest on school nights',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var m = 19 * 60; m <= 23 * 60; m += 30)
                      DropdownMenuItem(value: m, child: Text(formatMinutes(m))),
                  ],
                  onChanged: (v) => _set(_r.copyWith(minorLatestEnd: v)),
                ),
              ),
              _number(
                value: _r.minorMaxHoursPerDay,
                options: const [4, 5, 6, 7, 8, 9, 10],
                suffix: 'h a day',
                onChanged: (v) => _set(_r.copyWith(minorMaxHoursPerDay: v)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'School nights',
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < 7; i++)
                FilterChip(
                  label: Text(days[i]),
                  selected: _r.schoolNights.contains(i + 1),
                  onSelected: (on) => _set(
                    _r.copyWith(
                      schoolNights: [
                        for (var d = 1; d <= 7; d++)
                          if (d == i + 1 ? on : _r.schoolNights.contains(d)) d,
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
