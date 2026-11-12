-- Verifies that ServerStorage backups are safe to move out of the place: lists every reference
-- (ObjectValue, Ref properties) that crosses the boundary between the backups and the rest of the place.
-- Usage: lune run tools/backup-refs <place file>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local BACKUPS = { "OldMap_Backup", "HarborEnvironmentBackup2026", "MapCleanup_Backup" }

local game = roblox.deserializePlace(fs.readFile(process.args[1]))
local ss = game:GetService("ServerStorage")

local inBackup = {}
local backupCount = 0
for _, name in BACKUPS do
	local folder = ss:FindFirstChild(name)
	if folder then
		inBackup[folder] = true
		for _, d in folder:GetDescendants() do
			inBackup[d] = true
			backupCount += 1
		end
	else
		print("missing backup folder", name)
	end
end
print("instances inside backups:", backupCount)
print("ServerStorage children:")
for _, c in ss:GetChildren() do
	print("  ", c.Name, c.ClassName, #c:GetDescendants())
end

-- Ref-valued properties worth checking on common classes.
local REF_PROPS = {
	ObjectValue = { "Value" },
	Model = { "PrimaryPart" },
	Weld = { "Part0", "Part1" },
	WeldConstraint = { "Part0", "Part1" },
	Motor6D = { "Part0", "Part1" },
	Beam = { "Attachment0", "Attachment1" },
	Trail = { "Attachment0", "Attachment1" },
	RopeConstraint = { "Attachment0", "Attachment1" },
	BillboardGui = { "Adornee" },
	SurfaceGui = { "Adornee" },
	Highlight = { "Adornee" },
}

local outsideToBackup, backupToOutside, objectValuesTotal = 0, 0, 0
local samples = {}
for _, d in game:GetDescendants() do
	local props = REF_PROPS[d.ClassName]
	if props then
		for _, prop in props do
			local ok, target = pcall(function()
				return d[prop]
			end)
			if ok and target ~= nil then
				if d.ClassName == "ObjectValue" then
					objectValuesTotal += 1
				end
				local fromBackup, toBackup = inBackup[d] == true, inBackup[target] == true
				if fromBackup ~= toBackup then
					if toBackup then
						outsideToBackup += 1
					else
						backupToOutside += 1
					end
					if #samples < 15 then
						table.insert(samples, string.format("%s.%s -> %s", d:GetFullName(), prop, target:GetFullName()))
					end
				end
			end
		end
	end
end
print("ObjectValues with a target:", objectValuesTotal)
print("refs from live place INTO backups:", outsideToBackup)
print("refs from backups OUT to live place:", backupToOutside)
for _, s in samples do
	print("  " .. s)
end
