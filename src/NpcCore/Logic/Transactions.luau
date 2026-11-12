--!strict
-- Composite, all-or-nothing money flows built on Ledger. Each function runs without yielding,
-- so it either fully applies or leaves every balance untouched.

local EconomyConfig = require("../Config/Economy")
local Ledger = require("./Ledger")
local NpcBrain = require("./NpcBrain")
local Rng = require("./Rng")
local SecondaryCurrency = require("./SecondaryCurrency")

local PRIMARY = EconomyConfig.Currency.Primary
local SECONDARY = EconomyConfig.Currency.Secondary

local Transactions = {}

-- An NPC donates `amount` from its donation budget to a stand owner (player or NPC).
function Transactions.npcDonate(ledger: Ledger.Ledger, txId: string, donor: NpcBrain.Agent, receiver: Ledger.Account, amount: number): (boolean, string?)
	local ok, err = Ledger.transfer(ledger, txId, donor.budget, receiver, PRIMARY, amount, true)
	if ok then
		donor.donationsMade += 1
	end
	return ok, err
end

-- Moves money between an NPC's own wallet and budget (its own decision; conserves currency).
function Transactions.withdraw(ledger: Ledger.Ledger, txId: string, agent: NpcBrain.Agent, amount: number): boolean
	if amount <= 0 then
		return false
	end
	return (Ledger.transfer(ledger, txId, agent.wallet, agent.budget, PRIMARY, amount))
end

export type PlayerDonationResult = {
	ok: boolean,
	err: string?,
	secondary: number,
	returned: number,
}

-- Player donates one of the NPC's own listed amounts at the NPC's stand (§5.2, §12.8 step 7).
-- Secondary reward is always granted on success; the NPC may separately return primary currency
-- from its own funds. `returnWillingness` comes from Relationships.willingness (offended NPCs return less).
function Transactions.playerDonateToNpc(
	ledger: Ledger.Ledger,
	txId: string,
	player: Ledger.Account,
	npc: NpcBrain.Agent,
	amount: number,
	returnWillingness: number,
	rng: Rng.Rng
): PlayerDonationResult
	local listed = false
	for _, offer in npc.offers do
		if offer == amount then
			listed = true
			break
		end
	end
	if not listed then
		return { ok = false, err = "NotOffered", secondary = 0, returned = 0 }
	end

	local reward = SecondaryCurrency.reward(amount)
	local receiver = NpcBrain.receivingAccount(npc, EconomyConfig.NpcReceivedFundsTo)
	local ok, err = Ledger.transfer(ledger, txId, player, receiver, PRIMARY, amount, true)
	if not ok then
		return { ok = false, err = err, secondary = 0, returned = 0 }
	end
	-- Cannot fail after the validated transfer: reason/currency are allow-listed and txId is fresh.
	Ledger.mint(ledger, txId .. ":sec", player, SECONDARY, reward, "SecondaryReward")

	local returned = 0
	local want = Transactions.rollReturn(npc, amount, returnWillingness, rng)
	if want > 0 then
		local source = if Ledger.balance(npc.budget, PRIMARY) >= want then npc.budget else npc.wallet
		if Ledger.balance(source, PRIMARY) >= want and Ledger.transfer(ledger, txId .. ":ret", source, player, PRIMARY, want, true) then
			returned = want
		end
	end
	return { ok = true, err = nil, secondary = reward, returned = returned }
end

-- The NPC's separate decision to return a gift (§5.2): 0 = no return, else the Coins it wants to give back.
-- Offended NPCs (low `returnWillingness`) return less often (§12.9).
function Transactions.rollReturn(npc: NpcBrain.Agent, amount: number, returnWillingness: number, rng: Rng.Rng): number
	local r = EconomyConfig.ReturnDonation
	local chance = math.clamp(r.baseChance * returnWillingness * (0.5 + npc.traits.generosity), 0, 1)
	if not rng:chance(chance) then
		return 0
	end
	return math.max(1, math.floor(amount * rng:range(r.fractionMin, r.fractionMax)))
end

return Transactions
