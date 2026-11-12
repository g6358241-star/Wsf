-- Compares appearance-related properties of every instance two place files share (by full name + class).
-- Usage: lune run tools/compare-places <a> <b>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local PROPS = {
	SpecialMesh = { "MeshId", "TextureId", "Scale", "MeshType" },
	MeshPart = { "MeshId", "TextureID" },
	Decal = { "Texture", "Transparency" },
	Texture = { "Texture" },
	TextLabel = { "Text", "TextColor3", "TextSize" },
	SurfaceGui = { "Face" },
	PointLight = { "Brightness", "Range", "Color" },
	SpotLight = { "Brightness", "Range", "Color" },
	Sky = { "SkyboxBk", "SkyboxUp" },
	Atmosphere = { "Density", "Color" },
	ProximityPrompt = { "ActionText", "HoldDuration" },
	Part = { "Shape", "Anchored", "CanCollide" },
}

local function index(game)
	local map, dup = {}, {}
	for _, d in game:GetDescendants() do
		local k = d:GetFullName() .. "|" .. d.ClassName
		if map[k] then
			dup[k] = true
		end
		map[k] = d
	end
	for k in dup do
		map[k] = nil -- ambiguous names can't be paired reliably
	end
	return map
end

local a = roblox.deserializePlace(fs.readFile(process.args[1]))
local b = roblox.deserializePlace(fs.readFile(process.args[2]))
local ia, ib = index(a), index(b)
local compared, diffs = 0, 0
for k, x in ia do
	local y = ib[k]
	local props = PROPS[x.ClassName]
	if y and props then
		for _, p in props do
			local ok1, v1 = pcall(function()
				return x[p]
			end)
			local ok2, v2 = pcall(function()
				return y[p]
			end)
			if ok1 and ok2 then
				compared += 1
				if tostring(v1) ~= tostring(v2) then
					diffs += 1
					if diffs <= 10 then
						print("DIFF", k, p, tostring(v1), "=>", tostring(v2))
					end
				end
			end
		end
	end
end
local L1, L2 = a:GetService("Lighting"), b:GetService("Lighting")
for _, p in { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "Technology" } do
	local ok1, v1 = pcall(function()
		return L1[p]
	end)
	local ok2, v2 = pcall(function()
		return L2[p]
	end)
	if ok1 and ok2 then
		compared += 1
		if tostring(v1) ~= tostring(v2) then
			diffs += 1
			print("DIFF Lighting", p)
		end
	end
end
print(string.format("properties compared: %d, differences: %d", compared, diffs))
if diffs > 0 then
	process.exit(1)
end
