-- Deterministic xorshift noise, shared by ForestAtmos (the leaf field)
-- and StadiumFx (the beam haze): the particle deal and the leaf field must
-- come out identical on every machine and every visit.
--
-- The xor is written out in arithmetic rather than taken from LuaJIT's
-- `bit`, which works in SIGNED 32-bit and would need converting back on
-- every step (see the same note in StadiumFragment).
local Noise = {}

local function bxor32(a, b)
  local r, p = 0, 1
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end

local Rng = {}
Rng.__index = Rng

function Noise.rng(seed)
  local s = seed % 0x100000000
  if s == 0 then s = 0x9E3779B9 end
  return setmetatable({ s = s }, Rng)
end

function Rng:next()
  local x = self.s
  x = bxor32(x, (x % 0x80000) * 0x2000)               -- x ^= (x << 13)
  x = bxor32(x, math.floor(x / 0x20000))               -- x ^= x >> 17
  x = bxor32(x, (x % 0x8000000) * 0x20)               -- x ^= (x << 5)
  self.s = x % 0x100000000
  return self.s
end

function Rng:unit()
  return self:next() / 0x100000000
end

-- A w-by-h lattice of unit noise, consumed row by row so the sequence --
-- and therefore the texture -- is reproducible.
function Noise.lattice(rng, w, h)
  local g = {}
  for y = 1, h do
    local row = {}
    for x = 1, w do row[x] = rng:unit() end
    g[y] = row
  end
  return g
end

return Noise
