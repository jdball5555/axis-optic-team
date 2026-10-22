// Preview of the sign-in intro with the main thread kept busy, like the app
// signing in and loading underneath it.
//   flutter build web -t tools/store_intros/preview/main.dart -o <dir>
// URL options: ?flutter (Flutter-painted, no worker), ?idle (no busy work),
// ?store=<storeId> (which store's animation).
import 'dart:async';

import 'package:axis_team/ui/widgets/store_intro.dart';
import 'package:axis_team/ui/widgets/store_intro/intro_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final q = Uri.base.queryParameters;
  final useFlutter = q.containsKey('flutter');
  IntroCanvas.debugLogFps = true;
  final intro = (await StoreIntros.pickFor([
    q['store'] ?? 'sample-store-a',
  ]))!;

  // Busy main thread: 40 ms of work every 50 ms.
  if (!q.containsKey('idle')) {
    Timer.periodic(const Duration(milliseconds: 50), (_) {
      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < 40) {}
    });
  }

  // Flutter's own frame rate.
  var frames = 0;
  var from = DateTime.now();
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    frames++;
    final ms = DateTime.now().difference(from).inMilliseconds;
    if (ms >= 1000) {
      // ignore: avoid_print
      print('flutter: ${(frames * 1000 / ms).round()} fps');
      frames = 0;
      from = DateTime.now();
    }
  });

  runApp(
    MaterialApp(
      home: _Preview(intro: intro, useFlutter: useFlutter),
    ),
  );
}

/// Ready after 2 s, like the app finishing loading; logs when it's done.
class _Preview extends StatefulWidget {
  const _Preview({required this.intro, required this.useFlutter});
  final StoreIntro intro;
  final bool useFlutter;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  bool _ready = false, _done = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () => setState(() => _ready = true));
  }

  @override
  Widget build(BuildContext context) => _done
      ? const ColoredBox(
          color: Colors.white,
          child: Center(child: Text('the app')),
        )
      : StoreIntroScreen(
          intro: widget.intro,
          ready: _ready,
          onDone: () {
            // ignore: avoid_print
            print('intro done');
            setState(() => _done = true);
          },
          forcePaintInFlutter: widget.useFlutter,
        );
}
