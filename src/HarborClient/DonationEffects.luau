-- Short, client-only visuals triggered by validated server donation events.
local Tween=game:GetService('TweenService');local Debris=game:GetService('Debris');local M={}
function M.new(playerGui)
 local gui=Instance.new('ScreenGui');gui.Name='HarborDonationEffects';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=false;gui.DisplayOrder=64;gui.Parent=playerGui
 local alive=true;local rng=Random.new();local worldEffects={};local last={}
 local function tween(o,time,props) Tween:Create(o,TweenInfo.new(time,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),props):Play() end
 local controller={}
 function controller.screen()
  if not alive then return end
  -- A small celebratory burst near the toast, never a full-screen flash/shake.
  for i=1,14 do
   local p=Instance.new('Frame');p.Name='DonationSpark';p.AnchorPoint=Vector2.new(.5,.5);p.BorderSizePixel=0;p.Size=UDim2.fromOffset(rng:NextInteger(4,8),rng:NextInteger(5,10));p.BackgroundColor3=i%3==0 and Color3.fromRGB(255,221,125) or Color3.fromRGB(188,112,255);p.Position=UDim2.new(.5,rng:NextNumber(-150,150),1,-45);p.Rotation=45;p.Parent=gui
   tween(p,rng:NextNumber(.8,1.3),{Position=UDim2.new(.5,rng:NextNumber(-220,220),1,rng:NextNumber(-230,-110)),Rotation=rng:NextNumber(-140,180),BackgroundTransparency=1});Debris:AddItem(p,1.5)
  end
 end
 function controller.booth(data)
  if not alive or type(data)~='table' or typeof(data.BoothModel)~='Instance' or not data.BoothModel:IsDescendantOf(workspace) then return end
  local model=data.BoothModel;local anchor=model:FindFirstChild('CounterTop',true) or model:FindFirstChildWhichIsA('BasePart',true)
  if not anchor then return end
  local camera=workspace.CurrentCamera;if not camera or (camera.CFrame.Position-anchor.Position).Magnitude>130 then return end
  local now=os.clock();if now-(last[model] or -10)<.3 then return end;last[model]=now
  if worldEffects[model] then worldEffects[model]:Destroy() end
  local folder=Instance.new('Folder');folder.Name='LocalDonationEffect';folder.Parent=model;worldEffects[model]=folder
  local glow=Instance.new('Highlight');glow.Adornee=model;glow.DepthMode=Enum.HighlightDepthMode.Occluded;glow.FillColor=Color3.fromRGB(161,81,239);glow.OutlineColor=Color3.fromRGB(224,168,255);glow.FillTransparency=.8;glow.OutlineTransparency=.12;glow.Parent=folder
  tween(glow,1.3,{FillTransparency=1,OutlineTransparency=1})
  local attachment=Instance.new('Attachment');attachment.Name='DonationBurst';attachment.Position=Vector3.new(0,1,0);attachment.Parent=anchor
  local particles=Instance.new('ParticleEmitter');particles.Texture='rbxasset://textures/particles/sparkles_main.dds';particles.Color=ColorSequence.new(Color3.fromRGB(207,151,255),Color3.fromRGB(255,223,146));particles.LightEmission=.55;particles.Rate=0;particles.Lifetime=NumberRange.new(.55,1);particles.Speed=NumberRange.new(5,9);particles.SpreadAngle=Vector2.new(55,55);particles.Acceleration=Vector3.new(0,-7,0);particles.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(.4,.3),NumberSequenceKeypoint.new(1,0)});particles.Transparency=NumberSequence.new(0,1);particles.Parent=attachment;particles:Emit(20)
  local billboard=Instance.new('BillboardGui');billboard.Name='DonationAmountEffect';billboard.Adornee=anchor;billboard.Size=UDim2.fromOffset(160,46);billboard.StudsOffsetWorldSpace=Vector3.new(0,3,0);billboard.MaxDistance=110;billboard.AlwaysOnTop=false;billboard.Parent=folder
  local label=Instance.new('TextLabel');label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.Text='+'..tostring(data.Amount)..' D';label.Font=Enum.Font.GothamBold;label.TextSize=28;label.TextColor3=Color3.fromRGB(228,190,255);label.TextStrokeTransparency=.5;label.Parent=billboard
  tween(billboard,1.5,{StudsOffsetWorldSpace=Vector3.new(0,5.5,0)});tween(label,1.5,{TextTransparency=1,TextStrokeTransparency=1})
  Debris:AddItem(folder,1.7);Debris:AddItem(attachment,1.7)
  folder.Destroying:Connect(function()if attachment.Parent then attachment:Destroy() end;if worldEffects[model]==folder then worldEffects[model]=nil;last[model]=nil end end)
 end
 function controller.destroy()
  if not alive then return end;alive=false
  for _,folder in worldEffects do folder:Destroy() end;table.clear(worldEffects);table.clear(last);gui:Destroy()
 end
 return controller
end
return M
