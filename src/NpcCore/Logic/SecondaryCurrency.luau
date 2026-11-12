--!strict
-- Deterministic secondary-currency reward (§2.2, §12.10). Same amount + same config => same reward. No randomness.

local EconomyConfig = require("../Config/Economy")

local SecondaryCurrency = {}

export type RewardConfig = typeof(EconomyConfig.SecondaryReward)

function SecondaryCurrency.tierMultiplier(amount: number, cfg: RewardConfig?): number
	local c = cfg or EconomyConfig.SecondaryReward
	local multiplier = 1
	for _, tier in c.tiers do
		if amount >= tier.minAmount then
			multiplier = tier.multiplier
		end
	end
	return multiplier
end

function SecondaryCurrency.reward(amount: number, cfg: RewardConfig?): number
	local c = cfg or EconomyConfig.SecondaryReward
	if amount <= 0 then
		return 0
	end
	local raw = amount * c.baseRate * SecondaryCurrency.tierMultiplier(amount, c) + c.flatBonus
	return math.clamp(math.floor(raw), c.minPerDonation, c.maxPerDonation)
end

return SecondaryCurrency
