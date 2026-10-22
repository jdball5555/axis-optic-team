#!/usr/bin/env node
// Builds the blueprint login animations the app plays after sign-in.
//
//   node tools/store_intros/build.js
//
// Reads every model in tools/store_intros/models/*.js and writes
// assets/store_intros/<model>.json. A model is plain JS that fills S (line
// segments: [x1,y1,z1,x2,y2,z2,tag], metres, x = east, y = up, z = south;
// tag 1 = the front door) and sets DOOR = [x,y,z] (the point the camera flies
// into). Optional settings go in a comment block at the top:
//   // @name   Sample Store A
//   // @site   6,0,-2        (point the camera orbits)
//   // @orbit  84,0.5        (orbit distance in metres, pitch in radians)
//
// Which store plays which animation lives in assets/store_intros/index.json.
const fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.join(__dirname, '..', '..');
const modelsDir = path.join(__dirname, 'models');
const outDir = path.join(root, 'assets', 'store_intros');
fs.mkdirSync(outDir, { recursive: true });
for (const file of fs.readdirSync(modelsDir).filter(f => f.endsWith('.js'))) {
  const src = fs.readFileSync(path.join(modelsDir, file), 'utf8');
  const meta = k => (src.match(new RegExp('@' + k + '\\s+(.+)')) || [])[1];
  const box = {};
  vm.runInNewContext(src + ';this.S=S;this.DOOR=DOOR;', box);
  const r = v => Math.round(v * 100) / 100;
  const segs = [];
  for (const s of box.S) segs.push(r(s[0]), r(s[1]), r(s[2]), r(s[3]), r(s[4]), r(s[5]), s[6] ? 1 : 0);
  const num = (k, d) => (meta(k) || d).split(',').map(Number);
  const [dist, pitch] = num('orbit', '84,0.5');
  const out = {
    name: (meta('name') || file.replace(/\.js$/, '')).trim(),
    site: num('site', '0,0,0'),
    door: box.DOOR.map(r),
    orbit: { dist, pitch },
    segments: segs,
  };
  const dest = path.join(outDir, file.replace(/\.js$/, '.json'));
  fs.writeFileSync(dest, JSON.stringify(out));
  console.log(`${file} -> ${path.relative(root, dest)} (${box.S.length} lines, ${(fs.statSync(dest).size / 1024).toFixed(0)} KB)`);
}
