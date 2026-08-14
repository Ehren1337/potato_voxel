-- OpenXR is not available to sandboxed mods.

local VRXR = {}
local reason = "OpenXR is unavailable to sandboxed mods"

VRXR.XR = {}

function VRXR._loaderCandidates()
  return {}
end

function VRXR.input()
  return {}
end

function VRXR.start()
  return false, reason
end

function VRXR.stop()
end

function VRXR.poll()
  return false
end

function VRXR.isRunning()
  return false
end

function VRXR.waitFrame()
  return nil, false
end

function VRXR.locateViews()
  return nil
end

function VRXR.acquireEye()
  return nil
end

function VRXR.releaseEye()
  return false
end

function VRXR.acquireQuad()
  return nil
end

function VRXR.releaseQuad()
  return false
end

function VRXR.endFrame()
  return false
end

function VRXR.quadSize()
  return nil, nil
end

function VRXR.status()
  return reason
end

return VRXR
