-- WaterLevel: levels the turquoise lagoon in Workspace.Map.Environment.
-- The whole ocean stage (lagoon, shoals, horizon islets, lighthouse, horizon clouds) was tilted
-- about 6.9 degrees. This moves it back as one rigid piece to the HarborRedesign frame:
-- level, centred under CompassPlaza, OCEAN_DROP studs below the deck top.
-- Command Bar, Edit mode (not Play):
--   require(game.ReplicatedStorage.Shared.WaterLevel:Clone()).preview()
--   require(game.ReplicatedStorage.Shared.WaterLevel:Clone()).run()
-- Ctrl+Z undoes it. Workspace.Map is not managed by Rojo, so save the place afterwards.
local W = {}

local OCEAN_DROP = 46 -- same as HarborRedesign cfg.OceanDrop and the HarborRepair check

local function find()
	local root = assert(workspace:FindFirstChild("CloudHarbor"), "CloudHarbor missing")
	local islands = assert(root:FindFirstChild("Islands"), "CloudHarbor.Islands missing")
	local compass = assert(islands:FindFirstChild("CompassPlaza"), "CompassPlaza missing")
	local plaza = assert(compass:FindFirstChild("StoneDeck"), "CompassPlaza.StoneDeck missing")
	local map = assert(workspace:FindFirstChild("Map"), "Workspace.Map missing")
	local env = assert(map:FindFirstChild("Environment"), "Map.Environment missing")
	local water = assert(env:FindFirstChild("TurquoiseLagoon"), "TurquoiseLagoon missing")
	assert(plaza:IsA("BasePart") and water:IsA("BasePart"), "Unexpected plaza or lagoon class")
	return map, env, water, plaza
end

-- Angle between the part's up axis and world up.
local function tiltDeg(cf)
	return math.deg(math.acos(math.clamp(cf.UpVector.Y, -1, 1)))
end

-- Smallest angle between any local axis and world up (0 for level parts, discs included).
local function axisTiltDeg(cf)
	local m = math.max(math.abs(cf.RightVector.Y), math.abs(cf.UpVector.Y), math.abs(cf.LookVector.Y))
	return math.deg(math.acos(math.clamp(m, -1, 1)))
end

-- Same yaw, no pitch or roll: the shortest rotation that turns the up axis straight up.
local function levelRotation(cf)
	local rot = cf.Rotation
	local up = rot.UpVector
	local axis = up:Cross(Vector3.yAxis)
	local s = axis.Magnitude
	if s < 1e-7 then
		return rot
	end
	local angle = math.atan2(s, up.Y)
	local level = CFrame.fromAxisAngle(axis / s, angle) * rot
	if level.UpVector.Y < 0.99999 then
		level = CFrame.fromAxisAngle(axis / s, -angle) * rot
	end
	assert(level.UpVector.Y > 0.99999, "Could not compute a level frame")
	return level
end

-- Height difference between the highest and lowest corner of the part's top face.
local function cornerSpread(part)
	local cf, half = part.CFrame, part.Size / 2
	local lo, hi = math.huge, -math.huge
	for _, x in { -half.X, half.X } do
		for _, z in { -half.Z, half.Z } do
			local y = (cf * Vector3.new(x, half.Y, z)).Y
			lo = math.min(lo, y)
			hi = math.max(hi, y)
		end
	end
	return hi - lo
end

local function plan()
	local map, env, water, plaza = find()
	local goal = (plaza.CFrame * CFrame.new(0, plaza.Size.Y / 2 - OCEAN_DROP, 0)).Position
	local target = CFrame.new(goal) * levelRotation(water.CFrame)
	return map, env, water, plaza, target, target * water.CFrame:Inverse()
end

local function countParts(env)
	local n = 0
	for _, o in env:GetDescendants() do
		if o:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

function W.preview()
	local _, env, water, plaza, target = plan()
	print(string.format(
		"WATER_LEVEL_PREVIEW: tilt %.3f deg, corner spread %.1f studs; centre %s -> %s; water top after %.2f (deck top %.2f); parts to move %d",
		tiltDeg(water.CFrame), cornerSpread(water), tostring(water.Position), tostring(target.Position),
		target.Position.Y + water.Size.Y / 2, plaza.Position.Y + plaza.Size.Y / 2, countParts(env)
	))
end

function W.run()
	assert(not game:GetService("RunService"):IsRunning(), "Stop Play before running WaterLevel")
	local map, env, water, plaza, target, delta = plan()
	local tiltBefore, spreadBefore = tiltDeg(water.CFrame), cornerSpread(water)
	if tiltBefore < 0.01 and (water.Position - target.Position).Magnitude < 0.02 then
		print("WATER_LEVEL_OK: the lagoon is already level, nothing changed")
		return true
	end

	-- Snapshot every goal first so welded parts cannot be moved twice.
	local parts, goals, pivots = {}, {}, {}
	for _, o in env:GetDescendants() do
		if o:IsA("BasePart") then
			table.insert(parts, o)
			table.insert(goals, delta * o.CFrame)
		elseif o:IsA("Model") and not o.PrimaryPart then
			table.insert(pivots, { model = o, pivot = delta * o.WorldPivot })
		end
	end

	local CHS = game:GetService("ChangeHistoryService")
	local okRec, rec = pcall(function()
		return CHS:TryBeginRecording("WaterLevel", "Level the lagoon")
	end)
	if not okRec then
		rec = nil
	end
	if not rec then
		pcall(function()
			CHS:SetWaypoint("Before WaterLevel")
		end)
	end

	local ok, err = pcall(function()
		local storage = game:GetService("ServerStorage")
		local backup = storage:FindFirstChild("OldMap_Backup")
		if not backup then
			backup = Instance.new("Folder")
			backup.Name = "OldMap_Backup"
			backup.Parent = storage
		end
		if not backup:FindFirstChild("Environment_BeforeWaterLevel") then
			local copy = env:Clone()
			copy.Name = "Environment_BeforeWaterLevel"
			copy.Parent = backup
		end
		for i, p in parts do
			p.CFrame = goals[i]
		end
		for _, entry in pivots do
			entry.model.WorldPivot = entry.pivot
		end
		-- HarborRepair binds Map to this frame; this keeps a repeated HarborRepair.apply() a no-op.
		map:SetAttribute("BoundPlazaFrame", plaza.CFrame)
	end)

	if rec then
		CHS:FinishRecording(rec, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	elseif ok then
		pcall(function()
			CHS:SetWaypoint("Lagoon leveled")
		end)
	end
	assert(ok, "WaterLevel failed: " .. tostring(err))

	assert(tiltDeg(water.CFrame) < 0.01, "The lagoon is still tilted")
	assert((water.Position - target.Position).Magnitude < 0.02, "The lagoon is not under the plaza")
	local aligned = 0
	for _, p in parts do
		if axisTiltDeg(p.CFrame) < 0.05 then
			aligned += 1
		end
	end
	print(string.format(
		"WATER_LEVEL_OK: tilt %.3f -> %.3f deg; corner spread %.1f -> %.1f studs; water top Y %.2f (deck top %.2f); moved %d parts, %d now axis-aligned; backup ServerStorage.OldMap_Backup.Environment_BeforeWaterLevel. Save the place (Ctrl+S).",
		tiltBefore, tiltDeg(water.CFrame), spreadBefore, cornerSpread(water),
		water.Position.Y + water.Size.Y / 2, plaza.Position.Y + plaza.Size.Y / 2, #parts, aligned
	))
	return true
end

return W
