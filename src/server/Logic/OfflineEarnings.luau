--!strict
-- Offline earnings (§6.3–6.4). Pure math; the service decides when to snapshot and credit.

local OfflineConfig = require("../Config/Offline")

local OfflineEarnings = {}

local DAY = 86400

local function smoothstep(x: number): number
	return x * x * (3 - 2 * x)
end

-- Rate (fraction of average hourly income) after `daysAway` days, eased between config keypoints.
function OfflineEarnings.rateAt(daysAway: number, cfg: typeof(OfflineConfig)?): number
	local c = cfg or OfflineConfig
	if daysAway >= c.stopAfterDays then
		return 0
	end
	local points = c.rateKeypoints
	if daysAway <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if daysAway <= b[1] then
			local x = (daysAway - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * smoothstep(x)
		end
	end
	return 0
end

export type Result = {
	amount: number, -- whole primary currency to credit
	exact: number, -- before rounding
	averageHourly: number,
	awaySeconds: number,
	creditedHours: number,
}

-- `averageHourly` is the snapshot taken at logout (PROPOSAL §6.5: snapshot rather than rolling window).
function OfflineEarnings.compute(averageHourly: number, awaySeconds: number, cfg: typeof(OfflineConfig)?): Result
	local c = cfg or OfflineConfig
	local result = { amount = 0, exact = 0, averageHourly = averageHourly, awaySeconds = awaySeconds, creditedHours = 0 }
	if averageHourly <= 0 or awaySeconds < c.minimumAwaySeconds then
		return result
	end
	local stopSeconds = c.stopAfterDays * DAY
	local endSeconds = math.min(awaySeconds, stopSeconds)
	local step = c.integrationStepHours * 3600
	local total = 0
	local t = 0
	while t < endSeconds do
		local dt = math.min(step, endSeconds - t)
		local mid = (t + dt / 2) / DAY
		total += averageHourly * OfflineEarnings.rateAt(mid, c) * (dt / 3600)
		t += dt
	end
	if c.maxCreditPerCollection then
		total = math.min(total, c.maxCreditPerCollection)
	end
	result.exact = total
	result.amount = math.floor(total)
	result.creditedHours = endSeconds / 3600
	return result
end

return OfflineEarnings
