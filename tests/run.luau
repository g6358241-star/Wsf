-- Minimal Lune test runner. Usage: lune run tests/run
local Rng = require("../src/server/Logic/Rng")
local Ledger = require("../src/server/Logic/Ledger")
local SecondaryCurrency = require("../src/server/Logic/SecondaryCurrency")
local OfflineEarnings = require("../src/server/Logic/OfflineEarnings")
local IncomeStats = require("../src/server/Logic/IncomeStats")
local Relationships = require("../src/server/Logic/Relationships")
local Luck = require("../src/server/Logic/Luck")
local OfferGenerator = require("../src/server/Logic/OfferGenerator")
local NpcFactory = require("../src/server/Logic/NpcFactory")
local NpcBrain = require("../src/server/Logic/NpcBrain")
local Transactions = require("../src/server/Logic/Transactions")
local PersistenceConfig = require("../src/server/Config/Persistence")
local process = require("@lune/process")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. "\n     " .. tostring(err))
	end
end
local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
	end
end
local function near(a: number, b: number, tol: number, msg: string?)
	if math.abs(a - b) > tol then
		error(string.format("%s: expected %.4f±%.4f, got %.4f", msg or "near", b, tol, a), 2)
	end
end

test("Rng is reproducible and in [0,1)", function()
	local a, b = Rng.new("seed"), Rng.new("seed")
	local mean = 0
	for _ = 1, 20000 do
		local x = a:next()
		eq(x, b:next(), "same sequence")
		assert(x >= 0 and x < 1, "range")
		mean += x
	end
	near(mean / 20000, 0.5, 0.01, "uniform mean")
end)

test("Ledger transfer validates and is idempotent", function()
	local l = Ledger.new()
	local a = Ledger.newAccount("a", { Primary = 100 })
	local b = Ledger.newAccount("b")
	eq((Ledger.transfer(l, "t1", a, b, "Primary", 40, true)), true)
	eq(select(2, Ledger.transfer(l, "t1", a, b, "Primary", 40, true)), "Duplicate")
	eq(select(2, Ledger.transfer(l, "t2", a, b, "Primary", 61)), "InsufficientFunds")
	eq(select(2, Ledger.transfer(l, "t3", a, b, "Primary", 1.5)), "BadAmount")
	eq(select(2, Ledger.transfer(l, "t4", a, b, "Primary", -5)), "BadAmount")
	eq(select(2, Ledger.transfer(l, "t5", a, b, "Primary", 0 / 0)), "BadAmount")
	eq(select(2, Ledger.transfer(l, "t6", a, b, "Robux", 1)), "BadCurrency")
	eq(a.balances.Primary, 60)
	eq(b.balances.Primary, 40)
	eq(a.donated, 40)
	eq(b.raised, 40)
end)

test("Ledger mint is allow-listed per currency", function()
	local l = Ledger.new()
	local a = Ledger.newAccount("a")
	eq(select(2, Ledger.mint(l, "m1", a, "Primary", 10, "NpcPassiveIncome")), "MintNotAllowed")
	eq(select(2, Ledger.mint(l, "m2", a, "Secondary", 10, "RobuxPurchase")), "MintNotAllowed") -- secondary not for Robux
	eq((Ledger.mint(l, "m3", a, "Secondary", 10, "SecondaryReward")), true)
	eq(a.balances.Secondary, 10)
end)

test("Secondary reward is deterministic, monotonic, always >= 1", function()
	local previous = 0
	for amount = 1, 20000, 7 do
		local r = SecondaryCurrency.reward(amount)
		eq(r, SecondaryCurrency.reward(amount), "deterministic")
		assert(r >= 1, "at least 1")
		assert(r >= previous, "monotonic at " .. amount)
		previous = r
	end
	-- examples published in docs/SIMULATION.md
	for amount, expected in { [5] = 1, [10] = 2, [50] = 6, [99] = 10, [100] = 12, [500] = 56, [1000] = 121, [5000] = 601, [10000] = 1301, [100000] = 5000 } do
		eq(SecondaryCurrency.reward(amount), expected, "reward(" .. amount .. ")")
	end
end)

test("Offline: owner example 2000/24h at 5% = 4.17 per hour", function()
	local stats = IncomeStats.new()
	local now = 1_800_000_000
	local opts = { maxRecords = 200, dailyDays = 30, averagedSources = { NpcStandDonation = true }, primaryCurrency = "Primary" }
	for h = 0, 19 do
		IncomeStats.record(stats, { id = 0, t = now - h * 3600, fromId = "n", fromName = "N", amount = 100, currency = "Primary", source = "NpcStandDonation" }, opts)
	end
	-- excluded sources must not count toward the average
	IncomeStats.record(stats, { id = 0, t = now, fromId = "x", fromName = "X", amount = 999, currency = "Primary", source = "RobuxPurchase" }, opts)
	local avg = IncomeStats.averageHourly(stats, now, 24)
	near(avg, 2000 / 24, 1e-9, "average")
	local result = OfflineEarnings.compute(avg, 3600)
	near(result.exact, 4.1667, 0.001, "one hour at 5%")
	eq(result.amount, 4, "floored")
end)

test("Offline rate curve: 5% -> ~1% at 4.5d -> 0 at 14d, no jumps", function()
	near(OfflineEarnings.rateAt(0), 0.05, 1e-9)
	near(OfflineEarnings.rateAt(4.5), 0.01, 1e-9)
	eq(OfflineEarnings.rateAt(14), 0)
	eq(OfflineEarnings.compute(100, 30 * 86400).creditedHours, 14 * 24)
	local prev = OfflineEarnings.rateAt(0)
	for i = 1, 1400 do
		local r = OfflineEarnings.rateAt(i / 100)
		assert(math.abs(r - prev) < 0.0005, "jump at day " .. i / 100)
		prev = r
	end
end)

test("IncomeStats daily keys are UTC calendar dates", function()
	eq(IncomeStats.dateKey(0), "1970-01-01")
	eq(IncomeStats.dateKey(951782400), "2000-02-29")
	eq(IncomeStats.dateKey(1794441600), "2026-11-12")
end)

test("Relationships expire 3 days after the latest interaction", function()
	local opts = {
		retentionSeconds = PersistenceConfig.Memory.retentionSeconds,
		maxEventsPerNpc = 4,
		maxNpcs = 300,
		maxReasonLog = 20,
	}
	local mem, rep = {}, { score = 0, log = {} }
	local traits = { sensitivity = 0.5, generosity = 0.5 }
	Relationships.record(mem, rep, "npc1", "Ava", traits, "DonatedToNpc", 0, opts)
	assert(Relationships.opinion(mem, "npc1", 2 * 86400, opts) > 0, "remembered")
	Relationships.record(mem, rep, "npc1", "Ava", traits, "DeclinedRequest", 2 * 86400, opts) -- refresh
	assert(Relationships.opinion(mem, "npc1", 4.5 * 86400, opts) ~= 0, "refreshed retention")
	eq(Relationships.opinion(mem, "npc1", 5.1 * 86400, opts), 0, "forgotten")
	Relationships.expire(mem, 5.1 * 86400, opts)
	eq(mem.npc1, nil)
	eq(#rep.log, 2, "reputation reasons logged")
end)

test("Sensitive NPCs take ignoring harder", function()
	local calm = Relationships.scaledImpact("IgnoredAfterAccept", { sensitivity = 0.1 })
	local touchy = Relationships.scaledImpact("IgnoredAfterAccept", { sensitivity = 0.9 })
	assert(touchy < calm and calm < 0, "personality scales penalty")
end)

test("Luck sources add up under one global cap", function()
	near(Luck.total({ Vip = true }), 0.05, 1e-9)
	near(Luck.total({ Vip = true, RareStand = true }), 0.08, 1e-9)
	local cfg = { globalCap = 0.06, areaWeights = { visitChance = 1 }, sources = { Vip = 0.05, RareStand = 0.03 } }
	near(Luck.total({ Vip = true, RareStand = true }, cfg :: any), 0.06, 1e-9)
end)

test("NPC offers: ascending, 1..10 buttons, >= 10k distinct combinations", function()
	local rng = Rng.new(42)
	local distinct, count = {}, 0
	for _ = 1, 150000 do
		local wallet = math.floor(10 ^ rng:range(1, 6.5))
		local offers = OfferGenerator.generate(rng, wallet)
		assert(#offers >= 1 and #offers <= 10, "count")
		for i = 2, #offers do
			assert(offers[i] > offers[i - 1], "ascending")
		end
		local key = table.concat(offers, ",")
		if not distinct[key] then
			distinct[key] = true
			count += 1
		end
	end
	assert(count >= 10000, "only " .. count .. " distinct sets")
end)

test("Player donation to NPC: listed amounts only, secondary always, conserves primary", function()
	local rng = Rng.new(7)
	local l = Ledger.new()
	local tier = NpcFactory.rollWealthTier(rng)
	local profile = NpcFactory.create(rng, "npc", tier, 0)
	profile.offers = { 10, 50 }
	local npc = NpcBrain.fromProfile(profile, 0, rng)
	Ledger.mint(l, "spawn", npc.wallet, "Primary", 1000, "NpcSpawnWallet")
	local player = Ledger.newAccount("player", { Primary = 100 })

	eq(Transactions.playerDonateToNpc(l, "d0", player, npc, 25, 1, rng).err, "NotOffered")
	eq(Transactions.playerDonateToNpc(l, "d1", player, npc, 500, 1, rng).ok, false, "not listed")
	local before = player.balances.Primary + NpcBrain.totalFunds(npc)
	for i = 1, 30 do
		local res = Transactions.playerDonateToNpc(l, "tx" .. i, player, npc, 10, 1, rng)
		if player.balances.Primary < 10 and not res.ok then
			break
		end
		eq(res.ok, true)
		eq(res.secondary, SecondaryCurrency.reward(10), "secondary always granted")
	end
	eq(player.balances.Primary + NpcBrain.totalFunds(npc), before, "primary conserved")
	eq(Transactions.playerDonateToNpc(l, "tx1", player, npc, 10, 1, rng).err, "Duplicate")
end)

test("Donation decision never picks unaffordable or unlisted amounts", function()
	local rng = Rng.new(99)
	local l = Ledger.new()
	local tier = NpcFactory.rollWealthTier(rng)
	for i = 1, 3000 do
		local npc = NpcBrain.fromProfile(NpcFactory.create(rng, "n" .. i, tier, 0), 0, rng)
		Ledger.mint(l, "w" .. i, npc.budget, "Primary", rng:int(1, 5000), "NpcSpawnWallet")
		local stand = { id = "s", ownerId = "p", offers = { 5, 100, 1000, 10000 }, appeal = rng:next(), luck = 0 }
		local decision = NpcBrain.decideDonation(npc, stand, 1, rng)
		if decision.amount then
			assert(table.find(stand.offers, decision.amount), "listed")
			assert(decision.amount <= npc.budget.balances.Primary, "affordable")
		end
	end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
