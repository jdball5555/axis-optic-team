import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// After the training review: anything else for this week, one request per
/// box (admin time, training, meetings, days off…). Requests from past weeks
/// are listed so they can be picked again. Returns the requests (empty =
/// nothing extra), or null when cancelled.
Future<List<String>?> showRequestsDialog(
  BuildContext context, {
  List<String> previous = const [],
  List<String> past = const [],
  ValueChanged<String>? onForget,
}) => showDialog<List<String>>(
  context: context,
  builder: (_) => _RequestsDialog(previous: previous, past: past, onForget: onForget),
);

class _RequestsDialog extends StatefulWidget {
  final List<String> previous;
  final List<String> past;
  final ValueChanged<String>? onForget;
  const _RequestsDialog({required this.previous, required this.past, this.onForget});

  @override
  State<_RequestsDialog> createState() => _RequestsDialogState();
}

class _RequestsDialogState extends State<_RequestsDialog> {
  late final List<TextEditingController> _boxes = [
    for (final r in widget.previous) TextEditingController(text: r),
    if (widget.previous.isEmpty) TextEditingController(),
  ];
  late final List<String> _past = [...widget.past];

  @override
  void dispose() {
    for (final c in _boxes) {
      c.dispose();
    }
    super.dispose();
  }

  bool _inBoxes(String text) =>
      _boxes.any((c) => c.text.trim().toLowerCase() == text.trim().toLowerCase());

  /// Puts a past request in the first empty box (or a new one).
  void _use(String text) => setState(() {
    if (_inBoxes(text)) return;
    final empty = _boxes.where((c) => c.text.trim().isEmpty).firstOrNull;
    if (empty != null) {
      empty.text = text;
    } else {
      _boxes.add(TextEditingController(text: text));
    }
  });

  List<String> _result() => [
    for (final c in _boxes)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    return AlertDialog(
      backgroundColor: theme.cardColor,
      title: const Text('Anything else for this week?'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'One request per box. They override the rules, and the terminal says '
                'whether each one could be done.',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.tint(AppTheme.accent2).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.assignment_outlined, size: 16, color: AppTheme.accent2),
                        const SizedBox(width: 6),
                        Text(
                          'Does anyone need admin time?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Admin time is time off the floor (paperwork, ordering, truck '
                      'check-in…). It goes right before or after their shift and '
                      'doesn\'t count toward the people needed. Try: "Jordan needs 1 hour '
                      'of admin after his truck shift", "Give Sam 2 hours of admin on '
                      'Tuesday".',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Other ideas: "Have Rosa train Lena on Tuesday", "One-hour meeting '
                      'with Sam, Nina and Omar", "Tyler can\'t work Friday night".',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _boxes.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.tint(AppTheme.accent2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.onTint(AppTheme.accent2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _boxes[i],
                          autofocus: i == 0 && _boxes[i].text.isEmpty,
                          minLines: 1,
                          maxLines: 3,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: i == 0
                                ? 'e.g. "Jordan needs 1 hour of admin after his shift"'
                                : 'Another request (optional)',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () => setState(() {
                          _boxes.removeAt(i).dispose();
                          if (_boxes.isEmpty) _boxes.add(TextEditingController());
                        }),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _boxes.add(TextEditingController())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add another request'),
                ),
              ),
              if (_past.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'From past weeks',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                Text(
                  'Tap one to use it again this week.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in _past)
                      InputChip(
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Text(p, overflow: TextOverflow.ellipsis),
                        ),
                        selected: _inBoxes(p),
                        showCheckmark: true,
                        onPressed: () => _use(p),
                        onDeleted: widget.onForget == null
                            ? null
                            : () {
                                widget.onForget!(p);
                                setState(() => _past.remove(p));
                              },
                        deleteButtonTooltipMessage: 'Forget this one',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _result()),
          child: const Text('Build'),
        ),
      ],
    );
  }
}
