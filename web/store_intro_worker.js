// Store intro renderer (web). Runs in a Web Worker on an OffscreenCanvas so
// the app signing in and loading on the main thread can't make it stutter.
// Same drawing as _BlueprintPainter in lib/ui/widgets/store_intro.dart.
//
// Messages in:
//   {type:'init', canvas, segs:Float32Array, site:[x,y,z], door:[x,y,z],
//    orbitDist, orbitPitch, reduceMotion}
//   {type:'resize', w, h, dpr}        CSS size of the canvas
//   {type:'fly', quick:bool}          head for the door
// Messages out:
//   {type:'firstFrame'}               something is on screen
//   {type:'done'}                     faded out completely

const FULL = { turn: 1300, dive: 1150, fade: 650 };
const QUICK = { turn: 520, dive: 480, fade: 380 };
const FADE_AT_DIST = 16; // start fading this far from the door (metres)

let ctx = null, canvas = null;
let W = 0, H = 0, DPR = 1;
let S = null, DOOR = [0, 1.3, 0];
let reduceMotion = false;
const cam = { az: Math.random() * Math.PI * 2, pitch: 0.5, dist: 84, t: [0, 0, 0] };

let phase = 'orbit', phaseStart = 0, now = 0, last = null;
let flight = FULL, from = null, fadeFrom = null, fade = 0;
let firstSent = false, finished = false, running = false;
let debug = false, frames = 0, statFrom = 0; // debug: log frames per second

const ease = k => k * k * (3 - 2 * k);
const lerp = (a, b, k) => a + (b - a) * k;

const raf = self.requestAnimationFrame
  ? cb => self.requestAnimationFrame(cb)
  : cb => setTimeout(() => cb(performance.now()), 16);

onmessage = e => {
  const m = e.data;
  if (m.type === 'init') {
    canvas = m.canvas;
    ctx = canvas.getContext('2d');
    S = m.segs;
    DOOR = m.door;
    cam.t = m.site.slice();
    cam.dist = m.orbitDist;
    cam.pitch = m.orbitPitch;
    reduceMotion = !!m.reduceMotion;
    debug = !!m.debug;
    start();
  } else if (m.type === 'resize') {
    W = m.w; H = m.h; DPR = m.dpr || 1;
    if (canvas) {
      canvas.width = Math.max(1, Math.round(W * DPR));
      canvas.height = Math.max(1, Math.round(H * DPR));
    }
    start();
  } else if (m.type === 'fly') {
    flyIn(m.quick ? QUICK : FULL);
  }
};

function start() {
  if (running || !ctx || !W || !H) return;
  running = true;
  raf(frame);
}

function go(p) { phase = p; phaseStart = now; }

function flyIn(f) {
  if (phase !== 'orbit') return;
  flight = f;
  if (reduceMotion) { fadeFrom = now; go('dive'); return; }
  let d = ((Math.PI - cam.az) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
  // A full swing always turns a little; a quick one takes the short way.
  if (f === FULL && d < 0.9) d += Math.PI * 2;
  if (f === QUICK && d > Math.PI) d -= Math.PI * 2;
  from = { az: cam.az, toAz: cam.az + d, pitch: cam.pitch, dist: cam.dist, t: cam.t.slice() };
  go('turn');
}

function frame(t) {
  if (finished) return;
  if (last === null) last = t;
  const dt = Math.min(100, t - last);
  last = t;
  now += dt;
  step(dt);
  draw();
  if (debug && ++frames && now - statFrom >= 1000) {
    console.log(`store intro worker: ${Math.round(frames * 1000 / (now - statFrom))} fps`);
    frames = 0; statFrom = now;
  }
  if (!firstSent) { firstSent = true; postMessage({ type: 'firstFrame' }); }
  if (finished) {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    postMessage({ type: 'done' });
    return;
  }
  raf(frame);
}

function step(dt) {
  const k0 = now - phaseStart;
  if (phase === 'orbit') {
    if (!reduceMotion) cam.az += dt * 0.000132;
  } else if (phase === 'turn') {
    const k = Math.min(1, k0 / flight.turn), e = ease(k);
    cam.az = lerp(from.az, from.toAz, e);
    cam.pitch = lerp(from.pitch, 0.16, e);
    cam.dist = lerp(from.dist, 30, e);
    for (let i = 0; i < 3; i++) cam.t[i] = lerp(from.t[i], DOOR[i], e);
    if (k >= 1) go('dive');
  } else if (phase === 'dive' && !reduceMotion) {
    const k = Math.min(1, k0 / flight.dive);
    cam.pitch = lerp(0.16, 0, ease(k));
    cam.dist = lerp(30, -4, k * k * k);
    if (k >= 1) cam.dist -= dt * 0.01; // keep drifting through
  }
  // Fade out on the way up to the door, not after reaching it.
  if (fadeFrom === null && phase === 'dive' && cam.dist < FADE_AT_DIST) fadeFrom = now;
  if (fadeFrom !== null) {
    const k = Math.min(1, (now - fadeFrom) / flight.fade);
    fade = ease(k);
    if (k >= 1) finished = true;
  }
}

function draw() {
  const w = W, h = H, on = 1 - fade;
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  ctx.clearRect(0, 0, w, h);
  if (on <= 0) return;
  const sx = w / 2, sy = h * 0.52;

  // Backdrop (Flutter RadialGradient(center (0, 0.1), radius 0.9)).
  const r = 0.9 * Math.min(w, h);
  const bg = ctx.createRadialGradient(sx, h * 0.55, 0, sx, h * 0.55, r);
  bg.addColorStop(0, `rgba(58,0,14,${on})`);
  bg.addColorStop(0.45, `rgba(18,5,10,${on})`);
  bg.addColorStop(1, `rgba(7,7,9,${on})`);
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, w, h);

  const cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
  const sa = Math.sin(cam.az), ca = Math.cos(cam.az);
  const cx = cam.t[0] + cam.dist * cp * sa;
  const cy = cam.t[1] + cam.dist * sp;
  const cz = cam.t[2] + cam.dist * cp * ca;
  const fx = -cp * sa, fy = -sp, fz = -cp * ca;
  let rx = -fz, rz = fx;
  const rl = Math.hypot(rx, rz); rx /= rl; rz /= rl;
  const ux = -rz * fy, uy = rz * fx - rx * fz, uz = rx * fy;
  const fp = Math.min(w, h) * 1.25;
  const near = 0.25;
  const approaching = phase === 'turn' || phase === 'dive';
  // Flying in, lines that pass right by the camera are dropped rather than
  // smeared across the screen.
  const tooClose = phase === 'dive' ? 2.5 : 0;
  const depthRef = Math.max(20, Math.abs(cam.dist) + 40);

  const buckets = [[], [], []], door = [];
  for (let i = 0; i < S.length; i += 7) {
    let dx = S[i] - cx, dy = S[i + 1] - cy, dz = S[i + 2] - cz;
    let ax = dx * rx + dz * rz, ay = dx * ux + dy * uy + dz * uz, az = dx * fx + dy * fy + dz * fz;
    dx = S[i + 3] - cx; dy = S[i + 4] - cy; dz = S[i + 5] - cz;
    let bx = dx * rx + dz * rz, by = dx * ux + dy * uy + dz * uz, bz = dx * fx + dy * fy + dz * fz;
    if (az < near && bz < near) continue;
    if (tooClose > 0 && Math.min(az, bz) < tooClose) continue;
    if (az < near) {
      const k = (near - az) / (bz - az); ax += (bx - ax) * k; ay += (by - ay) * k; az = near;
    } else if (bz < near) {
      const k = (near - bz) / (az - bz); bx += (ax - bx) * k; by += (ay - by) * k; bz = near;
    }
    const out = approaching && S[i + 6] === 1
      ? door
      : buckets[(az + bz) / 2 / depthRef > 1.15 ? 2 : ((az + bz) / 2 / depthRef > 0.75 ? 1 : 0)];
    out.push(sx + fp * ax / az, sy - fp * ay / az, sx + fp * bx / bz, sy - fp * by / bz);
  }

  const stroke = (pts, width, color) => {
    if (!pts.length) return;
    ctx.beginPath();
    for (let i = 0; i < pts.length; i += 4) { ctx.moveTo(pts[i], pts[i + 1]); ctx.lineTo(pts[i + 2], pts[i + 3]); }
    ctx.lineWidth = width;
    ctx.strokeStyle = color;
    ctx.stroke();
  };
  ctx.lineCap = 'round';
  const pulse = 0.92 + 0.08 * Math.sin(now / 700);
  const red = a => `rgba(255,51,71,${a})`;
  stroke(buckets[0], 1.3 * 3.5, red(0.14 * pulse * on)); // soft glow, no blur
  const alphas = [0.95, 0.62, 0.34];
  for (let k = 0; k < 3; k++) stroke(buckets[k], 1.3, red(alphas[k] * pulse * on));
  if (approaching) {
    stroke(door, 6, `rgba(255,32,64,${0.28 * on})`);
    stroke(door, 2, `rgba(255,230,232,${on})`);
  }

  // Fade the edges of the site away while orbiting; open up on approach.
  const ms = phase === 'orbit' ? 1 : phase === 'turn' ? 1 - ease(Math.min(1, (now - phaseStart) / flight.turn)) : 0;
  if (ms > 0) {
    const r0 = Math.max(w, h * 1.4);
    const inner = r0 * (0.22 + 0.5 * (1 - ms));
    const outer = r0 * (0.5 + 0.6 * (1 - ms));
    ctx.save();
    ctx.translate(sx, sy);
    ctx.scale(1, 0.62);
    const v = ctx.createRadialGradient(0, 0, 0, 0, 0, outer);
    v.addColorStop(Math.min(0.999, inner / outer), 'rgba(7,7,9,0)');
    v.addColorStop(1, `rgba(7,7,9,${on})`);
    ctx.fillStyle = v;
    ctx.fillRect(-w * 2, -h * 3, w * 4, h * 6);
    ctx.restore();
  }
}
