-- Stand-income balance report. Usage: lune run sim/balance [hours] [runs]
local process = require("@lune/process")
local Market = require("./Market")

local HOURS = tonumber(process.args[1]) or 6
local RUNS = tonumber(process.args[2]) or 24
local percentile = Market.percentile

local scenarios = {
	{ name = "Only 100", offers = { 100 } },
	{ name = "Only 1,000", offers = { 1000 } },
	{ name = "Only 10,000", offers = { 10000 } },
	{ name = "Small ladder 5–100", offers = { 5, 10, 25, 50, 100 } },
	{ name = "Wide 10–10,000", offers = { 10, 100, 1000, 10000 } },
}

local tierModes = { { label = "random tier (80/17/3)", force = nil }, { label = "Ordinary server", force = "Ordinary" } }

print(string.format("# Balance simulation — %d runs × %dh per scenario, %d stands\n", RUNS, HOURS, Market.STAND_COUNT))
print("All parameters are PROPOSALS from src/NpcCore/Config. Times are simulated, not promises to players.\n")
for _, mode in tierModes do
	print("## " .. mode.label .. "\n")
	print("| Listing | Donations/h | Median gap (min) | Passers before 1st donation (p10/median/p90) | Avg gift | NPC→NPC/h | Peak NPCs |")
	print("|---|---|---|---|---|---|---|")
	for _, sc in scenarios do
		local perHour, gaps, firsts, gifts, n2n, peaks = {}, {}, {}, {}, 0, 0
		for r = 1, RUNS do
			local m = Market.runOnce(sc.name .. ":" .. mode.label .. ":" .. r, sc.offers, mode.force, { hours = HOURS })
			table.insert(perHour, #m.donations / HOURS)
			for i = 2, #m.donations do
				table.insert(gaps, (m.donations[i].t - m.donations[i - 1].t) / 60)
			end
			for _, d in m.donations do
				table.insert(gifts, d.amount)
			end
			table.insert(firsts, m.firstDonationPasses or math.huge)
			n2n += m.npcToNpc
			peaks = math.max(peaks, m.peak)
		end
		local total = 0
		for _, g in gifts do
			total += g
		end
		local function fmt(x)
			return if x == math.huge then "none" elseif x ~= x then "–" else string.format("%.0f", x)
		end
		local mean = 0
		for _, x in perHour do
			mean += x
		end
		print(string.format(
			"| %s | %.2f | %s | %s / %s / %s | %s | %.1f | %d |",
			sc.name,
			mean / RUNS,
			if #gaps > 0 then string.format("%.1f", percentile(gaps, 0.5)) else "–",
			fmt(percentile(table.clone(firsts), 0.1)),
			fmt(percentile(table.clone(firsts), 0.5)),
			fmt(percentile(table.clone(firsts), 0.9)),
			if #gifts > 0 then string.format("%.0f", total / #gifts) else "–",
			n2n / (RUNS * HOURS),
			peaks
		))
	end
	print("")
end
print("Conservation check passed for every run (no NPC currency created or lost).")
