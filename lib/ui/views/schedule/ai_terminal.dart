import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'ai_scheduler.dart';

/// AI scheduler panel: a terminal-style log of what the AI did, and the
/// "Build schedule for week of …" button. Uses the app's own colors.
class AiTerminalPanel extends StatefulWidget {
  final List<AiLine> lines;
  final bool busy;

  /// e.g. "Oct 5".
  final String weekLabel;
  final VoidCallback onBuild;
  final VoidCallback onClear;
  final VoidCallback onClose;

  /// What Undo would undo ("the AI build"), or null for no Undo button.
  final String? undoLabel;
  final VoidCallback? onUndo;

  /// Sends a change request from the chat box. Null = no chat box (the week
  /// has no shifts yet).
  final ValueChanged<String>? onSend;

  const AiTerminalPanel({
    super.key,
    required this.lines,
    required this.busy,
    required this.weekLabel,
    required this.onBuild,
    required this.onClear,
    required this.onClose,
    this.undoLabel,
    this.onUndo,
    this.onSend,
  });

  @override
  State<AiTerminalPanel> createState() => _AiTerminalPanelState();
}

class _AiTerminalPanelState extends State<AiTerminalPanel>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _chat = TextEditingController();

  void _send() {
    final text = _chat.text.trim();
    if (text.isEmpty || widget.busy) return;
    widget.onSend?.call(text);
    _chat.clear();
  }
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    // Created here (not lazily during build) so it's disposed cleanly.
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant AiTerminalPanel old) {
    super.didUpdateWidget(old);
    if (widget.lines.length != old.lines.length || widget.busy != old.busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _chat.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final dim = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: 12.5,
      height: 1.5,
      color: fg,
    );

    (String, Color) style(AiLineKind kind) => switch (kind) {
      AiLineKind.command => ('\$ ', AppTheme.accent),
      AiLineKind.info => ('  ', dim),
      AiLineKind.success => ('✓ ', AppTheme.accent2),
      AiLineKind.warning => ('! ', AppTheme.accent),
      AiLineKind.error => ('✗ ', AppTheme.red),
      AiLineKind.ai => ('› ', fg),
      AiLineKind.user => ('› ', fg),
    };

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.accent2.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: AppTheme.accent2,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI scheduler',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.titleLarge?.color,
                        ),
                      ),
                      Row(
                        children: [
                          FadeTransition(
                            opacity: widget.busy
                                ? _blink
                                : const AlwaysStoppedAnimation(1.0),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: widget.busy
                                    ? AppTheme.accent
                                    : AppTheme.accent2,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.busy
                                  ? 'Working…'
                                  : 'Gemini · ${AiScheduler.lastWorkingModel ?? kScheduleAiModels.first}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: dim),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Clear log',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: widget.busy ? null : widget.onClear,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          // Log.
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor),
              ),
              child: SelectionArea(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  children: [
                    for (final l in widget.lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Builder(
                          builder: (_) {
                            final (prefix, color) = style(l.kind);
                            return Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: prefix,
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(text: l.text),
                                ],
                              ),
                              style: mono.copyWith(
                                color: switch (l.kind) {
                                  AiLineKind.info => dim,
                                  AiLineKind.warning => fg,
                                  AiLineKind.error => AppTheme.red,
                                  _ => fg,
                                },
                                fontWeight: l.kind == AiLineKind.command
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            );
                          },
                        ),
                      ),
                    if (widget.busy)
                      Row(
                        children: [
                          Text('  working ', style: mono.copyWith(color: dim)),
                          FadeTransition(
                            opacity: _blink,
                            child: Text(
                              '▍',
                              style: mono.copyWith(color: AppTheme.accent2),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Undo the last AI build / change.
          if (widget.undoLabel != null && widget.onUndo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: widget.busy ? null : widget.onUndo,
                  icon: const Icon(Icons.undo, size: 16),
                  label: Text('Undo ${widget.undoLabel}'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
            ),
          // Chat: ask for a change.
          if (widget.onSend != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _chat,
                enabled: !widget.busy,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: mono,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Ask for a change, e.g. "No training for Lena on Wednesday"',
                  hintStyle: mono.copyWith(color: dim),
                  prefixText: '› ',
                  prefixStyle: mono.copyWith(color: AppTheme.accent2, fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    tooltip: 'Send',
                    onPressed: widget.busy ? null : _send,
                    icon: Icon(Icons.send, size: 18, color: AppTheme.accent2),
                  ),
                ),
              ),
            ),
          // Build.
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: widget.busy ? null : widget.onBuild,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              icon: widget.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                widget.busy
                    ? 'Building schedule…'
                    : 'Build schedule for week of ${widget.weekLabel}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
