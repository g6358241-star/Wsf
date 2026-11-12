-- NPC locomotion: pooled R15 rigs, server pathfinding/FSM, booth approaches and despawn effects.
-- Decisions and money live in NpcDirector + NpcCore; this module only moves characters.
-- Population is dynamic (spawned/despawned by the director, up to NpcCore Config.Population.maxActive).
local Players=game:GetService('Players')
local Pathfinding=game:GetService('PathfindingService')
local Collection=game:GetService('CollectionService')
local Physics=game:GetService('PhysicsService')
local Run=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local RS=game:GetService('ReplicatedStorage')
local Shared=RS:WaitForChild('HarborShared')
local Config=require(Shared.Config).NPC
local Phrases=require(Shared.NPCPhrases)
local M={Running=false,Agents={},Pool={},Stats={Spawned=0,Despawned=0,Routes=0,Arrivals=0,Chats=0,Lines=0,Repaths=0,Recoveries=0,Falls=0,Errors=0,Lost=0,PathMsTotal=0,PathMsMax=0,PathCount=0,QueueTimeouts=0}}
M.Events={}
for _,name in {'StateChanged','Arrived','Conversation','Lost'} do local event=Instance.new('BindableEvent');M.Events[name]=event end
M.States=table.freeze({Idle='Idle',Walk='Walk',Chat='Chat',VisitStand='VisitStand'})
local navigationModifiers={}
local rng=Random.new();local nodes={};local spawnNodes={};local floors={};local pending=0;local connections={};local epoch=0;local remote;local folder;local frame;local lastLine
local approaches={} -- [booth model] = {points={Vector3}, load={number}}
local nextHandle=0
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
 local visit=a.visit;a.visit=nil
 if not visit then return end
 if visit.marker then visit.marker:Destroy() end
 if visit.slot then local slots=approaches[visit.booth];if slots then slots.load[visit.slot]=math.max(0,slots.load[visit.slot]-1) end end
 -- A visit that never reached the booth reports failure so the director can move on.
 if not visit.arrived and visit.onFail then task.spawn(visit.onFail) end
end
local function idle(a,now)
 cancelVisit(a)
 disconnectPath(a);a.humanoid:MoveTo(a.root.Position);a.humanoid.AutoRotate=true
 state(a,'Idle');a.untilTime=now+rng:NextNumber(Config.IdleMin,Config.IdleMax)
end
local clearParams=OverlapParams.new();clearParams.FilterType=Enum.RaycastFilterType.Exclude;clearParams.RespectCanCollide=true
local function safeAt(position)
 local hit=ground(position);if not hit or hit.Normal.Y<.9 then return nil end
 clearParams.FilterDescendantsInstances=folder and {folder} or {}
 for _,part in workspace:GetPartBoundsInBox(CFrame.new(hit.Position+Vector3.new(0,3.2,0)),Vector3.new(4,5.4,4),clearParams) do
  if part.CanCollide then return nil end
 end
 return hit
end
local function safeNode(node)
 if not node.Parent then return nil end
 return safeAt(node.Position)
end
-- Node safety changes rarely (only when something blocks a spot), so idle route picks reuse a short-lived cache.
local safeCache={}
local function safeNodeCached(node,now)
 local c=safeCache[node]
 if c and now-c.t<5 then return c.ok end
 local ok=safeNode(node)~=nil;safeCache[node]={t=now,ok=ok}
 return ok
end
local function safePivot(a,position)
 local hit=safeAt(position);if not hit then return false end
 a.model:PivotTo(CFrame.new(hit.Position+Vector3.new(0,a.humanoid.HipHeight+a.root.Size.Y/2+.05,0)))
 a.root.AssemblyLinearVelocity=Vector3.zero;a.root.AssemblyAngularVelocity=Vector3.zero
 return true
end
local function recover(a,now)
 local best,dist
 for _,node in nodes do local d=(node.Position-a.root.Position).Magnitude;if (not dist or d<dist) and safeNode(node) then best=node;dist=d end end
 disconnectPath(a)
 if not best or not safePivot(a,best.Position) then error('No safe recovery waypoint') end
 M.Stats.Recoveries+=1;a.failures=0;idle(a,now)
end
local requestPath
local function failure(a,now)
 a.failures+=1
 if a.failures<=Config.PathRetries and a.target then M.Stats.Repaths+=1;requestPath(a,a.target,now) else recover(a,now) end
end
local function finishWander(a)
 local done=a.wanderDone;a.wanderDone=nil;a.wanderDeadline=nil
 if done then task.spawn(done) end
end
local function advance(a,now)
 a.pointIndex+=1
 local p=a.points and a.points[a.pointIndex]
 if not p and a.visit then
  -- Arrived at the booth: hold position until the director calls Hold (or the safety timeout passes).
  a.humanoid:MoveTo(a.root.Position);a.humanoid.AutoRotate=false;disconnectPath(a);state(a,'VisitStand')
  a.visit.arrived=true;a.untilTime=now+3;M.Stats.Arrivals+=1
  local onArrive=a.visit.onArrive;a.visit.onArrive=nil
  if onArrive then task.spawn(onArrive) end
  return
 end
 if not p then a.failures=0;M.Stats.Arrivals+=1;M.Events.Arrived:Fire(a.model,a.target);idle(a,now);finishWander(a);return end
 -- Reject route segments with no walkable floor before asking the humanoid to move.
 local delta=p.Position-a.root.Position;local count=math.clamp(math.ceil(delta.Magnitude/3),1,6)
 for k=1,count do if not ground(a.root.Position+delta*(k/count)) then failure(a,now);return end end
 if p.Action==Enum.PathWaypointAction.Jump then a.humanoid.Jump=true end
 local support=ground(p.Position);a.movePosition=support and support.Position or p.Position
 a.humanoid:MoveTo(a.movePosition);a.moveIssued=now;a.stepDeadline=now+Config.WaypointTimeout;a.lastPosition=a.root.Position;a.progressTime=now
end
local pathParams={AgentRadius=Config.AgentRadius,AgentHeight=Config.AgentHeight,AgentCanJump=true,AgentCanClimb=false,WaypointSpacing=4,Costs={NPCObstacle=math.huge,Water=math.huge}}
requestPath=function(a,target,now)
 local queueStarted=a.queueStarted
 disconnectPath(a);state(a,'Walk');a.target=target;a.routeDeadline=now+Config.PathTimeout
 if pending>=Config.MaxConcurrentPaths then a.queueStarted=queueStarted or now;a.queued=true;a.untilTime=now+.3;return end
 a.queued=false;a.computing=true;pending+=1
 local token=a.generation;local session=epoch
 local path=Pathfinding:CreatePath(pathParams)
 task.spawn(function()
  local started=os.clock()
  local ok=pcall(function()path:ComputeAsync(a.root.Position,target.Position)end)
  local ms=(os.clock()-started)*1000
  M.Stats.PathMsTotal+=ms;M.Stats.PathCount+=1;M.Stats.PathMsMax=math.max(M.Stats.PathMsMax,ms)
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
-- Arrivals appear on the outer edge of the map (docks/bridge ends), not in the middle of the plaza.
local function pickSpawnNodes()
 local center=frame.Position;local sorted=table.clone(nodes)
 table.sort(sorted,function(a,b)return (a.Position-center).Magnitude>(b.Position-center).Magnitude end)
 spawnNodes={};for i=1,math.max(4,math.floor(#sorted/4)) do table.insert(spawnNodes,sorted[i]) end
end
-- Visitor-side standing spots per booth, computed once. "Front" faces away from the booth's sign board.
local function buildApproaches(boothsFolder)
 local probe=Vector3.zero
 for _,booth in boothsFolder:GetChildren() do
  if not booth:IsA('Model') then continue end
  local anchor=booth:FindFirstChild('CounterTop',true) or booth:FindFirstChildWhichIsA('BasePart',true)
  if not anchor then continue end
  local sign=booth:FindFirstChild('SignBoard',true)
  local front
  if sign and sign:IsA('BasePart') then local d=anchor.Position-sign.Position;d=Vector3.new(d.X,0,d.Z);if d.Magnitude>.5 then front=d.Unit end end
  local points,fallback={}, {}
  for _,radius in {6,9,12} do for k=0,11 do
   local angle=k*math.pi/6;local offset=Vector3.new(math.cos(angle)*radius,0,math.sin(angle)*radius)
   probe=anchor.Position+offset
   local hit=safeAt(probe)
   if hit then
    if not front or offset.Unit:Dot(front)>.3 then table.insert(points,hit.Position) else table.insert(fallback,hit.Position) end
   end
  end end
  if #points==0 then points=fallback end
  if #points>0 then local load={};for i in points do load[i]=0 end;approaches[booth]={points=points,load=load,anchor=anchor} end
 end
end
local BODY={Head='skin',LeftHand='skin',RightHand='skin',LeftLowerArm='skin',RightLowerArm='skin',LeftUpperArm='shirt',RightUpperArm='shirt',UpperTorso='shirt',LowerTorso='shirt',LeftUpperLeg='legs',RightUpperLeg='legs',LeftLowerLeg='legs',RightLowerLeg='legs',LeftFoot='legs',RightFoot='legs'}
local function newRig()
 local description=Instance.new('HumanoidDescription')
 local ok,model=pcall(function()return Players:CreateHumanoidModelFromDescriptionAsync(description,Enum.HumanoidRigType.R15)end)
 description:Destroy()
 if not ok then error('R15 rig creation unavailable: '..tostring(model)) end
 local hum=model:FindFirstChildOfClass('Humanoid');local root=model:FindFirstChild('HumanoidRootPart')
 if not hum or not root then model:Destroy();error('R15 rig missing Humanoid/root') end
 model:SetAttribute('NPCManaged',true);model.ModelStreamingMode=Enum.ModelStreamingMode.Atomic
 local parts={}
 for _,part in model:GetDescendants() do
  if part:IsA('BasePart') then part.Anchored=false;part.CanTouch=false;part.CanQuery=false;part.CollisionGroup='HarborNPC';if part~=root then parts[part]=part.Transparency end
  elseif part:IsA('LuaSourceContainer') then part:Destroy() end
 end
 hum.WalkSpeed=Config.WalkSpeed;hum.MaxSlopeAngle=35
 hum.BreakJointsOnDeath=false;hum.AutoJumpEnabled=false;hum.UseJumpPower=false;hum.JumpHeight=Config.JumpHeight
 hum.HealthDisplayType=Enum.HumanoidHealthDisplayType.AlwaysOff;hum.NameDisplayDistance=45
 for _,v in {Enum.HumanoidStateType.FallingDown,Enum.HumanoidStateType.Ragdoll,Enum.HumanoidStateType.Climbing,Enum.HumanoidStateType.Swimming} do hum:SetStateEnabled(v,false) end
 model.PrimaryPart=root
 local animator=hum:FindFirstChildOfClass('Animator') or Instance.new('Animator',hum);local tracks={}
 for name,id in Config.Animations do
  local animation=Instance.new('Animation');animation.AnimationId=id
  local loaded,track=pcall(function()return animator:LoadAnimation(animation)end);animation:Destroy()
  if loaded then track.Looped=true;track.Priority=name=='Walk' and Enum.AnimationPriority.Movement or Enum.AnimationPriority.Idle;tracks[name]=track end
 end
 return {model=model,root=root,humanoid=hum,parts=parts,tracks=tracks}
end
local function dress(rig,seed,name)
 local r=Random.new(seed)
 local skin=Color3.fromRGB(table.unpack(Config.Skins[r:NextInteger(1,#Config.Skins)]))
 local shirt=Color3.fromRGB(table.unpack(Config.Colors[r:NextInteger(1,#Config.Colors)]))
 local legs=Color3.fromRGB(table.unpack(Config.Trousers))
 for part,original in rig.parts do
  part.Transparency=original
  local kind=BODY[part.Name];if kind then part.Color=kind=='skin' and skin or kind=='shirt' and shirt or legs end
 end
 rig.humanoid.DisplayName=name;rig.model.Name='Visitor_'..name:gsub('%s','')
end
local sight=RaycastParams.new();sight.FilterType=Enum.RaycastFilterType.Exclude;sight.RespectCanCollide=true
local function canChat(a,b)
 if not b.model or not b.root or not b.root.Parent or b.humanoid.Health<=0 then return false end
 sight.FilterDescendantsInstances={folder}
 return workspace:Raycast(a.root.Position,b.root.Position-a.root.Position,sight)==nil
end
-- Parks the rig for reuse (or destroys it if it is broken). Never fires director callbacks.
local function park(a)
 a.visit=nil;a.wanderDone=nil
 disconnectPath(a)
 for _,track in a.tracks do track:Stop(0) end
 local healthy=a.model.Parent and a.root.Parent and a.humanoid.Health>0
 if healthy and #M.Pool<40 then
  a.model.Parent=nil
  table.insert(M.Pool,{model=a.model,root=a.root,humanoid=a.humanoid,parts=a.parts,tracks=a.tracks})
 else a.model:Destroy() end
end
-- Director API -----------------------------------------------------------------------------------
-- Creates (or reuses) a rig at an arrival point. onReady(handle|nil) is called once.
function M.Spawn(spec,onReady)
 if not M.Running then onReady(nil);return end
 task.spawn(function()
  local rig=table.remove(M.Pool)
  if not rig then
   local ok,result=pcall(newRig)
   if not ok then M.Stats.Errors+=1;if folder then folder:SetAttribute('LastSpawnError',tostring(result)) end;onReady(nil);return end
   rig=result
  end
  if not M.Running then rig.model:Destroy();onReady(nil);return end
  dress(rig,spec.seed,spec.name)
  nextHandle+=1;local handle='h'..nextHandle
  local a={handle=handle,id=spec.id,model=rig.model,root=rig.root,humanoid=rig.humanoid,parts=rig.parts,tracks=rig.tracks,generation=0,state='Idle',
   lastPosition=rig.root.Position,progressTime=os.clock(),failures=0,nextThink=os.clock(),chatReady=os.clock()+rng:NextNumber(5,15),nextChatScan=0}
  rig.model:SetAttribute('NpcId',spec.id)
  rig.model.Parent=folder
  local placed=false
  for _=1,6 do local node=spawnNodes[rng:NextInteger(1,#spawnNodes)];if safePivot(a,node.Position) then placed=true;break end end
  if not placed then rig.model:Destroy();onReady(nil);return end
  rig.root:SetNetworkOwner(nil)
  idle(a,os.clock());M.Agents[handle]=a;M.Stats.Spawned+=1
  onReady(handle)
 end)
end
function M.VisitBooth(handle,booth,onArrive,onFail)
 local a=M.Agents[handle];local slots=approaches[booth]
 if not a or not slots then task.spawn(onFail);return end
 cancelVisit(a);a.wanderDone=nil
 -- Least-crowded of the three nearest visitor spots, so NPCs don't stack on one point.
 local order={};for i,p in slots.points do table.insert(order,{i=i,d=(p-a.root.Position).Magnitude}) end
 table.sort(order,function(x,y)return x.d<y.d end)
 local best=order[1].i
 for k=2,math.min(3,#order) do if slots.load[order[k].i]<slots.load[best] then best=order[k].i end end
 slots.load[best]+=1
 local marker=Instance.new('Part');marker.Name='NPCBoothApproach';marker.Size=Vector3.new(.2,.2,.2);marker.Anchored=true;marker.CanCollide=false;marker.CanTouch=false;marker.CanQuery=false;marker.Transparency=1;marker.Position=slots.points[best];marker.Parent=folder
 a.visit={marker=marker,booth=booth,anchor=slots.anchor,slot=best,onArrive=onArrive,onFail=onFail,arrived=false}
 requestPath(a,marker,os.clock())
end
function M.Hold(handle,seconds,onDone)
 local a=M.Agents[handle]
 if not a or not a.visit or not a.visit.arrived then task.spawn(onDone);return end
 a.visit.onDone=onDone;a.untilTime=os.clock()+seconds
end
function M.Wander(handle,onDone)
 local a=M.Agents[handle]
 if not a then task.spawn(onDone);return end
 if a.visit then idle(a,os.clock()) end
 a.wanderDone=onDone;a.wanderDeadline=os.clock()+45
end
function M.Despawn(handle)
 local a=M.Agents[handle];if not a then return end
 M.Agents[handle]=nil;M.Stats.Despawned+=1
 if a.visit then a.visit.onFail=nil;cancelVisit(a) end
 a.humanoid:MoveTo(a.root.Position)
 local info=TweenInfo.new(Config.DespawnFadeSeconds)
 for part in a.parts do TweenService:Create(part,info,{Transparency=1}):Play() end
 task.delay(Config.DespawnFadeSeconds+.05,function() park(a) end)
end
---------------------------------------------------------------------------------------------------
local function lose(a,reason)
 M.Agents[a.handle]=nil;M.Stats.Lost+=1
 if folder then folder:SetAttribute('LastError',tostring(reason)) end
 if a.visit then a.visit.onFail=nil;cancelVisit(a) end
 a.visit=nil;a.wanderDone=nil
 pcall(function() a.model:Destroy() end)
 M.Events.Lost:Fire(a.id)
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
 if a.wanderDone and now>(a.wanderDeadline or now) then finishWander(a) end
 if a.state=='VisitStand' then
  local visit=a.visit
  if visit and visit.booth.Parent then
   local look=visit.anchor.Position
   local delta=Vector3.new(look.X-pos.X,0,look.Z-pos.Z)
   if delta.Magnitude>.1 then a.root.CFrame=a.root.CFrame:Lerp(CFrame.lookAt(pos,pos+delta),.35) end
  end
  if now>=a.untilTime then
   local done=visit and visit.onDone
   if visit and visit.marker then visit.marker:Destroy() end
   idle(a,now)
   if done then task.spawn(done) end
  end
  return
 end
 if a.state=='Chat' then if now>=a.untilTime then idle(a,now) end;return end
 if not a.visit and now>=a.chatReady and now>=a.nextChatScan then
  a.nextChatScan=now+Config.ChatScanSeconds
  for _,b in M.Agents do
   if b~=a and not b.visit and b.model.Parent and (b.state=='Walk' or b.state=='Idle') and now>=b.chatReady and (b.root.Position-pos).Magnitude<Config.ChatDistance and canChat(a,b) then chat(a,b,now);return end
  end
 end
 if a.state=='Idle' then
  if now>=a.untilTime then
   local candidates={};for index,node in nodes do if index~=a.lastNode and (node.Position-pos).Magnitude>6 and safeNodeCached(node,now) then table.insert(candidates,index) end end
   if #candidates>0 then local index=candidates[rng:NextInteger(1,#candidates)];a.lastNode=index;requestPath(a,nodes[index],now) else a.untilTime=now+2 end
  end
  return
 end
 if a.queued then
  -- Waiting for a free path slot never teleports the NPC; it gives up the current goal instead.
  if now-(a.queueStarted or now)>Config.QueueWaitSeconds then M.Stats.QueueTimeouts+=1;idle(a,now);return end
  if now>=a.untilTime then requestPath(a,a.target,now) end;return
 end
 if a.computing then if now>a.routeDeadline then failure(a,now) end;return end
 if a.needsFailure then a.needsFailure=false;failure(a,now);return end
 if a.needsRepath then a.needsRepath=false;failure(a,now);return end
 if now>a.routeDeadline or now>(a.stepDeadline or now+1) then failure(a,now);return end
 local point=a.points and a.points[a.pointIndex]
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
  local path=Pathfinding:CreatePath(pathParams)
  local ok=pcall(function()path:ComputeAsync(nodes[1].Position,nodes[i].Position)end)
  if ok and path.Status==Enum.PathStatus.Success then table.insert(reachable,nodes[i]) else rejected+=1 end
  path:Destroy();task.wait()
 end
 assert(#reachable>=4,'NPC needs connected grounded waypoints');nodes=reachable;folder:SetAttribute('UnreachableWaypoints',rejected)
 pickSpawnNodes()
 buildApproaches(cloud.Booths)
 local approachCount=0;for _ in approaches do approachCount+=1 end
 epoch+=1;M.Running=true
 local lastTick=0;local lastReport=os.clock();local started=os.clock()
 local frameTotal,frameCount,maxFrame,tickTotal,tickMax,tickCount=0,0,0,0,0,0
 local viewers={}
 table.insert(connections,Run.Heartbeat:Connect(function(dt)
  frameTotal+=dt;frameCount+=1;maxFrame=math.max(maxFrame,dt)
  local now=os.clock();if now-lastTick<Config.TickSeconds then return end;lastTick=now
  table.clear(viewers)
  for _,p in Players:GetPlayers() do local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart');if root then table.insert(viewers,root.Position) end end
  local far2=Config.VisualDistance*Config.VisualDistance
  for _,a in M.Agents do
   if now>=a.nextThink then
    -- NPCs out of every player's view get fewer movement checks; their decisions run on the same rules.
    local near=false
    for _,v in viewers do local d=a.root.Position-v;if d.X*d.X+d.Z*d.Z<far2 then near=true;break end end
    a.nextThink=now+(near and Config.TickSeconds or Config.FarThinkSeconds)+rng:NextNumber(0,.05)
    local ok,err=pcall(update,a,now)
    if not ok then M.Stats.Errors+=1;lose(a,err) end
   end
  end
  local spent=os.clock()-now;tickTotal+=spent;tickCount+=1;tickMax=math.max(tickMax,spent)
  if now-lastReport>=30 then lastReport=now
   local active=0;for _ in M.Agents do active+=1 end
   local queued=0;for _,a in M.Agents do if a.queued then queued+=1 end end
   folder:SetAttribute('Uptime',math.floor(now-started));folder:SetAttribute('Active',active);for k,v in M.Stats do folder:SetAttribute(k,v) end
   local mem=game:GetService('Stats'):GetTotalMemoryUsageMb();folder:SetAttribute('MemoryMB',mem)
   print(string.format('[NPC_PERF] active=%d pool=%d memoryMB=%.1f meanFrameMS=%.2f maxFrameMS=%.2f npcTickMeanMS=%.2f npcTickMaxMS=%.2f pathsInFlight=%d queued=%d pathMeanMS=%.1f pathMaxMS=%.1f',
    active,#M.Pool,mem,frameTotal/math.max(1,frameCount)*1000,maxFrame*1000,tickTotal/math.max(1,tickCount)*1000,tickMax*1000,pending,queued,M.Stats.PathMsTotal/math.max(1,M.Stats.PathCount),M.Stats.PathMsMax))
   print(string.format('[NPC_HEALTH] seconds=%d spawned=%d despawned=%d routes=%d arrivals=%d chats=%d recoveries=%d falls=%d queueTimeouts=%d lost=%d errors=%d',
    now-started,M.Stats.Spawned,M.Stats.Despawned,M.Stats.Routes,M.Stats.Arrivals,M.Stats.Chats,M.Stats.Recoveries,M.Stats.Falls,M.Stats.QueueTimeouts,M.Stats.Lost,M.Stats.Errors))
   frameTotal,frameCount,maxFrame,tickTotal,tickMax,tickCount=0,0,0,0,0,0;M.Stats.PathMsMax=0
  end
 end))
 game:BindToClose(M.Stop)
 print('[NPC] Ready: waypoints='..#nodes..' spawnPoints='..#spawnNodes..' boothsWithApproaches='..approachCount)
end
function M.Stop()
 M.Running=false;epoch+=1
 for _,c in connections do c:Disconnect() end;table.clear(connections)
 for _,a in M.Agents do a.visit=nil;a.wanderDone=nil;pcall(function() a.model:Destroy() end) end;table.clear(M.Agents)
 for _,rig in M.Pool do rig.model:Destroy() end;table.clear(M.Pool)
 if folder then folder:Destroy();folder=nil end
 for _,modifier in navigationModifiers do modifier:Destroy() end;table.clear(navigationModifiers)
end
-- Booth model lookup for the director adapter.
function M.BoothModel(boothId)
 local cloud=workspace:FindFirstChild('CloudHarbor')
 return cloud and cloud.Booths:FindFirstChild(boothId)
end
return M
