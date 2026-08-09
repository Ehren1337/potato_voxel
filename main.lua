-- PotatoVoxel (fork of Dramatic Shape Voxel Mod): a full 3D diorama
-- overworld, shipped as a rendering pipeline mod.
--
-- The engine's render_pipelines registry (src/mods/Schemas.lua) lets a mod
-- own part of the frame.  This mod registers two:
--
--   voxel      a drawWorld pipeline.  Instead of the flat tile blit, the
--              overworld's terrain is extruded into real geometry, walked
--              by a depth-buffered 3D camera, with characters as leaning
--              sprite slabs and a shadow map throwing real cast shadows
--              across whatever they land on.  Occlusion is the depth
--              buffer, not a y-sort: walk behind a building and the
--              building is simply in front.
--
--   tiltshift  a worldPresent pipeline -- the stage that post-processes
--              the finished world BEFORE the UI composites over it.  A
--              tilt-shift blur that sells the miniature-model look, on the
--              diorama only, leaving text boxes and menus crisp.
--
-- Everything a display mode needs beyond the two draw functions -- the
-- OFF/15/35/50 ladder, the options rows, the hotkeys, persistence in
-- save.options.pipelines, the free-roam gate, the mutual exclusion with
-- the engine's TILT mode -- is engine plumbing driven by the records
-- below.  This file declares; lib/ draws.
--
-- Voxel mode is presentational: it changes what the world LOOKS like and
-- nothing about what it IS.  TWO rungs are the deliberate exception. 1ST
-- (the camera in the player's own eyes) and 3RD (the same rig, boomed back
-- behind their shoulder) replace the grid WALK with a free,
-- camera-relative one while either is selected (lib/FreeMove.lua), because
-- a camera you can steer with a mouse demands feet that go where it looks.
-- Even there the game is untouched: the walk asks the engine's own
-- collision the same questions a grid step asks, keeps the player's
-- logical cell synced, and fires the engine's own landing pipeline per
-- cell crossed -- warps, encounters, ledges, gates and scripts all run
-- exactly as themselves. Step off the rung and the grid walk is back.

local mod = ...

-- ------- the mod namespace
--
-- lib/ modules require each other through V rather than package.path: a
-- mod directory is not on it, and may live inside a mounted .love archive
-- that plain require cannot reach.  Each module is loaded once, with V
-- passed in as its vararg (`local V = ...`).

local V = { mod = mod, path = mod.path }

local function chunkFor(rel)
  local source = mod:read(rel)
  if not source then
    error(("potato_voxel: %s is missing -- reinstall the mod"):format(rel), 0)
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
  if not chunk then
    error(("potato_voxel: %s did not compile: %s"):format(rel, tostring(err)), 0)
  end
  return chunk
end

local modules = {}
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local value = chunkFor("lib/" .. name .. ".lua")(V)
  modules[name] = value
  return value
end

local dataFiles = {}
function V.data(name)
  local hit = dataFiles[name]
  if hit ~= nil then return hit end
  local value = chunkFor("data/" .. name .. ".lua")(V)
  dataFiles[name] = value
  return value
end

-- ------- pipelines

local Voxel = V.require("VoxelState")
local Voxel3D = V.require("Voxel3D")
local VoxelScene = V.require("VoxelScene")
local ChunkMesher = V.require("ChunkMesher")
local VoxelGrid = V.require("VoxelGrid")
local WorldCurve = V.require("WorldCurve")
local DayNight = V.require("DayNight")
local DayTint = V.require("DayTint")
local Water = V.require("Water")
local ForestAtmos = V.require("ForestAtmos")
local Upscale = V.require("Upscale")
local FirstPerson = V.require("FirstPerson")
local FreeMove = V.require("FreeMove")
local CamControl = V.require("CamControl")
-- HORDE MODE: the konami code's minigame. Horde owns the state machine and
-- every hook; the other four are the gun, the crowd, the readout and the
-- chip-synthesized sounds it fires. See lib/Horde.lua for the whole design.
local Horde = V.require("Horde")
local HordeGun = V.require("HordeGun")
local HordeHud = V.require("HordeHud")
local CachePrebuild = V.require("CachePrebuild")
local HordeSfx = V.require("HordeSfx")

-- The low-end runtime tuner (lib/BrickProfile.lua): the TrimUI Brick
-- tuning this fork ships with, applied on every platform. Loaded on
-- every platform so the rest of this file can ask isBrick() freely; it
-- no-ops everywhere except Linux (the Brick). Its apply() must run before
-- the pipeline registrations below -- the voxel pipeline and the rows hook
-- capture the ladders by reference, and apply mutates those tables in
-- place.
local BrickProfile = V.require("BrickProfile")
BrickProfile.apply(V)

-- Forward declaration: the voxel pipeline's update hook (registered below)
-- calls this, and it is defined further down with the settings it drives.
-- Declared rather than left global -- a mod writing to _G would leak into
-- every other mod's namespace.
local applyFull

-- The last VOID FILL the terrain was meshed under; see the update hook.
-- The scene canvas's size, in FRAMEBUFFER PIXELS.
--
-- `ctx.width/height` are the window measured in LOVE UNITS
-- (love.graphics.getDimensions), but the engine composites a pipeline's
-- returned canvas with `draw(canvas, 0, 0, 0, 1/dpiX, 1/dpiY)` -- a scale
-- that only covers the window when the canvas is at PIXEL resolution.
-- Sizing it in units costs the DPI scale TWICE: the canvas is that much
-- smaller, then it is drawn that much smaller again, so the diorama lands
-- in the top-left corner at 1/dpi of the screen.  Desktop never sees it --
-- units and pixels are the same thing there -- but on Android the DPI scale
-- is the display density (2.625 on a 420dpi panel), and the world came out
-- a third of the size in each direction.
--
-- So ask for the pixel dimensions rather than trusting the ctx.  That is
-- the number a fixed engine would hand over, so this keeps working either
-- way instead of double-correcting.  It also squares the FX pass: ctx.scale
-- is ALREADY in pixels per world pixel (Zoom.scale over Renderer:fitScale,
-- which measures the drawable), so the closures ctx.drawFx runs were being
-- scaled for a canvas 2.6x bigger than the one they drew into.
local function sceneSize(ctx)
  if love.graphics and love.graphics.getPixelDimensions then
    local pw, ph = love.graphics.getPixelDimensions()
    if pw and ph and pw > 0 and ph > 0 then return pw, ph end
  end
  return ctx.width, ctx.height
end

local voidFill = { last = nil }
function voidFill.check()
  local TileRenderer = require("src.render.TileRenderer")
  local now = TileRenderer.voidFill
  if voidFill.last ~= nil and now ~= voidFill.last then
    ChunkMesher.invalidate()   -- no map id: every ring on every map is stale
  end
  voidFill.last = now
end

mod.content.render_pipelines:register("voxel", {
  label = "VOXEL",
  levels = Voxel.ANGLE_LABELS,
  -- 3 is the engine's TILT key, which this mode supersedes -- see the
  -- hotkey block near the bottom of this file for how it is claimed
  hotkey = "8",
  -- above tiltshift, so the two sort together in the options list with the
  -- mode first and its post-process under it
  priority = 20,

  -- Headless runs and drivers without a depth canvas or shader support
  -- answer false here, and the engine keeps the vanilla 2D path -- which
  -- is why no caller ever has to guard for a missing 3D pass.
  available = function()
    return Voxel3D.available()
  end,

  -- the engine hands over the live level; we ease the camera toward it.
  -- pump() advances queued mesh builds inside a few-millisecond budget,
  -- so entering voxel mode (and streaming neighbours while walking)
  -- costs frames nothing visible -- the old synchronous build froze the
  -- first frame for seconds. prefetch() runs here as well as in the
  -- draw, because update ticks even while a warp's Transition covers
  -- the screen: the destination's meshes start building the moment the
  -- map swaps behind the fade, and the fade-covered frames get a wider
  -- pump slice -- so stepping out of a door lands on terrain that is
  -- already there instead of a flat flash.
  update = function(dt, level)
    -- FULL is a preset, so it is applied ON THE PRESS rather than held every
    -- frame: it SETS the other rows and then leaves them alone. Holding them
    -- would make the zoom keys and the wheel dead while the mode was on, and
    -- would fight anyone who changed one deliberately.
    applyFull(level)
    Voxel.update(dt, level)
    -- the first-person head, on the same tick: its blend in and out of the
    -- orbit, the mouse capture lifecycle, and the frame's stick-rate look.
    -- Unconditional like Voxel.update, because the blend has to keep easing
    -- OUT after the rung is left
    FirstPerson.update(dt)
    -- the day/night clock, on the same always-running tick: Pipelines.update
    -- runs whatever the level, so time passes with the mode off, through
    -- battles and menus, and a CYCLE evening falls mid-fight exactly as it
    -- would mid-walk
    DayNight.update(dt)
    -- the atmosphere's own clock (shaft shimmer, drifting motes), on the
    -- same tick so the beams keep breathing through a dialog box
    ForestAtmos.update(dt)
    -- The horde, on the same always-running tick and for the same reason:
    -- it owns no pass of the frame, it is a MODE over the overworld, and
    -- it has to keep thinking while a warp's wipe covers the screen (the
    -- crowd follows the player through the door) and under the GAME OVER
    -- card, which is a pushed state that stops everything below it.
    Horde.update(dt)
    -- VOID FILL picks the block the border ring is made of, and in this
    -- mode that ring is BAKED INTO THE MESH rather than drawn each frame.
    -- So the option has to reach the cache or nothing happens on screen
    -- until the meshes are dropped for some other reason -- which reads
    -- exactly like the option doing nothing at all. Polled rather than
    -- hooked because the engine changes it from three places (the options
    -- row, applyOptions on load, TileRenderer.setVoidFill) and none of
    -- them announces it. Ahead of the active() gate, so switching it
    -- while voxel mode is OFF still invalidates what is cached.
    voidFill.check()
    -- The cache prebuilder is deliberately independent of the active display
    -- mode: an Options-menu press must keep progressing while VOXEL is OFF.
    CachePrebuild.update()
    if not Voxel.active() then return end
    local Game = require("src.core.Game")
    local ow = Game and Game.overworld
    if ow and ow.map and ow.camera then
      pcall(VoxelScene.prefetch, ow)
    end
    ChunkMesher.pump(Game and Game.stack
                     and Game.stack:top() ~= ow)
  end,

  drawWorld = function(ctx)
    -- Terrain and characters are geometry; the field FX stay ordinary 2D
    -- draws composited on top, anchored through the same camera the 3D
    -- pass used (ctx.drawFx below).  The scene renders at the window's
    -- PIXEL resolution (see sceneSize) so the 3D pass is crisp rather than
    -- a magnified low-res image, while the FX closures keep drawing in
    -- world-pixel units.
    local sw, sh = sceneSize(ctx)
    local rs = BrickProfile.renderScale(Voxel.level)
    local crw = math.max(1, math.floor(sw * rs + 0.5))
    local crh = math.max(1, math.floor(sh * rs + 0.5))
    local canvas = VoxelScene.render(ctx.state, crw, crh,
                                      ctx.vw, ctx.vh, ctx.paletteFor)
    if not canvas then return nil end   -- fall back to the 2D path
    if Voxel3D.beginOverlay() then
      -- the FX closures are ordinary 2D draws sized in DISPLAY pixels, and
      -- they are drawing into the supersampled canvas alongside everything
      -- else -- so the scale goes up with it, or the "!" bubble lands the
      -- right place at half the size.  project() already answers in canvas
      -- pixels, so only the scale needs saying.
      ctx.drawFx(function(wx, wy) return Voxel3D.project(wx, 0, wy) end,
                 ctx.scale * rs)
      -- the horde's readout rides the same overlay, over the FX: health,
      -- ammunition, the crosshair and the banners, sized in the same
      -- supersampled canvas pixels everything else here is drawn in. A
      -- headset never reaches this line (drawWorld returns the mirror
      -- above) -- lib/VR draws the same HUD onto each eye instead.
      HordeHud.drawFlat(crw, crh, ctx.scale * rs)
      Voxel3D.endOverlay()
    end
    return Upscale.apply(canvas, sw, sh, "world")
  end,

  invalidate = function()
    Voxel3D.invalidate()
    Upscale.invalidate()
    ChunkMesher.invalidate()   -- no map id = every cached mesh
    ForestAtmos.invalidate()   -- shaft/particle meshes and shader sentinels
  end,
})

-- A missing pipeline entry is a new-install/default case. Seed MEDIUM before
-- Game:applyOptions runs for a new save, and update the live level when a
-- loaded save receives the same migration. Never touch an existing value.
local function ensureBrickVoxelDefault(event)
  local save = event and event.save
  local options = save and save.options
  if BrickProfile.ensureVoxelDefault(options) then
    require("src.render.Pipelines").setLevel("voxel", BrickProfile.DESKTOP_MEDIUM_LEVEL)
  end
end
mod.events:on("save.created", ensureBrickVoxelDefault)
mod.events:on("save.loaded", ensureBrickVoxelDefault)

-- ------- this mod's own settings
--
-- Neither of these is a pipeline: they own no pass of the frame, they
-- PARAMETERISE the voxel one, so they have nothing to put in drawWorld or
-- present and the registry would rightly reject them.  Plain mod settings
-- instead -- see ModSetting for where they persist and how the two rows
-- each ends up on stay in step.

-- The Brick profile uses one fixed diorama framing for every active quality rung.
local fullWas = nil
applyFull = function(level)
  local active = level > 0
  if active == fullWas then return end
  fullWas = active
  if not active then return end
  local Game = require("src.core.Game")
  local opts = Game.save and Game.save.options
  if opts and opts.zoom ~= 0 then
    opts.zoom = 0
    require("src.render.Zoom").applyOptions(opts)
    if Game.writeOptions then pcall(Game.writeOptions, Game) end
  end
end

local SETTINGS = {
  { VoxelGrid.setting, "One-pixel wireframe along every voxel edge." },
  { WorldCurve.setting, "Bend the world down over the horizon." },
  { Water.setting, "Reflections on water." },
  { ForestAtmos.setting, "Forest atmosphere effects." },
  { DayNight.setting, "What time it is outdoors." },
}
local schema = {}
for _, entry in ipairs(SETTINGS) do schema[#schema + 1] = entry[1]:schema(entry[2]) end
mod.options:define(schema)

-- The Brick quality ladder is the only display hotkey owned by this mod.
local HOTKEYS = { ["8"] = "pipeline", ["lshift"] = "pipeline", ["rshift"] = "pipeline" }

local function cycleVoxel(game)
  local Pipelines = require("src.render.Pipelines")
  local top = game.stack and game.stack:top()
  if not Pipelines.canToggle("voxel", top, game.overworld) then return false end
  Pipelines.setLevel("voxel", Voxel.nextHotkeyLevel(Pipelines.level("voxel")))
  Pipelines.syncOptions(game.save.options)
  game.save.options.tilt = 0
  game.save.options.gbcfx = 0
  require("src.render.GBCFX").setLevel(0)
  require("src.render.Tilt").setLevel(0)
  game:writeOptions()
  return true
end

do
  local Game = require("src.core.Game")
  local inner = Game.keypressed
  function Game:keypressed(key)
    if key == "q" or key == "e" then
      local top = self.stack and self.stack:top()
      if not (top and top.onKeyPressed) and CamControl.zoomBy(key == "q" and 1 or -1) then return end
    end
    if HOTKEYS[key] and not (self.stack and self.stack:top() and self.stack:top().onKeyPressed) then
      if cycleVoxel(self) then return end
    end
    return inner(self, key)
  end
end

mod.hooks:wrap("ui.options.rows", function(nextFn, game, rows)
  local out = nextFn(game, rows)
  if type(out) ~= "table" then return out end
  local anchor = nil
  for i, row in ipairs(out) do
    if type(row) == "table" and row.id == "pipeline:voxel" then anchor = i end
  end
  local prebuild = {
    id = "potato_voxel:prebuild", label = CachePrebuild.isAndroid() and "PREBUILD / CANCEL" or "PREBUILD MAP CACHE",
    value = function() return CachePrebuild.status() end,
    activate = function(g)
      local status = CachePrebuild.status()
      local _, _, running = CachePrebuild.progress()
      local decision = CachePrebuild.activationDecision(status, running)
      if decision == "cancel" then CachePrebuild.cancel()
      elseif decision == "start" then CachePrebuild.start(g) end
    end,
  }
  table.insert(out, (anchor or #out) + 1, prebuild)
  return out
end)

-- ------- keeping the geometry in step with the world
--
-- Terrain meshes are derived from a map's block layer, so anything that
-- rewrites a block (a cut tree, a smashed rock, a script's replaceBlock)
-- has to drop that map's cached mesh or the 3D world keeps showing the
-- tree that is no longer there.  The 2D tile renderer invalidates its own
-- caches off the same edit.

-- refresh, not invalidate: the stale mesh keeps drawing while the
-- replacement builds in the background, so a one-block edit (Cut, a
-- door stamp, the tree regrowing on re-entry) repopulates in place
-- instead of blinking the whole scene down to the flat 2D path
mod.events:on("world.block_replaced", function(payload)
  local mapId = payload and (payload.mapId or (payload.map and payload.map.id))
  if mapId then ChunkMesher.refresh(mapId) end
end)

-- The event above is the ANNOUNCED edit -- OverworldState:replaceBlock
-- emits it, which is the path Victory Road's barriers and a script's
-- replaceBlock take. Several edits do not go through it:
--
--   Cut          swaps the tree block and rebuilds the 2D renderer
--   the regrowth restores those blocks when the map is re-entered
--   card-key doors are stamped closed on floor load
--
-- all of them writing the block layer directly. Meshes derived from that
-- layer went stale with no announcement -- the cut tree stayed standing,
-- and after a round trip through a door the stump stayed cut because this
-- map's mesh survives in the cache (that is what prevLive is for).
--
-- The engine could announce each of those, and an earlier cut of this
-- work changed it to. That is the wrong place: it edits the game for one
-- mod's benefit, and every future path that writes a block has to
-- remember to do the same. They all funnel through ONE choke point --
-- Map:setBlock -- so wrap that from here instead. Map is a plain
-- metatable shared by every map instance, so this covers all of them,
-- including paths written after this mod.
--
-- Read back rather than trust the argument: setBlock silently ignores an
-- out-of-bounds write, and a stamp that rewrites a block with the value
-- it already held (the door code guards for this, the regrowth does not)
-- is not a change and must not throw the mesh away.
do
  local Map = require("src.world.Map")
  if not Map.dramaticShapeBlockHook then
    local setBlock = Map.setBlock
    Map.setBlock = function(self, bx, by, block)
      local before = self:blockAt(bx, by)
      setBlock(self, bx, by, block)
      if self.id and self:blockAt(bx, by) ~= before then
        ChunkMesher.refresh(self.id)
      end
    end
    Map.dramaticShapeBlockHook = true
  end
end

-- A reloaded map is rebuilt from scratch (warps that re-enter the same map,
-- hot reload), so its mesh is stale for the same reason -- with one
-- exception, and it is the common one.
--
-- A palette switch reloads the map ONLY to rebuild its atlas
-- (PaletteFX.setMode -> reloadMap(id, "colors")). The geometry that comes
-- back is identical: this mesher reads block layout and tile ids and never
-- reads colour, and the palette lives entirely in the texture TerrainAtlas
-- hands back per frame -- which is keyed BY palette, so the new colours are
-- already built by the time the next frame draws.
--
-- Dropping the mesh anyway cost a visible flash of the flat 2D world on
-- every palette toggle. Mesh builds are asynchronous, so the frames between
-- the drop and the first finished mesh have no terrain to draw, and
-- drawWorld returning nil IS the 2D fallback. Keeping the geometry lets the
-- new colours land on the diorama already on screen, in one frame, which is
-- what a palette toggle should look like from inside voxel mode.
mod.events:on("map.reloaded", function(payload)
  if payload and payload.reason == "colors" then return end
  local mapId = payload and (payload.mapId or (payload.map and payload.map.id))
  if mapId then ChunkMesher.invalidate(mapId) end
  -- the atmosphere's layout stands on the same carved stamps the meshes
  -- do, so it goes stale on exactly the same event
  if mapId then ForestAtmos.invalidate(mapId) end
end)

-- ------- the free-roam rungs' inputs and their walk
--
-- 1ST and 3RD need two things no other rung does, and each is a named seam.
-- Both rungs are one rig -- the boom behind the shoulder is a number inside
-- it (lib/ThirdPerson.lua) -- so both are installed by the same two calls:
--
-- FirstPerson.install claims the LOOK inputs the engine ignores: the right
-- stick's axes (Game:gamepadaxis passes them to Input, which returns early
-- on anything but the left pair), relative mouse motion (love.mousemoved --
-- there is no Game handler to wrap; the engine's own callback only feeds
-- the mouse-as-touch debug path, which stays untouched), the mouse buttons
-- while the cursor is captured (A and B -- there is no cursor to click UI
-- with), and any touch that lands off the overlay's controls (a drag on
-- open screen is the look; the d-pad and buttons still go to
-- TouchControls, whose own d-pad finger is also read back analog as the
-- move vector). Every wrap forwards whatever it does not claim, and claims
-- only while one of the two rungs is actually driving.
--
-- FreeMove.install wraps OverworldState:handleInput -- the one choke point
-- where the grid walk reads the pad, and the same seam the engine's own
-- Cycling Road pull lives behind. While either drives, the walk is continuous
-- and camera-relative; the player's logical cell stays synced and every
-- per-cell consequence still runs through the engine's own machinery
-- (onStepComplete, checkEdgeExit, checkLedgeHop, checkBoulderPush). The
-- file argues the whole arrangement.
FirstPerson.install()
FreeMove.install()

-- ------- the zooms, and the battle camera the player can steer
--
-- CamControl claims the wheel, Q/E, the mouse and the touch screen for
-- whichever camera is actually in front of the player -- the staged
-- battle's, the third-person boom, or the engine's own survey zoom -- and
-- forwards everything else. Installed AFTER the two above deliberately: a
-- wrap installed later is the OUTER one, so a fight gets first refusal on
-- the mouse and the fingers, which is right, because while one is staged
-- the free-roam look is not driving.
CamControl.install()

-- ------- the konami code, and everything it turns on
--
-- Installed last of the input seams so its handleInput reasoning sits
-- outside FreeMove's and SELECT's. The detector itself does not live on
-- handleInput at all -- it reads the fixed step's own press queue, which
-- is where keyboard, pad, touch and the VR controllers have all already
-- become the same eight buttons. See lib/Horde.lua.
Horde.install()

-- ------- and the hour on the flat world
--
-- The clock reaches the diorama through the voxel shader's own tint uniform,
-- which the 2D tile path never runs -- so with the mode off, the same evening
-- that fell on the diorama left the flat world at permanent noon. One clock,
-- two worlds, one of them ignoring it. DayTint paints the same multiply over
-- the composited flat world, between the world blit and the UI blit; the
-- reasoning for that exact instant is in the file.
DayTint.install()

-- ------- what time it is
--
-- The cycle's clock rides the SAVE SLOT (save.modData, via mod.save): what
-- time it is in Kanto is a fact about that journey, like where the player is
-- standing. Written on the engine's save.writing event -- the moment before
-- the bytes hit disk -- and read back whenever a save is opened or begun. A
-- save with no clock in it starts at day; that is DayNight.restore's
-- fallback, and also the DAYTIME row's own default.
mod.events:on("save.writing", function()
  DayNight.store()
end)

mod.events:on("save.loaded", function()
  DayNight.restore()
end)

mod.events:on("save.created", function()
  DayNight.restore()
end)

-- The engine's own time-of-day seam. OverworldState:timeOfDay() is an
-- eternal "DAY" until a mod answers here; answering it hands the period to
-- the map.palette hook (ctx.tod) and music.select, so a palette or music
-- pack keyed to night works with this mod's clock for free. next() first: a
-- mod loaded before this one that already moved the time keeps its answer.
mod.hooks:wrap("world.tod", function(next, tod, ctx)
  local out = next(tod, ctx)
  if out ~= tod then return out end
  return DayNight.tod()
end)

mod.exports.version = "1.6.2-brick.17"
-- exposed so a companion mod can pin its own tiles' shapes or read the
-- camera without reaching into this mod's file layout
mod.exports.lib = V
-- the Brick tuner, exposed so tests and tooling can probe isBrick() and
-- the pinned ladders without a device
mod.exports.brick = BrickProfile
