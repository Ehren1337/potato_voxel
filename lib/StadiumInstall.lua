-- STADIUM battles: scoped ROM import and scoped pack persistence.
--
-- The sandbox has no host-file picker and no raw filesystem. A ROM may still
-- be supplied inside the mod's own folder and read with mod:read; generated
-- DSM packs are data owned by this mod and live in mod.storage.

local V = ...
local StadiumPack = V.require("StadiumPack")

local StadiumInstall = {}
StadiumInstall.ROM_DIR = "baseroms"
StadiumInstall.DIR = StadiumPack.CACHE_DIR
StadiumInstall.MARKER = "stadium/manifest"
StadiumInstall.FORMAT = "DSM3"
StadiumInstall.REV = 3
StadiumInstall.COUNT = 151

local PACK_PREFIX = "stadium/packs"
local ROM_NAMES = {
  "baseroms/baserom.z64",
  "baseroms/baserom.n64",
  "baseroms/baserom.v64",
}
local storageGame = nil
local job = nil
local status = { state = "idle", done = 0, total = StadiumInstall.COUNT }
StadiumInstall.status = status

local function modRead(path)
  local mod = V.mod
  if not (mod and mod.read) then return nil end
  local ok, bytes = pcall(mod.read, mod, path)
  return ok and type(bytes) == "string" and bytes or nil
end

local function storageApi()
  local mod = V.mod
  local storage = mod and mod.storage
  if not (storage and storage.read and storage.write and storage.list
          and storage.delete and storageGame) then
    return nil
  end
  local ok = pcall(storage.context, storage, storageGame)
  return ok and storage or nil
end

local function storageRead(key)
  local storage = storageApi()
  if not storage then return nil end
  local ok, value = pcall(storage.read, storage, storageGame, key)
  return ok and type(value) == "table" and value or nil
end

local function storageWrite(key, value)
  local storage = storageApi()
  if not storage then return false end
  local ok, result = pcall(storage.write, storage, storageGame, key, value)
  return ok and result == true
end

local function storageDelete(key)
  local storage = storageApi()
  if not storage then return false end
  local ok, result = pcall(storage.delete, storage, storageGame, key)
  return ok and result == true
end

function StadiumInstall.setGame(game)
  storageGame = game
  StadiumPack.setGame(game)
end

function StadiumInstall.romPath()
  for _, path in ipairs(ROM_NAMES) do
    local bytes = modRead(path)
    if bytes and #bytes > 0 then return path end
  end
  return nil
end

function StadiumInstall.romPresent()
  return StadiumInstall.romPath() ~= nil
end

function StadiumInstall.romHint()
  return "put baseroms/baserom.z64 inside the mod folder"
end

function StadiumInstall.romHintFile()
  return StadiumInstall.romHint()
end

local function shipped()
  return modRead(("%s/%03d.dsm"):format(StadiumPack.DIR, 1)) ~= nil
     and modRead(("%s/%03d.dsm"):format(StadiumPack.DIR, StadiumInstall.COUNT)) ~= nil
end

function StadiumInstall.ready()
  local marker = storageRead(StadiumInstall.MARKER)
  return marker and marker.format == StadiumInstall.FORMAT
    and tonumber(marker.total) == StadiumInstall.COUNT
    and tonumber(marker.rev) == StadiumInstall.REV
end

function StadiumInstall.available()
  return StadiumInstall.ready() or shipped()
end

function StadiumInstall.pending()
  return not StadiumInstall.available() and StadiumInstall.romPresent()
end

function StadiumInstall.forget()
  storageDelete(StadiumInstall.MARKER)
  local storage = storageApi()
  if storage then
    local ok, keys = pcall(storage.list, storage, storageGame, PACK_PREFIX)
    if ok and type(keys) == "table" then
      for _, key in ipairs(keys) do storageDelete(key) end
    end
  end
  StadiumPack.forget()
end

local function writePack(species, bytes)
  local compressed = StadiumPack.compress(bytes)
  return storageWrite(("%s/%03d"):format(PACK_PREFIX, species),
                      { body = compressed })
end

function StadiumInstall.begin(game)
  if game then StadiumInstall.setGame(game) end
  local path = StadiumInstall.romPath()
  if not path then return false, "no ROM in " .. StadiumInstall.ROM_DIR end
  local bytes = modRead(path)
  if not bytes then return false, "could not read " .. path end
  return StadiumInstall.beginFrom(bytes, path)
end

function StadiumInstall.beginFrom(bytes, label)
  if type(bytes) ~= "string" or #bytes == 0 then
    return false, "empty file"
  end
  if not storageApi() then return false, "storage is unavailable" end

  local StadiumRom = V.require("StadiumRom")
  local StadiumBuild = V.require("StadiumBuild")
  local rom, err = StadiumRom.open(bytes)
  if not rom then return false, tostring(err) end
  status.wrongVersion = false
  if not rom:isExpectedUS() then
    status.wrongVersion = true
    V.mod.log:warn("stadium: %s is not Pokemon Stadium (US) 1.0; "
                   .. "building anyway", tostring(label or "the ROM"))
  end
  if rom:modelCount() < StadiumInstall.COUNT then
    return false, "needs Pokemon Stadium US 1.0"
  end

  job = StadiumBuild.job(rom, writePack, StadiumInstall.COUNT)
  job.md5 = rom:md5()
  status.state, status.done, status.total, status.error =
    "building", 0, job.total, nil
  return true
end

function StadiumInstall.step()
  if not job then return false end
  local more = job:step()
  status.done, status.species = job.done, job.species
  if job.error then
    status.state, status.error, job = "failed", job.error, nil
    return false
  end
  if more then return true end

  local wrote = #job.failed == 0 and job.total == StadiumInstall.COUNT
  if wrote then
    wrote = storageWrite(StadiumInstall.MARKER, {
      format = StadiumInstall.FORMAT,
      total = job.total,
      md5 = tostring(job.md5 or ""),
      rev = StadiumInstall.REV,
    })
  end
  if wrote then
    status.state = "done"
    StadiumPack.forget()
  else
    status.state = "failed"
    status.error = #job.failed > 0 and "one or more Stadium models failed"
                   or "could not persist Stadium packs"
  end
  job = nil
  return false
end

function StadiumInstall.cancel()
  job = nil
  status.state, status.error = "idle", nil
end

return StadiumInstall
