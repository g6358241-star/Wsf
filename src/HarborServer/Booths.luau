-- Server-authoritative ownership. Existing map geometry is never rebuilt.
local Players = game:GetService('Players')
local TextService = game:GetService('TextService')
local Booths = {entries={}, owned={}, busy={}, lastPrompt={}}
local Remote
local Profiles=require(script.Parent.Profiles)
local Economy=require(script.Parent.Economy)
local function near(player, entry)
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 return root and (root.Position-entry.anchor.Position).Magnitude <= 18
end
local function paint(entry)
 local owner=entry.owner
 entry.model:SetAttribute('OwnerUserId', owner and owner.UserId or 0)
 entry.model:SetAttribute('OwnerName', owner and owner.DisplayName or '')
 entry.model:SetAttribute('BoothText', entry.text or '')
 entry.model:SetAttribute('TipAmount',entry.amount or 5)
 entry.prompt.ActionText=owner and 'Open booth' or 'Claim booth'
 entry.prompt.ObjectText=owner and ('@'..owner.Name) or 'Available booth'
 if entry.label then entry.label.Text=owner and (owner.DisplayName..'\n'..(entry.text or 'Welcome to my booth!')..'\n'..tostring(entry.amount or 5)..' D — test donation' ) or 'YOUR SPACE\nHold E / tap to claim' end
 for _,label in entry.targets do label.Text=owner and ('@'..owner.Name) or 'AVAILABLE' end
end
function Booths.release(player)
 local id=Booths.owned[player.UserId];local entry=id and Booths.entries[id]
 Booths.owned[player.UserId]=nil
 if entry and entry.owner==player then entry.owner=nil;entry.text=nil;entry.amount=5;paint(entry) end
end
function Booths.claim(player,id)
 if not Profiles.get(player) then return false,'Your profile is loading.' end
 local entry=Booths.entries[id]
 if not entry or not near(player,entry) then return false,'Move closer to this booth.' end
 if entry.owner and entry.owner~=player then return false,'This booth is occupied.' end
 if Booths.owned[player.UserId] and Booths.owned[player.UserId]~=id then return false,'Release your current booth first.' end
 local first=entry.owner~=player
 if first and not Economy.claimed(player) then return false,'Profile busy. Try claiming again.' end
 entry.owner=player;entry.text=entry.text or 'Welcome to my booth!';entry.amount=entry.amount or 5
 Booths.owned[player.UserId]=id;paint(entry)
 return true,'Booth claimed.'
end
function Booths.edit(player,text,amount)
 local id=Booths.owned[player.UserId];local entry=id and Booths.entries[id]
 if not entry or entry.owner~=player then return false,'Claim a booth first.' end
 if Booths.busy[player] then return false,'Please wait.' end
 if type(text)~='string' or #text>240 or not utf8.len(text) or utf8.len(text)>80 then return false,'Use up to 80 characters.' end
 if type(amount)~='number' or amount~=amount or amount%1~=0 or amount<5 or amount>10000 then return false,'Choose a whole amount from 5 to 10,000.' end
 Booths.busy[player]=true
 local ok,filtered=pcall(function() return TextService:FilterStringAsync(text,player.UserId):GetNonChatStringForBroadcastAsync() end)
 Booths.busy[player]=nil
 if not ok then return false,'Text filtering is unavailable. Please try again.' end
 if entry.owner~=player or not player.Parent then return false,'Booth is no longer yours.' end
 entry.text=filtered;entry.amount=amount;paint(entry)
 return true,'Booth updated.'
end
function Booths.public(id)
 local e=Booths.entries[id]
 if not e then return nil end
 return {id=id,ownerId=e.owner and e.owner.UserId or 0,owner=e.owner and e.owner.DisplayName or '',text=e.text or '',amount=e.amount or 5}
end
function Booths.init(remote)
 Remote=remote
 local map=workspace:FindFirstChild('CloudHarbor');local folder=map and map:FindFirstChild('Booths')
 assert(folder,'Existing CloudHarbor/Booths folder is missing; map preserved, no replacement created.')
 for _,model in folder:GetChildren() do
  if not model:IsA('Model') then continue end
  local anchor=model:FindFirstChild('CounterTop',true) or model:FindFirstChildWhichIsA('BasePart',true)
  if not anchor or not anchor:IsA('BasePart') then continue end
  local prompt=model:FindFirstChildWhichIsA('ProximityPrompt',true)
  if not prompt then prompt=Instance.new('ProximityPrompt');prompt.Name='ClaimPrompt';prompt.Parent=anchor end
  prompt.Enabled=true;prompt.HoldDuration=.35;prompt.MaxActivationDistance=12;prompt.RequiresLineOfSight=false
  local board=model:FindFirstChild('SignBoard',true)
  local label=model:FindFirstChild('BoothStatus',true) or (board and board:FindFirstChildWhichIsA('TextLabel',true))
  local targets={}
  for _,obj in model:GetDescendants() do
   if obj:IsA('TextLabel') and obj~=label and (obj.Name=='Text' or obj.Name=='Label') then
    local lower=string.lower(obj.Text)
    if lower:find('unclaimed') or lower:find('claim') or lower:find('your text') then table.insert(targets,obj) end
   end
  end
  local entry={model=model,anchor=anchor,prompt=prompt,label=label,amount=5,targets=targets};Booths.entries[model.Name]=entry;paint(entry)
  prompt.Triggered:Connect(function(player)
   local now=os.clock();if now-(Booths.lastPrompt[player] or -100)<.75 then return end;Booths.lastPrompt[player]=now
   if not near(player,entry) then return end
   if not entry.owner then local ok,msg=Booths.claim(player,model.Name);Remote:FireClient(player,'Notice',msg);if not ok then return end end
   Remote:FireClient(player,'Booth',Booths.public(model.Name))
  end)
 end
 Players.PlayerRemoving:Connect(function(player) Booths.release(player);Booths.busy[player]=nil;Booths.lastPrompt[player]=nil end)
 Profiles.Changed.Event:Connect(function(player)
  local id=Booths.owned[player.UserId];local entry=id and Booths.entries[id]
  if entry then paint(entry) end
 end)
 local count=0;for _ in Booths.entries do count+=1 end
 print('[Harbor] Booths ready: '..count)
end
return Booths
