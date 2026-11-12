-- Session lease + write serialization. No client can access profile tables.
local Players = game:GetService("Players")
local DSS = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("HarborShared").Config)
local NpcCore = game:GetService("ServerScriptService"):WaitForChild("NpcCore")
local IncomeStats = require(NpcCore.Logic.IncomeStats)
local PersistenceConfig = require(NpcCore.Config.Persistence)
local OfflineConfig = require(NpcCore.Config.Offline)
local Profiles = {Active = {}, Changed = Instance.new("BindableEvent"), DonationDelivered=Instance.new("BindableEvent")}
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
        Stand = {Offers = {}}, Stats = IncomeStats.new()}
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
    return {Donated=data.Donated,Received=data.Received,PlaySeconds=data.PlaySeconds}
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
    for _, key in {"DCoins", "Coins", "Pearls", "XP", "PlaySeconds", "Donated", "Received", "LastDaily", "Inventory", "Equipped", "Quests", "BoostUntil", "Claims", "CoinsRaised", "CoinsDonated", "Stand"} do
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
function Profiles.save(player, release)
    local r = Profiles.Active[player]
    if not r or r.Busy or r.Lost then return false end
    r.Busy = true
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
    local data
    local ok, result = true, nil
    if memory then data = defaults() else
        ok, result = retry(function()
            return store:UpdateAsync("u_" .. player.UserId, function(old)
                if old ~= nil and type(old) ~= "table" then error("Invalid record") end
                if old and old.Session and old.Session.Id ~= session and old.Session.Until > os.time() then return nil end
                local value = old and normalize(old.Data) or defaults()
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
function Profiles.reconcile(player)
    local r=Profiles.Active[player]
    if not r or r.Busy or r.Lost or r.Closing then return end
    r.Busy=true
    for id,tx in r.Data.Outbox do
        if deliver(id,tx) then
            local draft=clone(r.Data);draft.Outbox[id]=nil
            if not persist(player,r,draft) then break end
        end
    end
    r.Busy=false
end
function Profiles.transfer(sender,receiver,amount,id)
    if sender==receiver or type(id)~="string" or #id>120 or type(amount)~="number" or amount~=amount or amount%1~=0 or amount<Config.TestCurrency.MinDonation or amount>Config.TestCurrency.MaxDonation then return false,"Invalid donation." end
    local r=Profiles.Active[sender];local target=Profiles.Active[receiver]
    if not r or r.Busy or r.Closing or r.Lost or not target or target.Busy or target.Closing or target.Lost then return false,"Profile busy. Retry shortly." end
    local key=tostring(sender.UserId)..":"..id
    if r.Data.Receipts["out:"..key] then return false,"This donation was already accepted." end
    if r.Data.DCoins<amount then return false,"Not enough D." end
    if target.Data.DCoins+amount>Config.MaxBalance then return false,"Recipient balance limit." end
    r.Busy=true
    local draft=clone(r.Data);draft.DCoins-=amount;draft.Donated+=amount
    draft.Outbox[key]={Target=receiver.UserId,Sender=sender.UserId,Amount=amount};draft.Receipts["out:"..key]=true
    local ok=persist(sender,r,draft);r.Busy=false
    if not ok then return false,"Donation verification interrupted." end
    Profiles.Changed:Fire(sender);Profiles.reconcile(sender)
    return true,r.Data.Outbox[key] and "Donation reserved; delivery will retry automatically." or "Donation sent."
end
function Profiles.testGrant(player,amount,id)
    local r=Profiles.Active[player]
    if not r or r.Busy or r.Lost or r.Closing or type(amount)~="number" or amount%1~=0 or amount<1 or amount>Config.NPC.DonationMax then return false end
    local key="npc:"..id
    if r.Data.Receipts[key] or r.Data.DCoins+amount>Config.MaxBalance then return false end
    r.Busy=true;local draft=clone(r.Data);draft.DCoins+=amount;draft.Received+=amount;draft.Receipts[key]=true
    local ok=persist(player,r,draft);r.Busy=false;if ok then Profiles.Changed:Fire(player) end;return ok
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
