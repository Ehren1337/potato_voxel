-- ScopedMeshStorage owns the data-only record layout used by MeshCache.
-- The public interface deliberately accepts logical payload keys instead of
-- filesystem-looking paths.
local V = ...

local Store = {}
Store.CHUNK_SIZE = 256 * 1024
Store.SCHEMA = 2

local storage = nil
local storageGame = nil
local errorMessage = nil
local generationSerial = 0

local Budget = V.require("BuildBudget")

local function setError(operation, detail)
  errorMessage = tostring(operation)
  if detail ~= nil then errorMessage = errorMessage .. ": " .. tostring(detail) end
end

local function clearError()
  errorMessage = nil
end

local function validSegment(value)
  return type(value) == "string" and value ~= ""
     and value:match("^[%w_%-]+$") ~= nil
end

local function mapToken(mapId)
  if type(mapId) ~= "string" then return nil end
  if #mapId == 0 then return "0" end
  local out = {}
  for i = 1, #mapId do
    out[#out + 1] = ("%02x"):format(mapId:byte(i))
  end
  return table.concat(out)
end

local function logicalRoot(logicalKey)
  if type(logicalKey) ~= "table" then
    setError("invalid_key", "logical key must be a table")
    return nil
  end
  local token = mapToken(logicalKey.mapId)
  local slot, kind = logicalKey.slot, logicalKey.kind
  if not token or not validSegment(slot) or not validSegment(kind)
     or (slot ~= "body" and slot ~= "full")
     or (kind ~= "terrain" and kind ~= "water" and kind ~= "aux") then
    setError("invalid_key", "unsupported map, slot, or payload kind")
    return nil
  end
  return table.concat({ "meshes", "v2", token, slot, kind }, "/")
end

local function generationRoot(root, generation)
  return root .. "/g" .. tostring(generation)
end

local function callRead(key)
  local ok, value, code, detail = pcall(storage.read, storage, storageGame, key)
  if not ok then
    setError("read_failed", value)
    return nil, false
  end
  if value == nil then
    if code ~= nil then setError("read_failed", code .. ": " .. tostring(detail)) end
    return nil, false
  end
  if type(value) ~= "table" then
    setError("invalid_record", key)
    return nil, false
  end
  return value, true
end

local function callWrite(key, value)
  local ok, result, code, detail = pcall(storage.write, storage, storageGame,
                                         key, value)
  if not ok then
    setError("write_failed", result)
    return false
  end
  if result ~= true then
    setError("write_failed", code or detail or key)
    return false
  end
  return true
end

local function callDelete(key)
  local ok, result, code, detail = pcall(storage.delete, storage, storageGame,
                                         key)
  if not ok then
    setError("delete_failed", result)
    return false
  end
  if result == false then
    setError("delete_failed", code or detail or key)
    return false
  end
  return true
end

local function callList(prefix)
  local ok, keys, code, detail = pcall(storage.list, storage, storageGame,
                                      prefix)
  if not ok then
    setError("list_failed", keys)
    return nil
  end
  if type(keys) ~= "table" then
    setError("list_failed", code or detail or prefix)
    return nil
  end
  return keys
end

local function commitKey(root)
  return root .. "/commit"
end

local function metaKey(root, generation)
  return generationRoot(root, generation) .. "/meta"
end

local function chunkKey(root, generation, index)
  return generationRoot(root, generation) .. "/chunk/" .. ("%06d"):format(index)
end

local function readCommit(root)
  local commit = callRead(commitKey(root))
  if not commit then return nil end
  if commit.schema ~= Store.SCHEMA or type(commit.generation) ~= "number"
     or type(commit.fingerprint) ~= "string"
     or type(commit.chunks) ~= "number" or commit.chunks < 1
     or type(commit.bytes) ~= "number" or commit.bytes < 0 then
    setError("invalid_commit", root)
    return nil
  end
  return commit
end

local function legacyKey(logicalKey)
  local id = tostring(logicalKey.mapId):gsub("[^%w_]", "_")
  local name = table.concat({ id, logicalKey.slot, logicalKey.kind }, ".")
  name = name:gsub("[^%w_%-]", "_")
  return "meshes/" .. name
end

local function logicalId(logicalKey)
  return table.concat({ tostring(logicalKey.mapId), tostring(logicalKey.slot),
                        tostring(logicalKey.kind) }, "/")
end

local function metaRecordKey(name)
  if not validSegment(name) then
    setError("invalid_key", "metadata name must be a safe segment")
    return nil
  end
  return "meshes/v2/meta/" .. name
end

local function nextGeneration(root)
  local previous = readCommit(root)
  local generation = previous and math.floor(previous.generation) or 0
  generationSerial = generationSerial + 1
  return generation + 1 + generationSerial * 1000000
end

local function bindSelected(api, game)
  if not (api and type(api.selected) == "function") then return api end
  local ok, selected, code, detail = pcall(api.selected, api, game)
  if not ok then
    setError("storage_unavailable", selected)
    return nil
  end
  if type(selected) == "table" then
    -- Keep the adapter's existing (game, key) call shape while the engine's
    -- selected-playthrough facade closes over its safe title-session scope.
    return {
      context = function() return selected:context() end,
      read = function(_, _, key) return selected:read(key) end,
      write = function(_, _, key, value) return selected:write(key, value) end,
      list = function(_, _, prefix) return selected:list(prefix) end,
      delete = function(_, _, key) return selected:delete(key) end,
    }
  end
  if code == "not_at_title" then
    local meta = game and game.save and game.save.meta
    local overworld = game and game.overworld
    local activeMap = overworld and overworld.map
    if validSegment(meta and meta.playthroughId)
       or (type(activeMap) == "table" and activeMap.id ~= nil) then
      return api
    end
    -- game.ready can fire with a launcher/bootstrap state already on the
    -- stack, before TitleState is pushed. Only a stamped playthrough id or an
    -- actually restored overworld proves this is gameplay; ordinary storage
    -- on the fresh skeleton would allocate an orphan id and overwrite the
    -- selected slot's routing.
    setError("not_in_playthrough", "playthrough selection is not ready")
    return nil
  end
  -- At title with no selected playthrough, storage must stay unavailable.
  -- Falling back to ordinary storage would allocate an orphan identity.
  setError(code or "storage_unavailable", detail)
  return nil
end

function Store.configure(api, game)
  storage = nil
  storageGame = game
  errorMessage = nil
  storage = bindSelected(api, game)
end

function Store.available()
  if not (storage and storage.context and storage.read and storage.write
          and storage.list and storage.delete and storageGame) then
    errorMessage = "storage_unavailable"
    return false
  end
  local ok, context = pcall(storage.context, storage, storageGame)
  if not (ok and type(context) == "table") then
    errorMessage = ok and "storage_unavailable" or tostring(context)
    return false
  end
  errorMessage = nil
  return true
end

function Store.lastError()
  return errorMessage
end

function Store.write(logicalKey, fingerprint, packedPayload)
  local root = logicalRoot(logicalKey)
  if not root or type(fingerprint) ~= "string"
     or type(packedPayload) ~= "string" then
    if not root then return false end
    setError("invalid_payload", "fingerprint and payload must be strings")
    return false
  end
  if not Store.available() then return false end

  local generation = nextGeneration(root)
  local chunkCount = math.max(1, math.ceil(#packedPayload / Store.CHUNK_SIZE))
  local metadata = {
    schema = Store.SCHEMA,
    fingerprint = fingerprint,
    generation = generation,
    bytes = #packedPayload,
    chunkSize = Store.CHUNK_SIZE,
    chunks = chunkCount,
  }
  if not callWrite(metaKey(root, generation), metadata) then return false end

  for index = 1, chunkCount do
    local first = (index - 1) * Store.CHUNK_SIZE + 1
    local last = math.min(#packedPayload, index * Store.CHUNK_SIZE)
    local body = packedPayload:sub(first, last)
    if not callWrite(chunkKey(root, generation, index), {
      body = body,
      index = index,
      total = chunkCount,
      generation = generation,
      byteLength = #body,
    }) then
      return false
    end
    Budget.check()
  end

  if not callWrite(commitKey(root), {
    schema = Store.SCHEMA,
    fingerprint = fingerprint,
    generation = generation,
    bytes = #packedPayload,
    chunks = chunkCount,
  }) then
    return false
  end
  local keepPrefix = generationRoot(root, generation) .. "/"
  local oldKeys = callList(root)
  if oldKeys then
    for _, key in ipairs(oldKeys) do
      if key ~= commitKey(root) and key:sub(1, #keepPrefix) ~= keepPrefix then
        -- A committed replacement is already safe. Old-generation cleanup is
        -- best effort so a cleanup failure cannot turn a successful cache
        -- write into a visible build failure.
        pcall(storage.delete, storage, storageGame, key)
      end
    end
  end
  clearError()
  return true
end

function Store.read(logicalKey, fingerprint)
  local root = logicalRoot(logicalKey)
  if not root or type(fingerprint) ~= "string" then return nil end
  if not Store.available() then return nil end

  local commit = readCommit(root)
  if commit and commit.fingerprint == fingerprint then
    local metadata = callRead(metaKey(root, commit.generation))
    if metadata and metadata.schema == Store.SCHEMA
       and metadata.fingerprint == commit.fingerprint
       and metadata.generation == commit.generation
       and metadata.bytes == commit.bytes
       and metadata.chunks == commit.chunks then
      local parts = {}
      local total = 0
      for index = 1, commit.chunks do
        local chunk = callRead(chunkKey(root, commit.generation, index))
        if not chunk or type(chunk.body) ~= "string"
           or chunk.index ~= index or chunk.total ~= commit.chunks
           or chunk.generation ~= commit.generation
           or chunk.byteLength ~= #chunk.body then
          setError("incomplete_payload", root)
          parts = nil
          break
        end
        parts[index] = chunk.body
        total = total + #chunk.body
        Budget.check()
      end
      if parts and total == commit.bytes then
        clearError()
        return table.concat(parts), "v2"
      end
      if parts then setError("payload_length_mismatch", root) end
    else
      setError("invalid_metadata", root)
    end
  end

  local legacy = callRead(legacyKey(logicalKey))
  if legacy and type(legacy.body) == "string" then
    clearError()
    return legacy.body, "legacy"
  end
  return nil
end

function Store.readMeta(name)
  local key = metaRecordKey(name)
  if not key or not Store.available() then return nil end
  local value = callRead(key)
  if not value then
    local legacyName = name == "manifest" and "cache_info"
                    or name == "build-info" and "build_info"
    if legacyName then value = callRead("meshes/" .. legacyName) end
  end
  if value then clearError() end
  return value
end

function Store.writeMeta(name, value)
  local key = metaRecordKey(name)
  if not key or not Store.available() or type(value) ~= "table" then
    if key and type(value) ~= "table" then setError("invalid_metadata") end
    return false
  end
  local ok = callWrite(key, value)
  if ok then clearError() end
  return ok
end

function Store.removeMeta(name)
  local key = metaRecordKey(name)
  if not key or not Store.available() then return false end
  local ok = callDelete(key)
  local legacyName = name == "manifest" and "cache_info"
                  or name == "build-info" and "build_info"
  if legacyName and not callDelete("meshes/" .. legacyName) then ok = false end
  if ok then clearError() end
  return ok
end

function Store.scan(logicalKeys)
  local records, count = {}, 0
  if not Store.available() then return records, count end
  for _, logicalKey in ipairs(logicalKeys or {}) do
    local root = logicalRoot(logicalKey)
    if root then
      local commit = readCommit(root)
      local expected = logicalKey.fingerprint
      local matches = commit and type(expected) == "string"
                    and ((logicalKey.prefix
                          and commit.fingerprint:sub(1, #expected) == expected)
                         or (not logicalKey.prefix
                             and commit.fingerprint == expected))
      if matches then
        local id = logicalId(logicalKey)
        records[id] = { logicalKey = logicalKey, source = "v2",
                        fingerprint = commit.fingerprint,
                        generation = commit.generation,
                        bytes = commit.bytes, chunks = commit.chunks }
        count = count + 1
      end
    end
  end
  clearError()
  return records, count
end

function Store.remove(logicalKey)
  local root = logicalRoot(logicalKey)
  if not root or not Store.available() then return false end
  local keys = callList(root)
  if not keys then return false end
  for _, key in ipairs(keys) do
    if not callDelete(key) then return false end
  end
  clearError()
  return true
end

function Store.wipe()
  if not Store.available() then return false end
  local keys = callList("meshes")
  if not keys then return false end
  for _, key in ipairs(keys) do
    if not callDelete(key) then return false end
  end
  clearError()
  return true
end

return Store
