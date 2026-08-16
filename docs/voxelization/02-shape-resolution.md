# 02 — Shape Resolution: How Every Tile Gets a Class

`lib/TileShape.lua` answers one question: **given a tile id at a
position, what 3D shape is it?** This is the first stage of the whole
pipeline and everything else consumes its answer.

## The resolution ladder (TileShape.lua:5-12, 421-450)

Per tile, in order — first match wins:

1. **Authored pin** — the tile is named in `data/voxel_heights.lua`
   (`tilesets[<id>].<class> = { tile ids }`). Bypasses detection entirely.
2. **Cell is water** → `water` (recessed flat sheet).
3. **Cell is walkable** → `ground` (flat).
4. **Tile-level fallback** → tile is in the map's water set → `water`;
   in the map's walkable list → `ground`; anything else → `wall`.

### Why cell granularity (steps 2-3) is load-bearing

A tile in a *walkable cell* is ground the player stands on, whatever the
tileset's walkable list says about that tile id. The other three tiles of
a cell carry no collision meaning, so a pure per-tile lookup misfiles
every decorative tile: **flowers become 16 px pillars, fence gap tiles
become wall, grass tufts extrude** (TileShape.lua:13-21). Hand-authoring
(rule 1) is the only thing that overrides cell walkability.

### Derived pins (no profile entry needed)

- `tileset.grassTile` → `grass` class (standing tufts) (TileShape.lua:398-401).
- Tiles animated by frame rewrite (`animatedTiles` specs with
  `kind == "frames"`) → `flower` class — the animated meadow tile stands
  as a 1-voxel cutout (TileShape.lua:363-377).
- **Void tiles**: tiles whose art is entirely black or transparent
  (interior darkness) resolve to `void` and never extrude, whatever class
  they got (Structures.lua:126-149, applied at 228-230 — authored pins
  still win).

## The profile file: data/voxel_heights.lua

Loaded through `V.data("voxel_heights")` (the mod's own loader, not
`require` — a mod dir is not on the module path). Absent or broken, the
mod degrades to the derived defaults — a rougher-looking world, not no
world (TileShape.lua:217-229).

```lua
return {
  heights = { class = px, ... },          -- global overrides of the
                                          -- FALLBACK_HEIGHTS table
  tilesets = {
    ["OVERWORLD"] = {
      heights = { table = 6 },            -- per-tileset class heights
      ground = { 0, 1, ... },             -- class = { tile ids }
      wall   = { 3, 4, 5, ... },
      tree   = { ... },
      ledge  = { ... },
      when_above = {                      -- conditional pins, per tile
        [0x32] = { { above = { ... }, class = "counter" } },
      },
      when_below = { [0x0D] = { { below = { ... }, class = "rock" } } },
      figures = { ... },                  -- pixel masks (see 04)
      mounted = { ... },                  -- pixel masks on walls (see 04)
      prop_bg  = { { tiles = {...}, shades = {"light","white"} } },
      prop_ground = { propTile = groundTile },
      bookcase_backfill = "above",        -- or nil
      bookcase_relief = false,            -- default true
      stump_cap / can_cap / can_base / can_height / can_well / can_taper,
      buildings = { ... },                -- building templates (see 06)
    },
  },
}
```

## Conditional pins: when the same tile means two things

A tile id maps to ONE shape, but one graphic can be used for two things.
The route-gates' `$32/$33` is the canonical case: it is the wall's dark
base course AND every service counter's front (TileShape.lua:257-279).
`when_above` / `when_below` carry rules evaluated **per position**, where
the map and coordinates are in hand:

- `above`: the tile *above* (ty-1) is in the named set → class.
- `below`: the tile *below* (ty+1) is in the set → class (the Plateau's
  top-band/base-course `$0D` splits only on what is BELOW it).
- First match wins; no match keeps the ordinary pin. Resolved in
  `TileShape.at` (TileShape.lua:426-443) BEFORE the cell rules — an
  authored answer outranks detection.

**Gotcha:** `map:tileAt` border-extends — one row off the map answers the
border block, so a rule listing that block fires along the whole edge
(TileShape.lua:429-432).

## The resolution cache

- `TileShape.forMap(map)` resolves **tile-level** shapes once per tileset
  id (the table depends only on the tileset record + profile — the
  per-map part, cell walkability, lives in `TileShape.at`, NOT here)
  (TileShape.lua:326-415).
- `TileShape.at(map, shapes, tile, tx, ty)` does the per-position part:
  conditional pins → cell water → cell walkable → fallback.
- `TileShape.invalidate()` clears everything (hot reload, mod toggle).
- The `classes` subtable holds one canonical shape per class, shared by
  every tile that falls to a cell rule; `condShape` holds separate
  *authored* shapes for conditional-pin classes (TileShape.lua:383-393).

## What the pipeline does with a class

| class resolves to | pipeline route |
|---|---|
| ground / water / void | flat quad at class height (water into its own pass) |
| wall, tree, fence, sign, table, desk, counter, … | volume path: region flood → column runs → extruded box (03/07) |
| cylinder, canopy, planter, stump, can | round hull (05) |
| billboard, prop, stool, cutout, bike, console, signpost, post | per-pixel standee, depth by PINNED_DEPTH (04) |
| grass | tuft rows (04) |
| flower | 1-voxel cutout + animated atlas slot (04/09) |
| relief | top-down extrusion (04) |
| bookcase | shelf-rank collapse (04) |
| stair_* | stepped geometry (04) |
| building (claimed by Buildings) | band-classified template model (06) |
