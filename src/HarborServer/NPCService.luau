-- Pooled R15 visitors, server path/FSM and opt-in occupied-booth visits.
-- Currency is granted only by the separate server Donations/Economy controller.
local Players=game:GetService('Players')
local Pathfinding=game:GetService('PathfindingService')
local Collection=game:GetService('CollectionService')
local Physics=game:GetService('PhysicsService')
local Run=game:GetService('RunService')
local RS=game:GetService('ReplicatedStorage')
local Shared=RS:WaitForChild('HarborShared')
local Config=require(Shared.Config).NPC
local Phrases=require(Shared.NPCPhrases)
local M={Running=false,Agents={},Stats={Spawned=0,Routes=0,Arrivals=0,Chats=0,Lines=0,Repaths=0,Recoveries=0,Falls=0,Errors=0}}
M.Events={}
for _,name in {'StateChanged','Arrived','Conversation','Recreated','VisitStandRequested'} do local event=Instance.new('BindableEvent');M.Events[name]=event end
M.States=table.freeze({Idle='Idle',Walk='Walk',Chat='Chat',VisitStand='VisitStand'})
local navigationModifiers={}
local rng=Random.new();local nodes={};local floors={};local pending=0;local connections={};local epoch=0;local remote;local folder;local frame;local lastLine
local floorParams=RaycastParams.new();floorParams.FilterType=Enum.RaycastFilterType.Include
local function ground(position)
 return workspace:Raycast(position+Vector3.new(0,12,0),Vector3.new(0,-55,0),floorParams)
end
local function state(a,name)
 local previous=a.state;a.state=name;a.model:SetAttribute('NPCState',name)
 if previous~=name then M.Events.StateChanged:Fire(a.model,name,previous) end
end
local function disconnectPath(a)
 if a.blocked then a.blocked:Disconnect();a.blocked=nil end
 if a.path then a.path:Destroy();a.path=nil end
 a.points=nil;a.queueStarted=nil;a.generation+=1;a.computing=false;a.queued=false;a.needsRepath=false;a.needsFailure=false
end
local function cancelVisit(a)
 if a.visit and a.visit.marker then a.visit.marker:Destroy() end;a.visit=nil
end
local function idle(a,now)
 cancelVisit(a)
 disconnectPath(a);a.humanoid:MoveTo(a.root.Position);a.humanoid.AutoRotate=true
 state(a,'Idle');a.untilTime=now+rng:NextNumber(Config.IdleMin,Config.IdleMax)
end
local clearParams=OverlapParams.new();clearParams.FilterType=Enum.RaycastFilterType.Exclude;clearParams.RespectCanCollide=true
local function safeNode(node)
 if not node.Parent then return nil end
 local hit=ground(node.Position);if not hit or hit.Normal.Y<.9 then return nil end
 clearParams.FilterDescendantsInstances=folder and {folder} or {}
 for _,part in workspace:GetPartBoundsInBox(CFrame.new(hit.Position+Vector3.new(0,3.2,0)),Vector3.new(4,5.4,4),clearParams) do
  if part.CanCollide then return nil end
 end
 return hit
end
local function safePivot(a,node)
 local hit=safeNode(node);if not hit then return false end
 a.model:PivotTo(CFrame.new(hit.Position+Vector3.new(0,a.humanoid.HipHeight+a.root.Size.Y/2+.05,0)))
 a.root.AssemblyLinearVelocity=Vector3.zero;a.root.AssemblyAngularVelocity=Vector3.zero
 return true
end
local function recover(a,now)
 local best,dist
 for _,node in nodes do local d=(node.Position-a.root.Position).Magnitude;if (not dist or d<dist) and safeNode(node) then best=node;dist=d end end
 disconnectPath(a)
 if not best or not safePivot(a,best) then error('No safe recovery waypoint') end
 M.Stats.Recoveries+=1;a.failures=0;idle(a,now)
end
local requestPath
local function failure(a,now)
 a.failures+=1
 if a.failures<=Config.PathRetries and a.target then M.Stats.Repaths+=1;requestPath(a,a.target,now) else recover(a,now) end
end
local function advance(a,now)
 a.pointIndex+=1
 local p=a.points and a.points[a.pointIndex]
 if not p and a.visit then a.humanoid:MoveTo(a.root.Position);a.humanoid.AutoRotate=false;disconnectPath(a);state(a,'VisitStand');a.untilTime=now+Config.VisitStandSeconds;return end
 if not p then a.failures=0;M.Stats.Arrivals+=1;M.Events.Arrived:Fire(a.model,a.target);idle(a,now);return end
 -- Reject route segments with no walkable floor before asking the humanoid to move.
 local delta=p.Position-a.root.Position;local count=math.clamp(math.ceil(delta.Magnitude/2),1,12)
 for k=1,count do if not ground(a.root.Position+delta*(k/count)) then failure(a,now);return end end
 if p.Action==Enum.PathWaypointAction.Jump then a.humanoid.Jump=true end
 local support=ground(p.Position);a.movePosition=support and support.Position or p.Position
 a.humanoid:MoveTo(a.movePosition);a.moveIssued=now;a.stepDeadline=now+Config.WaypointTimeout;a.lastPosition=a.root.Position;a.progressTime=now
end
requestPath=function(a,target,now)
 local queueStarted=a.queueStarted
 disconnectPath(a);state(a,'Walk');a.target=target;a.routeDeadline=now+Config.PathTimeout
 if pending>=Config.MaxConcurrentPaths then a.queueStarted=queueStarted or now;a.queued=true;a.untilTime=now+.3;return end
 a.queued=false;a.computing=true;pending+=1
 local token=a.generation;local session=epoch
 local path=Pathfinding:CreatePath({AgentRadius=Config.AgentRadius,AgentHeight=Config.AgentHeight,AgentCanJump=true,AgentCanClimb=false,WaypointSpacing=4,Costs={NPCObstacle=math.huge,Water=math.huge}})
 task.spawn(function()
  local ok=pcall(function()path:ComputeAsync(a.root.Position,target.Position)end)
  pending=math.max(0,pending-1)
  if not M.Running or session~=epoch or token~=a.generation or not a.model.Parent then path:Destroy();return end
  a.computing=false
  if not ok or path.Status~=Enum.PathStatus.Success then path:Destroy();a.needsFailure=true;return end
  local points=path:GetWaypoints()
  if #points<2 or #points>180 then path:Destroy();a.needsFailure=true;return end
  a.path=path;a.points=points;a.pointIndex=1;M.Stats.Routes+=1
  a.blocked=path.Blocked:Connect(function(index)if a.state=='Walk' and index>=a.pointIndex then a.needsRepath=true end end)
  local advanced=pcall(advance,a,os.clock());if not advanced then a.needsFailure=true end
 end)
end
local function say(a,other)
 local text,index=Phrases.pick(rng,a.lastPhrase,lastLine);a.lastPhrase=index;lastLine=index;M.Stats.Lines+=1
 for _,p in Players:GetPlayers() do local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
  if root and (root.Position-a.root.Position).Magnitude<=Config.BubbleDistance then remote:FireClient(p,a.model,text) end
 end
end
local function chat(a,b,now)
 disconnectPath(a);disconnectPath(b)
 local id=a.generation;local otherId=b.generation;local session=epoch
 for _,v in {a,b} do
  v.humanoid:MoveTo(v.root.Position);v.humanoid.AutoRotate=false;state(v,'Chat');v.untilTime=now+Config.ChatSeconds;v.chatReady=now+rng:NextNumber(Config.ChatCooldownMin,Config.ChatCooldownMax)
 end
 local pa,pb=a.root.Position,b.root.Position
 if (Vector3.new(pa.X,0,pa.Z)-Vector3.new(pb.X,0,pb.Z)).Magnitude>.1 then
  a.root.CFrame=CFrame.lookAt(pa,Vector3.new(pb.X,pa.Y,pb.Z));b.root.CFrame=CFrame.lookAt(pb,Vector3.new(pa.X,pb.Y,pa.Z))
 end
 M.Stats.Chats+=1;M.Events.Conversation:Fire(a.model,b.model);say(a,b)
 task.delay(1.7,function()
  if M.Running and session==epoch and a.generation==id and b.generation==otherId and a.state=='Chat' and b.state=='Chat' and a.model.Parent and b.model.Parent then say(b,a) end
 end)
end
local function makeWaypoints()
 local waypoints=workspace:FindFirstChild('NPCWaypoints')
 if not waypoints then waypoints=Instance.new('Folder');waypoints.Name='NPCWaypoints';waypoints.Parent=workspace end
 local authored=0;for _,o in waypoints:GetDescendants() do if o:IsA('BasePart') and safeNode(o) then authored+=1 end end
 if authored<Config.MinWaypoints then
  local positions={}
  for k=0,7 do local angle=k*math.pi/4;table.insert(positions,Vector3.new(math.cos(angle)*24,42,math.sin(angle)*24)) end
  for axis=0,3 do
   local cf=CFrame.Angles(0,axis*math.pi/2,0)
   for _,z in {48,61,75} do table.insert(positions,(cf*CFrame.new(0,42,z)).Position) end
   for _,x in {-32,-16,0,16,32} do table.insert(positions,(cf*CFrame.new(x,42,114)).Position) end
   for _,x in {-7,7} do table.insert(positions,(cf*CFrame.new(x,42,162)).Position) end
  end
  for i,p in positions do
   local hit=ground(frame:PointToWorldSpace(p))
   if hit and not waypoints:FindFirstChild(string.format('Auto_%02d',i)) then
    local marker=Instance.new('Part');marker.Name=string.format('Auto_%02d',i);marker.Size=Vector3.new(.7,.1,.7);marker.Position=hit.Position+Vector3.new(0,.06,0);marker.Anchored=true;marker.CanCollide=false;marker.CanTouch=false;marker.CanQuery=false;marker.Transparency=1;marker:SetAttribute('NPCAutoWaypoint',true);marker.Parent=waypoints
   end
  end
  print('[NPC] Auto waypoints generated; edit NPCWaypoints in Studio or configure authored markers.')
 end
 nodes={}
 local seen={}
 for _,o in waypoints:GetDescendants() do if o:IsA('BasePart') and safeNode(o) then table.insert(nodes,o);seen[o]=true end end
 for _,o in Collection:GetTagged('NPCWaypoint') do if o:IsA('BasePart') and not seen[o] and safeNode(o) then table.insert(nodes,o);seen[o]=true end end
 table.sort(nodes,function(a,b)return a.Name<b.Name end)
 assert(#nodes>=4,'NPCService needs at least four grounded waypoint parts')
 return waypoints
end
local function rig(index,node)
 local description=Instance.new('HumanoidDescription')
 local skin=Color3.fromRGB(table.unpack(Config.Skins[(index-1)%#Config.Skins+1]))
 local shirt=Color3.fromRGB(table.unpack(Config.Colors[(index-1)%#Config.Colors+1]))
 description.HeadColor=skin;description.LeftArmColor=skin;description.RightArmColor=skin
 description.TorsoColor=shirt;description.LeftLegColor=Color3.fromRGB(table.unpack(Config.Trousers));description.RightLegColor=description.LeftLegColor
 local ok,model=pcall(function()return Players:CreateHumanoidModelFromDescriptionAsync(description,Enum.HumanoidRigType.R15)end)
 description:Destroy()
 if not ok then error('R15 rig creation unavailable: '..tostring(model)) end
 if not M.Running then model:Destroy();return nil end
 local hum=model:FindFirstChildOfClass('Humanoid');local root=model:FindFirstChild('HumanoidRootPart')
 if not hum or not root then model:Destroy();error('R15 rig missing Humanoid/root') end
 model.Name=string.format('Visitor_%02d',index);model:SetAttribute('NPCManaged',true);model.ModelStreamingMode=Enum.ModelStreamingMode.Atomic
 for _,part in model:GetDescendants() do
  if part:IsA('BasePart') then part.Anchored=false;part.CanTouch=false;part.CanQuery=false;part.CollisionGroup='HarborNPC'
  elseif part:IsA('LuaSourceContainer') then part:Destroy() end
 end
 hum.DisplayName=Config.Names[(index-1)%#Config.Names+1];hum.WalkSpeed=Config.WalkSpeed;hum.MaxSlopeAngle=35
 hum.BreakJointsOnDeath=false;hum.AutoJumpEnabled=false;hum.UseJumpPower=false;hum.JumpHeight=Config.JumpHeight
 hum.HealthDisplayType=Enum.HumanoidHealthDisplayType.AlwaysOff;hum.NameDisplayDistance=45
 for _,v in {Enum.HumanoidStateType.FallingDown,Enum.HumanoidStateType.Ragdoll,Enum.HumanoidStateType.Climbing,Enum.HumanoidStateType.Swimming} do hum:SetStateEnabled(v,false) end
 model.PrimaryPart=root;model.Parent=folder
 local a={model=model,root=root,humanoid=hum,generation=0,state='Idle',lastPosition=root.Position,progressTime=os.clock(),failures=0,nextThink=os.clock()+index*.06,chatReady=os.clock()+index*.5}
 if not safePivot(a,node) then model:Destroy();error('Unsafe NPC spawn') end
 root:SetNetworkOwner(nil)
 local animator=hum:FindFirstChildOfClass('Animator') or Instance.new('Animator',hum);a.tracks={}
 for name,id in Config.Animations do
  local animation=Instance.new('Animation');animation.AnimationId=id
  local loaded,track=pcall(function()return animator:LoadAnimation(animation)end);animation:Destroy()
  if loaded then track.Looped=true;track.Priority=name=='Walk' and Enum.AnimationPriority.Movement or Enum.AnimationPriority.Idle;a.tracks[name]=track end
 end
 idle(a,os.clock());M.Stats.Spawned+=1
 return a
end
local sight=RaycastParams.new();sight.FilterType=Enum.RaycastFilterType.Exclude;sight.RespectCanCollide=true
local function canChat(a,b)
 if not b.model or not b.root or not b.root.Parent or b.humanoid.Health<=0 then return false end
 sight.FilterDescendantsInstances={folder}
 return workspace:Raycast(a.root.Position,b.root.Position-a.root.Position,sight)==nil
end
local function dispose(a)
 cancelVisit(a);if a.model then disconnectPath(a);a.model:Destroy() end
end
local function replaceAgent(index,now)
 local old=M.Agents[index];if old.rebuilding or now<(old.retryAt or 0) then return end
 old.rebuilding=true;dispose(old);local session=epoch
 task.spawn(function()
  local node=nodes[(index-1)*3%#nodes+1]
  if not safeNode(node) then for _,candidate in nodes do if safeNode(candidate) then node=candidate;break end end end
  local ok,new=pcall(rig,index,node)
  if not M.Running or session~=epoch then if ok and new then dispose(new) end;return end
  if ok and new then M.Agents[index]=new;M.Events.Recreated:Fire(new.model,index)
  else old.rebuilding=false;old.retryAt=os.clock()+5;folder:SetAttribute('LastSpawnError',tostring(new)) end
 end)
end
-- Reserved opt-in integration point only: no stand selection, currency or donation logic.
function M.RequestVisitStand(model,stand)
 for _,a in M.Agents do if a.model==model and a.model.Parent and not a.rebuilding then
  disconnectPath(a);a.humanoid:MoveTo(a.root.Position);state(a,'VisitStand');a.untilTime=os.clock()+Config.VisitStandSeconds
  M.Events.VisitStandRequested:Fire(model,stand);return true
 end end
 return false
end
-- A booth approach is a normal path, never a teleport or a client-triggered grant.
function M.VisitBooth(model,booth,anchor,callback)
 if not M.Running or not booth.Parent then return false end
 for _,a in M.Agents do if a.model==model and not a.visit and not a.rebuilding then
  local marker=Instance.new('Part');marker.Name='NPCBoothApproach';marker.Size=Vector3.new(.2,.2,.2);marker.Anchored=true;marker.CanCollide=false;marker.CanTouch=false;marker.CanQuery=false;marker.Transparency=1;marker.Parent=folder
  local best,dist
  for _,radius in {6,9,12} do for k=0,11 do
   local angle=k*math.pi/6;marker.Position=anchor.Position+Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
   local hit=safeNode(marker)
   if hit then local d=(a.root.Position-hit.Position).Magnitude;if not dist or d<dist then dist=d;best=hit.Position end end
  end end
  if not best then marker:Destroy();return false end
  marker.Position=best; a.visit={marker=marker,booth=booth,anchor=anchor,callback=callback}
  requestPath(a,marker,os.clock());return true
 end end
 return false
end

local function update(a,now)
 if not a.model or not a.model.Parent or not a.root.Parent or a.humanoid.Health<=0 then error('NPC rig unavailable') end
 local pos=a.root.Position
 if a.tracks then
  local moving=a.state=='Walk' and a.root.AssemblyLinearVelocity.Magnitude>.5
  local selected=moving and 'Walk' or 'Idle'
  for name,track in a.tracks do
   if name==selected and not track.IsPlaying then track:Play(.2) elseif name~=selected and track.IsPlaying then track:Stop(.2) end
  end
 end
 if frame:PointToObjectSpace(pos).Y<35 then M.Stats.Falls+=1;recover(a,now);return end
 if a.state=='VisitStand' then
  local visit=a.visit
  if visit and visit.booth.Parent then
   local ownerId=visit.booth:GetAttribute('OwnerUserId');local owner=ownerId and Players:GetPlayerByUserId(ownerId)
   local target=owner and owner.Character and owner.Character:FindFirstChild('HumanoidRootPart')
   local look=target and target.Position or visit.anchor.Position
   local delta=Vector3.new(look.X-pos.X,0,look.Z-pos.Z)
   if delta.Magnitude>.1 then a.root.CFrame=a.root.CFrame:Lerp(CFrame.lookAt(pos,pos+delta),.35) end
  end
  if now>=a.untilTime then local callback=visit and visit.callback;idle(a,now);if callback then task.spawn(callback,a.model) end end
  return
 end
 if a.state=='Chat' then if now>=a.untilTime then idle(a,now) end;return end
 if not a.visit and now>=a.chatReady then
  for _,b in M.Agents do
   if b~=a and not b.visit and not b.rebuilding and b.model and b.model.Parent and (b.state=='Walk' or b.state=='Idle') and now>=b.chatReady and (b.root.Position-pos).Magnitude<Config.ChatDistance and canChat(a,b) then chat(a,b,now);return end
  end
 end
 if a.state=='Idle' then
  if now>=a.untilTime then
   local candidates={};for index,node in nodes do if index~=a.lastNode and (node.Position-pos).Magnitude>6 and safeNode(node) then table.insert(candidates,index) end end
   if #candidates>0 then local index=candidates[rng:NextInteger(1,#candidates)];a.lastNode=index;requestPath(a,nodes[index],now) else a.untilTime=now+2 end
  end
  return
 end
 if a.queued then if now-(a.queueStarted or now)>10 then recover(a,now);return end;if now>=a.untilTime then requestPath(a,a.target,now) end;return end
 if a.computing then if now>a.routeDeadline then failure(a,now) end;return end
 if a.needsFailure then a.needsFailure=false;failure(a,now);return end
 if a.needsRepath then a.needsRepath=false;failure(a,now);return end
 if now>a.routeDeadline or now>(a.stepDeadline or now+1) then failure(a,now);return end
 local point=a.points and a.points[a.pointIndex]
 a.model:SetAttribute('WaypointDistance',point and (point.Position-pos).Magnitude or 0);a.model:SetAttribute('Failures',a.failures)
 local support=point and ground(point.Position)
 if point and support and (Vector3.new(pos.X,0,pos.Z)-Vector3.new(point.Position.X,0,point.Position.Z)).Magnitude<1.35 and math.abs(pos.Y-support.Position.Y-(a.humanoid.HipHeight+a.root.Size.Y/2))<2.5 then advance(a,now);return end
 if point and now-(a.moveIssued or 0)>2.5 then a.humanoid:MoveTo(a.movePosition or point.Position);a.moveIssued=now end
 if (pos-a.lastPosition).Magnitude>.65 then a.lastPosition=pos;a.progressTime=now
 elseif now-a.progressTime>Config.StuckSeconds then failure(a,now) end
end
function M.Start()
 if M.Running or not Config.Enabled then return end
 local cloud=workspace:WaitForChild('CloudHarbor',20);assert(cloud,'CloudHarbor map not loaded')
 frame=cloud.Islands.CompassPlaza.StoneDeck.CFrame*CFrame.new(0,-40,0)
 floors={};for _,bridge in cloud.Bridges:GetChildren() do local deck=bridge:FindFirstChild('Deck');if deck then table.insert(floors,deck) end end;for _,island in cloud.Islands:GetChildren() do local d=island:FindFirstChild('StoneDeck');if d then table.insert(floors,d) end end
 floorParams.FilterDescendantsInstances=floors
 -- Navigation-only labels: keep paths off counters, booths and the fountain without changing physics.
 for _,group in {cloud:FindFirstChild('Booths'),cloud:FindFirstChild('Landmarks')} do
  if group then for _,part in group:GetDescendants() do if part:IsA('BasePart') and part.CanCollide and not part:FindFirstChild('NPCNavObstacle') then
   local modifier=Instance.new('PathfindingModifier');modifier.Name='NPCNavObstacle';modifier.Label='NPCObstacle';modifier.Parent=part;table.insert(navigationModifiers,modifier)
  end end end
 end
 if not Physics:IsCollisionGroupRegistered('HarborNPC') then Physics:RegisterCollisionGroup('HarborNPC') end;Physics:CollisionGroupSetCollidable('HarborNPC','HarborNPC',false)
 assert(not workspace:FindFirstChild('HarborNPCs'),'Existing HarborNPCs folder; refusing to delete unknown NPCs')
 folder=Instance.new('Folder');folder.Name='HarborNPCs';folder:SetAttribute('ManagedBy','NPCService');folder.Parent=workspace
 remote=RS:FindFirstChild('HarborNPCSpeech') or Instance.new('RemoteEvent');remote.Name='HarborNPCSpeech';remote.Parent=RS
 makeWaypoints()
 local reachable={nodes[1]};local rejected=0
 for i=2,#nodes do
  local path=Pathfinding:CreatePath({AgentRadius=Config.AgentRadius,AgentHeight=Config.AgentHeight,AgentCanJump=true,AgentCanClimb=false,Costs={NPCObstacle=math.huge,Water=math.huge}})
  local ok=pcall(function()path:ComputeAsync(nodes[1].Position,nodes[i].Position)end)
  if ok and path.Status==Enum.PathStatus.Success then table.insert(reachable,nodes[i]) else rejected+=1 end
  path:Destroy();task.wait()
 end
 assert(#reachable>=4,'NPC needs connected grounded waypoints');nodes=reachable;folder:SetAttribute('UnreachableWaypoints',rejected)
 epoch+=1;M.Running=true
 for i=1,math.clamp(Config.Count,12,16) do M.Agents[i]={retryAt=0};replaceAgent(i,os.clock());task.wait(Config.SpawnSpacing) end
 local lastTick=0;local lastReport=os.clock();local started=os.clock();local frameTotal=0;local frameCount=0;local maxFrame=0
 table.insert(connections,Run.Heartbeat:Connect(function(dt)
  frameTotal+=dt;frameCount+=1;maxFrame=math.max(maxFrame,dt)
  local now=os.clock();if now-lastTick<Config.TickSeconds then return end;lastTick=now
  for index,a in M.Agents do if a.rebuilding then continue end
   if not a.model or not a.model.Parent or not a.root.Parent or a.humanoid.Health<=0 then replaceAgent(index,now);continue end
   if now>=a.nextThink then
   a.nextThink=now+Config.TickSeconds+rng:NextNumber(0,.08)
   local ok,err=pcall(update,a,now)
   if not ok then M.Stats.Errors+=1;folder:SetAttribute('LastError',tostring(err));replaceAgent(index,now) end
  end end
  if now-lastReport>=30 then lastReport=now;folder:SetAttribute('Uptime',math.floor(now-started));for k,v in M.Stats do folder:SetAttribute(k,v) end
   local mem=game:GetService('Stats'):GetTotalMemoryUsageMb();folder:SetAttribute('MemoryMB',mem)
   print(string.format('[NPC_PERF] memoryMB=%.1f meanFrameMS=%.2f maxFrameMS=%.2f',mem,frameTotal/math.max(1,frameCount)*1000,maxFrame*1000));frameTotal=0;frameCount=0;maxFrame=0
   print(string.format('[NPC_HEALTH] seconds=%d pool=%d routes=%d arrivals=%d chats=%d recoveries=%d falls=%d errors=%d',now-started,#M.Agents,M.Stats.Routes,M.Stats.Arrivals,M.Stats.Chats,M.Stats.Recoveries,M.Stats.Falls,M.Stats.Errors))
  end
 end))
 game:BindToClose(M.Stop)
 print('[NPC] Ready: pooled='..#M.Agents..' waypoints='..#nodes..'; R15 visitors and server-controlled booth visit hooks')
end
function M.Stop()
 M.Running=false;epoch+=1
 for _,c in connections do c:Disconnect() end;table.clear(connections)
 for _,a in M.Agents do dispose(a) end;table.clear(M.Agents)
 if folder then folder:Destroy();folder=nil end
 for _,modifier in navigationModifiers do modifier:Destroy() end;table.clear(navigationModifiers)
end
return M
