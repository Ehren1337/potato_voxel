# PotatoVoxel — How the 2D World Becomes 3D

Reverse-engineering notes for the voxelization pipeline in PotatoVoxel
(1.6.x fork of Dramatic Shape Voxel Mod), written so the mod can be
understood, improved, and ported to another engine.

## What the mod does, in one sentence

It replaces the flat tile blit with **real 3D geometry built from the
map's own tile layer and the tileset atlas** — every 8x8 tile is resolved
to a *shape class* (ground, wall, tree, sign, …), connected drawings are
detected and either raised as **volumes** (houses, walls, forests) or
voxelized **per pixel** (plants, signs, grass), and the whole thing is
rendered by a depth-buffered camera with baked per-face shading, ambient
occlusion, real cast shadows, and a voxel wireframe option. **No
gameplay, collision, or script data is touched** — the 3D layer is
purely presentational; the engine's walkable lists keep driving
collision as always.

## The pipeline at a glance

```
map (block layer, 8x8 tiles, 16x16 cells)
  │
  ├─ TileShape      per-tile SHAPE CLASS + height + art mode
  │                  (profile pins override; cells decide walkable→ground)
  │
  ├─ Structures     per-map scene analysis, once per map id:
  │   ├─ Buildings   band-classified building templates (houses, desks)
  │   ├─ buildCylinders  round hulls for trees / pots / bins (stamps)
  │   ├─ buildStairs / buildBookcases / buildFigures / buildMounted
  │   ├─ region flood of solid tiles
  │   ├─ extractObjects  background-flood → per-pixel voxel props
  │   └─ buildVolume     column runs → extruded volumes with real heights
  │
  ├─ ChunkMesher    emit ONE static mesh per map (body + border ring):
  │   └─ quads with atlas UVs, per-vertex shade (AO + face direction)
  │
  └─ VoxelScene / Voxel3D   draw the frame: shadow pass → terrain →
       characters (leaning sprite cards) → water → grass → FX overlay
```

Mesh builds are **asynchronous** (coroutine jobs sliced into per-frame
millisecond budgets) and **cached** (in-memory per map + on-disk in the
mod's scoped storage), so the 3D world streams in without hitching.

## How to read this documentation

| File | Covers |
|---|---|
| [01-world-model.md](01-world-model.md) | Coordinate system, map/tile/cell data model, the shape-class vocabulary |
| [02-shape-resolution.md](02-shape-resolution.md) | How every tile gets a class (TileShape.lua, data/voxel_heights.lua) |
| [03-structures-pipeline.md](03-structures-pipeline.md) | Structures.forMap: the ordered pass list and the region flood |
| [04-object-voxelization.md](04-object-voxelization.md) | Per-pixel voxel props: background flood, standee pools, grass, flowers, relief |
| [05-cylinder-hulls.md](05-cylinder-hulls.md) | Round scenery: trees, planters, stumps, bins (roundTemplate) |
| [06-buildings.md](06-buildings.md) | The band-classified building pipeline (Buildings.lua) |
| [07-chunk-mesher.md](07-chunk-mesher.md) | Geometry emission: quads, UVs, AO, roofs, side folds, seams |
| [08-characters.md](08-characters.md) | Characters as leaning sprite billboards (NOT voxelized — deliberate) |
| [09-texturing.md](09-texturing.md) | TerrainAtlas: palette baking, animated tiles, flower cutouts |
| [10-async-and-cache.md](10-async-and-cache.md) | The async build system, budgets, mesh cache, disk cache format |
| [11-frame-render.md](11-frame-render.md) | One frame: shadow pass, scene passes, water, draw order |
| [12-porting-guide.md](12-porting-guide.md) | How to port the pipeline to another engine |
| [13-extension-points.md](13-extension-points.md) | Where the seams are for improving the mod |

## The three most important files

- **`lib/Structures.lua`** (3892 lines) — the heart. Detection,
  segmentation, and per-pixel voxelization. Header comment explains the
  four-step method (flood regions → background flood → sprite-like
  objects → volumes).
- **`lib/ChunkMesher.lua`** (1686 lines) — turns the Structures analysis
  into one static mesh per map. The geometry is GPU-free and tested
  headless via `ChunkMesher.geometry()`.
- **`data/voxel_heights.lua`** (4484 lines) — the hand-authored PROFILE
  that pins tiles to shape classes, defines building templates and pixel
  masks. This is the "3dSen game profile" layer over the detector.

## Key invariants (repeated everywhere, break at your peril)

1. **World space is world pixels.** +X east, +Y up (0 = ground), +Z
   south. 1 unit = 1 map pixel. A cell is 16x16, a tile 8x8. No unit
   conversion anywhere (Voxel3D.lua:3-12).
2. **One unit per voxel.** The voxel wireframe is a *shader* that darkens
   fragments near integer planes of model space — it only works because
   every mesh is built 1 unit per voxel (VoxelGrid.lua:1-12).
3. **Textures come from the tileset atlas, not a map render.** 24 KB per
   tileset vs ~5 MB per map canvas, and palette baking lives in the
   texture (ChunkMesher.lua:27-33, TerrainAtlas.lua).
4. **Collision is per CELL, judged by the cell's bottom-left tile.**
   Shape resolution uses cell walkability, never tile-level lists, or
   every flower becomes a pillar (TileShape.lua:13-21).
5. **The profile beats the detector; the detector beats the fallback.**
   Resolution order per tile: authored pin → cell water → cell walkable →
   tile-level fallback (TileShape.lua:5-12).
6. **Everything degrades headless / without pixel access.** Every GPU
   object is pcall-guarded; without atlas pixels, regions stay volumes
   and tests still pass (Structures.lua:40-42).

## Numbers that matter

| Constant | Value | Where |
|---|---|---|
| Tile / cell size | 8 px / 16 px | — |
| Border ring | 3 blocks = 12 tiles | ChunkMesher.lua:69, Structures.lua:56 |
| Round-hull carve radius | 12 tiles (Brick sets full ring) | Structures.lua:69 |
| Volume height cap | 48 px (6 rows) | Structures.lua:107 |
| Object max rows | 6 rows (48 px) | Structures.lua:89 |
| Object depth (detected) | 6 voxels | Structures.lua:90 |
| Pinned standee depths | 1–10 voxels by class | Structures.lua:104-105 |
| Mesh build slices | 10 / 4 / 40 ms (urgent/idle/covered) | BrickProfile.lua:192-194 |
| UV inset | 0.02 texel | ChunkMesher.lua:86 |
| AO strength | 2.4 (step 0.09×2.4 per neighbour) | ChunkMesher.lua:278-283 |
| Geometry cache version | 18 | MeshCache.lua:70 |

## Shipped-build specifics (PotatoVoxel, one build everywhere)

- VOXEL ladder is **OFF / HIGH / MEDIUM / LOW / POTATO / CUSTOM**, every
  on-rung at the same 35° camera; rungs differ only in the quality
  preset they apply (BrickProfile.lua:161-175).
- **RENDER SCALE** renders the scene at 100/75/50/33 % of window
  resolution and upscales (main.lua:483-494).
- Round trees are **billboard hulls** (flat south cards, crossed at ±45°)
  instead of carved voxel balls — ~12–36 quads vs ~3000 (BrickProfile
  144-159, Structures.lua:773-869).
- Shadow map sizes 512/768/1024 (1536 fixed for HIGH); sun in the
  southeast at ~45° elevation (ShadowMap.lua:56-57, BrickProfile 204-208).
- Defaults are the potato tuning: water, AA, staged battles off until a
  mode preset turns them on.
