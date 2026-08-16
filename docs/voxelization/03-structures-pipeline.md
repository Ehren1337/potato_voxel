# 03 — The Structures Pipeline: Detecting What Is on the Map

`lib/Structures.lua` is the 3dSen-style scene analysis: it turns the
tile layer into a list of *things* (volumes, objects, hulls, stamps) the
mesher can emit. Everything is derived **per map and cached**
(`Structures.forMap(map)`); pixel access degrades gracefully headless.

The method, from the header (Structures.lua:1-42):

1. Flood-fill every connected region of solid tiles.
2. Decide which art pixels are BACKGROUND (white that connects to
   walkable ground — whiteness alone says nothing; window frames and
   wall stripes are white too).
3. Tiles whose art is mostly background are **sprite-like** → per-pixel
   voxel OBJECTS (thin depth, real drawn height, standing on synthesized
   ground).
4. Everything else is a **VOLUME**: columns rise to the height the
   structure is actually DRAWN (repeat-aware: a 40-row border forest is
   rows of 16 px trees, not a monolith).

## Pass order (Structures.forMap, Structures.lua:159-555)

Order matters — each pass claims tiles so later passes never see them:

| # | Pass | What it does | Claims |
|---|---|---|---|
| 1 | Grid resolve | Shape + tile for every cell in body + 12-tile ring, via `TileShape.at`. Ring uses `TileRenderer.borderBlockFor` (trees for overworlds, NOT the tileset's own borderBlock — a route's borderBlock is grass). Void tiles → `void`. | — |
| 2 | `Buildings.build` | Match building templates (houses, desks, the Tower) by tile grid; build one model per template, stamp at every placement. | skips all template tiles (and `keep`-listed tiles stay live for standees) |
| 3 | Door fold | Door cells (walkable, warp onto them) become `wall` so the facade is continuous; marked `doorFold` so buildVolume gives the column the region's height. Profile pins win over the fold. | shapeAt → wall |
| 4 | `buildCylinders` | Round-pinned cells (tree canopies, planters, stumps, cans) → hull templates, one per distinct art signature, stamped. | skips cells, roundStamps |
| 5 | `buildStairs` | Pinned stair cells → 4-step flights (or excavated stairwells). | skips cells |
| 6 | `buildBookcases` | Pinned shelf columns → ranks collapsed to one cell of depth, pane relief. | skips rows |
| 7 | `buildFigures` | Authored pixel-mask figures painted INTO furniture → lifted off, stood up (people as flat cards, objects as slabs). Repaints `tileAt` so later passes see the furniture without the figure. | repaints tiles |
| 8 | `buildMounted` | Authored masks drawn INTO wall bands → per-pixel slabs jutting south of the wall. Repaints the plain panel behind. | repaints tiles |
| 9 | Region flood | 4-connected flood of *structural* tiles (art == "upright" AND not authored) into regions (Structures.lua:346-379). | — |
| 10 | Per region: `extractObjects` → `buildVolume` | Carve sprite-like clusters out; raise the rest as volumes (04, below). | object tiles; volume runs |
| 11 | Billboards / posts / relief | Profile-pinned standee pools, extracted per class (pools cluster separately so touching drawings never stack). Fence posts extract PER CELL (each cell's posts stand in their own depth band). Relief props extrude from top-down drawings. | skips |
| 12 | `buildGrass` / `buildFlowers` | Tuft rows and animated flower cutouts (body only). | flower skips + synthesized ground |
| 13 | Ground vote | Every claimed cell with unresolved ground (`false`) gets the map's commonest flat ground tile; `prop_ground` pins override per prop (Structures.lua:515-551). | — |

## The ring and border handling

- The **ring** is 12 tiles of border blocks around the body (RING=12,
  Structures.lua:56) — the same width the 2D renderer draws, so both
  modes end at the same place.
- **Trees fill stops at ROUND_RING**: beyond it, tree cells are not
  carved into hulls and `tileLookup` answers nil → open sky (BLACK). The
  shipped build sets ROUND_RING = 12 (full ring, cheap billboard hulls)
  (BrickProfile.lua:142, Structures.lua:190-218).
- `hullRingOnly` (S.hideBareRing): on tree-ringed overworlds, ring cells
  nothing claimed are dropped by the mesher rather than left as
  flat-topped boxes beside carved trunks (ChunkMesher.lua:471-481).

## The region flood (step 9)

Structural = `art == "upright"` and not authored (Structures.lua:298-301).
Authored tiles are profile-pinned and keep their authored shape — they
never join a region. The flood is a simple 4-connected BFS with
`Budget.tick()` inside, producing `{tiles, minX, maxX, minY, maxY}`.

Each region then either:
- gets `extractObjects` applied (if pixels are available) which returns
  the *leftover* tiles, or
- goes straight to `buildVolume` (headless).

## Claiming (`S.skip`) and synthesized ground (`S.ground`)

When any specialist builder (buildings, cylinders, objects, stairs,
bookcases, grass, flowers) takes a cell, it sets `S.skip[key] = true`.
The mesher then:
- paints a flat **synthesized ground** quad under it (the art that was
  there now stands up as the object), using the tile voted from flat
  neighbours or `prop_ground`, and
- emits the prebuilt quads (S.objectQuads / grassQuads / flowerQuads /
  roundStamps) on top.

Skip is also how the mesher knows a claimed cell is NOT water at height
-2: it still emits below-ground shoreline bands when water is next door
(ChunkMesher.lua:483-515).

## Heights: buildVolume, repeat-aware column runs

`buildVolume(S, map, tiles)` (Structures.lua:2286-2422):

1. Group leftover tiles into **vertical runs per column**.
2. Each run reads its own height:
   - `unit = min(extent, MAX_ROWS=6)` — at most 48 px.
   - **Repeat detection**: scan down the column for a tile equal to the
     front tile → the repeat period is the drawn unit (a border forest's
     2-row canopy → 16 px trees, not a monolith).
   - **Trim-foot rule**: if the two rows above the front are identical,
     the column is a repeat wearing a one-row trim foot → unit 2
     (Routes 3/4 cliff mesas) (Structures.lua:2336-2341).
3. **Region consensus**: the mode height of the region wins. A column
   that read a repeat *adopts* a taller mode height (the column above a
   doorway belongs to its 48 px house); a column that read its full
   extent keeps it (an attached low wing stays low). Doorway columns
   answer to the region entirely (Diglett's Cave cave-mouth fix).
4. **Roofs** (outdoors only, h ≥ 16, not a flat repeat): `roofRows`
   ≤ 2 rows, `rise = roofRows * 8`, `peak = h`, `h = h - rise` (facade
   height). **Only pitched roofs slope**: if the top two rows are
   identical the roof stays level (a flat rooftop repeats one texture
   tile; tilting it reads as a ramp) (Structures.lua:2399-2417).

The mesher reads `S.runs` for the fold rule and gable building (07).
