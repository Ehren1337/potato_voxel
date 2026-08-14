-- The mod's settings surface: the schema the mod manager's page shows,
-- the row set for the VOXEL SETTINGS submenu, the OPTIONS rows hook that
-- replaces every PotatoVoxel row with one launcher, and the manager's
-- options_changed follow-up. main.lua owns the seams this surface hangs
-- off (the pipeline row itself, the hotkey); everything user-configurable
-- lives here. Kept out of the pipeline record on purpose -- these rows
-- parameterise the voxel pass and own no frame of it.
local V = ...

local QualityMode = V.require("QualityMode")
local VoxelGrid = V.require("VoxelGrid")
local WorldCurve = V.require("WorldCurve")
local Water = V.require("Water")
local ForestAtmos = V.require("ForestAtmos")
local OverworldBattle = V.require("OverworldBattle")
local DayNight = V.require("DayNight")
local AntiAlias = V.require("AntiAlias")
local VR = V.require("VR")
local ShadowSettings = V.require("ShadowSettings")
local Voxel = V.require("VoxelState")
local CachePrebuild = V.require("CachePrebuild")
local MeshCache = V.require("MeshCache")

local VoxelSettings = {}

-- Whether a fight can be staged on the map, as far as the OPTIONS menu is
-- concerned: the 3D-BTL row, and nothing else.
--
-- The row is the only thing that decides: OverworldBattle.begin and
-- wantsFront both gate on enabled() alone, so this predicate must not
-- second-guess them (a staged fight claimed by a preset the player had
-- turned off inside would pin BATTLE LAYOUT to OG for a fight that is
-- never staged).
--
-- Deliberately NOT gated on Voxel3D.available(): the engine offers a
-- pipeline's row whether or not the hardware can run it (Pipelines.rows), so
-- this mode's rows say ON on a machine without a depth buffer too, and a menu
-- that claims 3D battles are on must not also offer the layout they cannot be
-- drawn in.
local function stagedBattles()
  return OverworldBattle.enabled()
end

local SETTINGS = {
  { QualityMode.renderSetting,
    "Render the 3D scene at a fraction of the window resolution and fold "
    .. "it back up -- the single biggest frame-budget lever. Each quality "
    .. "mode (HIGH / MEDIUM / LOW / POTATO) sets this; moving it on its own "
    .. "switches the mode to CUSTOM." },
  { VoxelGrid.setting, "One-pixel wireframe along every voxel edge." },
  { WorldCurve.setting,
    "Bend the world down over the horizon, Animal Crossing style." },
  { Water.setting,
    "Reflections on water. FULL adds screen-space reflections of the "
    .. "shoreline, the trees and the buildings behind it; SKY is the sky, "
    .. "the sun and the moon alone, which is most of the look for a "
    .. "fraction of the cost." },
  { ForestAtmos.setting,
    "The air of the deep woods (Viridian Forest): a ground haze, and "
    .. "volumetric light let down through the unseen canopy overhead -- "
    .. "gold spears of sun by day, silver moon rays at night, pollen "
    .. "drifting through the beams and fireflies once they cool. LOW "
    .. "keeps the haze, halves the beam march and stands the particles "
    .. "down. On a phone the row offers LOW alone: the beams need a "
    .. "depth texture the pass can read back, and no mobile driver here "
    .. "grants one." },
  -- Off the OPTIONS menu while VR is on: the headset REQUIRES staged
  -- battles (OverworldBattle.enabled answers true regardless of this row)
  -- and forbids back sprites (backPinned answers false), so both rows
  -- decide nothing there and a dead switch on the menu reads as broken.
  { OverworldBattle.setting,
    "Fight in three dimensions, shot over the shoulder with a slow parallax "
    .. "drift. 2D-3D stands the game's own battle pics up as cards; STADIUM "
    .. "replaces them with the Pokemon Stadium battle models, animated, "
    .. "playing the animation the move being used actually calls for. A "
    .. "stages the fight on the MAP -- the nearest clear ground, in that "
    .. "place's own weather and light; B stands it on two discs against the "
    .. "sky instead, which works everywhere, including the caves and shop "
    .. "floors that have nowhere to stage a fight. The STADIUM rungs only "
    .. "appear once the models have been built, and building them needs a "
    .. "Pokemon Stadium (US) 1.0 ROM of your own -- place it at "
    .. "baseroms/baserom.z64 inside this mod and restart. No "
    .. "other version works: the reader is keyed to that one cartridge.",
    when = function() return not VR.enabled() end },
  -- Only offered while a fight can actually be staged on the map: with 3D-BTL
  -- off the engine draws the classic screen, which is this row's ON already,
  -- and a row that no longer decides anything is worse than no row.
  { OverworldBattle.backSetting,
    "Keep your own Pokemon on the battle menu, seen from behind in its "
    .. "original slot, instead of standing it on the map facing the foe. "
    .. "The foe is still out there on its own tile.",
    when = function() return stagedBattles() and not VR.enabled() end },
  -- Shows only while a fight can actually be staged, like BACK SPRITES
  -- above: the switch decides how a STAGED fight is drawn, so without a
  -- staged fight it decides nothing.
  { OverworldBattle.stadiumSetting,
    "Fight with the Pokemon Stadium battle models -- skinned and animated, "
    .. "playing the animation the move actually calls for -- instead of the "
    .. "flat battle pics. Needs the models built from your own Pokemon "
    .. "Stadium (US) 1.0 ROM placed at baseroms/baserom.z64 inside this "
    .. "mod; restart after adding it.",
    when = function() return stagedBattles() end },
  { DayNight.setting,
    "What time it is outdoors: pin the sky to DAY, NIGHT, DUSK or DAWN, "
    .. "let CYCLE run it -- ten minutes of sun, ten of moon, with the "
    .. "shadows, the sky and the light following -- or SYNC it to the "
    .. "clock on the wall, so Kanto's evening falls when yours does." },
  { AntiAlias.setting,
    "Smooth the stair-stepped edges of the 3D world -- roof ridges, ledge "
    .. "lips, a tree against the sky -- by rendering the diorama larger than "
    .. "the window and folding it back down. Every edge in the picture "
    .. "softens with them, the tileset's own texels included, so the diorama "
    .. "reads smoother rather than sharper. 2X costs half again as many "
    .. "pixels in each direction and 4X twice, which makes this the most "
    .. "expensive row in the mod." },
  { VR.setting,
    "PCVR through OpenXR (SteamVR, Oculus, WMR). The diorama becomes a "
    .. "tabletop model your head moves around; the first-person mode "
    .. "stands you inside the world at life size, looking where the "
    .. "headset looks. "
    .. "Menus and dialogs float on a panel. Needs a Windows OpenXR runtime "
    .. "and the mod running from a real folder; without them the row stays "
    .. "and the game stays flat, with the reason on the console.",
    -- on Windows the row stays even when a runtime is missing (the console
    -- says why); off Windows -- mobile above all -- there is no VR to have
    -- and the row does not exist
    when = function() return VR.supported() end },
  -- Under the VR row and only while it is ON: a comfort setting for a
  -- device that is not plugged in decides nothing, and this one is read
  -- exclusively by the headset's right stick.
  { VR.smoothTurn,
    "Turn smoothly with the right stick instead of snapping 45 degrees a "
    .. "flick. OFF by default, and deliberately: a software turn moves the "
    .. "world past a head that did not move, which is the most reliable way "
    .. "to make somebody ill in a headset. Turn it on if you have your sea "
    .. "legs and want the continuity.",
    when = function() return VR.enabled() end },
  { ShadowSettings.enabledSetting,
    "Cast real shadows across the diorama -- a shadow climbs a wall, drapes "
    .. "over a roof and slides across a passing NPC. OFF is the flat-lit "
    .. "model: no shadow map is drawn, no contact blobs sit under the "
    .. "characters, and nothing reads as pasted on -- there just is no sun." },
  { ShadowSettings.qualitySetting,
    "How fine a shadow map to spend on the pass, as the edge of the square "
    .. "map in texels. AUTO is what the pass already does -- the smallest "
    .. "size whose texel stays under a target slice of a world pixel, up to "
    .. "2048. A fixed rung forces the map's edge whatever the view: bigger "
    .. "maps resolve finer shadow edges and cost fill rate and RAM (2048 is "
    .. "a 16MB depth pass), which is the whole of why this is a row." },
}

-- The mod manager's page offers the same settings the VOXEL SETTINGS menu
-- does: every knob is configurable now, so the page is a real form rather
-- than the old empty card. The VR rows are the one omission -- they are
-- absent from the manager's page wherever the platform cannot do VR at all
-- (the OPTIONS menu's `when` gates are situational, a row hidden for now;
-- this one is existential). The VOXEL row still lives on the OPTIONS menu,
-- through the render-pipelines registry, as the quality ladder (OFF / HIGH
-- / MEDIUM / LOW / POTATO).
function VoxelSettings.schema()
  local schema = {}
  for _, entry in ipairs(SETTINGS) do
    local vrOnly = entry[1] == VR.setting or entry[1] == VR.smoothTurn
    if not vrOnly or VR.supported() then
      schema[#schema + 1] = entry[1]:schema(entry[2])
    end
  end
  return schema
end

-- ------- TILT and GBC FX are gone while this mod is installed
--
-- Both fight the diorama, and both were already half-taken: the mode's own
-- key (8) clears them on every press, and the registry switches TILT off
-- whenever a world pipeline takes the pass. What was left was two rows the
-- player could set and watch get reverted -- TILT is the flat fake of what
-- this mode does for real, and GBC FX is a full-screen present pass over the
-- top of the whole thing.
--
-- So they come OFF the menu, and are HELD at zero rather than merely dropped.
-- Hiding a live setting is a trap: a save written before the mod was installed
-- can carry TILT 3, and a row that is not there is a row that cannot turn it
-- back off. Pinned wherever the value could have arrived from -- the menu
-- opening, a save being loaded or begun -- so there is no route by which one
-- of them is on and unreachable.
--
-- Everything they did is still reachable: uninstall the mod and both rows are
-- back, at whatever they were last set to.
-- BATTLE BG rides the same reasoning, and comes off for a reason of its own.
-- The row picks what fills the screen AROUND the battle's 160x144 field --
-- WHITE paper, BLACK bars, or the frozen overworld dimmed behind it -- and
-- all three were answers to the same question: what to do with the voids,
-- given the battle is a small picture in the middle of a big window.
--
-- This mod answers that question differently and permanently. A staged fight
-- fills the whole window with the map the fight is standing on, and the
-- flat battle screen it composites over it is drawn on the mode's own
-- surface; there are no voids left for the row to fill. WORLD is the worst
-- of the three under it -- it makes the battle non-opaque so the engine
-- draws the overworld underneath, which is a SECOND copy of the world drawn
-- under the one the arena pass already put there, dimmed and at a different
-- camera. BLACK bars over a diorama read as a letterboxed screenshot.
--
-- So the value is pinned at WHITE, which is the one the mode was composed
-- against, and the row comes off the menu on the same reasoning as TILT and
-- GBC FX: a row that no longer decides anything is worse than no row.
-- Uninstall the mod and it is back, at whatever it was last set to.
function VoxelSettings.pinEngineFx(game)
  game = game or require("src.core.Game")
  local opts = game and game.save and game.save.options
  local Tilt = require("src.render.Tilt")
  local GBCFX = require("src.render.GBCFX")
  local changed = false
  if opts then
    changed = (opts.tilt or 0) ~= 0 or (opts.gbcfx or 0) ~= 0
                or (opts.battleBg or "white") ~= "white"
    opts.tilt, opts.gbcfx = 0, 0
    opts.battleBg = "white"
  end
  pcall(Tilt.setLevel, 0)
  pcall(GBCFX.setLevel, 0)
  if changed and game.writeOptions then pcall(game.writeOptions, game) end
end

-- One label for a READY cache, wherever it is shown: the CACHE STATUS row
-- and the status dialog both answer through this.
local function readyLabel(status)
  if status ~= "READY" then return status end
  local codec = MeshCache.codec()
  if codec then return ("READY (%s)"):format(codec:upper()) end
  local mode = MeshCache.compressionStatus()
  if mode == "mixed" then return "READY (MIXED)" end
  if mode == "raw" then return "READY (RAW)" end
  return "READY"
end

local function showCacheStatus(game)
  local TextBox = require("src.render.TextBox")
  local label = readyLabel(CachePrebuild.status())
  -- which backend created the cache dir, so a support report names the path
  local backend = MeshCache.dirBackend()
  local backendLabel = backend == "storage" and "MOD STORAGE"
      or "NONE"
  game.stack:push(TextBox.new(game,
    ("%s\fGEOMETRY %d\fDIR: %s"):format(label, MeshCache.GEOMETRY_VERSION,
                                          backendLabel)))
end

local function confirmCacheWipe(game)
  local _, _, running = CachePrebuild.progress()
  local TextBox = require("src.render.TextBox")
  if running then
    game.stack:push(TextBox.new(game, "CANCEL BUILD\nBEFORE WIPING."))
    return
  end
  game.stack:push(TextBox.new(game, "WIPE CACHE?", nil, {
    defaultNo = true,
    choice = function(yes)
      if yes then CachePrebuild.wipe(game) end
    end,
  }))
end

-- Both the post-load gate and the manual OPTIONS action enter the same
-- blocking screen.  Keeping the push beside the start call matters: a build
-- that is running with no screen leaves the settings row looking frozen at
-- BUILD 0/N and gives the player no cancel or failure path.
local function startCacheBuild(game)
  if not CachePrebuild.start(game) then return false end
  local Progress = V.require("CachePrebuildScreen")
  game.stack:push(Progress.new(game))
  return true
end

-- Build the complete PotatoVoxel-owned row set for the dedicated submenu.
function VoxelSettings.rows(game)
  local overworld = game and game.overworld
  local activeMap = overworld and overworld.map
  local inGameplay = type(activeMap) == "table" and activeMap.id ~= nil
  -- Cache management belongs to a restored playthrough. The title keeps the
  -- visual settings but does not bind, build, or wipe per-playthrough data.
  if inGameplay then CachePrebuild.refresh(game) end
  local Pipelines = require("src.render.Pipelines")
  local rows = {}
  for _, row in ipairs(Pipelines.rows(game)) do rows[#rows + 1] = row end
  -- Every setting row lives here. The potato tuning is the DEFAULT, not a
  -- lock, so each knob is a switchable row (WATER OFF/SKY/FULL, FOREST FX
  -- OFF/LOW/FULL, AA OFF/2X/4X, V-CURVE, V-GRID, 3D-BTL, BACK SPRITES,
  -- DAY/NIGHT, SHADOWS, SHADOW QUALITY). The only gates are the situational
  -- `when`s -- VR rows, and BACK SPRITES needing a staged fight -- so
  -- nothing a device can carry is hidden from it.
  for _, entry in ipairs(SETTINGS) do
    if not entry.when or entry.when() then
      rows[#rows + 1] = entry[1]:row()
    end
  end
  local okPick, importRow = pcall(function()
    return V.require("StadiumRomPick").row()
  end)
  if okPick and importRow then rows[#rows + 1] = importRow end
  if inGameplay then
    rows[#rows + 1] = {
      id = "potato_voxel:prebuild",
      label = "PREBUILD CACHE",
      value = function() return CachePrebuild.status() end,
      activate = function(g)
        local status = CachePrebuild.status()
        local _, _, running = CachePrebuild.progress()
        local decision = CachePrebuild.activationDecision(status, running)
        if decision == "cancel" then CachePrebuild.cancel()
        elseif decision == "start" then startCacheBuild(g)
        elseif decision == "confirm_rebuild" then
          local TextBox = require("src.render.TextBox")
          local ChoiceBox = require("src.ui.ChoiceBox")
          g.stack:push(TextBox.new(g, "REBUILD CACHE?", function()
            g.stack:push(ChoiceBox.new(g, function(yes)
              if yes then startCacheBuild(g) end
            end, { defaultNo = true }))
          end))
        end
      end,
    }
    rows[#rows + 1] = {
      id = "potato_voxel:cache_status",
      label = "CACHE STATUS",
      value = function()
        local status = CachePrebuild.status()
        return status == "READY"
               and readyLabel(status)
               or ("GEO %d"):format(MeshCache.GEOMETRY_VERSION)
      end,
      activate = showCacheStatus,
    }
    rows[#rows + 1] = {
      id = "potato_voxel:wipe_cache",
      label = "WIPE CACHE",
      value = function() return "DELETE" end,
      activate = confirmCacheWipe,
    }
  end
  return rows
end

-- Rows that no longer decide anything are taken off rather than left to be
-- changed to no effect. A row that no longer decides anything is worse
-- than no row.
local function dropRow(out, id)
  for i = #out, 1, -1 do
    if type(out[i]) == "table" and out[i].id == id then table.remove(out, i) end
  end
  return out
end

function VoxelSettings.install()
  local mod = V.mod
  mod.options:define(VoxelSettings.schema())

  -- Keep engine OPTIONS focused: one launcher replaces every PotatoVoxel
  -- row -- the pipeline's own VOXEL row and every potato_voxel:* setting
  -- row -- with a single VOXEL SETTINGS row that opens the submenu.
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    VoxelSettings.pinEngineFx(game)
    dropRow(out, "tilt")
    dropRow(out, "gbcfx")
    dropRow(out, "battleBg")
    if stagedBattles() then
      OverworldBattle.forceOG(game)
      dropRow(out, "battleLayout")
    end
    for i = #out, 1, -1 do
      local id = type(out[i]) == "table" and out[i].id or ""
      id = id or ""
      if id == "pipeline:voxel"
         or id:find("^potato_voxel:") then table.remove(out, i) end
    end
    out[#out + 1] = {
      id = "potato_voxel:settings", label = "VOXEL SETTINGS",
      value = function() return "OPEN" end,
      activate = function(g)
        require("src.ui.Screens").push(g, "PotatoVoxelSettings")
      end,
    }
    return out
  end)

  mod.content.screens:register("PotatoVoxelSettings", {
    new = function(game)
      return V.require("VoxelSettingsMenu").new(game, VoxelSettings.rows)
    end,
  })

  -- The mod manager writes and persists on its own, so the only thing left
  -- to do is move our cached index and pick the new value up.
  mod.events:on("mod.options_changed", function(payload)
    if not (payload and payload.mod == mod.id) then return end
    for _, entry in ipairs(SETTINGS) do
      if payload.key == entry[1].key then entry[1]:sync(payload.value) end
    end
    -- 3D-BTL switched on from the manager's page pins BATTLE LAYOUT exactly as
    -- the OPTIONS row does. The manager persists its own value; this is the one
    -- that has to follow it.
    if stagedBattles() then OverworldBattle.forceOG() end
    -- and DAYTIME changed from the manager's page while HIGH owns it snaps
    -- straight back to SYNC -- the manager's row is not hidden, so the pin
    -- must hold against it too
    local Pipelines = require("src.render.Pipelines")
    if Voxel.isFull(Pipelines.level("voxel")) then DayNight.forceSync() end
  end)
end

return VoxelSettings
