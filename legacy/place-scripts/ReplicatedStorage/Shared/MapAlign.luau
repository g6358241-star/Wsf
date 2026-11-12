-- MapAlign: доворачивает всю гавань (острова, мосты, декор, свет, спавн) вокруг центра
-- CompassPlaza так, чтобы острова встали ровно по осям X/Z, и выравнивает высоту палуб.
-- Command Bar:
--   local A = require(game.ReplicatedStorage.Shared.MapAlign:Clone()) A.preview()
--   local A = require(game.ReplicatedStorage.Shared.MapAlign:Clone()) A.run()
-- Отмена: Ctrl+Z.

local Workspace = game:GetService("Workspace")
local CHS = game:GetService("ChangeHistoryService")

local M = {}
local HALF_PI = math.pi / 2

local function deckOf(inst: Instance): BasePart?
	local best, area = nil, -1
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			local a = d.Size.X * d.Size.Z
			if a > area then best, area = d, a end
		end
	end
	return best
end

local function topY(p: BasePart): number
	local s, cf = p.Size, p.CFrame
	local h = math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
	return cf.Position.Y + h
end

local function layout()
	local ch = Workspace:FindFirstChild("CloudHarbor")
	assert(ch, "Нет Workspace.CloudHarbor")
	local islands = ch:FindFirstChild("Islands")
	assert(islands, "Нет CloudHarbor.Islands")
	local plaza = islands:FindFirstChild("CompassPlaza")
	assert(plaza and plaza:IsA("Model"), "Нет CompassPlaza")
	local center = plaza:GetBoundingBox().Position
	local list = {}
	for _, m in ipairs(islands:GetChildren()) do
		if m:IsA("Model") and m ~= plaza and not m.Name:match("^Terrace") then
			local p = m:GetBoundingBox().Position
			local dx, dz = p.X - center.X, p.Z - center.Z
			local a = math.atan2(dx, dz)
			local off = a - math.round(a / HALF_PI) * HALF_PI
			table.insert(list, { model = m, angle = a, off = off, dist = math.sqrt(dx * dx + dz * dz) })
		end
	end
	local sum = 0
	for _, it in ipairs(list) do sum += it.off end
	local theta = if #list > 0 then -sum / #list else 0
	return ch, islands, plaza, center, list, theta
end

local function targets(): { PVInstance }
	local out: { PVInstance } = {}
	local function addFolder(f: Instance)
		for _, c in ipairs(f:GetChildren()) do
			if c:IsA("Folder") then addFolder(c)
			elseif c:IsA("PVInstance") then table.insert(out, c) end
		end
	end
	for _, name in ipairs({ "CloudHarbor", "HarborEnvironment2026" }) do
		local t = Workspace:FindFirstChild(name)
		if t then if t:IsA("Folder") then addFolder(t) elseif t:IsA("PVInstance") then table.insert(out, t) end end
	end
	local map = Workspace:FindFirstChild("Map")
	if map then
		for _, c in ipairs(map:GetChildren()) do
			if c.Name ~= "Environment" and c.Name ~= "Ambience" then
				if c:IsA("Folder") then addFolder(c) elseif c:IsA("PVInstance") then table.insert(out, c) end
			end
		end
	end
	return out
end

function M.preview()
	local _, islands, plaza, center, list, theta = layout()
	print(("[MapAlign] центр (%.1f, %.1f), поворот на %.2f°"):format(center.X, center.Z, math.deg(theta)))
	local plazaTop = topY(deckOf(plaza) :: BasePart)
	for _, it in ipairs(list) do
		local d = deckOf(it.model)
		print(("  %-14s угол %.1f° (косо %.1f°) дист %.1f  высота %.2f (центр %.2f)"):format(
			it.model.Name, math.deg(it.angle), math.deg(it.off), it.dist, d and topY(d) or -1, plazaTop))
	end
	return theta
end

function M.run()
	local _, islands, plaza, center, list, theta = layout()
	local rec
	pcall(function() rec = CHS:TryBeginRecording("MapAlign") end)
	local moved = 0
	if math.abs(theta) > math.rad(0.05) then
		local pivot = Vector3.new(center.X, 0, center.Z)
		local T = CFrame.new(pivot) * CFrame.Angles(0, theta, 0) * CFrame.new(-pivot)
		for _, pv in ipairs(targets()) do
			pv:PivotTo(T * pv:GetPivot())
			moved += 1
		end
	end
	-- выравнивание высоты палуб островов по центральной площади (только малые расхождения)
	local plazaTop = topY(deckOf(plaza) :: BasePart)
	local leveled = 0
	for _, m in ipairs(islands:GetChildren()) do
		if m:IsA("Model") and m ~= plaza then
			local d = deckOf(m)
			if d then
				local dy = plazaTop - topY(d)
				if math.abs(dy) > 0.02 and math.abs(dy) < 6 then
					m:PivotTo(CFrame.new(0, dy, 0) * m:GetPivot())
					leveled += 1
				end
			end
		end
	end
	if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) else pcall(function() CHS:SetWaypoint("MapAlign") end) end
	print(("[MapAlign] повёрнуто на %.2f° (%d объектов), выровнено по высоте: %d"):format(math.deg(theta), moved, leveled))
	M.preview()
end

return M
