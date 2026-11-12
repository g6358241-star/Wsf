-- Session lease + write serialization. No client can access profile tables.
local Players = game:GetService("Players")
local DSS = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("HarborShared").Config)
local NpcCore = game:GetService("ServerScriptService"):WaitForChild("NpcCore")
local IncomeStats = require(NpcCore.Logic.IncomeStats)
local Relationships = require(NpcCore.Logic.Relationships)
local OfflineEarnings = require(NpcCore.Logic.OfflineEarnings)
local SecondaryCurrency = require(NpcCore.Logic.SecondaryCurrency)
local PersistenceConfig = require(NpcCore.Config.Persistence)
local OfflineConfig = require(NpcCore.Config.Offline)
local Profiles = {Active = {}, Changed = Instance.new("BindableEvent"), DonationDelivered=Instance.new("BindableEvent"), OfflineCredited=Instance.new("BindableEvent")}
Profiles.BeforeClose = nil :: ((Player, any) -> ())?
local store
local memory = RunService:IsStudio() and Config.StudioMemoryOnly
local session = game.JobId ~= "" and game.JobId or Http:GenerateGUID(false)
local shuttingDown = false
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in value do result[key] = clone(child) end
    return result
end
local PRIMARY = Config.Currencies.Primary
local statsOptions = {
    maxRecords = PersistenceConfig.History.maxRecords,
    dailyDays = PersistenceConfig.History.dailyDays,
    averagedSources = OfflineConfig.countedSources,
    primaryCurrency = PRIMARY,
}
local presetSet = {}
for _, amount in Config.Stand.Presets do presetSet[amount] = true end
local function defaults()
    -- Version 2 adds the NPC economy fields. Pearls/Donated/Received/Outbox are legacy and kept untouched.
    return {Version = 2, Coins = 0, Pearls = 0, DCoins = Config.TestCurrency.StartingBalance, Outbox = {}, XP = 0, PlaySeconds = 0,
        Donated = 0, Received = 0, Claims = 0, LastDaily = -1, RewardIndex = 0,
        Inventory = {}, Equipped = {}, Quests = {}, Receipts = {}, Passes = {}, BoostUntil = 0,
        CoinsRaised = 0, CoinsDonated = 0, LegacyDCoins = 0, MigratedTestDCoins = false,
        Stand = {Offers = {}}, Stats = IncomeStats.new(),
        Memories = {}, Reputation = {score = 0, log = {}},
        Offline = {lastSeenAt = 0, avgHourly = 0, last = {amount = 0, awaySeconds = 0, avgHourly = 0, t = 0}}}
end
local function isCount(v)
    return type(v) == "number" and v == v and v % 1 == 0 and v >= 0 and v < 2^53
end
-- Structural checks for v2 tables. Corrupt economic data aborts the load (never overwritten);
-- stand offers that are no longer presets are dropped because they carry no value.
local function checkStats(stats)
    if type(stats.hourly) ~= "table" or type(stats.daily) ~= "table" or type(stats.history) ~= "table" or not isCount(stats.nextId) then
        error("Invalid stats")
    end
    for _, map in {stats.hourly, stats.daily} do
        for key, value in map do
            if type(key) ~= "string" or #key > 16 or not isCount(value) then error("Invalid stats bucket") end
        end
    end
    for _, r in stats.history do
        if type(r) ~= "table" or not isCount(r.id) or type(r.t) ~= "number" or not isCount(r.amount)
            or type(r.currency) ~= "string" or type(r.source) ~= "string" or type(r.fromName) ~= "string" or type(r.fromId) ~= "string" then
            error("Invalid history record")
        end
    end
end
local memoryOptions = {
    retentionSeconds = PersistenceConfig.Memory.retentionSeconds,
    maxEventsPerNpc = PersistenceConfig.Memory.maxEventsPerNpc,
    maxNpcs = PersistenceConfig.Memory.maxNpcs,
    maxReasonLog = PersistenceConfig.Reputation.maxReasonLog,
}
Profiles.memoryOptions = memoryOptions
local function finite(v)
    return type(v) == "number" and v == v and math.abs(v) ~= math.huge
end
-- NPC memories, reputation and offline data: structural checks only (values may be fractional).
local function checkSocial(data)
    for id, mem in data.Memories do
        if type(id) ~= "string" or #id > 40 or type(mem) ~= "table" or not finite(mem.s) or not finite(mem.t)
            or type(mem.n) ~= "string" or type(mem.e) ~= "table" then
            error("Invalid NPC memory")
        end
        for _, code in mem.e do if type(code) ~= "string" then error("Invalid NPC memory event") end end
    end
    local rep = data.Reputation
    if not finite(rep.score) or type(rep.log) ~= "table" then error("Invalid reputation") end
    for _, entry in rep.log do
        if type(entry) ~= "table" or type(entry.reason) ~= "string" or type(entry.npc) ~= "string" or not finite(entry.delta) or not finite(entry.t) then
            error("Invalid reputation log")
        end
    end
    local off = data.Offline
    if not finite(off.lastSeenAt) or not finite(off.avgHourly) or type(off.last) ~= "table" then error("Invalid offline data") end
end
local function sanitizeOffers(offers)
    local clean, seen = {}, {}
    for _, amount in offers do
        if presetSet[amount] and not seen[amount] then seen[amount] = true; table.insert(clean, amount) end
    end
    table.sort(clean)
    return clean
end
Profiles.sanitizeOffers = sanitizeOffers
local function normalize(raw)
    if type(raw) ~= "table" or (raw.Version ~= 1 and raw.Version ~= 2) then error("Unsupported/corrupt profile version") end
    local data = defaults()
    for key, fallback in data do
        local value = raw[key]
        if value ~= nil and key ~= "Version" then
            if type(value) ~= type(fallback) then error("Invalid profile field " .. key) end
            if type(value) == "number" and (value ~= value or math.abs(value) == math.huge or value % 1 ~= 0 or value < (key == "LastDaily" and -1 or 0)) then
                error("Invalid numeric field " .. key)
            end
            data[key] = clone(value)
        end
    end
    for id,tx in data.Outbox do
        if type(id)~="string" or #id>160 or type(tx)~="table" or type(tx.Target)~="number" or tx.Target%1~=0 or type(tx.Amount)~="number" or tx.Amount%1~=0 or tx.Amount<1 or tx.Amount>Config.MaxBalance then error("Invalid pending transfer") end
    end
    -- Reject malformed nested data rather than repairing/overwriting the stored profile.
    for _,field in {"Inventory","Quests","Receipts","Passes"} do
        for key,value in data[field] do
            if type(key)~="string" or #key>160 or type(value)~="boolean" then error("Invalid profile dictionary "..field) end
        end
    end
    for key,value in data.Equipped do
        if type(key)~="string" or type(value)~="string" or #key>32 or #value>48 then error("Invalid equipped cosmetic") end
    end
    if type(data.Stand.Offers) ~= "table" then error("Invalid stand") end
    data.Stand.Offers = sanitizeOffers(data.Stand.Offers)
    checkStats(data.Stats)
    checkSocial(data)
    Relationships.expire(data.Memories, os.time(), memoryOptions)
    -- OPEN owner decision (Config.Migration): park pre-decision test DCoins without deleting them.
    if Config.Migration.QuarantineTestDCoins and not data.MigratedTestDCoins then
        data.LegacyDCoins += data.DCoins
        data.DCoins = 0
        data.MigratedTestDCoins = true
    end
    return data
end
Profiles.normalize = normalize
Profiles.defaults = defaults
local function savedStats(data)
    return {CoinsDonated=data.CoinsDonated,CoinsRaised=data.CoinsRaised,PlaySeconds=data.PlaySeconds}
end
local function retry(callback, attempts)
    local last
    for attempt = 1, attempts or Config.SaveAttempts do
        local ok, value = pcall(callback)
        if ok then return true, value end
        last = value
        if attempt < (attempts or Config.SaveAttempts) then task.wait(2 ^ (attempt - 1)) end
    end
    return false, last
end
function Profiles.get(player)
    local record = Profiles.Active[player]
    if record and not record.Closing and not record.Lost then return record.Data end
    return nil
end
function Profiles.public(player)
    local data = Profiles.get(player)
    if not data then return {Ready = false} end
    local result = {}
    for _, key in {"DCoins", "Coins", "Pearls", "XP", "PlaySeconds", "Donated", "Received", "LastDaily", "Inventory", "Equipped", "Quests", "BoostUntil", "Claims", "CoinsRaised", "CoinsDonated", "Stand", "Reputation"} do
        result[key] = clone(data[key])
    end
    result.Ready = true
    result.Level = 1 + math.floor(data.XP / Config.XPPerLevel)
    result.MemoryOnly = memory
    return result
end
function Profiles.mutate(player, callback)
    local r = Profiles.Active[player]
    if not r or r.Busy or r.Closing or r.Lost then return false, "Profile busy. Try again in a moment." end
    -- Callbacks MUST NOT yield. Drafts make failure rollback all-or-nothing.
    r.Busy = true
    local draft = clone(r.Data)
    local ok, accepted, message = pcall(callback, draft)
    if ok and accepted then r.Data = draft end
    r.Busy = false
    if not ok then warn("[Harbor] Profile mutation rejected: " .. tostring(accepted)); return false, "Request could not be completed." end
    if accepted then Profiles.Changed:Fire(player) end
    return accepted == true, message
end
-- Offline earnings (§6.3–6.4). Runs inside the load transform, so the credit and the new lastSeenAt are written
-- in the same atomic DataStore update as the session lease: a retry or crash can never pay twice.
local function applyOffline(data, now)
    local off = data.Offline
    local result
    if off.lastSeenAt > 0 and now > off.lastSeenAt then
        local res = OfflineEarnings.compute(off.avgHourly, now - off.lastSeenAt)
        if res.amount > 0 and data.Coins + res.amount <= Config.MaxBalance then
            data.Coins += res.amount
            IncomeStats.record(data.Stats, {
                id = 0, t = now, fromId = "offline", fromName = "Offline earnings", amount = res.amount,
                currency = PRIMARY, source = "OfflineEarnings",
            }, statsOptions)
            off.last = {amount = res.amount, awaySeconds = res.awaySeconds, avgHourly = res.averageHourly, t = now}
            result = {amount = res.amount, awaySeconds = res.awaySeconds, creditedHours = res.creditedHours, avgHourly = res.averageHourly}
        end
    end
    off.lastSeenAt = now
    return result
end
Profiles.applyOffline = applyOffline
-- Snapshot taken on every save (PROPOSAL §6.5: snapshot, not a rolling window recomputed while offline).
local function stampOffline(data)
    local now = os.time()
    data.Offline.lastSeenAt = now
    data.Offline.avgHourly = IncomeStats.averageHourly(data.Stats, now, OfflineConfig.averageWindowHours)
end
function Profiles.save(player, release)
    local r = Profiles.Active[player]
    if not r or r.Busy or r.Lost then return false end
    r.Busy = true
    stampOffline(r.Data)
    local snapshot = clone(r.Data)
    local ok, result = true, nil
    if not memory then
        ok, result = retry(function()
            return store:UpdateAsync("u_" .. player.UserId, function(old)
                if type(old) ~= "table" or type(old.Session) ~= "table" or old.Session.Id ~= session then return nil end
                local lease = nil
                if not release then lease = {Id = session, Until = os.time() + Config.LeaseSeconds} end
                return {Data = snapshot, Session = lease}
            end)
        end)
        if ok and result == nil then r.Lost = true; ok = false end
    end
    if ok then r.LastSaved = os.time(); r.SavedStats = savedStats(snapshot) end
    r.Busy = false
    if not ok then
        warn("[Harbor] Profile save failed for " .. player.UserId)
        if r.Lost or os.time() - r.LastSaved >= Config.LeaseSeconds - 30 then
            r.Lost = true
            if player.Parent then player:Kick("Your data session could not be kept safe. Please rejoin.") end
        end
    end
    return ok
end
-- Atomic durable receipt marker + benefit. A retry can never double grant.
function Profiles.receipt(player, purchaseId, grant)
    local r = Profiles.Active[player]
    if memory or not r or r.Busy or r.Lost or r.Closing or type(purchaseId) ~= "string" then return false, false end
    r.Busy = true
    local draft = clone(r.Data)
    local fresh = draft.Receipts[purchaseId] ~= true
    if fresh then
        local ok = pcall(function() grant(draft); draft.Receipts[purchaseId] = true end)
        if not ok then r.Busy = false; return false, false end
    end
    local ok, result = retry(function()
        return store:UpdateAsync("u_" .. player.UserId, function(old)
            if type(old) ~= "table" or type(old.Session) ~= "table" or old.Session.Id ~= session then return nil end
            return {Data = draft, Session = {Id = session, Until = os.time() + Config.LeaseSeconds}}
        end)
    end)
    if ok and result then
        r.Data = draft; r.LastSaved = os.time(); r.SavedStats = savedStats(draft)
    elseif ok then r.Lost = true end
    r.Busy = false
    if ok and result then Profiles.Changed:Fire(player); return true, fresh end
    -- An ambiguous timeout may have persisted a receipt. Never overwrite it
    -- with our older in-memory state; reconnect must reload durable truth.
    r.Lost = true
    if player.Parent then player:Kick("Purchase verification interrupted. Rejoin to safely recover your purchase.") end
    return false, false
end
function Profiles.load(player)
    if shuttingDown then player:Kick("Server is closing. Please rejoin."); return end
    if Profiles.Active[player] then return end
    local data, offline
    local ok, result = true, nil
    if memory then data = defaults() else
        ok, result = retry(function()
            return store:UpdateAsync("u_" .. player.UserId, function(old)
                if old ~= nil and type(old) ~= "table" then error("Invalid record") end
                if old and old.Session and old.Session.Id ~= session and old.Session.Until > os.time() then return nil end
                local value = old and normalize(old.Data) or defaults()
                offline = applyOffline(value, os.time())
                return {Data = value, Session = {Id = session, Until = os.time() + Config.LeaseSeconds}}
            end)
        end)
        if ok and result then data = result.Data end
    end
    if not ok or not data then
        if player.Parent then player:Kick("Your saved data is unavailable or active in another server. Please retry shortly.") end
        return
    end
    Profiles.Active[player] = {Data = data, Busy = false, Closing = false, LastSaved = os.time(), SavedStats = savedStats(data)}
    if not player.Parent or shuttingDown then Profiles.close(player); return end
    player:SetAttribute("HarborProfileReady", true)
    Profiles.Changed:Fire(player)
    if offline then Profiles.OfflineCredited:Fire(player, offline) end
end
function Profiles.close(player)
    local r = Profiles.Active[player]
    if not r or r.Closing then return end
    r.Closing = true
    local deadline = os.clock() + 22
    while r.Busy and os.clock() < deadline do task.wait(.1) end
    if not r.Busy then
        if Profiles.BeforeClose and not r.Lost then
            local draft=clone(r.Data)
            local ok=pcall(Profiles.BeforeClose,player,draft)
            if ok then r.Data=draft else warn("[Harbor] Final playtime update failed") end
        end
        local saved = Profiles.save(player, true)
        if not saved and not r.Lost and os.clock() < deadline then Profiles.save(player, true) end
    end
    Profiles.Active[player] = nil
end
-- Durable outbox: debit is persisted before credit; inbox receipts make retries idempotent.
-- No client-supplied draft/recipient ever reaches this layer.
local function persist(player,r,draft)
    if memory then r.Data=draft;return true end
    local ok,result=retry(function()
        return store:UpdateAsync("u_"..player.UserId,function(old)
            if type(old)~="table" or not old.Session or old.Session.Id~=session then return nil end
            return {Data=draft,Session={Id=session,Until=os.time()+Config.LeaseSeconds}}
        end)
    end)
    if ok and result then r.Data=draft;r.LastSaved=os.time();r.SavedStats=savedStats(draft);return true end
    -- Ambiguous writes must never be overwritten with stale in-memory balances.
    r.Lost=true
    if player.Parent then player:Kick("Data verification interrupted. Rejoin to recover your pending transfer safely.") end
    return false
end
local function deliver(id,tx)
    local target=Players:GetPlayerByUserId(tx.Target)
    local r=target and Profiles.Active[target]
    if not r or r.Busy or r.Closing or r.Lost then return false end
    r.Busy=true
    local draft=clone(r.Data);local receipt="in:"..id
    local fresh=not draft.Receipts[receipt]
    if fresh then
        -- A reserved debit can temporarily wait rather than clipping/destroying money.
        if draft.DCoins+tx.Amount>Config.MaxBalance then r.Busy=false;return false end
        draft.DCoins+=tx.Amount;draft.Received+=tx.Amount;draft.Receipts[receipt]=true
    end
    local ok=persist(target,r,draft);r.Busy=false
    if ok then Profiles.Changed:Fire(target);if fresh then Profiles.DonationDelivered:Fire(target,tx.Sender or 0,tx.Amount) end end
    return ok
end
-- LEGACY DRAIN ONLY: player-to-player donations are removed from V1, so nothing creates Outbox entries any
-- more. Transfers that were already debited before the update are still delivered (idempotent via inbox
-- receipts) so no player loses currency they already sent. See docs/DECISIONS.md.
function Profiles.reconcile(player)
    local r=Profiles.Active[player]
    if not r or r.Busy or r.Lost or r.Closing or next(r.Data.Outbox)==nil then return end
    r.Busy=true
    for id,tx in r.Data.Outbox do
        if deliver(id,tx) then
            local draft=clone(r.Data);draft.Outbox[id]=nil
            if not persist(player,r,draft) then break end
        end
    end
    r.Busy=false
end
-- Credits Coins an NPC donated to this player's stand and records it in history/daily stats.
-- Never yields: the caller debits the NPC in the same synchronous step, so the pair is atomic.
-- Duplicate protection is the NPC world ledger's transaction id (see Economy.receiveNpcDonation).
function Profiles.creditFromNpc(player, amount, record)
    if type(amount)~="number" or amount~=amount or amount%1~=0 or amount<1 then return false,"Invalid amount." end
    return Profiles.mutate(player,function(data)
        if data.Coins+amount>Config.MaxBalance then return false,"Balance limit reached." end
        data.Coins+=amount
        data.CoinsRaised+=amount
        IncomeStats.record(data.Stats,{
            id=0,t=os.time(),fromId=record.fromId,fromName=record.fromName,amount=amount,
            currency=PRIMARY,source=record.source,standId=record.standId,
        },statsOptions)
        return true
    end)
end
-- Remembers the player's last stand offers so the next claim restores them.
function Profiles.setStandOffers(player, offers)
    return Profiles.mutate(player,function(data)
        data.Stand.Offers=sanitizeOffers(offers)
        return true
    end)
end
-- Records a meaningful interaction with an NPC persona (§12.9): refreshes its 3-day memory, updates its
-- opinion and the player's overall reputation, with the reason kept for the UI (§12.11).
function Profiles.recordRelationship(player, persona, event)
    return Profiles.mutate(player,function(data)
        Relationships.record(data.Memories,data.Reputation,persona.id,persona.name,persona.traits,event,os.time(),memoryOptions)
        return true
    end)
end
function Profiles.opinion(player, personaId)
    local data=Profiles.get(player)
    if not data or not personaId then return 0 end
    return Relationships.opinion(data.Memories,personaId,os.time(),memoryOptions)
end
-- Personas this player remembers (unexpired), for NPCs returning in a later session (§12.1).
function Profiles.rememberedPersonas(player)
    local data=Profiles.get(player);local list={}
    if not data then return list end
    local now=os.time()
    for id,mem in data.Memories do
        if now-mem.t<=memoryOptions.retentionSeconds then table.insert(list,{id=id,name=mem.n}) end
    end
    table.sort(list,function(a,b) return a.id<b.id end)
    return list
end
-- Profile side of a player donation at an NPC's stand (§5.2, §12.8 step 7). Non-yielding and all-or-nothing:
-- debit Coins, always grant the deterministic DCoins reward, credit an optional return gift, remember it.
-- The caller moves the Coins into the NPC world in the same synchronous step.
function Profiles.donateToNpc(player, amount, persona, returned)
    if type(amount)~="number" or amount~=amount or amount%1~=0 or amount<1 then return false,"Invalid amount.",0 end
    local reward=SecondaryCurrency.reward(amount)
    local ok,message=Profiles.mutate(player,function(data)
        if data.Coins<amount then return false,"Not enough Coins." end
        if data.Coins-amount+returned>Config.MaxBalance or data.DCoins+reward>Config.MaxBalance then return false,"Balance limit reached." end
        data.Coins-=amount
        data.CoinsDonated+=amount
        data.DCoins+=reward
        if returned>0 then
            data.Coins+=returned
            data.CoinsRaised+=returned
            IncomeStats.record(data.Stats,{
                id=0,t=os.time(),fromId=persona.id,fromName=persona.name,amount=returned,
                currency=PRIMARY,source="NpcReturnDonation",
            },statsOptions)
        end
        Relationships.record(data.Memories,data.Reputation,persona.id,persona.name,persona.traits,"DonatedToNpc",os.time(),memoryOptions)
        return true
    end)
    return ok,message,(ok and reward or 0)
end

function Profiles.init()
    if not memory then store = DSS:GetDataStore(Config.DataStore) end
    Players.PlayerAdded:Connect(function(p) task.spawn(Profiles.load, p) end)
    Players.PlayerRemoving:Connect(Profiles.close)
    for _, p in Players:GetPlayers() do task.spawn(Profiles.load, p) end
    task.spawn(function()
        while not shuttingDown do
            task.wait(Config.AutosaveSeconds)
            for p, r in Profiles.Active do
                if not r.Closing then task.spawn(Profiles.save, p, false) end
            end
        end
    end)
    game:BindToClose(function()
        shuttingDown = true
        for p in Profiles.Active do task.spawn(Profiles.close, p) end
        local deadline = os.clock() + 25
        while next(Profiles.Active) and os.clock() < deadline do task.wait(.1) end
    end)
    task.spawn(function()
        while not shuttingDown do
            task.wait(5)
            for player in Profiles.Active do task.spawn(Profiles.reconcile,player) end
        end
    end)
    print("[Harbor] Profiles ready: " .. (memory and "STUDIO MEMORY ONLY" or "persistent session leases"))
end
return Profiles
