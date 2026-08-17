-- Geometry worker for the threaded prebuilder (docs/threaded-geometry-design.md).
--
-- Runs the pure CPU phase of a cache job -- Structures analysis,
-- runGeometry's terrain/water streams and the flattened aux records --
-- off the main thread, following the engine's own chip_worker pattern
-- (src/core/chip_worker.lua): command channel in, result channel out,
-- one job at a time per worker.
--
-- The mod's lib files load through the same `local V = ...` sandbox as
-- in-game; the engine modules the geometry path touches are replaced by
-- the small pure shims below (pre-seeded into package.loaded so the
-- libs' plain `require("src...")` gets them), because the real modules
-- can reach into love.graphics and are not thread-safe. Shims are
-- value-identical for the geometry surface:
--   TileRenderer.borderBlockFor + voidFill  (border ring + void fill)
--   Map.isOutdoor / Map:tileAt / Map:blockAt
--   Assets.imageData                        (void-tile pixel scan)
--   Assets.register                         (no-op: no runtime cache here)
--
-- Job payload:  { cmd="geometry", gen, mapSrc, bodyOnly, masks,
--                 voidFill, tileImage }
--   mapSrc   Lua-source dump of the map's data tables (WorkerPool.serializeMap)
--   tileImage  a love ImageData for the tileset (or false) -- the SAME
--            object the main thread's Assets.imageData returned, so the
--            pixel scan is byte-identical to the serial path
-- Result:    { gen, data={ terrain={buf,n,idx,m}, water={...}, aux={..} } }
--         or { gen, error = msg } -- main falls back to the serial pump.

require("love.thread")
require("love.timer")
require("love.filesystem")
require("love.image")

-- --------------------------------------------------------- engine shims

local TileRenderer = {}
TileRenderer.voidFill = "trees" -- per-job override; see handleGeometry
local TREE_WALL_BLOCK = 0x0F
local WATER_BORDER_BLOCK = 0x43
function TileRenderer.borderBlockFor(map)
  if map.def.tileset == "OVERWORLD" then
    local mode = TileRenderer.voidFill or "trees"
    if mode == "water" then return WATER_BORDER_BLOCK end
    if mode == "black" then return false end
    return TREE_WALL_BLOCK
  end
  return map.def.borderBlock
end

local Assets = {}
function Assets.register() end
function Assets.imageData(path)
  if not (love and love.image and love.image.newImageData) then return nil end
  local ok, data = pcall(love.image.newImageData, path)
  return ok and data or nil
end

local Map = {}
function Map.isOutdoor(def)
  if def.outdoor ~= nil then return def.outdoor end
  return def.tileset == "OVERWORLD"
end
function Map.blockAt(self, bx, by)
  if bx < 0 or by < 0 or bx >= self.def.width or by >= self.def.height then
    return self.def.borderBlock
  end
  return self.def.blocks[by * self.def.width + bx + 1]
end
function Map.tileAt(self, tx, ty)
  local bx, by = math.floor(tx / 4), math.floor(ty / 4)
  local block = self.tileset.blocks[self:blockAt(bx, by) + 1]
  local ix = (ty % 4) * 4 + (tx % 4) + 1
  return block[ix]
end
function Map.cellTile(self, cx, cy)
  return self:tileAt(cx * 2, cy * 2 + 1)
end
function Map.inBounds(self, cx, cy)
  return cx >= 0 and cy >= 0 and cx < self.def.width * 2
         and cy < self.def.height * 2
end
function Map.isWalkableCell(self, cx, cy)
  return self.walkable and self.walkable[self:cellTile(cx, cy)] or false
end
function Map.isGrassCell(self, cx, cy)
  if not self:inBounds(cx, cy) then return false end
  local grass = self.tileset.grassTile
  return grass ~= nil and self:cellTile(cx, cy) == grass
end
function Map.isWaterCell(self, cx, cy)
  return self.waterTiles and self.waterTiles[self:cellTile(cx, cy)] or false
end

-- Anything else the libs touch lazily (MeshCache.resolveStore's Game,
-- DebugOverlay, Sky/DayNight's PaletteFX, ...) must never load the real
-- module in a thread: the pure geometry path does not need them. Anything
-- under "src." that is not pre-seeded above resolves to an empty-table
-- stub -- load-time side effects of the real modules (canvases, shaders)
-- are exactly what a thread cannot have.
local function srcStub(name)
  if name:find("^src%.") then
    return function() return {} end
  end
  return "\n\tno stub for " .. name
end
table.insert(package.loaders or package.searchers, 1, srcStub)

-- the shims we DO implement win over the stub via package.loaded
package.loaded["src.render.TileRenderer"] = TileRenderer
package.loaded["src.render.Assets"] = Assets
package.loaded["src.world.Map"] = Map

-- ------------------------------------------------------- mod sandbox

-- The mod's libs are loaded with `local V = ...` and V.require() exactly
-- like main.lua does; V.data is unused by the geometry path but shimmed
-- for load-time symmetry. `root` is the love.filesystem prefix to the mod
-- dir, set per job ("" for a dev harness, "mods/<id>" in the game).
local libs = {}
local root = ""
local V = { mod = {}, path = "potato_voxel" }
function V.require(name)
  local hit = libs[name]
  if hit ~= nil then return hit end
  local ok, chunk = pcall(love.filesystem.load,
                          root == "" and ("lib/" .. name .. ".lua")
                                       or (root .. "/lib/" .. name .. ".lua"))
  if not ok or not chunk then
    error("geometry worker: cannot load lib/" .. name .. ".lua: "
          .. tostring(chunk), 0)
  end
  local value = chunk(V)
  libs[name] = value
  return value
end
function V.data(name)
  local ok, chunk = pcall(love.filesystem.load,
                          root == "" and ("data/" .. name .. ".lua")
                                       or (root .. "/data/" .. name .. ".lua"))
  if not ok or not chunk then return nil end
  return chunk(V)
end

-- ChunkMesher loads lazily on the first job: its lib path needs the
-- job's fs root, which is only known once the pool has started.
local ChunkMesher = nil

-- -------------------------------------------------------------- loop

local cmdCh = love.thread.getChannel("pv_geom_cmd")
local outCh = love.thread.getChannel("pv_geom_out")

local function handleGeometry(cmd)
  root = cmd.root or ""
  if not ChunkMesher then ChunkMesher = V.require("ChunkMesher") end
  TileRenderer.voidFill = cmd.voidFill or "trees"
  local chunk, err = load(cmd.mapSrc, "@pv-job-map", "t")
  if not chunk then
    error("job map source did not compile: " .. tostring(err), 0)
  end
  local map = chunk()
  -- the engine Map class is not loaded in the worker; reattach the pure
  -- methods the geometry path uses (same implementations as src/world/Map.lua)
  for _, name in ipairs({ "tileAt", "blockAt", "cellTile", "inBounds",
                          "isWalkableCell", "isGrassCell", "isWaterCell" }) do
    map[name] = Map[name]
  end
  if cmd.tileImage then
    -- same pixel source the main thread scanned with
    Assets.imageData = function() return cmd.tileImage end
  else
    Assets.imageData = function() return nil end
  end
  local data = ChunkMesher.buildGeometryData(map, cmd.bodyOnly, cmd.masks)
  return { gen = cmd.gen, data = data }
end

while true do
  local cmd = cmdCh:pop()
  if cmd then
    if cmd.cmd == "quit" then break end
    if cmd.cmd == "geometry" then
      local ok, res = pcall(handleGeometry, cmd)
      if ok then
        outCh:push(res)
      else
        outCh:push({ gen = cmd.gen, error = tostring(res) })
      end
    end
  else
    love.timer.sleep(0.001)
  end
end
