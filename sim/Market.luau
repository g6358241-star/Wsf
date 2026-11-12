-- Headless market simulation shared by sim/balance and sim/requests. Runs the real NpcBrain, NpcFactory
-- and Transactions code against a model of the 48-booth CloudHarbor market.
local Rng = require("../src/NpcCore/Logic/Rng")
local Ledger = require("../src/NpcCore/Logic/Ledger")
local NpcFactory = require("../src/NpcCore/Logic/NpcFactory")
local NpcBrain = require("../src/NpcCore/Logic/NpcBrain")
local Transactions = require("../src/NpcCore/Logic/Transactions")
local NpcConfig = require("../src/NpcCore/Config/Npc")
local EconomyConfig = require("../src/NpcCore/Config/Economy")

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

export type Options = {
	hours: number,
	-- NPC request model; nil = NpcConfig.Request values, player ignores requests (balance runs).
	request: { chancePerCheck: number, cooldown: number }?,
	player: { accept: number, follow: number, cheapest: number, median: number }?,
}

local function runOnce(seed: string, playerOffers: { number }, forceTier: string?, opts: Options)
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
	local endT = opts.hours * 3600
	local reqCfg = opts.request or { chancePerCheck = NpcConfig.Request.chancePerCheck, cooldown = NpcConfig.Request.playerCooldownSeconds }
	local busyUntil = 0
	local nextId, active, peak = 0, 0, 0
	local departedFunds = 0
	local m = {
		passes = 0, inspections = 0, donations = {}, firstDonationPasses = nil :: number?, npcToNpc = 0, requests = 0, arrivals = 0, reasons = {},
		accepted = 0, declined = 0, ignored = 0, cantAfford = 0, declinedAtStand = 0, requestDonations = 0, spent = 0, dcoins = 0,
		returned = 0, returnCount = 0, busySeconds = 0, playtimeCoins = 0, standCoins = 0,
	}
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
		Ledger.mint(ledger, id .. ":spawn", agent.wallet, "Coins", profile.wallet, "NpcSpawnWallet")
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
	if opts.player then
		push(queue, { t = 300, kind = "Playtime", agent = nil })
	end
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
				local npc = ev.agent
				if ev.t - lastRequestAt >= reqCfg.cooldown and ev.t >= busyUntil and rng:chance(reqCfg.chancePerCheck * npc.traits.sociability) then
					lastRequestAt = ev.t
					m.requests += 1
					local pm = opts.player
					if pm then
						-- Player response model (ASSUMPTION, see docs/REQUEST_FREQUENCY.md).
						local busy = 5 -- reading the prompt, camera focus
						if not rng:chance(pm.accept) then
							m.declined += 1
						elseif not rng:chance(pm.follow) then
							m.accepted += 1
							m.ignored += 1
							busy += 15
						else
							m.accepted += 1
							busy += rng:range(20, 40) + 5 -- follow the NPC to its stand, choose an amount
							local affordable = {}
							for _, amount in npc.offers do
								if amount <= player.balances.Coins then
									table.insert(affordable, amount)
								end
							end
							local roll = rng:next()
							if #affordable == 0 then
								m.cantAfford += 1
							elseif roll > pm.cheapest + pm.median then
								m.declinedAtStand += 1
							else
								local amount = if roll <= pm.cheapest then affordable[1] else affordable[math.ceil(#affordable / 2)]
								local res = Transactions.playerDonateToNpc(ledger, "req" .. m.requests, player, npc, amount, 1, rng)
								if res.ok then
									m.requestDonations += 1
									m.spent += amount
									m.dcoins += res.secondary
									m.returned += res.returned
									if res.returned > 0 then
										m.returnCount += 1
									end
								end
							end
						end
						busyUntil = ev.t + busy
						m.busySeconds += busy
					end
				end
				push(queue, { t = ev.t + NpcConfig.Request.checkIntervalSeconds, kind = "RequestCheck", agent = ev.agent })
			elseif ev.kind == "Playtime" then
				-- Existing playtime reward (HarborShared.Config: 50 Coins per 5 minutes), a legitimate Coins source.
				Ledger.mint(ledger, "play" .. ev.t, player, "Coins", 50, "PlaytimeReward")
				m.playtimeCoins += 50
				push(queue, { t = ev.t + 300, kind = "Playtime", agent = nil })
			end
		end
	end

	-- Conservation: every coin minted into NPC wallets is held by a live NPC, a departed NPC, or the player.
	local live = 0
	for _, a in agents do
		live += NpcBrain.totalFunds(a)
	end
	local minted = (ledger.minted.NpcSpawnWallet or 0) + (ledger.minted.PlaytimeReward or 0)
	assert(live + departedFunds + player.balances.Coins == minted, "currency not conserved in run " .. seed)

	m.tier = tier.id
	m.peak = peak
	for _, d in m.donations do
		m.standCoins += d.amount
	end
	m.finalCoins = player.balances.Coins
	m.finalDCoins = player.balances.DCoins
	assert(player.balances.DCoins == m.dcoins, "DCoins came from somewhere other than donations to NPCs in run " .. seed)
	return m
end
return { runOnce = runOnce, percentile = percentile, STAND_COUNT = STAND_COUNT }
