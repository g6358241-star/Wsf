-- Test D only. No MarketplaceService, Robux, products or client-issued NPC grants.
local Players=game:GetService('Players')
local Http=game:GetService('HttpService')
local RS=game:GetService('ReplicatedStorage')
local Config=require(RS:WaitForChild('HarborShared').Config)
local Profiles=require(script.Parent.Profiles)
local Economy=require(script.Parent.Economy)
local Booths=require(script.Parent.Booths)
local M={};local remote;local last={};local rng=Random.new()
function M.player(player,boothId,amount,requestId,expectedOwner)
 if type(boothId)~='string' or #boothId>48 or type(requestId)~='string' or #requestId<16 or #requestId>64 or not requestId:match('^[%w%-]+$') then return false,'Invalid donation request.' end
 local e=Booths.entries[boothId];local owner=e and e.owner
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 if not owner or owner==player or not owner.Parent or expectedOwner~=owner.UserId or not root or (root.Position-e.anchor.Position).Magnitude>18 then return false,'Move close to the occupied booth and select it again.' end
 local now=os.clock();if now-(last[player] or -10)<1 then return false,'Please wait.' end;last[player]=now
 return Economy.donate(player,owner,amount,requestId)
end
local function notice(owner,name,userId,amount,isNPC,model)
 if not owner.Parent then return end
 remote:FireClient(owner,'Donation',{Name=name,UserId=userId,Amount=amount,Currency='D',NPC=isNPC,NPCModel=model,Kind='TestCurrency'})
 local id=Booths.owned[owner.UserId];local entry=id and Booths.entries[id]
 if entry and entry.owner==owner then
  for _,viewer in Players:GetPlayers() do
   local root=viewer.Character and viewer.Character:FindFirstChild('HumanoidRootPart')
   if root and (root.Position-entry.anchor.Position).Magnitude<=120 then remote:FireClient(viewer,'DonationEffect',{BoothModel=entry.model,Amount=amount}) end
  end
 end
end
function M.init(event)
 remote=event
 Profiles.DonationDelivered.Event:Connect(function(owner,senderId,amount)
  local sender=Players:GetPlayerByUserId(senderId);notice(owner,sender and sender.DisplayName or ('Player '..senderId),senderId,amount,false)
 end)
 Players.PlayerRemoving:Connect(function(player)last[player]=nil end)
 task.spawn(function()
  local NPC=require(script.Parent.NPCService)
  while true do
   task.wait(rng:NextNumber(Config.NPC.DonationIntervalMin,Config.NPC.DonationIntervalMax))
   if not NPC.Running then continue end
   local occupied={};for _,entry in Booths.entries do if entry.owner and entry.owner.Parent and Profiles.get(entry.owner) then table.insert(occupied,entry) end end
   if #occupied==0 then continue end
   local entry=occupied[rng:NextInteger(1,#occupied)];local owner=entry.owner
   local available={};for _,agent in NPC.Agents do if agent.model and agent.model.Parent and agent.root and not agent.rebuilding and not agent.visit and agent.state~='Chat' and agent.state~='VisitStand' then table.insert(available,agent) end end
   table.sort(available,function(a,b)return (a.root.Position-entry.anchor.Position).Magnitude<(b.root.Position-entry.anchor.Position).Magnitude end)
   local agent=available[1];if not agent then continue end
   NPC.VisitBooth(agent.model,entry.model,entry.anchor,function(model)
    if entry.owner~=owner or not owner.Parent then return end
    local amount=rng:NextInteger(Config.NPC.DonationMin,Config.NPC.DonationMax)
    if Economy.npcDonate(owner,amount,Http:GenerateGUID(false)) then
     local hum=model:FindFirstChildOfClass('Humanoid');notice(owner,hum and hum.DisplayName or 'Visitor',0,amount,true,model)
    end
   end)
  end
 end)
end
return M
