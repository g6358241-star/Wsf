-- Server-authoritative ownership. Existing map geometry is never rebuilt.
-- A booth is owned by at most one player OR one NPC. Offers are preset amounts only (no custom entry in V1).
local Players = game:GetService('Players')
local TextService = game:GetService('TextService')
local Config = require(game:GetService('ReplicatedStorage'):WaitForChild('HarborShared').Config)
local Booths = {entries={}, owned={}, busy={}, lastPrompt={}, Ready=false, Changed=Instance.new('BindableEvent')}
local Remote
local Profiles=require(script.Parent.Profiles)
local Economy=require(script.Parent.Economy)
local presetSet={};for _,amount in Config.Stand.Presets do presetSet[amount]=true end
local function near(player, entry)
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 return root and (root.Position-entry.anchor.Position).Magnitude <= 18
end
local function offersText(offers)
 if #offers==0 then return 'No offers listed' end
 local parts={};for i,amount in offers do if i>6 then table.insert(parts,'…');break end;table.insert(parts,tostring(amount)) end
 return table.concat(parts,' · ')..' Coins'
end
local function paint(entry)
 local owner,npc=entry.owner,entry.npc
 local ownerName=owner and owner.DisplayName or npc and npc.name or ''
 entry.model:SetAttribute('OwnerUserId', owner and owner.UserId or 0)
 entry.model:SetAttribute('OwnerNpcId', npc and npc.id or '')
 entry.model:SetAttribute('OwnerName', ownerName)
 entry.model:SetAttribute('BoothText', entry.text or '')
 entry.model:SetAttribute('Offers', table.concat(entry.offers, ','))
 entry.prompt.Enabled=npc==nil -- NPC stands are interacted with through their own flow, not the claim prompt
 entry.prompt.ActionText=owner and 'Open booth' or 'Claim booth'
 entry.prompt.ObjectText=owner and ('@'..owner.Name) or 'Available booth'
 if entry.label then
  if owner or npc then entry.label.Text=ownerName..'\n'..(entry.text or 'Welcome to my booth!')..'\n'..offersText(entry.offers)
  else entry.label.Text='YOUR SPACE\nHold E / tap to claim' end
 end
 for _,label in entry.targets do label.Text=owner and ('@'..owner.Name) or npc and npc.name or 'AVAILABLE' end
 Booths.Changed:Fire(entry.model.Name)
end
local function reset(entry)
 entry.owner=nil;entry.npc=nil;entry.text=nil;entry.offers={};paint(entry)
end
function Booths.release(player)
 local id=Booths.owned[player.UserId];local entry=id and Booths.entries[id]
 Booths.owned[player.UserId]=nil
 if entry and entry.owner==player then reset(entry) end
end
function Booths.claim(player,id)
 if not Profiles.get(player) then return false,'Your profile is loading.' end
 local entry=Booths.entries[id]
 if not entry or not near(player,entry) then return false,'Move closer to this booth.' end
 if entry.npc or (entry.owner and entry.owner~=player) then return false,'This booth is occupied.' end
 if Booths.owned[player.UserId] and Booths.owned[player.UserId]~=id then return false,'Release your current booth first.' end
 local first=entry.owner~=player
 if first and not Economy.claimed(player) then return false,'Profile busy. Try claiming again.' end
 if first then
  local saved=Profiles.get(player).Stand.Offers
  entry.offers=#saved>0 and table.clone(saved) or table.clone(Config.Stand.DefaultOffers)
 end
 entry.owner=player;entry.text=entry.text or 'Welcome to my booth!'
 Booths.owned[player.UserId]=id;paint(entry)
 return true,'Booth claimed.'
end
-- Validates a client-sent offer list: every value must be a preset, duplicates removed, sorted.
-- No arbitrary cap: the preset list itself is the only bound (§12.12).
function Booths.validateOffers(offers)
 if type(offers)~='table' then return nil end
 local count=0;for _ in offers do count+=1 end
 if count~=#offers or count>#Config.Stand.Presets*2 then return nil end
 local clean,seen={},{}
 for _,amount in ipairs(offers) do
  if type(amount)~='number' or not presetSet[amount] then return nil end
  if not seen[amount] then seen[amount]=true;table.insert(clean,amount) end
 end
 table.sort(clean)
 return clean
end
function Booths.edit(player,text,offers)
 local id=Booths.owned[player.UserId];local entry=id and Booths.entries[id]
 if not entry or entry.owner~=player then return false,'Claim a booth first.' end
 if Booths.busy[player] then return false,'Please wait.' end
 if type(text)~='string' or #text>240 or not utf8.len(text) or utf8.len(text)>80 then return false,'Use up to 80 characters.' end
 local clean=Booths.validateOffers(offers)
 if not clean then return false,'Choose amounts from the preset list.' end
 Booths.busy[player]=true
 local ok,filtered=pcall(function() return TextService:FilterStringAsync(text,player.UserId):GetNonChatStringForBroadcastAsync() end)
 Booths.busy[player]=nil
 if not ok then return false,'Text filtering is unavailable. Please try again.' end
 if entry.owner~=player or not player.Parent then return false,'Booth is no longer yours.' end
 -- NPCs read offers when they make their decision, so in-progress transactions are never changed retroactively.
 entry.text=filtered;entry.offers=clean;paint(entry)
 Profiles.setStandOffers(player,clean)
 return true,'Booth updated.'
end
-- NPC ownership (§12.5). The NPC director owns the decision; this only enforces the booth rules.
function Booths.freeCount()
 local n=0;for _,e in Booths.entries do if not e.owner and not e.npc then n+=1 end end
 return n
end
-- `npc` = {id, name}; `pick(n)` returns 1..n from the director's seeded RNG.
function Booths.npcClaim(npc,offers,text,pick)
 if Booths.freeCount()<=Config.Stand.ReservedForPlayers then return nil end
 local free={};for id,e in Booths.entries do if not e.owner and not e.npc then table.insert(free,id) end end
 if #free==0 then return nil end
 table.sort(free)
 local id=free[pick(#free)]
 local entry=Booths.entries[id]
 entry.npc=npc;entry.text=text;entry.offers=table.clone(offers);paint(entry)
 return id
end
function Booths.npcRelease(npcId)
 for _,entry in Booths.entries do if entry.npc and entry.npc.id==npcId then reset(entry) end end
end
-- Read-only snapshots for NpcBrain.StandView. ownerId is "p:<userId>" for players or the NPC id.
function Booths.view(id)
 local e=Booths.entries[id]
 if not e then return nil end
 local ownerId=e.owner and ('p:'..e.owner.UserId) or e.npc and e.npc.id or nil
 return {id=id,ownerId=ownerId,offers=table.clone(e.offers),appeal=e.model:GetAttribute('Appeal') or .5,luck=0}
end
function Booths.views()
 local list={}
 for id in Booths.entries do local v=Booths.view(id);if v.ownerId then table.insert(list,v) end end
 table.sort(list,function(a,b) return a.id<b.id end)
 return list
end
function Booths.public(id)
 local e=Booths.entries[id]
 if not e then return nil end
 return {id=id,ownerId=e.owner and e.owner.UserId or 0,owner=e.owner and e.owner.DisplayName or e.npc and e.npc.name or '',
  npc=e.npc~=nil,text=e.text or '',offers=table.clone(e.offers),presets=Config.Stand.Presets}
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
  local entry: any={model=model,anchor=anchor,prompt=prompt,label=label,offers={},targets=targets};Booths.entries[model.Name]=entry;paint(entry)
  prompt.Triggered:Connect(function(player)
   local now=os.clock();if now-(Booths.lastPrompt[player] or -100)<.75 then return end;Booths.lastPrompt[player]=now
   if not near(player,entry) or entry.npc then return end
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
 Booths.Ready=true
 print('[Harbor] Booths ready: '..count)
end
return Booths
