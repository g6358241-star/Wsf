-- Headless balance simulation. Runs the real NpcBrain/NpcFactory/Transactions code against a
-- model of the 48-booth CloudHarbor market and reports how often the player's stand receives
-- donations under different listings. Usage: lune run sim/balance [hours] [runs]
local process = require("@lune/process")
local Rng = require("../src/server/Logic/Rng")
local Ledger = require("../src/server/Logic/Ledger")
local NpcFactory = require("../src/server/Logic/NpcFactory")
local NpcBrain = require("../src/server/Logic/NpcBrain")
local Transactions = require("../src/server/Logic/Transactions")
local NpcConfig = require("../src/server/Config/Npc")
local EconomyConfig = require("../src/server/Config/Economy")

local HOURS = tonumber(process.args[1]) or 6
local RUNS = tonumber(process.args[2]) or 24
local STAND_COUNT = 48 -- CloudHarbor/Booths

type Event = { t: number, kind: string, agent: any }

local function push(queue: { Event }, ev: Event)
	local i = #queue + 1
	queue[i] = ev
	while i > 1 and queue[i - 1].t > ev.t do -- small queue; insertion keeps it sorted
		queue[i], queue[i - 1] = queue[i - 1], queue[i]
		i -= 1
	end
end

local function percentile(list: { number }, p: number): number
	if #list == 0 then
		return 0 / 0
	end
	table.sort(list)
	return list[math.clamp(math.floor(p * (#list - 1) + 1.5), 1, #list)]
end

local function runOnce(seed: string, playerOffers: { number }, forceTier: string?)
	local rng = Rng.new(seed)
	local ledger = Ledger.new(200000)
	local tier = NpcFactory.rollWealthTier(rng)
	if forceTier then
		for _, t in NpcConfig.wealthTiers do
			if t.id == forceTier then
				tier = t
			end
		end
	end
	local v = NpcConfig.Visit
	local pop = NpcConfig.Population
	local player = Ledger.newAccount("player")
	local stands = {}
	for i = 1, STAND_COUNT do
		stands[i] = { id = "S" .. i, ownerId = nil, offers = {}, appeal = 0.5, luck = 0 }
	end
	stands[1].ownerId = "player"
	stands[1].offers = playerOffers
	local agents: { [string]: any } = {}
	local queue: { Event } = {}
	local endT = HOURS * 3600
	local nextId, active, peak = 0, 0, 0
	local departedFunds = 0
	local m = { passes = 0, inspections = 0, donations = {}, firstDonationPasses = nil :: number?, npcToNpc = 0, requests = 0, arrivals = 0, reasons = {} }
	local lastRequestAt = -math.huge

	local function travel()
		return rng:range(v.travelSeconds[1], v.travelSeconds[2])
	end

	local function leave(agent, reason)
		if agent.ownedStandId then
			for _, s in stands do
				if s.id == agent.ownedStandId then
					s.ownerId, s.offers = nil, {}
				end
			end
			agent.ownedStandId = nil
		end
		departedFunds += NpcBrain.totalFunds(agent)
		agents[agent.id] = nil
		active -= 1
		m.reasons[reason] = (m.reasons[reason] or 0) + 1
	end

	local function scheduleArrival(t)
		local gap = -math.log(math.max(rng:next(), 1e-12)) * 60 / pop.arrivalsPerMinute
		push(queue, { t = t + gap, kind = "Spawn", agent = nil })
	end

	local function spawn(t)
		if active >= pop.maxActive then
			return
		end
		nextId += 1
		local id = "N" .. nextId
		local profile = NpcFactory.create(rng, id, tier, 0)
		local agent = NpcBrain.fromProfile(profile, t, rng)
		Ledger.mint(ledger, id .. ":spawn", agent.wallet, "Primary", profile.wallet, "NpcSpawnWallet")
		Transactions.withdraw(ledger, id .. ":w0", agent, NpcBrain.initialWithdrawal(agent, rng))
		agents[id] = agent
		active += 1
		m.arrivals += 1
		peak = math.max(peak, active)
		push(queue, { t = t + travel(), kind = "Step", agent = agent })
	end

	local function step(agent, t)
		if NpcBrain.wantsToClaim(agent, rng) then
			local free = {}
			for _, s in stands do
				if not s.ownerId then
					table.insert(free, s)
				end
			end
			if #free > 0 then
				local s = free[rng:int(1, #free)]
				s.ownerId, s.offers, s.appeal = agent.id, agent.offers, rng:range(0.3, 0.7)
				agent.ownedStandId = s.id
				push(queue, { t = t + NpcBrain.standDuration(agent, rng), kind = "StandEnd", agent = agent })
				push(queue, { t = t + NpcConfig.Request.checkIntervalSeconds, kind = "RequestCheck", agent = agent })
				return
			end
		end
		local stand = NpcBrain.chooseTarget(agent, stands, rng)
		if not stand then
			return leave(agent, "NothingLeft")
		end
		local isPlayer = stand.ownerId == "player"
		if isPlayer then
			m.passes += 1
		end
		local dwell = 0
		if NpcBrain.decideInspect(agent, stand, rng) then
			if isPlayer then
				m.inspections += 1
			end
			dwell = rng:range(v.inspectSeconds[1], v.inspectSeconds[2])
			local decision = NpcBrain.decideDonation(agent, stand, 1, rng)
			if decision.reason == "TooExpensive" or decision.reason == "NoBudget" then
				local top = NpcBrain.refillAmount(agent, t, rng)
				if top > 0 and Transactions.withdraw(ledger, agent.id .. ":r" .. t, agent, top) then
					decision = NpcBrain.decideDonation(agent, stand, 1, rng)
				end
			end
			if decision.amount then
				local receiver = if isPlayer then player else NpcBrain.receivingAccount(agents[stand.ownerId :: string], EconomyConfig.NpcReceivedFundsTo)
				if Transactions.npcDonate(ledger, agent.id .. ":d" .. agent.donationsMade, agent, receiver, decision.amount) then
					if isPlayer then
						table.insert(m.donations, { t = t, amount = decision.amount })
						m.firstDonationPasses = m.firstDonationPasses or m.passes
					else
						m.npcToNpc += 1
					end
				end
			end
		end
		local reason = NpcBrain.departureReason(agent, t, rng)
		if reason then
			return leave(agent, reason)
		end
		push(queue, { t = t + dwell + rng:range(v.idleSeconds[1], v.idleSeconds[2]) + travel(), kind = "Step", agent = agent })
	end

	for _ = 1, pop.initialBurst do
		spawn(rng:range(0, 30))
	end
	scheduleArrival(0)
	while #queue > 0 do
		local ev = table.remove(queue, 1) :: Event
		if ev.t > endT then
			break
		end
		if ev.kind == "Spawn" then
			spawn(ev.t)
			scheduleArrival(ev.t)
		elseif agents[ev.agent and ev.agent.id or ""] == ev.agent then
			if ev.kind == "Step" then
				step(ev.agent, ev.t)
			elseif ev.kind == "StandEnd" then
				leave(ev.agent, "StandDone")
			elseif ev.kind == "RequestCheck" then
				if ev.t - lastRequestAt >= NpcConfig.Request.playerCooldownSeconds and NpcBrain.wantsToRequest(ev.agent, rng) then
					lastRequestAt = ev.t
					m.requests += 1
				end
				push(queue, { t = ev.t + NpcConfig.Request.checkIntervalSeconds, kind = "RequestCheck", agent = ev.agent })
			end
		end
	end

	-- Conservation: every coin minted into NPC wallets is held by a live NPC, a departed NPC, or the player.
	local live = 0
	for _, a in agents do
		live += NpcBrain.totalFunds(a)
	end
	local minted = ledger.minted.NpcSpawnWallet or 0
	assert(live + departedFunds + player.balances.Primary == minted, "currency not conserved in run " .. seed)

	m.tier = tier.id
	m.peak = peak
	m.avgActive = nil
	return m
end

local scenarios = {
	{ name = "Only 100", offers = { 100 } },
	{ name = "Only 1,000", offers = { 1000 } },
	{ name = "Only 10,000", offers = { 10000 } },
	{ name = "Small ladder 5–100", offers = { 5, 10, 25, 50, 100 } },
	{ name = "Wide 10–10,000", offers = { 10, 100, 1000, 10000 } },
}

local tierModes = { { label = "random tier (80/17/3)", force = nil }, { label = "Ordinary server", force = "Ordinary" } }

print(string.format("# Balance simulation — %d runs × %dh per scenario, %d stands\n", RUNS, HOURS, STAND_COUNT))
print("All parameters are PROPOSALS from src/server/Config. Times are simulated, not promises to players.\n")
for _, mode in tierModes do
	print("## " .. mode.label .. "\n")
	print("| Listing | Donations/h | Median gap (min) | Passers before 1st donation (p10/median/p90) | Avg gift | NPC→NPC/h | Requests/h | Peak NPCs |")
	print("|---|---|---|---|---|---|---|---|")
	for _, sc in scenarios do
		local perHour, gaps, firsts, gifts, n2n, reqs, peaks = {}, {}, {}, {}, 0, 0, 0
		for r = 1, RUNS do
			local m = runOnce(sc.name .. ":" .. mode.label .. ":" .. r, sc.offers, mode.force)
			table.insert(perHour, #m.donations / HOURS)
			for i = 2, #m.donations do
				table.insert(gaps, (m.donations[i].t - m.donations[i - 1].t) / 60)
			end
			for _, d in m.donations do
				table.insert(gifts, d.amount)
			end
			table.insert(firsts, m.firstDonationPasses or math.huge)
			n2n += m.npcToNpc
			reqs += m.requests
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
			"| %s | %.2f | %s | %s / %s / %s | %s | %.1f | %.1f | %d |",
			sc.name,
			mean / RUNS,
			if #gaps > 0 then string.format("%.1f", percentile(gaps, 0.5)) else "–",
			fmt(percentile(table.clone(firsts), 0.1)),
			fmt(percentile(table.clone(firsts), 0.5)),
			fmt(percentile(table.clone(firsts), 0.9)),
			if #gifts > 0 then string.format("%.0f", total / #gifts) else "–",
			n2n / (RUNS * HOURS),
			reqs / (RUNS * HOURS),
			peaks
		))
	end
	print("")
end
print("Conservation check passed for every run (no NPC currency created or lost).")
