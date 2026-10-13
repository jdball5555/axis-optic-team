import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_scheduler.dart';

/// The AI scheduler's terminal log and whether a build is running. Kept
/// app-wide (not in the Schedule page) so a build keeps going when you switch
/// pages, the sidebar can show a spinner, and the log is still there when you
/// come back.
class AiBuildState {
  final List<AiLine> lines;
  final bool busy;

  /// What the terminal's Undo button undoes ("the AI build", "that
  /// change"), or null when there's nothing to undo.
  final String? undoLabel;

  const AiBuildState({required this.lines, this.busy = false, this.undoLabel});

  AiBuildState copyWith({
    List<AiLine>? lines,
    bool? busy,
    String? undoLabel,
    bool clearUndo = false,
  }) => AiBuildState(
    lines: lines ?? this.lines,
    busy: busy ?? this.busy,
    undoLabel: clearUndo ? null : (undoLabel ?? this.undoLabel),
  );
}

class AiBuildController extends Notifier<AiBuildState> {
  static List<AiLine> intro() => [
    (
      kind: AiLineKind.info,
      text: 'AI scheduler · Gemini (${kScheduleAiModels.join(' → ')})',
    ),
    (
      kind: AiLineKind.warning,
      text:
          'Free tier: Google may use requests to improve its products. Use '
          'sample data, not real team members. Names are sent as P1, P2, ….',
    ),
    (
      kind: AiLineKind.info,
      text:
          'Builds every day that has a template, exactly to the template: '
          'the bars are cut into slots and each slot gets one person. Order: '
          'your instructions, training, title/tag bars, everyone else, then '
          'holes (swaps and splits). The AI then reviews the draft and swaps '
          'people to get everyone closer to their usual shifts. Then it lists '
          'what\'s still open and why, and deploys positions by priority. '
          'Once the week has shifts, type a change below (e.g. "No training '
          'for Lena on Wednesday") and it reworks the schedule around it.',
    ),
  ];

  @override
  AiBuildState build() => AiBuildState(lines: intro());

  void log(AiLine line) =>
      state = state.copyWith(lines: [...state.lines, line]);

  void clear() {
    if (!state.busy) state = AiBuildState(lines: intro(), undoLabel: state.undoLabel);
  }

  Future<void> Function()? _undo;

  /// After a build or chat change: how to put the schedule back.
  void setUndo(String label, Future<void> Function() undo) {
    _undo = undo;
    state = state.copyWith(undoLabel: label);
  }

  /// Puts back what the last AI build or change replaced.
  Future<void> undo() async {
    final undo = _undo;
    final label = state.undoLabel;
    if (undo == null || state.busy) return;
    await run((log) async {
      log((kind: AiLineKind.command, text: 'undo'));
      await undo();
      _undo = null;
      state = state.copyWith(clearUndo: true);
      log((kind: AiLineKind.success, text: 'Undid $label. The schedule is back to how it was.'));
    });
  }

  /// What the manager asked for, per store and week (requests and chat
  /// changes), so later changes keep them.
  final Map<String, List<String>> _requests = {};

  List<String> requestsFor(String key) => _requests[key] ?? const [];

  void setRequests(String key, List<String> r) => _requests[key] = r;

  /// Runs [task] as the current build (ignored if one is already running).
  /// Errors are written to the log with a hint where one helps.
  Future<void> run(Future<void> Function(void Function(AiLine) log) task) async {
    if (state.busy) return;
    state = state.copyWith(busy: true);
    try {
      await task(log);
    } catch (e) {
      log((kind: AiLineKind.error, text: '$e'));
      final hint = _hintFor(e.toString());
      if (hint != null) log((kind: AiLineKind.info, text: hint));
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  static String? _hintFor(String error) {
    if (error.contains('No Gemini API key')) return null;
    if (error.contains('API key not valid') || error.contains('API_KEY')) {
      return 'Check the key in lib/core/gemini_key.dart '
          '(aistudio.google.com/apikey).';
    }
    if (error.toLowerCase().contains('referer')) {
      return 'The key\'s website restriction doesn\'t allow this address. Run '
          'on the port the key allows (e.g. --web-port=5050).';
    }
    return null;
  }
}

final aiBuildProvider = NotifierProvider<AiBuildController, AiBuildState>(
  AiBuildController.new,
);
