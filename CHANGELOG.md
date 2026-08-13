# Changelog

## [1.4.7] - 2026-08-13

### Fixed

- The mesh cache folder is now created correctly on a fresh install. The
  shell-free directory creation only made the cache's own subfolders, so
  when the save directory itself was brand new the cache was disabled for
  the whole session (it read as "UNAVAILABLE" until a restart). It now
  creates every missing level, from the root down, before writing.

## [1.4.6] - 2026-08-13

### Performance

- Terrain and water meshes are now stored quantized: 11 bytes a vertex
  (16-bit position, 16-bit texture coordinates, 8-bit shade) instead of the
  24-byte six-float stream -- about 54% smaller before compression. Cache
  files shrink and a cold map load reads and decompresses far less from
  storage. Positions are integer pixels and come back exactly; texture
  coordinates and shade round to 1/65535 and 1/255, both far finer than the
  voxel grid or the baked ambient-occlusion steps can show. The mesh that
  reaches the GPU is unchanged, so there is no visual difference and no
  steady-state draw cost.

### Changed

- The mesh cache no longer uses shell commands to set itself up. The cache
  folder is created through LÖVE's filesystem where it can reach it, and
  through a direct library call on portable (SD-card) installs, with a real
  write test before use -- so the cache works where shell access is
  restricted or unavailable. WIPE CACHE lists files through the filesystem
  API instead of a shell listing.

- **CACHE STATUS** now names the compression method: **READY (LZ4)**,
  **READY (ZSTD)**, **READY (RAW)**, or **READY (MIXED)**. The cache tries
  zstd first when the runtime provides it, and reports whichever codec it
  actually used.

### Added

- The cache format now records its compression codec per file, so a cache
  written by one build stays readable by another and the status can name the
  real method. Updating to 1.4.6 refreshes the cache once (the geometry
  version moved to 18), in the background or on demand.

## [1.4.5] - 2026-08-13

### Fixed

- Stadium models no longer play a hurt/faint-looking animation when sent
  out. Two causes, both in the send-out entrance. The anchor that pins a
  Pokemon to its tile over-corrected when an entrance hopped: the lagged
  offset outlived the hop and dragged the body below the tile on the way
  back down, which is a collapse no matter what the animation said. It is
  clamped to the excursion that caused it, so a returned hop is not
  dragged past the tile it came back to. And species whose entrance is a
  genuine drop to well under standing height (Squirtle into its shell,
  Goldeen flat on the ground -- 48 of the 151) no longer play it at all:
  the entrance is measured once at load, through the anchor the player
  actually sees, and a species that reads as hurt on arrival now arrives
  on its standby loop instead. The standbys and the entrances that still
  read as entrances are untouched.

## [1.4.4] - 2026-08-12

### Fixed

- Mediatek/Mali devices: every voxel rung now uses the HIGH shadow path
  (the sprite-layer map) instead of the flat contact-blob fallback. The
  fallback path is what froze the screen on the last frame (the game kept
  running behind it) and dropped the player's shadow on MEDIUM/LOW/POTATO/
  CUSTOM -- the exact rungs that break are the ones HIGH's configuration
  never touches, and users confirmed HIGH works. The decal pass is also
  now crash-proofed so a failing decal can no longer freeze a frame on any
  device.

## [1.4.3] - 2026-08-12

### Fixed

- Black screen with shadows enabled on Mediatek/Mali Android devices. Two
  failure paths are closed: a shadow pass that dies mid-draw can no longer
  leave its offscreen canvas bound (the world was rendering into the shadow
  map, which is the black frame), and NaN values from a degenerate light
  fit can no longer poison the shadow math (NaN comparisons silently pass
  GLSL bounds checks, then black out every fragment they touch). Both now
  fall back to a flat-lit frame for that moment instead of a black screen.

## [1.4.2] - 2026-08-12

### Fixed

- The map cache no longer asks to rebuild on every launch. The game was
  checking the cache with default settings before your save loaded, so a
  save that used a different VOID FILL looked "stale" every time -- even
  when the cache matched your settings perfectly. The check now runs after
  your save (and its options) are loaded, and the BUILD NOW? prompt appears
  over the world instead of the title screen.
- Interrupted builds now resume. If a build is cut short (the app was
  backgrounded, the battery died, a crash), the next launch continues from
  where it stopped instead of starting over or prompting forever.
- The map cache now refreshes itself once when you update to 1.4.2 (the
  cache now remembers more detail about your game data, so old files are
  rebuilt a single time, in the background or on demand).
- Windows: updating the cache info file no longer fails silently, which
  could leave the game asking for a rebuild every launch.
- When a build fails, the game now tells you WHY (a full SD card, a
  read-only folder) instead of a generic "verification failed".
- The cache folder is created more reliably: the game tries the normal
  save-system folder first, then falls back to system commands, and
  double-checks the folder can actually be written to before using it.
  **CACHE STATUS** now shows which method was used (LOVE FS / MKDIR / NONE).
- If the cache folder can't be set up, the game now retries instead of
  quietly disabling the cache for the whole session.
- Boot logging: when the cache is rejected, the game log now explains
  exactly why, which makes "it rebuilds every time" reports much easier to
  diagnose.

## [1.4.1] - 2026-08-12

### Fixed

- The map-cache build now starts on Windows: the cache folder is created with
  Windows-native commands (`if not exist ... mkdir ...` for each level instead
  of the POSIX-only `mkdir -p`, which cmd.exe rejected by treating `-p` as a
  folder name and choking on the `/dev/null` redirect). The build used to fail
  the instant it began after a cache wipe, on every Windows release back to
  1.3.3.

## [1.4.0] - 2026-08-12

### Added

- One build for every device: the DS_BRICK environment switch is gone, so the
  tuned diorama runs identically on everything -- no more desktop/potato
  split.
- The VOXEL ladder is now a set of quality MODES (OFF / HIGH / MEDIUM / LOW /
  POTATO / CUSTOM). Picking a mode applies its tuned preset to every quality
  knob -- WATER, FOREST FX, AA, V-CURVE, V-GRID, 3D-BTL, SHADOWS, SHADOW
  QUALITY and RENDER SCALE -- and changing any knob on its own flips the mode
  to CUSTOM until a named mode is picked again.
- Added a RENDER SCALE row (100% / 75% / 50% / 33%), the single biggest
  frame-budget lever: the modes set it, and moving it on its own also flips
  the mode to CUSTOM.
- The quality knobs (WATER, FOREST FX, AA, V-CURVE, V-GRID, BACK SPRITES) are
  no longer pinned off on every device: each is a switchable row on the VOXEL
  SETTINGS submenu.
- Added a STADIUM SPRITES row (OFF / ON): staged fights use the Pokemon
  Stadium battle models -- skinned and animated -- instead of the flat battle
  pics. It shows while 3D-BTL is on and needs the models built from the
  player's own Pokemon Stadium (US) 1.0 ROM.
- Stadium packs are now compressed with LZ4 -- the same codec as the terrain
  mesh cache -- so the set is roughly 40% smaller on disk and reads back
  faster. Old raw packs and new compressed ones load through the same path.

### Changed

- Stadium models and their discs are lit by a real sun-directional diffuse
  term (an ambient floor plus a diffuse against the actual sun direction)
  instead of a flat axis-aligned guess, so a Pokemon reads as properly
  shaded in the same light the shadow map throws.
- V-GRID now follows the player's setting inside 3D battles (it used to be
  forced on).
- The anti-aliasing fold gains a light crispness (unsharp) term, so
  supersampling no longer washes out the tileset (AntiAlias.SHARP, tunable).

### Fixed

- Stadium models no longer read their own stale shadow: they are cast-only,
  like the flat battle cards, so the glitchy moire that crawled over their
  bodies is gone.

## [1.3.10] - 2026-08-11

### Added

- Added a SHADOWS row (ON / OFF). OFF is the flat-lit diorama: no shadow map
  is drawn, the main pass is sent sunDark=0, and the contact blobs under the
  characters go with it -- in free-roam and staged battles alike, so a device
  that cannot carry the shadow pass can turn it off wholesale rather than
  only dropping the expensive animated-actor layer.
- Added a SHADOW QUALITY row (AUTO / 512 / 1024 / 2048). AUTO is the adaptive
  ladder the pass always ran (the smallest size whose texel stays under a
  target slice of a world pixel, capped at 2048); a fixed rung forces the
  square shadow map's edge in texels whatever the view, so a player can trade
  fill rate and RAM (a 2048 edge is a 16 MB depth pass, re-rasterised
  whenever the shadow signature moves) for finer shadow edges.
- Both rows are visible in every profile: they appear on the VOXEL SETTINGS
  submenu and the mod manager's page whether the device runs the Brick
  profile (which pins every other knob) or the full desktop mod, and stay on
  the menu under the FULL preset.

### Fixed

- The shadow map canvas is now allocated at the fitted resolution rung
  instead of staying pinned to the ladder's smallest size. The 1536 and 2048
  rungs used to render into a 1024 (or 512 on the Brick) map whose fit, depth
  bias and filter were computed for the finer rung; a fixed SHADOW QUALITY
  rung now produces a map of exactly that size, and the Brick HIGH rung's
  documented 1536 edge is real.

## [1.3.9] - 2026-08-11

### Fixed

- The enemy HUD panel is hidden while a wild battle's intro plays its ball
  animation, instead of showing an empty status box over the arena.

### Contributors

- **AverageConsumer** — the wild-intro HUD fix.

## [1.3.7] - 2026-08-11

### Added

- Added a `github` field to the manifest (`ShaneMcGovernIE/potato_voxel`) so the
  launcher enables the Check for updates / Versions / Update flow for
  PotatoVoxel.

### Fixed

- Removed the per-byte Lua checksum pass that ran over every decompressed
  cache payload on load, eliminating a slight hitch when moving between maps
  with the compressed mesh cache enabled. Truncation is still caught by the
  packed-length and raw-length checks.

## [1.3.6] - 2026-08-11

### Added

- Added an opaque Town Map loading cover for cold asynchronous voxel builds. On
  a cold cache the cover stays up until the current map's first terrain mesh is
  ready, so the vanilla 2D world never flashes before the diorama appears. The
  mesh queue keeps pumping behind it, and invisible overworld updates pause
  until the build finishes, failing open if a build ends without terrain or
  voxel mode is turned off. Loading state is exposed through
  `mod.potato_voxel.loading_changed` and `mod.exports.isLoading`.

### Fixed

- Staged battles now honour the engine's `bottomUIVisible()` and
  `statusHUDVisible()` seams before drawing PotatoVoxel's battle backings, so a
  mod hiding the battle UI no longer leaves frosted panels behind.
- The staged-battle front-sprite wrapper now runs before downstream
  `pokemon.sprite` wrappers, asks them for the FRONT variant with a copied
  side context, and propagates `trueColor` back to the caller, so compatible
  sprite-replacing mods apply inside staged battles instead of being bypassed.

### Contributors

- **AverageConsumer** — interoperability with battle UI and sprite mods, and
  the cold mesh-build loading cover.

## [1.3.5] - 2026-08-11

### Fixed

- Fixed long launcher stalls when booting with a complete compressed mesh cache.
- Boot-time cache readiness now validates bounded file headers, fingerprints,
  codecs, packed lengths, and file sizes without reading or decompressing every
  terrain, water, and auxiliary payload.
- Rebuilding a missing cache manifest now uses the same bounded header scan
  instead of decoding the full cache before the title screen.

### Performance

- Full LZ4 decompression, checksum validation, and mesh decoding remain
  deferred until a map actually loads its mesh or an explicit cache
  verification runs, reducing startup I/O and peak memory use.

## [1.3.4] - 2026-08-10

### Added

- Added optional LZ4 compression for large terrain, water, and auxiliary mesh-cache payloads when the runtime supports it and the compressed result is smaller.
- Compressed entries store their codec, raw and packed lengths, and a checksum so damaged or truncated cache files are rejected safely.
- Existing raw cache files remain readable and are repacked lazily when loaded; **PREBUILD CACHE** migrates the complete cache in one pass.
- Added compression-aware cache status labels: **READY CMP**, **READY MIX**, and **READY RAW**, with the detailed **CACHE STATUS** view showing the same state.

### Performance

- Reduces on-disk cache size and the amount of data read from storage during cache loads, especially for large terrain meshes.
- Keeps raw fallback for unsupported runtimes, tiny payloads, or cases where LZ4 would not reduce the size.
- Does not change mesh vertices, UVs, rendering quality, GPU memory use, or steady-state draw cost.

## [1.3.3] - 2026-08-10

### Added

- Added optional optimized 3D battles to the Brick profile, following the VOXEL render-quality scale.
- Reused the existing cached map terrain for staged battle scenes.

### Fixed

- Split battle terrain and Pokemon cards into separate shadow layers to prevent camera-dependent triangle artifacts.
- Battle cards no longer receive their own sun-shadow depth test while continuing to cast shadows onto the arena.
- Lower Brick battle tiers use contact shadows instead of the actor shadow map.

## [1.3.2] - 2026-08-10

### Added

- Added boot-time mesh-cache readiness detection with automatic migration for complete current caches.
- Added **CACHE STATUS** and confirmed **WIPE CACHE** actions under VOXEL SETTINGS.
- Added a cancellable cache-prebuild prompt before CONTINUE and NEW GAME when the cache is incomplete.

### Fixed

- Prebuilds now validate durable terrain, water, and auxiliary files before reporting READY.
- Cache identities now include the active ROM/data revision, preventing stale geometry from being reused across versions.
- Cache completion is finalized immediately after the last job instead of waiting for another frame.

## [1.3.1] - 2026-08-10

### Changed

- Added conflict detection for `BATTLE_ART_VOXEL_FORK` and `DRAMALESS_SHAPE`, showing a clearer warning that two voxel mods should not be installed at the same time.

## [1.3.0] - 2026-08-10

### Performance

- Reduced Building voxel placement cost with anchor-tile candidate indexing while preserving row-major matching and first-claim behavior.
- Reduced Building voxel model-generation cost with cached atlas shade sampling, lower index arithmetic overhead, and dense voxel storage.
- Preserved building geometry, shading, UVs, shadows, seams, and BuildBudget coroutine behavior.

### Fixed

- SELECT no longer changes the Voxel graphics quality ladder; quality remains controlled by the Voxel option and its supported hotkeys.

## [1.2.4] - 2026-08-10

### Fixed

- Fixed performance regressions in POTATO Mode.
- Removed the DEBUG option from the in-game OPTIONS menu; diagnostics remain available only through benchmark instrumentation.

## [1.2.3] - 2026-08-09

### Fixed

- Fixed stretched, screen-spanning overworld NPC shadows on Android by guarding zero-length camera-ray normalization in the mobile shader.
- Kept NPC contact shadows grounded and stable with camera-ward depth bias and pixel-quantized placement.
- Replaced animated NPC shadow silhouettes with fixed contact-shadow blobs so animation frames, mirroring, and jump lift cannot stretch or shimmer shadows.
- Removed the DEBUG option from the in-game options menu.

[1.3.7]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.7
[1.3.6]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.6
[1.3.5]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.5
[1.3.4]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.4
[1.3.3]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.3
[1.3.2]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.2
[1.3.1]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.1
[1.3.0]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.0
[1.2.4]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.2.4
[1.2.3]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.2.3
