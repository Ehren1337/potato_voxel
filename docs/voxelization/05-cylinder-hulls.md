# 05 — Cylinder Hulls: Round Scenery From Flat Sprites

Tree canopies, potted plants, stumps, and bins are *round* drawings —
a ball drawn over background grass. The mod carves them into real
**voxel hulls** cut from the art itself (`roundTemplate`,
Structures.lua:632-1403).

## The mask: "darkest outline plus its enclosure"

The art's mid-greens pass any brightness test (they inflated the first
lathe attempt to full width), so the tree's own **darkest pixels** are
what bound it (Structures.lua:567-595):

1. Classify every canvas pixel into the four GB shades by its darkest
   channel (`Structures.shadeClass`, Structures.lua:2432-2437).
2. **4-connected flood** from the canvas border through every non-black
   pixel. What the flood cannot reach is the tree: black outline +
   everything it encloses.
3. **Fallback for dither** (the border tree wall is a black/canopy
   checker with no drawn ring): if the enclosure is tiny
   (< NX·NX/8 non-black pixels), re-flood passing only LIGHT and WHITE —
   black and dark together become the boundary, and the dither mass
   itself becomes the mask (a 4-connected flood cannot thread a diagonal
   checker).
4. Per **band** for stacked canvases (the planter): each 16-row band
   decides independently, because the leaf crown and the pot want
   opposite answers (the pot is a solid dark body whose base runs flush
   to the band edge — the enclosure flood would gut it).

## The volume: rows become discs

The canvas is NX wide and NX DEEP (a hull is round in plan — its depth is
its width), NY tall (NY = NX for a ball; 2·NX for a drawing stacked two
cells high on one cell of plot) (Structures.lua:634-645).

- Per mask row: the row's span gives a centre and half-width; every mask
  pixel's column runs that circle's **chord** in z, quantized to whole
  voxels (Structures.lua:978-1012). Front view = the sprite; plan view =
  the sprite's own width profile turned in depth.
- Rows below the mask (the drawn shadow) repeat the bottom row's discs
  to the ground — the canopy stands on a short dark foot.

## The skin: where each face gets its texel

- **Front and back faces**: the drawing per-pixel (back mirrored,
  sprite-pure); columns sharing a chord plane merge into runs (never
  crossing an 8 px atlas-tile seam, since UV interpolation must stay
  inside one tile) (Structures.lua:1230-1298).
- **Sides and steps**: a constant texel per voxel — the *de-outline
  walk* (step inward past black pixels for the first painted colour) so
  flanks read as material, not solid black (Structures.lua:1199-1222).
- **Top cap**: outline only on the rim cells; interior samples the
  canopy a couple of rows deeper (`deepTexel`) — painting the whole cap
  with the outline blacked out every dome (Structures.lua:1189-1197,
  1370-1375).
- **Bottom**: dark undersides where exposed.

Shades: front 1.0, back 0.68, side 0.78, top 1.0, bottom 0.55
(Structures.lua:599-600).

## Ground matching

The ball's drawn background names its floor: score every flat ground
tile the map places against the cell's unmasked LIGHT pixels (dark
unmasked pixels are the drawn shadow and stay out of the score), keep
the closest (Structures.lua:740-771). Falls back to the commonest-ground
vote.

## The five hull shapes

| class | NX | NY | extras |
|---|---|---|---|
| `cylinder` (tree) | 16 | 16 | plain ball |
| `canopy` (2x2-cell group) | 32 | 32 | one hull over the whole group; anchor tile pins it, partners must be round-pinned or the anchor is left alone (Structures.lua:1474-1509) |
| `stump` | 16 | 16 | `capRows` (stump_cap, 6) of the drawn top are the CUT FACE: stripped from the mask, projected across the round cap as an ellipse (Structures.lua:875-894, 1356-1369) |
| `can` (bin) | 16 | 16 | cut at BOTH ends + hollow + tapered (below) |
| `planter` (potted plant) | 16 | 32 | anchor is the NORTH cell; the hull stands in the SOUTH cell (where the pot is drawn — ground contact is the plot); the crown is height, not depth; `spray` caps the top 24 rows to a 5-voxel slab instead of revolving (the leaves are a spray running off all four sides — revolving them produces a hedge column) (Structures.lua:616-631, 1521-1569) |

### The can (Structures.lua:896-966, 1124-1147)

A bin is only round in the horizontal plane, and the GB cell spends most
of itself on the opening:

- **base_rows** (can_base, 4): the drawn base ellipse is ground contact
  — stripped from the mask, the foot rule runs the last body row's full
  disc straight to the floor (keeps its own texels so the drawn base rim
  still shows).
- **can_height** (9 voxels): the surviving body band is repeated upward,
  bottom row first, to the authored height (the drawing alone states a
  squat drum).
- **well**: the top `wellRows` rows hollow — every chord long enough for
  two walls plus a gap keeps a wall at each end (a ring in plan), so you
  can look INTO the bin. The drawn mouth ellipse projects across the
  round top AND down the well walls (mouthRow).
- **taper**: the plan narrows toward the floor (taperVox, 4); rows
  re-cut their chords from the narrowed span (keeping the plan round),
  and the squeeze maps the art into the narrowed span rather than
  clipping the outline.
- Foot rows' sides keep the last body row's material (`sideTexel`
  yBot rule) so the can's flanks aren't black.

## Templates, stamps, and the Brick billboard mode

- **Hull templates dedupe GLOBALLY** per (tileset, tile signature,
  ground set): the same four-tile tree repeats for hundreds of cells, so
  the carve runs once per distinct drawing per session. Maps keep a
  STAMP LIST — `{quads, mx, mz, r}` template + offset — that the mesher
  expands while packing vertices. This is what stopped multi-GB heap
  growth on cross-region treks (Structures.lua:1405-1413).
- **The shipped build never carves**: `HULL_BILLBOARDS = true` collapses
  the whole carve to one flat south-facing card per mask run per row at
  the hull's front plane (~12 quads a tree instead of ~3000), and
  `BILLBOARD_CROSS = true` repeats the card at ±45° about the vertical
  axis (an X cross in plan — ~36 quads, reads as a dome) (BrickProfile
  144-159, Structures.lua:773-869). The Brick's camera is yaw-locked due
  south, so the cards are geometrically correct at every pitch.
- Stamps are **atomic** in the mesher: the trunk (stamp centre) decides
  whether the whole tree is kept or dropped against neighbour-body masks
  — a tree is never cut in half along a map seam (ChunkMesher.lua:787-
  835).
