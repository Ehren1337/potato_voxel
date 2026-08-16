-- Player-facing support ID: an 8-digit token, unique per INSTALL, shown
-- in the debugger and shipped inside consented log payloads.
--
-- Privacy contract: the token is a random identifier with no link to any
-- personal data, and it only identifies a player when the player chooses
-- to share it (e.g. in a support chat). The engine's playthroughId is
-- deliberately NOT used -- that would let a log be matched to a save
-- without the player's involvement. The token persists in the mod's
-- OPTIONS store, which is per-install (not per-save), so a player with
-- several saves carries one ID.
--
-- Collisions: 8 digits = 1e8 values; at a few thousand installs the
-- birthday bound is negligible, and a support lookup can always confirm
-- with platform + versions before acting.
local V = ...
local PlayerId = {}

local KEY = "player_id"
local cached = nil
local seeded = false

local function mint()
  if not seeded then
    seeded = true
    math.randomseed(os.time() + math.floor((os.clock() or 0) * 1e6))
  end
  return string.format("%08d", math.random(0, 99999999))
end

-- The persisted id, or nil before the first mint. Never blocks on the
-- options store: a missing or broken store leaves the session without
-- an id (the payload simply omits it) instead of erroring a send.
function PlayerId.get()
  if cached then return cached end
  local opts = V.mod and V.mod.options
  if opts and opts.get then
    local ok, v = pcall(opts.get, opts, KEY)
    if ok and type(v) == "string" and v:match("^%d%d%d%d%d%d%d%d$") then
      cached = v
      return v
    end
  end
  return nil
end

-- Mint on first call in the session and try to persist it; a failed
-- persist keeps the session value (the next boot mints a new one).
function PlayerId.ensure()
  if PlayerId.get() then return cached end
  local v = mint()
  cached = v
  local opts = V.mod and V.mod.options
  if opts and opts.set then
    pcall(opts.set, opts, KEY, v)
  end
  return v
end

-- Test seam: forget the session cache (the suites replay boots).
function PlayerId._resetForTests()
  cached = nil
end

return PlayerId
