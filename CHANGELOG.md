# Changelog

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

[1.3.3]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.3
[1.3.2]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.2
[1.3.1]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.1
[1.3.0]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.3.0
[1.2.4]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.2.4
[1.2.3]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.2.3
