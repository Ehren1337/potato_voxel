-- One memoized shader loader, shared by every pass that compiles a
-- shader string at first use: nil = untried, false = unavailable, the
-- handle once compiled. The source string is the cache key, so each pass
-- keeps asking for its own shader and this stays a plain memo -- and a
-- headless or shader-less run returns nil exactly as the per-module
-- copies did, without a retry storm.
local V = ...

local ShaderCache = {}
local cache = {}

function ShaderCache.get(source)
  local hit = cache[source]
  if hit == nil then
    local ok, sh = pcall(love.graphics.newShader, source)
    hit = (ok and sh) or false
    cache[source] = hit
  end
  return hit or nil
end

return ShaderCache
