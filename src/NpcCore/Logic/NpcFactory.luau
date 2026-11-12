--!strict
-- Creates individual NPCs: server wealth profile, archetype, traits, wallet and offers (§3.2, §12.3–12.4).

local NpcConfig = require("../Config/Npc")
local Rng = require("./Rng")
local Luck = require("./Luck")
local OfferGenerator = require("./OfferGenerator")

local NpcFactory = {}

export type WealthTier = typeof(NpcConfig.wealthTiers[1])

export type Profile = {
	id: string,
	name: string,
	archetype: NpcConfig.Archetype,
	traits: { [string]: number },
	wallet: number,
	offers: { number },
	personaId: string?,
}

local FIRST = {
	"Milo", "Ava", "Juno", "Theo", "Nia", "Otis", "Ivy", "Rafe", "Lena", "Kai", "Mabel", "Ezra", "Pip", "Rosa",
	"Hugo", "Wren", "Cleo", "Arlo", "Tess", "Ozzy", "Iris", "Bram", "Lulu", "Finn", "Sage", "Remy", "Dot", "Gus",
}
local LAST = {
	"Brook", "Vale", "Finch", "Marsh", "Penn", "Quill", "Rowe", "Stone", "Thorn", "Wilde", "Hale", "Moss", "Pike",
	"Reed", "Ash", "Bell", "Cole", "Drake", "Frost", "Gale", "Holt", "Lark", "North", "Oak",
}

function NpcFactory.rollWealthTier(rng: Rng.Rng): WealthTier
	local weights = {}
	for i, tier in NpcConfig.wealthTiers do
		weights[i] = tier.weight
	end
	return NpcConfig.wealthTiers[rng:weightedIndex(weights)]
end

function NpcFactory.pickArchetype(rng: Rng.Rng, luckTotal: number): NpcConfig.Archetype
	local rareMult = Luck.multiplier(luckTotal, "rareSpawn")
	local weights = {}
	for i, a in NpcConfig.archetypes do
		weights[i] = if a.rare then a.spawnWeight * rareMult else a.spawnWeight
	end
	return NpcConfig.archetypes[rng:weightedIndex(weights)]
end

function NpcFactory.rollTraits(rng: Rng.Rng, archetype: NpcConfig.Archetype): { [string]: number }
	local traits = {}
	for name, range in archetype.traits do
		traits[name] = math.clamp(rng:normal(range.mean, range.spread), 0, 1)
	end
	return traits
end

function NpcFactory.rollWallet(rng: Rng.Rng, tier: WealthTier, archetype: NpcConfig.Archetype): number
	local whale = NpcConfig.whale
	if tier.id == "Wealthy" and rng:chance(whale.chanceOnWealthyServer) then
		return math.floor(math.exp(rng:range(math.log(whale.minWallet), math.log(whale.maxWallet))))
	end
	return math.max(1, math.floor(rng:logNormal(tier.medianWallet * archetype.walletScale, archetype.walletSigma)))
end

function NpcFactory.create(rng: Rng.Rng, id: string, tier: WealthTier, luckTotal: number): Profile
	local archetype = NpcFactory.pickArchetype(rng, luckTotal)
	local wallet = NpcFactory.rollWallet(rng, tier, archetype)
	return {
		id = id,
		name = FIRST[rng:int(1, #FIRST)] .. " " .. LAST[rng:int(1, #LAST)],
		archetype = archetype,
		traits = NpcFactory.rollTraits(rng, archetype),
		wallet = wallet,
		offers = OfferGenerator.generate(rng, wallet),
	}
end

-- A persistent identity (§12.1, §12.9): the persona id alone determines name, archetype and personality, so an
-- NPC that returns in a later session is recognisably the same character. Wallet and offers still come from
-- this server's wealth profile via `rng`.
function NpcFactory.createPersona(rng: Rng.Rng, id: string, personaId: string, tier: WealthTier, luckTotal: number): Profile
	local identity = Rng.new("persona:" .. personaId)
	local archetype = NpcFactory.pickArchetype(identity, luckTotal)
	local name = FIRST[identity:int(1, #FIRST)] .. " " .. LAST[identity:int(1, #LAST)]
	local traits = NpcFactory.rollTraits(identity, archetype)
	local wallet = NpcFactory.rollWallet(rng, tier, archetype)
	return {
		id = id,
		name = name,
		archetype = archetype,
		traits = traits,
		wallet = wallet,
		offers = OfferGenerator.generate(rng, wallet),
		personaId = personaId,
	}
end

return NpcFactory
