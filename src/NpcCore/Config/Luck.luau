--!strict
-- Luck & modifiers (§2.4, §12.14).
-- AGREED: sources are additive and share one global cap. PROPOSAL: every number.

return {
	-- One shared cap on the summed luck of all sources, as a fraction (0.15 = +15%).
	globalCap = 0.15,

	-- How strongly the capped luck value affects each area. 1.0 = full luck value.
	areaWeights = {
		visitChance = 1.0,
		donateChance = 1.0,
		rareSpawn = 1.0,
		donationSize = 0.5,
	},

	sources = {
		Vip = 0.05,
		RareStand = 0.03,
	},
}
