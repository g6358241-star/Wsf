--!strict
-- MapCleanup: убирает провода (FestoonCable + BrassFinialPost), флажки ThemePennant
-- и всё, что висит в воздухе (ничего не касается и под ним пусто).
-- Ничего не удаляется: объекты переносятся в ServerStorage.MapCleanup_Backup (restore() вернёт).
-- Command Bar:
--   local C = require(game.ReplicatedStorage.Shared.MapCleanup:Clone()) C.preview()
--   local C = require(game.ReplicatedStorage.Shared.MapCleanup:Clone()) C.run()
--   local C = require(game.ReplicatedStorage.Shared.MapCleanup:Clone()) C.restore()

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local CHS = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local M = {}

M.config = {
	maxGap = 1.5, -- сколько стадов пустоты под объектом считается "висит"
	maxFootprint = 600, -- большие платформы/острова не трогаем
	includeAirship = true,
	includeClouds = false,
}

local ROOTS = { "Map", "HarborEnvironment2026", "CloudHarbor" }
local WIRE_NAMES = { FestoonCable = true, BrassFinialPost = true, ThemePennant = true }
local SKIP_NAMES = {
	LowHorizonCloud = true, DistantShoal = true, TurquoiseLagoon = true,
	LagoonLighthouse = true, Ambience = true,
}

local function skipped(inst: Instance): boolean
	if SKIP_NAMES[inst.Name] then return true end
	if inst.Name:match("^HorizonIslet") then return true end
	if inst.Name == "TheWayfarerAirship" and not M.config.includeAirship then return true end
	return false
end

local function hasParts(inst: Instance): boolean
	return inst:IsA("BasePart") or inst:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function bounds(unit: Instance): (CFrame, Vector3)
	if unit:IsA("BasePart") then return unit.CFrame, unit.Size end
	return (unit :: Model):GetBoundingBox()
end

local function isFloating(unit: Instance): boolean
	local cf, size = bounds(unit)
	if size.X * size.Z > M.config.maxFootprint then return false end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { unit }
	for _, p in ipairs(Workspace:GetPartBoundsInBox(cf, size + Vector3.new(0.4, 0.4, 0.4), op)) do
		if p.Transparency < 0.95 and p.Name ~= "TurquoiseLagoon" and not WIRE_NAMES[p.Name] then
			return false -- к чему-то прикреплён / стоит
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { unit }
	local bottom = cf.Position - Vector3.new(0, size.Y / 2, 0)
	local hit = Workspace:Raycast(bottom + Vector3.new(0, 0.05, 0), Vector3.new(0, -M.config.maxGap, 0), rp)
	return hit == nil
end

local function collectUnits(container: Instance, out: { Instance })
	for _, ch in ipairs(container:GetChildren()) do
		if skipped(ch) then continue end
		if ch:IsA("Folder") or (ch:IsA("Model") and ch.Name:match("^Bridge_%d+_Jewelry$")) then
			collectUnits(ch, out)
		elseif (ch:IsA("Model") or ch:IsA("BasePart")) and hasParts(ch) then
			table.insert(out, ch)
		end
	end
end

function M.find(): { [Instance]: string }
	local found: { [Instance]: string } = {}
	for _, rootName in ipairs(ROOTS) do
		local root = Workspace:FindFirstChild(rootName)
		if not root then continue end
		for _, d in ipairs(root:GetDescendants()) do
			if WIRE_NAMES[d.Name] then found[d] = "wire/pennant" end
			if M.config.includeClouds and d.Name == "LowHorizonCloud" then found[d] = "cloud" end
		end
		local units = {}
		collectUnits(root, units)
		for _, u in ipairs(units) do
			if not found[u] and isFloating(u) then found[u] = "floating" end
		end
	end
	-- убрать дубли: если предок уже в списке, ребёнка не трогаем отдельно
	for inst in pairs(found) do
		local a = inst.Parent
		while a do
			if found[a] then found[inst] = nil break end
			a = a.Parent
		end
	end
	return found
end

function M.preview()
	local found = M.find()
	local groups: { [string]: number } = {}
	local list = {}
	for inst, reason in pairs(found) do
		local key = reason .. " | " .. inst.Name:gsub("%d+", "#") .. " | " .. (inst.Parent and inst.Parent:GetFullName():gsub("%d+", "#") or "?")
		groups[key] = (groups[key] or 0) + 1
		table.insert(list, inst)
	end
	print(("[MapCleanup] найдено %d объектов:"):format(#list))
	for k, n in pairs(groups) do print(("  %3d  %s"):format(n, k)) end
	Selection:Set(list)
	print("[MapCleanup] они выделены в Explorer. Если всё верно — запусти C.run()")
	return #list
end

function M.run()
	local found = M.find()
	local backup = ServerStorage:FindFirstChild("MapCleanup_Backup")
	if not backup then
		backup = Instance.new("Folder")
		backup.Name = "MapCleanup_Backup"
		backup.Parent = ServerStorage
	end
	local rec
	pcall(function() rec = CHS:TryBeginRecording("MapCleanup") end)
	local n = 0
	for inst in pairs(found) do
		local ref = Instance.new("ObjectValue")
		ref.Name = "__CleanupParent"
		ref.Value = inst.Parent
		ref.Parent = inst
		inst.Parent = backup
		n += 1
	end
	if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) else pcall(function() CHS:SetWaypoint("MapCleanup") end) end
	Selection:Set({})
	print(("[MapCleanup] убрано %d объектов в ServerStorage.MapCleanup_Backup. Ctrl+Z или C.restore() вернёт."):format(n))
	return n
end

function M.restore()
	local backup = ServerStorage:FindFirstChild("MapCleanup_Backup")
	if not backup then print("[MapCleanup] бэкапа нет") return 0 end
	local n = 0
	for _, inst in ipairs(backup:GetChildren()) do
		local ref = inst:FindFirstChild("__CleanupParent")
		if ref and ref:IsA("ObjectValue") and ref.Value then
			inst.Parent = ref.Value
			ref:Destroy()
			n += 1
		end
	end
	print(("[MapCleanup] возвращено %d объектов"):format(n))
	return n
end

return M
