local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("HarborShared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local Profiles = require(script.Parent.Profiles)
local NpcCore = game:GetService("ServerScriptService"):WaitForChild("NpcCore")
local Ledger = require(NpcCore.Logic.Ledger)
local NpcBrain = require(NpcCore.Logic.NpcBrain)
local Transactions = require(NpcCore.Logic.Transactions)
local NpcEconomy = require(NpcCore.Config.Economy)
local Economy = {}
local clock = {}
local looks = {}
local function applyLook(player)
    local data = Profiles.get(player)
    local char = player.Character
    local head = char and char:FindFirstChild("Head")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not data or not head or not root then return end
    local equipped = data.Equipped
    local key = (equipped.Title or "") .. ":" .. (equipped.Effect or "") .. ":" .. (equipped.Accessory or "")
    if looks[player] and looks[player].Character == char and looks[player].Key == key then return end
    looks[player] = {Character = char, Key = key}
    local old = char:FindFirstChild("HarborCosmetics")
    if old then old:Destroy() end
    local folder = Instance.new("Folder"); folder.Name = "HarborCosmetics"; folder.Parent = char
    -- Attachments belong to their parts, not the cosmetic folder. Explicitly clean them.
    for _, name in {"HarborTrailA", "HarborTrailB"} do
        local a = root:FindFirstChild(name); if a then a:Destroy() end
    end
    if equipped.Title and (Config.Shop[equipped.Title] or equipped.Title=="Supporter") then
        local gui = Instance.new("BillboardGui"); gui.Name = "Title"; gui.Adornee = head
        gui.Size = UDim2.fromOffset(180,30); gui.StudsOffsetWorldSpace = Vector3.new(0,2.5,0)
        gui.MaxDistance = 55; gui.Parent = folder
        local text = Instance.new("TextLabel"); text.Size = UDim2.fromScale(1,1); text.BackgroundTransparency = 1
        text.Font = Enum.Font.GothamBold; text.TextSize = 14; text.TextColor3 = Color3.fromRGB(255,218,133)
        text.TextStrokeTransparency = .5; text.Text = equipped.Title=="Supporter" and "SUPPORTER" or string.gsub(Config.Shop[equipped.Title].Label, " title", ""); text.Parent = gui
    end
    if equipped.Effect == "SeaTrail" then
        local a = Instance.new("Attachment"); a.Name="HarborTrailA"; a.Position=Vector3.new(-.6,0,0); a.Parent=root
        local b = Instance.new("Attachment"); b.Name="HarborTrailB"; b.Position=Vector3.new(.6,0,0); b.Parent=root
        local trail = Instance.new("Trail"); trail.Attachment0=a; trail.Attachment1=b
        trail.Lifetime=.45; trail.MinLength=.2; trail.Color=ColorSequence.new(Color3.fromRGB(82,216,195))
        trail.Transparency=NumberSequence.new(.3,1); trail.Parent=folder
    end
    if equipped.Accessory == "HarborHat" then
        local orb=Instance.new("Part"); orb.Name="HarborLantern"; orb.Shape=Enum.PartType.Ball
        orb.Size=Vector3.new(.5,.5,.5); orb.Color=Color3.fromRGB(82,216,195); orb.Material=Enum.Material.Neon
        orb.CanCollide=false; orb.CanTouch=false; orb.CanQuery=false; orb.Massless=true
        orb.CFrame=head.CFrame*CFrame.new(0,1.6,0); orb.Parent=folder
        local weld=Instance.new("WeldConstraint"); weld.Part0=head; weld.Part1=orb; weld.Parent=orb
    end
end
function Economy.action(player, action, key)
    return Profiles.mutate(player, function(data)
        if action == "Daily" then return Rules.daily(data, os.time(), Config)
        elseif action == "Shop" then return Rules.buy(data, key, os.time(), Config)
        elseif action == "Equip" then return Rules.equip(data, key, Config)
        elseif action == "Quest" then return Rules.quest(data, key, Config) end
        return false, "Unknown action."
    end)
end
-- NPC -> player stand donation. Debits the NPC's donation budget in the NPC world ledger and credits the
-- player's profile in one non-yielding step: either both happen or neither (refund on any failure).
-- `world` is the NpcDirector ledger, `playerAccount` the player's account inside it, `npc` an NpcBrain agent.
function Economy.receiveNpcDonation(world, txId, npc, player, playerAccount, amount, standId)
    local ok, err = Ledger.transfer(world, txId, npc.budget, playerAccount, Config.Currencies.Primary, amount, true)
    if not ok then return false, err end
    local credited, message = Profiles.creditFromNpc(player, amount, {
        fromId = npc.id, fromName = npc.name, source = "NpcStandDonation", standId = standId,
    })
    if not credited then
        Ledger.refund(world, txId, npc.budget, playerAccount, Config.Currencies.Primary, amount)
        return false, message
    end
    npc.donationsMade += 1
    return true, nil
end
-- Player -> NPC donation at the NPC's stand (§5.2). One synchronous, non-yielding step:
--   1. the NPC decides on a return gift (separate random outcome, Coins from its own funds),
--   2. the profile is debited and receives the deterministic DCoins reward (+ return gift) atomically,
--   3. the donated Coins enter the NPC world and the return gift leaves it, through the ledger.
-- Step 3 cannot fail once step 2 succeeded: transaction ids are fresh and the NPC always holds the returned
-- amount (at most half the gift it just received).
function Economy.playerDonateToNpc(world, txId, npc, player, playerAccount, amount, willingness, rng)
    if not table.find(npc.offers, amount) then return false, "That amount isn't offered here." end
    local returned = Transactions.rollReturn(npc, amount, willingness, rng)
    local persona = {id = npc.personaId or npc.id, name = npc.name, traits = npc.traits}
    local ok, message, reward = Profiles.donateToNpc(player, amount, persona, returned)
    if not ok then return false, message end
    local primary = Config.Currencies.Primary
    local receiver = NpcBrain.receivingAccount(npc, NpcEconomy.NpcReceivedFundsTo)
    Ledger.mint(world, txId .. ":in", receiver, primary, amount, "PlayerInflow")
    receiver.raised += amount
    playerAccount.donated += amount
    if returned > 0 then
        local source = if Ledger.balance(npc.budget, primary) >= returned then npc.budget else npc.wallet
        Ledger.transfer(world, txId .. ":ret", source, playerAccount, primary, returned, true)
    end
    return true, {amount = amount, dcoins = reward, returned = returned}
end
function Economy.claimed(player)
    return Profiles.mutate(player, function(data) data.Claims = math.min(1000000, data.Claims + 1); return true end)
end
-- leaderstats name -> profile field. Coins = primary, DCoins = secondary (APPROVED); Pearls is legacy.
local LEADERSTATS = {{"Coins", "Coins"}, {"DCoins", "DCoins"}, {"Pearls", "Pearls"}, {"Raised", "CoinsRaised"}, {"Donated", "CoinsDonated"}}
local function stats(player)
    local data = Profiles.get(player); if not data then return end
    local folder = player:FindFirstChild("leaderstats")
    if not folder then folder=Instance.new("Folder");folder.Name="leaderstats";folder.Parent=player end
    for _, pair in LEADERSTATS do
        local value=folder:FindFirstChild(pair[1])
        if not value then value=Instance.new("IntValue");value.Name=pair[1];value.Parent=folder end
        value.Value=data[pair[2]]
    end
    applyLook(player)
end
function Economy.init(remote)
    Profiles.BeforeClose=function(player,data)
        local previous=clock[player]
        if previous then Rules.tick(data,math.floor(os.clock()-previous),os.time(),Config) end
        clock[player]=nil;looks[player]=nil
    end
    Profiles.Changed.Event:Connect(function(p)
        if not clock[p] then clock[p]=os.clock() end
        if p.Parent then stats(p) end
    end)
    local function added(p)
        p.CharacterAdded:Connect(function(char)
            task.spawn(function()
                local head=char:WaitForChild("Head",8)
                local root=char:WaitForChild("HumanoidRootPart",8)
                if head and root and p.Parent then applyLook(p) end
            end)
        end)
        if Profiles.get(p) then clock[p]=os.clock();stats(p) end
    end
    Players.PlayerAdded:Connect(added)
    -- Profile close flushes the final partial reward interval before saving.
    for _, p in Players:GetPlayers() do added(p) end
    task.spawn(function()
        while true do
            task.wait(15)
            for p, previous in clock do
                local elapsed=math.floor(os.clock()-previous)
                local reward=0
                local ok=Profiles.mutate(p,function(data)
                    local accepted, count=Rules.tick(data,elapsed,os.time(),Config);reward=count;return accepted
                end)
                if ok then
                    clock[p]=previous+math.min(elapsed,60)
                    if reward>0 then remote:FireClient(p,"Notice","Harbor time reward earned! +Coins and Pearls") end
                end
            end
        end
    end)
    print("[Harbor] Economy ready: Coins, Pearls, daily, quests and cosmetics")
end
return Economy
