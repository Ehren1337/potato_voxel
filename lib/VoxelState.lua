-- Voxel world mode: the camera angle and its tween.
--
-- The LEVEL is not ours. The engine's render_pipelines plumbing owns it --
-- the options row, the hotkey, the ladder labels, persistence in
-- save.options.pipelines.voxel, and the mutual exclusion with tilt -- and
-- hands it to update() every frame. All this module keeps is the eased
-- ANGLE that level implies, because the tween is renderer state and only
-- the renderer knows what to do with a half-raised camera.
--
-- Purely presentational, like tilt and survey zoom: nothing here reaches
-- collision, movement, triggers or scripts.

local Voxel = {}

-- The ladder this build ships: OFF plus the five active rungs
-- (HIGH / MEDIUM / LOW / POTATO / CUSTOM), every active rung at the
-- classic 35-degree diorama framing. The duplicate angle in the table is
-- deliberate: the ladder is a list of what each rung LOOKS like, and rungs
-- may look the same while meaning different things -- the modes differ in
-- the quality preset QualityMode applies. BrickProfile.apply() re-pins
-- these tables in place at boot (the pipeline record captured them by
-- reference), so a tuning change stays a one-file edit.
Voxel.ANGLES_DEG = { 0, 35, 35, 35, 35, 35 }
Voxel.ANGLE_LABELS = { "OFF", "HIGH", "MEDIUM", "LOW", "POTATO", "CUSTOM" }
Voxel.MAX_LEVEL = #Voxel.ANGLES_DEG - 1

-- the rung HIGH sits on. The upstream build called this rung FULL, and
-- the name is kept so the gates that mean "the mode is at its headline
-- rung" still read as such.
Voxel.FULL_LEVEL = 1

function Voxel.isFull(level)
  return (level or Voxel.level) == Voxel.FULL_LEVEL
end

-- The free-roam rungs (upstream 1ST / 3RD) are not on this ladder --
-- these predicates are constant-false here. They stay for the VR restore
-- path, which reads them through FirstPerson.engaged().
Voxel.FP_LEVEL = 6

function Voxel.isFirstPerson(level)
  return (level or Voxel.level) == Voxel.FP_LEVEL
end

Voxel.TP_LEVEL = 7

function Voxel.isThirdPerson(level)
  return (level or Voxel.level) == Voxel.TP_LEVEL
end

-- The two of them together: the rungs where the camera stands WITH the
-- player rather than orbiting the view centre, which is what decides that
-- the look inputs are read, the walk goes free and the cards turn to face
-- the eye.
function Voxel.isFreeCam(level)
  level = level or Voxel.level
  return Voxel.isFirstPerson(level) or Voxel.isThirdPerson(level)
end

-- ------- what the hotkey walks
--
-- The active rungs: OFF -> HIGH -> MEDIUM -> LOW -> POTATO -> OFF. CUSTOM
-- is left out -- it is the player's own combination, reached from the
-- menu, not a mode a key should land on.
Voxel.HOTKEY_ORDER = { 0, 1, 2, 3, 4 }  -- OFF,HIGH,MEDIUM,LOW,POTATO

-- The rung a press moves to from `level`.
--
-- A level that is not on the key's path -- CUSTOM, reached from the menu
-- -- steps on from whichever rung shows the SAME camera it does: CUSTOM
-- is 35 degrees, so a press from it goes to MEDIUM rather than wrapping
-- early, and the key never appears to do nothing. Matched by ANGLE rather
-- than by a hardcoded rung, so retuning the ladder moves the key's answer
-- with it.
function Voxel.nextHotkeyLevel(level)
  level = level or Voxel.level
  local order = Voxel.HOTKEY_ORDER
  local at = nil
  for i, rung in ipairs(order) do
    if rung == level then at = i break end
  end
  if not at then
    local deg = Voxel.ANGLES_DEG[level + 1]
    for i, rung in ipairs(order) do
      if Voxel.ANGLES_DEG[rung + 1] == deg then at = i break end
    end
  end
  if not at then return order[1] end
  return order[at % #order + 1]
end

Voxel.level = 0
Voxel.angle = 0
Voxel.from = 0
Voxel.goal = 0
Voxel.t = 1

-- Whether the scene has terrain to show for the current map. VoxelScene
-- maintains it every frame; while the first mesh of a fresh toggle is
-- still building, update() holds the camera tween at flat -- the 2D
-- fallback IS the flat pose, so the switch waits invisibly instead of
-- tilting an empty stage (or, before builds went asynchronous, freezing
-- the whole frame for seconds).
Voxel.ready = true

-- A cold destination owns an opaque cover until its first terrain mesh lands,
-- so the asynchronous build never leaks the vanilla 2D world.
Voxel.loading = false
Voxel.loadingMap = nil
Voxel.loadingSince = 0

local clock = (love and love.timer and love.timer.getTime) or os.clock

function Voxel.beginLoading(mapId)
  if Voxel.loading and Voxel.loadingMap == mapId then return end
  Voxel.loading = true
  Voxel.loadingMap = mapId
  Voxel.loadingSince = clock()
  Voxel.ready = false
end

function Voxel.finishLoading(mapId)
  if mapId and Voxel.loadingMap ~= mapId then return end
  Voxel.loading = false
  Voxel.loadingMap = nil
  Voxel.loadingSince = 0
end

Voxel.TWEEN_TIME = 0.25
-- Camera distance as a multiple of the view height, and the matching field
-- of view. Kept equal to Tilt.FOCAL so a given angle frames the world the
-- same way in both modes; Voxel3D derives the FOV from it.
Voxel.FOCAL = 1.0

local function ease(t)
  return t * t * (3 - 2 * t)
end

local function goalFor(level)
  return math.rad(Voxel.ANGLES_DEG[level + 1] or 0)
end

function Voxel.setLevel(level)
  level = math.floor(tonumber(level) or 0)
  if level < 0 then level = 0 end
  if level > Voxel.MAX_LEVEL then level = Voxel.MAX_LEVEL end
  local goal = goalFor(level)
  if goal <= 0 then Voxel.finishLoading() end
  if goal ~= Voxel.goal or level ~= Voxel.level then
    Voxel.from = Voxel.angle
    Voxel.goal = goal
    Voxel.t = 0
    -- leaving flat: presume no terrain until the scene reports some, so
    -- the tween's very first frame already waits instead of easing over
    -- an empty stage (render() confirms readiness the same frame when
    -- the meshes are already cached)
    if Voxel.angle == 0 and goal > 0 then Voxel.ready = false end
  end
  Voxel.level = level
end

function Voxel.reset()
  Voxel.level, Voxel.angle = 0, 0
  Voxel.from, Voxel.goal, Voxel.t = 0, 0, 1
  Voxel.finishLoading()
end

function Voxel.levelLabel(level)
  return Voxel.ANGLE_LABELS[(level or Voxel.level) + 1] or "OFF"
end

-- The pipeline's per-frame tick. `level` is what the engine currently has
-- the mode set to, so a hotkey press or an options row lands here as a new
-- goal to ease toward rather than as a jump.  dt is real frame time, so
-- fast-forward does not speed the camera up.
function Voxel.update(dt, level)
  if level ~= nil and level ~= Voxel.level then Voxel.setLevel(level) end
  -- hold at flat until there is geometry to tilt over; easing OUT (goal
  -- below the current angle) never waits
  if Voxel.angle == 0 and Voxel.goal > 0 and not Voxel.ready then
    return
  end
  if Voxel.t < 1 then
    Voxel.t = math.min(1, Voxel.t + dt / Voxel.TWEEN_TIME)
    Voxel.angle = Voxel.from + (Voxel.goal - Voxel.from) * ease(Voxel.t)
  else
    Voxel.angle = Voxel.goal
  end
end

-- True while voxel mode is on *or* still easing out -- i.e. whenever the
-- renderer must take the 3D path instead of the flat blit. Mirrors
-- Tilt.active so the two gate the same way.
function Voxel.active()
  return Voxel.level > 0 or Voxel.angle > 0
end

return Voxel
