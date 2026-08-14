package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = require("src.core.Data")
Data:load()

local run = T.sdk.loadMod("mods/potato_voxel", { data = Data })
T.eq(#run.errors, 0, "loads clean")

local exports = run.loader.exports.potato_voxel
local Prebuild = exports.lib.require("CachePrebuild")
local MeshCache = exports.lib.require("MeshCache")
local Perf = exports.lib.require("Perf")
local Brick = exports.brick
local Battles = exports.lib.require("OverworldBattle")
local QualityMode = exports.lib.require("QualityMode")

T.eq(Battles.setDebug(true), false,
     "battle diagnostics can be enabled through the module API")
T.check(Battles.debugEnabled(),
        "battle diagnostics report their explicit sandbox-safe state")
T.eq(Battles.setDebug(false), true,
     "battle diagnostics can be disabled through the module API")

if Brick and Brick.isBrick() then
  T.eq(Brick.battleRenderScale(), 1.0,
       "battle scene follows the RENDER SCALE knob (default 100%)")
  QualityMode.renderSetting:setValue(50)
  T.eq(Brick.battleRenderScale(), 0.5,
       "battle scene follows a changed RENDER SCALE")
  QualityMode.renderSetting:setValue(100)
  T.eq(Brick.battleActorShadowMap(1), true,
       "HIGH keeps battle actor shadow map")
  T.eq(Brick.battleActorShadowMap(4), false,
       "POTATO uses cheap battle contact shadows")
  T.eq(Battles.setting.values[1], false, "3D-BTL is off by default")
  T.eq(Battles.setting.values[2], true, "3D-BTL remains available")
end

local maps = {
  B = { id = "B", width = 3, height = 2, borderBlock = 0,
        blocks = { 1, 2, 3, 4, 5, 6 }, connections = {} },
  A = { id = "A", width = 4, height = 5, borderBlock = 0,
        blocks = { 1, 2, 3, 4, 5, 6 }, connections = {
          east = { map = "B", offset = 0 },
        } },
}

local jobs = Prebuild.enumerate(maps)
T.eq(#jobs, 4, "prebuild enumerates body and full variants")
T.eq(jobs[1].id, "A", "prebuild sorts map ids")
T.eq(jobs[1].slot, "body", "body runs before full")
T.eq(jobs[2].slot, "full", "full follows body")
T.eq(Prebuild.activationDecision("PREBUILD", false), "start",
     "incomplete cache starts a build")
T.eq(Prebuild.activationDecision("READY", false), "confirm_rebuild",
     "ready cache confirms rebuild")
T.eq(Prebuild.activationDecision("BUILD 1/4", true), "cancel",
     "running cache build cancels")
T.eq(Prebuild.failureReason("complete", false, "aux: encode_failed"),
     "aux: encode_failed",
     "verification failure does not report the completed job status")

MeshCache.configure({ maps = maps, tilesets = {} })
local firstIdentity = MeshCache.identity()
maps.A.blocks[1] = 99
MeshCache.configure({ maps = maps, tilesets = {} })
T.check(firstIdentity ~= MeshCache.identity(),
        "map data changes the cache identity")

-- Sandbox storage is the persistent replacement for the old host-file cache.
-- Keep this fixture data-only so it exercises the same contract the engine
-- enforces, without depending on the test runner's filesystem.
local storageFiles = {}
local storage = {
  context = function(_, game)
    return game and game.save and {
      gameVersion = game.save.version,
      playthroughId = game.save.meta.playthroughId,
    }
  end,
  write = function(_, _, key, value)
    storageFiles[key] = value
    return true
  end,
  read = function(_, _, key)
    return storageFiles[key]
  end,
  list = function(_, _, prefix)
    local keys = {}
    for key in pairs(storageFiles) do
      if key:sub(1, #prefix) == prefix then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
  end,
  delete = function(_, _, key)
    storageFiles[key] = nil
    return true
  end,
}
local storageGame = {
  save = { version = "red", meta = { playthroughId = "cache-test" } },
}
local ScopedMeshStorage = exports.lib.require("ScopedMeshStorage")

-- Title options run against a fresh save skeleton, but their cache belongs to
-- the engine-selected existing playthrough. Using the ordinary storage
-- methods here would allocate a throwaway identity; CONTINUE would then bind
-- the real identity and immediately lose the cache that just completed.
local selectedPlaythrough = "selected-cache-test"
local titleScopes = {}
local directTitleContexts = 0
local function titleScope(id)
  titleScopes[id] = titleScopes[id] or {}
  return titleScopes[id]
end
local function titleStorageMethods(id)
  return {
    context = function()
      return { gameVersion = "red", playthroughId = id }
    end,
    write = function(_, key, value)
      titleScope(id)[key] = value
      return true
    end,
    read = function(_, key) return titleScope(id)[key] end,
    list = function(_, prefix)
      local keys = {}
      for key in pairs(titleScope(id)) do
        if key:sub(1, #prefix) == prefix then keys[#keys + 1] = key end
      end
      table.sort(keys)
      return keys
    end,
    delete = function(_, key)
      titleScope(id)[key] = nil
      return true
    end,
  }
end
local titleAwareStorage = {
  selected = function()
    return titleStorageMethods(selectedPlaythrough)
  end,
  context = function(_, game)
    directTitleContexts = directTitleContexts + 1
    local meta = game.save.meta
    meta.playthroughId = meta.playthroughId or "throwaway-title-cache"
    return { gameVersion = game.save.version,
             playthroughId = meta.playthroughId }
  end,
  write = function(_, game, key, value)
    titleScope(game.save.meta.playthroughId)[key] = value
    return true
  end,
  read = function(_, game, key)
    return titleScope(game.save.meta.playthroughId)[key]
  end,
  list = function(_, game, prefix)
    local keys = {}
    for key in pairs(titleScope(game.save.meta.playthroughId)) do
      if key:sub(1, #prefix) == prefix then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
  end,
  delete = function(_, game, key)
    titleScope(game.save.meta.playthroughId)[key] = nil
    return true
  end,
}
local preTitleGame = {
  save = { version = "red", meta = {} },
  -- game.ready can already have a launcher/bootstrap state.  A non-empty
  -- stack is not proof that a real playthrough has been restored.
  stack = { states = { { screenId = "BootState" } } },
}
titleAwareStorage.selected = function()
  return nil, "not_at_title", "Title state has not been pushed yet."
end
ScopedMeshStorage.configure(titleAwareStorage, preTitleGame)
T.check(not ScopedMeshStorage.available(),
        "pre-title boot leaves cache unavailable until playthrough selection")
T.eq(preTitleGame.save.meta.playthroughId, nil,
     "pre-title cache probe does not replace selected playthrough routing")
T.eq(directTitleContexts, 0,
     "pre-title cache probe never allocates ordinary storage")

-- Sandbox aux meshes must use the same dense row layout that newMesh and
-- encodeIndexed consume.  Sparse float-style row keys collide at vertex 7:
-- src[7] is both dense row 7 and sparse row 2, producing stretched triangles.
do
  local quads = {
    { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 },
      u = 0, v = 0, shade = 1 },
    { { 100, 0, 0 }, { 101, 0, 0 }, { 101, 1, 0 }, { 100, 1, 0 },
      u = 0, v = 0, shade = 1 },
  }
  local vertices, indices = {}, {}
  local floats, count = MeshCache.flattenQuads(quads, vertices, indices)
  T.eq(#vertices, 8, "flattened aux vertices are dense Lua rows")
  local decoded = MeshCache.decodeIndexed(
    MeshCache.encodeIndexed(floats / 6, vertices, count, indices))
  T.eq(decoded.vertices[7][1], 101,
       "aux vertex 7 survives cache encoding without colliding with row 2")
end

T.eq(MeshCache.GEOMETRY_VERSION, 19,
     "cache version rejects sparse-aux geometry from version 18")

titleAwareStorage.selected = function()
  return titleStorageMethods(selectedPlaythrough)
end
local titleGame = {
  save = { version = "red", meta = {} },
  stack = { states = { { screenId = "TitleState" } } },
}
ScopedMeshStorage.configure(titleAwareStorage, titleGame)
T.check(ScopedMeshStorage.available(),
        "title cache binds the selected playthrough storage facade")
T.eq(titleGame.save.meta.playthroughId, nil,
     "title cache does not allocate a throwaway playthrough identity")
T.eq(directTitleContexts, 0,
     "title cache never probes ordinary active-playthrough storage")
T.check(ScopedMeshStorage.writeMeta("manifest", { scope = "selected" }),
        "title cache writes through the selected playthrough binding")

-- Legacy saves receive their durable id on first storage use. That backfill
-- is safe only after the overworld has actually been restored, not merely
-- because some launcher state exists on the stack.
titleAwareStorage.selected = function()
  return nil, "not_at_title", "Selected storage is title-only."
end
local legacyGameplay = {
  save = { version = "red", meta = {} },
  overworld = { map = { id = "ROUTE_4" } },
  stack = { states = { {} } },
}
ScopedMeshStorage.configure(titleAwareStorage, legacyGameplay)
T.check(ScopedMeshStorage.available(),
        "restored legacy gameplay can backfill ordinary storage identity")
T.eq(legacyGameplay.save.meta.playthroughId, "throwaway-title-cache",
     "restored gameplay, not launcher boot, performs legacy identity backfill")
local continuedGame = {
  save = { version = "red", meta = { playthroughId = selectedPlaythrough } },
}
-- Active gameplay reports not_at_title and uses the ordinary facade. Model
-- that transition after the title write and prove both views share one scope.
titleAwareStorage.selected = function()
  return nil, "not_at_title", "Selected storage is title-only."
end
ScopedMeshStorage.configure(titleAwareStorage, continuedGame)
local continuedManifest = ScopedMeshStorage.readMeta("manifest")
T.check(continuedManifest and continuedManifest.scope == "selected",
        "CONTINUE sees cache completed from title options")

local strictRecords = {}
local strictWriteCount = 0
local strictReadCount = 0
local strictFailOnWrite = nil
local function safeStorageKey(key)
  if type(key) ~= "string" or key == "" or key:sub(1, 1) == "/"
     or key:sub(-1) == "/" or key:find("//", 1, true) then
    return false
  end
  for segment in key:gmatch("[^/]+") do
    if not segment:match("^[%w_%-]+$") then return false end
  end
  return true
end
local strictStorage = {
  context = function(_, game)
    return game and game.save and {
      gameVersion = game.save.version,
      playthroughId = game.save.meta.playthroughId,
    }
  end,
  write = function(_, _, key, value)
    T.check(safeStorageKey(key),
            "storage key uses safe segments")
    T.check(type(value) == "table", "storage value is a data-only record")
    strictWriteCount = strictWriteCount + 1
    if strictFailOnWrite and strictWriteCount >= strictFailOnWrite then
      return false
    end
    strictRecords[key] = value
    return true
  end,
  read = function(_, _, key)
    strictReadCount = strictReadCount + 1
    return strictRecords[key]
  end,
  list = function(_, _, prefix)
    local keys = {}
    for key in pairs(strictRecords) do
      if key:sub(1, #prefix) == prefix then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
  end,
  delete = function(_, _, key)
    strictRecords[key] = nil
    return true
  end,
}
ScopedMeshStorage.configure(strictStorage, storageGame)
T.check(ScopedMeshStorage.available(),
        "scoped storage adapter reports a valid context")
T.eq(ScopedMeshStorage.lastError(), nil,
     "scoped storage adapter starts without an error")

local storageKey = { mapId = "A/B", slot = "body", kind = "terrain" }
local storagePayload = string.rep("mesh", ScopedMeshStorage.CHUNK_SIZE + 37)
strictRecords, strictWriteCount, strictFailOnWrite = {}, 0, nil
T.check(ScopedMeshStorage.write(storageKey, "fp-1", storagePayload),
        "large payload writes as a committed v2 record")
T.eq(ScopedMeshStorage.read(storageKey, "fp-1"), storagePayload,
     "committed chunks reassemble byte-for-byte")
T.check(ScopedMeshStorage.read(storageKey, "wrong-fingerprint") == nil,
        "fingerprint mismatch is a miss")
local v2Keys = {}
for key in pairs(strictRecords) do
  v2Keys[#v2Keys + 1] = key
  T.check(key:sub(1, 10) == "meshes/v2/",
          "chunked cache uses the v2 storage namespace")
  T.check(not key:find("A/B", 1, true),
          "chunked cache encodes map ids into safe keys")
end
T.check(#v2Keys > 1, "large payload uses multiple storage records")

local replacement = string.rep("replacement", ScopedMeshStorage.CHUNK_SIZE + 37)
strictFailOnWrite = strictWriteCount + 2
T.check(not ScopedMeshStorage.write(storageKey, "fp-1", replacement),
        "a failed replacement does not commit")
strictFailOnWrite = nil
T.eq(ScopedMeshStorage.read(storageKey, "fp-1"), storagePayload,
     "failed replacement preserves the previous generation")

strictRecords, strictWriteCount, strictFailOnWrite = {}, 0, 1
T.check(not ScopedMeshStorage.write(storageKey, "fp-first", storagePayload),
        "a first write can fail before commit")
strictFailOnWrite = nil
T.check(ScopedMeshStorage.read(storageKey, "fp-first") == nil,
        "an uncommitted first write is invisible")

local legacyKey = { mapId = "LEGACY", slot = "body", kind = "terrain" }
strictRecords["meshes/LEGACY_body_terrain"] = { body = "legacy-payload" }
local legacyPayload, legacySource = ScopedMeshStorage.read(legacyKey, "legacy-fp")
T.eq(legacyPayload, "legacy-payload", "legacy storage records remain readable")
T.eq(legacySource, "legacy", "legacy reads identify their source")
strictWriteCount = 0
T.check(ScopedMeshStorage.write(storageKey, "fp-1", storagePayload),
        "new writes use v2 after a legacy cache is present")
for key in pairs(strictRecords) do
  if key ~= "meshes/LEGACY_body_terrain" then
    T.check(key:sub(1, 10) == "meshes/v2/",
            "new writes do not modify legacy records")
  end
end
local scanned, scannedCount = ScopedMeshStorage.scan({
  { mapId = "A/B", slot = "body", kind = "terrain", fingerprint = "fp-1" },
}, "identity")
T.eq(scannedCount, 1, "storage scan counts committed payloads")
T.check(scanned["A/B/body/terrain"] ~= nil,
        "storage scan returns the logical payload key")
T.check(ScopedMeshStorage.writeMeta("manifest", {
  schema = 2, identity = "identity", complete = false,
}), "storage writes metadata records")
local manifestMeta = ScopedMeshStorage.readMeta("manifest")
T.check(manifestMeta and manifestMeta.complete == false,
        "storage reads data-only metadata records")
T.check(ScopedMeshStorage.remove(storageKey),
        "storage removes one logical payload")
T.check(ScopedMeshStorage.read(storageKey, "fp-1") == nil,
        "removed payload is no longer readable")
T.check(ScopedMeshStorage.wipe(), "storage wipes v2 and legacy records")
T.check(next(strictRecords) == nil, "storage wipe removes scoped records")

local integrationStorage = exports.lib.mod.storage
local integrationChunkSize = ScopedMeshStorage.CHUNK_SIZE
exports.lib.mod.storage = strictStorage
ScopedMeshStorage.CHUNK_SIZE = 64
strictRecords, strictWriteCount, strictFailOnWrite = {}, 0, nil
local integrationMap = {
  id = "A", tileset = { image = "tileset.png", trueColor = false },
  renderer = { gbcAtlas = false },
}
local integrationVerts = {
  { 0, 0, 0, 0, 0, 1 }, { 1, 0, 0, 1, 0, 1 },
  { 1, 1, 0, 1, 1, 1 }, { 0, 1, 0, 0, 1, 1 },
}
local integrationIdx = { 1, 2, 3, 1, 3, 4 }
MeshCache.configure({ maps = maps, tilesets = {} }, storageGame)
T.eq(MeshCache.saveTerrain(integrationMap, "body", integrationVerts, 4,
                           integrationIdx, 6), true,
     "MeshCache saves terrain through the scoped adapter")
T.eq(MeshCache.saveWater(integrationMap, "body", integrationVerts, 4,
                         integrationIdx, 6), true,
     "MeshCache saves water through the scoped adapter")
T.eq(MeshCache.saveAux(integrationMap, "body", {
  grass = { n = 4, buf = integrationVerts, m = 6, idx = integrationIdx },
  flowers = nil, figures = {},
}), true, "MeshCache saves aux through the scoped adapter")
local integrationSawV2 = false
for key in pairs(strictRecords) do
  if key:sub(1, 10) == "meshes/v2/" then integrationSawV2 = true end
  T.check(key:sub(1, 7) ~= "meshes/" or key:sub(1, 10) == "meshes/v2/",
          "MeshCache does not write flattened storage keys")
end
T.check(integrationSawV2, "MeshCache writes chunked v2 records")
T.check(MeshCache.loadTerrain(integrationMap, "body") ~= nil,
        "MeshCache loads terrain from chunked records")
T.check(MeshCache.loadAux(integrationMap, "body") ~= nil,
        "MeshCache loads aux from chunked records")

-- Runtime loading gets one decode per payload, with a cooperative checkpoint
-- in each non-empty vertex/index stream. Validation used to decode once and
-- load decoded the same bytes again, doubling the transition work.
do
  local function chunksFor(kind)
    local suffix = "/41/body/" .. kind .. "/commit"
    for key, value in pairs(strictRecords) do
      if key:sub(-#suffix) == suffix then return value.chunks end
    end
    return 0
  end
  local Budget = exports.lib.require("BuildBudget")
  local oldCheck = Budget.check
  local checks = 0
  Budget.check = function() checks = checks + 1 end
  local terrain, water = MeshCache.loadTerrain(integrationMap, "body")
  Budget.check = oldCheck
  T.check(terrain ~= nil and water ~= nil,
          "single-pass terrain fixture loads both mesh streams")
  T.eq(checks, chunksFor("terrain") + chunksFor("water") + 4,
       "terrain cache yields in each vertex and index stream exactly once")

  checks = 0
  Budget.check = function() checks = checks + 1 end
  local aux = MeshCache.loadAux(integrationMap, "body")
  Budget.check = oldCheck
  T.check(aux ~= nil, "single-pass auxiliary fixture loads")
  T.eq(checks, chunksFor("aux") + 2,
       "aux cache performs one cooperative vertex/index decode")
end

-- A connected-map request happens on the render/update boundary. Even when
-- the destination is fully precached, request() must only queue cooperative
-- work; reading and decoding storage here turns the crossing frame into a
-- visible stall.
do
  local ChunkMesher = exports.lib.require("ChunkMesher")
  local crossingMap = {
    id = "CROSSING_CACHE", tileset = { image = "tileset.png", trueColor = false },
    renderer = { gbcAtlas = false },
  }
  MeshCache.saveTerrain(crossingMap, "full", integrationVerts, 4,
                        integrationIdx, 6)
  MeshCache.saveWater(crossingMap, "full", integrationVerts, 4,
                      integrationIdx, 6)
  MeshCache.saveAux(crossingMap, "full", {
    grass = { n = 4, buf = integrationVerts, m = 6, idx = integrationIdx },
    flowers = nil, figures = {},
  })
  strictReadCount = 0
  local before = ChunkMesher.pending()
  local immediate = ChunkMesher.request(crossingMap, false, nil, true)
  T.eq(strictReadCount, 0,
       "cold cached destination request performs no synchronous storage reads")
  T.eq(immediate, nil,
       "cold cached destination is completed by the cooperative worker")
  T.eq(ChunkMesher.pending(), before + 1,
       "cold cached destination queues one cooperative load job")
  ChunkMesher.release(crossingMap.id)
end

-- Chunk reconstruction is part of that cooperative job. Every bounded
-- storage record must offer the budget a yield point; otherwise a large map's
-- dozens of records still monopolise one frame before decode starts.
do
  local Budget = exports.lib.require("BuildBudget")
  local yieldKey = { mapId = "YIELD_CACHE", slot = "body", kind = "terrain" }
  local yieldPayload = string.rep("yield-payload", 80)
  T.check(ScopedMeshStorage.write(yieldKey, "yield-fp", yieldPayload),
          "yield fixture writes as several bounded records")
  local oldCheck = Budget.check
  local checks = 0
  Budget.check = function() checks = checks + 1 end
  strictReadCount = 0
  local reread = ScopedMeshStorage.read(yieldKey, "yield-fp")
  Budget.check = oldCheck
  T.eq(reread, yieldPayload,
       "cooperative chunk read preserves the committed payload")
  T.check(checks >= 2,
          "chunked storage read offers cooperative yield points")
end
ScopedMeshStorage.CHUNK_SIZE = integrationChunkSize
exports.lib.mod.storage = integrationStorage

local prebuildStorage = exports.lib.mod.storage
exports.lib.mod.storage = strictStorage
ScopedMeshStorage.CHUNK_SIZE = 64
strictRecords, strictWriteCount, strictFailOnWrite = {}, 0, nil
local prebuildGame = { data = { maps = maps }, save = storageGame.save }
MeshCache.configure(prebuildGame.data, prebuildGame)
T.check(Prebuild.start(prebuildGame),
        "prebuild starts with scoped storage available")
T.check(Prebuild.fail("terrain: write_failed"),
        "prebuild records a storage failure")
T.eq(Prebuild.status(), "FAILED",
     "prebuild exposes a failed storage build")
T.check(Prebuild.error() and Prebuild.error():find("write_failed", 1, true),
        "prebuild retains the storage failure detail")

-- The live sandbox removes package, so finishing a build must not inspect
-- package.loaded while releasing the temporary map.
T.check(Prebuild.start(prebuildGame),
        "prebuild can restart before the sandbox cleanup regression")
local savedPackage = _G.package
_G.package = nil
local cleanupOk, cleanupResult = pcall(Prebuild.fail, "sandbox cleanup")
_G.package = savedPackage
T.check(cleanupOk and cleanupResult == true,
        "prebuild cleanup does not require the sandbox package global")

strictRecords, strictWriteCount, strictFailOnWrite = {}, 0, nil
local prebuildMap = {
  id = "A", tileset = { image = "tileset.png", trueColor = false },
  renderer = { gbcAtlas = false },
}
MeshCache.configure(prebuildGame.data, prebuildGame)
MeshCache.saveTerrain(prebuildMap, "body", integrationVerts, 4,
                      integrationIdx, 6)
MeshCache.saveWater(prebuildMap, "body", integrationVerts, 4,
                    integrationIdx, 6)
MeshCache.saveAux(prebuildMap, "body", {
  grass = { n = 4, buf = integrationVerts, m = 6, idx = integrationIdx },
  flowers = nil, figures = {},
})
Prebuild.bootstrap(prebuildGame)
T.check(Prebuild.start(prebuildGame),
        "prebuild restarts after scanning committed jobs")
local resumedDone, resumedTotal, resumedRunning = Prebuild.progress()
T.eq(resumedDone, 1, "prebuild resumes past one committed logical job")
T.eq(resumedTotal, 4, "prebuild resume keeps the logical job total")
T.check(resumedRunning, "prebuild resume remains active for missing jobs")
Prebuild.cancel()
Prebuild.update()

-- Switching from boot/title skeleton state to selected-playthrough storage
-- must rescan that selected scope. Reusing the previous scope's resume set
-- would skip jobs that do not exist after CONTINUE.
titleScopes[selectedPlaythrough] = {}
titleAwareStorage.selected = function()
  return titleStorageMethods(selectedPlaythrough)
end
exports.lib.mod.storage = titleAwareStorage
local selectedTitleGame = {
  data = prebuildGame.data,
  save = { version = "red", meta = {} },
  stack = { states = { { screenId = "TitleState" } } },
}
T.check(Prebuild.start(selectedTitleGame),
        "prebuild starts after binding selected title storage")
local selectedDone = Prebuild.progress()
T.eq(selectedDone, 0,
     "prebuild does not reuse resume records from another playthrough scope")
Prebuild.cancel()
Prebuild.update()

ScopedMeshStorage.CHUNK_SIZE = integrationChunkSize
exports.lib.mod.storage = prebuildStorage
local oldStorage = exports.lib.mod.storage
exports.lib.mod.storage = storage
MeshCache.configure({ maps = maps, tilesets = {} }, storageGame)
T.check(MeshCache.available(),
        "mesh cache is available through mod.storage in the sandbox")
local storageMap = {
  id = "A", tileset = { image = "tileset.png", trueColor = false },
  renderer = { gbcAtlas = false },
}
local storageVerts = {
  { 0, 0, 0, 0, 0, 1 }, { 1, 0, 0, 1, 0, 1 },
  { 1, 1, 0, 1, 1, 1 }, { 0, 1, 0, 0, 1, 1 },
}
local storageIdx = { 1, 2, 3, 1, 3, 4 }
T.eq(MeshCache.saveTerrain(storageMap, "body", storageVerts, 4,
                           storageIdx, 6), true,
     "terrain cache writes through scoped storage")
T.eq(MeshCache.saveWater(storageMap, "body", storageVerts, 4,
                         storageIdx, 6), true,
     "water cache writes through scoped storage")
T.eq(MeshCache.saveAux(storageMap, "body", {
  grass = { n = 4, buf = storageVerts, m = 6, idx = storageIdx },
  flowers = nil, figures = {},
}), true, "aux cache writes through scoped storage")
local storageRecord = MeshCache.jobRecord(storageMap, "body")
T.check(MeshCache.loadTerrain(storageMap, "body") ~= nil,
        "terrain cache reads back from scoped storage")
T.check(MeshCache.loadAux(storageMap, "body") ~= nil,
        "aux cache reads back from scoped storage")
Perf.setGame(storageGame)
T.check(Perf.write("cache/bench", { source = "storage" }),
        "benchmark reports persist through scoped storage")
T.check(storageFiles["perf/cache/bench"]
          and type(storageFiles["perf/cache/bench"].body) == "string",
        "benchmark report is stored as data-only text")
MeshCache.begin()
T.check(MeshCache.writeManifest({ [storageRecord.key] = storageRecord }, 1),
        "storage cache writes its manifest")
MeshCache.configure({ maps = maps, tilesets = {} }, storageGame)
T.check(MeshCache.ready({ { id = "A", slot = "body" } }),
        "storage cache is READY after a fresh configuration")
MeshCache.wipe({ { id = "A", slot = "body" } })
exports.lib.mod.storage = oldStorage
MeshCache.setGame(nil)

-- Stadium import now uses a ROM placed inside the mod's own folder. The
-- sandbox does not offer a host picker, but mod:read is the scoped replacement
-- for reading a bundled/installed sibling file.
local StadiumInstall = exports.lib.require("StadiumInstall")
local Stadium = exports.lib.require("Stadium")
T.eq(Stadium.setDebug(true), false,
     "Stadium diagnostics can be enabled through the module API")
T.check(Stadium.debugEnabled(),
        "Stadium diagnostics report their explicit sandbox-safe state")
T.eq(Stadium.setDebug(false), true,
     "Stadium diagnostics can be disabled through the module API")
local oldRead = exports.lib.mod.read
exports.lib.mod.read = function(_, path)
  if path == "baseroms/baserom.z64" then return "rom bytes" end
  return nil
end
T.eq(StadiumInstall.romPath(), "baseroms/baserom.z64",
     "Stadium finds a ROM through mod:read")
T.check(StadiumInstall.romPresent(),
        "Stadium reports a scoped ROM as present")
exports.lib.mod.read = oldRead

T.check(MeshCache.mkdirCommands == nil,
        "directory creation is shell-free (love.filesystem / libc mkdir)")

local record = MeshCache.jobRecord({
  id = "A", tileset = { image = "tileset.png", trueColor = false },
  renderer = { gbcAtlas = false },
}, "body")
T.check(record.terrain ~= record.water and record.water ~= record.aux,
        "job record names terrain, water, and aux files separately")
T.check(record.terrainFp ~= record.waterFp
          and record.waterFp ~= record.auxFp,
        "job record fingerprints each payload separately")

-- F6: the dataset revision covers every tileset input the mesher reads.
local function shallowCopy(table_)
  local out = {}
  for key, value in pairs(table_ or {}) do out[key] = value end
  return out
end
local baseData = {
  maps = {
    A = { id = "A", width = 4, height = 5, borderBlock = 0,
          tileset = "T", blocks = { 1, 2, 3, 4, 5, 6 },
          connections = { east = { map = "B", offset = 0 } } },
  },
  tilesets = {
    T = { id = "T", image = "t.png", tilesPerRow = 16,
          blocks = { 1, 2 }, walkable = { 1, 2 }, counterTiles = {},
          doorTiles = {}, warpTiles = {}, grassTile = 1 },
  },
}
MeshCache.configure(baseData)
local baseIdentity = MeshCache.identity()
local function revisionDiffers(variant)
  MeshCache.configure(variant)
  local different = MeshCache.identity() ~= baseIdentity
  MeshCache.configure(baseData)
  return different
end
local counterVariant = { maps = baseData.maps,
                         tilesets = { T = shallowCopy(baseData.tilesets.T) } }
counterVariant.tilesets.T.counterTiles = { 42 }
T.check(revisionDiffers(counterVariant),
        "counterTiles changes the dataset revision")
local grassVariant = { maps = baseData.maps,
                       tilesets = { T = shallowCopy(baseData.tilesets.T) } }
grassVariant.tilesets.T.grassTile = 7
T.check(revisionDiffers(grassVariant),
        "grassTile changes the dataset revision")
local doorVariant = { maps = baseData.maps,
                      tilesets = { T = shallowCopy(baseData.tilesets.T) } }
doorVariant.tilesets.T.doorTiles = { 9 }
T.check(revisionDiffers(doorVariant),
        "doorTiles changes the dataset revision")
local warpVariant = { maps = baseData.maps,
                      tilesets = { T = shallowCopy(baseData.tilesets.T) } }
warpVariant.tilesets.T.warpTiles = { 4, 5 }
T.check(revisionDiffers(warpVariant),
        "warpTiles changes the dataset revision")
local walkVariant = { maps = baseData.maps,
                      tilesets = { T = shallowCopy(baseData.tilesets.T) } }
walkVariant.tilesets.T.walkable = { 1 }
T.check(revisionDiffers(walkVariant),
        "walkable changes the dataset revision")

local ffiOk, ffi = pcall(require, "ffi")
local cacheDir = MeshCache.dir()
if ffiOk and cacheDir and MeshCache.dirBackend() ~= "storage" then
  T.check(MeshCache.dirBackend() == "love"
            or MeshCache.dirBackend() == "ffi",
          "dir resolution records which backend created the folder")
  T.check(MeshCache.probeWritable(cacheDir),
          "the resolved cache dir passes a real io write probe")
  T.check(not MeshCache.probeWritable("/definitely/not/here/potato_voxel"),
          "a nonexistent directory fails the write probe")
  local fakeMap = {
    id = "A", tileset = { image = "tileset.png", trueColor = false },
    renderer = { gbcAtlas = false },
  }
  MeshCache.configure({ maps = maps, tilesets = {} })
  MeshCache.saveTerrain(fakeMap, "body", nil, 0)
  MeshCache.saveWater(fakeMap, "body", nil, 0)
  MeshCache.saveAux(fakeMap, "body", { figures = {} })
  local manifestRecord = MeshCache.jobRecord(fakeMap, "body")
  local originalAvailable = MeshCache.available
  MeshCache.available = function() return true end
  os.remove(cacheDir .. "/cache.info")
  local ready = MeshCache.ready({ { id = "A", slot = "body" } })
  T.check(ready, "complete cache without a manifest reports READY")
  local manifest = io.open(cacheDir .. "/cache.info", "rb")
  T.check(manifest ~= nil, "legacy complete cache gets a manifest")
  if manifest then manifest:close() end
  os.remove(cacheDir .. "/" .. manifestRecord.water)
  T.check(not MeshCache.ready({ { id = "A", slot = "body" } }),
          "missing cache payload clears READY")
  T.check(MeshCache.wipe({ { id = "A", slot = "body" } }),
          "wipe cache removes precache files")
  local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
  end
  T.check(not exists(cacheDir .. "/" .. manifestRecord.terrain)
          and not exists(cacheDir .. "/" .. manifestRecord.water)
          and not exists(cacheDir .. "/" .. manifestRecord.aux),
          "wipe cache removes all payload variants")

  local oldLove = love
  local testLove = oldLove or {}
  local oldData = testLove.data
  local packed = {}
  local serial = 0
  testLove.data = {
    compress = function(_, format, body)
      -- Simulate the shipped runtime: no zstd codec, lz4 only. A format
      -- that is not lz4 returns nil so packPayload falls back to lz4.
      if format ~= "lz4" then return nil end
      serial = serial + 1
      local key = "packed" .. serial
      packed[key] = body
      return key
    end,
    decompress = function(_, _, body) return packed[body] end,
  }
  _G.love = testLove
  MeshCache.configure({ maps = maps, tilesets = {} })
  local vertices = ffi.new("float[?]", 128 * 6)
  MeshCache.saveTerrain(fakeMap, "body", vertices, 128)
  local compressed = io.open(cacheDir .. "/A.body.terrain", "rb")
  local compressedFormat = compressed and compressed:read(4):byte(4) or nil
  if compressed then compressed:close() end
  T.eq(compressedFormat, 2, "cache uses compressed format when available")
  MeshCache.saveWater(fakeMap, "body", nil, 0)
  MeshCache.saveAux(fakeMap, "body", { figures = {} })
  local loaded = MeshCache.loadTerrain(fakeMap, "body")
  T.check(loaded ~= nil and loaded.n == 128,
          "compressed cache payload loads through the normal decoder")
  local oldDecompress = testLove.data.decompress
  testLove.data.decompress = function()
    error("boot validation should not decompress every cached payload")
  end
  T.check(MeshCache.ready({ { id = "A", slot = "body" } }),
          "compressed cache reports READY from headers")
  T.eq(MeshCache.compressionStatus(), "compressed",
       "cache status identifies compressed payloads")
  T.eq(MeshCache.codec(), "lz4",
       "cache status identifies the codec (lz4 fallback without zstd)")
  T.check(MeshCache.ready({ { id = "A", slot = "body" } }),
          "manifest READY check uses bounded payload headers")
  testLove.data.decompress = oldDecompress

  -- A runtime WITH zstd: the same payload compressed as zstd writes codec
  -- byte 2, and codec() reports "zstd" -- the READY (ZSTD) label path.
  testLove.data.compress = function(_, format, body)
    if format ~= "zstd" then return nil end
    serial = serial + 1
    local key = "zpacked" .. serial
    packed[key] = body
    return key
  end
  MeshCache.saveTerrain(fakeMap, "body", vertices, 128)
  MeshCache.saveWater(fakeMap, "body", nil, 0)
  MeshCache.saveAux(fakeMap, "body", { figures = {} })
  local zloaded = MeshCache.loadTerrain(fakeMap, "body")
  T.check(zloaded ~= nil and zloaded.n == 128,
          "zstd-compressed payload loads through the codec-aware decoder")
  T.check(MeshCache.ready({ { id = "A", slot = "body" } }),
          "zstd cache reports READY from headers")
  T.eq(MeshCache.codec(), "zstd",
       "cache status identifies the zstd codec")

  testLove.data = oldData
  _G.love = oldLove
  MeshCache.wipe({ { id = "A", slot = "body" } })

  -- --- relaunch simulation: same data + options => READY, no rebuild ------
  local function readManifestIdentity()
    local f = io.open(cacheDir .. "/cache.info", "rb")
    if not f then return nil end
    local line = f:read()
    f:close()
    return line and line:match("^PVMC1\t([^\t]+)\t%d+$") or nil
  end
  local function readBuildInfoText()
    local f = io.open(cacheDir .. "/build.info", "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
  end

  os.remove(cacheDir .. "/build.info")
  local buildJob = { id = "A", slot = "body" }
  MeshCache.configure({ maps = maps, tilesets = {} })
  MeshCache.begin()
  MeshCache.saveTerrain(fakeMap, "body", nil, 0)
  MeshCache.saveWater(fakeMap, "body", nil, 0)
  MeshCache.saveAux(fakeMap, "body", { figures = {} })
  local builtRecord = MeshCache.jobRecord(fakeMap, "body")
  T.check(MeshCache.writeManifest({ [builtRecord.key] = builtRecord }, 1),
          "active build writes a manifest")
  local builtIdentity = readManifestIdentity()
  T.eq(builtIdentity, MeshCache.identity(),
       "manifest identity equals the live identity after an unchanged build")
  local buildInfo = readBuildInfoText()
  T.check(buildInfo and buildInfo:find("identity=" .. builtIdentity, 1, true),
          "build.info records the build identity")

  -- A fresh configure() is the relaunch: same maps, same default options.
  MeshCache.configure({ maps = maps, tilesets = {} })
  T.eq(MeshCache.identity(), builtIdentity,
       "relaunch recomputes the same cache identity")
  T.check(MeshCache.ready({ buildJob }),
          "relaunch reports READY from the existing manifest (no rebuild)")
  T.check(MeshCache.getLastFailure() == nil,
          "a READY cache leaves lastFailure unset")

  -- --- begin()-time snapshot survives a mid-build identity drift ---------
  local okTR, TileRenderer = pcall(require, "src.render.TileRenderer")
  if okTR and TileRenderer then
    local oldVoidFill = TileRenderer.voidFill
    local driftedFill = oldVoidFill == "cactus" and "trees" or "cactus"
    os.remove(cacheDir .. "/build.info")
    MeshCache.configure({ maps = maps, tilesets = {} })
    MeshCache.begin()
    local snapshotIdentity = MeshCache.identity()
    local snapshot = MeshCache.buildInfoSnapshot()
    T.check(snapshot and snapshot.identity == snapshotIdentity,
            "buildInfoSnapshot exposes the begin()-time identity")
    -- Mid-build drift: a live identity component changes after begin().
    TileRenderer.voidFill = driftedFill
    MeshCache.saveTerrain(fakeMap, "body", nil, 0)
    MeshCache.saveWater(fakeMap, "body", nil, 0)
    MeshCache.saveAux(fakeMap, "body", { figures = {} })
    T.check(MeshCache.writeManifest({ [builtRecord.key] = builtRecord }, 1),
            "build finishes normally despite a mid-build identity drift")
    local driftedManifestId = readManifestIdentity()
    T.eq(driftedManifestId, snapshotIdentity,
         "manifest carries the begin()-time identity, not the drifted one")
    local driftedBuildInfo = readBuildInfoText()
    T.check(driftedBuildInfo
              and driftedBuildInfo:find("identity=" .. snapshotIdentity, 1, true),
            "build.info carries the begin()-time identity")
    -- Next launch: a fresh session drops the snapshot while the live
    -- identity still carries the drifted voidFill, so ready() must report
    -- the mismatch explicitly instead of a generic rejection.
    MeshCache.configure({ maps = maps, tilesets = {} })
    T.check(not MeshCache.ready({ buildJob }),
            "drifted live identity rejects the cache")
    local failure = MeshCache.getLastFailure()
    T.check(failure and failure.reason == "identity_mismatch",
            "rejection is reported as identity_mismatch")
    T.eq(failure.actual, snapshotIdentity,
         "identity_mismatch reports the manifest (actual) identity")
    T.check(failure.diffs and failure.diffs[1] == "voidFill",
            "identity_mismatch diff pinpoints the voidFill drift")
    TileRenderer.voidFill = oldVoidFill
    MeshCache.wipe({ buildJob })
  end

  -- --- F3 + F5: saves report results; begin() keeps the manifest ---------
  MeshCache.configure({ maps = maps, tilesets = {} })
  MeshCache.begin()
  T.eq(MeshCache.saveTerrain(fakeMap, "body", nil, 0), true,
       "saveTerrain reports its write result")
  T.eq(MeshCache.saveWater(fakeMap, "body", nil, 0), true,
       "saveWater reports its write result")
  T.eq(MeshCache.saveAux(fakeMap, "body", { figures = {} }), true,
       "saveAux reports its write result")
  T.eq(MeshCache.saveError(), nil,
       "successful saves leave no write error")
  local f3Record = MeshCache.jobRecord(fakeMap, "body")
  T.check(MeshCache.writeManifest({ [f3Record.key] = f3Record }, 1),
          "build writes a manifest")
  T.check(exists(cacheDir .. "/cache.info"),
          "manifest exists after the build")
  MeshCache.begin()
  T.check(exists(cacheDir .. "/cache.info"),
          "begin() keeps the manifest (F3): a mid-build death leaves it")
  T.check(MeshCache.writeManifest({ [f3Record.key] = f3Record }, 1),
          "manifest rewrite over an existing file succeeds (F4 self-heal)")
  MeshCache.wipe({ buildJob })

  -- --- F3: an interrupted build leaves a manifest naming finished jobs --
  local jobSet = Prebuild.enumerate(maps)   -- A body/full, B body/full
  local fakeMapB = {
    id = "B", tileset = { image = "tileset.png", trueColor = false },
    renderer = { gbcAtlas = false },
  }
  MeshCache.configure({ maps = maps, tilesets = {} })
  MeshCache.begin()
  MeshCache.saveTerrain(fakeMap, "body", nil, 0)
  MeshCache.saveWater(fakeMap, "body", nil, 0)
  MeshCache.saveAux(fakeMap, "body", { figures = {} })
  local partial = {}
  local bodyRecord = MeshCache.jobRecord(fakeMap, "body")
  partial[bodyRecord.key] = bodyRecord
  T.check(MeshCache.writeProgress(partial, #jobSet),
          "writeProgress writes a partial manifest")
  T.check(exists(cacheDir .. "/cache.info"),
          "interrupted build leaves a manifest behind")
  -- the relaunch: a fresh session rescans the actual files
  MeshCache.configure({ maps = maps, tilesets = {} })
  local complete, doneCount = MeshCache.scanComplete(jobSet)
  T.eq(doneCount, 1, "scanComplete finds exactly the one finished job")
  T.check(complete["A/body"] ~= nil and complete["A/full"] == nil
          and complete["B/body"] == nil,
          "scanComplete names the finished job and skips the rest")
  local readyOk, resumeCount = MeshCache.ready(jobSet)
  T.check(not readyOk, "a partial build is not READY")
  T.eq(resumeCount, 1, "ready reports the resumable job count")
  MeshCache.wipe(jobSet)

  -- --- F1: boot under skeleton options, refresh after the save loads ----
  local okTR, TileRenderer = pcall(require, "src.render.TileRenderer")
  if okTR and TileRenderer then
    local originalFill = TileRenderer.voidFill
    local saveFill = originalFill ~= "cactus" and "cactus" or "water"
    MeshCache.configure({ maps = maps, tilesets = {} })
    TileRenderer.voidFill = saveFill
    MeshCache.begin()
    for _, job in ipairs(jobSet) do
      local m = job.id == "A" and fakeMap or fakeMapB
      MeshCache.saveTerrain(m, job.slot, nil, 0)
      MeshCache.saveWater(m, job.slot, nil, 0)
      MeshCache.saveAux(m, job.slot, { figures = {} })
    end
    local full = {}
    for _, job in ipairs(jobSet) do
      local m = job.id == "A" and fakeMap or fakeMapB
      local rec = MeshCache.jobRecord(m, job.slot)
      full[rec.key] = rec
    end
    T.check(MeshCache.writeManifest(full, #jobSet),
            "build completes under the save's VOID FILL")
    -- boot: game.ready runs under the skeleton save's DEFAULT options
    TileRenderer.voidFill = originalFill
    local stubGame = { data = { maps = maps, tilesets = {} } }
    T.check(not Prebuild.bootstrap(stubGame),
            "skeleton defaults do not match the save's cache")
    T.check(not Prebuild.isReady(),
            "cache not READY while the skeleton options are active")
    -- the save loads and the engine applies the slot's real options; the
    -- post-load gate refreshes under them (no invalidation needed)
    TileRenderer.voidFill = saveFill
    T.check(Prebuild.refresh(stubGame),
            "refresh after the save's options land reports READY")
    T.check(Prebuild.isReady(),
            "no rebuild prompt after the boot/load options transition")
    TileRenderer.voidFill = originalFill
    MeshCache.wipe(jobSet)
  end

  MeshCache.available = originalAvailable
end

run.release()
T.finish("potato_voxel_cache")
