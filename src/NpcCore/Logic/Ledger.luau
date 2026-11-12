--!strict
-- In-memory, server-authoritative ledger. Every operation is synchronous (no yields), so on Roblox's
-- single-threaded scheduler each call is atomic. Duplicate transaction ids are rejected without effect.

local EconomyConfig = require("../Config/Economy")

export type Account = {
	id: string,
	balances: { [string]: number },
	donated: number, -- primary given away (leaderboard "Donated")
	raised: number, -- primary received from donations (leaderboard "Raised")
}

export type Ledger = {
	seen: { [string]: boolean },
	seenOrder: { string },
	maxSeen: number,
	minted: { [string]: number },
}

local Ledger = {}

function Ledger.new(maxSeen: number?): Ledger
	return { seen = {}, seenOrder = {}, maxSeen = maxSeen or 5000, minted = {} }
end

function Ledger.newAccount(id: string, balances: { [string]: number }?): Account
	local b = { [EconomyConfig.Currency.Primary] = 0, [EconomyConfig.Currency.Secondary] = 0 }
	if balances then
		for k, v in balances do
			b[k] = v
		end
	end
	return { id = id, balances = b, donated = 0, raised = 0 }
end

local function validAmount(amount: any): boolean
	return type(amount) == "number" and amount == amount and amount > 0 and amount < math.huge
		and math.floor(amount) == amount
end

local function validCurrency(currency: any): boolean
	return currency == EconomyConfig.Currency.Primary or currency == EconomyConfig.Currency.Secondary
end

local function claimTx(self: Ledger, txId: string): boolean
	if self.seen[txId] then
		return false
	end
	self.seen[txId] = true
	table.insert(self.seenOrder, txId)
	if #self.seenOrder > self.maxSeen then
		self.seen[table.remove(self.seenOrder, 1) :: string] = nil
	end
	return true
end

function Ledger.balance(account: Account, currency: string): number
	return account.balances[currency] or 0
end

-- Moves currency between accounts. `isDonation` updates Donated/Raised.
function Ledger.transfer(
	self: Ledger,
	txId: string,
	from: Account,
	to: Account,
	currency: string,
	amount: number,
	isDonation: boolean?
): (boolean, string?)
	if type(txId) ~= "string" or txId == "" then
		return false, "BadTxId"
	end
	if self.seen[txId] then
		return false, "Duplicate"
	end
	if not validCurrency(currency) then
		return false, "BadCurrency"
	end
	if not validAmount(amount) then
		return false, "BadAmount"
	end
	if from == to then
		return false, "SameAccount"
	end
	if (from.balances[currency] or 0) < amount then
		return false, "InsufficientFunds"
	end
	if not claimTx(self, txId) then
		return false, "Duplicate"
	end
	from.balances[currency] -= amount
	to.balances[currency] = (to.balances[currency] or 0) + amount
	if isDonation and currency == EconomyConfig.Currency.Primary then
		from.donated += amount
		to.raised += amount
	end
	return true, nil
end

-- Reverses a transfer that succeeded moments ago when the paired step (e.g. a profile credit) failed.
-- The transaction id stays consumed, so the original request can never be replayed.
function Ledger.refund(self: Ledger, txId: string, from: Account, to: Account, currency: string, amount: number): boolean
	if not self.seen[txId] or (to.balances[currency] or 0) < amount then
		return false
	end
	to.balances[currency] -= amount
	from.balances[currency] = (from.balances[currency] or 0) + amount
	if currency == EconomyConfig.Currency.Primary then
		from.donated = math.max(0, from.donated - amount)
		to.raised = math.max(0, to.raised - amount)
	end
	return true
end

-- Creates currency. Only reasons allow-listed in Config.Economy.MintReasons may mint, each for one currency.
function Ledger.mint(self: Ledger, txId: string, to: Account, currency: string, amount: number, reason: string): (boolean, string?)
	local allowed = (EconomyConfig.MintReasons :: { [string]: string })[reason]
	if type(txId) ~= "string" or txId == "" then
		return false, "BadTxId"
	end
	if self.seen[txId] then
		return false, "Duplicate"
	end
	if allowed == nil or allowed ~= currency then
		return false, "MintNotAllowed"
	end
	if not validAmount(amount) then
		return false, "BadAmount"
	end
	if not claimTx(self, txId) then
		return false, "Duplicate"
	end
	to.balances[currency] = (to.balances[currency] or 0) + amount
	self.minted[reason] = (self.minted[reason] or 0) + amount
	return true, nil
end

return Ledger
