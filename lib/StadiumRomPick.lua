-- STADIUM battles: the scoped ROM import row.
--
-- The sandbox cannot open an arbitrary host path. The supported flow is to
-- place the ROM at baseroms/baserom.z64 (or .n64/.v64) inside the mod and let
-- mod:read supply the bytes to StadiumInstall.

local V = ...
local StadiumInstall = V.require("StadiumInstall")

local StadiumRomPick = {}
StadiumRomPick.LABEL = "STADIUM ROM"
StadiumRomPick.ID = "potato_voxel:stadiumRom"

function StadiumRomPick.canDialog()
  return StadiumInstall.romPresent()
end

StadiumRomPick.available = StadiumRomPick.canDialog

function StadiumRomPick.choose()
  return StadiumInstall.romPath()
end

function StadiumRomPick.read()
  local path = StadiumRomPick.choose()
  if not path then return nil, "no scoped Stadium ROM found" end
  local ok, bytes = pcall(V.mod.read, V.mod, path)
  if not ok or type(bytes) ~= "string" then
    return nil, "could not read " .. path
  end
  return bytes, path
end

function StadiumRomPick.import(game)
  if StadiumInstall.status.state == "building" then return false end
  StadiumInstall.setGame(game)
  local bytes, label = StadiumRomPick.read()
  if not bytes then
    local StadiumScreen = V.require("StadiumScreen")
    if game and game.stack then
      game.stack:push(StadiumScreen.newNote(game, "STADIUM ROM",
        "NO SCOPED STADIUM ROM FOUND:", StadiumInstall.romHint()))
    end
    return false
  end
  local ok, err = StadiumInstall.beginFrom(bytes, label)
  if not ok then
    local StadiumScreen = V.require("StadiumScreen")
    if game and game.stack then
      game.stack:push(StadiumScreen.newNote(game, "STADIUM ROM",
        "STADIUM IMPORT FAILED:", tostring(err)))
    end
    return false
  end
  if game and game.stack then
    local StadiumScreen = V.require("StadiumScreen")
    game.stack:push(StadiumScreen.new(game, true))
  end
  return true
end

function StadiumRomPick.row()
  return {
    id = StadiumRomPick.ID,
    label = StadiumRomPick.LABEL,
    value = function()
      if StadiumInstall.status.state == "building" then return "BUILDING" end
      if StadiumInstall.available() then return "READY" end
      if StadiumInstall.romPresent() then return "IMPORT" end
      return "UNAVAILABLE"
    end,
    step = function(game)
      pcall(StadiumRomPick.import, game)
      return true
    end,
  }
end

function StadiumRomPick.poll()
  return false
end

return StadiumRomPick
