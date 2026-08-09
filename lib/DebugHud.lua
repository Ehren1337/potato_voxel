-- Voxel world mode: the realtime diagnostics panel.
--
-- A DEBUG OFF/ON row on the OPTIONS menu. ON arms the same instrumentation
-- the benchmark driver uses (the Perf.wrap spans over Structures.forMap,
-- Buildings.build, ChunkMesher.pump and VoxelScene.render, plus the
-- once-per-rendered-frame stamp) and draws a live panel over the finished
-- frame: whole-frame stats (n, avg, p50, p95, p99, worst, the >16.7ms and
-- >33.3ms hitch counts -- the exact numbers the bench report prints) and
-- the four mesh-build spans, so a player can watch what the fork is
-- spending its frame budget on without a driver.
--
-- OFF is the default and the off path is free: with the row off, arm()
-- never runs, the render.hud wrapper returns before touching love.graphics
-- state, and nothing is wrapped or stamped. The panel is instrumentation
-- for the player, not a feature that plays itself.
--
-- When DS_PERF is already set (a benchmark run), the driver owns the
-- instrumentation -- it wraps the same four functions and stamps the frame
-- itself. DebugHud detects that (Perf.enabled is true at load) and only
-- DRAWS, never double-wraps or double-stamps, so a driver run with the row
-- on stays clean.

local V = ...

local ModSetting = V.require("ModSetting")

local DebugHud = {}

-- the key under options.modOptions.DRAMATIC_SHAPE, shared by the row in
-- OPTIONS (the mod manager's page does not carry it: it is a viewer, not
-- a knob, and the Brick's schema is deliberately empty)
DebugHud.KEY = "debug"
DebugHud.LABEL = "DEBUG"

DebugHud.setting = ModSetting.new(DebugHud.KEY, DebugHud.LABEL,
                                  { false, true }, { "OFF", "ON" })

function DebugHud.enabled()
  return DebugHud.setting:get() and true or false
end

function DebugHud.sync(value)
  DebugHud.setting:sync(value and true or false)
end

function DebugHud.row()
  return DebugHud.setting:row()
end

-- ------- instrumentation

local armed = false
-- true when THIS module was the one to switch Perf on (DS_PERF was not
-- set). Only the owner stamps frames and calls drawStats, so a driver run
-- with the row on never double-counts.
local ownsPerf = false

function DebugHud.owns()
  return ownsPerf
end

-- Install the measurement once, the first frame the row is on. A session
-- that toggles OFF and back ON keeps the same wraps (Perf's own enabled
-- gate makes a wrapped function a pass-through while the row is off).
function DebugHud.arm()
  if armed then return end
  armed = true
  local Perf = V.require("Perf")
  if Perf.enabled then return end   -- the driver owns it; draw only
  Perf.enabled = true
  ownsPerf = true
  -- the same spans the bench driver wraps, with the same labels, so a
  -- panel read and a bench report talk about the same numbers
  Perf.wrap(V.require("Structures"), "forMap", "Structures.forMap")
  Perf.wrap(V.require("Buildings"), "build", "Buildings.build")
  Perf.wrap(V.require("ChunkMesher"), "pump", "ChunkMesher.pump")
  Perf.wrap(V.require("VoxelScene"), "render", "VoxelScene.render")
end

-- Called every frame from the render.hud hook, which runs once per
-- rendered frame at the end of Game:draw -- exactly where Perf.frame()
-- belongs. Stamps only when we own the instrumentation.
function DebugHud.frameHook()
  local on = DebugHud.enabled()
  local Perf = V.require("Perf")
  if on then
    DebugHud.arm()
    if ownsPerf then
      Perf.enabled = true          -- re-affirm (a previous OFF cleared it)
      Perf.frame()
      Perf.drawStats()
    end
  elseif ownsPerf then
    Perf.enabled = false           -- nothing measured while the row is off
  end
end

-- ------- the panel

-- The lines the panel draws, pure and testable: frame stats from the ring
-- plus the four mesh-build spans. Each line is kept inside the 17-glyph
-- width of a 20-tile Font.drawBox interior (see the 3x3 rule).
function DebugHud.statsLines()
  local Perf = V.require("Perf")
  local f = Perf.frameStats()
  local lines = {
    ("FRAME %d %.2fms"):format(f.n, f.avg),
    ("p50 %.1f p95 %.1f"):format(f.p50, f.p95),
    ("p99 %.1f wrst %.1f"):format(f.p99, f.worst),
    (">16.7 %d >33.3 %d"):format(f.over16, f.over33),
  }
  local spans = {
    "Structures.forMap", "Buildings.build",
    "ChunkMesher.pump", "VoxelScene.render",
  }
  for _, lbl in ipairs(spans) do
    local s = Perf.labels[lbl]
    if s and s.n and s.n > 0 then
      local name = lbl:match("^.*%.(.*)$") or lbl
      lines[#lines + 1] = ("%s n=%d %.1fms"):format(name, s.n, s.total * 1000)
    end
  end
  local c = Perf.counters
  lines[#lines + 1] = ("draws %d shad %d"):format(c["stat.drawcalls"] or 0,
                                                  c["stat.shaderswitches"] or 0)
  if Perf.texturememory then
    lines[#lines + 1] = ("tex %dMB"):format(math.floor(Perf.texturememory / 1048576))
  end
  -- identity lines: the version as loaded from the installed manifest and
  -- the active canvas-fold mode -- the on-screen proof of which build is running
  local version, upKind = "?", "?"
  pcall(function()
    local ok, body = love.filesystem.read("manifest.json")
    if ok and body then
      version = body:match('"version"%s*:%s*"([^"]+)"') or "?"
    end
    upKind = V.require("Upscale").kind() or "?"
  end)
  lines[#lines + 1] = ("PotatoVoxel %s"):format(version)
  lines[#lines + 1] = (("canvas fold %s"):format(upKind))
  return lines
end

-- Screen-space panel: white box, black glyphs -- the only idiom that
-- survives the palette pass (black-on-white; white-on-black draws the box
-- and loses the letters). Drawn through the render.hud hook, which fires
-- after the composite, so the panel sits on top of the finished frame.
-- Guarded end to end: headless stubs and shader-less drivers must be able
-- to load and run with the row on. A missing viewport (another mod's
-- endFrame wrap swallowing it) falls back to the window's own size rather
-- than silently drawing nothing.
function DebugHud.draw(viewport)
  local g = love and love.graphics
  if not (g and g.push and g.origin and g.translate and g.scale and g.pop) then
    return
  end
  if not DebugHud.enabled() then return end
  local ok, Font = pcall(require, "src.render.Font")
  if not ok or not Font then return end
  local lines = DebugHud.statsLines()
  g.push("all")
  g.origin()
  local gw = viewport and viewport.gameWidth
  local gx = viewport and viewport.gameX
  local gy = viewport and viewport.gameY
  if not gw or gw <= 0 then
    local w, h = g.getDimensions()
    gw, gx, gy = w, 0, 0
  end
  g.translate(gx or 0, gy or 0)
  g.scale(gw / 160)
  -- interior is (tw-2)x(th-2): 18 glyphs wide, one more row than lines
  Font.drawBox(0, 0, 20, #lines + 5)
  g.setColor(0, 0, 0, 1)
  for i, line in ipairs(lines) do
    Font.draw(line, 8, 8 * i)
  end
  g.setColor(1, 1, 1, 1)
  g.pop()
end

return DebugHud
