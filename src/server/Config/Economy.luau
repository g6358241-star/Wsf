--!strict
-- Economy configuration.
-- Every number here is a PROPOSAL awaiting owner approval (Design Brief §10) unless tagged AGREED.

return {
	Currency = {
		Primary = "Primary",
		Secondary = "Secondary",
	},

	-- AGREED structure (§2.2, §12.10): base rate + deterministic tier modifiers, always >= 1 on a qualifying donation.
	-- PROPOSAL values. Rounding: floor after all modifiers, then clamp to [min, max].
	SecondaryReward = {
		baseRate = 0.10,
		flatBonus = 1,
		tiers = {
			{ minAmount = 1, multiplier = 1.00 },
			{ minAmount = 100, multiplier = 1.10 },
			{ minAmount = 1000, multiplier = 1.20 },
			{ minAmount = 10000, multiplier = 1.30 },
		},
		minPerDonation = 1,
		maxPerDonation = 5000,
	},

	-- Separate random outcome after a player donation to an NPC (§5.2). Paid from the NPC's own funds.
	ReturnDonation = {
		baseChance = 0.15,
		fractionMin = 0.05,
		fractionMax = 0.50,
	},

	-- OPEN (§12.3): where funds an NPC receives are credited. "wallet" | "budget".
	NpcReceivedFundsTo = "wallet",

	-- OPEN: starting grant for new players. 0 = none.
	StartingPrimary = 0,

	-- Preset amounts a player may list (§4.2). No arbitrary cap on how many are listed (§12.12);
	-- the list itself is the only bound. PROPOSAL values.
	PlayerStandPresets = {
		5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000,
	},

	-- Only these reasons may create currency. NPC activity can never mint (§12.3: no passive NPC income).
	MintReasons = {
		SecondaryReward = "Secondary",
		RobuxPurchase = "Primary",
		OfflineEarnings = "Primary",
		StartingGrant = "Primary",
		NpcSpawnWallet = "Primary", -- an arriving NPC's starting wallet, the one approved NPC money source
	},
}
