// The sign-in intro drawn off the main thread (web only). See
// intro_canvas_web.dart; elsewhere [IntroCanvas.create] returns null and the
// intro is painted by Flutter.
export 'intro_canvas_stub.dart'
    if (dart.library.js_interop) 'intro_canvas_web.dart';
