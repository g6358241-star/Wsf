-- Behaviour only. Never creates/clones/destroys GUI or edits visual styling/layout.
local Players=game:GetService('Players');local RS=game:GetService('ReplicatedStorage')
local player=Players.LocalPlayer;local gui=player:WaitForChild('PlayerGui')
local remote=RS:WaitForChild('HarborGame'):WaitForChild('Action')
local config=require(RS:WaitForChild('HarborShared').Config)
local effects=require(script.Parent:WaitForChild('DonationEffects')).new(gui)
local toast=require(script.Parent:WaitForChild('DonationToast')).new(gui,config,effects)
script.Destroying:Connect(function()toast.destroy();effects.destroy()end)
local state={};local booth: any={};local bound=setmetatable({},{__mode='k'})
local function find(name) return gui:FindFirstChild(name,true) end
local function text(name) local o=find(name);return o and o:IsA('TextBox') and o.Text or nil end
local function update(o)
 if o:IsA('TextLabel') or o:IsA('TextButton') then
  local field=o:GetAttribute('CurrencyField') or ((o.Name=='Balance' or o.Name=='CurrencyBalance') and config.Currencies.Primary) or ((o.Name=='Coins' or o.Name=='DCoins') and o.Name)
  if field and type(state[field])=='number' then o.Text=tostring(state[field]) end
 elseif (o:IsA('ImageLabel') or o:IsA('ImageButton')) and o.Name=='CurrencyIcon' then local icon=config.Currencies[config.Currencies.Primary].Icon;o.Image=icon;o.Visible=icon~='' end
end
-- Stand offers: buttons carrying a PresetAmount attribute toggle that amount (Selected attribute). Until the
-- chosen UI concept adds an editor, saving keeps the stand's current offers. No custom amounts in V1.
local function selectedOffers()
 local chosen,any={},false
 for _,o in gui:GetDescendants() do
  local amount=o:GetAttribute('PresetAmount')
  if type(amount)=='number' then any=true;if o:GetAttribute('Selected') then table.insert(chosen,amount) end end
 end
 if any then return chosen end
 return booth.offers or {}
end
local function bind(o)
 update(o)
 if not o:IsA('GuiButton') or bound[o] then return end
 local action=o:GetAttribute('GameplayAction')
 if not action then
  -- Player-to-player donation buttons are intentionally not bound (removed from V1).
  local names={ReleaseBooth='Release',SaveBooth='Edit',ClaimBooth='Claim'};action=names[o.Name]
 end
 if type(o:GetAttribute('PresetAmount'))=='number' then action='TogglePreset' end
 if not action then return end
 bound[o]=true
 o.Activated:Connect(function()
  if action=='TogglePreset' then o:SetAttribute('Selected',not o:GetAttribute('Selected'))
  elseif action=='Edit' then remote:FireServer('Edit',text('BoothText') or '',selectedOffers())
  elseif action=='Claim' then remote:FireServer('Claim',o:GetAttribute('BoothId') or booth.id)
  elseif action=='Release' or action=='MyBooth' or action=='Daily' or action=='Boards' then remote:FireServer(action)
  elseif action=='Shop' or action=='Equip' or action=='Quest' then remote:FireServer(action,o:GetAttribute('ItemKey')) end
 end)
end
for _,o in gui:GetDescendants() do bind(o) end
gui.DescendantAdded:Connect(bind)
local booths=workspace:WaitForChild('CloudHarbor'):WaitForChild('Booths')
for _,o in booths:GetDescendants() do bind(o) end;booths.DescendantAdded:Connect(bind)
remote.OnClientEvent:Connect(function(kind,data)
 if kind=='State' then state=data;for _,o in gui:GetDescendants() do update(o) end
 elseif kind=='Booth' then
  booth=data
  local box=find('BoothText');if box and box:IsA('TextBox') and data.ownerId==player.UserId then box.Text=data.text or '' end
  local panel=find('BoothPanel');if panel and panel:IsA('GuiObject') and data.open~=false then panel.Visible=true end
 elseif kind=='Notice' then local label=find('NoticeText');if label and label:IsA('TextLabel') then label.Text=tostring(data) end
 elseif kind=='DonationEffect' then effects.booth(data)
 elseif kind=='Donation' then toast.enqueue(data)
 end
end)
remote:FireServer('Sync')
