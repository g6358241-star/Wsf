--!strict
-- NPC relationships, compact memory and global reputation (§12.9, §12.11).
-- Every change carries a reason so the UI can explain why opinion moved. Impact values are PROPOSALS.

local Relationships = {}

-- Base impact of each meaningful event on one NPC's opinion of the player (-100..100).
Relationships.EventImpact = {
	DonatedToNpc = 12, -- player donated at the NPC's stand
	DeclinedRequest = -3,
	IgnoredAfterAccept = -10, -- accepted, then never came (after the grace period)
	ReceivedFromNpc = 2, -- the NPC donated to the player's stand
	LeftAtStand = -2, -- followed the NPC, then left without donating although an offer was affordable
}

-- How strongly each event feeds the player's overall reputation, relative to the NPC opinion change.
Relationships.ReputationShare = 0.5

export type Memory = {
	s: number, -- opinion score
	t: number, -- last meaningful interaction (unix seconds)
	n: string, -- display name, so a returning NPC is recognisable
	e: { string }, -- most recent event codes, newest last
}

export type Reputation = {
	score: number,
	log: { { reason: string, npc: string, delta: number, t: number } },
}

export type Options = {
	retentionSeconds: number,
	maxEventsPerNpc: number,
	maxNpcs: number,
	maxReasonLog: number,
}

-- Personality changes how hard an event lands: sensitive NPCs react more to negative events,
-- generous ones value donations a little more. Returns the scaled delta.
function Relationships.scaledImpact(event: string, traits: { [string]: number }): number
	local base = (Relationships.EventImpact :: { [string]: number })[event] or 0
	local sensitivity = traits.sensitivity or 0.5
	if base < 0 then
		return base * (0.5 + sensitivity)
	end
	return base * (0.8 + 0.4 * (traits.generosity or 0.5))
end

function Relationships.expire(memories: { [string]: Memory }, now: number, opts: Options)
	for id, mem in memories do
		if now - mem.t > opts.retentionSeconds then
			memories[id] = nil
		end
	end
end

function Relationships.opinion(memories: { [string]: Memory }, npcId: string, now: number, opts: Options): number
	local mem = memories[npcId]
	if mem == nil or now - mem.t > opts.retentionSeconds then
		return 0
	end
	return mem.s
end

local function trimOldest(memories: { [string]: Memory }, maxNpcs: number)
	local count = 0
	local oldestId, oldestT = nil :: string?, math.huge
	for id, mem in memories do
		count += 1
		if mem.t < oldestT then
			oldestId, oldestT = id, mem.t
		end
	end
	if count > maxNpcs and oldestId then
		memories[oldestId] = nil
	end
end

-- Records a meaningful interaction: refreshes the 3-day retention, updates opinion and reputation.
function Relationships.record(
	memories: { [string]: Memory },
	reputation: Reputation,
	npcId: string,
	npcName: string,
	traits: { [string]: number },
	event: string,
	now: number,
	opts: Options
): number
	Relationships.expire(memories, now, opts)
	local delta = Relationships.scaledImpact(event, traits)
	local mem = memories[npcId]
	if mem == nil then
		mem = { s = 0, t = now, n = npcName, e = {} }
		memories[npcId] = mem
	end
	mem.s = math.clamp(mem.s + delta, -100, 100)
	mem.t = now
	table.insert(mem.e, event)
	while #mem.e > opts.maxEventsPerNpc do
		table.remove(mem.e, 1)
	end
	trimOldest(memories, opts.maxNpcs)

	local repDelta = delta * Relationships.ReputationShare
	reputation.score = math.clamp(reputation.score + repDelta, -1000, 1000)
	table.insert(reputation.log, { reason = event, npc = npcName, delta = repDelta, t = now })
	while #reputation.log > opts.maxReasonLog do
		table.remove(reputation.log, 1)
	end
	return delta
end

-- Multiplier applied to an NPC's willingness to help the player (donate at their stand, return donations).
-- Opinion -100..100 maps to roughly 0.5..1.3; neutral NPCs are unaffected.
function Relationships.willingness(opinion: number): number
	if opinion >= 0 then
		return 1 + 0.3 * (opinion / 100)
	end
	return 1 + 0.5 * (opinion / 100)
end

return Relationships
