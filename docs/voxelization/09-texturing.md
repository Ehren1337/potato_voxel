# 09 — Texturing: The Terrain Atlas and Palette Baking

Voxel terrain is textured from the **tileset atlas** (128x48 px), not a
rendered copy of the map. A map-space canvas covering the biggest routes
would be ~5 MB each with up to five live at once; the atlas costs 24 KB
and costs nothing in fidelity — TerrainAtlas hands back the same atlas
TileRenderer draws with, including RED++'s per-map bakes (ChunkMesher.lua:
27-33).

## The three colour paths (TerrainAtlas.lua:1-18)

| path | what the atlas is | what the mod does |
|---|---|---|
| RED++ | a fully recolored per-map atlas baked by the engine (`getGbcAtlas`), already true color | nothing — use as-is |
| trueColor mod | a mod's full-color atlas | nothing — use as-is |
| SGB modes | raw 4-shade grayscale; colour normally arrives as a screen-space shade-remap pass over rectangular zones — meaningless once the ground is geometry | **bake**: one atlas copy per (atlas, palette), remapped through the same cutoffs the shader uses (`TileRenderer.recolorSample`), cached by palette key (TerrainAtlas.lua:79-113) |

Sprite sheets get the same treatment under SGB palettes
(`TerrainAtlas.forSprite`, TerrainAtlas.lua:590-614) — the voxel canvas
composites 1:1 with no shade-remap pass, so without the bake a character
stands in raw DMG greys inside a coloured room.

## Animated tiles: animate the TEXTURE, not the mesh

The 2D path animates water/flowers by overdrawing the animated cells
each frame. A single static mesh has no equivalent — the geometry
samples one texture. So the mod **rewrites the animated tile's slot in a
private copy of the atlas** whenever the step advances; every instance of
that tile across the whole mesh moves at once. Which is what the Game
Boy does in the first place (home/vcopy.asm rewrites the tile's VRAM
bytes); the 2D overdraw is the port's workaround, not the original
(TerrainAtlas.lua:20-28).

- **The clock is the ENGINE's** 60 Hz counter (`TileRenderer.animFrame`,
  or the `tick` upvalue, or wall time) — toggling voxel mode mid-cycle
  continues the animation instead of restarting it (TerrainAtlas.lua:
  394-441).
- **Private copy always**: the base may be the engine's own atlas, and
  rewriting it would double-animate the flat path (TerrainAtlas.lua:
  463-471).
- **hshift** (the water rotate): the tile's own pixels rolled sideways,
  read from the UNANIMATED base so steps never compound
  (TerrainAtlas.lua:158-168).
- **frames** (flowers): each frame file is raw grayscale — the mod
  *learns* what the atlas did to the tile (`learnShades`: read the tile's
  slot in raw art and finished atlas side by side) so the frame lands on
  the same colours, whatever recolour path ran (TerrainAtlas.lua:127-150).
- **Cut masks** (the flower billboard): only the frame's darkest tones
  plus their enclosure stay opaque; the true background is keyed to
  alpha, which the voxel shader discards — the standing silhouette trims
  itself frame by frame in texture space, the sway animating without a
  vertex moving (TerrainAtlas.lua:184-217, 495-508).
- Redundant uploads are avoided by folding every spec's step into one
  number; repatch only when it changes (~3×/s, ~130 px of work)
  (TerrainAtlas.lua:540-570).
- Failure handling: attempts budget of 3, then give up for the session
  (a driver refusing one readback must not kill water forever)
  (TerrainAtlas.lua:51-60).

## Pixel access

- Our own bake → we have the pixels.
- Engine atlas: `TileRenderer.atlasImageData` where the build offers it,
  else the tileset art on disk, else (RED++ only, which throws its
  ImageData away) a canvas **readback** — guarded, and preferred over by
  `gbcPixels`, a deterministic CPU re-bake of the engine's GBC atlas
  from public inputs (TerrainAtlas.lua:298-392).

## Eviction

RED++'s per-map atlases are held per map and evicted with the mesh
neighbourhood (`setLive`, same live set ChunkMesher uses); the shared
SGB bakes key on (tileset, palette) and are bounded for a session
(TerrainAtlas.lua:616-632).
