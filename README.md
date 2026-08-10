# PotatoVoxel

A performance-first 3D voxel diorama for the Pokémon Gen 1 Recompilation.

PotatoVoxel is a fork of [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) v1.6.2. It keeps the original mod's defining features—extruded terrain, a depth-buffered camera, billboard characters, shadows, and optional 3D battles—but tunes the experience for low-power handhelds and other constrained devices.

## What players get

Compared with the original mod, PotatoVoxel is designed to provide:

- **Smoother gameplay:** mesh generation is spread across frames instead of blocking gameplay with large work spikes.
- **Lower GPU load:** MEDIUM, LOW, and POTATO render the 3D scene at 75%, 50%, and 33% of window resolution, then scale it back to the display.
- **Lower geometry cost:** distant border forests use crossed billboard cards instead of expensive carved voxel hulls.
- **Predictable defaults:** water, forest effects, anti-aliasing, staged 3D battles, and other costly effects are disabled by default.
- **Faster revisits:** terrain meshes can be stored on disk and prebuilt from the OPTIONS menu.
- **Useful diagnostics:** the DEBUG option shows frame-time and mesh-build statistics while tuning.

These changes target frame-time spikes, fill rate, and memory pressure. They are optimizations rather than a promise of a specific FPS on every device.

## Quality modes

The **VOXEL** option is a simple ladder:

- **OFF** — use the normal 2D overworld.
- **HIGH** — full-resolution 3D rendering and full actor shadows.
- **MEDIUM** — 75% render scale with cheaper actor shadows.
- **LOW** — 50% render scale with cheaper actor shadows.
- **POTATO** — 33% render scale with the lowest GPU workload.

The potato profile is enabled by default on every device. This keeps the first experience consistent and avoids requiring players to tune several independent graphics settings. On that profile, **3D-BTL** appears directly after VOXEL as an **OFF / ON** switch. It defaults OFF, follows the VOXEL quality scale when enabled, and keeps the map mesh cache; legacy staged and Stadium selections remain compatible internally when ON.

## Desktop compatibility

The full desktop path from the original mod remains available:

```sh
DS_BRICK=0 /path/to/gen1recomp/love      # full desktop path
DS_BRICK=1 /path/to/gen1recomp/love      # force PotatoVoxel tuning
# unset: PotatoVoxel tuning (default)
```

VR support and its OpenXR loader are not included in this release. If you need VR, use the upstream mod or restore the loader from it.

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
  DS_BRICK=0 luajit mods/potato_voxel/tests/potato_voxel_test.lua
```

The suite asserts the desktop path (it runs with `DS_BRICK=0`); the potato
collapse is exercised in-process by `BrickProfile.apply()`. Gates:

```sh
python3 tools/modkit.py lint mods/potato_voxel
python3 tools/modkit.py pack mods/potato_voxel
```

## Data & cache

- Settings persist under `options.modOptions.potato_voxel` (row ids
  `potato_voxel:*`).
- The terrain mesh cache lives at `mod-derived/potato_voxel/meshes` under
  the save dir; delete it (or the whole `mod-derived` tree) to force a
  rebuild. `MeshCache.GEOMETRY_VERSION` must be bumped whenever geometry
  output changes — the cache fingerprint does not cover every geometry
  knob. Large payloads use LZ4 compression when the runtime supports it;
  raw payloads remain readable as a fallback. This reduces storage and cache
  read cost, not steady-state GPU draw cost. Existing raw entries are repacked
  lazily as they are loaded; running PREBUILD CACHE migrates the full set.
- **OPTIONS → PREBUILD CACHE** cooperatively builds every map's body and full
  terrain variant, including water and auxiliary meshes. The game checks the
  complete cache at boot and shows **READY** when every current job is present.
  When the cache is incomplete, selecting **CONTINUE** or **NEW GAME** offers
  to build it first; choosing NO starts normally. The progress screen can be
  cancelled, and runtime GPU meshes are released after each map while the disk
  cache remains. The action is available on both desktop and the potato
  profile.
- **CACHE STATUS** shows the active geometry-cache version. **WIPE CACHE**
  removes the precalculated terrain files and clears the completion marker;
  the next voxel visit rebuilds maps on demand.
- **3D-BTL** reuses the same cached map terrain as the overworld. The battle
  cards and effects stay dynamic because they follow the live battle state;
  only the static map geometry belongs in the disk cache.

## Credits

- **DramaticShape** — the upstream Dramatic Shape Voxel Mod this is a fork
  of (v1.6.2, github.com/DramaticShape/DramaticShapeVoxelMod). Its own
  code carries no license; PotatoVoxel is a derived work.
- **pret/pokered** — the tile and sprite data the geometry is derived from.
- **pret/pokestadium** — the decompilation the STADIUM extractor was
  written against (no code or data from it is included or redistributed).

Version history (including the 1.6.2-brick.\* lineage under the old name)
is in [CHANGELOG.md](CHANGELOG.md).
