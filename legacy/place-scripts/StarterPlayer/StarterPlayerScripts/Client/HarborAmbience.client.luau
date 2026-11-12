-- Local ambience for the NEW resort decor only; never edits the fountain or airship.
-- Bounded update rate, distance-culling and streaming-safe rescans.
local RunService=game:GetService('RunService')
local Input=game:GetService('UserInputService')
local mobile=Input.TouchEnabled and not Input.KeyboardEnabled
local interval=if mobile then .12 else .08
local flags,lights,anchors={},{},{}
local rest=setmetatable({}, {__mode='k'})
local fx=Instance.new('Folder');fx.Name='__HarborResortMotes';fx.Parent=workspace
local elapsed,accumulated,lastScan=0,0,-10
local function scan(map)
 table.clear(flags);table.clear(lights);table.clear(anchors);fx:ClearAllChildren()
 for _,o in map:GetDescendants() do
  if o:IsA('BasePart') and o:GetAttribute('ResortAnimated') then
   rest[o]=rest[o] or o.CFrame;table.insert(flags,o)
  elseif o:IsA('PointLight') then table.insert(lights,o)
  elseif o:IsA('BasePart') and o.Name=='GardenMoteAnchor' then
   local motes={}
   for k=1,(if mobile then 2 else 4) do
    local p=Instance.new('Part');p.Name='GardenFirefly';p.Shape=Enum.PartType.Ball;p.Size=Vector3.one*.12
    p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
    p.Material=Enum.Material.Neon;p.Color=o:GetAttribute('ResortMoteColor') or Color3.fromRGB(255,224,164)
    p.Transparency=1;p.Parent=fx;table.insert(motes,p)
   end
   table.insert(anchors,{anchor=o,motes=motes})
  end
 end
end
local connection
connection=RunService.Heartbeat:Connect(function(dt)
 if not fx.Parent then connection:Disconnect();return end
 elapsed+=dt;accumulated+=dt;if accumulated<interval then return end;accumulated=0
 local map=workspace:FindFirstChild('Map');local camera=workspace.CurrentCamera
 if not map or not camera then return end
 if elapsed-lastScan>4 then scan(map);lastScan=elapsed end
 local position=camera.CFrame.Position
 for i,p in flags do
  if p.Parent and (p.Position-position).Magnitude<130 then
   p.CFrame=rest[p]*CFrame.Angles(0,math.sin(elapsed*1.4+i*.7)*.09,math.sin(elapsed+i)*.035)
  end
 end
 for _,l in lights do
  local p=l.Parent
  if p and p:IsA('BasePart') then l.Enabled=(p.Position-position).Magnitude<(if mobile then 85 else 140) end
 end
 for i,data in anchors do
  local a=data.anchor
  if a.Parent then
   local near=(a.Position-position).Magnitude<90
   for k,mote in data.motes do
    mote.Transparency=if near then .2+math.sin(elapsed*2+k)*.12 else 1
    if near then mote.Position=a.Position+Vector3.new(math.sin(elapsed*.4+k*2+i)*3,math.sin(elapsed*.8+k)*1.2,math.cos(elapsed*.5+k*1.7)*3) end
   end
  end
 end
end)
print('[HarborResort] Decor ambience ready; mobile='..tostring(mobile))
