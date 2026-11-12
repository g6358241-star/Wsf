-- NPC donation requests (brief §5, §12.8). Owns the player side of the flow, remote validation and reactions;
-- NpcDirector owns NPC movement and calls in here. One active request per player at a time.
--
-- Stages: Approaching (NPC walking to the player) -> Prompt (Accept/Decline above the NPC) -> Leading (NPC walks
-- back to its stand, player follows) -> AtStand (player picks one of the NPC's own amounts) -> finished.
-- Accepting is not a donation: Coins move only after the player picks an amount at the stand.
local Players=game:GetService('Players')
local NpcCore=game:GetService('ServerScriptService'):WaitForChild('NpcCore')
local NpcConfig=require(NpcCore.Config.Npc)
local NpcBrain=require(NpcCore.Logic.NpcBrain)
local Relationships=require(NpcCore.Logic.Relationships)
local SecondaryCurrency=require(NpcCore.Logic.SecondaryCurrency)
local Profiles=require(script.Parent.Profiles)
local Economy=require(script.Parent.Economy)
local Booths=require(script.Parent.Booths)

local R={active={} :: {[any]: any},cooldownUntil={},nextId=0,outcomes={}}
local remote
local cfg=NpcConfig.Request

local PHRASES={
 Ask={'Could you support my stand?','Hey! Would you donate to my stand?','Got a moment for my stand?'},
 Follow={'Great, follow me!','Wonderful! This way.'},
 Call={'Over here!','This way, my stand is close!','Are you still coming?'},
 Calm={'No worries, have a nice day!','Alright, maybe next time.'},
 Upset={'Oh... okay then.','Hmph. Fine.'},
 Surprised={'Oh! Really? Okay.','Huh, not even a little?'},
 Joke={'Worth a try! Ha.','My wallet will survive. Probably.'},
 Thanks={'Thank you so much!','You made my day!'},
 Return={'Here, a little something back for you!','Take this, for being kind!'},
 Offended={'You said you would come...','I waited for you.'},
 Left={'Oh, maybe another time.','Okay, see you around.'},
}

local function persona(agent)
 return {id=agent.personaId or agent.id,name=agent.name,traits=agent.traits}
end
local function rootOf(player)
 local char=player.Character
 return char and char:FindFirstChild('HumanoidRootPart')
end
local function near(player,standId,radius)
 local root=rootOf(player);local entry=Booths.entries[standId]
 return root~=nil and entry~=nil and (root.Position-entry.anchor.Position).Magnitude<=radius
end
local function say(st,key)
 local d=st.ctx.director;local list=PHRASES[key]
 d.deps.movement.say(st.ctx.live.handle,list[d.rng:int(1,#list)])
end
local function finish(player,st,outcome)
 if R.active[player]~=st then return end
 R.active[player]=nil
 R.cooldownUntil[player]=os.clock()+(workspace:GetAttribute('NpcRequestTest')==true and 10 or cfg.playerCooldownSeconds)
 R.outcomes[outcome]=(R.outcomes[outcome] or 0)+1
 if player.Parent then remote:FireClient(player,'NpcRequestClosed',{Id=st.id,Outcome=outcome}) end
 if st.ctx then task.spawn(st.ctx.onDone) end
end
local function remember(player,st,event)
 Profiles.recordRelationship(player,persona(st.ctx.live.agent),event)
end

-- Director API ------------------------------------------------------------------------------------
-- Picks a player this NPC may approach and reserves them so no other NPC asks at the same time.
function R.reserve(agent)
 local now=os.clock()
 for _,player in Players:GetPlayers() do
  if Profiles.get(player) and not R.active[player] and now>=(R.cooldownUntil[player] or 0) and rootOf(player) then
   R.active[player]={stage='Approaching',agentId=agent.id}
   return player
  end
 end
 return nil
end
function R.release(player,agentId)
 local st: any=R.active[player]
 if st and st.stage=='Approaching' and st.agentId==agentId then R.active[player]=nil end
end
-- The NPC has reached the player: show the Accept/Decline prompt. ctx = {director, live, onDone}.
function R.open(player,ctx)
 local st: any=R.active[player]
 if not st or st.stage~='Approaching' or st.agentId~=ctx.live.agent.id or not player.Parent then task.spawn(ctx.onDone);return end
 R.nextId+=1
 st.id=R.nextId;st.ctx=ctx;st.stage='Prompt'
 local mv=ctx.director.deps.movement
 mv.hold(ctx.live.handle,cfg.promptSeconds+2,function() end)
 say(st,'Ask')
 remote:FireClient(player,'NpcRequest',{Id=st.id,Name=ctx.live.agent.name,Model=mv.model and mv.model(ctx.live.handle) or nil,Seconds=cfg.promptSeconds})
 local id=st.id
 task.delay(cfg.promptSeconds,function()
  -- No answer is treated as a brief distraction: no relationship penalty (§12.11).
  local cur=R.active[player]
  if cur==st and cur.stage=='Prompt' and cur.id==id then finish(player,st,'NoAnswer') end
 end)
end
-- The NPC left the server (its time ran out or its character was lost): close without penalties.
function R.npcGone(agentId)
 for player,st in R.active do
  if st.agentId==agentId then
   R.active[player]=nil
   if st.id and player.Parent then remote:FireClient(player,'NpcRequestClosed',{Id=st.id,Outcome='NpcLeft'}) end
  end
 end
end
---------------------------------------------------------------------------------------------------
local function toStand(player,st)
 local agent=st.ctx.live.agent
 st.stage='AtStand'
 local offers={}
 for _,amount in agent.offers do table.insert(offers,{Amount=amount,DCoins=SecondaryCurrency.reward(amount)}) end
 local data=Profiles.get(player)
 remote:FireClient(player,'NpcStand',{Id=st.id,Name=agent.name,Offers=offers,Coins=data and data.Coins or 0,Seconds=cfg.choiceSeconds})
 local id=st.id
 task.delay(cfg.choiceSeconds,function()
  if R.active[player]==st and st.stage=='AtStand' and st.id==id then R.leave(player,id) end
 end)
end
local function lead(player,st)
 local lastCall=os.clock()
 while R.active[player]==st and st.stage=='Leading' do
  task.wait(1)
  if R.active[player]~=st or st.stage~='Leading' then return end
  local agent=st.ctx.live.agent;local standId=agent.ownedStandId
  local now=os.clock()
  if st.npcArrived and standId and near(player,standId,cfg.standReachStuds) then toStand(player,st);return end
  if now>st.deadline then
   -- Penalised only after the grace period plus this NPC's own patience (§12.8 step 9, §12.11).
   say(st,'Offended');remember(player,st,'IgnoredAfterAccept');finish(player,st,'Ignored');return
  end
  if now-lastCall>=cfg.callEverySeconds and not (standId and near(player,standId,cfg.standReachStuds)) then
   lastCall=now;say(st,'Call')
  end
 end
end
-- Remote handlers (validated; the client only sends intent) -----------------------------------------
function R.answer(player,id,accept)
 local st: any=R.active[player]
 if not st or st.id~=id or st.stage~='Prompt' or type(accept)~='boolean' then return false,'This request is no longer active.' end
 local d,l=st.ctx.director,st.ctx.live;local agent=l.agent
 if not accept then
  local reaction=NpcBrain.declineReaction(agent,d.rng)
  say(st,reaction);remember(player,st,'DeclinedRequest');finish(player,st,'Declined')
  return true,nil
 end
 local standId=agent.ownedStandId
 if not standId then finish(player,st,'NpcLost');return false,'This visitor no longer has a stand.' end
 local now=os.clock()
 st.stage='Leading';st.deadline=now+cfg.followGraceSeconds+NpcBrain.callPersistence(agent)
 say(st,'Follow')
 remote:FireClient(player,'NpcRequestUpdate',{Id=st.id,Stage='Leading',Name=agent.name,Seconds=st.deadline-now})
 d.deps.movement.visitBooth(l.handle,standId,function()
  if R.active[player]==st then st.npcArrived=true;d.deps.movement.hold(l.handle,600,function() end) end
 end,function()
  if R.active[player]==st then finish(player,st,'NpcLost') end
 end)
 task.spawn(lead,player,st)
 return true,nil
end
function R.donate(player,id,index)
 local st: any=R.active[player]
 if not st or st.id~=id or st.stage~='AtStand' then return false,'This request is no longer active.' end
 local d,l=st.ctx.director,st.ctx.live;local agent=l.agent
 if type(index)~='number' or index%1~=0 or not agent.offers[index] then return false,'Choose one of the listed amounts.' end
 if not (agent.ownedStandId and near(player,agent.ownedStandId,18)) then return false,'Move closer to the stand.' end
 local amount=agent.offers[index]
 local willingness=Relationships.willingness(Profiles.opinion(player,agent.personaId or agent.id))
 local ok,result=Economy.playerDonateToNpc(d.ledger,d:nextTx('pd'),agent,player,d:playerAccount(player.UserId),amount,willingness,d.rng)
 if not ok then return false,result end
 d.stats.requestDonations+=1;d.stats.requestCoins+=amount
 say(st,'Thanks')
 if result.returned>0 then task.delay(1.5,function() d.deps.movement.say(l.handle,PHRASES.Return[1]) end) end
 remote:FireClient(player,'NpcDonated',{Id=st.id,Name=agent.name,Amount=amount,DCoins=result.dcoins,Returned=result.returned})
 finish(player,st,'Donated')
 return true,nil
end
function R.leave(player,id)
 local st: any=R.active[player]
 if not st or st.id~=id or (st.stage~='Leading' and st.stage~='AtStand') then return false,'This request is no longer active.' end
 local agent=st.ctx.live.agent
 if st.stage=='Leading' then
  remember(player,st,'DeclinedRequest')
 else
  -- No penalty if the player couldn't afford any of the NPC's amounts.
  local data=Profiles.get(player);local cheapest=agent.offers[1]
  for _,a in agent.offers do cheapest=math.min(cheapest,a) end
  if data and cheapest and data.Coins>=cheapest then remember(player,st,'LeftAtStand') end
 end
 say(st,'Left');finish(player,st,'Left')
 return true,nil
end
function R.init(event)
 remote=event
 Players.PlayerRemoving:Connect(function(player)
  local st=R.active[player]
  R.active[player]=nil;R.cooldownUntil[player]=nil
  if st and st.ctx then task.spawn(st.ctx.onDone) end
 end)
end
return R
