-- Edit-mode alignment and lighthouse repair. Additive, repeat-safe, no external assets.
local M={}
local function new(parent,class,name) local o=Instance.new(class);o.Name=name;o.Parent=parent;return o end
local function part(parent,name,size,cf,color,mat,shape)
 local p=new(parent,'Part',name);p.Size=size;p.CFrame=cf;p.Color=color;p.Material=mat or Enum.Material.SmoothPlastic
 p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
 p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 if shape then p.Shape=shape end
 return p
end
local function oval(parent,name,size,cf,color,mat)
 local p=part(parent,name,Vector3.one,cf,color,mat);local mesh=new(p,'SpecialMesh','NativeSphere');mesh.MeshType=Enum.MeshType.Sphere;mesh.Scale=size;return p
end
local function disc(parent,name,r,h,cf,color,mat) return part(parent,name,Vector3.new(h,r*2,r*2),cf*CFrame.Angles(0,0,math.pi/2),color,mat,Enum.PartType.Cylinder) end
local function beam(parent,name,a,b,width,color) return part(parent,name,Vector3.new(width,width,(b-a).Magnitude),CFrame.lookAt((a+b)/2,b),color,Enum.Material.Metal) end
function M.apply()
 assert(not game:GetService('RunService'):IsRunning(),'Stop Play before repair')
 local root=assert(workspace:FindFirstChild('CloudHarbor'),'CloudHarbor missing')
 local map=assert(workspace:FindFirstChild('Map'),'Generated Map missing')
 local env=assert(map:FindFirstChild('Environment'),'Environment missing')
 local plaza=root.Islands.CompassPlaza.StoneDeck
 local water=env.TurquoiseLagoon
 local SS=game:GetService('ServerStorage')
 local backup=SS:FindFirstChild('OldMap_Backup') or new(SS,'Folder','OldMap_Backup')
 local repair=backup:FindFirstChild('AlignmentRepair') or new(backup,'Folder','AlignmentRepair')
 if not repair:FindFirstChild('Map_BeforeRepair') then local copy=map:Clone();copy.Name='Map_BeforeRepair';copy.Parent=repair end
 local protected={}
 for _,group in {root.Landmarks.StillwaterFountain,root.Landmarks.TheWayfarerAirship,root.Booths} do
  local list=group:GetDescendants();table.insert(list,group)
  for _,o in list do
   local s={o=o,parent=o.Parent,name=o.Name}
   if o:IsA('BasePart') then s.cf=o.CFrame;s.size=o.Size;s.color=o.Color;s.material=o.Material end
   if o:IsA('LuaSourceContainer') then s.source=o.Source end
   table.insert(protected,s)
  end
 end
 -- The original ocean was built at plaza-local y=(top - 46).
 -- Derive the old frame from geometry rather than hard-coding a world translation.
 local previous=map:GetAttribute('BoundPlazaFrame') or water.CFrame*CFrame.new(0,46-plaza.Size.Y/2,0)
 local delta=plaza.CFrame*previous:Inverse()
 local moved=0
 for _,o in map:GetDescendants() do if o:IsA('BasePart') then o.CFrame=delta*o.CFrame;moved+=1 end end
 map:SetAttribute('BoundPlazaFrame',plaza.CFrame)
 map:SetAttribute('AlignmentRepairVersion',1)
 -- Rojo can restore old source decor; retire only the known unprotected duplicates.
 local retired=repair:FindFirstChild('RetiredSourceDuplicates') or new(repair,'Folder','RetiredSourceDuplicates')
 local removed=0
 for _,island in root.Islands:GetChildren() do
  if island.Name=='CompassPlaza' or island.Name:sub(1,8)~='Terrace_' then
   for _,name in {'FloatingRock','LowerRock','RockKeel'} do
    local old=island:FindFirstChild(name)
    if old and env:FindFirstChild(island.Name..'_CliffSkirt') then old.Parent=retired;removed+=1 end
   end
  end
 end
 local leaves=map.Decor:FindFirstChild('RefinedLegacyFoliage')
 if leaves then
  for _,tree in root.Decor:GetChildren() do
   if tree.Name:match('^Tree_') or tree.Name:match('^PlazaTree_') then
    for _,o in tree:GetChildren() do if o:IsA('BasePart') and (o.Name=='Crown' or o.Name=='LowPolyCrown') then o.Parent=retired;removed+=1 end end
   end
  end
 end
 local old=env:FindFirstChild('LagoonLighthouse')
 if not old or old:GetAttribute('ResortLighthouseVersion')~=2 then
  if old then old.Name='Lighthouse_BeforeRepair';old.Parent=repair end
  local lighthouse=new(env,'Model','LagoonLighthouse');lighthouse:SetAttribute('ResortLighthouseVersion',2)
  local ivory=Color3.fromRGB(237,229,209);local gold=Color3.fromRGB(194,157,91);local teal=Color3.fromRGB(46,149,155);local dark=Color3.fromRGB(33,73,85);local slate=Color3.fromRGB(94,122,126)
  local cf=water.CFrame*CFrame.new(-235,water.Size.Y/2+7,-260)
  local sand=Color3.fromRGB(206,199,171)
  -- A genuine rock island intersects the water and supports the entire foundation.
  oval(lighthouse,'LimestoneIslet',Vector3.new(52,12,44),cf*CFrame.new(0,-5,0),ivory,Enum.Material.Slate)
  disc(lighthouse,'Sandbar',27,.16,cf*CFrame.new(0,-6.9,0),sand,Enum.Material.Sand)
  for k=1,9 do
   local a=k*math.pi*2/9
   part(lighthouse,'ShoreBoulder',Vector3.new(7+(k%3),5,7),cf*CFrame.new(math.cos(a)*20,-4.8,math.sin(a)*17)*CFrame.Angles(.2,a,.18),if k%2==0 then ivory else slate,Enum.Material.Slate)
  end
  local foundation=disc(lighthouse,'Foundation',16.2,.7,cf*CFrame.new(0,1,0),ivory,Enum.Material.Marble);lighthouse.PrimaryPart=foundation
  disc(lighthouse,'FoundationGoldReveal',14.8,.16,cf*CFrame.new(0,1.42,0),gold,Enum.Material.Metal)
  disc(lighthouse,'UpperTerrace',13.4,.55,cf*CFrame.new(0,1.6,0),ivory,Enum.Material.Marble)
  disc(lighthouse,'TowerFoot',6.8,.7,cf*CFrame.new(0,2.15,0),dark,Enum.Material.Slate)
  disc(lighthouse,'TowerBaseMoulding',5.8,.4,cf*CFrame.new(0,2.65,0),gold,Enum.Material.Metal)
  for level=0,3 do
   local r=5-level*.3
   disc(lighthouse,'IvoryTowerTier_'..level,r,6,cf*CFrame.new(0,5.9+level*6,0),ivory,Enum.Material.Marble)
   if level<3 then
    disc(lighthouse,'TurquoiseFrieze_'..level,r+.03,.65,cf*CFrame.new(0,8.55+level*6,0),teal)
    disc(lighthouse,'BrassFriezeEdge_'..level,r+.05,.12,cf*CFrame.new(0,8.94+level*6,0),gold,Enum.Material.Metal)
   end
   if level>0 then
    for k=1,4 do
     local a=k*math.pi/2
     local frame=cf*CFrame.Angles(0,a,0)*CFrame.new(0,5.8+level*6,r+.03)
     part(lighthouse,'WindowBrassFrame',Vector3.new(1.05,2.2,.14),frame,gold,Enum.Material.Metal)
     part(lighthouse,'DeepBlueWindow',Vector3.new(.75,1.85,.1),frame*CFrame.new(0,0,.09),dark,Enum.Material.Glass)
    end
   end
  end
  part(lighthouse,'EntranceBrassFrame',Vector3.new(2.5,3.9,.18),cf*CFrame.new(0,4.85,5.05),gold,Enum.Material.Metal)
  part(lighthouse,'TealDoor',Vector3.new(2.05,3.5,.16),cf*CFrame.new(0,4.8,5.18),dark)
  oval(lighthouse,'DoorHandle',Vector3.one*.18,cf*CFrame.new(.6,4.8,5.3),gold,Enum.Material.Metal)
  for k=1,3 do part(lighthouse,'EntranceStep',Vector3.new(4,.28,1.4),cf*CFrame.new(0,1.95+k*.28,9.6-k*1.3),ivory,Enum.Material.Marble) end
  disc(lighthouse,'BalconyUnderCornice',6.2,.4,cf*CFrame.new(0,26.9,0),gold,Enum.Material.Metal)
  disc(lighthouse,'BalconyDeck',7,.6,cf*CFrame.new(0,27.3,0),ivory,Enum.Material.Marble)
  for k=1,12 do
   local a=k*math.pi*2/12;local b=(k+1)*math.pi*2/12
   part(lighthouse,'BalconyPost',Vector3.new(.14,2.2,.14),cf*CFrame.new(math.cos(a)*6.35,28.7,math.sin(a)*6.35),gold,Enum.Material.Metal)
   for _,y in {28.25,29.8} do beam(lighthouse,'BalconyRail',cf:PointToWorldSpace(Vector3.new(math.cos(a)*6.35,y,math.sin(a)*6.35)),cf:PointToWorldSpace(Vector3.new(math.cos(b)*6.35,y,math.sin(b)*6.35)),.12,dark) end
  end
  disc(lighthouse,'LanternBase',3.8,.4,cf*CFrame.new(0,27.9,0),dark,Enum.Material.Metal)
  for k=1,8 do
   local a=k*math.pi/4
   part(lighthouse,'LanternMullion',Vector3.new(.17,4.8,.17),cf*CFrame.new(math.cos(a)*3.4,30.5,math.sin(a)*3.4),gold,Enum.Material.Metal)
   local pane=part(lighthouse,'LanternGlass',Vector3.new(2.58,4.5,.08),cf*CFrame.Angles(0,a+math.pi/8,0)*CFrame.new(0,30.5,3.14),Color3.fromRGB(174,223,223),Enum.Material.Glass);pane.Transparency=.68
  end
  local lamp=oval(lighthouse,'WarmOptic',Vector3.new(1.6,2.3,1.6),cf*CFrame.new(0,30.4,0),Color3.fromRGB(255,224,170),Enum.Material.Neon)
  local light=new(lamp,'PointLight','LighthouseWarmLight');light.Color=lamp.Color;light.Brightness=.8;light.Range=20;light.Shadows=false
  for level=0,3 do disc(lighthouse,'SteppedNavyRoof',7.1-level*1.35,.6,cf*CFrame.new(0,33.25+level*.5,0),dark,Enum.Material.Metal) end
  disc(lighthouse,'RoofGoldFinial',.28,2,cf*CFrame.new(0,35.2,0),gold,Enum.Material.Metal)
  oval(lighthouse,'FinialPearl',Vector3.one*.6,cf*CFrame.new(0,36.3,0),gold,Enum.Material.Metal)
  for _,x in {-11,11} do
   oval(lighthouse,'LowShrub',Vector3.new(5.5,2.1,4),cf*CFrame.new(x,1.5,-8),Color3.fromRGB(95,159,137))
   oval(lighthouse,'CreamFlowerCluster',Vector3.new(2,.6,1.5),cf*CFrame.new(x,2.6,-8),Color3.fromRGB(247,217,170))
  end
 end
 -- Persist the attachment frame so repair is a no-op if repeated after no movement.
 local count=0
 for _,o in map:GetDescendants() do if o:IsA('BasePart') then count+=1 end end
 map:SetAttribute('GeneratedParts',count)
 for _,s in protected do
  local o=s.o;assert(o.Parent==s.parent and o.Name==s.name,'Protected hierarchy changed')
  if s.cf then assert(o.CFrame==s.cf and o.Size==s.size and o.Color==s.color and o.Material==s.material,'Protected part changed: '..o.Name) end
  if s.source then assert(o.Source==s.source,'Protected script changed') end
 end
 local expected=plaza.CFrame*CFrame.new(0,plaza.Size.Y/2-46,0)
 assert((water.Position-expected.Position).Magnitude<.02,'Ocean alignment failed')
 for _,island in root.Islands:GetChildren() do
  local d=island:FindFirstChild('StoneDeck');local skirt=env:FindFirstChild(island.Name..'_CliffSkirt')
  if d and skirt then
   local average=Vector3.zero;local n=0
   for _,p in skirt:GetChildren() do if p:IsA('BasePart') and p.Name=='FacetedLimestone' then average+=p.Position;n+=1 end end
   if n>0 then local localPoint=d.CFrame:PointToObjectSpace(average/n);assert(Vector2.new(localPoint.X,localPoint.Z).Magnitude<.1,'Cliff skirt not aligned: '..island.Name) end
  end
 end
 game:GetService('ChangeHistoryService'):SetWaypoint('Environment aligned and lighthouse rebuilt')
 print('HARBOR_REPAIR_OK: delta='..tostring(delta.Position)..'; moved='..moved..'; retired duplicates='..removed..'; generated parts='..count..'; protected='..#protected)
 return true
end
return M
