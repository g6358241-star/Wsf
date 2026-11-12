local DSS=game:GetService("DataStoreService")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Config=require(game:GetService("ReplicatedStorage"):WaitForChild("HarborShared").Config)
local Profiles=require(script.Parent.Profiles)
local Boards={Cache={Ready=false,Mode="Loading",UpdatedAt=0,Rows={}}}
local fields={"Donated","Received","PlaySeconds"}
local stores={}
local localOnly=RunService:IsStudio()
local function localRows(field)
    local rows={}
    for p in Profiles.Active do
        local d=Profiles.get(p)
        if d then table.insert(rows,{UserId=p.UserId,Name=p.DisplayName,Value=d[field]}) end
    end
    table.sort(rows,function(a,b) if a.Value==b.Value then return a.UserId<b.UserId end;return a.Value>b.Value end)
    while #rows>10 do table.remove(rows) end
    return rows
end
local function refresh()
    local rows={};local available=true
    for _,field in fields do
        if localOnly then rows[field]=localRows(field) else
            for player,record in Profiles.Active do
                local stats=record.SavedStats
                if stats then
                    local ok=pcall(function()
                        stores[field]:UpdateAsync(tostring(player.UserId),function(old)
                            return math.max(type(old)=="number" and old or 0,stats[field])
                        end)
                    end)
                    if not ok then available=false end
                    task.wait(.2)
                end
            end
            local ok,page=pcall(function()return stores[field]:GetSortedAsync(false,10)end)
            if ok then
                rows[field]={}
                for _,item in page:GetCurrentPage() do
                    local id=tonumber(item.key)
                    if id then
                        local player=Players:GetPlayerByUserId(id)
                        table.insert(rows[field],{UserId=id,Name=player and player.DisplayName or ("User "..id),Value=item.value})
                    end
                end
            else available=false;rows[field]=Boards.Cache.Rows[field] or {} end
        end
    end
    Boards.Cache={Ready=true,Mode=localOnly and "Studio server preview" or (available and "Global" or "Global / last available data"),UpdatedAt=os.time(),Rows=rows}
end
function Boards.init()
    if not localOnly then
        for _,field in fields do stores[field]=DSS:GetOrderedDataStore(Config.DataStore.."_Top_"..field) end
    end
    task.spawn(function()
        task.wait(3)
        while true do refresh();task.wait(Config.BoardsSeconds) end
    end)
    print("[Harbor] Leaderboards ready; refresh "..Config.BoardsSeconds.."s")
end
return Boards
