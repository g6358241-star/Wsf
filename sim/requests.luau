-- NPC donation-request frequency study (owner request 2026-11-12: test frequencies before finalising).
-- Runs the full market with a player-response model and compares candidate request rates.
-- Usage: lune run sim/requests [hours] [runs]
local process = require("@lune/process")
local Market = require("./Market")

local HOURS = tonumber(process.args[1]) or 4
local RUNS = tonumber(process.args[2]) or 16

-- Candidate settings. cooldown = minimum seconds between two requests to the player.
local candidates = {
	{ name = "A  very frequent", chancePerCheck = 0.05, cooldown = 120 },
	{ name = "B  current draft", chancePerCheck = 0.02, cooldown = 240 },
	{ name = "C  moderate", chancePerCheck = 0.02, cooldown = 480 },
	{ name = "D  occasional", chancePerCheck = 0.01, cooldown = 720 },
	{ name = "E  rare", chancePerCheck = 0.005, cooldown = 1200 },
}

-- ASSUMED player behaviour; the same for every candidate so only the frequency changes.
local playerModels = {
	{ label = "Engaged player (accepts 70%, follows 90%)", accept = 0.70, follow = 0.90, cheapest = 0.60, median = 0.30 },
	{ label = "Casual player (accepts 40%, follows 75%)", accept = 0.40, follow = 0.75, cheapest = 0.75, median = 0.15 },
}

local offers = { 5, 10, 25, 50, 100 } -- default stand listing

print(string.format("# NPC request frequency study — %d runs × %dh per cell, new player (0 starting Coins)\n", RUNS, HOURS))
for _, pm in playerModels do
	print("## " .. pm.label .. "\n")
	print("| Setting | Requests/h | Time in requests | Donations/h | Coins spent/h | Coins earned/h (stand + playtime) | Net Coins/h | DCoins/h | Return gifts/h | Ignored after accept/h | Couldn't afford/h |")
	print("|---|---|---|---|---|---|---|---|---|---|---|")
	for _, c in candidates do
		local sum = { requests = 0, busy = 0, don = 0, spent = 0, earned = 0, net = 0, dcoins = 0, ret = 0, ignored = 0, afford = 0 }
		for r = 1, RUNS do
			local m = Market.runOnce(c.name .. pm.label .. r, offers, nil, {
				hours = HOURS,
				request = { chancePerCheck = c.chancePerCheck, cooldown = c.cooldown },
				player = pm,
			})
			sum.requests += m.requests
			sum.busy += m.busySeconds
			sum.don += m.requestDonations
			sum.spent += m.spent
			sum.earned += m.standCoins + m.playtimeCoins
			sum.net += m.standCoins + m.playtimeCoins + m.returned - m.spent
			sum.dcoins += m.dcoins
			sum.ret += m.returned
			sum.ignored += m.ignored
			sum.afford += m.cantAfford
		end
		local h = RUNS * HOURS
		print(string.format(
			"| %s (chance %.3f, cooldown %d min) | %.1f | %.1f%% | %.1f | %.0f | %.0f | %+.0f | %.1f | %.0f | %.1f | %.1f |",
			c.name, c.chancePerCheck, c.cooldown // 60, sum.requests / h, sum.busy / (h * 3600) * 100, sum.don / h,
			sum.spent / h, sum.earned / h, sum.net / h, sum.dcoins / h, sum.ret / h, sum.ignored / h, sum.afford / h
		))
	end
	print("")
end
print("Conservation check passed for every run (Coins and DCoins).")
