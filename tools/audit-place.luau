-- Map audit helper: summarises a .rbxl/.rbxlx place file. Usage: lune run tools/audit-place <path>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or error("usage: lune run tools/audit-place <place file>")
local game = roblox.deserializePlace(fs.readFile(path))

local function countClasses(root)
	local counts = {}
	for _, d in root:GetDescendants() do
		counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
	end
	local list = {}
	for k, v in counts do
		table.insert(list, { k, v })
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	return list
end

print("== Services (direct children with descendants) ==")
for _, service in game:GetChildren() do
	local n = #service:GetDescendants()
	if n > 0 then
		print(string.format("%-28s %-22s %6d descendants", service.Name, service.ClassName, n))
	end
end

print("\n== Top class counts (whole place) ==")
for i, entry in countClasses(game) do
	if i > 40 then
		break
	end
	print(string.format("%-24s %d", entry[1], entry[2]))
end

local function tree(inst, depth, maxDepth)
	if depth > maxDepth then
		return
	end
	local kids = inst:GetChildren()
	-- collapse many same-named siblings
	local seen = {}
	for _, c in kids do
		local key = c.Name .. "|" .. c.ClassName
		seen[key] = (seen[key] or 0) + 1
	end
	local printed = {}
	for _, c in kids do
		local key = c.Name .. "|" .. c.ClassName
		if not printed[key] then
			printed[key] = true
			local extra = ""
			if c:IsA("BasePart") then
				local ok, pos = pcall(function()
					return c.Position
				end)
				local ok2, size = pcall(function()
					return c.Size
				end)
				if ok and ok2 then
					extra = string.format("  pos=(%.0f,%.0f,%.0f) size=(%.0f,%.0f,%.0f)", pos.X, pos.Y, pos.Z, size.X, size.Y, size.Z)
				end
			end
			local mult = if seen[key] > 1 then string.format(" x%d", seen[key]) else ""
			print(string.rep("  ", depth) .. c.Name .. " [" .. c.ClassName .. "]" .. mult .. " (" .. #c:GetDescendants() .. ")" .. extra)
			tree(c, depth + 1, maxDepth)
		end
	end
end

local depth = tonumber(process.args[2]) or 3
for _, name in { "Workspace", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPlayer", "StarterPack", "ReplicatedFirst", "Lighting", "SoundService", "Teams" } do
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	if ok and s and #s:GetChildren() > 0 then
		print("\n== " .. name .. " ==")
		tree(s, 1, depth)
	end
end

print("\n== Scripts ==")
for _, d in game:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		local ok, src = pcall(function()
			return d.Source
		end)
		local lines = if ok and src then #string.split(src, "\n") else 0
		print(string.format("%-14s %-60s %5d lines", d.ClassName, d:GetFullName(), lines))
	end
end

print("\n== Lighting properties ==")
local L = game:GetService("Lighting")
for _, p in { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "Technology", "GlobalShadows", "FogEnd", "FogColor" } do
	local ok, v = pcall(function()
		return L[p]
	end)
	if ok then
		print(p, tostring(v))
	end
end
