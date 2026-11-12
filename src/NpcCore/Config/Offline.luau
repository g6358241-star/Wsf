--!strict
-- Offline earnings (§6.3–6.5, §10).
-- AGREED: average over the most recent 24 real hours; ~5% when recently active, ~1% after 4–5 days, 0% at 14 days.
-- PROPOSAL: keypoint shape, smoothstep easing between keypoints, snapshot at logout, floor rounding.

return {
	averageWindowHours = 24, -- AGREED
	stopAfterDays = 14, -- AGREED

	-- {daysAway, rate}. Rates are eased between neighbouring keypoints so there is no abrupt jump.
	rateKeypoints = {
		{ 0, 0.05 },
		{ 1, 0.05 },
		{ 4.5, 0.01 },
		{ 10, 0.01 },
		{ 14, 0.00 },
	},

	integrationStepHours = 0.25,
	minimumAwaySeconds = 300, -- shorter absences are not credited
	maxCreditPerCollection = nil :: number?, -- OPEN: nil = no cap beyond the 14-day stop

	-- PROPOSAL (§6.5): income sources that count toward the 24h average.
	countedSources = {
		NpcStandDonation = true,
		NpcReturnDonation = true,
	},
}
