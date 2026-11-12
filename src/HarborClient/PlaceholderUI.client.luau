-- TEMPORARY test interface (Config.PlaceholderUI). Functional only, so the build can be play-tested in Studio
-- until the owner picks a UI concept (docs/UI_CONCEPTS.md); the chosen concept replaces this file entirely.
-- Sends intent only: request ids, accept/decline, offer indices, preset amounts. The server validates everything.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local TweenService=game:GetService('TweenService')
local UserInputService=game:GetService('UserInputService')
local config=require(RS:WaitForChild('HarborShared'):WaitForChild('Config'))
if config.PlaceholderUI==false then return end
local player=Players.LocalPlayer
local playerGui=player:WaitForChild('PlayerGui')
local harbor=RS:WaitForChild('HarborGame')
local remote=harbor:WaitForChild('Action')

local INK=Color3.fromRGB(253,245,223) -- ivory
local PANEL=Color3.fromRGB(29,65,74) -- deep teal
local BUTTON=Color3.fromRGB(47,148,147) -- teal
local ACCENT=Color3.fromRGB(204,164,91) -- gold
local MUTED=Color3.fromRGB(90,110,115)

local function make(class,props,parent)
 local o=Instance.new(class)
 for k,v in props do o[k]=v end
 o.Parent=parent
 return o
end
local function panel(props,parent)
 props.BackgroundColor3=PANEL;props.BackgroundTransparency=props.BackgroundTransparency or .08;props.BorderSizePixel=0
 local f=make('Frame',props,parent)
 make('UICorner',{CornerRadius=UDim.new(0,6)},f)
 make('UIStroke',{Color=ACCENT,Thickness=1,Transparency=.35},f)
 return f
end
local function label(text,props,parent)
 props.Text=text;props.BackgroundTransparency=1;props.TextColor3=props.TextColor3 or INK
 props.Font=props.Font or Enum.Font.GothamMedium;props.TextSize=props.TextSize or 16;props.TextWrapped=true
 return make('TextLabel',props,parent)
end
local function button(text,props,parent,onClick)
 props.Text=text;props.BackgroundColor3=props.BackgroundColor3 or BUTTON;props.TextColor3=INK;props.AutoButtonColor=true
 props.Font=Enum.Font.GothamBold;props.TextSize=props.TextSize or 16;props.BorderSizePixel=0
 local b=make('TextButton',props,parent)
 make('UICorner',{CornerRadius=UDim.new(0,5)},b)
 if onClick then b.Activated:Connect(onClick) end
 return b
end
local function fmt(n) -- 12500 -> 12,500
 local s=tostring(math.floor(n));local out=s:reverse():gsub('(%d%d%d)','%1,'):reverse()
 return (out:gsub('^,',''))
end

local gui=make('ScreenGui',{Name='HarborTestUI',ResetOnSpawn=false,DisplayOrder=40,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
local scale=make('UIScale',{},gui)
local function rescale()
 local cam=workspace.CurrentCamera
 if cam then scale.Scale=math.clamp(cam.ViewportSize.Y/720,.75,1.2) end
end
rescale()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(rescale) end

local state={Coins=0,DCoins=0,Reputation={score=0}}

-- Balances (Coins are shown by the existing CurrencyHUD) ---------------------------------------------
local balances=panel({AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-20,.5,46),Size=UDim2.fromOffset(196,48)},gui)
local balanceText=label('',{Size=UDim2.fromScale(1,1),TextSize=15},balances)
local function refreshBalances()
 local rep=math.floor((state.Reputation and state.Reputation.score or 0)+.5)
 balanceText.Text=string.format('%s DCoins  ·  Rep %s%d',fmt(state.DCoins or 0),rep>=0 and '+' or '',rep)
end
refreshBalances()

-- Notices -----------------------------------------------------------------------------------------
local notice=panel({AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,70),Size=UDim2.fromOffset(460,44),Visible=false},gui)
local noticeText=label('',{Size=UDim2.new(1,-20,1,0),Position=UDim2.fromOffset(10,0)},notice)
local noticeToken=0
local function showNotice(text,seconds)
 noticeToken+=1;local token=noticeToken
 noticeText.Text=text;notice.Visible=true
 task.delay(seconds or 4,function() if noticeToken==token then notice.Visible=false end end)
end

-- Camera focus while a request prompt is open (§12.8 step 3): a gentle zoom, always restored. -----------
local savedFov
local function focus(on)
 local cam=workspace.CurrentCamera;if not cam then return end
 if on then
  savedFov=savedFov or cam.FieldOfView
  TweenService:Create(cam,TweenInfo.new(.6,Enum.EasingStyle.Sine),{FieldOfView=math.max(45,savedFov-14)}):Play()
 elseif savedFov then
  TweenService:Create(cam,TweenInfo.new(.5,Enum.EasingStyle.Sine),{FieldOfView=savedFov}):Play()
  savedFov=nil
 end
end

-- NPC request flow --------------------------------------------------------------------------------
local current -- {id, name}
local promptGui,leadBanner,standPanel
local function closeRequestUi()
 if promptGui then promptGui:Destroy();promptGui=nil end
 if leadBanner then leadBanner:Destroy();leadBanner=nil end
 if standPanel then standPanel:Destroy();standPanel=nil end
 focus(false)
end
local function showPrompt(data)
 closeRequestUi()
 current={id=data.Id,name=data.Name}
 local model=data.Model
 local adornee=model and (model:FindFirstChild('Head') or model.PrimaryPart)
 local holder
 if adornee then
  promptGui=make('BillboardGui',{Name='NpcRequestPrompt',Adornee=adornee,Size=UDim2.fromOffset(250,104),StudsOffsetWorldSpace=Vector3.new(0,3.2,0),AlwaysOnTop=true,Active=true,ResetOnSpawn=false},playerGui)
  holder=panel({Size=UDim2.fromScale(1,1)},promptGui)
 else
  promptGui=panel({AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-140),Size=UDim2.fromOffset(250,104)},gui)
  holder=promptGui
 end
 label(data.Name..' asks for your support',{Size=UDim2.new(1,-16,0,44),Position=UDim2.fromOffset(8,4)},holder)
 button('Accept',{Size=UDim2.new(.5,-12,0,40),Position=UDim2.new(0,8,1,-48)},holder,function()
  remote:FireServer('RequestAnswer',data.Id,true)
 end)
 button('Decline',{Size=UDim2.new(.5,-12,0,40),Position=UDim2.new(.5,4,1,-48),BackgroundColor3=MUTED},holder,function()
  remote:FireServer('RequestAnswer',data.Id,false)
 end)
 focus(true)
end
local function showLeading(data)
 closeRequestUi()
 leadBanner=panel({AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-120),Size=UDim2.fromOffset(420,52)},gui)
 label('Follow '..data.Name..' to their stand',{Size=UDim2.new(1,-120,1,0),Position=UDim2.fromOffset(12,0),TextXAlignment=Enum.TextXAlignment.Left},leadBanner)
 button('Cancel',{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-8,.5,0),Size=UDim2.fromOffset(96,36),BackgroundColor3=MUTED},leadBanner,function()
  remote:FireServer('RequestLeave',data.Id)
 end)
end
local function showStand(data)
 closeRequestUi()
 local rows=math.min(#data.Offers,6)
 standPanel=panel({AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.55),Size=UDim2.fromOffset(340,120+rows*46)},gui)
 label('Support '..data.Name,{Size=UDim2.new(1,-20,0,30),Position=UDim2.fromOffset(10,8),TextSize=20,Font=Enum.Font.GothamBold},standPanel)
 label('Every donation earns DCoins.',{Size=UDim2.new(1,-20,0,20),Position=UDim2.fromOffset(10,38),TextSize=14,TextColor3=ACCENT},standPanel)
 local list=make('ScrollingFrame',{Position=UDim2.fromOffset(10,64),Size=UDim2.new(1,-20,0,rows*46),BackgroundTransparency=1,BorderSizePixel=0,
  CanvasSize=UDim2.fromOffset(0,#data.Offers*46),ScrollBarThickness=6},standPanel)
 make('UIListLayout',{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder},list)
 for i,offer in data.Offers do
  local affordable=(state.Coins or 0)>=offer.Amount
  local b=button(string.format('%s Coins      +%s DCoins',fmt(offer.Amount),fmt(offer.DCoins)),{Size=UDim2.new(1,-8,0,40),LayoutOrder=i,
   BackgroundColor3=affordable and BUTTON or MUTED},list,function()
   if (state.Coins or 0)<offer.Amount then showNotice('Not enough Coins for that amount.');return end
   remote:FireServer('RequestDonate',data.Id,i)
  end)
  b.AutoButtonColor=affordable
 end
 button('Leave',{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-10),Size=UDim2.fromOffset(140,36),BackgroundColor3=MUTED},standPanel,function()
  remote:FireServer('RequestLeave',data.Id)
 end)
end
local CLOSED_TEXT={
 NoAnswer='The request expired.',
 Ignored='%s stopped waiting for you.',
 NpcLeft='%s had to leave.',
 NpcLost='%s could not reach their stand.',
}

-- Stand editor (preset amounts only; no custom amounts in V1) -----------------------------------------
local editor,selected
local function closeEditor() if editor then editor:Destroy();editor=nil end end
local function openEditor(data)
 closeEditor()
 selected={}
 for _,a in data.offers or {} do selected[a]=true end
 editor=panel({AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,24,.5,0),Size=UDim2.fromOffset(330,430)},gui)
 label('Your stand',{Size=UDim2.new(1,-20,0,30),Position=UDim2.fromOffset(10,8),TextSize=20,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left},editor)
 local sign=make('TextBox',{Name='StandSignBox',Position=UDim2.fromOffset(10,44),Size=UDim2.new(1,-20,0,34),Text=data.text or '',PlaceholderText='Sign text (80 characters)',
  ClearTextOnFocus=false,BackgroundColor3=Color3.fromRGB(18,44,50),TextColor3=INK,Font=Enum.Font.Gotham,TextSize=15,BorderSizePixel=0},editor)
 make('UICorner',{CornerRadius=UDim.new(0,5)},sign)
 label('Amounts NPCs can donate',{Size=UDim2.new(1,-20,0,20),Position=UDim2.fromOffset(10,86),TextSize=14,TextColor3=ACCENT,TextXAlignment=Enum.TextXAlignment.Left},editor)
 local grid=make('ScrollingFrame',{Position=UDim2.fromOffset(10,110),Size=UDim2.new(1,-20,0,250),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=6,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new()},editor)
 make('UIGridLayout',{CellSize=UDim2.fromOffset(94,38),CellPadding=UDim2.fromOffset(6,6),SortOrder=Enum.SortOrder.LayoutOrder},grid)
 for i,amount in data.presets or config.Stand.Presets do
  local b
  b=button(fmt(amount),{LayoutOrder=i,BackgroundColor3=selected[amount] and ACCENT or MUTED},grid,function()
   selected[amount]=not selected[amount] or nil
   b.BackgroundColor3=selected[amount] and ACCENT or MUTED
  end)
 end
 button('Save',{Position=UDim2.new(0,10,1,-50),Size=UDim2.fromOffset(96,38)},editor,function()
  local list={}
  for _,a in data.presets or config.Stand.Presets do if selected[a] then table.insert(list,a) end end
  remote:FireServer('Edit',sign.Text,list)
 end)
 button('Release',{Position=UDim2.new(0,116,1,-50),Size=UDim2.fromOffset(96,38),BackgroundColor3=MUTED},editor,function()
  remote:FireServer('Release')
 end)
 button('Close',{Position=UDim2.new(0,222,1,-50),Size=UDim2.fromOffset(96,38),BackgroundColor3=MUTED},editor,closeEditor)
end

-- Offline earnings ----------------------------------------------------------------------------------
local function showOffline(data)
 local p=panel({AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.45),Size=UDim2.fromOffset(340,190)},gui)
 local h=math.floor(data.awaySeconds/3600);local m=math.floor(data.awaySeconds%3600/60)
 label('While you were away',{Size=UDim2.new(1,-20,0,30),Position=UDim2.fromOffset(10,10),TextSize=20,Font=Enum.Font.GothamBold},p)
 label('+'..fmt(data.amount)..' Coins',{Size=UDim2.new(1,-20,0,34),Position=UDim2.fromOffset(10,44),TextSize=26,Font=Enum.Font.GothamBold,TextColor3=ACCENT},p)
 label(string.format('Away %dh %dm · based on your average of %s Coins per hour',h,m,fmt(data.avgHourly)),{Size=UDim2.new(1,-20,0,40),Position=UDim2.fromOffset(10,82),TextSize=14},p)
 button('OK',{AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-12),Size=UDim2.fromOffset(120,36)},p,function() p:Destroy() end)
end

-- TAB leaderboard (player + NPCs, Donated / Raised) -----------------------------------------------------
local board=panel({AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-20,0,20),Size=UDim2.fromOffset(330,380),Visible=false},gui)
label('Leaderboard',{Size=UDim2.new(1,-20,0,28),Position=UDim2.fromOffset(10,6),TextSize=18,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left},board)
local boardRows=make('Frame',{Position=UDim2.fromOffset(10,40),Size=UDim2.new(1,-20,1,-50),BackgroundTransparency=1},board)
local function row(i,name,donated,raised,mine)
 local y=(i-1)*22
 local color=mine and ACCENT or INK
 local font=mine and Enum.Font.GothamBold or Enum.Font.Gotham
 label(name,{Position=UDim2.fromOffset(0,y),Size=UDim2.new(.5,0,0,22),TextSize=14,TextColor3=color,Font=font,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,TextWrapped=false},boardRows)
 label(donated,{Position=UDim2.new(.5,0,0,y),Size=UDim2.new(.25,0,0,22),TextSize=14,TextColor3=color,Font=font,TextXAlignment=Enum.TextXAlignment.Right},boardRows)
 label(raised,{Position=UDim2.new(.75,0,0,y),Size=UDim2.new(.25,0,0,22),TextSize=14,TextColor3=color,Font=font,TextXAlignment=Enum.TextXAlignment.Right},boardRows)
end
local function refreshBoard()
 boardRows:ClearAllChildren()
 row(1,'Name','Donated','Raised',false)
 local source=harbor:FindFirstChild('Leaderboard')
 if not source then return end
 local entries=source:GetChildren()
 table.sort(entries,function(a,b) return (a:GetAttribute('Rank') or 999)<(b:GetAttribute('Rank') or 999) end)
 local mineId='p:'..player.UserId;local shown=1;local mineShown=false
 for _,e in entries do
  if shown>=14 then break end
  shown+=1
  local mine=e.Name==mineId;mineShown=mineShown or mine
  row(shown,e:GetAttribute('DisplayName') or e.Name,fmt(e:GetAttribute('Donated') or 0),fmt(e:GetAttribute('Raised') or 0),mine)
 end
 local me=source:FindFirstChild(mineId)
 if me and not mineShown then
  row(shown+1,'You (#'..tostring(me:GetAttribute('Rank'))..')',fmt(me:GetAttribute('Donated') or 0),fmt(me:GetAttribute('Raised') or 0),true)
 end
end
local function setBoard(on)
 board.Visible=on
 if on then
  refreshBoard()
  task.spawn(function() while board.Visible do task.wait(1);if board.Visible then refreshBoard() end end end)
 end
end
UserInputService.InputBegan:Connect(function(input,processed)
 if not processed and input.KeyCode==Enum.KeyCode.Tab then setBoard(true) end
end)
UserInputService.InputEnded:Connect(function(input)
 if input.KeyCode==Enum.KeyCode.Tab then setBoard(false) end
end)
if UserInputService.TouchEnabled then
 button('Board',{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-20,0,410),Size=UDim2.fromOffset(80,36)},gui,function() setBoard(not board.Visible) end)
end

-- Server events -------------------------------------------------------------------------------------
remote.OnClientEvent:Connect(function(kind,data)
 if kind=='State' and type(data)=='table' then
  state=data;refreshBalances()
 elseif kind=='Notice' and type(data)=='string' then
  showNotice(data)
 elseif kind=='NpcRequest' then
  showPrompt(data)
 elseif kind=='NpcRequestUpdate' and current and data.Id==current.id then
  if data.Stage=='Leading' then focus(false);showLeading(data) end
 elseif kind=='NpcStand' and current and data.Id==current.id then
  state.Coins=data.Coins;showStand(data)
 elseif kind=='NpcDonated' then
  local text=string.format('You donated %s Coins to %s · +%s DCoins',fmt(data.Amount),data.Name,fmt(data.DCoins))
  if data.Returned>0 then text=text..string.format('  ·  %s gave back %s Coins!',data.Name,fmt(data.Returned)) end
  showNotice(text,6)
 elseif kind=='NpcRequestClosed' and current and data.Id==current.id then
  local name=current.name;current=nil
  closeRequestUi()
  local text=CLOSED_TEXT[data.Outcome]
  if text then showNotice(string.format(text,name)) end
 elseif kind=='Booth' and type(data)=='table' then
  if data.ownerId==player.UserId and data.open~=false then openEditor(data)
  elseif editor and data.ownerId~=player.UserId then closeEditor() end
 elseif kind=='Offline' and type(data)=='table' then
  showOffline(data)
 end
end)
