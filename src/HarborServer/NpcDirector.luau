-- NPC world director (brief §3, §12.2–12.5). Owns the NPC population, their wallets (NPC world ledger) and the
-- sequence of decisions. It never moves a character itself and never touches profiles directly:
--   movement  -> NPCService adapter (pathfinding, holding at booths, despawn effects)
--   booths    -> Booths (stand snapshots, NPC claims)
--   economy   -> Economy.receiveNpcDonation (atomic NPC -> player credit)
-- Dependencies are injected so the identical code runs in Roblox and in the headless integration test.

local ServerScriptService = game:GetService("ServerScriptService")
local NpcCore = ServerScriptService:WaitForChild("NpcCore")
local NpcConfig = require(NpcCore.Config.Npc)
local EconomyConfig = require(NpcCore.Config.Economy)
local Rng = require(NpcCore.Logic.Rng)
local Ledger = require(NpcCore.Logic.Ledger)
local NpcFactory = require(NpcCore.Logic.NpcFactory)
local NpcBrain = require(NpcCore.Logic.NpcBrain)
local Transactions = require(NpcCore.Logic.Transactions)

local PRIMARY = EconomyConfig.Currency.Primary

export type Movement = {
	-- Creates a character; calls onReady(handle) or onReady(nil) when no rig could be made.
	spawn: (spec: { id: string, name: string, seed: number }, onReady: (handle: any?) -> ()) -> (),
	-- Walks to the booth's visitor side. Exactly one of onArrive / onFail is called.
	visitBooth: (handle: any, boothId: string, onArrive: () -> (), onFail: () -> ()) -> (),
	-- Stays at the booth (facing it) for `seconds`, then calls onDone.
	hold: (handle: any, seconds: number, onDone: () -> ()) -> (),
	-- Strolls to another spot on the map, then calls onDone.
	wander: (handle: any, onDone: () -> ()) -> (),
	despawn: (handle: any) -> (),
}

export type Deps = {
	now: () -> number,
	delay: (seconds: number, fn: () -> ()) -> (),
	movement: Movement,
	booths: any, -- Booths module
	economy: any, -- Economy module
	getPlayer: (userId: number) -> any?,
	notify: (player: any, npcName: string, amount: number, handle: any) -> (),
	publish: ((rows: { any }) -> ())?,
	seed: (number | string)?,
	targetPopulation: (() -> number)?, -- optional override (Studio stress test)
}

type Live = {
	agent: NpcBrain.Agent,
	handle: any,
	txCount: number,
}

local Director = {}
Director.__index = Director

function Director.new(deps: Deps)
	local rng = Rng.new(deps.seed or tostring(deps.now()))
	local self = setmetatable({
		deps = deps,
		rng = rng,
		ledger = Ledger.new(20000),
		tier = NpcFactory.rollWealthTier(rng),
		live = {} :: { [string]: Live },
		active = 0,
		pending = 0, -- spawns waiting for a rig
		nextId = 0,
		departedFunds = 0,
		playerAccounts = {} :: { [number]: Ledger.Account },
		running = false,
		stats = {
			spawned = 0, departed = 0, passes = 0, inspections = 0, decisions = 0, playerDonations = 0,
			playerCoins = 0, npcDonations = 0, npcCoins = 0, refills = 0, standClaims = 0, standGone = 0,
			visitFailures = 0, creditFailures = 0, reasons = {} :: { [string]: number },
		},
	}, Director)
	return self
end

function Director.playerAccount(self, userId: number): Ledger.Account
	local account = self.playerAccounts[userId]
	if not account then
		account = Ledger.newAccount("p:" .. userId)
		self.playerAccounts[userId] = account
	end
	return account
end

function Director.target(self): number
	local override = self.deps.targetPopulation and self.deps.targetPopulation() or 0
	return if override > 0 then math.min(override, NpcConfig.Population.maxActive) else NpcConfig.Population.maxActive
end

-- Every coin that ever entered the NPC world is held by a live NPC, left with a departed NPC, or was
-- received by a player. Returns ok, minted, accounted.
function Director.audit(self): (boolean, number, number)
	local held = self.departedFunds
	for _, l in self.live do
		held += NpcBrain.totalFunds(l.agent)
	end
	for _, account in self.playerAccounts do
		held += Ledger.balance(account, PRIMARY)
	end
	local minted = self.ledger.minted.NpcSpawnWallet or 0
	return held == minted, minted, held
end

local function count(self, reason: string)
	self.stats.reasons[reason] = (self.stats.reasons[reason] or 0) + 1
end

function Director.leave(self, l: Live, reason: string)
	local agent = l.agent
	if self.live[agent.id] ~= l then
		return
	end
	if agent.ownedStandId then
		self.deps.booths.npcRelease(agent.id)
		agent.ownedStandId = nil
	end
	-- Funds leave the server with the NPC; they are never destroyed or handed to anyone else.
	self.departedFunds += NpcBrain.totalFunds(agent)
	self.live[agent.id] = nil
	self.active -= 1
	self.stats.departed += 1
	agent.leaveReason = reason
	count(self, reason)
	self.deps.movement.despawn(l.handle)
end

-- Called by the movement layer when a character is lost (fell out of the world, rig destroyed).
function Director.lost(self, npcId: string)
	local l = self.live[npcId]
	if l then
		self:leave(l, "Lost")
	end
end

function Director.donate(self, l: Live, view: NpcBrain.StandView)
	local agent, rng = l.agent, self.rng
	self.stats.decisions += 1
	local decision = NpcBrain.decideDonation(agent, view, 1, rng)
	if decision.reason == "TooExpensive" or decision.reason == "NoBudget" then
		local top = NpcBrain.refillAmount(agent, self.deps.now(), rng)
		l.txCount += 1
		if top > 0 and Transactions.withdraw(self.ledger, agent.id .. ":r" .. l.txCount, agent, top) then
			self.stats.refills += 1
			decision = NpcBrain.decideDonation(agent, view, 1, rng)
		end
	end
	local amount = decision.amount
	if not amount then
		return
	end
	l.txCount += 1
	local txId = agent.id .. ":d" .. l.txCount
	local ownerId = view.ownerId :: string
	local userId = tonumber(string.match(ownerId, "^p:(%d+)$"))
	if userId then
		local player = self.deps.getPlayer(userId)
		if not player then
			return
		end
		local ok = self.deps.economy.receiveNpcDonation(self.ledger, txId, agent, player, self:playerAccount(userId), amount, view.id)
		if ok then
			self.stats.playerDonations += 1
			self.stats.playerCoins += amount
			self.deps.notify(player, agent.name, amount, l.handle)
		else
			self.stats.creditFailures += 1
		end
	else
		local receiver = self.live[ownerId]
		if receiver and Transactions.npcDonate(self.ledger, txId, agent, NpcBrain.receivingAccount(receiver.agent, EconomyConfig.NpcReceivedFundsTo), amount) then
			self.stats.npcDonations += 1
			self.stats.npcCoins += amount
		end
	end
end

function Director.afterStand(self, l: Live)
	if self.live[l.agent.id] ~= l then
		return
	end
	local reason = NpcBrain.departureReason(l.agent, self.deps.now(), self.rng)
	if reason then
		self:leave(l, reason)
		return
	end
	self.deps.movement.wander(l.handle, function()
		self:step(l)
	end)
end

function Director.runStand(self, l: Live)
	local agent, rng = l.agent, self.rng
	local standId = self.deps.booths.npcClaim({ id = agent.id, name = agent.name }, agent.offers, "Support my stand!", function(n: number)
		return rng:int(1, n)
	end)
	if not standId then
		return false
	end
	agent.ownedStandId = standId
	self.stats.standClaims += 1
	local duration = NpcBrain.standDuration(agent, rng)
	self.deps.movement.visitBooth(l.handle, standId, function()
		-- Stays at its stand (AFK-like) until its own time is up, then leaves (§12.5).
		self.deps.movement.hold(l.handle, duration, function()
			if self.live[agent.id] == l then
				self:leave(l, "StandDone")
			end
		end)
	end, function()
		if self.live[agent.id] == l then
			self:leave(l, "StandUnreachable")
		end
	end)
	return true
end

function Director.step(self, l: Live)
	local agent, rng, deps = l.agent, self.rng, self.deps
	if self.live[agent.id] ~= l then
		return
	end
	if NpcBrain.wantsToClaim(agent, rng) and self:runStand(l) then
		return
	end
	local views = deps.booths.views()
	local stand = NpcBrain.chooseTarget(agent, views, rng)
	if not stand then
		local anyClaimed = false
		for _, v in views do
			if v.ownerId ~= agent.id then
				anyClaimed = true
			end
		end
		if anyClaimed then
			self:leave(l, "SeenAll")
		else
			-- Nobody has a stand yet: keep strolling, but the visit clock still runs.
			local reason = NpcBrain.departureReason(agent, deps.now(), rng)
			if reason then
				self:leave(l, reason)
			else
				deps.movement.wander(l.handle, function()
					self:step(l)
				end)
			end
		end
		return
	end
	local standId, ownerAtChoice = stand.id, stand.ownerId
	deps.movement.visitBooth(l.handle, standId, function()
		if self.live[agent.id] ~= l then
			return
		end
		-- Re-read on arrival: the stand may have been released or re-claimed while the NPC walked (§8.3).
		local view = deps.booths.view(standId)
		if not view or view.ownerId ~= ownerAtChoice or #view.offers == 0 then
			agent.visited[standId] = true
			self.stats.standGone += 1
			self:afterStand(l)
			return
		end
		self.stats.passes += 1
		if not NpcBrain.decideInspect(agent, view, rng) then
			self:afterStand(l)
			return
		end
		self.stats.inspections += 1
		local v = NpcConfig.Visit
		deps.movement.hold(l.handle, rng:range(v.inspectSeconds[1], v.inspectSeconds[2]), function()
			if self.live[agent.id] ~= l then
				return
			end
			-- Decide on the offers as they are now (edits during inspection count, §12.12).
			local current = deps.booths.view(standId)
			if current and current.ownerId == ownerAtChoice and #current.offers > 0 then
				self:donate(l, current)
			end
			self:afterStand(l)
		end)
	end, function()
		agent.visited[standId] = true
		self.stats.visitFailures += 1
		self:afterStand(l)
	end)
end

function Director.spawn(self)
	if not self.running or self.active + self.pending >= self:target() then
		return
	end
	local rng = self.rng
	self.nextId += 1
	local id = "N" .. self.nextId
	local profile = NpcFactory.create(rng, id, self.tier, 0)
	self.pending += 1
	self.deps.movement.spawn({ id = id, name = profile.name, seed = rng:int(1, 2 ^ 30) }, function(handle: any?)
		self.pending -= 1
		if not handle or not self.running then
			if handle then
				self.deps.movement.despawn(handle)
			end
			return
		end
		local agent = NpcBrain.fromProfile(profile, self.deps.now(), rng)
		-- The starting wallet is the only approved way money enters the NPC world (§12.3).
		Ledger.mint(self.ledger, id .. ":spawn", agent.wallet, PRIMARY, profile.wallet, "NpcSpawnWallet")
		Transactions.withdraw(self.ledger, id .. ":w0", agent, NpcBrain.initialWithdrawal(agent, rng))
		local l: Live = { agent = agent, handle = handle, txCount = 0 }
		self.live[id] = l
		self.active += 1
		self.stats.spawned += 1
		self:step(l)
	end)
end

function Director.scheduleArrival(self)
	if not self.running then
		return
	end
	local stress = self.deps.targetPopulation and self.deps.targetPopulation() or 0
	local gap = if stress > 0 and self.active + self.pending < self:target()
		then 0.25 -- stress test: fill up quickly
		else -math.log(math.max(self.rng:next(), 1e-12)) * 60 / NpcConfig.Population.arrivalsPerMinute
	self.deps.delay(gap, function()
		self:spawn()
		self:scheduleArrival()
	end)
end

function Director.leaderboardRows(self): { any }
	local rows = {}
	for userId, account in self.playerAccounts do
		local player = self.deps.getPlayer(userId)
		if player then
			table.insert(rows, { id = "p:" .. userId, name = player.DisplayName, donated = account.donated, raised = account.raised, isPlayer = true })
		end
	end
	for id, l in self.live do
		table.insert(rows, { id = id, name = l.agent.name, donated = NpcBrain.donated(l.agent), raised = NpcBrain.raised(l.agent), isPlayer = false })
	end
	table.sort(rows, function(a, b)
		if a.raised ~= b.raised then
			return a.raised > b.raised
		end
		return a.id < b.id
	end)
	return rows
end

function Director.start(self)
	if self.running then
		return
	end
	self.running = true
	for i = 1, NpcConfig.Population.initialBurst do
		self.deps.delay(i * 0.5, function()
			self:spawn()
		end)
	end
	self:scheduleArrival()
	local publish = self.deps.publish
	if publish then
		local function loop()
			if not self.running then
				return
			end
			publish(self:leaderboardRows())
			self.deps.delay(2, loop)
		end
		self.deps.delay(2, loop)
	end
end

function Director.stop(self)
	self.running = false
	for _, l in self.live do
		self:leave(l, "ServerClosing")
	end
end

return Director
