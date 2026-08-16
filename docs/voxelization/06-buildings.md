# 06 — Buildings: Band-Classified Voxelization of Building Sprites

`lib/Buildings.lua` handles the one case the generic pipeline cannot: a
Game Boy building is a **fake-3D projection that packs several facings
into one flat drawing** — the roof is drawn as if seen from above, the
facade face-on, the sloped ends as diagonal silhouettes. Raising the
whole footprint as one box folds all three into a wall. This module
classifies each BAND of the drawing by the surface it depicts and
applies the matching operation per band.

Two rules govern it (Buildings.lua:14-21):

1. **Every visible voxel colour is a real texel of the drawing.**
   Nothing is invented but the geometry the sprite implies and never
   paints (undersides, the depth behind the facade) — and those wear the
   drawing's own four shades.
2. **The sprite is ground truth, not the tile grid.** The silhouette,
   taper rate, eave height and every window are MEASURED off the pixels;
   the profile only says which rows are roof and which are facade.

## The pipeline (per template, Buildings.lua:23-38)

```
read      composite the building out of the atlas; flood its silhouette
          in from the border through light pixels only
measure   topmost drawn row of each column = the roof's elevation profile
          (the drawn taper IS the slope); facade panes = non-black
          regions its black frames seal off
build     facade rows extrude straight back over the footprint; the
          awning band juts past them; panes sink one voxel; the roof
          lays the top-facing rows flat — level over the plateau,
          stepping down the drawn taper at the ends — then overwrites
          the walls it intersects
emit      cull to the shell and merge runs of texel-adjacent faces into
          single quads: a 90k-voxel house ships as ~2k quads
```

One model per template, stamped at every placement: Red's and Blue's
houses are the same seven-placement drawing, so they cost one build
between them (Buildings.lua:1269-1360).

## read (Buildings.lua:156-276)

- Composite the template's tile grid (`tiles`) out of the atlas; sample
  each pixel's shade class once (a tile recurs in many templates).
- **Silhouette flood**: seed the drawing's border through pixels ≤ GREY
  (white, grey) — black outline AND #555 shading together are the
  boundary; a "not black" test would eat the shaded flanks. `seal`
  names sides the drawing runs off (a brick base course flush to the
  art) where the flood must not seed.
- `topRows`: extra drawing rows composited ABOVE the matched grid — the
  Pokemon Tower straddles the Lavender/Route 10 boundary, its roof band
  standing in the route's last rows (Buildings.lua:147-155).
- `scrub`: pixel rects where an object stands ON the surface (Red's
  potted plant on the dining table); those pixels take a donor field
  texel so the model's top is the plain surface the object sat on — the
  object keeps its own standee via `keep`.

## measure (Buildings.lua:280-451)

| measurement | how |
|---|---|
| `top[x]` | first drawn row of column x = how far the roof has stepped down there — **the drawn taper is the slope** |
| `surfaceTop[x]` | first PAINTED row (skipping outline black) — the surface belongs there, not on the outline pixel, or the courses beat against it |
| `ground` | row after the last drawn one (furniture legs stop short of the grid — extruding to the grid would float it) |
| `interior` | de-outline walk: a black side pixel samples the first painted colour inwards, so flanks are material, not outline slabs |
| `recess` | panes = non-black regions the drawing seals behind black frames, each < RECESS_MAX (24) px — windows and doors sink a voxel; frames stay proud (nested frames layer for free). `panes = false` for drawings with inverted polarity (the healing machine's dark screens behind white bezels) |
| `shadeTexel` | one representative texel per shade, for synthesized surfaces (fascia, undersides) |
| `D` | depth = matched footprint (in tile rows or `depthPx` voxels), NOT sprite height — the Tower's 16-row drawing stands on 8 rows of plot |

## build — the voxel model (Buildings.lua:938-1051)

The model is a lookup `at(x, y, z)` → sprite pixel index (or nil), built
in an order that IS precedence — **roof first, so it overwrites the
walls it intersects**:

- **Roof**: a solid of constant thickness (`slab`) following the
  elevation profile. The surface wears `roofSy[z]` — drawn rows mapped
  back-to-front (top rows = far edge, bottom = eave), rims one row per
  voxel, the middle cycling the course rhythm picked up where the north
  rim left off. The rim reproduces the drawn eave: black outline,
  shaded fascia, closed by outline (a GREY fascia turns WHITE once the
  atlas is recolored — hence the black/DARK choice).
- **Awning** (`ledge`): the band juts two voxels past the walls, front
  and back.
- **Facade**: rows extrude straight back over the footprint, mapped
  against the measured ground line; the front face (z = D-1) is the
  drawing, the back (z = 0) the drawing, the interior the de-outlined
  texel. A recess DELETES the front voxel so the one behind shows as
  the pane.
- The base course sits one row above y=0 when the drawing's last row is
  the ground it stands on.

## desk sets and parts (deskSetModel, Buildings.lua:466-932)

Templates with `parts` classify at PART granularity — the lab tables
with monitors/keyboards, the healing machine, Bill's computer:

| part kind | what it is |
|---|---|
| `flat` | a sheet lying on the desk plane, drawn row = depth row 1:1, optional `thick` body and `at`/`z` origins |
| `box` | a drawn rect standing at its own drawn elevation (equipment attached to a machine); height beyond the drawn rows fills from the top 1:1, then cycles, then from the bottom |
| `iso` | a box drawn in 2:1 isometric — un-projected by running the projection backwards: the drawn rhombus's x radius is the half-width, half that the z radius, the near corner's row the base; `plan` names the real z radius (the drawing cannot state it) |
| upright (default) | a facade band folded up with a lid: top rows laid across the depth from the back, `inset` sinks authored panes, `rise`/`z` lift it off the plane |

- **Tray**: an open container (a tool box) — top-view band is the INSIDE,
  four walls stand to the rim, a floor slab lies under the opening, the
  cavity is air. NO recess pass here (a one-voxel wall would open
  straight through).
- The desk itself: fascia rows wrap every side (the slab), base band
  extrudes like any table, and the **lid** is either the drawing's own
  top band (`desk.top` — the healing machine paints its tabletop) or
  synthesized from the sibling tables' pattern (black rim, white
  highlight courses, grey field) in the drawing's own shades.
- `wall` element: the band a machine backs onto (the drawing shows only
  stripes behind it) — the block cycles the drawing's own stripe unit at
  wall-band height.

## emit — cull and merge (Buildings.lua:1060-1247)

- Materialize the voxel volume, count voxels and the shell (faces with
  ≥ 1 absent neighbour).
- Faces collapse into ONE quad when a run's texels are the **SAME**
  (flat-coloured strips — most sides) or **ADJACENT IN THE ATLAS** along
  the run (the drawing continuing — most fronts and roof tops). Both
  keep every texel exactly where the sprite put it.
- **Runs stop at the next 8 px lattice line** (`runCap`): the world
  curve drops every vertex by the square of its distance, so a long quad
  is the chord of a parabola while short neighbours draw the arc — the
  join tears open (a 102 px run hung 3 px under the roof surface and the
  eave tore off). Capping at 8 px bounds the sag under a twentieth of a
  world pixel (Buildings.lua:75-107).

## placement (Buildings.lua:1249-1441)

- Templates are anchored by their north-west tile; a reverse index lets
  a template examine only positions carrying its anchor.
- **First claim wins** — list order is priority order (the Tower's own
  templates come first so a 6x6 block tile behind it isn't matched as a
  second building).
- `stamp` claims the tiles (shape `{class="building", art="building",
  authored=true}` — the detector never touches them), votes the ground
  from flat neighbours, and copies the model's quads into place with
  `own = true` (exempt from the mesher's edge keep-rules: an edge-row
  house's eave legitimately overhangs the seam).
- `keep` lists tile ids that must NOT be claimed (their pins stay live —
  the standee scan still stands the plant); `support` states the model's
  top plane so a standee standing on the building is lifted to it.

## Reference implementation

`mods/DRAMATIC_SHAPE/tools/building_voxels.py` is the reference
implementation of the same algorithm; `Buildings.stats()` reports the
voxel/shell/quad counts it must agree with (Buildings.lua:42-45,
1446-1453).
