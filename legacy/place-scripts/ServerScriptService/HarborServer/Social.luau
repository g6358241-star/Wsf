local Players=game:GetService("Players")
local TextService=game:GetService("TextService")
local Social={}
local cooldown={};local globalLast=-100
function Social.action(player,action,value,remote)
    local now=os.clock()
    local state=cooldown[player] or {Announce=-100,Emote=-100};cooldown[player]=state
    if action=="Announce" then
        if type(value)~="string" or #value>400 then return false,"Use up to 100 characters." end
        local length=utf8.len(value)
        if not length or length<1 or length>100 or not value:find("%S") then return false,"Use 1 to 100 characters." end
        if now-state.Announce<60 or now-globalLast<10 then return false,"Harbor Radio is cooling down. Try later." end
        state.Announce=now;globalLast=now
        local ok,filtered=pcall(function()
            return TextService:FilterStringAsync(value,player.UserId):GetNonChatStringForBroadcastAsync()
        end)
        if not ok then return false,"Text filtering is unavailable. Your message was not sent." end
        if not player.Parent then return false,"Player left." end
        remote:FireAllClients("Announcement",{Name=player.DisplayName,Text=filtered})
        return true,"Announcement sent."
    elseif action=="Emote" then
        if value~="Wave" and value~="Cheer" then return false,"Unknown emote." end
        if now-state.Emote<5 then return false,"Wait before another emote." end
        local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health<=0 then return false,"Spawn your character first." end
        state.Emote=now;remote:FireClient(player,"Emote",string.lower(value))
        return true,""
    end
    return false,"Unknown social action."
end
function Social.init()
    Players.PlayerRemoving:Connect(function(p)cooldown[p]=nil end)
end
return Social
