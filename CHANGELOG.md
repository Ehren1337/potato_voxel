# Changelog

## [1.2.3] - 2026-08-09

### Fixed

- Fixed stretched, screen-spanning overworld NPC shadows on Android by guarding zero-length camera-ray normalization in the mobile shader.
- Kept NPC contact shadows grounded and stable with camera-ward depth bias and pixel-quantized placement.
- Replaced animated NPC shadow silhouettes with fixed contact-shadow blobs so animation frames, mirroring, and jump lift cannot stretch or shimmer shadows.
- Removed the DEBUG option from the in-game options menu.

[1.2.3]: https://github.com/ShaneMcGovernIE/potato_voxel/releases/tag/v1.2.3
