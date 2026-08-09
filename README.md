# PotatoVoxel

A performance-first 3D voxel diorama for the Pokémon Gen 1 Recompilation.

PotatoVoxel is a fork of [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) v1.6.2. It keeps the original mod's defining features such as extruded terrain, a depth-buffered camera, billboard characters, shadows, and optional 3D battles, but tunes the experience for low-power handhelds and other constrained devices.

## What players get

Compared with the original mod, PotatoVoxel is designed to provide:

- **Smoother gameplay:** mesh generation is spread across frames instead of blocking gameplay with large work spikes.
- **Lower GPU load:** MEDIUM, LOW, and POTATO render the 3D scene at 75%, 50%, and 33% of window resolution, then scale it back to the display.
- **Lower geometry cost:** distant border forests use crossed billboard cards instead of expensive carved voxel hulls.
- **Predictable defaults:** water, forest effects, anti-aliasing, staged 3D battles, and other costly effects are disabled by default.
- **Faster revisits:** terrain meshes can be stored on disk and prebuilt from the OPTIONS menu.

These changes target frame-time spikes, fill rate, and memory pressure. They are optimizations rather than a promise of a specific FPS on every device.

## Quality modes

The **VOXEL** option is a simple ladder:

- **OFF** — use the normal 2D overworld.
- **HIGH** — full-resolution 3D rendering and full actor shadows.
- **MEDIUM** — 75% render scale with cheaper actor shadows.
- **LOW** — 50% render scale with cheaper actor shadows.
- **POTATO** — 33% render scale with the lowest GPU workload.

The MEDIUM profile is enabled by default on every device. This keeps the first experience consistent and avoids requiring players to tune several independent graphics settings.

## Feature compatibility

VR support, its OpenXR loader and 3D Battle scenes are not included in this mod currently. If you need VR, use another Voxel mod.


## Data & cache

PotatoVoxel generates terrain meshes the first time each map is visited. Without
a cache, that work can cause long loading pauses and frame-time spikes. For
the smoothest experience, prebuild the cache before playing:

1. Start the game and open **OPTIONS**.
2. Set **VOXEL** to the quality level you plan to use (MEDIUM is the default).
3. Select **PREBUILD MAP CACHE** and press **A** to start.
4. Leave the game open until the row reports that the build is complete. On
   Android, keep the device connected to power if the build takes several
   minutes.

The prebuild cooperatively processes every map's body and full terrain
variant, including water and auxiliary meshes. It is deliberately spread across
frames so the game remains responsive, but it is still a substantial one-time
operation involving CPU work, allocations, disk writes, and GPU uploads. The
largest performance improvement comes after this first build, when revisiting
maps can load their meshes from disk instead of generating them during play.

While the build is running, the row shows map/job progress and an ETA. Select
the row and press **A** again to cancel safely; partial work remains valid and
can be completed by starting the prebuild again later. On Android the status is
condensed to fit the fixed options box, and the row changes to **CANCEL
PREBUILD** while active.

- Settings persist under `options.modOptions.potato_voxel` (row ids
  `potato_voxel:*`).
- The terrain mesh cache lives at `mod-derived/potato_voxel/meshes` under
  the save dir; delete it (or the whole `mod-derived` tree) to force a
  rebuild. `MeshCache.GEOMETRY_VERSION` is bumped when shipped geometry
  output changes.
- Runtime GPU meshes are released after each map while the disk cache remains,
  so prebuilding does not permanently keep every map resident in memory.

## Credits

- **DramaticShape** — the upstream Dramatic Shape Voxel Mod this is a fork
  of (v1.6.2, github.com/DramaticShape/DramaticShapeVoxelMod). Its own
  code carries no license; PotatoVoxel is a derived work.
- **pret/pokered** — the tile and sprite data the geometry is derived from.
- **bryanthaboi/gen1recomp** - for all his fantastic work and creating the gen1recomp that made this mod possible
