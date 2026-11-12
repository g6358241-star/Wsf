-- Integration tests: run the real HarborServer scripts (Main, NPC.server, Profiles, Economy, Booths,
-- Donations, Boards, Social, NpcDirector) and NpcCore against a mocked engine in virtual time.
-- Only locomotion (NPCService) is replaced. Usage: lune run tests/integration
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Scheduler = require("./harness/Scheduler")
local Mock = require("./harness/MockRoblox")

local ROOT = process.cwd
local failures, passes = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL " .. msg)
	end
end
local function section(name: string)
	print("\n## " .. name)
end

local function newWorld(opts)
	local sched = Scheduler.new()
	opts.scheduler = sched
	opts.root = ROOT
	opts.overrides = { ["ServerScriptService.HarborServer.NPCService"] = ROOT .. "/tests/harness/MockNPCService.luau" }
	local world = Mock.newWorld(opts)
	return world, sched
end

local function lastNotice(world, player)
	for i = #world.clientEvents, 1, -1 do
		local e = world.clientEvents[i]
		if e.player == player and e.args[1] == "Notice" then
			return e.args[2]
		end
	end
	return nil
end

local function boothNear(world, id)
	local booth = world.workspace.CloudHarbor.Booths:FindFirstChild(id)
	return booth.CounterTop.Position + roblox.Vector3.new(3, 0, 0)
end

---------------------------------------------------------------------------------------------------
section("World A: Studio session — remotes, booths, autonomous NPC economy")
do
	local world, sched = newWorld({ studio = true })
	world.buildMap(48)
	world.runScript("ServerScriptService.HarborServer.Main")
	world.runScript("ServerScriptService.HarborServer.NPC")
	sched:advance(1)
	local Profiles = world.require(world.find("ServerScriptService.HarborServer.Profiles"))
	local Booths = world.require(world.find("ServerScriptService.HarborServer.Booths"))
	local Config = world.require(world.find("ReplicatedStorage.HarborShared.Config"))
	local remote = world.find("ReplicatedStorage.HarborGame.Action")
	check(remote ~= nil, "Main created the Action remote")
	check(Booths.Ready, "Booths initialised on the 48-booth map")

	local player = world.addPlayer(101, "Tester", roblox.Vector3.new(0, 42, -24))
	sched:advance(2)
	local data = Profiles.get(player)
	check(data ~= nil, "profile loaded")
	check(data.Coins == 0 and data.DCoins == 0, "new profile has no starting Coins or DCoins")
	check(data.Version == 2, "new profile is schema v2")

	local function fire(...)
		remote.OnServerEvent:Fire(player, ...)
		sched:advance(0.6) -- respects the token-bucket rate limit
	end

	-- Removed V1 features
	local before = #world.clientEvents
	fire("Donate", "Booth_001", 100, "0123456789abcdef0123", 0)
	fire("Transfer", "Booth_001")
	check(#world.clientEvents == before, "Donate/Transfer actions are ignored (no handler, no reply)")
	fire("Product", "SupportSmall")
	check(lastNotice(world, player) == "Real payments are disabled.", "Product prompt stays disabled")

	-- Daily reward: Coins (and legacy Pearls) only, never DCoins
	fire("Daily")
	data = Profiles.get(player)
	check(data.Coins == Config.DailyCoins and data.DCoins == 0, "daily reward grants Coins, no DCoins")

	-- Claiming
	fire("Claim", "Booth_005")
	check(lastNotice(world, player) == "Move closer to this booth.", "claim requires proximity")
	player.Character.HumanoidRootPart.Position = boothNear(world, "Booth_005")
	fire("Claim", "Booth_005")
	check(Booths.owned[101] == "Booth_005", "player claimed Booth_005")
	check(table.concat(Booths.entries.Booth_005.offers, ",") == table.concat(Config.Stand.DefaultOffers, ","), "first claim lists default preset offers")
	fire("Claim", "Booth_006")
	check(Booths.owned[101] == "Booth_005", "one stand per player")

	-- Editing offers: presets only
	fire("Edit", "Hello", { 7 })
	check(lastNotice(world, player) == "Choose amounts from the preset list.", "non-preset amount rejected")
	fire("Edit", "Hello", { 10, 100, 100, 1000 })
	check(table.concat(Booths.entries.Booth_005.offers, ",") == "10,100,1000", "offers saved, deduplicated and sorted")
	check(table.concat(Profiles.get(player).Stand.Offers, ",") == "10,100,1000", "offers remembered in profile")
	local allPresets = table.clone(Config.Stand.Presets)
	fire("Edit", "All of them", allPresets)
	check(#Booths.entries.Booth_005.offers == #Config.Stand.Presets, "no artificial cap: every preset can be listed")
	fire("Edit", "Hello", { 10, 100, 1000 })

	-- Two simulated hours of autonomous NPCs
	local NpcDirectorStats
	local maxNpcStands, minFree, overlap = 0, 48, false
	local offersAt: { [number]: { [number]: boolean } } = {}
	local function snapshotBooths()
		local npcStands = 0
		for _, e in Booths.entries do
			if e.npc then
				npcStands += 1
			end
			if e.npc and e.owner then
				overlap = true
			end
		end
		maxNpcStands = math.max(maxNpcStands, npcStands)
		minFree = math.min(minFree, Booths.freeCount())
	end
	for minute = 1, 120 do
		sched:advance(60)
		snapshotBooths()
	end
	data = Profiles.get(player)
	local historySum = 0
	for _, r in data.Stats.history do
		historySum += r.amount
		check(r.amount == 10 or r.amount == 100 or r.amount == 1000, "donation amount was a listed offer (" .. r.amount .. ")")
		check(r.source == "NpcStandDonation" and r.currency == "Coins", "history record source/currency")
	end
	check(data.CoinsRaised > 0, "NPCs donated to the player within 2 hours (" .. data.CoinsRaised .. " Coins)")
	check(historySum == data.CoinsRaised, "history total equals CoinsRaised")
	local playtimeCoins = data.RewardIndex * Config.PlayRewardCoins
	check(data.Coins == Config.DailyCoins + playtimeCoins + data.CoinsRaised, "Coins = daily + playtime rewards + NPC donations (nothing else)")
	check(data.DCoins == 0, "no DCoins appeared without a donation to an NPC")
	check(not overlap, "no booth was ever owned by a player and an NPC at once")
	check(maxNpcStands > 0, "NPCs claimed their own stands (max " .. maxNpcStands .. ")")
	check(minFree >= Config.Stand.ReservedForPlayers, "NPCs never took the reserved free booths (min free " .. minFree .. ")")

	local board = world.find("ReplicatedStorage.HarborGame.Leaderboard")
	local playerRow = board and board:FindFirstChild("p:101")
	check(playerRow ~= nil, "TAB leaderboard data includes the player")
	check(playerRow and playerRow:GetAttribute("Raised") == data.CoinsRaised, "leaderboard Raised matches the profile")
	check(board and #board:GetChildren() > 5, "leaderboard includes NPC rows (" .. (board and #board:GetChildren() or 0) .. ")")

	local dirPrints = 0
	for _, line in world.prints do
		if string.find(line, "[NPC_DIRECTOR]", 1, true) then
			dirPrints += 1
			check(string.find(line, "conserved=true", 1, true) ~= nil, "director conservation audit: " .. line)
		end
	end
	check(dirPrints >= 200, "director audit ran every 30s (" .. dirPrints .. " reports)")
	local lastDir = ""
	for _, line in world.prints do
		if string.find(line, "[NPC_DIRECTOR]", 1, true) then
			lastDir = line
		end
	end
	print("  " .. lastDir)

	-- Releasing the stand while NPCs walk towards it: no credit for a stand the player no longer owns
	fire("Release")
	local raisedAtRelease = Profiles.get(player).CoinsRaised
	sched:advance(15 * 60)
	check(Profiles.get(player).CoinsRaised == raisedAtRelease, "no donations credited after the stand was released")
	player.Character.HumanoidRootPart.Position = boothNear(world, "Booth_030")
	fire("Claim", "Booth_030")
	check(table.concat(Booths.entries.Booth_030.offers, ",") == "10,100,1000", "re-claim restores saved offers")

	-- Stress: fill to the 100-NPC cap
	world.workspace:SetAttribute("NpcStressTarget", 100)
	local NPCService = world.require(world.find("ServerScriptService.HarborServer.NPCService"))
	local peak = 0
	for _ = 1, 20 do
		sched:advance(15)
		local n = 0
		for _ in NPCService.Agents do
			n += 1
		end
		peak = math.max(peak, n)
	end
	check(peak == 100, "stress target reaches exactly 100 active NPCs (peak " .. peak .. ")")
	world.workspace:SetAttribute("NpcStressTarget", nil)

	-- Player leaves: stand released, profile closed, simulation continues without errors
	world.removePlayer(player)
	sched:advance(120)
	check(Booths.owned[101] == nil and Booths.entries.Booth_030.owner == nil, "stand released when the player leaves")
	check(Profiles.Active[player] == nil, "profile closed on leave")
	sched:advance(30 * 60)
	check(#sched.errors == 0, "no script errors in World A (" .. #sched.errors .. ")")
	for i = 1, math.min(5, #sched.errors) do
		print(sched.errors[i])
	end
	local warnCount = 0
	for _, w in world.warnings do
		if string.find(w, "CONSERVATION", 1, true) then
			warnCount += 1
		end
	end
	check(warnCount == 0, "no conservation warnings")
	print(string.format("  mock movement: spawned=%d despawned=%d lost=%d dropped-late-callbacks=%d", NPCService.Stats.Spawned, NPCService.Stats.Despawned, NPCService.Stats.Lost, NPCService.Stats.LateCallbacks))
end

---------------------------------------------------------------------------------------------------
section("World B: live persistence — v1 save migration, legacy transfer drain, Coins-only Robux packs")
local store = {}
store["HarborProfiles_TestCurrency_v2"] = {
	u_202 = {
		Data = {
			Version = 1, Coins = 40, Pearls = 7, DCoins = 500, XP = 120, PlaySeconds = 900, Donated = 25, Received = 0,
			Claims = 2, LastDaily = -1, RewardIndex = 3, Inventory = { Sailor = true }, Equipped = {}, Quests = {},
			Receipts = { ["out:202:abc"] = true }, Passes = {}, BoostUntil = 0,
			Outbox = { ["202:abc"] = { Target = 303, Sender = 202, Amount = 25 } },
		},
		Session = nil,
	},
}
do
	local world, sched = newWorld({ studio = false, dataStore = store })
	world.buildMap(48)
	world.runScript("ServerScriptService.HarborServer.Main")
	sched:advance(1)
	local Profiles = world.require(world.find("ServerScriptService.HarborServer.Profiles"))
	local Config = world.require(world.find("ReplicatedStorage.HarborShared.Config"))
	local sender = world.addPlayer(202, "Sender")
	sched:advance(2)
	local d = Profiles.get(sender)
	if not d then
		for _, k in world.kicks do
			print("  kick:", k.message)
		end
		for _, e in sched.errors do
			print("  error:", e)
		end
		for _, w in world.warnings do
			print("  warn:", w)
		end
	end
	check(d ~= nil, "v1 profile loads")
	check(d and d.Version == 2, "v1 profile migrated to v2")
	check(d and d.Coins == 40 and d.Pearls == 7 and d.DCoins == 500, "existing Coins/Pearls/DCoins preserved untouched")
	check(d and d.Inventory.Sailor == true and d.XP == 120, "inventory and progress preserved")
	check(d and d.Outbox["202:abc"] ~= nil, "pending pre-update transfer kept until delivered")

	local receiver = world.addPlayer(303, "Receiver")
	sched:advance(12)
	check(Profiles.get(receiver).DCoins == 25, "legacy drain delivered the already-paid transfer")
	check(next(Profiles.get(sender).Outbox) == nil, "sender outbox cleared after delivery")
	check(Profiles.get(sender).DCoins == 500, "drain did not debit the sender twice")

	-- Robux pack receipt grants Coins only, idempotently
	local Purchases = world.require(world.find("ServerScriptService.HarborServer.Purchases"))
	Purchases.init(world.find("ReplicatedStorage.HarborGame.Action"))
	Config.Products.SupportSmall.Id = 555
	local receipt = world.Market.ProcessReceipt
	local before = table.clone(Profiles.get(sender))
	local decision
	sched.task.spawn(function()
		decision = receipt({ PurchaseId = "r-1", PlayerId = 202, ProductId = 555, CurrencySpent = 25 })
	end)
	sched:advance(1)
	local after = Profiles.get(sender)
	check(decision == roblox.Enum.ProductPurchaseDecision.PurchaseGranted, "receipt granted")
	check(after.Coins == before.Coins + 100, "pack added 100 Coins")
	check(after.Pearls == before.Pearls and after.DCoins == before.DCoins, "pack granted no Pearls and no DCoins")
	sched.task.spawn(function()
		decision = receipt({ PurchaseId = "r-1", PlayerId = 202, ProductId = 555, CurrencySpent = 25 })
	end)
	sched:advance(1)
	check(Profiles.get(sender).Coins == before.Coins + 100, "replayed receipt does not grant twice")

	world.removePlayer(sender)
	world.removePlayer(receiver)
	sched:advance(5)
	local saved = store["HarborProfiles_TestCurrency_v2"].u_202
	check(saved.Data.Version == 2 and saved.Session == nil, "saved as v2 and session lease released")
	check(saved.Data.Pearls == 7 and saved.Data.DCoins == 500, "save keeps legacy balances")
	check(#sched.errors == 0, "no script errors in World B (" .. #sched.errors .. ")")
	for i = 1, math.min(5, #sched.errors) do
		print(sched.errors[i])
	end
end

---------------------------------------------------------------------------------------------------
section("World C: optional DCoins quarantine (owner decision, off by default)")
do
	local qStore = {
		["HarborProfiles_TestCurrency_v2"] = {
			u_404 = { Data = { Version = 1, Coins = 1, Pearls = 0, DCoins = 500, Outbox = {} }, Session = nil },
		},
	}
	for session = 1, 2 do
		local world, sched = newWorld({ studio = false, dataStore = qStore })
		world.buildMap(48)
		world.runScript("ServerScriptService.HarborServer.Main")
		sched:advance(1)
		local Config = world.require(world.find("ReplicatedStorage.HarborShared.Config"))
		Config.Migration.QuarantineTestDCoins = true
		local Profiles = world.require(world.find("ServerScriptService.HarborServer.Profiles"))
		local p = world.addPlayer(404, "Q")
		sched:advance(2)
		local d = Profiles.get(p)
		check(d.DCoins == 0 and d.LegacyDCoins == 500 and d.MigratedTestDCoins, "session " .. session .. ": test DCoins parked in LegacyDCoins exactly once")
		world.removePlayer(p)
		sched:advance(5)
		check(#sched.errors == 0, "no script errors in World C session " .. session)
	end
end

print(string.format("\n%d checks passed, %d failed", passes, failures))
if failures > 0 then
	process.exit(1)
end
