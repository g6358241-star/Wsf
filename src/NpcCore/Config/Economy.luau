--!strict
-- Economy configuration.
-- Values are PROPOSALS awaiting owner approval (Design Brief §10) unless tagged APPROVED.

return {
	-- APPROVED 2026-11-12: Coins = primary, DCoins = secondary. Must match ReplicatedStorage.HarborShared.Config.Currencies.
	Currency = {
		Primary = "Coins",
		Secondary = "DCoins",
	},

	-- APPROVED structure (§2.2, §12.10): base rate + deterministic tier modifiers, always >= 1 on a qualifying donation.
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

	-- Separate random outcome after a player donation to an NPC (§5.2). Paid in Coins from the NPC's own funds.
	ReturnDonation = {
		baseChance = 0.15,
		fractionMin = 0.05,
		fractionMax = 0.50,
	},

	-- OPEN (§12.3): where funds an NPC receives are credited. "wallet" | "budget".
	NpcReceivedFundsTo = "wallet",

	-- OPEN: starting Coins for new players. 0 = none. (DCoins never have a starting grant.)
	StartingPrimary = 0,

	-- The only reasons currency may be created, each for exactly one currency. NPCs cannot mint after spawning
	-- (§12.3: no passive NPC income). APPROVED: DCoins come from SecondaryReward and nothing else.
	-- Player-side Coins rewards (playtime, daily, quests, Robux packs) are credited through HarborShared.Rules,
	-- which rejects DCoins outright; they are listed here so the allow-list documents every Coins source.
	MintReasons = {
		SecondaryReward = "DCoins",
		RobuxPurchase = "Coins",
		OfflineEarnings = "Coins",
		StartingGrant = "Coins",
		PlaytimeReward = "Coins",
		DailyReward = "Coins",
		QuestReward = "Coins",
		NpcSpawnWallet = "Coins", -- an arriving NPC's starting wallet, the one approved NPC money source
	},
}
