-- Stage 1 presentation only: distance-limited bubble chat and inexpensive local walk poses.
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local TextChat=game:GetService('TextChatService')
local C=require(RS:WaitForChild('HarborShared').Config).NPC
local remote=RS:WaitForChild('HarborNPCSpeech',30)
local folder=workspace:WaitForChild('HarborNPCs',30)
if not remote or not folder then return end
local records={};local connections={}
local function attach(model)
 if not model:IsA('Model') or not model:GetAttribute('NPCManaged') then return end
 local root=model:WaitForChild('HumanoidRootPart',5);local torso=model:FindFirstChild('UpperTorso') or model:FindFirstChild('Torso')
 if not root or not torso or not model.Parent then return end
 local parts={};for _,o in model:GetDescendants() do if o:IsA('BasePart') then table.insert(parts,o) end end
 records[model]={root=root,parts=parts,visible=true,motors={torso:FindFirstChild('Right Shoulder'),torso:FindFirstChild('Left Shoulder'),torso:FindFirstChild('Right Hip'),torso:FindFirstChild('Left Hip')}}
end
for _,m in folder:GetChildren() do task.spawn(attach,m) end
table.insert(connections,folder.ChildAdded:Connect(function(m)task.spawn(attach,m)end))
table.insert(connections,folder.ChildRemoved:Connect(function(m)records[m]=nil end))
table.insert(connections,remote.OnClientEvent:Connect(function(model,text)
 local camera=workspace.CurrentCamera;local head=typeof(model)=='Instance' and model:IsDescendantOf(folder) and model:FindFirstChild('Head')
 if camera and head and type(text)=='string' and #text<500 and (head.Position-camera.CFrame.Position).Magnitude<=C.BubbleDistance then
  if TextChat.BubbleChatConfiguration then TextChat.BubbleChatConfiguration.Enabled=true end
  TextChat:DisplayBubble(head,text)
 end
end))
local accum=0;local lodTime=0
local hb
hb=Run.PreSimulation:Connect(function(dt)
 accum+=dt;lodTime+=dt;if accum<1/30 then return end;accum=0
 local camera=workspace.CurrentCamera;if not camera then return end
 local t=os.clock()
 for model,r in records do
  if not r.root.Parent then records[model]=nil;continue end
  local distance=(r.root.Position-camera.CFrame.Position).Magnitude
  if lodTime>=.5 then
   local visible=distance<C.VisualDistance
   if visible~=r.visible then r.visible=visible;for _,p in r.parts do if p.Parent then p.LocalTransparencyModifier=visible and 0 or 1 end end end
  end
  if distance<C.AnimationDistance and model:FindFirstChild('Torso') then
   local moving=model:GetAttribute('NPCState')=='Walk' and r.root.AssemblyLinearVelocity.Magnitude>.5
   local talking=model:GetAttribute('NPCState')=='Chat'
   local angle=moving and math.sin(t*8)*.38 or math.sin(t*1.7)*.025
   for i,m in r.motors do if m then m.Transform=CFrame.Angles((i%2==0 and -1 or 1)*angle-(talking and i<=2 and .45 or 0),0,talking and i<=2 and math.sin(t*3+i)*.12 or 0) end end
  end
 end
 if lodTime>=.5 then lodTime=0 end
end)
table.insert(connections,hb)
script.Destroying:Connect(function()for _,c in connections do c:Disconnect() end;table.clear(records)end)
