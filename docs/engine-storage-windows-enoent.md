# Engine storage: Windows aux-save ENOENT (finding, pending repro)

**Status:** finding documented; engine PR deferred until the trigger is reproduced (plan Phase 3).

## Evidence (friend's Windows log, log-3.bin)

- 180 staging failures, all `aux` payloads:
  `storage writeBytes: write_failed (Could not stage opaque storage data: .../mod_storage/red/<id>/potato_voxel/maps/<MAP>/<slot>/aux.bin.tmp: No such file or directory)`
  and the table fallback `aux.lua.tmp` identically.
- Terrain and water saves into the *same* `maps/<MAP>/<slot>/` directories succeed (89 `saved terrain` lines, zero terrain/water failures).
- Install path: `C:\Games\PC Ports & Recompilations\Gen1Recomp\` (space + `&`).
- Consequence: grass/flowers/figures never cache on that machine (re-voxelized each load) and the prebuild churns; the game remains playable.

## Engine code path

- `src/mods/Storage.lua`: `write` (table) and `writeBytes` both call `ensureParent(fs, main)`.
- `ensureParent` (line 36): splits on `/` only, calls `fs.createDirectory(dir)` once (single level), **ignores the result**.
- `fs` = `SaveData.persistenceFs(...)` facade; paths are relative (`mod_storage/red/<id>/potato_voxel/...`) and rendered absolute in errors.
- Why `aux` fails while `terrain` succeeds in the same directory is not yet explained by code reading (both go through the same staging) - needs the repro.

## Repro instructions (friend / maintainer, Windows)

1. Launch the game with PotatoVoxel 1.6.4, load a save.
2. OPTIONS > VOXEL SETTINGS > PREBUILD CACHE; let it run ~30s.
3. Press F8 / SEND LOGS and send the log (or read `mods/.../debug/log.bin`).
   Expected failure lines: `cache save failed: aux` + `write_failed ... aux.bin.tmp ... No such file or directory`.
4. Repeat after moving the game to a path with no `&` and no spaces (e.g. `C:\Gen1Recomp\`).
   - If aux saves then succeed: the special-character path is the trigger (shell/quoted-path handling in the persistence facade).
   - If they still fail: the trigger is the directory-depth/creation chain itself.

## Candidate engine fix (once reproduced)

- Make `ensureParent` create the full parent chain (walk segments, `createDirectory` each level, stop at the first existing) and propagate failure.
- Verify the persistence facade's `createDirectory` accepts Windows mixed-separator paths (or normalize separators before use).
