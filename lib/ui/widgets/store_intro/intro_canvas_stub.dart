import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Not available here: the intro is painted by Flutter instead.
class IntroCanvas {
  IntroCanvas._();

  static bool debugLogFps = false;

  static IntroCanvas? create({
    required Float32List segments,
    required List<double> site,
    required List<double> door,
    required double orbitDist,
    required double orbitPitch,
    required bool reduceMotion,
    required VoidCallback onFirstFrame,
    required VoidCallback onDone,
    required VoidCallback onError,
    required VoidCallback onTap,
  }) => null;

  Widget view() => const SizedBox.shrink();
  void flyIn({required bool quick}) {}
  void dispose() {}
}
