-- Cloud Harbor: additive, staged edit-mode installer. No external assets.
-- Command Bar: require(game.ReplicatedStorage.Shared.HarborRedesign).stage(1)
-- Run stages 1..5 in order. Repeating a completed stage is a no-op.
local M = {}
local W, SS, L = workspace, game:GetService('ServerStorage'), game:GetService('Lighting')
local C = {ivory=Color3.fromRGB(242,234,212),gold=Color3.fromRGB(201,166,102),teal=Color3.fromRGB(55,157,158),deep=Color3.fromRGB(31,74,83),rock=Color3.fromRGB(83,117,124),water=Color3.fromRGB(53,151,168),leaf=Color3.fromRGB(83,166,143),wood=Color3.fromRGB(151,111,77)}
local cfg = {MaxNewParts=1650,ClockTime=16.8,Brightness=2.4,OceanDrop=46,LanternBrightness=0.65,AtmosphereDensity=0.27}
M.Config=cfg
local map,plaza,fountain,ship,backup,generated
local protected={}
local partCount=0
local function folder(parent,name,class)
 local f=Instance.new(class or 'Folder');f.Name=name;f.Parent=parent;return f
end
local function remember(root)
 local objects=root:GetDescendants();table.insert(objects,root)
 for _,o in objects do
  local s={object=o,parent=o.Parent,name=o.Name,attrs=game:GetService('HttpService'):JSONEncode(o:GetAttributes())}
  if o:IsA('BasePart') then s.cf=o.CFrame;s.size=o.Size;s.color=o.Color;s.mat=o.Material;s.trans=o.Transparency end
  if o:IsA('LuaSourceContainer') then s.source=o.Source end
  table.insert(protected,s)
 end
end
local function verify()
 for _,s in protected do
  local o=s.object
  assert(o.Parent==s.parent and o.Name==s.name,'Protected hierarchy changed: '..s.name)
  if s.cf then assert(o.CFrame==s.cf and o.Size==s.size and o.Color==s.color and o.Material==s.mat and o.Transparency==s.trans,'Protected geometry changed: '..s.name) end
  if s.source then assert(o.Source==s.source,'Protected script changed: '..s.name) end
  assert(game:GetService('HttpService'):JSONEncode(o:GetAttributes())==s.attrs,'Protected attributes changed: '..s.name)
 end
 assert(#map.Booths:GetChildren()==48,'Booth count changed')
 return true
end
local function setup()
 if map then return end
 assert(not game:GetService('RunService'):IsRunning(),'STOP the play test before installing')
 map=assert(W:FindFirstChild('CloudHarbor'),'CloudHarbor not found')
 fountain=assert(map.Landmarks:FindFirstChild('StillwaterFountain'),'Fountain not found')
 ship=assert(map.Landmarks:FindFirstChild('TheWayfarerAirship'),'Airship not found')
 plaza=assert(map.Islands.CompassPlaza:FindFirstChild('StoneDeck'),'Plaza not found')
 assert(#map.Booths:GetChildren()==48,'Expected 48 booths; stop for review')
 remember(fountain);remember(ship);remember(map.Booths)
 local scripts=game.StarterPlayer.StarterPlayerScripts:FindFirstChild('HarborFountain',true)
 if scripts then remember(scripts) end
 backup=SS:FindFirstChild('OldMap_Backup') or folder(SS,'OldMap_Backup')
 if not backup:FindFirstChild('CloudHarbor_BeforeResort') then
  local clone=assert(map:Clone(),'Map snapshot failed');clone.Name='CloudHarbor_BeforeResort';clone.Parent=backup
  local lightSnapshot=folder(backup,'Lighting_BeforeResort')
  for _,o in L:GetChildren() do local c=o:Clone();if c then c.Parent=lightSnapshot end end
  for _,key in {'ClockTime','Brightness','ExposureCompensation','EnvironmentDiffuseScale','EnvironmentSpecularScale','Ambient','OutdoorAmbient','ColorShift_Top','ColorShift_Bottom','GlobalShadows','ShadowSoftness'} do
   local value=L[key];local typ=typeof(value);local v=folder(lightSnapshot,key,if typ=='Color3' then 'Color3Value' elseif typ=='boolean' then 'BoolValue' else 'NumberValue');v.Value=value
  end
  lightSnapshot:SetAttribute('Technology',"Studio-managed (read restricted)")
 end
 generated=W:FindFirstChild('Map')
 assert(not generated or generated:GetAttribute('HarborResort')==true,'Workspace.Map belongs to another system')
 if not generated then generated=folder(W,'Map');generated:SetAttribute('HarborResort',true) end
 generated:SetAttribute('NewPartBudget',cfg.MaxNewParts)
 for _,o in generated:GetDescendants() do if o:IsA('BasePart') then partCount+=1 end end
 print('RESORT_PREFLIGHT: protected fountain '..tostring(fountain:GetPivot().Position)..'; ship '..tostring(ship:GetPivot().Position)..'; booths=48')
end
local function part(parent,name,size,frame,color,material,shape,collide)
 partCount+=1;assert(partCount<=cfg.MaxNewParts,'New-part budget exceeded')
 local p=Instance.new('Part');p.Name=name;p.Size=size;p.CFrame=frame;p.Color=color or C.ivory;p.Material=material or Enum.Material.SmoothPlastic
 p.Anchored=true;p.CanCollide=collide==true;p.CanQuery=collide==true;p.CanTouch=false;p.CastShadow=false;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 if shape then p.Shape=shape end
 p.Parent=parent;return p
end
local function ellipsoid(parent,name,size,frame,color,material)
 local p=part(parent,name,Vector3.one,frame,color,material)
 local mesh=Instance.new('SpecialMesh');mesh.MeshType=Enum.MeshType.Sphere;mesh.Scale=size;mesh.Parent=p;return p
end
local function rod(parent,name,a,b,width,color,material)
 return part(parent,name,Vector3.new(width,width,(b-a).Magnitude),CFrame.lookAt((a+b)/2,b),color,material)
end
local function localRod(parent,name,cf,a,b,w,color,material) return rod(parent,name,cf:PointToWorldSpace(a),cf:PointToWorldSpace(b),w,color,material) end
local function disk(parent,name,radius,thickness,cf,color,material)
 return part(parent,name,Vector3.new(thickness,radius*2,radius*2),cf*CFrame.Angles(0,0,math.pi/2),color,material,Enum.PartType.Cylinder)
end
local function plant(parent,cf,accent,height)
 local model=folder(parent,'SculptedTree','Model');height=height or 8
 part(model,'Trunk',Vector3.new(.65,height,.65),cf*CFrame.new(0,height/2,0),C.wood,Enum.Material.Wood)
 for j=1,3 do
  local a=j*2.094
  ellipsoid(model,'Canopy',Vector3.new(5.2,3.6,4.6),cf*CFrame.new(math.cos(a)*1.6,height+0.2+j*.55,math.sin(a)*1.6)*CFrame.Angles(0,a,0),if j==2 then accent else C.leaf)
 end
 disk(model,'Planter',3,.6,cf*CFrame.new(0,.3,0),C.ivory,Enum.Material.Marble)
 disk(model,'Soil',2.65,.12,cf*CFrame.new(0,.65,0),C.deep)
 return model
end
local function planter(parent,cf,accent)
 local p=folder(parent,'FlowerParterre','Model')
 part(p,'StoneBox',Vector3.new(9,.8,3.2),cf*CFrame.new(0,.4,0),C.ivory,Enum.Material.Marble)
 part(p,'GoldenLip',Vector3.new(9.15,.12,3.35),cf*CFrame.new(0,.85,0),C.gold,Enum.Material.Metal)
 for k=-1,1 do
  ellipsoid(p,'Hedge',Vector3.new(3.1,1.6,2.7),cf*CFrame.new(k*2.65,1.4,0),C.leaf)
  ellipsoid(p,'FlowerCluster',Vector3.new(1.15,.6,1.1),cf*CFrame.new(k*2.65,2.2,0),accent)
 end
end
local function lantern(parent,cf,lit)
 local p=folder(parent,'ResortLantern','Model')
 part(p,'Foot',Vector3.new(1,.3,1),cf*CFrame.new(0,.15,0),C.ivory,Enum.Material.Marble)
 part(p,'Post',Vector3.new(.22,6,.22),cf*CFrame.new(0,3,0),C.deep,Enum.Material.Metal)
 local glow=part(p,'WarmGlass',Vector3.new(.65,.85,.65),cf*CFrame.new(0,6.3,0),Color3.fromRGB(255,220,159),Enum.Material.Neon)
 part(p,'Cap',Vector3.new(1,.18,1),cf*CFrame.new(0,6.83,0),C.gold,Enum.Material.Metal)
 if lit then local l=Instance.new('PointLight');l.Name='ResortWarmLight';l.Brightness=cfg.LanternBrightness;l.Color=glow.Color;l.Range=13;l.Shadows=false;l.Parent=glow end
end
local function sign(parent,cf,title,accent)
 local board=part(parent,'IslandWayfinder',Vector3.new(11,2.8,.3),cf*CFrame.new(0,6.4,0),C.deep)
 for _,x in {-5,5} do part(parent,'WayfinderPost',Vector3.new(.25,6,.25),cf*CFrame.new(x,3,0),C.gold,Enum.Material.Metal) end
 for _,face in {Enum.NormalId.Front,Enum.NormalId.Back} do
  local gui=Instance.new('SurfaceGui');gui.Face=face;gui.CanvasSize=Vector2.new(660,168);gui.LightInfluence=.3;gui.Parent=board
  local text=Instance.new('TextLabel');text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.Text=title;text.TextColor3=accent;text.Font=Enum.Font.GothamMedium;text.TextScaled=true;text.Parent=gui
  local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(.06,0);pad.PaddingRight=UDim.new(.06,0);pad.Parent=text
 end
end
local function oceanStage(parent)
 local env=folder(parent,'Environment');local cf=plaza.CFrame;local top=plaza.Size.Y/2
 local base=W:FindFirstChild('Baseplate');if base then base.Parent=backup end
 local sea=part(env,'TurquoiseLagoon',Vector3.new(2600,3,2600),cf*CFrame.new(0,top-cfg.OceanDrop,0),C.water,Enum.Material.SmoothPlastic)
 sea.Reflectance=.08
 -- Narrow highlight shoals, not stacked transparent full-screen water planes.
 for k=1,14 do
  local a=k*math.pi*2/14;local r=330+(k%3)*55
  local at=cf*CFrame.new(math.cos(a)*r,top-cfg.OceanDrop+1.52,math.sin(a)*r)*CFrame.Angles(0,a,0)
  disk(env,'DistantShoal',35+(k%3)*10,.08,at,Color3.fromRGB(76,176,184))
  local island=folder(env,'HorizonIslet_'..k,'Model')
  ellipsoid(island,'LimestoneIsland',Vector3.new(46,17,33),at*CFrame.new(0,6,0),C.ivory,Enum.Material.Slate)
  ellipsoid(island,'GardenCrown',Vector3.new(37,7,27),at*CFrame.new(0,14,0),C.leaf,Enum.Material.Grass)
  if k%2==0 then plant(island,at*CFrame.new(0,17,0),C.teal,10) end
 end
 -- Native mesh-free wedge cliffs add silhouette to all five main platforms.
 for _,island in map.Islands:GetChildren() do
  local d=island:FindFirstChild('StoneDeck')
  if d and island.Name:sub(1,8)~='Terrace_' then
   local rocks=folder(env,island.Name..'_CliffSkirt','Model')
   for _,oldName in {'FloatingRock','LowerRock','RockKeel'} do
    local old=island:FindFirstChild(oldName)
    if old then local b=backup:FindFirstChild('RetiredRockBases') or folder(backup,'RetiredRockBases');old.Parent=b end
   end
   for k=1,10 do
    local a=2*math.pi*k/10;local radius=math.min(d.Size.X,d.Size.Z)*.39
    local size=Vector3.new(12+(k%3)*3,14+(k%4)*3,13)
    local rock=Instance.new('WedgePart');partCount+=1;assert(partCount<=cfg.MaxNewParts,'Part budget')
    rock.Name='FacetedLimestone';rock.Size=size;rock.CFrame=d.CFrame*CFrame.new(math.cos(a)*radius,-size.Y/2-3.5,math.sin(a)*radius)*CFrame.Angles(math.pi, -a, .12)
    rock.Color=if k%3==0 then C.ivory else C.rock;rock.Material=Enum.Material.Slate;rock.Anchored=true;rock.CanCollide=false;rock.CanTouch=false;rock.CanQuery=false;rock.CastShadow=false;rock.Parent=rocks
   end
   for k=1,3 do
    local a=k*2.094
    part(rocks,'HangingCrystal',Vector3.new(2.2,7+k,2.2),d.CFrame*CFrame.new(math.cos(a)*12,-15,math.sin(a)*12)*CFrame.Angles(.2,a,.35),C.teal,Enum.Material.Glass)
   end
  end
 end
 -- A lighthouse is built from primitive geometry on a distant islet.
 local light=folder(env,'LagoonLighthouse','Model');local lc=cf*CFrame.new(-235,top-cfg.OceanDrop+18,-260)
 disk(light,'LighthouseFoot',13,3,lc,C.ivory,Enum.Material.Marble)
 disk(light,'IvoryTower',5,27,lc*CFrame.new(0,15,0),C.ivory,Enum.Material.Marble)
 for y=6,24,9 do disk(light,'TealTowerBand',5.06,2,lc*CFrame.new(0,y,0),C.teal) end
 disk(light,'LanternDeck',7,.5,lc*CFrame.new(0,29,0),C.gold,Enum.Material.Metal)
 disk(light,'LanternGlow',3.8,4,lc*CFrame.new(0,31,0),Color3.fromRGB(255,223,163),Enum.Material.Neon)
 disk(light,'Roof',6,1,lc*CFrame.new(0,34,0),C.deep)
 for k=1,10 do
  local a=k*2.39996;local cc=cf*CFrame.new(math.cos(a)*(240+k*11),42+(k%3)*12,math.sin(a)*(240+k*11))
  for j=-1,1 do ellipsoid(env,'LowHorizonCloud',Vector3.new(35,9,17),cc*CFrame.new(j*16,j%2*2,0),Color3.fromRGB(231,243,238)) end
 end
end
local function plazaStage(parent)
 local decor=folder(parent,'Decor');local lights=folder(parent,'Lights');local cf=plaza.CFrame*CFrame.new(0,plaza.Size.Y/2+.06,0)
 -- Leave a clear exclusion radius of 15 studs around the untouched fountain.
 for k=1,32 do
  local a=k*math.pi*2/32
  part(decor,'PearlRingInlay',Vector3.new(.22,.035,4.9),cf*CFrame.new(math.cos(a)*26,0,math.sin(a)*26)*CFrame.Angles(0,-a,0),if k%2==0 then C.gold else C.teal,Enum.Material.Marble)
 end
 for _,x in {-31,31} do for _,z in {-31,31} do
  planter(decor,cf*CFrame.new(x,0,z),Color3.fromRGB(255,218,189))
  lantern(lights,cf*CFrame.new(x-math.sign(x)*5,0,z),true)
 end end
 for _,z in {-34,34} do
  for _,x in {-16,16} do
   part(decor,'InsetWaterChannel',Vector3.new(9,.1,2),cf*CFrame.new(x,.02,z),C.teal,Enum.Material.Glass)
   for _,side in {-1,1} do part(decor,'ChannelBrassBorder',Vector3.new(9,.12,.14),cf*CFrame.new(x,.07,z+side*1.05),C.gold,Enum.Material.Metal) end
  end
 end
 -- Add rails and scalloped string lights, preserving all existing bridge parts.
 for index,bridge in map.Bridges:GetChildren() do
  local deck=bridge:FindFirstChild('CollisionDeck') or bridge:FindFirstChild('Deck')
  if not deck then for _,p in bridge:GetDescendants() do if p:IsA('BasePart') and p.CanCollide then deck=p;break end end end
  if deck then
   local frame=deck.CFrame*CFrame.new(0,deck.Size.Y/2,0)
   local longX=deck.Size.X>deck.Size.Z
   local width=if longX then deck.Size.Z else deck.Size.X
   local length=if longX then deck.Size.X else deck.Size.Z
   if longX then frame=frame*CFrame.Angles(0,math.pi/2,0) end
   local g=folder(decor,'Bridge_'..index..'_Jewelry','Model')
   for _,side in {-1,1} do
    for _,z in {-length/2+1,0,length/2-1} do
     part(g,'BrassFinialPost',Vector3.new(.32,5,.32),frame*CFrame.new(side*(width/2+.35),2.5,z),C.gold,Enum.Material.Metal)
     ellipsoid(g,'PearlFinial',Vector3.one*.65,frame*CFrame.new(side*(width/2+.35),5.2,z),C.ivory)
    end
    for _,height in {1.6,3.3} do part(g,'TealHandrail',Vector3.new(.2,.18,length),frame*CFrame.new(side*(width/2+.35),height,0),C.deep,Enum.Material.Metal) end
    for j=1,8 do
     local t=(j-1)/7;local z=-length/2+1+t*(length-2);local y=5.1-math.sin(t*math.pi)*.9
     if j>1 then local t0=(j-2)/7;localRod(g,'FestoonCable',frame,Vector3.new(side*(width/2+.35),5.1-math.sin(t0*math.pi)*.9,-length/2+1+t0*(length-2)),Vector3.new(side*(width/2+.35),y,z),.05,C.deep) end
     ellipsoid(g,'WarmFestoonBulb',Vector3.one*.3,frame*CFrame.new(side*(width/2+.35),y-.12,z),Color3.fromRGB(255,224,161),Enum.Material.Neon)
    end
   end
   for _,z in {-length/2+2,length/2-2} do lantern(lights,frame*CFrame.new(width/2+1.4,0,z),false) end
  end
 end
end
local themes={{name='MAGNOLIA GARDEN',color=Color3.fromRGB(246,192,204)},{name='CORAL COURT',color=Color3.fromRGB(244,172,135)},{name='GOLDEN ORANGERY',color=Color3.fromRGB(236,204,115)},{name='MOONLIGHT GROVE',color=Color3.fromRGB(163,181,233)}}
local function islandsStage(parent)
 local root=folder(parent,'Islands');local main={}
 for _,i in map.Islands:GetChildren() do if i.Name~='CompassPlaza' and i.Name:sub(1,8)~='Terrace_' and i:FindFirstChild('StoneDeck') then table.insert(main,i) end end
 table.sort(main,function(a,b)return a.Name<b.Name end);assert(#main==4,'Expected four booth islands')
 for index,island in main do
  local theme=themes[index];local group=folder(root,'Island'..index);group:SetAttribute('Theme',theme.name)
  local d=island.StoneDeck;local cf=d.CFrame*CFrame.new(0,d.Size.Y/2+.03,0)
  -- Existing booths sit to either side of z=0. All new features stay in the clear median or corners.
  for k=-5,5 do
   local x=k*8
   part(group,'PromenadePaver',Vector3.new(7.5,.055,9),cf*CFrame.new(x,.01,0),if k%2==0 then C.ivory else Color3.fromRGB(217,225,214),Enum.Material.Marble)
   part(group,'ThemeDiamond',Vector3.new(.65,.07,.65),cf*CFrame.new(x,.08,0)*CFrame.Angles(0,math.pi/4,0),theme.color,Enum.Material.Marble)
  end
  for _,z in {-5.1,5.1} do part(group,'PromenadeBrassInlay',Vector3.new(93,.05,.12),cf*CFrame.new(0,.08,z),C.gold,Enum.Material.Metal) end
  for _,x in {-43,43} do
   for _,z in {-26,26} do
    plant(group,cf*CFrame.new(x,0,z),theme.color,7+(index%2)*2)
   end
   planter(group,cf*CFrame.new(x,0,-11)*CFrame.Angles(0,math.pi/2,0),theme.color)
   planter(group,cf*CFrame.new(x,0,11)*CFrame.Angles(0,math.pi/2,0),theme.color)
   lantern(group,cf*CFrame.new(x,0,5.8),true)
   -- Two decorative rubbish bins: no collisions or queries.
   disk(group,'WasteBin',.6,1.8,cf*CFrame.new(x,1,-6.4),C.deep,Enum.Material.Metal)
   disk(group,'WasteBinLid',.7,.15,cf*CFrame.new(x,2,-6.4),C.gold,Enum.Material.Metal)
  end
  sign(group,cf*CFrame.new(-34,0,0)*CFrame.Angles(0,math.pi/2,0),theme.name,theme.color)
  for _,x in {-20,20} do
   for _,z in {-30.5,30.5} do
    part(group,'PergolaPost',Vector3.new(.3,9,.3),cf*CFrame.new(x,4.5,z),C.wood,Enum.Material.Wood)
    part(group,'PergolaLintel',Vector3.new(14,.3,.4),cf*CFrame.new(x,9,z),C.gold,Enum.Material.Metal)
    for j=-2,2 do
     local px=x+j*2
     local flag=part(group,'ThemePennant',Vector3.new(.9,1.25,.07),cf*CFrame.new(px,8.2,z),if j%2==0 then theme.color else C.ivory,Enum.Material.Fabric)
     flag:SetAttribute('ResortAnimated',true)
    end
   end
  end
  -- A decorative native-primitive pond at a corner, away from booth footprints.
  local pond=folder(group,'GardenPond','Model');local pc=cf*CFrame.new(0,0,29)
  disk(pond,'PondStoneRim',4,.35,pc*CFrame.new(0,.18,0),C.ivory,Enum.Material.Marble)
  disk(pond,'PondWater',3.6,.05,pc*CFrame.new(0,.38,0),C.teal,Enum.Material.Glass)
  for j=1,3 do disk(pond,'LilyPad',.6,.04,pc*CFrame.new(math.cos(j*2)*2,.43,math.sin(j*2)*2),C.leaf) end
  local anchor=part(group,'GardenMoteAnchor',Vector3.one,pc*CFrame.new(0,3,0),theme.color);anchor.Transparency=1
  -- Ambient motion is client-only and uses primitives; no unavailable particle texture IDs.
  anchor:SetAttribute('ResortMoteColor',theme.color)
 end
end
local function lightingStage(parent)
 local retired=backup:FindFirstChild('RetiredLightingEffects') or folder(backup,'RetiredLightingEffects')
 for _,o in L:GetChildren() do if o:IsA('Atmosphere') or o:IsA('PostEffect') then o.Parent=retired end end
 L.ClockTime=cfg.ClockTime;L.Brightness=cfg.Brightness;L.Ambient=Color3.fromRGB(112,132,145);L.OutdoorAmbient=Color3.fromRGB(152,172,179)
 L.ColorShift_Top=Color3.fromRGB(22,13,3);L.ColorShift_Bottom=Color3.new();L.GlobalShadows=true;L.ShadowSoftness=.6
 L.EnvironmentDiffuseScale=.65;L.EnvironmentSpecularScale=.45;L.ExposureCompensation=.05
 local ok=pcall(function()L.Technology=Enum.Technology.ShadowMap end)
 generated:SetAttribute('LightingTechnology',"Studio-managed (read restricted)");generated:SetAttribute('TechnologyEditable',ok)
 local a=folder(L,'ResortAtmosphere','Atmosphere');a.Density=cfg.AtmosphereDensity;a.Offset=.12;a.Color=Color3.fromRGB(205,232,233);a.Decay=Color3.fromRGB(222,204,175);a.Glare=.08;a.Haze=1.4
 local b=folder(L,'ResortBloom','BloomEffect');b.Intensity=.12;b.Size=18;b.Threshold=1.45
 local c=folder(L,'ResortColor','ColorCorrectionEffect');c.Contrast=.06;c.Saturation=.09;c.Brightness=.01;c.TintColor=Color3.fromRGB(255,248,234)
 local rays=folder(L,'ResortSunRays','SunRaysEffect');rays.Intensity=.035;rays.Spread=.7
 local dof=folder(L,'ResortDepthOfField','DepthOfFieldEffect');dof.Enabled=false;dof.FarIntensity=.06;dof.NearIntensity=0;dof.FocusDistance=100;dof.InFocusRadius=90
 if not L:FindFirstChildOfClass('Sky') then local sky=folder(L,'ResortSky','Sky');sky.CelestialBodiesShown=true;sky.StarCount=800;sky.SunAngularSize=11 end
 local clouds=W.Terrain:FindFirstChildOfClass('Clouds')
 if clouds then local copy=clouds:Clone();copy.Name='Clouds_BeforeResort';copy.Parent=backup else clouds=folder(W.Terrain,'ResortClouds','Clouds') end
 clouds.Cover=.42;clouds.Density=.35;clouds.Color=Color3.fromRGB(244,238,218)
 local soundRoot=folder(parent,'Ambience')
 for _,name in {'LagoonWater','SoftWind','GardenBirds'} do local sound=folder(soundRoot,name,'Sound');sound.SoundId='';sound.Volume=.12;sound.Looped=true;sound:SetAttribute('Note','Placeholder only; no external audio ID supplied') end
 print('RESORT_LIGHTING: ClockTime='..L.ClockTime..'; Technology='.."Studio-managed (read restricted)"..'; technology editable='..tostring(ok)..'; DOF disabled for gameplay')
end
local function polishStage(parent)
 if not generated.Decor:FindFirstChild('RefinedLegacyFoliage') then
  local leaves=folder(generated.Decor,'RefinedLegacyFoliage')
  local old=backup:FindFirstChild('RetiredTreeCrowns') or folder(backup,'RetiredTreeCrowns')
  for _,tree in map.Decor:GetChildren() do
   if tree.Name:match('^Tree_') or tree.Name:match('^PlazaTree_') then
    for _,crown in tree:GetChildren() do
     if crown:IsA('BasePart') and (crown.Name=='Crown' or crown.Name=='LowPolyCrown') then
      local cf,size=crown.CFrame,crown.Size
      crown.Parent=old
      for k=1,3 do
       local angle=k*2.094
       ellipsoid(leaves,'SculptedLegacyCanopy',Vector3.new(size.X*.72,size.Y*.8,size.Z*.72),cf*CFrame.new(math.cos(angle)*size.X*.23,math.sin(k)*.6,math.sin(angle)*size.Z*.23),if k==2 then Color3.fromRGB(130,190,159) else C.leaf)
      end
     end
    end
   end
  end
 end
 local count=0;local pointLights=0
 for _,o in generated:GetDescendants() do
  if o:IsA('BasePart') then count+=1;assert(o.Anchored and not o.CanCollide and not o.CanQuery and not o.CanTouch,'Decor physics policy violated: '..o.Name)
  elseif o:IsA('PointLight') then pointLights+=1 end
 end
 verify();generated:SetAttribute('GeneratedParts',count);generated:SetAttribute('PointLights',pointLights);generated:SetAttribute('ProtectedAuditPassed',true)
 print('RESORT_AUDIT_OK: booths=48; protectedInstances='..#protected..'; newParts='..count..'; newPointLights='..pointLights..'; backup=ServerStorage.OldMap_Backup')
end
local builders={oceanStage,plazaStage,islandsStage,lightingStage,polishStage}
function M.stage(number)
 setup();assert(builders[number],'Choose stage 1..5');verify()
 local key='Stage'..number
 if generated:FindFirstChild(key) then print('RESORT_STAGE_'..number..'_ALREADY_DONE');return end
 for previous=1,number-1 do assert(generated:FindFirstChild('Stage'..previous),'Complete stage '..previous..' first') end
 local stage=folder(generated,key)
 local ok,err=xpcall(function()builders[number](stage);verify()end,debug.traceback)
 if not ok then stage.Name=key..'_Failed_'..os.time();stage.Parent=backup;error(err) end
 for _,child in stage:GetChildren() do child.Parent=generated end
 stage:SetAttribute('Complete',true)
 print('RESORT_STAGE_'..number..'_OK; cumulative newParts='..partCount)
end
return M
