-- Single entry point. All economic mutations and purchase decisions are server-owned.
local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local folder=Instance.new("Folder");folder.Name="HarborGame";folder.Parent=RS
local remote=Instance.new("RemoteEvent");remote.Name="Action";remote.Parent=folder
local Profiles=require(script.Parent.Profiles)
local Economy=require(script.Parent.Economy)
local Booths=require(script.Parent.Booths)
local Donations=require(script.Parent.Donations)
local Boards=require(script.Parent.Boards)
local Social=require(script.Parent.Social)
Profiles.Changed.Event:Connect(function(player)
    if player.Parent then remote:FireClient(player,"State",Profiles.public(player)) end
end)
local function boothState(player,open)
    local id=Booths.owned[player.UserId]
    local data=id and Booths.public(id) or {id="",ownerId=0,text="",offers={},presets=require(RS.HarborShared.Config).Stand.Presets}
    data.open=open
    remote:FireClient(player,"Booth",data)
end
local limits={}
remote.OnServerEvent:Connect(function(player,action,a,b,c,d)
    if type(action)~="string" or #action>32 then return end
    local now=os.clock()
    local rate=limits[player] or {Time=now,Tokens=8};limits[player]=rate
    rate.Tokens=math.min(8,rate.Tokens+(now-rate.Time)*2);rate.Time=now
    if rate.Tokens<1 then return end;rate.Tokens-=1
    if action=="Sync" then remote:FireClient(player,"State",Profiles.public(player));boothState(player,false);return end
    if not Profiles.get(player) then remote:FireClient(player,"Notice","Your profile is loading.");return end
    if action=="MyBooth" then boothState(player,true);return end
    if action=="Boards" then remote:FireClient(player,"Boards",Boards.Cache);return end
    local key=type(a)=="string" and #a<48 and a or nil
    local ok,message
    -- V1 has no player-to-player donations or Robux transfers (APPROVED): "Donate"/"Transfer" are not accepted.
    if ((action=="Product" or action=="Pass") and key) or action=="RefreshPass" then
        ok=false;message="Real payments are disabled."
    elseif action=="Daily" or ((action=="Shop" or action=="Equip" or action=="Quest") and key) then
        ok,message=Economy.action(player,action,key)
    elseif (action=="Announce" or action=="Emote") then
        ok,message=Social.action(player,action,a,remote)
    elseif action=="Release" then Booths.release(player);ok=true;message="Booth released."
    elseif action=="Edit" then ok,message=Booths.edit(player,a,b) -- a = sign text, b = list of preset amounts
    elseif action=="Claim" and key then ok,message=Booths.claim(player,key)
    else return end
    if player.Parent and message and message~="" then remote:FireClient(player,"Notice",message) end
    if ok and player.Parent and (action=="Release" or action=="Edit" or action=="Claim") then boothState(player,true) end
end)
Players.PlayerRemoving:Connect(function(player)limits[player]=nil end)
Economy.init(remote)
Booths.init(remote)
Donations.init(remote)
Boards.init()
Social.init()
Profiles.init()
print("[Harbor] Server ready")
