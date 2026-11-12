-- Single notification renderer, invoked only by server Donation messages.
local Tween=game:GetService('TweenService')
local Players=game:GetService('Players')
local M={}
function M.new(playerGui,config,effects)
 local old=playerGui:FindFirstChild('HarborDonationToast');if old then old:Destroy() end
 local connections={};local queue={};local alive=true;local running=false;local generation=0;local activeTweens={};local avatarWorld
 local function make(class,name,props,parent)
  local o=Instance.new(class);o.Name=name;for k,v in props do o[k]=v end;o.Parent=parent;return o
 end
 local gui=make('ScreenGui','HarborDonationToast',{ResetOnSpawn=false,IgnoreGuiInset=false,DisplayOrder=65,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
 local notice=make('CanvasGroup','DonationNotice',{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,132),Size=UDim2.fromOffset(620,112),BackgroundColor3=Color3.fromRGB(48,24,88),BorderSizePixel=0,Visible=false,GroupTransparency=1},gui)
 local scale=make('UIScale','ResponsiveScale',{Scale=1},notice)
 make('UICorner','Round',{CornerRadius=UDim.new(0,30)},notice)
 make('UIStroke','PurpleEdge',{Color=Color3.fromRGB(184,91,255),Thickness=3,Transparency=.05},notice)
 make('UIGradient','PurpleSurface',{Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(79,37,132)),ColorSequenceKeypoint.new(.5,Color3.fromRGB(48,24,88)),ColorSequenceKeypoint.new(1,Color3.fromRGB(58,31,106))}),Rotation=25},notice)
 local avatarFrame=make('Frame','AvatarCircle',{Position=UDim2.fromOffset(16,12),Size=UDim2.fromOffset(88,88),BackgroundColor3=Color3.fromRGB(98,43,172),BorderSizePixel=0,ClipsDescendants=true},notice)
 make('UICorner','Circle',{CornerRadius=UDim.new(1,0)},avatarFrame)
 make('UIStroke','AvatarEdge',{Color=Color3.fromRGB(188,112,255),Thickness=3},avatarFrame)
 local initial=make('TextLabel','AvatarInitial',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Text='',Font=Enum.Font.GothamBold,TextSize=34,TextColor3=Color3.new(1,1,1)},avatarFrame)
 local avatar=make('ImageLabel','Avatar',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Image='',Visible=false},avatarFrame)
 make('UICorner','AvatarCircle',{CornerRadius=UDim.new(1,0)},avatar)
 local viewport=make('ViewportFrame','NPCPortrait',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false,Ambient=Color3.fromRGB(190,177,210),LightColor=Color3.new(1,1,1),LightDirection=Vector3.new(-1,-1,-2)},avatarFrame)
 make('UICorner','PortraitCircle',{CornerRadius=UDim.new(1,0)},viewport)
 local name=make('TextLabel','SenderName',{Position=UDim2.fromOffset(126,20),Size=UDim2.fromOffset(292,33),BackgroundTransparency=1,Text='',Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.fromRGB(252,248,255),TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,RichText=false},notice)
 make('TextLabel','Message',{Position=UDim2.fromOffset(127,58),Size=UDim2.fromOffset(316,28),BackgroundTransparency=1,Text='отправил тебе донат!',Font=Enum.Font.GothamBold,TextSize=21,TextColor3=Color3.fromRGB(193,137,242),TextXAlignment=Enum.TextXAlignment.Left},notice)
 local coin=make('ImageLabel','DonationCurrencyIcon',{Position=UDim2.fromOffset(451,35),Size=UDim2.fromOffset(42,42),BackgroundTransparency=1,Image=config.TestCurrency.Icon,ScaleType=Enum.ScaleType.Fit},notice)
 local amount=make('TextLabel','Amount',{Position=UDim2.fromOffset(500,31),Size=UDim2.fromOffset(105,49),BackgroundTransparency=1,Text='',Font=Enum.Font.GothamBold,TextSize=34,TextScaled=true,TextColor3=Color3.fromRGB(252,248,255),TextXAlignment=Enum.TextXAlignment.Left},notice)
 make('UITextSizeConstraint','AmountSize',{MinTextSize=15,MaxTextSize=34},amount)
 local function resize()
  local camera=workspace.CurrentCamera;if camera then scale.Scale=math.clamp((camera.ViewportSize.X-32)/620,.35,.82) end
 end
 resize();local camera=workspace.CurrentCamera
 if camera then table.insert(connections,camera:GetPropertyChangedSignal('ViewportSize'):Connect(resize)) end
 local function clearPortrait()
  if avatarWorld then avatarWorld:Destroy();avatarWorld=nil end
  local oldCamera=viewport:FindFirstChildOfClass('Camera');if oldCamera then oldCamera:Destroy() end
  viewport.CurrentCamera=nil;viewport.Visible=false;avatar.Visible=false;avatar.Image=''
 end
 local function portrait(data,token)
  clearPortrait();local second=utf8.offset(data.Name,2);initial.Text=data.Name:sub(1,second and second-1 or #data.Name)
  if data.NPC and typeof(data.NPCModel)=='Instance' and data.NPCModel:IsA('Model') and data.NPCModel.Parent then
   local source=data.NPCModel;local was=source.Archivable;source.Archivable=true;local clone=source:Clone();source.Archivable=was
   if clone then
    for _,o in clone:GetDescendants() do if o:IsA('LuaSourceContainer') or o:IsA('Sound') or o:IsA('ParticleEmitter') then o:Destroy() elseif o:IsA('BasePart') then o.Anchored=true;o.CanCollide=false;o.LocalTransparencyModifier=0 end end
    avatarWorld=Instance.new('WorldModel');avatarWorld.Parent=viewport;clone.Parent=avatarWorld;clone:PivotTo(CFrame.identity)
    local head=clone:FindFirstChild('Head');local root=clone:FindFirstChild('HumanoidRootPart')
    if head and root then
     local cam=Instance.new('Camera');cam.FieldOfView=32;cam.CFrame=CFrame.lookAt(head.Position+root.CFrame.LookVector*4+Vector3.new(0,.15,0),head.Position-Vector3.new(0,.18,0));cam.Parent=viewport;viewport.CurrentCamera=cam;viewport.Visible=true;initial.Text=''
    end
   end
  elseif type(data.UserId)=='number' and data.UserId>0 then
   task.spawn(function()
    local ok,url=pcall(Players.GetUserThumbnailAsync,Players,data.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size150x150)
    if alive and generation==token and ok then avatar.Image=url;avatar.Visible=true;initial.Text='' end
   end)
  end
 end
 local function animate(properties,duration,style,direction)
  local tween=Tween:Create(notice,TweenInfo.new(duration,style,direction),properties);activeTweens[tween]=true;tween:Play();tween.Completed:Wait();activeTweens[tween]=nil
 end
 local function drain()
  if running then return end;running=true
  task.spawn(function()
   while alive and #queue>0 do
    local data=table.remove(queue,1);generation+=1;local token=generation
    name.Text=data.Name;amount.Text='+'..tostring(data.Amount)..(coin.IsLoaded and '' or ' D');portrait(data,token)
    notice.Position=UDim2.new(.5,0,1,132);notice.GroupTransparency=1;notice.Visible=true
    notice:SetAttribute('ShowingDonation',true)
    if effects then effects.screen() end
    animate({Position=UDim2.new(.5,0,1,-24),GroupTransparency=0},.42,Enum.EasingStyle.Quint,Enum.EasingDirection.Out)
    local untilTime=os.clock()+3.1
    repeat task.wait(.1) until not alive or os.clock()>=untilTime
    if not alive then break end
    animate({Position=UDim2.new(.5,0,1,132),GroupTransparency=1},.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
    if alive then notice.Visible=false;notice:SetAttribute('ShowingDonation',false);clearPortrait() end
   end
   running=false
  end)
 end
 local controller={}
 function controller.enqueue(data)
  if not alive or type(data)~='table' or type(data.Name)~='string' or type(data.Amount)~='number' or data.Amount~=data.Amount or data.Amount<=0 or data.Amount%1~=0 then return end
  if #queue>=30 then table.remove(queue,1) end
  table.insert(queue,{Name=string.sub(data.Name,1,80),Amount=data.Amount,UserId=data.UserId,NPC=data.NPC==true,NPCModel=data.NPCModel});drain()
 end
 function controller.destroy()
  if not alive then return end;alive=false;generation+=1;table.clear(queue)
  for tween in activeTweens do tween:Cancel() end
  for _,connection in connections do connection:Disconnect() end;table.clear(connections);clearPortrait()
  if gui.Parent then gui:Destroy() end
 end
 table.insert(connections,gui.Destroying:Connect(controller.destroy))
 return controller
end
return M
