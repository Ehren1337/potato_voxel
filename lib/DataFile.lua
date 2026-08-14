-- Memoized loader for the mod's own data tables (data/*.lua, read through
-- V.data rather than package.path -- a mod's directory is not on it and
-- may live inside a mounted .love archive). Nil while untried, false when
-- absent or not a table, the table once read -- one semantics for every
-- consumer of a data file instead of each keeping a copy of the pcall.
local V = ...

local DataFile = {}
local cache = {}

function DataFile.table(name)
  local hit = cache[name]
  if hit == nil then
    local ok, s = pcall(V.data, name)
    hit = (ok and type(s) == "table") and s or false
    cache[name] = hit
  end
  return hit or nil
end

return DataFile
