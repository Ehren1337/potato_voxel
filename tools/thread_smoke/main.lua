-- Threaded-geometry smoke test. Runs under the REAL love binary (no
-- test stub) to prove the worker can load the mod's lib graph through the
-- sandbox shim and return a geometry result through the channels.
--
--   love /Users/shanemcgovern/dev/potato_voxel/tools/thread_smoke
--
-- Exits 0 on success, 1 on failure.

-- the mod directory: symlinked as lib/ + workers/ next to this file, so
-- the harness game dir itself resolves them (no mount needed)
local modRoot = "."
assert(love.filesystem.mount or true)

-- engine shims, exactly like workers/geometry_worker.lua seeds them
local Assets = { register = function() end, imageData = function() return nil end }
local Map = {
  isOutdoor = function(def)
    if def.outdoor ~= nil then return def.outdoor end
    return def.tileset == "OVERWORLD"
  end,
  blockAt = function(self, bx, by)
    if bx < 0 or by < 0 or bx >= self.def.width or by >= self.def.height then
      return self.def.borderBlock
    end
    return self.def.blocks[by * self.def.width + bx + 1]
  end,
  tileAt = function(self, tx, ty)
    local bx, by = math.floor(tx / 4), math.floor(ty / 4)
    local block = self.tileset.blocks[self:blockAt(bx, by) + 1]
    local ix = (ty % 4) * 4 + (tx % 4) + 1
    return block[ix]
  end,
  cellTile = function(self, cx, cy)
    return self:tileAt(cx * 2, cy * 2 + 1)
  end,
  inBounds = function(self, cx, cy)
    return cx >= 0 and cy >= 0 and cx < self.def.width * 2
           and cy < self.def.height * 2
  end,
  isWalkableCell = function(self, cx, cy)
    return self.walkable and self.walkable[self:cellTile(cx, cy)] or false
  end,
  isGrassCell = function(self, cx, cy)
    if not self:inBounds(cx, cy) then return false end
    local grass = self.tileset.grassTile
    return grass ~= nil and self:cellTile(cx, cy) == grass
  end,
  isWaterCell = function(self, cx, cy)
    return self.waterTiles and self.waterTiles[self:cellTile(cx, cy)] or false
  end,
}
local TileRenderer = { voidFill = "trees",
  borderBlockFor = function(map)
    if map.def.tileset == "OVERWORLD" then return 0x0F end
    return map.def.borderBlock
  end }
package.loaded["src.render.Assets"] = Assets
package.loaded["src.world.Map"] = Map
package.loaded["src.render.TileRenderer"] = TileRenderer
package.loaded["src.core.Game"] = {}
package.loaded["DebugOverlay"] = {}

-- any other engine module the load graph pulls in resolves to a stub
local function srcStub(name)
  if name:find("^src%.") then
    return function() return {} end
  end
  return "\n\tno stub for " .. name
end
table.insert(package.loaders or package.searchers, 1, srcStub)

local libs = {}
local V = { mod = {}, path = "potato_voxel" }
function V.require(name)
  local hit = libs[name]
  if hit ~= nil then return hit end
  local ok, chunk = pcall(love.filesystem.load, "lib/" .. name .. ".lua")
  assert(ok and chunk, "load lib/" .. name)
  local value = chunk(V)
  libs[name] = value
  return value
end

local WorkerPool = V.require("WorkerPool")
local MeshCache = V.require("MeshCache")

-- a tiny flat map: 4x4 grass blocks, no structures to speak of
local blocks = {}
for i = 1, 16 do blocks[i] = 1 end          -- block 1 = grass
local tileset = {
  id = "SMOKE", image = "smoke.png", tilesPerRow = 16,
  imageWidth = 128, imageHeight = 48,
  blocks = { { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
             { 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 } },
}
local map = {
  id = "SMOKE_CITY", def = { width = 4, height = 4, blocks = blocks,
                             borderBlock = 1, tileset = "OVERWORLD" },
  tileset = tileset,
  walkable = { [1] = true, [2] = true },
  waterTiles = {},
  doorTiles = {},
}

-- 1. serialization round-trip
local src = WorkerPool.serializeMap(map)
local chunk = assert(load(src, "@smoke", "t"))
local map2 = chunk()
map2.tileAt = Map.tileAt
map2.blockAt = Map.blockAt
assert(map2.id == "SMOKE_CITY" and map2.def.width == 4
       and map2.def.blocks[1] == 1 and map2.tileset.blocks[2][16] == 2,
       "serialize round-trip")

-- 2. the real threaded round trip
assert(WorkerPool.enabled(), "pool enabled under real love")
WorkerPool.start()
assert(WorkerPool.working(), "workers started")

local gen = WorkerPool.submit({
  version = MeshCache.GEOMETRY_VERSION,
  mapSrc = src,
  bodyOnly = false,
  masks = {},
  voidFill = "trees",
  tileImage = nil,
})
assert(gen, "job submitted")

local deadline = love.timer.getTime() + 60
local result = nil
while love.timer.getTime() < deadline do
  local items = WorkerPool.poll()
  if #items > 0 then
    result = items[1]
    break
  end
  love.timer.sleep(0.01)
end

assert(result, "worker returned a result within 60s")
assert(not result.error, "result carries no error: " .. tostring(result.error))
local d = result.data
assert(d and d.terrain and d.terrain.n and d.terrain.n > 0,
       "terrain stream has vertices")
assert(d.terrain.n * 6 == #d.terrain.buf, "terrain buffer matches count")
assert(d.water and d.aux, "water + aux present")

print("THREADED GEOMETRY OK: terrain=" .. d.terrain.n .. " verts, "
      .. "aux grass=" .. tostring(d.aux.grass and d.aux.grass.n or 0)
      .. " figures=" .. tostring(#d.aux.figures))
WorkerPool.shutdown()
love.event.quit(0)
