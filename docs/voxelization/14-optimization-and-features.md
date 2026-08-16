# 14 — Optimization Opportunities & Feature Additions (fact-checked plan)

Working plan for the next iterations of potato_voxel. Every item was
verified against the source; corrections from fact-checking are folded
in (marked CORRECTED / STRENGTHENED).

## Optimizations (ranked by impact ÷ effort)

### O1. Eliminate the two-stage vertex-table chain in mesh uploads — PARTIAL, then REVERTED on evidence

- Cache path: `meshFromData` (ChunkMesher.lua:1047-1064) folded every
  cached vertex stream into `rows` — one 6-element table per vertex
  (~500k tables on a big route; the 500k figure is the code's own,
  ChunkMesher.lua:119-120). `uploadTableMesh` (129-148) then copied rows
  into per-8192 slice tables, on the SYNCHRONOUS cold-entry path
  (1274-1306).
- CORRECTED during fact-check: fresh builds never sliced at all —
  `sink.finish()` → `Voxel3D.newMesh(verts, indices)` was a one-shot
  upload (ChunkMesher.lua:190), i.e. exactly the 100-500 ms hitch the
  comment at 119-120 warns about, inside a pumped frame.
- Shipped: (a) a flat-array upload path (`uploadFlatMesh`); (b)
  `sink.finish()` routed through the budget-sliced `uploadTableMesh`.
- **REVERTED (a)**: the flat path SHIPPED A WORLD-BREAKING BUG. Measured
  on the engine's own LOVE 11.5: `Mesh:setVertices` on a vertex-count
  mesh counts flat-table ELEMENTS as VERTICES and rejects the call
  ("expected at most 4, got 24") — and the mod pcall'd it unchecked, so
  every cache load uploaded a zeroed mesh (right count, all-zero
  vertices): black voids and missing terrain that vanished on cache
  wipe (fresh builds) and returned after rebuild (cache hits). The
  rows fold is restored; uploadTableMesh now CHECKS every slice and
  vertex-map call and drops the mesh on failure, so a regression fails
  the job loudly instead of blacking the world. (b) stays — the user's
  own post-wipe session proves the sliced rows upload renders.

### O2. In-place `casterMatrix` — DONE

- `Voxel3D.casterMatrix` (Voxel3D.lua:1444-1449) allocated ~5-6 tables
  per call, once per character per frame in `drawEntity`
  (VoxelScene.lua:389) and again per stale pose in the sprite-layer
  shadow redraw (947-949).
- STRENGTHENED: with WATER on, `drawCast` runs twice per frame (mirror
  copy at VoxelScene.lua:1134-1136 + real draw), doubling the cost.
- Fix: build in module-local scratch matrices (`casterA`/`casterB`), the
  same pattern `figureCasterMat` already uses. Callers all consume the
  result immediately (verified: VoxelScene.lua:389/948, Voxel3D.shadowMatrix).

### O3. Water FULL march cost at full res — DONE (HALF rung)

- Shipped: the WATER row gains a HALF rung (OFF / SKY / HALF / FULL).
  HALF is the reflective pass at a reduced ray budget -- a second
  shader compilation with RAY_STEPS 16 / RAY_REFINE 4 (vs 24/5),
  the same second-compilation pattern the wireframe already uses.
  FULL is byte-identical to before; presets unchanged (HIGH stays
  FULL, MEDIUM stays SKY). Suite coverage (245/245); both generated
  GLSL variants structurally validated.
- In-game verify: WATER HALF should look like FULL with a shorter
  reflection reach (far water hands back to the sky sooner).

### O4/O5. Leave as-is

- `Budget.check()` clock-per-cell in runGeometry is deliberate
  (ChunkMesher.lua:459-463).
- Shadow signature strings are cheap (table.concat, VoxelScene.lua:783-822).

### Verified-clean

DebugOverlay always-on cost (event-driven, 5 s stats), TerrainAtlas
step-gated repatch, two-layer shadow signature cache, lz4-first
compression (1.6.11), pcall guards (degrade-don't-error contract).

## Feature additions (ranked)

### F1. Per-map fog / atmosphere — DONE (tested; known nit below)

- The entire fog path is alive but pinned off: vertex-stage fog
  (Voxel3D.lua:120-125), mixing (311), uniforms sent every frame
  (1096-1100), while VoxelScene.lua:1003-1005 sets `Voxel3D.fog = nil`.
  ADR 0004 removed FOREST FX over an Android OS probe, not the fog.
- Shipped: `data/voxel_atmos.lua` (map id → { color, density, start,
  heightK }, forest + cave entries), `lib/MapAtmos.lua` (ATMOS row,
  default OFF, fogFor lookup), wired in place of the nil pin, row added
  to SETTINGS, suite coverage (231/231). The battle pass keeps its own
  fog = nil — staged shots stay clear by design.
- The water nit is CLOSED: Water.effect now reads fogColor/fogInfo from
  Voxel3D.fog, so a lake on a foggy map is the same air its banks are
  (the reflection already carried it — the mirror copy was fogged).

### F2. Structures debug overlay — DONE (tested)

- Shipped: `lib/ShapeDebug.lua` — F6 toggles a class-tinted map of the
  current overworld (one pixel per 8x8 tile in its resolved class
  colour; volume runs toward white, claimed cells toward magenta),
  built from the same Structures record the mesher reads, cached per
  map id, invalidated on block_replaced/map.reloaded. Drawn top-right
  through the render.hud wrap, player cell outlined. Suite coverage
  (237/237). README Diagnostics section names F6.
- Needs in-game visual confirmation (suite can't verify visuals).

### F3. Desktop camera ladder behind a profile flag

Original 8-rung ladder intact (VoxelState.lua:45), flattened by
BrickProfile (170-172); FP/TP rigs still install (main.lua:1502-1503).
A `BrickProfile.desktop` flag restores 15/50/75 + 1ST/3RD. Needs
re-verification — the Brick build was only validated against the flat
ladder.

### F4. Reuse the dead `VoxelGrid.override` seam

VoxelGrid.lua:64-72 — the battle used to force the wireframe as a
staged-shot look. One line per pass re-enables per-pass forcing.

### F5. Per-tileset water tuning — DONE (tested; shader source validated)

- Shipped: wave trains/swell/bend moved from compile-time source paste
  to per-pass uniforms (uTrain1-3, uSwell, uBend as vec4s);
  `Water.WAVE_PROFILES` keys profiles by tileset id (a calm GYM pool
  ships as the example); `Water.waveRate`/`waveTime` derive the phase
  from the ACTIVE profile's dominant train; VoxelScene passes the
  current map's profile. Suite coverage (241/241); generated GLSL
  checked structurally (balanced, uniforms declared before use).
- In-game verify: Cerulean Gym pool should read calm vs the sea; a
  shader compile failure would log and fall back to flat water.

### F6. Weather overlay (rain/snow) via the FX path — DONE (tested)

- Shipped: `lib/Weather.lua` + `data/voxel_weather.lua`. Drops live in
  WORLD space, stepped on the wall clock, drawn as thin screen-space
  streak quads through one stream mesh in the FX overlay (the same
  Voxel3D.project seam the "!" bubble uses) -- parallax against the
  terrain, in front of everything, zero depth risk. Pool recycled in
  place and bounded 40-220; camera teleports re-seed. Rain (Viridian
  Forest, density 0.5, pairs with the haze entry) and snow (no entry
  ships -- total conversions' own cold regions); WEATHER row, default
  OFF. Suite coverage (253/253); mesh is a GPU object, so the draw
  path needs the in-game pass.

## What NOT to touch

- Detection heuristics (TILE_BG_RATIO, OBJECT_MAX_ROWS, flood rules) —
  tuned against the whole game; change only with golden tests.
- The table-sink geometry core — the headless-tested contract
  (ChunkMesher.geometry / results()).
- Vertex/UV output changes without bumping MeshCache.GEOMETRY_VERSION
  (MeshCache.lua:70) — every device would silently rebuild.
- VR / STADIUM / raw-file features — the sandbox gate greps banned
  patterns (ADR 0004).

## Execution order

1. O1 + O2 (pure wins, no visual change) — DONE, tested
2. F1 fog (biggest visual win, smallest diff) — DONE, tested
3. O3 water HALF rung — DONE, tested
4. F2 authoring overlay — DONE, tested
5. F5 per-tileset water profiles — DONE, tested
6. F6 weather overlay — DONE, tested
7. F3 desktop ladder — needs the build-identity call
8. F4 grid-override use case — speculative without a look to hang on it

## Verification status (fact-check pass)

| Item | Status |
|---|---|
| O1 cache path, slice tables, 500k figure, sync cold-entry | Confirmed |
| O1 fresh-build one-shot | CORRECTED — worse than first stated; fix included |
| O2 alloc count, call sites, in-place pattern | Confirmed; STRENGTHENED with water-mirror 2× |
| O3 constants, gate, HIGH=FULL+100% preset | Confirmed |
| F1 fog plumbing + pinned nil + ADR reason | Confirmed |
| F2-F6 seams | Confirmed |
| LOVE flat-array setVertices | **FALSIFIED on-device**: LOVE 11.5 rejects flat arrays on vertex-count meshes (counts elements as vertices) — path reverted, uploads hardened to check results |
