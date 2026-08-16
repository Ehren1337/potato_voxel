# Log Review: potato_voxel diagnostics — 2026-08-16

Reviewed: /Users/shanemcgovern/dev/loghook/logs (920 files, ~33 MB, 549,767 lines)
Window: 07:15Z → 13:03Z (4 sessions; the bulk is one 77-minute Linux session)

## Executive summary

The diagnostic stream is **~98% redundant**: 549,767 lines total across all
files, but only **10,669 unique lines**. The client sends a full snapshot every
5 seconds (boot evidence + full ring + status), even when the game state is
unchanged — 920 POSTs per ~77 minutes of play, ~30 MB/day/client. Three real
defects sit behind the noise: a **1-second-per-frame crawl for ~55s on a
Raspberry Pi**, **storage invalid_key state with boot failures on iOS**, and
**main-thread mesh prebuilds that stall frames for up to 15 seconds**.

---

## Sessions found

| Session | Platform | Files | Notable |
|---|---|---|---|
| 20260816-081129 | iOS / Metal (M5 Pro) | 1 | worstFrame 935ms; errors=4; cache wipe → 444-job rebuild 98s; texMB to 380MB |
| 20260816-084534 | iOS / Metal (M5 Pro) | 1 | **8-second boot, 6 storage failures, state=invalid_key, jobs=0 — crashed at boot** |
| 20260816-010255 | Linux / Broadcom V3D (Pi) | 1 | **worstFrame 2183ms; 1fps for ~55s; prebuild 428.9s; errors=5; storage invalid_key + 2 failures** |
| 20260816-084615 | Linux / AMD Steam Machine | 917 | voxel=OFF whole session; draws=0 always; pipeline never available; worstFrame 690ms during prebuild; prebuild 299.6s |

---

## Bugs

### 1. Raspberry Pi: ~55 seconds at 1 FPS (session 010255) — worst defect
Timeline: voxel pipeline came online 01:11:25 ("pipeline voxel available",
"drawWorld: first scene render"). texMB spiked 8→85.8, then **dropped 85.8→25.4
at 01:11:47** (a 60MB eviction). From **01:11:52 → 01:12:47** every frame ran at
~1000ms:
```
01:11:52.043 frame avg 395.7ms max 1002.0ms ... updates=11011
01:11:57.049 frame avg 1001.1ms max 1002.0ms ... updates=11016
...
01:12:47.091 frame avg 28.6ms  max 1001.7ms ... updates=11236   <- recovers
```
Updates counter crawls (11011→11236 = 4/sec vs normal 60/sec), so the loop is
genuinely blocked ~1s per frame — not a reporting artifact. Pattern smells like
the GPU driver (Broadcom V3D / Mesa) stalling on texture re-upload or shader
compile after the first voxel scene render + memory eviction. User-visible:
game frozen for nearly a minute right after the world first renders.

### 2. Storage `invalid_key` state + failures (sessions 084534, 010255)
- iOS 084534 booted, wrote nothing, **6 storage failures**, state=invalid_key,
  jobs=0, prebuild 0/444, dead after 8 seconds (frame 492).
- Pi wrote 348 times while state=invalid_key with **2 failures** — writes
  "succeed" under an invalid key, which risks corrupting / misdirecting saves.

The cache identity differs between sessions (PVMC1|18|red|b|1523604175 vs
PVMC1|18|red|b|636494512 vs PVMC1|18|blue|b|1523604175) — worth checking the
storage-key derivation path against the save identity (docs/engine-storage-windows-enoent.md
is adjacent territory).

### 3. Main-thread prebuild stalls frames (all sessions)
The 444-job prebuild runs on the main thread. Mesh builds are serial and long:
- **Pi: `mesh done CELADON_CITY:body (15320ms)` — a single 15.3-second stall**
  (frames hit 1632.9ms max during it); VIRIDIAN_FOREST/full 6050ms.
- iOS: mesh done ROUTE_5:body 3917ms, SAFFRON_CITY:body 2828ms; hitches to 882ms.
- Steam Machine: hitches to 690ms (08:49:36, during prebuild) — the session's
  worstFrame.

Prebuild duration: M5 Pro 98.2s (4.5 jobs/s) · Steam Machine 299.6s (1.5 jobs/s)
· Pi 428.9s (1.0 jobs/s). On the Pi this is **7+ minutes of repeated stutter**.

### 4. SLOW cache loads block map entry (sessions 081129, 010255)
Cache "hits" that take 300–1219ms are flagged SLOW load:
Pi: VIRIDIAN_CITY 1219ms, ROUTE_21 497ms, CINNABAR_ISLAND 491ms, PALLET_TOWN 320ms, ROUTE_1 296ms
iOS: SAFFRON_CITY 616ms, PEWTER_CITY 372ms
These are synchronous zlib decompressions on the main thread during map
transitions — hitches right when the player changes map.

### 5. `errors` counter == `slowLoads` counter (naming/conflation)
counters: jobs=470 errors=4 ... slowLoads=4   (iOS)
counters: jobs=449 errors=5 ... slowLoads=5   (Pi)
There are **zero jobFails and zero exceptions** anywhere. The "errors" field is
literally the slow-load count. If "errors" is meant to be hard failures, it is
mislabeled; if slow loads are intentionally errors, that's fine but should be
documented so dashboards don't alarm on cache-warmup hitches.

### 6. Boot hitch on every session
First frame after boot: 126.9ms (iOS), 347.4ms (Steam Machine), **1625.4ms
(Pi)**. First-frame shader/texture warmup.

### 7. Settings churn invalidates cache (iOS 081129)
56 setting lines in ~10 seconds (renderScale 50%→33%→50%→33%→100%, water/aa/
curve/grid/battles toggles), then `cache wipe` + `cache invalidate ALL` →
full 444-job prebuild (98.2s). The settings menu emits 8 log lines per change
and each change nukes the cache — expensive and noisy.

---

## Optimizations

### A. Kill the ~98% log redundancy (highest ROI, client+server)
- 549,767 lines written, 10,669 unique. Per 5s send: ~700 lines transmitted,
  only **8 new lines (~430 bytes)**.
- The ring grows across the session (exported 166 lines → 624 lines) — the
  client re-sends the *entire session history* every 5 seconds, plus a static
  boot-evidence block (128 lines) in every file.
- Options (any one removes ~95% of the 30MB/day/client):
  1. **Client: delta sends** — send only lines since the last acked send,
     plus a compact status block. Ring stays local.
  2. **Server: append per session** — one file per session instead of one file
     per POST; `logToFile` writes a new file every request today
     (`fs.writeFileSync` per POST).
  3. At minimum: cap the ring and stop repeating boot evidence in every send.

### B. Adaptive send cadence
5s is too aggressive for an idle session — the Steam Machine session sat in
REDS_HOUSE_2F with voxel OFF for ~70 minutes and still pushed a snapshot every
5s (917 files, ~28MB of near-identical content). Back off when nothing changed
(e.g., no new events + no state delta → 30–60s, or send-on-change only).

### C. Server: stop blocking the event loop
`fs.writeFileSync` on every POST serializes requests. Use async append +
per-session handles. Also add retention (920 files/day/client today, no
rotation/compression) and optional gzip.

### D. Move prebuild off the main thread (or time-slice it)
The 444-job prebuild stutters every frame for 1.5–7 minutes. Thread the mesh
building or budget it per-frame (e.g., N ms of meshing per frame) so the game
stays interactive. The 15.3s single-mesh case (CELADON_CITY on Pi) should never
block the loop.

### E. Async cache decompression
SLOW loads up to 1219ms during map entry are synchronous zlib on the main
thread. Decompress on a worker thread or warm the next map's terrain ahead of
transition.

---

## Notes for the loghook server (server.js)
- `logToFile` uses `writeFileSync` per POST and stamps a new filename per
  request — combined with the 5s client cadence this is what produced 920 files
  in one morning. Appending to a per-session/per-client file would shrink the
  file count ~920x.
- The 5MB request cap is far above the engine's 64KB postLog cap — harmless but
  the sync write is the real bottleneck under concurrent clients.

## Suggested next steps
1. Confirm the Pi 1fps crawl repro (broadcom V3D + first voxel render + memory
   eviction). Highest user impact.
2. Trace the storage invalid_key path — two sessions hit it, one crashed at boot.
3. Ship delta-send + append-per-session on the loghook side; expect log volume
   to drop ~95%.
