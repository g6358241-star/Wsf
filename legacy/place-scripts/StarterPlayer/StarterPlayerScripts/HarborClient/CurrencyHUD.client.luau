-- Requested right-side currency counter only; existing sidebar/panels are untouched.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local player=Players.LocalPlayer
local playerGui=player:WaitForChild('PlayerGui')
local config=require(RS:WaitForChild('HarborShared'):WaitForChild('Config'))
if playerGui:FindFirstChild('HarborCurrencyHUD') then return end
local connections={}
local function create(class,name,props,parent)
 local object=Instance.new(class);object.Name=name
 for key,value in props do object[key]=value end
 object.Parent=parent;return object
end
local gui=create('ScreenGui','HarborCurrencyHUD',{ResetOnSpawn=false,DisplayOrder=30,IgnoreGuiInset=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
local wallet=create('Frame','Wallet',{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-20,.5,0),Size=UDim2.fromOffset(196,64),BackgroundColor3=Color3.fromRGB(37,23,67),BackgroundTransparency=1,BorderSizePixel=0},gui)
create('ImageLabel','CurrencyIcon',{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,10,.5,0),Size=UDim2.fromOffset(50,50),BackgroundTransparency=1,Image=config.TestCurrency.Icon,ScaleType=Enum.ScaleType.Fit},wallet)
local balance=create('TextLabel','Balance',{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,70,.5,0),Size=UDim2.new(1,-82,0,42),BackgroundTransparency=1,Text='…',TextColor3=Color3.fromRGB(250,247,255),Font=Enum.Font.GothamBold,TextSize=26,TextScaled=true,TextXAlignment=Enum.TextXAlignment.Right},wallet)
balance:SetAttribute('CurrencyField','DCoins')
create('UITextSizeConstraint','TextBounds',{MinTextSize=14,MaxTextSize=26},balance)
local stopped=false
local function cleanup()
 if stopped then return end;stopped=true
 for _,connection in connections do connection:Disconnect() end;table.clear(connections)
end
table.insert(connections,gui.Destroying:Connect(cleanup))
table.insert(connections,script.Destroying:Connect(function()cleanup();if gui.Parent then gui:Destroy() end end))
local stats=player:WaitForChild('leaderstats',45)
local coins=stats and stats:WaitForChild('DCoins',15)
if coins and not stopped then
 local function refresh()balance.Text=tostring(coins.Value) end
 refresh();table.insert(connections,coins:GetPropertyChangedSignal('Value'):Connect(refresh))
end
