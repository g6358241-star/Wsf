--!strict
-- Transaction history, daily totals and the rolling 24h average (§6.1–6.3). Operates on the
-- persisted `stats` table; keys are strings so the table stays DataStore-safe.

local IncomeStats = {}

export type Record = {
	id: number,
	t: number, -- unix seconds (UTC)
	fromId: string,
	fromName: string,
	amount: number,
	currency: string,
	source: string, -- e.g. "NpcStandDonation", "NpcReturnDonation", "OfflineEarnings", "RobuxPurchase"
	standId: string?,
}

export type Stats = {
	hourly: { [string]: number },
	daily: { [string]: number },
	history: { Record },
	nextId: number,
}

function IncomeStats.new(): Stats
	return { hourly = {}, daily = {}, history = {}, nextId = 1 }
end

-- UTC "YYYY-MM-DD" without relying on os.date (days-from-civil inverse, H. Hinnant).
function IncomeStats.dateKey(t: number): string
	local z = math.floor(t / 86400) + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	if m <= 2 then
		y += 1
	end
	return string.format("%04d-%02d-%02d", y, m, d)
end

local function hourIndex(t: number): number
	return math.floor(t / 3600)
end

export type Options = {
	maxRecords: number,
	dailyDays: number,
	averagedSources: { [string]: boolean },
	primaryCurrency: string,
}

function IncomeStats.record(stats: Stats, entry: Record, opts: Options)
	entry.id = stats.nextId
	stats.nextId += 1
	table.insert(stats.history, entry)
	while #stats.history > opts.maxRecords do
		table.remove(stats.history, 1)
	end

	if entry.currency == opts.primaryCurrency then
		local day = IncomeStats.dateKey(entry.t)
		stats.daily[day] = (stats.daily[day] or 0) + entry.amount
		if opts.averagedSources[entry.source] then
			local key = tostring(hourIndex(entry.t))
			stats.hourly[key] = (stats.hourly[key] or 0) + entry.amount
		end
	end
	IncomeStats.prune(stats, entry.t, opts)
end

function IncomeStats.prune(stats: Stats, now: number, opts: Options)
	local oldestHour = hourIndex(now) - 48
	for key in stats.hourly do
		if (tonumber(key) :: number) < oldestHour then
			stats.hourly[key] = nil
		end
	end
	local oldestDay = IncomeStats.dateKey(now - opts.dailyDays * 86400)
	for key in stats.daily do
		if key < oldestDay then -- ISO dates compare lexicographically
			stats.daily[key] = nil
		end
	end
end

-- Average hourly income over the most recent `windowHours` real hours, including hours spent offline (§6.3).
-- The current partial hour is included, so the window is between windowHours-1 and windowHours long.
function IncomeStats.averageHourly(stats: Stats, now: number, windowHours: number): number
	local first = hourIndex(now) - (windowHours - 1)
	local sum = 0
	for key, amount in stats.hourly do
		if (tonumber(key) :: number) >= first then
			sum += amount
		end
	end
	return sum / windowHours
end

-- Ordered daily totals for the chart: { { date = "YYYY-MM-DD", amount = n }, ... } oldest first.
function IncomeStats.dailySeries(stats: Stats, now: number, days: number): { { date: string, amount: number } }
	local series = {}
	for i = days - 1, 0, -1 do
		local key = IncomeStats.dateKey(now - i * 86400)
		table.insert(series, { date = key, amount = stats.daily[key] or 0 })
	end
	return series
end

return IncomeStats
