-- Builds the updated place from the owner's original file without modifying it:
--   1. moves the ServerStorage backup folders into a separate archive model (.rbxmx),
--   2. replaces HarborServer / HarborShared / HarborClient scripts with the repository versions and adds NpcCore,
--   3. verifies that every other instance in the place is unchanged.
-- Usage: lune run tools/build-place <original.rbxlx> <out.rbxlx> <archive.rbxmx>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local SRC, OUT, ARCHIVE = process.args[1], process.args[2], process.args[3]
assert(SRC and OUT and ARCHIVE, "usage: lune run tools/build-place <original> <out.rbxlx> <archive.rbxmx>")
assert(SRC ~= OUT, "refusing to overwrite the original place")

local BACKUPS = { "OldMap_Backup", "HarborEnvironmentBackup2026", "MapCleanup_Backup" }
-- container path -> repository folder
local SCRIPT_ROOTS = {
	{ path = { "ServerScriptService", "HarborServer" }, dir = "src/HarborServer" },
	{ path = { "ServerScriptService", "NpcCore" }, dir = "src/NpcCore" },
	{ path = { "ReplicatedStorage", "HarborShared" }, dir = "src/HarborShared" },
	{ path = { "StarterPlayer", "StarterPlayerScripts", "HarborClient" }, dir = "src/HarborClient" },
}

local function key(inst)
	return inst:GetFullName() .. "|" .. inst.ClassName
end

-- Fingerprint of everything outside the replaced script folders and the backups.
local function fingerprint(game, skip)
	local list = {}
	for _, d in game:GetDescendants() do
		local skipped = false
		local p = d
		while p do
			if skip[p] then
				skipped = true
				break
			end
			p = p.Parent
		end
		if not skipped then
			local extra = ""
			if d:IsA("BasePart") then
				local cf, size = d.CFrame, d.Size
				extra = string.format("|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%s|%s|%.3f", cf.X, cf.Y, cf.Z, size.X, size.Y, size.Z, tostring(d.Color), tostring(d.Material), d.Transparency)
			elseif d:IsA("LuaSourceContainer") then
				extra = "|" .. #d.Source
			end
			table.insert(list, key(d) .. extra)
		end
	end
	table.sort(list)
	return list
end

local function resolve(game, path)
	local inst = game:GetService(path[1])
	for i = 2, #path do
		inst = inst and inst:FindFirstChild(path[i])
	end
	return inst
end

local function skipSet(game)
	local skip = {}
	local ss = game:GetService("ServerStorage")
	for _, name in BACKUPS do
		local f = ss:FindFirstChild(name)
		if f then
			skip[f] = true
		end
	end
	for _, root in SCRIPT_ROOTS do
		local inst = resolve(game, root.path)
		if inst then
			skip[inst] = true
		end
	end
	return skip
end

local original = roblox.deserializePlace(fs.readFile(SRC))
local before = fingerprint(original, skipSet(original))
local originalTotal = #original:GetDescendants()

-- 1. Archive backups. Restore pointers that target the live map are also stored as paths.
local ss = original:GetService("ServerStorage")
local archived, pointerPaths, backupInstances = {}, 0, 0
for _, name in BACKUPS do
	local folder = ss:FindFirstChild(name)
	if folder then
		backupInstances += 1 + #folder:GetDescendants()
		local inside = { [folder] = true }
		for _, d in folder:GetDescendants() do
			inside[d] = true
		end
		for _, d in folder:GetDescendants() do
			if d.ClassName == "ObjectValue" and d.Value ~= nil and not inside[d.Value] then
				d:SetAttribute("RestoreTargetPath", d.Value:GetFullName())
				pointerPaths += 1
			end
		end
		table.insert(archived, folder)
	end
end
fs.writeFile(ARCHIVE, roblox.serializeModel(archived, true))
for _, folder in archived do
	folder.Parent = nil
end

-- 2. Replace scripts from the repository.
local function build(parent, dir, name)
	local folder = roblox.Instance.new("Folder")
	folder.Name = name
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			build(folder, path, entry)
		else
			local base, class = string.match(entry, "^(.-)%.server%.luau$"), "Script"
			if not base then
				base, class = string.match(entry, "^(.-)%.client%.luau$"), "LocalScript"
			end
			if not base then
				base, class = string.match(entry, "^(.-)%.luau$"), "ModuleScript"
			end
			if base then
				local s = roblox.Instance.new(class)
				s.Name = base
				s.Source = fs.readFile(path)
				s.Parent = folder
			end
		end
	end
	folder.Parent = parent
	return folder
end
local replaced = {}
for _, root in SCRIPT_ROOTS do
	local parentPath = table.clone(root.path)
	local name = table.remove(parentPath)
	local parent = resolve(original, parentPath)
	assert(parent, "missing container " .. table.concat(parentPath, "."))
	local old = parent:FindFirstChild(name)
	local oldCount = old and #old:GetChildren() or 0
	if old then
		old.Parent = nil
	end
	local new = build(parent, root.dir, name)
	table.insert(replaced, string.format("%s.%s: %d -> %d instances", table.concat(parentPath, "."), name, oldCount, #new:GetDescendants()))
end

fs.writeFile(OUT, roblox.serializePlace(original, true))

-- 3. Verify by reading both files back.
local out = roblox.deserializePlace(fs.readFile(OUT))
local after = fingerprint(out, skipSet(out))
local archive = roblox.deserializeModel(fs.readFile(ARCHIVE))
local archiveInstances = 0
for _, i in archive do
	archiveInstances += 1 + #i:GetDescendants()
end
local same = #before == #after
if same then
	for i = 1, #before do
		if before[i] ~= after[i] then
			same = false
			print("DIFF", before[i], "=>", after[i])
			break
		end
	end
end
local scriptsMatch = true
for _, root in SCRIPT_ROOTS do
	local inst = resolve(out, root.path)
	for _, d in inst:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			local rel = {}
			local p = d
			while p ~= inst do
				table.insert(rel, 1, p.Name)
				p = p.Parent
			end
			local suffix = if d.ClassName == "Script" then ".server.luau" elseif d.ClassName == "LocalScript" then ".client.luau" else ".luau"
			if fs.readFile(root.dir .. "/" .. table.concat(rel, "/") .. suffix) ~= d.Source then
				scriptsMatch = false
				print("SCRIPT MISMATCH", d:GetFullName())
			end
		end
	end
end
print(string.format("original instances: %d", originalTotal))
print(string.format("archived backup instances: %d (read back: %d), restore pointers stored as paths: %d", backupInstances, archiveInstances, pointerPaths))
for _, line in replaced do
	print("replaced " .. line)
end
print(string.format("untouched instances compared: %d, identical: %s", #before, tostring(same)))
print(string.format("scripts in output match repository: %s", tostring(scriptsMatch)))
print(string.format("output: %s (%d bytes), archive: %s (%d bytes), original size %d bytes", OUT, #fs.readFile(OUT), ARCHIVE, #fs.readFile(ARCHIVE), #fs.readFile(SRC)))
if not (same and scriptsMatch and archiveInstances == backupInstances) then
	process.exit(1)
end
