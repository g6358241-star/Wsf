-- Behaviour only. Never creates/clones/destroys GUI or edits visual styling/layout.
local Players=game:GetService('Players');local RS=game:GetService('ReplicatedStorage');local Http=game:GetService('HttpService')
local player=Players.LocalPlayer;local gui=player:WaitForChild('PlayerGui')
local remote=RS:WaitForChild('HarborGame'):WaitForChild('Action')
local config=require(RS:WaitForChild('HarborShared').Config)
local effects=require(script.Parent:WaitForChild('DonationEffects')).new(gui)
local toast=require(script.Parent:WaitForChild('DonationToast')).new(gui,config,effects)
script.Destroying:Connect(function()toast.destroy();effects.destroy()end)
local state={};local booth={};local pending;local bound=setmetatable({},{__mode='k'})
local function find(name) return gui:FindFirstChild(name,true) end
local function text(name) local o=find(name);return o and o:IsA('TextBox') and o.Text or nil end
local function update(o)
 if o:IsA('TextLabel') or o:IsA('TextButton') then
  local field=o:GetAttribute('CurrencyField') or ((o.Name=='Balance' or o.Name=='CurrencyBalance' or o.Name=='DCoins') and 'DCoins')
  if field and type(state[field])=='number' then o.Text=tostring(state[field]) end
 elseif (o:IsA('ImageLabel') or o:IsA('ImageButton')) and o.Name=='CurrencyIcon' and config.TestCurrency.Icon~='' then o.Image=config.TestCurrency.Icon end
end
local function sendDonation(data)
 remote:FireServer('Donate',data.id,data.amount,data.requestId,data.owner)
end
local function bind(o)
 update(o)
 if not o:IsA('GuiButton') or bound[o] then return end
 local action=o:GetAttribute('GameplayAction')
 if not action then
  local names={Donate='Donate',DonateButton='Donate',ReleaseBooth='Release',SaveBooth='Edit',ClaimBooth='Claim',ConfirmDonation='Confirm',CancelDonation='Cancel'};action=names[o.Name]
 end
 if not action then return end
 bound[o]=true
 o.Activated:Connect(function()
  if action=='Donate' then
   local model=o:FindFirstAncestorWhichIsA('Model')
   local id=o:GetAttribute('BoothId') or (model and model.Name) or booth.id
   local owner=o:GetAttribute('OwnerUserId') or (model and model:GetAttribute('OwnerUserId')) or booth.ownerId
   local amount=o:GetAttribute('DonationAmount') or tonumber(text('DonationAmount')) or booth.amount
   local data={id=id,owner=owner,amount=amount,requestId=Http:GenerateGUID(false)}
   local confirmation=find('DonationConfirmation')
   if confirmation and confirmation:IsA('GuiObject') then pending=data;confirmation.Visible=true else sendDonation(data) end
  elseif action=='Confirm' then if pending then sendDonation(pending);pending=nil end;local panel=find('DonationConfirmation');if panel and panel:IsA('GuiObject') then panel.Visible=false end
  elseif action=='Cancel' then pending=nil;local panel=find('DonationConfirmation');if panel and panel:IsA('GuiObject') then panel.Visible=false end
  elseif action=='Edit' then remote:FireServer('Edit',text('BoothText') or '',tonumber(text('DonationAmount')) or booth.amount or 5)
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
