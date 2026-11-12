--!strict
-- Generates an NPC's own set of donation buttons (§5.1, §12.5). Amounts reflect the NPC's wallet;
-- button count and spacing pattern vary, giving a large combination space (>10k distinct sets).

local NpcConfig = require("../Config/Npc")
local Rng = require("./Rng")

local OfferGenerator = {}

local PATTERNS = { "Consecutive", "SkipOne", "Doubling", "Spread", "Mixed" }
local PATTERN_WEIGHTS = { 25, 20, 20, 10, 25 }

local function nextIndex(ladder: { number }, idx: number, pattern: string, rng: Rng.Rng): number
	if pattern == "Consecutive" then
		return idx + 1
	elseif pattern == "SkipOne" then
		return idx + 2
	elseif pattern == "Mixed" then
		return idx + rng:int(1, 4)
	end
	local factor = if pattern == "Doubling" then 2 else 4
	local target = ladder[idx] * factor
	local j = idx + 1
	while j <= #ladder and ladder[j] < target do
		j += 1
	end
	return j
end

function OfferGenerator.generate(rng: Rng.Rng, wallet: number, cfg: typeof(NpcConfig.Offers)?): { number }
	local c = cfg or NpcConfig.Offers
	local ladder = c.ladder
	local count = rng:weightedIndex(c.countWeights)
	local target = wallet * 10 ^ rng:range(c.startFractionLog10[1], c.startFractionLog10[2])

	local idx = 1
	for i, value in ladder do
		if value <= target then
			idx = i
		end
	end

	local pattern = PATTERNS[rng:weightedIndex(PATTERN_WEIGHTS)]
	local offers = {}
	while #offers < count and idx <= #ladder do
		table.insert(offers, ladder[idx])
		idx = nextIndex(ladder, idx, pattern, rng)
	end
	return offers
end

return OfferGenerator
