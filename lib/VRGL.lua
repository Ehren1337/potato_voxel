-- VR graphics interop is unavailable to sandboxed mods.

local VRGL = {}
local reason = "VR graphics interop is unavailable to sandboxed mods"

VRGL.GL = {}

function VRGL.load()
  return false, reason
end

function VRGL.contexts()
  return nil, nil
end

function VRGL.canvasFBO()
  return nil
end

function VRGL.blitToTexture()
  return false
end

function VRGL.copyFrontBuffer()
  return false
end

function VRGL.copyFrontRegionToTexture()
  return false
end

function VRGL.copyFrontToCanvas()
  return false
end

function VRGL.status()
  return reason
end

return VRGL
