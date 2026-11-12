-- Extracts every script in a place file to disk, mirroring the instance hierarchy.
-- Usage: lune run tools/extract-scripts <place file> <output dir>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or error("usage: lune run tools/extract-scripts <place> <outdir>")
local out = process.args[2] or error("missing output dir")
local game = roblox.deserializePlace(fs.readFile(path))

local suffix = { Script = ".server.luau", LocalScript = ".client.luau", ModuleScript = ".luau" }
local index = {}

for _, d in game:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		local parts = {}
		local node = d
		while node and node ~= game do
			table.insert(parts, 1, (string.gsub(node.Name, "[^%w%._%-]", "_")))
			node = node.Parent
		end
		local file = out .. "/" .. table.concat(parts, "/") .. (suffix[d.ClassName] or ".luau")
		local dir = string.match(file, "^(.*)/[^/]*$")
		fs.writeDir(dir)
		local ok, src = pcall(function()
			return d.Source
		end)
		local source = if ok and src then src else ""
		local disabled = ""
		pcall(function()
			if d:IsA("Script") and d.Enabled == false then
				disabled = " DISABLED"
			end
		end)
		-- scripts with children (e.g. module with submodules) still get their own file
		if fs.isFile(file) then
			file = file .. ".dup" .. tostring(#index)
		end
		fs.writeFile(file, source)
		table.insert(index, string.format("%6d  %s%s", #string.split(source, "\n"), string.sub(file, #out + 2), disabled))
	end
end
table.sort(index, function(a, b)
	return string.sub(a, 9) < string.sub(b, 9)
end)
fs.writeFile(out .. "/INDEX.txt", table.concat(index, "\n") .. "\n")
print(#index .. " scripts extracted")
