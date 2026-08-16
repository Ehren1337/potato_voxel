# 04 — Object Voxelization: Per-Pixel Props, Grass, Flowers, Figures

The most "voxel" part of the mod: small drawn things (plants, signs, lone
trees, fence posts) become **per-pixel voxel prisms** — every opaque art
pixel is a 1x1x(depth) column standing on the ground, textured with its
own texel.

## The background flood (extractObjects, Structures.lua:2448-2689)

Tileset art has **no alpha**, and white is a paint colour (window frames,
wall stripes) — so "background" cannot be detected by colour alone. The
map decides: **background is the white that connects to walkable ground
in the assembled scene.**

The region is re-imaged at pixel granularity, bbox + 1 px apron:

```
state per pixel:
  solid   member art (non-white)
  cand    member white — the flood decides
  air     walkable: INSIDE the bbox (gaps between fence posts)
          and the SOUTH apron row (where a prop's white meets the ground)
  barrier everything else (neighbouring structure, void)
```

Rules (Structures.lua:2461-2520):

- **Outdoors:** only the south apron is air — the direction the viewer
  reads background from. A flood allowed around the sides would pour in
  from the north and shred roofs into misdetected sprite clusters (it
  did).
- **Indoors:** all four aprons seed (furniture backs onto walls, bottom
  rows meet the void ring; no roofs to protect).
- **Forced (pinned) props:** every apron seeds and interior non-member
  pixels are `iair` — the pin IS the classification, so a vase boxed in
  by its table still gets cut out (Structures.lua:2504-2511).

Then flood from every air cell through `cand` (and white-run rules for
the strict `cutout` pool). What survives the flood is the object.

### Forced-prop segmentation (pinned billboards etc.)

Objects wear a **black outline**; background = whatever shades touch the
cluster's edge (the rim vote, Structures.lua:2541-2577) — or the
profile's `prop_bg` override when the drawing's own body reaches its
bbox edge and votes itself away (the Centers' pots — their olive base is
drawn flush with the bottom row, so "dark" must NOT be background there,
but the healing consoles' screens DO stand on a dark wall band and need
dark voted out — keyed by tile, not tileset). `cutout` is stricter: mid
shades always background, whites drain only along white runs reaching
the ring.

## Sprite-like detection and clustering

- Per tile: fraction of flooded (background) pixels ≥ `TILE_BG_RATIO`
  (0.20) → sprite-like (Structures.lua:2630-2648).
- Sprite-like tiles cluster 4-connected; each cluster is validated as ONE
  prop (buildObject, Structures.lua:2694-3009):
  - `rows <= OBJECT_MAX_ROWS` (6, i.e. 48 px of drawing).
  - Must touch flat ground (south, outdoors; any side indoors).
  - **No vertical repetition** — a repeating column (tree wall edge) is
    scenery, not a prop.
  - ≥ 5 % background (a silhouette must actually exist), ≤ 4096 quads.
- Failed clusters fall back to the volume path (`leftover`).

## buildObject: the voxel prism

Per solid pixel (Structures.lua:2904-2939):

```
voxel column at (wx0+lx, y, z0..z1), depth = OBJECT_DEPTH (6 voxels)
  front face (+z, toward camera)  wears the pixel's own texel, shade 1.0
  back face (-z)                  same texel, shade 0.68
  top / bottom / sides            only where a neighbour is absent
                                  (hidden-face culling), shades 1.0/0.55/0.78
```

- **Connected components** (8-connectivity): one cluster can hold
  several objects (two stools, a leaf beside a vase). Each component
  stands on its own feet in the depth band of the tile row its lowest
  pixel is drawn in — stacked drawings become separate standees, not one
  tower (Structures.lua:2836-2880).
- **`cutout` / `console` are ONE object by contract**: only the largest
  component survives, killing loose black scraps (cast-shadow edges,
  seams) (Structures.lua:2890-2902).
- **Depth per class** (PINNED_DEPTH, Structures.lua:104-105):
  `billboard` 10, `prop` 5, `stool` 10, `cutout` 1 (paper), `console`
  10, `post` 6, `signpost` 2 (a plate on a stick), `bike` 2 (a line
  drawing whose negative space is the drawing — any thicker and the
  side faces close every gap).
- **Support lift**: a pinned prop drawn above an authored box in a
  BLOCKED cell stands ON the box (monitor on desk). Blocked-cell test is
  the discriminator — a chair drawn against a table's north side is in a
  walkable cell and stays on the floor (Structures.lua:2786-2826).
  Furniture supports (`desk`, `table`, `counter`) keep the claimed tile
  rendering as the box; full-height supports (`wall`, `cliff`,
  `bookcase`, `building`) become synthesized floor (Structures.lua:
  2956-3007).
- Synthesized ground: commonest flat tile touching the cluster, painted
  under every claimed tile (Structures.lua:2944-2955).

## Relief props (buildRelief, Structures.lua:1633-1735)

A `relief` cell is drawn FROM ABOVE (a console on the floor): standing it
up would be wrong. Segment like a forced prop (black outline; edge shades
are background), then extrude each object pixel **straight up `h` voxels**
(3), art on the TOP face. The removed floor is repainted by the claimed
tiles' common-ground fill.

## Bookcases (buildBookcases, Structures.lua:1998-2094)

A drawn bookcase is TALL, not deep (32 px high, 16 px deep plot).
Columns of `bookcase` tiles collapse in **ranks** (≤ 4 drawn rows each,
measured from the south): every rank raises ONE box over its front two
tile rows — the drawing folded up its south face band by band — and its
back rows become hidden floor. An unpinnable trim row above the run
becomes the rank's CAP. Ranks of the same height standing side by side
form a BANK, and the bank's front carries measured **pane relief**:
every non-black region the drawing seals behind its own black frame
(≤ 24 px) sinks one voxel behind the proud frame, with sill/lintel
reveals (bookcasePanes / bookcaseRank, Structures.lua:1773-1996).

`bookcase_backfill = "above"` hands vacated rows the cell above (a wall
set into a terrace); `bookcase_relief = false` keeps masonry fronts
flush (the League's gate walls, Bill's transporter drums).

## Stairs (buildStairs, Structures.lua:2115-2279)

A `stair_e/w` cell becomes a flight of `STAIR_STEPS` (4) boxes rising
across the cell toward the named side; `stair_down_*` is the same flight
EXCAVATED below floor level (an open stairwell with walls). The 2D
staircase is drawn from the side, so vertical faces wear the matching
slice of the drawing (the railing's diagonal lands along the stepped
silhouette) while treads sample the art band drawn at their own height.

## Authored figures (buildFigures, Structures.lua:3210-3361)

A figure drawn INTO furniture cannot be segmented by any flood (no
background margin, same shades as the furniture). The profile authors
the silhouette **pixel by pixel** (TileShape.lua:452-573):

```lua
figures = { {
  w = 2,                    -- tiles across
  tiles = { ...w*h ids, row-major... },
  under = { ...what each tile wears once the figure is lifted off... },
  pixels = { "...", ... },  -- h*8 strings of w*8 chars, "." = not the figure
  depth = nil,              -- ABSENT = a person (flat card); present = object
  thin  = { rows=..., depth=... },   -- cap top rows' thickness
  flat  = { x={lx0,lx1}, rows={r0,r1} },  -- a top-view surface laid flat
} }
```

- Matched by **tile pattern** across the map (one blockset entry places
  the couch in all eleven Pokemon Centers).
- **No `depth`** → a person: a flat sprite card in its own local space,
  drawn the way SpriteBillboards draws a character (leaned back at draw
  time), standing at its feet on the furniture. A figure is a face-on 2D
  icon; extruding one reconstructs a body nobody drew.
- **With `depth`** → an object (the Marts' cash register): a per-pixel
  voxel slab in world space via `maskSlab` (Structures.lua:3034-3083),
  anchored at the front edge of the tile row its feet are drawn in,
  growing north. `thin` caps the receipt curl; `flat` lays the keypad
  plate horizontal one voxel proud via `maskPlate` (Structures.lua:
  3107-3169).
- The lift test matches buildObject's: blocked cell + tallest authored
  upright below (Structures.lua:3237-3248).

## Mounted objects (buildMounted, Structures.lua:3388-3433)

Same authoring premise, for things drawn INTO a wall band (the Bike
Shop's bicycles): mask IS the classification, builds headless. Unlike a
figure it keeps its **drawn elevation** (a hung bike stays hung) and has
**thickness** (`depth`, default 2) jutting SOUTH of the band's face, in
world space. The wall behind is repainted with `under` tiles.

## Tall grass (buildGrass, Structures.lua:3531-3640)

- Only where `map:isGrassCell` (the cell's collision tile is grass) —
  the grass GRAPHIC also appears as decorative filler in ground blocks;
  a tile-level test sprouted tufts all over town plazas.
- One tile = ONE standing piece: a thin per-pixel slab (front + back
  faces 2 voxels apart) over the flat grass base the tile already
  renders. **The player walks between the two tile rows of a cell** and
  the southern row overdraws feet (the GB grass-over-feet trick, 3D
  version).
- Runs of adjacent pixels merge into single quads; one template per tile
  id stamped across the map.
- Drawn as its OWN mesh AFTER the characters, with the same camera-ward
  pull, so depth fights resolve correctly (ChunkMesher.lua:886-892).

## Flowers (buildFlowers, Structures.lua:3644-3874)

- The animated flower tile stands as a billboard **1 voxel deep**, cut to
  the drawing's darkest tones PLUS everything they enclose (the round
  hull's rule).
- The mesh is static but the flower is not: the geometry spans the UNION
  of the mask over the base art and every animation frame, and
  TerrainAtlas rewrites the tile's atlas slot each step with only the
  CURRENT frame's mask opaque — the rest keyed to alpha, which the voxel
  shader discards. **The sway animates in texture space; no vertex
  moves** (09).
- Every pixel gets a cap on all four remaining faces (the "everyPixel"
  sideQuads rule, Structures.lua:3378-3412): a pixel that drops out of a
  frame takes the union's wall with it, so each pixel carries its own
  edges, inset a hair to avoid z-fighting.
- Own mesh, drawn after characters with a slightly REDUCED pull (one
  tile row of northness) so a flower on the player's own cell stays
  behind their card (VoxelScene.lua:1246-1265).
