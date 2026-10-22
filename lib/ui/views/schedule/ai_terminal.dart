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

    Widget buildLine(AiLine l) {
      if (l.kind == AiLineKind.user) {
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(top: 4, bottom: 4, left: 24),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              l.text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        );
      }

      final (icon, iconColor) = switch (l.kind) {
        AiLineKind.command => (Icons.play_arrow_rounded, AppTheme.accent),
        AiLineKind.success => (
          Icons.check_circle_outline_rounded,
          AppTheme.green,
        ),
        AiLineKind.warning => (Icons.warning_amber_rounded, AppTheme.accent),
        AiLineKind.error => (Icons.error_outline_rounded, AppTheme.red),
        _ => (Icons.info_outline_rounded, dim),
      };

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 14, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.text,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: l.kind == AiLineKind.command
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: switch (l.kind) {
                    AiLineKind.error => AppTheme.red,
                    AiLineKind.success => fg,
                    AiLineKind.warning => fg,
                    AiLineKind.info => dim,
                    _ => fg,
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppTheme.accent2.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: AppTheme.accent2,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Scheduler',
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
                                  ? 'Generating schedule…'
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
                  tooltip: 'Clear history',
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
          // Activity list.
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.7),
                ),
              ),
              child: SelectionArea(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  children: [
                    if (widget.lines.isEmpty && !widget.busy)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 28,
                                color: dim.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ready to generate shifts for this week',
                                style: TextStyle(fontSize: 13, color: dim),
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final l in widget.lines) buildLine(l),
                    if (widget.busy)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Optimizing assignments…',
                              style: TextStyle(fontSize: 12, color: dim),
                            ),
                          ],
                        ),
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
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
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
                style: TextStyle(fontSize: 13, color: fg),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Ask AI to change, e.g. "No training for Lena"',
                  hintStyle: TextStyle(fontSize: 13, color: dim),
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.6),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Send',
                    onPressed: widget.busy ? null : _send,
                    icon: Icon(Icons.send, size: 18, color: AppTheme.accent),
                  ),
                ),
              ),
            ),
          // Build.
          Padding(
            padding: const EdgeInsets.all(12),
            child: widget.busy
                ? FilledButton.icon(
                    onPressed: null,
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
                    icon: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    label: const Text('Building schedule…'),
                  )
                : FilledButton(
                    onPressed: widget.onBuild,
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
                    child: Text(
                      'Build schedule for week of ${widget.weekLabel}',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
