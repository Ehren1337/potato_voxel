# 07 — The Chunk Mesher: Turning the Scene Record Into One Mesh

`lib/ChunkMesher.lua` emits the static geometry: **one mesh per map**
(plus a body-only variant and aux meshes), textured from the tileset
atlas, with per-vertex shading baked in. The geometry core
(`runGeometry`) is GPU-free and exercised headless via
`ChunkMesher.geometry()`.

## The vertex format and shading model

Every vertex is `{x, y, z, u, v, shade}` (Voxel3D.FORMAT,
Voxel3D.lua:45-49). The shade carries:

- **Face direction** (FACE_SHADE, Voxel3D.lua:63-70): top 1.0, south
  0.90, east 0.84, west 0.72, north 0.68, bottom 0.55. The sun hangs in
  the southeast; an away-facing wall is dark because of its ANGLE, which
  no shadow map measures.
- **Baked ambient occlusion** (below), per corner, interpolated by the
  rasteriser.

## runGeometry: the emission loop

The map body plus a RING of 3 border blocks (12 tiles, ChunkMesher.lua:
69) is scanned tile by tile (ChunkMesher.lua:457-679). Per cell:

1. **Top face** — three cases:
   - `run.rise > 0`: a **gable segment** — the roof rises from the
     facade top at the south eave to a ridge across the footprint's
     middle, falling back at the north edge (a shed plane rising all
     the way north turned buildings into ramps). The south slope wears
     the structure's roof rows (ridge art at the ridge); exposed
     east/west flanks **hip** — their outer edge drops toward the eave
     (ChunkMesher.lua:521-558).
   - flat-topped volume run: wears the run's top rows, cycling a 2-row
     unit (`run.north + (ty - run.north) % min(2, extent)`).
   - plain cell: its own tile — except an **authored upright box**, whose
     top wears the nearest row above the face block (the drawn tabletop
     stays on top) via the north/front scan (ChunkMesher.lua:565-601).
   - Water cells' tops route to the **water sink** (the one class drawn
     as its own reflective pass) (ChunkMesher.lua:607-609).
2. **Side faces**: for each of the four directions, wherever the
   neighbour is lower, emit 8 px bands spanning `[max(nh, 8k),
   min(h, 8k+8))` — **never stretched**, art cropped at partial bands
   (ChunkMesher.lua:615-676).
3. **The fold rule** (the heart of how art stands up):
   - Volume run: band k samples the map row `k` tiles north of the
     structure's front, clamped to its extent. The **south face is the
     drawing itself at full brightness**; the other sides wear the same
     rows darkened, so a building's flank matches its face instead of
     smearing one tile (ChunkMesher.lua:630-644).
   - Authored upright (pinned wall/furniture): same fold from the
     southmost same-class row, repeating past the top; south face full
     brightness (ChunkMesher.lua:645-669).
4. **Shoreline bands**: below-ground side bands expose the water's
   recessed sheet (nh < 0 → bands down to nh), including around
   synthesized ground plots.

### UVs (ChunkMesher.lua:71-86, 246-253)

- `uvRect(tile, vTop, vBot)`: one 8x8 atlas rect, optionally cropped to
  art rows.
- **INSET = 0.02 texel** keeps a quad's sampling inside its own tile —
  without it the perspective rasteriser lands on a neighbouring tile's
  texel along shared edges and stitches bright seams. It must be a
  sliver, not half a texel: the art advances 7/8 texel per pixel and
  boundaries drift off the pixel grid (ChunkMesher.lua:71-86).
- Side-face `u` follows +X on north/south faces so a door or sign never
  draws mirrored.

## Baked ambient occlusion (ChunkMesher.lua:255-364)

AO is the complement of the shadow map: the dark seam in corners the
sky cannot see into, at every scale finer than a shadow-map texel.
Baked per vertex, resolution-independent:

- `aoShades`: a top face's corners each count the three crowding cells
  (two edge neighbours + diagonal; a diagonal wedged behind both edges
  adds nothing — counting it again turns an inside corner black). Step
  down once per neighbour, floored at 0.25. Constants: strength 2.4,
  step 0.09×2.4.
- `sideShades`: the CREASE a band rises out of (AO_EDGE), the INSIDE
  CORNERS where flanking columns stand proud (AO_CORNER = edge²), and
  the top corners' edge term.
- `groundShades`: prebuilt prop quads have no columns to count, but the
  ground plane blocks half the sky — the closer a voxel sits to it
  (within 6 px), the darker (0.12×2.4 at contact). This is what plants a
  prop on the floor instead of pasting it on top.

## Claimed cells: objects and stamps (ChunkMesher.lua:681-835)

- **Synthesized ground** is painted under every claimed cell (the
  `S.ground` tile), plus shoreline bands where water is next door.
- **objectQuads** (per-pixel props, buildings, relief, bookcases,
  stairs, figures-with-depth): emitted with keep-rules against the body
  rect and neighbour-body masks — `overBody` for body-only, `maskedClosed`
  + `outwardOnEdge` (winding test) for the full variant, so a structure's
  outward facade on the boundary plane survives while inward ring scraps
  die (ChunkMesher.lua:695-724).
- **roundStamps**: expanded in place through scratch corners (no
  allocation). The **trunk decides**: a stamp whose centre is under a
  neighbour body is dropped WHOLE (a tree would rise through the
  neighbour's flat ground); a trunk on this map's side keeps the whole
  stamp, canopy overhang and all — the depth buffer sorts it
  (ChunkMesher.lua:787-835).

## The border ring and neighbour masks

- **bodyOnly**: the shape the 2D path's drawMapOnly has always had — no
  ring. Neighbours contribute bodies only.
- **full**: the ring, with `masks` (rects where connected neighbour
  bodies sit) suppressing ring geometry under them — the 2D renderer
  painted neighbour bodies OVER the ring; with a depth buffer, a ring
  tree would rise straight through the neighbour's flat ground
  (ChunkMesher.lua:204-219).
- `hideBareRing`: on tree-ringed overworlds, ring cells nothing claimed
  are dropped (see 03).

## The water split

With a `waterSink`, water-class tops are routed to a SECOND mesh: a
mirror cannot be drawn until what it reflects exists. The shoreline
faces stay in the ground mesh. Both meshes always come from the SAME
build — pairing a full mesh with a body build's water would draw the
ring's ponds twice (ChunkMesher.lua:219-227, 1521-1526).

## The aux meshes

- **Grass**: tuft rows as their own mesh, drawn AFTER the characters
  with the same camera-ward pull — the southern tuft row still overdraws
  a walker's feet (ChunkMesher.lua:886-892).
- **Flowers**: the same for flower cutouts, with a reduced pull (one
  tile row of northness) so a flower on the player's own cell hides
  behind their card; still casts shadows (ChunkMesher.lua:894-904).
- **Figures**: one mesh per authored figure, in the card's OWN local
  space — each is placed by its own leaning matrix at draw time
  (ChunkMesher.lua:906-933).

## Caching and invalidation (see 10 for the async system)

- Per map id: `{ full, body, fullWater, bodyWater, grass, flowers,
  figures, stale }`.
- `setLive` evicts everything outside the live set PLUS the previous one
  (stepping into a house keeps the town warm; two neighbourhoods
  bounded) (ChunkMesher.lua:1588-1627).
- `invalidate(mapId)` / `refresh(mapId)`: the latter keeps the stale
  mesh drawing while the replacement cooks — a one-block edit (Cut, a
  door stamp) never blinks the world to 2D (ChunkMesher.lua:1559-1586).
- The engine's `Assets.register` handoff is skipped on the first boot
  callback (and on Switch until any real mesh work exists) or every
  launch would drop the manifest and force a cold 444-job prebuild
  (ChunkMesher.lua:1657-1684).
