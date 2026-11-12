-- Exactly one ProcessReceipt owner. Never grant from client/prompt-finished signals.
local Market = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("HarborShared")
local Config = require(Shared.Config)
local Rules = require(Shared.Rules)
local Profiles = require(script.Parent.Profiles)
local Booths = require(script.Parent.Booths)
local Purchases = {}
local remote
local last, busy = {}, {}
local transferReady = false
local function integer(n)
    return type(n)=="number" and n==n and n%1==0 and n>=0 and n<1000000000
end
local function feedback(player, amount, kind)
    remote:FireAllClients("Donation", {Name=player.DisplayName, UserId=player.UserId, Amount=amount, Kind=kind})
end
local function receipt(info)
    local deferred=Enum.ProductPurchaseDecision.NotProcessedYet
    if type(info)~="table" or type(info.PurchaseId)~="string" then return deferred end
    local player=Players:GetPlayerByUserId(info.PlayerId)
    if not player or not Profiles.get(player) then return deferred end
    local product
    for _, item in Config.Products do if item.Id>0 and item.Id==info.ProductId then product=item;break end end
    if not product then return deferred end -- Keep retired IDs in Config until all receipts resolve.
    local ok,fresh=Profiles.receipt(player,"product:"..info.PurchaseId,function(data)
        Rules.credit(data,"Coins",product.Coins,Config)
        Rules.credit(data,"Pearls",product.Pearls,Config)
    end)
    if not ok then return deferred end
    if fresh then feedback(player,integer(info.CurrencySpent) and info.CurrencySpent or 0,"GameSupport") end
    return Enum.ProductPurchaseDecision.PurchaseGranted
end
local function transferReceipt(info, field)
    if type(info)~="table" or type(info.TransferRequestId)~="string" or not integer(info.CurrencySpent) then
        return Enum.ReceiptDecision.NotProcessedYet
    end
    local player=Players:GetPlayerByUserId(info.PlayerId)
    if not player or not Profiles.get(player) then return Enum.ReceiptDecision.NotProcessedYet end
    -- Both sides commit independently in THEIR own profile; no fragile cross-key transaction.
    local ok,fresh=Profiles.receipt(player,"transfer:"..field..":"..info.TransferRequestId,function(data)
        data[field]=math.min(Config.MaxBalance,data[field]+info.CurrencySpent)
    end)
    if not ok then return Enum.ReceiptDecision.NotProcessedYet end
    if fresh then feedback(player,info.CurrencySpent,field) end
    return Enum.ReceiptDecision.Processed
end
function Purchases.refreshPass(player)
    local pass=Config.Passes.Supporter
    if pass.Id<=0 or RunService:IsStudio() then return false,"Supporter pass is not configured for live use." end
    local ok,owns=pcall(Market.UserOwnsGamePassAsync,Market,player.UserId,pass.Id)
    if not ok then return false,"Pass ownership is temporarily unavailable." end
    return Profiles.mutate(player,function(data)
        data.Passes.Supporter=owns
        data.Inventory.Supporter=owns or nil
        if not owns and data.Equipped.Title=="Supporter" then data.Equipped.Title=nil end
        return true,owns and "Supporter title unlocked. Equip it in the shop." or "Supporter pass not owned."
    end)
end
function Purchases.action(player, action, key)
    if RunService:IsStudio() then return false,"Real Robux purchases are disabled in Studio. Use a published test experience." end
    if not Profiles.get(player) then return false,"Profile not ready." end
    if busy[player] or os.clock()-(last[player] or -100)<8 then return false,"Please wait before another purchase prompt." end
    last[player]=os.clock()
    if action=="RefreshPass" then return Purchases.refreshPass(player) end
    if action=="Transfer" then
        if not Config.TransfersEnabled or not transferReady then return false,"Player transfers are not enabled yet." end
        local entry=Booths.entries[key]
        local owner=entry and entry.owner
        local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not owner or not owner.Parent or owner==player or not root or (root.Position-entry.anchor.Position).Magnitude>18 then
            return false,"Move close to another player's occupied booth."
        end
        local amount=entry.amount -- Server-owned, filtered booth preference. NEVER client amount/recipient.
        if not integer(amount) or amount<5 or amount>10000 then return false,"Invalid transfer amount." end
        busy[player]=true
        local ok=pcall(Market.PromptRobuxTransferAsync,Market,player,owner.UserId,amount)
        busy[player]=nil
        return ok,ok and "Review the official Roblox transfer prompt. Receiver gets 90%; game gets 10%." or "Transfer unavailable. Check Roblox Plus, account eligibility and experience setup."
    end
    local entry=action=="Product" and Config.Products[key] or action=="Pass" and Config.Passes[key]
    if not entry or entry.Id<=0 then return false,"This offer is not configured yet." end
    local ok=pcall(function()
        if action=="Product" then Market:PromptProductPurchase(player,entry.Id)
        else Market:PromptGamePassPurchase(player,entry.Id) end
    end)
    return ok,ok and "Review the official Roblox price before confirming. This supports the game, not a booth owner." or "Roblox purchase prompt unavailable."
end
function Purchases.init(event)
    remote=event
    Market.ProcessReceipt=receipt
    local ok=pcall(function()
        Market:BindReceiptHandler(Enum.ReceiptType.RobuxTransferSender,function(info) return transferReceipt(info,"Donated") end)
        Market:BindReceiptHandler(Enum.ReceiptType.RobuxTransferReceiver,function(info) return transferReceipt(info,"Received") end)
    end)
    transferReady=ok
    workspace:SetAttribute("HarborTransfersEnabled",ok and Config.TransfersEnabled and not RunService:IsStudio())
    Market.PromptGamePassPurchaseFinished:Connect(function(player,id,purchased)
        if purchased and id==Config.Passes.Supporter.Id and id>0 then
            task.spawn(function()
                local success,message=Purchases.refreshPass(player)
                if player.Parent then remote:FireClient(player,"Notice",message) end
            end)
        end
    end)
    local function added(player)
        if Config.Passes.Supporter.Id<=0 then return end
        task.spawn(function()
            for _=1,30 do
                if not player.Parent then return end
                if Profiles.get(player) then Purchases.refreshPass(player);return end
                task.wait(1)
            end
        end)
    end
    Players.PlayerAdded:Connect(added)
    Players.PlayerRemoving:Connect(function(p) last[p]=nil;busy[p]=nil end)
    for _,p in Players:GetPlayers() do added(p) end
    print("[Harbor] Purchases ready; zero IDs disabled; transfers "..(ok and "API bound" or "unsupported"))
end
return Purchases
