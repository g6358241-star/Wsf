--!strict
-- NPC decision core (§3, §12.2–12.5). Pure and engine-agnostic: the live NPC controller and the
-- headless balance simulator call the same functions, so behaviour is identical in both.
-- Movement/pathfinding stays in the existing NPCService; this module only decides.
--
-- Stages are separate (§3.5): spawn (SpawnDirector/NpcFactory) -> pass a stand (chooseTarget)
-- -> stop and inspect (decideInspect) -> donate or decline (decideDonation).

local NpcConfig = require("../Config/Npc")
local Ledger = require("./Ledger")
local Luck = require("./Luck")
local Rng = require("./Rng")
local NpcFactory = require("./NpcFactory")

local NpcBrain = {}

export type Agent = {
	id: string,
	name: string,
	archetype: NpcConfig.Archetype,
	traits: { [string]: number },
	offers: { number },
	wallet: Ledger.Account, -- total wallet
	budget: Ledger.Account, -- separate donation budget (§12.3)
	arrivedAt: number,
	visitSeconds: number,
	maxInspections: number,
	claimAfterVisits: number,
	visited: { [string]: boolean },
	passes: number,
	inspections: number,
	donationsMade: number,
	ownedStandId: string?,
	standUntil: number?,
	leaveReason: string?,
}

-- Read-only stand snapshot supplied by the caller (StandService in game, the sim offline).
export type StandView = {
	id: string,
	ownerId: string?,
	offers: { number },
	appeal: number, -- 0..1 presentation score; a moderate modifier only (§3.4, §7.3)
	luck: number, -- owner's capped luck total (Luck.total)
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local PRIMARY = require("../Config/Economy").Currency.Primary

function NpcBrain.fromProfile(profile: NpcFactory.Profile, now: number, rng: Rng.Rng): Agent
	local tr = profile.traits
	local cfg = NpcConfig
	return {
		id = profile.id,
		name = profile.name,
		archetype = profile.archetype,
		traits = tr,
		offers = profile.offers,
		wallet = Ledger.newAccount(profile.id .. ":wallet"),
		budget = Ledger.newAccount(profile.id .. ":budget"),
		arrivedAt = now,
		visitSeconds = lerp(cfg.Departure.visitSeconds[1], cfg.Departure.visitSeconds[2], tr.patience) * rng:range(0.8, 1.2),
		maxInspections = math.floor(lerp(cfg.Departure.maxInspections[1], cfg.Departure.maxInspections[2], tr.curiosity) + 0.5),
		claimAfterVisits = rng:int(cfg.NpcStand.claimAfterVisits[1], cfg.NpcStand.claimAfterVisits[2]),
		visited = {},
		passes = 0,
		inspections = 0,
		donationsMade = 0,
	}
end

function NpcBrain.donated(agent: Agent): number
	return agent.budget.donated + agent.wallet.donated
end

function NpcBrain.raised(agent: Agent): number
	return agent.budget.raised + agent.wallet.raised
end

function NpcBrain.totalFunds(agent: Agent): number
	return Ledger.balance(agent.wallet, PRIMARY) + Ledger.balance(agent.budget, PRIMARY)
end

-- Account that receives donations made to this NPC (OPEN decision, Config.Economy.NpcReceivedFundsTo).
function NpcBrain.receivingAccount(agent: Agent, receivedTo: string): Ledger.Account
	return if receivedTo == "budget" then agent.budget else agent.wallet
end

-- How much of the wallet the NPC sets aside on arrival. May be nothing (§12.3).
function NpcBrain.initialWithdrawal(agent: Agent, rng: Rng.Rng): number
	local f = NpcConfig.Finance
	if rng:chance(f.nothingWithdrawnChance) then
		return 0
	end
	local fraction = math.clamp(rng:normal(f.initialWithdrawMean, f.initialWithdrawSpread) * (0.5 + agent.traits.generosity), 0, 1)
	return math.floor(Ledger.balance(agent.wallet, PRIMARY) * fraction)
end

-- The NPC's own choice whether to top up its budget; never automatic (§12.3).
function NpcBrain.refillAmount(agent: Agent, now: number, rng: Rng.Rng): number
	local f = NpcConfig.Finance
	local wallet = Ledger.balance(agent.wallet, PRIMARY)
	if wallet <= 0 then
		return 0
	end
	local elapsed = math.clamp((now - agent.arrivedAt) / agent.visitSeconds, 0, 1)
	if not rng:chance(f.refillChanceScale * agent.traits.generosity * (1 - elapsed)) then
		return 0
	end
	return math.max(1, math.floor(wallet * rng:range(f.refillFraction[1], f.refillFraction[2])))
end

-- Stage 1: which claimed stand to walk past next. Unvisited stands are equally likely; presentation
-- does not bias this stage, so "passers" are counted fairly.
function NpcBrain.chooseTarget(agent: Agent, stands: { StandView }, rng: Rng.Rng): StandView?
	local candidates: { StandView } = {}
	for _, stand in stands do
		if stand.ownerId and stand.ownerId ~= agent.id and not agent.visited[stand.id] and #stand.offers > 0 then
			table.insert(candidates, stand)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:int(1, #candidates)]
end

-- Stage 2: does the NPC stop and look? Appeal and luck nudge this moderately.
function NpcBrain.inspectChance(agent: Agent, stand: StandView): number
	local v = NpcConfig.Visit
	local base = v.inspectBase + v.inspectCuriosityWeight * agent.traits.curiosity
	local appealMod = 1 + v.appealVisitWeight * (stand.appeal - 0.5) * agent.traits.appealSensitivity
	return math.clamp(base * appealMod * Luck.multiplier(stand.luck, "visitChance"), 0, 0.95)
end

function NpcBrain.decideInspect(agent: Agent, stand: StandView, rng: Rng.Rng): boolean
	agent.passes += 1
	agent.visited[stand.id] = true
	local inspect = rng:chance(NpcBrain.inspectChance(agent, stand))
	if inspect then
		agent.inspections += 1
	end
	return inspect
end

-- Comfortable single gift for this NPC right now.
function NpcBrain.comfortAmount(agent: Agent, luck: number): number
	local d = NpcConfig.Decision
	local budget = Ledger.balance(agent.budget, PRIMARY)
	local fraction = lerp(d.comfortFractionMin, d.comfortFractionMax, agent.traits.generosity * agent.traits.riskTolerance)
	return math.max(1, budget * fraction * Luck.multiplier(luck, "donationSize"))
end

-- Willingness 0..1 to give `amount`: full at or below the comfortable gift, falling off above it.
function NpcBrain.offerFit(amount: number, comfort: number): number
	if amount <= comfort then
		return 1
	end
	local x = math.log(amount / comfort)
	local sigma = NpcConfig.Decision.overComfortSigma
	return math.exp(-(x * x) / (2 * sigma * sigma))
end

export type Decision = {
	amount: number?, -- nil = declined
	reason: string, -- "Donated" | "Declined" | "TooExpensive" | "AsksTooMuch" | "NoBudget"
	chance: number, -- the donation probability that was rolled (0 when not rolled)
}

-- Stage 3: donate or decline, and which listed amount. `willingness` folds in the NPC's opinion of
-- the stand owner (Relationships.willingness), 1 for NPC-owned stands.
function NpcBrain.decideDonation(agent: Agent, stand: StandView, willingness: number, rng: Rng.Rng): Decision
	local d = NpcConfig.Decision
	local budget = Ledger.balance(agent.budget, PRIMARY)
	if budget <= 0 then
		return { amount = nil, reason = "NoBudget", chance = 0 }
	end
	local affordable: { number } = {}
	for _, amount in stand.offers do
		if amount <= budget then
			table.insert(affordable, amount)
		end
	end
	if #affordable == 0 then
		return { amount = nil, reason = "TooExpensive", chance = 0 }
	end

	local comfort = NpcBrain.comfortAmount(agent, stand.luck)
	local cheapest, bestFit = math.huge, 0
	for _, amount in affordable do
		cheapest = math.min(cheapest, amount)
		bestFit = math.max(bestFit, NpcBrain.offerFit(amount, comfort))
	end
	if agent.traits.pickiness > 0.6 and cheapest > comfort * d.pickyRejectRatio then
		return { amount = nil, reason = "AsksTooMuch", chance = 0 }
	end

	local tr = agent.traits
	local generosityMod = (1 - d.generosityWeight / 2) + d.generosityWeight * tr.generosity
	local appealMod = 1 + d.appealDecisionWeight * (stand.appeal - 0.5) * 2 * tr.pickiness
	local p = agent.archetype.donateChance
		* generosityMod
		* appealMod
		* Luck.multiplier(stand.luck, "donateChance")
		* willingness
		* d.repeatDonationDecay ^ agent.donationsMade
		* bestFit
	p = math.clamp(p, 0, d.maxChance)

	if not rng:chance(p) then
		return { amount = nil, reason = "Declined", chance = p }
	end

	-- Prefer amounts near the comfortable gift, from either side.
	local weights = {}
	for i, amount in affordable do
		local x = math.log(amount / comfort)
		weights[i] = NpcBrain.offerFit(amount, comfort) * math.exp(-(x * x) / 2)
	end
	return { amount = affordable[rng:weightedIndex(weights)], reason = "Donated", chance = p }
end

-- Departure check after each stand (§3.1). Returns a reason when the NPC decides to leave.
function NpcBrain.departureReason(agent: Agent, now: number, rng: Rng.Rng): string?
	if now - agent.arrivedAt >= agent.visitSeconds then
		return "Tired"
	end
	if agent.inspections >= agent.maxInspections then
		return "SeenEnough"
	end
	if NpcBrain.totalFunds(agent) <= 0 then
		return "OutOfMoney"
	end
	if rng:chance(NpcConfig.Departure.leaveHazardPerStand * (1.2 - agent.traits.patience)) then
		return "Bored"
	end
	return nil
end

-- Whether the NPC wants to run its own stand once it has looked around a bit (§12.5).
function NpcBrain.wantsToClaim(agent: Agent, rng: Rng.Rng): boolean
	return agent.ownedStandId == nil and agent.passes >= agent.claimAfterVisits and rng:chance(agent.traits.standAmbition)
end

function NpcBrain.standDuration(agent: Agent, rng: Rng.Rng): number
	local s = NpcConfig.NpcStand.afkSeconds
	return lerp(s[1], s[2], agent.traits.patience) * rng:range(0.8, 1.2)
end

-- Periodic check while the NPC owns a stand: does it go and ask the player for support? (§5, §12.8)
function NpcBrain.wantsToRequest(agent: Agent, rng: Rng.Rng): boolean
	return agent.ownedStandId ~= nil and rng:chance(NpcConfig.Request.chancePerCheck * agent.traits.sociability)
end

-- How long the NPC keeps calling a player who accepted but hasn't followed (§12.8 step 9).
function NpcBrain.callPersistence(agent: Agent): number
	local r = NpcConfig.Request.maxCallSeconds
	return lerp(r[1], r[2], agent.traits.patience)
end

-- Personality-dependent reaction to an immediate decline (§12.8 step 8). Returns a reaction key.
function NpcBrain.declineReaction(agent: Agent, rng: Rng.Rng): string
	local tr = agent.traits
	local weights = {
		0.5 + tr.patience, -- Calm
		tr.sensitivity, -- Upset
		0.3 + tr.curiosity * 0.5, -- Surprised
		0.2 + tr.sociability * 0.6, -- Joke
	}
	return ({ "Calm", "Upset", "Surprised", "Joke" })[rng:weightedIndex(weights)]
end

return NpcBrain
