// Store intro: after sign-in, a red blueprint of the person's store orbits
// while the app loads underneath. Once the data is in, a tap skips straight
// in; otherwise, after a minimum showing, the camera swings round to the
// front door, flies through it, and the blueprint fades to reveal the app.
//
// The animations live in assets/store_intros/ (one JSON file per store,
// built by tools/store_intros/build.js). index.json links store IDs to files.
// A person with several linked stores gets one of them at random; a person
// with none gets no intro.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/app_providers.dart';
import 'store_intro/intro_canvas.dart';

/// Shortest time the intro plays before flying in on its own, so it always
/// runs a little longer than the load. A tap skips it once loading is done.
const Duration kStoreIntroMinShow = Duration(milliseconds: 6500);

/// If the data never reports ready, let them in anyway after this.
const Duration kStoreIntroMaxWait = Duration(seconds: 15);

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class StoreIntro {
  StoreIntro({
    required this.storeId,
    required this.name,
    required this.segments,
    required this.site,
    required this.door,
    required this.orbitDist,
    required this.orbitPitch,
  });

  final String storeId;
  final String name;

  /// Line segments, 7 numbers each: x1 y1 z1 x2 y2 z2 tag (tag 1 = door).
  /// Metres; x = east, y = up, z = south.
  final Float32List segments;
  final List<double> site;
  final List<double> door;
  final double orbitDist;
  final double orbitPitch;

  int get count => segments.length ~/ 7;

  static StoreIntro fromJson(String storeId, Map<String, dynamic> j) {
    List<double> v3(Object? o, List<double> d) {
      if (o is List && o.length == 3) {
        return [for (final n in o) (n as num).toDouble()];
      }
      return d;
    }

    final orbit = (j['orbit'] as Map?) ?? const {};
    final raw = (j['segments'] as List?) ?? const [];
    final segs = Float32List(raw.length - raw.length % 7);
    for (var i = 0; i < segs.length; i++) {
      segs[i] = (raw[i] as num).toDouble();
    }
    return StoreIntro(
      storeId: storeId,
      name: (j['name'] as String?) ?? '',
      segments: segs,
      site: v3(j['site'], const [0, 0, 0]),
      door: v3(j['door'], const [0, 1.3, 0]),
      orbitDist: ((orbit['dist'] as num?) ?? 84).toDouble(),
      orbitPitch: ((orbit['pitch'] as num?) ?? 0.5).toDouble(),
    );
  }
}

class StoreIntros {
  StoreIntros._();

  static const _dir = 'assets/store_intros/';
  static Map<String, String>? _index;
  static final Map<String, StoreIntro> _cache = {};

  /// Store ID → animation file, from assets/store_intros/index.json.
  static Future<Map<String, String>> index() async {
    final cached = _index;
    if (cached != null) return cached;
    var out = <String, String>{};
    try {
      final j =
          jsonDecode(await rootBundle.loadString('${_dir}index.json'))
              as Map<String, dynamic>;
      final stores = (j['stores'] as Map?) ?? const {};
      out = {
        for (final e in stores.entries)
          if (e.value is String && !e.key.toString().startsWith('_'))
            e.key.toString(): e.value as String,
      };
    } catch (e) {
      debugPrint('Store intros: no index ($e)');
    }
    return _index = out;
  }

  /// Already loaded index (null until [index] has run once).
  static Map<String, String>? get loadedIndex => _index;

  static Future<StoreIntro?> load(String storeId) async {
    final hit = _cache[storeId];
    if (hit != null) return hit;
    final file = (await index())[storeId];
    if (file == null) return null;
    try {
      final j =
          jsonDecode(await rootBundle.loadString('$_dir$file'))
              as Map<String, dynamic>;
      return _cache[storeId] = StoreIntro.fromJson(storeId, j);
    } catch (e) {
      debugPrint('Store intros: could not load $file ($e)');
      return null;
    }
  }

  /// One linked store from [storeIds] at random (null when none are linked).
  static Future<StoreIntro?> pickFor(
    List<String> storeIds, {
    math.Random? random,
  }) async {
    final idx = await index();
    final linked = storeIds.where(idx.containsKey).toList();
    if (linked.isEmpty) return null;
    final id = linked[(random ?? math.Random()).nextInt(linked.length)];
    return load(id);
  }

  /// Loads every linked animation up front (called when the app opens) so
  /// the intro can appear the moment someone signs in.
  static Future<void> preloadAll() async {
    for (final id in (await index()).keys) {
      await load(id);
    }
  }

  /// One of [storeIds]' animations, if it's already loaded (no waiting).
  static StoreIntro? cachedFor(List<String> storeIds, {math.Random? random}) {
    final ready = [
      for (final id in storeIds)
        if (_cache[id] case final StoreIntro intro) intro,
    ];
    if (ready.isEmpty) return null;
    return ready[(random ?? math.Random()).nextInt(ready.length)];
  }

  /// Whether any of [storeIds] has an animation.
  static bool anyLinked(Map<String, String> index, List<String> storeIds) =>
      storeIds.any(index.containsKey);

  static String _prefsKey(String email) =>
      'store_intro_ids_${email.trim().toLowerCase()}';

  /// Remembers which stores an email signs in to, on this device, so next
  /// time the intro can start as soon as Login is pressed.
  static Future<void> rememberAccount(String email, List<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey(email), ids);
    } catch (_) {}
  }

  static Future<List<String>?> rememberedFor(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_prefsKey(email));
    } catch (_) {
      return null;
    }
  }

  /// The stores on a login: a team member's store plus any owned stores.
  static List<String> storeIdsOf(Map<String, dynamic> user) {
    final own = user['storeId'];
    final owned = user['owned_stores'];
    return <String>{
      if (own is String && own.isNotEmpty) own,
      if (owned is List)
        for (final s in owned)
          if (s is String && s.isNotEmpty) s,
    }.toList();
  }
}

/// Store ID → animation file (empty until the index has loaded).
final storeIntroIndexProvider = FutureProvider<Map<String, String>>(
  (ref) => StoreIntros.index(),
);

/// Set by the sign-in page the moment Login is pressed (the stores this
/// email signed in to last time on this device), so the intro starts before
/// sign-in finishes. Cleared again when sign-in ends either way.
final storeIntroRequestProvider = StateProvider<List<String>?>((ref) => null);

// ---------------------------------------------------------------------------
// Gate: sits over the whole app and shows the intro right after sign-in
// ---------------------------------------------------------------------------

class StoreIntroGate extends ConsumerStatefulWidget {
  const StoreIntroGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<StoreIntroGate> createState() => _StoreIntroGateState();
}

class _StoreIntroGateState extends ConsumerState<StoreIntroGate> {
  StoreIntro? _intro;

  /// True from sign-in until we know whether there's an intro (keeps the app
  /// from flashing before the blueprint covers it).
  bool _covering = false;
  int _session = 0;

  /// The fly-in has started: the app underneath draws again so it's ready
  /// before the blueprint fades off it.
  bool _revealing = false;

  bool get _running => _intro != null || _covering;

  @override
  void initState() {
    super.initState();
    // Load the animations now so sign-in can show one straight away.
    StoreIntros.preloadAll();
    ref.listenManual<List<String>?>(storeIntroRequestProvider, (prev, next) {
      final signedIn = ref.read(currentUserProvider) != null;
      if (next != null && !signedIn && !_running) _start(next);
      // Sign-in failed: back to the login page.
      if (next == null && !signedIn) _end();
    });
    ref.listenManual<Map<String, dynamic>?>(currentUserProvider, (prev, next) {
      if (prev == null && next != null && !_running) {
        _start(StoreIntros.storeIdsOf(next));
      }
      if (next == null) _end();
    });
  }

  Future<void> _start(List<String> ids) async {
    final session = ++_session;
    final idx = StoreIntros.loadedIndex;
    if (idx != null && !ids.any(idx.containsKey)) return; // nothing linked
    final ready = StoreIntros.cachedFor(ids);
    if (ready != null) {
      // Already loaded: show it this frame.
      setState(() {
        _intro = ready;
        _revealing = false;
      });
      return;
    }
    setState(() {
      _covering = true;
      _revealing = false;
    });
    final intro = await StoreIntros.pickFor(ids);
    if (!mounted || session != _session) return;
    setState(() {
      _intro = intro;
      _covering = false;
    });
  }

  void _end() {
    _session++;
    if (_intro != null || _covering) {
      setState(() {
        _intro = null;
        _covering = false;
        _revealing = false;
      });
    }
  }

  /// Signed in and the app's first data is in: the store list and the team.
  bool _dataReady() {
    if (ref.watch(currentUserProvider) == null) return false;
    final stores = ref.watch(allStoresStreamProvider);
    final team = ref.watch(allStoreUsersStreamProvider);
    return (stores.hasValue || stores.hasError) &&
        (team.hasValue || team.hasError);
  }

  @override
  Widget build(BuildContext context) {
    final intro = _intro;
    // While the blueprint fully covers the app, the app keeps loading but
    // doesn't draw or animate (so the intro gets the whole frame budget).
    final hideApp = _covering || (intro != null && !_revealing);
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !hideApp,
          child: Offstage(offstage: hideApp, child: widget.child),
        ),
        if (_covering) const ColoredBox(color: Color(0xFF070709)),
        if (intro != null)
          StoreIntroScreen(
            key: ValueKey('intro-$_session'),
            intro: intro,
            ready: _dataReady(),
            onFlyIn: () {
              if (mounted && !_revealing) setState(() => _revealing = true);
            },
            onDone: _end,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The screen
// ---------------------------------------------------------------------------

enum _Phase { orbit, turn, dive, done }

class _Cam {
  double az = 0, pitch = 0.5, dist = 84;
  List<double> t = [0, 0, 0];

  // Live frame state read by the painter (so only the painter repaints).
  _Phase phase = _Phase.orbit;
  double phaseMs = 0, nowMs = 0, turnMs = 1300;

  /// 0 = blueprint fully on, 1 = gone (the app shows through).
  double fade = 0;
}

/// How the camera reaches the door: the full swing when the intro runs its
/// course, a quicker one after a tap.
class _Flight {
  const _Flight({
    required this.turnMs,
    required this.diveMs,
    required this.fadeMs,
  });
  final double turnMs, diveMs, fadeMs;

  static const full = _Flight(turnMs: 1300, diveMs: 1150, fadeMs: 650);
  static const quick = _Flight(turnMs: 520, diveMs: 480, fadeMs: 380);
}

/// The fade to the app starts while still heading for the door, at this
/// distance (metres), so the store dissolves into the app on the approach.
const double _fadeAtDist = 16;

class StoreIntroScreen extends StatefulWidget {
  const StoreIntroScreen({
    super.key,
    required this.intro,
    required this.ready,
    required this.onDone,
    this.onFlyIn,
    this.forcePaintInFlutter = false,
  });

  final StoreIntro intro;

  /// The app behind has loaded; tapping now flies in quickly.
  final bool ready;
  final VoidCallback onDone;

  /// The camera has started for the door (the app should start drawing).
  final VoidCallback? onFlyIn;

  /// Always paint with Flutter, never the web worker (for comparing).
  final bool forcePaintInFlutter;

  @override
  State<StoreIntroScreen> createState() => _StoreIntroScreenState();
}

class _StoreIntroScreenState extends State<StoreIntroScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _repaint = ValueNotifier<int>(0);
  final _progress = ValueNotifier<double>(0);
  final _cam = _Cam();

  Duration _now = Duration.zero, _phaseStart = Duration.zero;
  _Flight _flight = _Flight.full;

  /// What the text at the bottom shows (rebuilt only when these change).
  bool _hudReady = false, _hudVisible = true;

  /// Tapped before the app was ready: fly in quickly as soon as it is.
  bool _tapped = false;
  Duration? _fadeFrom;
  late double _fromAz, _toAz, _fromPitch, _fromDist;
  late List<double> _fromT;

  _Phase get _phase => _cam.phase;

  /// On the web the blueprint is drawn off the main thread (see
  /// intro_canvas_web.dart); null means Flutter paints it here instead.
  IntroCanvas? _canvas;

  /// The worker has drawn its first frame (until then a plain backdrop).
  bool _canvasShowing = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final i = widget.intro;
    _cam
      ..az = math.Random().nextDouble() * math.pi * 2
      ..pitch = i.orbitPitch
      ..dist = i.orbitDist
      ..t = List.of(i.site);
    _hudReady = widget.ready;
    _progress.value = widget.ready ? 1 : 0;
    _canvas = widget.forcePaintInFlutter
        ? null
        : IntroCanvas.create(
            segments: i.segments,
            site: i.site,
            door: i.door,
            orbitDist: i.orbitDist,
            orbitPitch: i.orbitPitch,
            reduceMotion: WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations,
            onFirstFrame: () {
              if (mounted && !_canvasShowing)
                setState(() => _canvasShowing = true);
            },
            onDone: _finish,
            onTap: () {
              if (mounted) _skip();
            },
            onError: () {
              // The worker couldn't run: paint it here after all.
              if (!mounted || _canvas == null) return;
              _canvas!.dispose();
              setState(() => _canvas = null);
            },
          );
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _progress.dispose();
    _canvas?.dispose();
    super.dispose();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _ticker.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
  }

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  double _ms(Duration d) => d.inMicroseconds / 1000.0;
  double _ease(double k) => k * k * (3 - 2 * k);
  double _lerp(double a, double b, double k) => a + (b - a) * k;

  void _go(_Phase p) {
    _cam.phase = p;
    _phaseStart = _now;
  }

  void _startFlyIn(_Flight flight) {
    _flight = flight;
    _cam.turnMs = flight.turnMs;
    widget.onFlyIn?.call();
    _canvas?.flyIn(quick: flight == _Flight.quick);
    if (_reduceMotion) {
      _fadeFrom = _now;
      _go(_Phase.dive);
      return;
    }
    var d = ((math.pi - _cam.az) % (math.pi * 2) + math.pi * 2) % (math.pi * 2);
    // A full swing always turns a little; a quick one takes the short way.
    if (flight == _Flight.full && d < 0.9) d += math.pi * 2;
    if (flight == _Flight.quick && d > math.pi) d -= math.pi * 2;
    _fromAz = _cam.az;
    _toAz = _cam.az + d;
    _fromPitch = _cam.pitch;
    _fromDist = _cam.dist;
    _fromT = List.of(_cam.t);
    _go(_Phase.turn);
  }

  /// A tap: fly through the door quickly (once the app has loaded).
  void _skip() {
    if (_phase != _Phase.orbit) return;
    if (widget.ready || _now >= kStoreIntroMaxWait) {
      _startFlyIn(_Flight.quick);
    } else {
      _tapped = true;
    }
  }

  void _tick(Duration elapsed) {
    final dt = _ms(elapsed - _now);
    _now = elapsed;
    final ready = widget.ready || _now >= kStoreIntroMaxWait;
    final k0 = _ms(_now - _phaseStart);

    switch (_phase) {
      case _Phase.orbit:
        if (!_reduceMotion) _cam.az += dt * 0.000132;
        if (ready && _tapped) {
          _startFlyIn(_Flight.quick);
        } else if (ready && _now >= kStoreIntroMinShow) {
          _startFlyIn(_Flight.full);
        }
      case _Phase.turn:
        final k = math.min(1.0, k0 / _flight.turnMs), e = _ease(k);
        _cam
          ..az = _lerp(_fromAz, _toAz, e)
          ..pitch = _lerp(_fromPitch, 0.16, e)
          ..dist = _lerp(_fromDist, 30, e);
        for (var i = 0; i < 3; i++) {
          _cam.t[i] = _lerp(_fromT[i], widget.intro.door[i], e);
        }
        if (k >= 1) _go(_Phase.dive);
      case _Phase.dive:
        if (!_reduceMotion) {
          final k = math.min(1.0, k0 / _flight.diveMs);
          _cam
            ..pitch = _lerp(0.16, 0, _ease(k))
            ..dist = _lerp(30, -4, k * k * k);
          if (k >= 1) _cam.dist -= dt * 0.01; // keep drifting through
        }
      case _Phase.done:
        break;
    }

    // Fade out on the way up to the door, not after reaching it.
    if (_fadeFrom == null && _phase == _Phase.dive && _cam.dist < _fadeAtDist) {
      _fadeFrom = _now;
    }
    if (_fadeFrom case final from? when _phase != _Phase.done) {
      final k = math.min(1.0, _ms(_now - from) / _flight.fadeMs);
      _cam.fade = _ease(k);
      if (k >= 1) {
        _cam.phase = _Phase.done;
        if (_canvas == null) {
          _finish();
        } else {
          // The worker says when it's done; this is only a safety net.
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) _finish();
          });
        }
      }
    }

    _cam
      ..phaseMs = _ms(_now - _phaseStart)
      ..nowMs = _ms(_now);
    _repaint.value++;
    _progress.value = ready
        ? 1.0
        : 0.92 * math.min(1.0, _ms(_now) / _ms(kStoreIntroMinShow));

    // The text only rebuilds when what it says changes.
    final hudVisible = _phase == _Phase.orbit;
    if (hudVisible != _hudVisible || ready != _hudReady) {
      setState(() {
        _hudVisible = hudVisible;
        _hudReady = ready;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_canvas case final canvas?) ...[
            if (!_canvasShowing)
              const ColoredBox(color: _BlueprintPainter._bgEdge),
            canvas.view(),
          ] else
            // Backdrop, lines and the fade are all one cheap paint.
            RepaintBoundary(
              child: CustomPaint(
                painter: _BlueprintPainter(
                  intro: widget.intro,
                  cam: _cam,
                  repaint: _repaint,
                  backdrop: true,
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                opacity: _hudVisible ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.intro.name.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFF4F1EE),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 240,
                          height: 2,
                          child: ValueListenableBuilder<double>(
                            valueListenable: _progress,
                            builder: (context, v, _) => LinearProgressIndicator(
                              value: v,
                              backgroundColor: const Color(0x1FFFFFFF),
                              color: const Color(0xFFFF3347),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _hudReady ? 'TAP TO ENTER' : 'LOADING YOUR STORE',
                            key: ValueKey(_hudReady),
                            style: TextStyle(
                              color: _hudReady
                                  ? const Color(0xFFF4F1EE)
                                  : const Color(0xFFA9A3AB),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A store's blueprint slowly orbiting (the dashboard Store tile)
// ---------------------------------------------------------------------------

class StoreOrbit extends StatefulWidget {
  const StoreOrbit({super.key, required this.intro});
  final StoreIntro intro;

  @override
  State<StoreOrbit> createState() => _StoreOrbitState();
}

class _StoreOrbitState extends State<StoreOrbit>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _repaint = ValueNotifier<int>(0);
  final _cam = _Cam();
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    final i = widget.intro;
    _cam
      ..az = math.Random().nextDouble() * math.pi * 2
      ..pitch = i.orbitPitch
      ..dist = i.orbitDist
      ..t = List.of(i.site);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1000.0;
    _last = elapsed;
    _cam.az += dt * 0.000132;
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _BlueprintPainter(
        intro: widget.intro,
        cam: _cam,
        repaint: _repaint,
        glow: false,
        lineWidth: 0.6,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Painter: perspective line drawing with a red glow
// ---------------------------------------------------------------------------

class _BlueprintPainter extends CustomPainter {
  _BlueprintPainter({
    required this.intro,
    required this.cam,
    required Listenable repaint,
    this.glow = true,
    this.lineWidth = 1.3,
    this.backdrop = false,
  }) : super(repaint: repaint);

  final StoreIntro intro;

  /// Camera plus the live phase / time / fade.
  final _Cam cam;

  /// A soft glow under the nearest lines (off for small, always-on views).
  final bool glow;

  /// Width of the blueprint lines.
  final double lineWidth;

  /// Paint the intro's dark backdrop too (the sign-in intro). Without it the
  /// lines sit on whatever is behind (the dashboard tile).
  final bool backdrop;

  static const _red = Color(0xFFFF3347);
  static const _bgEdge = Color(0xFF070709);

  @override
  void paint(Canvas canvas, Size size) {
    final phase = cam.phase;
    if (phase == _Phase.done) return;
    final w = size.width, h = size.height;
    final bounds = Offset.zero & size;
    // Everything fades together as the app is revealed.
    final on = 1 - cam.fade;
    if (on <= 0) return;

    final sx = w / 2, sy = h * 0.52;
    if (backdrop) {
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, 0.1),
            radius: 0.9,
            colors: [
              const Color(0xFF3A000E).withValues(alpha: on),
              const Color(0xFF12050A).withValues(alpha: on),
              _bgEdge.withValues(alpha: on),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(bounds),
      );
    }

    final cp = math.cos(cam.pitch), sp = math.sin(cam.pitch);
    final sa = math.sin(cam.az), ca = math.cos(cam.az);
    final cx3 = cam.t[0] + cam.dist * cp * sa;
    final cy3 = cam.t[1] + cam.dist * sp;
    final cz3 = cam.t[2] + cam.dist * cp * ca;
    final fx = -cp * sa, fy = -sp, fz = -cp * ca;
    var rx = -fz, rz = fx;
    final rl = math.sqrt(rx * rx + rz * rz);
    rx /= rl;
    rz /= rl;
    // up = right × forward
    final ux = 0 * fz - rz * fy, uy = rz * fx - rx * fz, uz = rx * fy - 0 * fx;
    final fp = math.min(w, h) * 1.25;
    const near = 0.25;
    final approaching = phase == _Phase.turn || phase == _Phase.dive;
    // Flying in, lines that pass right by the camera are dropped rather than
    // smeared across the screen.
    final tooClose = phase == _Phase.dive ? 2.5 : 0.0;
    final depthRef = math.max(20.0, cam.dist.abs() + 40);

    final paths = [Path(), Path(), Path()];
    final door = Path();
    final s = intro.segments;

    for (var i = 0; i < s.length; i += 7) {
      var dx = s[i] - cx3, dy = s[i + 1] - cy3, dz = s[i + 2] - cz3;
      var ax = dx * rx + dz * rz, ay = dx * ux + dy * uy + dz * uz;
      var az = dx * fx + dy * fy + dz * fz;
      dx = s[i + 3] - cx3;
      dy = s[i + 4] - cy3;
      dz = s[i + 5] - cz3;
      var bx = dx * rx + dz * rz, by = dx * ux + dy * uy + dz * uz;
      var bz = dx * fx + dy * fy + dz * fz;
      if (az < near && bz < near) continue;
      if (tooClose > 0 && math.min(az, bz) < tooClose) continue;
      if (az < near) {
        final k = (near - az) / (bz - az);
        ax += (bx - ax) * k;
        ay += (by - ay) * k;
        az = near;
      } else if (bz < near) {
        final k = (near - bz) / (az - bz);
        bx += (ax - bx) * k;
        by += (ay - by) * k;
        bz = near;
      }
      final Path p;
      if (approaching && s[i + 6] == 1) {
        p = door;
      } else {
        final rel = (az + bz) / 2 / depthRef;
        p = paths[rel > 1.15 ? 2 : (rel > 0.75 ? 1 : 0)];
      }
      p
        ..moveTo(sx + fp * ax / az, sy - fp * ay / az)
        ..lineTo(sx + fp * bx / bz, sy - fp * by / bz);
    }

    // Fade the edges of the site away while orbiting; open up on approach.
    final ms = phase == _Phase.orbit
        ? 1.0
        : phase == _Phase.turn
        ? 1 - _ease(math.min(1.0, cam.phaseMs / cam.turnMs))
        : 0.0;
    // Over the intro's own backdrop the edges fade under a vignette painted
    // on top (cheap); on a tile they're masked out in a layer.
    final maskLayer = ms > 0 && !backdrop;
    if (maskLayer) canvas.saveLayer(bounds, Paint());

    final pulse = 0.92 + 0.08 * math.sin(cam.nowMs / 700);
    const alphas = [0.95, 0.62, 0.34];
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (glow) {
      // A wide faint line under the nearest lines (no blur: blur is slow).
      canvas.drawPath(
        paths[0],
        stroke
          ..strokeWidth = lineWidth * 3.5
          ..color = _red.withValues(alpha: 0.14 * pulse * on),
      );
    }
    for (var k = 0; k < 3; k++) {
      canvas.drawPath(
        paths[k],
        stroke
          ..strokeWidth = lineWidth
          ..color = _red.withValues(alpha: alphas[k] * pulse * on),
      );
    }
    if (approaching) {
      canvas.drawPath(
        door,
        stroke
          ..strokeWidth = 6
          ..color = const Color(0xFFFF2040).withValues(alpha: 0.28 * on),
      );
      canvas.drawPath(
        door,
        stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFFE6E8).withValues(alpha: on),
      );
    }

    if (ms > 0) {
      final r0 = math.max(w, h * 1.4);
      final inner = r0 * (0.22 + 0.5 * (1 - ms));
      final outer = r0 * (0.5 + 0.6 * (1 - ms));
      canvas.save();
      canvas.translate(sx, sy);
      canvas.scale(1, 0.62);
      final circle = Rect.fromCircle(center: Offset.zero, radius: outer);
      final area = Rect.fromLTRB(-w * 2, -h * 3, w * 2, h * 3);
      if (maskLayer) {
        canvas.drawRect(
          area,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = RadialGradient(
              colors: const [Color(0xFF000000), Color(0x00000000)],
              stops: [inner / outer, 1],
            ).createShader(circle),
        );
      } else {
        canvas.drawRect(
          area,
          Paint()
            ..shader = RadialGradient(
              colors: [
                _bgEdge.withValues(alpha: 0),
                _bgEdge.withValues(alpha: on),
              ],
              stops: [inner / outer, 1],
            ).createShader(circle),
        );
      }
      canvas.restore();
    }
    if (maskLayer) canvas.restore();
  }

  static double _ease(double k) => k * k * (3 - 2 * k);

  @override
  bool shouldRepaint(covariant _BlueprintPainter old) =>
      old.intro != intro || old.cam != cam || old.lineWidth != lineWidth;
}
