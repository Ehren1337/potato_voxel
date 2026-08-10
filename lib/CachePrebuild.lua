-- Cooperative all-map mesh-cache prebuilder.
-- Keeps only one runtime map resident while ChunkMesher's normal sliced queue
-- does the actual body/full/aux work and writes terrain, water, and aux files.
local V = ...
local Prebuild = {}

local ChunkMesher = V.require("ChunkMesher")
local MeshCache = V.require("MeshCache")

-- Use the engine's own placement routine so prebuilt FULL masks cover the same
-- connected strips (including two-hop neighbours) as the live renderer.
local OverworldState = require("src.world.OverworldController")

local state = { running = false, cancelled = false, maps = {}, index = 0,
                slot = nil, done = 0, total = 0, game = nil,
                startedAt = nil, eta = nil, ready = false,
                failed = false, error = nil, completed = {} }

local function sortedIds(maps)
  local ids = {}
  for id, def in pairs(maps or {}) do
    if type(def) == "table" and def.width and def.height then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
  return ids
end

-- Direct connection rectangles in the current map's world-pixel frame. This
-- is the same placement math as OverworldState.computeNeighbors, but uses the
-- authoritative generated map definitions and never constructs neighbours.
local function masksFor(maps, id)
  local out = {}
  -- The live renderer asks for two connection hops.  Keep that contract here
  -- rather than reimplementing placement (and drifting when the engine does).
  local neighbours = OverworldState.computeNeighbors(maps, id, 2)
  for _, neighbour in ipairs(neighbours or {}) do
    local other = maps[neighbour.id]
    if other then
      out[#out + 1] = {
        neighbour.ox, neighbour.oy,
        neighbour.ox + other.width * 32,
        neighbour.oy + other.height * 32,
      }
    end
  end
  table.sort(out, function(a, b)
    return (a[2] == b[2]) and (a[1] < b[1]) or (a[2] < b[2])
  end)
  return out
end

Prebuild.enumerate = function(maps)
  local ids = sortedIds(maps)
  local jobs = {}
  for _, id in ipairs(ids) do
    local masks = masksFor(maps, id)
    jobs[#jobs + 1] = { id = id, slot = "body", masks = masks }
    jobs[#jobs + 1] = { id = id, slot = "full", masks = masks }
  end
  return jobs
end
Prebuild.masksFor = masksFor

function Prebuild.available()
  return MeshCache.available()
end

function Prebuild.bootstrap(game)
  local data = game and game.data
  MeshCache.configure(data)
  local jobs = Prebuild.enumerate(data and data.maps)
  local ready, done = MeshCache.ready(jobs)
  state = { running = false, cancelled = false, maps = jobs, index = 0,
            slot = nil, done = ready and #jobs or done, total = #jobs,
            game = nil, startedAt = nil, eta = nil, ready = ready,
            failed = false, error = nil, completed = {} }
  return ready
end

-- Never tear down an instance the overworld can still draw.  The options
-- action may outlive the menu that started it (and the player can move while
-- it runs), so the live set has to be checked at the moment a job completes,
-- not only when prebuild starts.
local function liveMaps(game)
  local live = {}
  local overworld = game and (game.overworld or game)
  local current = overworld and overworld.map
  if current and current.id then live[current.id] = true end
  for _, neighbour in ipairs((overworld and overworld.neighbors) or {}) do
    local map = neighbour.map or neighbour
    if map and map.id then live[map.id] = true end
  end
  return live
end

local function releaseMap(id, game)
  if liveMaps(game)[id] then return false end
  if ChunkMesher.release then ChunkMesher.release(id) end
  local MapLoader = package.loaded["src.world.MapLoader"]
  local m = MapLoader and MapLoader.evict and MapLoader.cached(id)
  if m and MapLoader.evict then MapLoader.evict(id) end
  return true
end

local function finish(cancelled)
  if state.index > 0 and state.maps[state.index] then
    releaseMap(state.maps[state.index].id, state.game)
  end
  if not cancelled and not state.failed and state.done >= state.total then
    state.ready = MeshCache.writeManifest(state.completed, state.total)
    if not state.ready then
      state.failed = true
      state.error = "manifest write failed"
    end
  end
  state.running, state.cancelled = false, cancelled or false
  state.slot = nil
  state.game = nil
  state.eta = nil
end

local function now()
  local timer = love and love.timer
  if timer and timer.getTime then
    local ok, value = pcall(timer.getTime)
    if ok and type(value) == "number" then return value end
  end
  return nil
end

local function android()
  local system = love and love.system
  if not (system and system.getOS) then return false end
  local ok, os = pcall(system.getOS)
  return ok and os == "Android"
end

Prebuild.isAndroid = android

function Prebuild.start(game)
  if state.running then
    state.cancelled = true
    return false
  end
  local data = game and game.data
  local jobs = Prebuild.enumerate(data and data.maps)
  if #jobs == 0 or not MeshCache.available() then return false end
  MeshCache.begin()
  state = { running = true, cancelled = false, maps = jobs, index = 1,
            slot = nil, done = 0, total = #jobs, game = game,
            startedAt = now(), eta = nil, ready = false,
            failed = false, error = nil, completed = {} }
  return true
end

function Prebuild.cancel()
  if state.running then state.cancelled = true; return true end
  return false
end

function Prebuild.wipe(game)
  if state.running then return false end
  local data = game and game.data
  local jobs = Prebuild.enumerate(data and data.maps)
  local ok = MeshCache.wipe(jobs)
  if ok then
    ChunkMesher.invalidate()
    state.ready, state.cancelled, state.failed = false, false, false
    state.done, state.total, state.error = 0, #jobs, nil
  end
  return ok
end

-- Keep the options-row decision separate from the UI so the READY path can be
-- covered headlessly.  A running build keeps its existing A-to-cancel action;
-- only a completed cache needs confirmation before it is rebuilt.
function Prebuild.activationDecision(status, running)
  if running then return "cancel" end
  if status == "READY" then return "confirm_rebuild" end
  return "start"
end

function Prebuild.update()
  if not state.running then return end
  if state.cancelled then finish(true); return end
  local job = state.maps[state.index]
  if not job then finish(false); return end
  if not state.slot then
    local MapLoader = require("src.world.MapLoader")
    local map = MapLoader.load(state.game.data, job.id)
    state.slot = map
    ChunkMesher.request(map, job.slot == "body", job.masks, false, true)
  end
  -- Prebuild runs alongside normal gameplay; use the ordinary cooperative
  -- slice rather than the 30ms covered/menu budget.
  ChunkMesher.pump(false)
  local bodyOnly = job.slot == "body"
  local jobStatus = ChunkMesher.jobStatus(job.id, bodyOnly)
  if jobStatus == "pending" then return end
  if jobStatus ~= "complete" or not MeshCache.verifyJob(state.slot, job.slot) then
    state.failed = true
    state.error = jobStatus or "cache verification failed"
    finish(false)
    return
  end
  state.completed[tostring(job.id) .. "/" .. tostring(job.slot)] =
    MeshCache.jobRecord(state.slot, job.slot)
  releaseMap(job.id, state.game)
  state.done = state.done + 1
  state.index = state.index + 1
  state.slot = nil
  local elapsed = state.startedAt and now()
  if elapsed and state.startedAt and state.done > 0 then
    state.eta = (elapsed - state.startedAt) * (state.total - state.done) / state.done
  end
  if state.done >= state.total then finish(false) end
end

function Prebuild.status()
  if state.running then
    return (android() and "B" or "BUILD ") .. ("%d/%d"):format(
      state.done, state.total)
  end
  if state.ready and MeshCache.isDirty() then state.ready = false end
  if not Prebuild.available() then return "UNAVAILABLE" end
  if state.failed then return "FAILED" end
  if state.ready then return "READY" end
  if state.cancelled then return "CANCELLED" end
  return "PREBUILD"
end

function Prebuild.progress()
  return state.done, state.total, state.running, state.eta
end

function Prebuild.isReady()
  return state.ready and not MeshCache.isDirty()
end

return Prebuild
