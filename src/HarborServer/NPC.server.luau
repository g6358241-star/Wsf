-- Starts NPC locomotion and the NPC world director. Kept separate from Main so a locomotion failure
-- never takes down profiles, booths or purchases.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local service=require(script.Parent.NPCService)
local Booths=require(script.Parent.Booths)
local Economy=require(script.Parent.Economy)
local Donations=require(script.Parent.Donations)
local Profiles=require(script.Parent.Profiles)
local Director=require(script.Parent.NpcDirector)
local Requests=require(script.Parent.Requests)
local Relationships=require(game:GetService('ServerScriptService'):WaitForChild('NpcCore').Logic.Relationships)

local ok,err=pcall(service.Start)
if not ok then service.Stop();warn('[NPC] Startup failed: '..tostring(err));return end
while not Booths.Ready do task.wait(.1) end

-- Per-server TAB leaderboard data (player + NPCs, Donated/Raised). The UI reads this folder.
local game_=RS:WaitForChild('HarborGame')
local board=Instance.new('Folder');board.Name='Leaderboard';board.Parent=game_
local function publish(rows)
 local seen={}
 for rank,row in rows do
  seen[row.id]=true
  local entry=board:FindFirstChild(row.id)
  if not entry then entry=Instance.new('Configuration');entry.Name=row.id;entry.Parent=board end
  entry:SetAttribute('DisplayName',row.name);entry:SetAttribute('Donated',row.donated);entry:SetAttribute('Raised',row.raised)
  entry:SetAttribute('IsPlayer',row.isPlayer);entry:SetAttribute('Rank',rank)
 end
 for _,entry in board:GetChildren() do if not seen[entry.Name] then entry:Destroy() end end
end

local director=Director.new({
 now=os.clock,
 delay=function(seconds,fn) task.delay(seconds,fn) end,
 movement={
  spawn=service.Spawn,
  visitBooth=function(handle,boothId,onArrive,onFail)
   local model=service.BoothModel(boothId)
   if not model then task.spawn(onFail);return end
   service.VisitBooth(handle,model,onArrive,onFail)
  end,
  hold=service.Hold,
  wander=service.Wander,
  despawn=service.Despawn,
  approachPlayer=service.ApproachPlayer,
  say=service.Say,
  model=service.Model,
 },
 booths=Booths,
 economy=Economy,
 requests=Requests,
 getPlayer=function(userId)
  local player=Players:GetPlayerByUserId(userId)
  return player and Profiles.get(player) and player or nil
 end,
 notify=function(player,npcName,amount,handle)
  local a=service.Agents[handle]
  Donations.notify(player,npcName,amount,a and a.model)
 end,
 publish=publish,
 seed=game.JobId~='' and game.JobId or nil,
 -- Studio stress test: set Workspace attribute NpcStressTarget (e.g. 100) to fill the server quickly.
 targetPopulation=function() return workspace:GetAttribute('NpcStressTarget') or 0 end,
 -- Studio test switch: Workspace attribute NpcRequestTest = true makes stand NPCs ask at every check.
 forceRequests=function() return workspace:GetAttribute('NpcRequestTest')==true end,
 willingness=function(userId,personaId)
  local player=Players:GetPlayerByUserId(userId)
  return player and Relationships.willingness(Profiles.opinion(player,personaId)) or 1
 end,
 rememberedPersonas=function()
  local all={}
  for _,player in Players:GetPlayers() do
   for _,p in Profiles.rememberedPersonas(player) do table.insert(all,p) end
  end
  return all
 end,
})
service.Events.Lost.Event:Connect(function(npcId) director:lost(npcId) end)
director:start()
game:BindToClose(function() director:stop() end)
print(string.format('[NPC] Director started: serverWealth=%s', director.tier.id))

task.spawn(function()
 while true do
  task.wait(30)
  local s=director.stats
  local balanced,minted,held=director:audit()
  local folder=workspace:FindFirstChild('HarborNPCs')
  if folder then for k,v in s do if type(v)=='number' then folder:SetAttribute('Dir_'..k,v) end end end
  print(string.format('[NPC_DIRECTOR] active=%d spawned=%d departed=%d passes=%d inspections=%d decisions=%d toPlayer=%d (%d Coins) npcToNpc=%d standClaims=%d requests=%d requestDonations=%d returning=%d standGone=%d visitFailures=%d creditFailures=%d conserved=%s minted=%d accounted=%d',
   director.active,s.spawned,s.departed,s.passes,s.inspections,s.decisions,s.playerDonations,s.playerCoins,s.npcDonations,s.standClaims,s.requests,s.requestDonations,s.returning,s.standGone,s.visitFailures,s.creditFailures,tostring(balanced),minted,held))
  if not balanced then warn('[NPC_DIRECTOR] CONSERVATION CHECK FAILED') end
 end
end)
