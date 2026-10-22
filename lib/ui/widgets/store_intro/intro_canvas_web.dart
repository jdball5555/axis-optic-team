import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../../core/app_version.dart';

int _viewCount = 0;

/// The sign-in intro drawn by web/store_intro_worker.js on an
/// OffscreenCanvas in a Web Worker. On the web the app signs in and loads on
/// the same thread Flutter draws on, which made the intro stutter; the worker
/// keeps drawing smoothly however busy that thread gets.
class IntroCanvas {
  IntroCanvas._({
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
  }) {
    final worker = web.Worker('store_intro_worker.js?v=$appVersion'.toJS);
    _worker = worker;
    worker.onmessage = ((web.MessageEvent e) {
      final data = e.data;
      if (data == null || !data.isA<JSObject>()) return;
      final type = ((data as JSObject)['type'] as JSString?)?.toDart;
      if (type == 'firstFrame') onFirstFrame();
      if (type == 'done') onDone();
    }).toJS;
    worker.onerror = ((web.Event _) => onError()).toJS;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement;
      canvas.style
        ..width = '100%'
        ..height = '100%'
        ..display = 'block';
      // Clicks on a web view element don't reach Flutter: pass taps on.
      canvas.addEventListener('click', ((web.Event _) => onTap()).toJS);
      try {
        final offscreen = canvas.transferControlToOffscreen();
        final init = JSObject()
          ..['type'] = 'init'.toJS
          ..['canvas'] = offscreen
          ..['segs'] = segments.toJS
          ..['site'] = [for (final v in site) v.toJS].toJS
          ..['door'] = [for (final v in door) v.toJS].toJS
          ..['orbitDist'] = orbitDist.toJS
          ..['orbitPitch'] = orbitPitch.toJS
          ..['reduceMotion'] = reduceMotion.toJS
          ..['debug'] = debugLogFps.toJS;
        worker.postMessage(init, [offscreen].toJS);
        _observer = web.ResizeObserver(
          ((JSArray<web.ResizeObserverEntry> entries, web.ResizeObserver _) {
            final list = entries.toDart;
            if (list.isEmpty) return;
            final rect = list.last.contentRect;
            final msg = JSObject()
              ..['type'] = 'resize'.toJS
              ..['w'] = rect.width.toJS
              ..['h'] = rect.height.toJS
              ..['dpr'] = web.window.devicePixelRatio.toJS;
            worker.postMessage(msg);
          }).toJS,
        )..observe(canvas);
      } catch (_) {
        onError();
      }
      return canvas;
    });
  }

  final String _viewType = 'store-intro-canvas-${_viewCount++}';

  /// Log the worker's frames per second to the browser console.
  static bool debugLogFps = false;
  web.Worker? _worker;
  web.ResizeObserver? _observer;

  /// A worker-driven canvas, or null when this browser can't (no
  /// OffscreenCanvas / workers): then Flutter paints the intro itself.
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
  }) {
    try {
      if (!globalContext.has('Worker') ||
          !globalContext.has('OffscreenCanvas')) {
        return null;
      }
      final canvasClass = globalContext['HTMLCanvasElement'] as JSObject?;
      final proto = canvasClass?['prototype'] as JSObject?;
      if (proto == null || !proto.has('transferControlToOffscreen')) {
        return null;
      }
      return IntroCanvas._(
        segments: segments,
        site: site,
        door: door,
        orbitDist: orbitDist,
        orbitPitch: orbitPitch,
        reduceMotion: reduceMotion,
        onFirstFrame: onFirstFrame,
        onDone: onDone,
        onError: onError,
        onTap: onTap,
      );
    } catch (_) {
      return null;
    }
  }

  Widget view() => HtmlElementView(viewType: _viewType);

  void flyIn({required bool quick}) {
    _worker?.postMessage(
      JSObject()
        ..['type'] = 'fly'.toJS
        ..['quick'] = quick.toJS,
    );
  }

  void dispose() {
    _observer?.disconnect();
    _observer = null;
    _worker?.terminate();
    _worker = null;
  }
}
