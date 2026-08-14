# PotatoVoxel

A performance-first 3D voxel diorama for the Pokémon Gen 1 Recompilation.

PotatoVoxel is a fork of [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) v1.6.2. It keeps the original mod's defining features—extruded terrain, a depth-buffered camera, billboard characters, shadows, and optional 3D battles—but tunes the experience for low-power handhelds and other constrained devices.

## What players get

Compared with the original mod, PotatoVoxel is designed to provide:

- **Smoother gameplay:** mesh generation is spread across frames instead of blocking gameplay with large work spikes.
- **Lower GPU load:** MEDIUM, LOW, and POTATO render the 3D scene at 75%, 50%, and 33% of window resolution, then scale it back to the display.
- **Lower geometry cost:** distant border forests use crossed billboard cards instead of expensive carved voxel hulls.
- **Predictable defaults:** water, forest effects, anti-aliasing, staged 3D battles, and other costly effects are disabled by default.
- **Predictable rebuilds:** terrain meshes are rebuilt in memory when needed;
  completed meshes are also kept in the engine's scoped mod storage, per
  playthrough.
- **Benchmark diagnostics:** the realtime stats overlay (frame-time and mesh-build spans) is armed by benchmark instrumentation.

These changes target frame-time spikes, fill rate, and memory pressure. They are optimizations rather than a promise of a specific FPS on every device.

## Quality modes

The **VOXEL** option is a mode ladder. Picking a mode applies that mode's
tuned defaults to every quality knob in the VOXEL SETTINGS menu; changing
any knob individually flips the mode to **CUSTOM**, which keeps your own
combination until you pick a named mode again:

- **OFF** — use the normal 2D overworld.
- **HIGH** — 100% render scale, full water and forest effects, 2X AA.
- **MEDIUM** — 75% render scale, sky reflections, low forest effects.
- **LOW** — 50% render scale, cheaper shadows, water and forest off.
- **POTATO** — 33% render scale, the lowest GPU workload.
- **CUSTOM** — the VOXEL row reads this the moment any knob leaves its
  mode's preset.

**RENDER SCALE** (100% / 75% / 50% / 33%) is its own row in the VOXEL
SETTINGS menu: the modes set it, and moving it on its own also flips the
mode to CUSTOM.

The potato profile is the build. Every device runs the same tuned diorama —
there is no environment switch to a full desktop path, so behaviour is
identical everywhere. **3D-BTL** defaults OFF and follows the VOXEL quality
scale when enabled; legacy staged and Stadium selections remain compatible
internally when ON.

VR support remains capability-gated because the sandbox does not expose a
scoped OpenXR or graphics-interoperability API. The mod stays safe on builds
without that engine capability; it does not load a raw FFI workaround.

## Install

Import the .zip in-game (MODS > Import mod .zip), or copy the folder to
the game's `mods/` directory and restart — mods load at boot. The mod
conflicts with `DRAMATIC_SHAPE`, `ds_fp_ceiling` and the pre-rename
`dramatic_shape_brick`; only one may run at a time. Remove the old
`dramatic_shape_brick` from the mod manager after installing.

## Develop & test

From the engine checkout root:

```sh
POKEPORT_DATA_DIR="$PWD/tests/fixture_data" \
  luajit mods/potato_voxel/tests/potato_voxel_test.lua
```

The suite asserts the single potato build (the collapse is exercised
in-process by `BrickProfile.apply()`). Gates:

```sh
python3 tools/modkit.py lint mods/potato_voxel
python3 tools/modkit.py pack mods/potato_voxel
```

## Data & cache

- Settings persist under `options.modOptions.potato_voxel` (row ids
  `potato_voxel:*`).
- Terrain mesh cache records are stored through `mod.storage` under the mod's
  own namespace as bounded v2 chunks. Each terrain, water, and auxiliary
  payload has a fingerprint, generation, and commit record; incomplete
  writes are invisible and older committed work remains resumable.
- Existing unchunked cache records are read-only migration sources and are
  copied into the v2 layout lazily. New writes never use filename-shaped or
  raw filesystem keys.
- **In-game OPTIONS → PREBUILD CACHE** builds and resumes logical map/variant
  records; the progress count does not expose internal storage chunks. The
  cache cannot be built from the main menu: load a save first, or start it
  while loading into a save. A storage
  failure stays visible as `FAILED` with retryable completed work. If the
  scoped storage context is unavailable, the mod remains loaded but reports
  `UNAVAILABLE` and does not start a persistent prebuild.
- The normal renderer still builds maps on demand when no storage context
  exists or when a cache record is missing or stale.
- Stadium packs are read from the mod's own assets or generated once into
  `mod.storage`. To generate them, place a supported ROM at
  `baseroms/baserom.z64` inside the mod folder; `mod:read` supplies the bytes
  without exposing an arbitrary host path.

## Credits

- **DramaticShape** — the upstream Dramatic Shape Voxel Mod this is a fork
  of (v1.6.2, github.com/DramaticShape/DramaticShapeVoxelMod). Its own
  code carries no license; PotatoVoxel is a derived work.
- **pret/pokered** — the tile and sprite data the geometry is derived from.
- **pret/pokestadium** — the decompilation the STADIUM extractor was
  written against (no code or data from it is included or redistributed).
- **AverageConsumer** — battle UI/sprite interoperability improvements and
  the cold mesh-build loading cover.

Version history (including the 1.6.2-brick.\* lineage under the old name)
is in [CHANGELOG.md](CHANGELOG.md).
