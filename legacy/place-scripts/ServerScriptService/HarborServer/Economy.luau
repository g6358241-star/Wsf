local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("HarborShared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local Profiles = require(script.Parent.Profiles)
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
function Economy.donate(sender,receiver,amount,id)
    return Profiles.transfer(sender,receiver,amount,id)
end
function Economy.npcDonate(receiver,amount,id)
    return Profiles.testGrant(receiver,amount,id)
end
function Economy.claimed(player)
    return Profiles.mutate(player, function(data) data.Claims = math.min(1000000, data.Claims + 1); return true end)
end
local function stats(player)
    local data = Profiles.get(player); if not data then return end
    local folder = player:FindFirstChild("leaderstats")
    if not folder then folder=Instance.new("Folder");folder.Name="leaderstats";folder.Parent=player end
    for _, name in {"DCoins", "Coins", "Pearls", "Donated", "Received"} do
        local value=folder:FindFirstChild(name)
        if not value then value=Instance.new("IntValue");value.Name=name;value.Parent=folder end
        value.Value=data[name]
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
