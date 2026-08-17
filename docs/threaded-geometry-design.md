# Threaded geometry workers for the prebuilder

**Status:** implemented in 1.7.5 (`lib/WorkerPool.lua` +
`workers/geometry_worker.lua` + `ChunkMesher.buildGeometryData` +
`CachePrebuild` threaded dispatch). Requires the engine's `compute`
permission (src/mods/Sandbox.lua) for threads to spawn; every engine
without the grant runs the serial pump unchanged. Verify with
`love tools/thread_smoke`.

## Goal

Cold-cache fills currently build meshes on one core: the pump slices a
single build coroutine at 5ms (idle) / 50ms (covered), so a 446-job fill
is wall-clock serial even on an 8-core desktop. Thread the CPU phase
(geometry generation) across a worker pool; keep everything that touches
love.graphics or love.filesystem on the main thread.

## Why it is safe (the seam)

`ChunkMesher.runJob` phases:

```
load  -> map from engine MapLoader.load           MAIN (fs)
aux   -> Structures grass/flowers/figures          CPU (threadable)
cache-load -> MeshCache.loadTerrain               MAIN (fs)
geometry -> runGeometry(...) into byte sinks      CPU (threadable)
save  -> MeshCache.saveTerrain/Water              MAIN (fs)
mesh  -> meshFromData -> love mesh                MAIN (graphics)
```

`geometry` is pure Lua: it reads `map`, `masks`, Structures quads, the
TileRenderer palette state, and writes quantized byte buffers. No
graphics objects, no fs. This is the same shape as the engine's own
`src/core/chip_worker.lua` (pure-Lua synth off-main via love.thread +
channels, ships on every platform).

## Design

- **New `lib/WorkerPool.lua`** (mod) + **`workers/geometry_worker.lua`**:
  a chip_worker-style command/result channel pair per worker.
- **Worker count**: `math.max(1, cpuCount - 1)` capped at 3 on desktop
  and linux; 0 on Switch/Android low-end (battery/thermal + the 1GB RAM
  ceiling; revisit when a Switch measurement exists). Default 0 off
  unless the prebuild explicitly enables the pool.
- **Job protocol**: main thread serializes the map ONCE per map
  (body+full share it) to a Lua-source string (the tables are
  data-only) and pushes `{ gen, mapSrc, masks, bodyOnly, slot }`; the
  worker pumps its own copy of `runGeometry` with a no-op Budget
  (a worker coroutine runs to completion — no frame slice to respect),
  then pushes `{ gen, terrain={buf,n,idx,m}, water={...}, aux? }` back.
- **Worker environment**: `love.filesystem.load("lib/ChunkMesher.lua")`
  is not enough — the sandbox (`V.require`) and the engine module web
  (TileRenderer palettes, Data, Platform) must resolve headless in the
  thread. Plan: a small `V` shim in the worker that maps `V.require`
  onto `love.filesystem.load` of the same file, plus a captured
  palette/voidFill/atlas snapshot pushed per job (the geometry path
  must not lazily touch love.graphics).
- **Main-thread pump changes**: `CachePrebuild.update` dispatches the
  next job to a free worker instead of `ChunkMesher.request(force=true)`
  when the pool is on; drains results; on result: upload + save via the
  existing `saveTerrain/saveWater` + `swapSlot` path. Urgent/live builds
  stay on the current coroutine path unchanged.
- **Fallback**: any worker error, a failed `love.thread.newThread`, or a
  geometry result that fails the same assertions as a main-thread build
  drops that job back onto the serial path (and counts a jobFail).

## Open risks to resolve during implementation

1. `runGeometry`'s exact dependency closure (Structures, TileShape,
   palette/tileset state, Budget) — verify nothing touches
   love.graphics even on error paths, and that `Budget.tick()` with no
   pump is inert outside a coroutine.
2. Map serialization cost (map tables are large; measure Lua-source
   round-trip on SAFFRON_CITY).
3. Sandbox: the mod's lib files reference `...` (the V arg) — the
   worker shim must provide it; engine modules must be requirable from
   the thread's package path (`love.filesystem.load` per chip_worker).
4. love.data in threads: `packPayload` compress stays MAIN (love.data
   is thread-safe but the main pump can pipeline it later); the worker
   returns raw quantized bytes only.

## Success metric

On an 8-core desktop: cold 446-job fill wall-time with the pool on
should beat the serial covered-slice time by ~2-4x with zero
`jobFails`, zero hitches (geometry no longer shares the frame), and a
prebuild that is byte-identical to the serial cache (same
fingerprints, same payloads — the manifest/verify machinery is
untouched).
