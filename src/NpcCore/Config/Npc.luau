--!strict
-- NPC simulation configuration (§3, §12). All values are PROPOSALS for the balancing phase.
-- Spawn, stand-visit and donation chances are deliberately separate stages (§3.5).

export type TraitRange = { mean: number, spread: number }

export type Archetype = {
	id: string,
	spawnWeight: number,
	rare: boolean, -- affected by the rare-spawn luck area
	walletScale: number, -- multiplies the server wealth tier's median wallet
	walletSigma: number, -- log-normal spread of the individual wallet
	traits: { [string]: TraitRange },
	donateChance: number, -- stage 3 base chance once an NPC is inspecting a stand
}

local function t(mean: number, spread: number): TraitRange
	return { mean = mean, spread = spread }
end

local archetypes: { Archetype } = {
	{
		id = "Ordinary",
		spawnWeight = 60,
		rare = false,
		walletScale = 1.0,
		walletSigma = 0.8,
		traits = {
			curiosity = t(0.45, 0.15), patience = t(0.45, 0.15), generosity = t(0.35, 0.15),
			pickiness = t(0.40, 0.15), riskTolerance = t(0.35, 0.15), appealSensitivity = t(0.40, 0.15),
			standAmbition = t(0.06, 0.04), sociability = t(0.30, 0.15), sensitivity = t(0.50, 0.20),
		},
		donateChance = 0.13,
	},
	{
		id = "Curious",
		spawnWeight = 18,
		rare = false,
		walletScale = 0.9,
		walletSigma = 0.8,
		traits = {
			curiosity = t(0.80, 0.10), patience = t(0.70, 0.12), generosity = t(0.35, 0.15),
			pickiness = t(0.35, 0.15), riskTolerance = t(0.40, 0.15), appealSensitivity = t(0.55, 0.15),
			standAmbition = t(0.08, 0.05), sociability = t(0.55, 0.15), sensitivity = t(0.45, 0.20),
		},
		donateChance = 0.11,
	},
	{
		id = "Picky",
		spawnWeight = 12,
		rare = false,
		walletScale = 1.3,
		walletSigma = 0.8,
		traits = {
			curiosity = t(0.50, 0.15), patience = t(0.40, 0.15), generosity = t(0.30, 0.12),
			pickiness = t(0.85, 0.10), riskTolerance = t(0.25, 0.12), appealSensitivity = t(0.80, 0.10),
			standAmbition = t(0.05, 0.04), sociability = t(0.20, 0.10), sensitivity = t(0.70, 0.15),
		},
		donateChance = 0.09,
	},
	{
		id = "Generous",
		spawnWeight = 8,
		rare = false,
		walletScale = 2.5,
		walletSigma = 0.9,
		traits = {
			curiosity = t(0.55, 0.15), patience = t(0.55, 0.15), generosity = t(0.80, 0.10),
			pickiness = t(0.30, 0.15), riskTolerance = t(0.60, 0.15), appealSensitivity = t(0.40, 0.15),
			standAmbition = t(0.10, 0.05), sociability = t(0.60, 0.15), sensitivity = t(0.35, 0.15),
		},
		donateChance = 0.24,
	},
	{
		-- Rare/popular visitors are never announced or telegraphed (§12.7); they run the same simulation.
		id = "Rare",
		spawnWeight = 2,
		rare = true,
		walletScale = 12.0,
		walletSigma = 1.0,
		traits = {
			curiosity = t(0.60, 0.20), patience = t(0.60, 0.20), generosity = t(0.70, 0.20),
			pickiness = t(0.50, 0.25), riskTolerance = t(0.70, 0.20), appealSensitivity = t(0.50, 0.20),
			standAmbition = t(0.45, 0.20), sociability = t(0.50, 0.20), sensitivity = t(0.40, 0.20),
		},
		donateChance = 0.22,
	},
}

return {
	archetypes = archetypes,

	-- Server wealth profile (§12.4), rolled once per server. medianWallet = typical NPC wallet on that server.
	wealthTiers = {
		{ id = "Ordinary", weight = 80, medianWallet = 600 },
		{ id = "Medium", weight = 17, medianWallet = 2500 },
		{ id = "Wealthy", weight = 3, medianWallet = 25000 },
	},
	-- Chance that any single NPC on a Wealthy server is a "whale" in the 400k–1M+ range (§12.4).
	whale = { chanceOnWealthyServer = 0.02, minWallet = 400000, maxWallet = 1500000 },

	Population = {
		maxActive = 100, -- target scenario (§12.2), subject to profiling
		arrivalsPerMinute = 7,
		initialBurst = 12,
		returningNpcChance = 0.08, -- chance an arrival is a remembered NPC (§12.1)
	},

	Visit = {
		-- stage 2: chance an NPC passing a claimed stand stops to inspect it
		inspectBase = 0.30,
		inspectCuriosityWeight = 0.50,
		appealVisitWeight = 0.25, -- appeal moves visit odds by at most ±12.5% (§3.4 "minor factor")
		travelSeconds = { 6, 20 },
		inspectSeconds = { 4, 12 },
		idleSeconds = { 2, 8 },
	},

	Decision = {
		generosityWeight = 0.8, -- p *= (1 - w/2) + w * generosity
		appealDecisionWeight = 0.10, -- appeal's effect on the separate donation decision, scaled by pickiness
		repeatDonationDecay = 0.55, -- p *= decay^(donations already made this visit)
		maxChance = 0.85,
		comfortFractionMin = 0.04, -- comfortable gift = budget * lerp(min, max, generosity * riskTolerance)
		comfortFractionMax = 0.35,
		overComfortSigma = 0.9, -- how quickly willingness falls for amounts above the comfortable gift (log space)
		pickyRejectRatio = 4, -- picky NPCs walk away if the cheapest offer exceeds comfort * ratio
	},

	Finance = {
		initialWithdrawMean = 0.35, -- fraction of wallet moved to the donation budget on arrival
		initialWithdrawSpread = 0.20,
		nothingWithdrawnChance = 0.15, -- some NPCs only browse
		refillChanceScale = 0.6,
		refillFraction = { 0.10, 0.35 },
	},

	Departure = {
		visitSeconds = { 120, 900 }, -- lerp by patience
		maxInspections = { 2, 10 }, -- lerp by curiosity
		leaveHazardPerStand = 0.06,
	},

	NpcStand = {
		claimAfterVisits = { 0, 3 },
		afkSeconds = { 300, 1800 },
	},

	Request = {
		chancePerCheck = 0.02, -- scaled by sociability; checked while an NPC owns a stand
		checkIntervalSeconds = 30,
		playerCooldownSeconds = 240,
		followGraceSeconds = 25, -- no penalty for brief delays (§12.11)
		maxCallSeconds = { 30, 120 }, -- lerp by patience: how long the NPC keeps calling the player
	},

	Offers = {
		ladder = {
			1, 2, 3, 5, 10, 15, 20, 25, 50, 75, 100, 150, 200, 250, 500, 750, 1000, 1500, 2000, 2500,
			5000, 7500, 10000, 15000, 20000, 25000, 50000, 75000, 100000, 250000, 500000, 1000000,
		},
		countWeights = { 14, 14, 21, 18, 11, 8, 6, 4, 2, 2 }, -- index = number of buttons
		startFractionLog10 = { -3.5, -1.2 }, -- first button ~ wallet * 10^U(range)
	},
}
