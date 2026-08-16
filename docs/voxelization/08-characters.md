# 08 — Characters: Sprites Are NOT Voxelized (Deliberately)

Every character — the player, NPCs, ghosts on neighbour maps — is its
**current 2D sprite frame on a single flat quad** (SpriteBillboards.lua).
The sheets carry real alpha and the voxel shader discards it, so the
quad cuts the sprite's exact silhouette out of itself (Voxel3D.lua:
263-267). No geometry is built from the pixels; nothing about a sprite
is voxelized.

## Why

A sprite is a DRAWING, not an object seen from one side: Gen 1's
overworld figures are 16x16 icons with a fixed front-on reading, and
turning one into a solid reconstructs a body the artist never drew and
the game never implied (SpriteBillboards.lua:9-15). The mod also refused
to ship a description of the ROM art. One quad wearing the real frame is
more faithful AND cheaper: it needs no pixel access at all.

## The card

- One mesh per (sprite def, frame index), cached: a 16x16 quad
  UV-mapped to the whole frame with a hair of inset
  (SpriteBillboards.lua:35-71).
- The card **always faces SOUTH** (the direction the 2D game implies)
  and only **leans back**, pivoting at its feet, by exactly the camera's
  pitch — so at every tilt level the sprite reads face-on like the flat
  game (billboardMatrix, VoxelScene.lua:298-314).
- Right-facing and the alternating walk step are **matrix mirrors**, not
  extra meshes.
- UVs point into the live sheet image, so RED++ OBP bakes, SGB palette
  bakes (TerrainAtlas.forSprite) and sprite-replacing mods all texture
  it with no rebuild.
- The same frame tables as the flat renderer (`SR.WALK`/`SR.STAND`), so
  the 3D pass and the 2D path agree on which frame is showing
  (VoxelScene.lua:215-225).

## Camera-ward pull

The leaned-back slab would lose the depth test against the wall it
leans OVER. Every vertex of a character draw is moved toward the eye
along its OWN ray by `pull` (6–22 px depending on pitch) — a pure depth
bias with zero screen drift, applied in the vertex shader
(Voxel3D.lua:137-151, VoxelScene.lua:204-210). A character genuinely
behind a building is dozens of pixels deeper and still loses, so real
occlusion works.

## The player's occlusion silhouette (the ghost)

Honest occlusion means the player can walk behind the Mart and lose
their own character — which the flat game never allowed. So the player's
card is drawn a SECOND time with the depth test INVERTED ("greater"
passes exactly where "lequal" failed): solid where visible, translucent
flat grey where not, with no seam and no double-blending (Voxel3D.lua:
1154-1188). Drawn BEFORE the characters (so it only meets the world in
the depth buffer), depth-write-free. One flat colour, not a dimmed copy:
a silhouette reads as a shape, not a hole in the building.

## The sun sees a different pose

The leaning slab is a trick played on the VIEWER. The sun pass draws the
same card **upright and flattened** (`casterMatrix`, Voxel3D.lua:1428-
1449), so shadows stay full-length at every camera pitch — and the main
pass looks up its own shadowing with that same upright transform
(`sunModel`, ShadowMap.snug), so a figure never fringes itself.

## First person

In 1ST/3RD the card stops leaning and starts TURNING — upright, yawed
about its feet to face the eye (cylindrical billboarding). The blend
eases the lean out as the yaw eases in; the pose's facing is remapped
so the card wears the frame the pose SHOWS that eye (the back of a head
you walk behind) (VoxelScene.lua:241-249, 298-314).

## Battle cards

Battle mons on the overworld use the same single-quad technique
(BattleBillboard), plus stadium-disc arenas for staged fights; the
battle pass is covered in 11.

## Key numbers

| constant | value | where |
|---|---|---|
| card size | 16x16 px, feet at y=0, centred on the cell | SpriteBillboards.lua:38-53 |
| ghost colour / alpha | (0.26, 0.26, 0.28) / 0.5 | Voxel3D.lua:1151-1152 |
| pull | `6 + (16·cos a − 8)⁺ / max(sin a, 0.2)` | VoxelScene.lua:208-210 |
| shadow caster | upright card at cell middle, z-flattened | Voxel3D.lua:1428-1449 |
