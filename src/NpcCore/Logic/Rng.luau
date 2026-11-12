--!strict
-- Portable seeded PRNG (mulberry32). Identical sequences in Roblox and Lune keep simulations reproducible.

local TWO32 = 4294967296

local function imul(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bHi, bLo = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	local cross = bit32.band(aHi * bLo + aLo * bHi, 0xFFFF)
	return (aLo * bLo + cross * 65536) % TWO32
end

local function hashString(s: string): number
	local h = 2166136261 -- FNV-1a
	for i = 1, #s do
		h = imul(bit32.bxor(h, string.byte(s, i)), 16777619)
	end
	return h
end

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number | string): Rng
	local s = if type(seed) == "string" then hashString(seed) else math.floor(seed) % TWO32
	return setmetatable({ state = s }, Rng)
end

function Rng.next(self: Rng): number
	self.state = (self.state + 0x6D2B79F5) % TWO32
	local x = self.state
	x = imul(bit32.bxor(x, bit32.rshift(x, 15)), bit32.bor(x, 1))
	x = bit32.bxor(x, (x + imul(bit32.bxor(x, bit32.rshift(x, 7)), bit32.bor(x, 61))) % TWO32)
	return bit32.bxor(x, bit32.rshift(x, 14)) / TWO32
end

function Rng.range(self: Rng, min: number, max: number): number
	return min + (max - min) * self:next()
end

function Rng.int(self: Rng, min: number, max: number): number
	return min + math.floor(self:next() * (max - min + 1))
end

function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

function Rng.normal(self: Rng, mean: number, sd: number): number
	local u1 = math.max(self:next(), 1e-12)
	local u2 = self:next()
	return mean + sd * math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

function Rng.logNormal(self: Rng, median: number, sigma: number): number
	return median * math.exp(self:normal(0, sigma))
end

-- Returns the index chosen proportionally to weights[i].
function Rng.weightedIndex(self: Rng, weights: { number }): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = self:next() * total
	for i, w in weights do
		roll -= w
		if roll < 0 then
			return i
		end
	end
	return #weights
end

-- Independent child stream, so adding draws in one subsystem doesn't shift another's sequence.
function Rng.fork(self: Rng, salt: string): Rng
	return Rng.new(bit32.bxor(math.floor(self:next() * TWO32), hashString(salt)))
end

Rng.hashString = hashString

return Rng
