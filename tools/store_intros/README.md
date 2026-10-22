# Store intro animations

After sign-in, the app plays a red blueprint of the person's store while it
loads (`lib/ui/widgets/store_intro.dart`).

- `models/<name>.js` – the 3D line model of one store (metres; x = east,
  y = up, z = south). Lines tagged 1 are the front door the camera flies into.
- `node tools/store_intros/build.js` – turns every model into
  `assets/store_intros/<name>.json`.
- `assets/store_intros/index.json` – links store IDs to animation files:

  ```json
  { "stores": { "<storeId>": "store_a.json" } }
  ```

Rules: only stores listed in the index get an intro. Someone with several
linked stores gets one at random. The intro plays at least 6.5 s; once the app
has loaded, a tap goes straight in.
