-- Cloud Harbor fountain v2: visible flow, streaming-safe discovery, local effects.
-- No camera movement, global lighting changes, purchases or server physics.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
local mobile = Input.TouchEnabled and not Input.KeyboardEnabled
local INTERVAL = if mobile then 1/15 else 1/30
local RANGE = if mobile then 120 else 180
local FX_NAME = "__HarborFountainLocalFX"
local previous = workspace:FindFirstChild(FX_NAME)
if previous then previous:Destroy() end
local effects = Instance.new("Folder")
effects.Name = FX_NAME
effects.Parent = workspace
local fountain = nil
local surface = nil
local jets = {}
local splashes = {}
local lights = {}
local ripples = {}
local lastScan = -10
local elapsed = 0
local accumulated = 0
local reported = false
player:SetAttribute("HarborFountainStatus", "Starting")
print("[HarborFountain] v2 client started")

local function discover()
 local map = workspace:FindFirstChild("CloudHarbor")
 local landmarks = map and map:FindFirstChild("Landmarks")
 local found = landmarks and landmarks:FindFirstChild("StillwaterFountain")
 if found and found:IsA("Model") then return found end
 -- Handles a renamed parent folder while keeping the fountain's stable name.
 local fallback = workspace:FindFirstChild("StillwaterFountain", true)
 return if fallback and fallback:IsA("Model") then fallback else nil
end

local function makeDrop()
 local p = Instance.new("Part")
 p.Name = "FlowDroplet"
 p.Shape = Enum.PartType.Ball
 p.Size = Vector3.new(0.17, 0.17, 0.17)
 p.Color = Color3.fromRGB(222, 255, 255)
 p.Material = Enum.Material.SmoothPlastic
 p.Transparency = 0.18
 p.Anchored = true
 p.CanCollide = false
 p.CanQuery = false
 p.CanTouch = false
 p.CastShadow = false
 p.Parent = effects
 return p
end

local function rescan(found)
 fountain = found
 surface = found:FindFirstChild("WaterSurface", true)
 table.clear(jets)
 table.clear(splashes)
 table.clear(lights)
 table.clear(ripples)
 effects:ClearAllChildren()
 for _, object in found:GetDescendants() do
  if object:IsA("Beam") and object.Name:match("^WaterJet_") then
   if object.Attachment0 and object.Attachment1 then
    object.Enabled = true
    object.Segments = if mobile then 12 else 20
    local drops = {}
    for _ = 1, (if mobile then 3 else 5) do table.insert(drops, makeDrop()) end
    table.insert(jets, {beam=object, drops=drops})
   end
  elseif object:IsA("ParticleEmitter") and object.Name:match("^Splash_") then
   object.Rate = if mobile then 4 else 7
   object.Enabled = true
   table.insert(splashes, object)
  elseif object:IsA("PointLight") then
   table.insert(lights, object)
  elseif object:IsA("BasePart") and object.Name == "RippleSegment" then
   local phase = tonumber(object.Parent.Name:match("(%d+)$")) or 0
   table.insert(ripples, {part=object, phase=phase*0.7})
  end
 end
 player:SetAttribute("HarborFountainStatus", "Ready: "..#jets.." jets")
 if not reported and #jets > 0 then
  reported = true
  print("[HarborFountain] READY: "..#jets.." jets; animated droplets enabled")
 end
end

local function bezier(t, a, b, c, d)
 local u = 1-t
 return a*(u*u*u) + b*(3*u*u*t) + c*(3*u*t*t) + d*(t*t*t)
end

local connection
connection = RunService.Heartbeat:Connect(function(dt)
 if not effects.Parent then connection:Disconnect(); return end
 elapsed += dt
 accumulated += dt
 if accumulated < INTERVAL then return end
 accumulated = 0
 local found = discover()
 if not found then
  if fountain then effects:ClearAllChildren(); fountain=nil end
  player:SetAttribute("HarborFountainStatus", "Waiting for fountain to stream in")
  return
 end
 -- Re-scan occasionally because streaming can introduce attachments after the Beam.
 if found ~= fountain or elapsed-lastScan > 3 then
  rescan(found)
  lastScan = elapsed
 end
 local camera = workspace.CurrentCamera
 if not camera then return end
 -- Do NOT require PrimaryPart: it may be absent during partial streaming.
 local anchor = if surface and surface:IsA("BasePart") and surface.Parent then surface.Position else fountain:GetPivot().Position
 local nearby = (camera.CFrame.Position-anchor).Magnitude <= RANGE
 for i, data in jets do
  local beam = data.beam
  if not beam.Parent or not beam.Attachment0 or not beam.Attachment1 then lastScan=-10; continue end
  beam.Enabled = nearby
  for _, drop in data.drops do drop.Transparency = if nearby then 0.18 else 1 end
  if not nearby then continue end
  -- All droplets follow the actual world-space Beam curve, even after moving the map.
  local wave = math.sin(elapsed*1.45+i*0.65)
  beam.CurveSize0 = 5.4+wave*0.28
  beam.CurveSize1 = 4.9+wave*0.24
  beam.Width0 = 0.12+wave*0.015
  beam.Width1 = 0.085+wave*0.009
  local startFrame, endFrame = beam.Attachment0.WorldCFrame, beam.Attachment1.WorldCFrame
  local a,d = startFrame.Position,endFrame.Position
  local b = a+startFrame.RightVector*beam.CurveSize0
  local c = d-endFrame.RightVector*beam.CurveSize1
  for k, drop in data.drops do
   local t = (elapsed*0.65+k/#data.drops+i*0.13)%1
   drop.Position = bezier(t,a,b,c,d)
  end
 end
 for _, emitter in splashes do if emitter.Parent then emitter.Enabled=nearby end end
 for i, light in lights do
  if light.Parent then
   light.Enabled = nearby and (not mobile or i<=3)
   local base = if light.Name == "SculptureWarmLight" then 0.3 else 0.5
   light.Brightness = base*(1+math.sin(elapsed*0.8+i)*0.12)
  end
 end
 if not nearby then return end
 if surface and surface:IsA("BasePart") and surface.Parent then
  surface.Transparency = 0.30+math.sin(elapsed*0.9)*0.035
 end
 for _, data in ripples do
  if data.part.Parent then data.part.Transparency=0.73+math.sin(elapsed*3+data.phase)*0.18 end
 end
end)
