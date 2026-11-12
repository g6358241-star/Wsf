--!strict
-- Luck & modifiers (§12.14): additive sources under one global cap.

local LuckConfig = require("../Config/Luck")

local Luck = {}

-- `activeSources` is a set of source names (e.g. { Vip = true }). Returns the capped total, e.g. 0.08.
function Luck.total(activeSources: { [string]: boolean }, cfg: typeof(LuckConfig)?): number
	local c = cfg or LuckConfig
	local sum = 0
	for name, active in activeSources do
		local value = (c.sources :: { [string]: number })[name]
		if active and value then
			sum += value
		end
	end
	return math.clamp(sum, 0, c.globalCap)
end

-- Multiplier for one area ("visitChance", "donateChance", "rareSpawn", "donationSize").
function Luck.multiplier(total: number, area: string, cfg: typeof(LuckConfig)?): number
	local c = cfg or LuckConfig
	local weight = (c.areaWeights :: { [string]: number })[area] or 0
	return 1 + total * weight
end

return Luck
