-- Focused audit of the CloudHarbor map: booths, islands, bridges, spawn, lighting and StarterGui.
-- Usage: lune run tools/audit-map <place file>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local game = roblox.deserializePlace(fs.readFile(process.args[1]))
local ws = game:GetService("Workspace")
local cloud = ws:FindFirstChild("CloudHarbor")

local function v3(v)
	return string.format("(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
end

local function pivot(model)
	local ok, cf = pcall(function()
		return model:GetPivot()
	end)
	if ok then
		return v3(cf.Position)
	end
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	local okPart, cframe = pcall(function()
		return part.CFrame
	end)
	return if okPart and cframe then v3(cframe.Position) else "?"
end

print("== Booths ==")
local booths = cloud.Booths:GetChildren()
print("count", #booths)
for i, b in booths do
	local names = {}
	for _, c in b:GetChildren() do
		table.insert(names, c.Name)
	end
	local prompt = b:FindFirstChildWhichIsA("ProximityPrompt", true)
	local attrs = {}
	for k, v in b:GetAttributes() do
		table.insert(attrs, k .. "=" .. tostring(v))
	end
	if i <= 3 then
		print(b.Name, b.ClassName, pivot(b), "#desc=" .. #b:GetDescendants(), "prompt=" .. tostring(prompt ~= nil), "children=" .. table.concat(names, ","), table.concat(attrs, " "))
	else
		print(b.Name, pivot(b), "#desc=" .. #b:GetDescendants(), "prompt=" .. tostring(prompt ~= nil))
	end
end

for _, folderName in { "Islands", "Bridges", "SpawnLocations", "Landmarks", "Decor", "LightingProps" } do
	print("\n== " .. folderName .. " ==")
	for _, c in cloud[folderName]:GetChildren() do
		local deck = c:FindFirstChild("StoneDeck") or c:FindFirstChild("Deck")
		local extra = ""
		if deck and deck:IsA("BasePart") then
			extra = " deck pos=" .. v3(deck.CFrame.Position) .. " size=" .. v3(deck.Size) .. " mat=" .. tostring(deck.Material) .. " color=" .. tostring(deck.Color)
		elseif c:IsA("BasePart") then
			extra = " pos=" .. v3(c.CFrame.Position) .. " size=" .. v3(c.Size)
		end
		print(c.Name, c.ClassName, "#desc=" .. #c:GetDescendants() .. extra)
	end
end

print("\n== Palette sample (top materials/colors among CloudHarbor parts) ==")
local mats, cols = {}, {}
for _, d in cloud:GetDescendants() do
	if d:IsA("BasePart") then
		local m = tostring(d.Material)
		mats[m] = (mats[m] or 0) + 1
		local c = d.Color
		local key = string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
		cols[key] = (cols[key] or 0) + 1
	end
end
local function top(t, n)
	local l = {}
	for k, v in t do
		table.insert(l, { k, v })
	end
	table.sort(l, function(a, b)
		return a[2] > b[2]
	end)
	local out = {}
	for i = 1, math.min(n, #l) do
		table.insert(out, l[i][1] .. ":" .. l[i][2])
	end
	return table.concat(out, "  ")
end
print("materials", top(mats, 10))
print("colors", top(cols, 14))

print("\n== Lighting ==")
local L = game:GetService("Lighting")
for _, p in { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "Technology", "EnvironmentDiffuseScale", "ExposureCompensation" } do
	local ok, v = pcall(function()
		return L[p]
	end)
	print(p, ok and tostring(v) or "?")
end
for _, c in L:GetChildren() do
	print("  child", c.Name, c.ClassName)
end

print("\n== StarterGui ==")
for _, c in game:GetService("StarterGui"):GetChildren() do
	print(c.Name, c.ClassName, #c:GetDescendants())
end
print("NPCWaypoints folder:", ws:FindFirstChild("NPCWaypoints") ~= nil)
