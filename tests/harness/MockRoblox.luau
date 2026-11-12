-- Minimal Roblox engine mock for running the real HarborServer scripts headlessly in Lune.
-- It models the instance tree, signals, attributes and the services those scripts touch. Physics,
-- pathfinding and rendering are NOT modelled (NPCService is replaced by MockNPCService).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Rng = require("../../src/NpcCore/Logic/Rng")

local Mock = {}
local deepCloneImpl
local function roblox_clone(v)
	return deepCloneImpl(v)
end

local IS_A = {
	Part = { "BasePart", "PVInstance" },
	MeshPart = { "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	Script = { "BaseScript", "LuaSourceContainer" },
	LocalScript = { "BaseScript", "LuaSourceContainer" },
	ModuleScript = { "LuaSourceContainer" },
	TextLabel = { "GuiObject", "GuiBase2d" },
	IntValue = { "ValueBase" },
	Folder = {},
}

local SIGNALS = {
	Triggered = true, Event = true, OnServerEvent = true, Changed = true, Destroying = true, DescendantAdded = true,
	CharacterAdded = true, PlayerAdded = true, PlayerRemoving = true, Heartbeat = true, PromptGamePassPurchaseFinished = true,
}

function Mock.newWorld(opts)
	opts = opts or {}
	local sched = opts.scheduler
	local world = { sched = sched, clientEvents = {}, kicks = {}, prints = {}, warnings = {} }

	local Signal = {}
	Signal.__index = Signal
	function Signal.new()
		return setmetatable({ handlers = {} }, Signal)
	end
	function Signal:Connect(fn)
		local entry = { fn = fn, connected = true }
		table.insert(self.handlers, entry)
		return {
			Disconnect = function()
				entry.connected = false
			end,
			Connected = true,
		}
	end
	function Signal:Fire(...)
		for _, h in table.clone(self.handlers) do
			if h.connected then
				sched.task.spawn(h.fn, ...)
			end
		end
	end
	function Signal:Wait()
		local co = coroutine.running()
		local conn
		conn = self:Connect(function(...)
			conn.Disconnect()
			sched:resume(co, ...)
		end)
		return coroutine.yield()
	end

	local Instance = {}
	local methods = {}
	local meta = {}

	local function new(className, name)
		local inst = setmetatable({}, meta)
		rawset(inst, "_props", { ClassName = className, Name = name or className })
		rawset(inst, "_children", {})
		rawset(inst, "_attrs", {})
		rawset(inst, "_signals", {})
		return inst
	end
	world.new = new

	meta.__index = function(self, key)
		local props = rawget(self, "_props")
		if key == "Parent" then
			return rawget(self, "_parent")
		end
		local v = props[key]
		if v ~= nil then
			return v
		end
		if methods[key] then
			return methods[key]
		end
		if SIGNALS[key] then
			local signals = rawget(self, "_signals")
			signals[key] = signals[key] or Signal.new()
			return signals[key]
		end
		-- child lookup by name (Roblox dot-indexing)
		for _, c in rawget(self, "_children") do
			if c.Name == key then
				return c
			end
		end
		return nil
	end
	meta.__newindex = function(self, key, value)
		if key == "Parent" then
			local old = rawget(self, "_parent")
			if old then
				local list = rawget(old, "_children")
				local i = table.find(list, self)
				if i then
					table.remove(list, i)
				end
			end
			rawset(self, "_parent", value)
			if value then
				table.insert(rawget(value, "_children"), self)
				local anc = value
				while anc do
					local sig = rawget(anc, "_signals").DescendantAdded
					if sig then
						sig:Fire(self)
					end
					anc = rawget(anc, "_parent")
				end
			end
			return
		end
		rawget(self, "_props")[key] = value
	end
	meta.__tostring = function(self)
		return self.Name
	end

	function methods:GetChildren()
		return table.clone(rawget(self, "_children"))
	end
	function methods:GetDescendants()
		local out = {}
		local function walk(i)
			for _, c in rawget(i, "_children") do
				table.insert(out, c)
				walk(c)
			end
		end
		walk(self)
		return out
	end
	function methods:IsA(className)
		local own = self.ClassName
		if own == className or className == "Instance" then
			return true
		end
		return table.find(IS_A[own] or {}, className) ~= nil
	end
	function methods:FindFirstChild(name, recursive)
		for _, c in (if recursive then self:GetDescendants() else rawget(self, "_children")) do
			if c.Name == name then
				return c
			end
		end
		return nil
	end
	function methods:FindFirstChildWhichIsA(className, recursive)
		for _, c in (if recursive then self:GetDescendants() else rawget(self, "_children")) do
			if c:IsA(className) then
				return c
			end
		end
		return nil
	end
	function methods:FindFirstChildOfClass(className)
		for _, c in rawget(self, "_children") do
			if c.ClassName == className then
				return c
			end
		end
		return nil
	end
	function methods:FindFirstAncestorWhichIsA(className)
		local p = self.Parent
		while p do
			if p:IsA(className) then
				return p
			end
			p = p.Parent
		end
		return nil
	end
	function methods:WaitForChild(name, timeout)
		local c = self:FindFirstChild(name)
		if c then
			return c
		end
		local waited = 0
		while not c and waited < (timeout or 30) do
			sched.task.wait(0.1)
			waited += 0.1
			c = self:FindFirstChild(name)
		end
		if not c and not timeout then
			error("Infinite yield on WaitForChild(" .. name .. ") under " .. self.Name)
		end
		return c
	end
	function methods:SetAttribute(k, v)
		rawget(self, "_attrs")[k] = v
	end
	function methods:GetAttribute(k)
		return rawget(self, "_attrs")[k]
	end
	function methods:GetAttributes()
		return table.clone(rawget(self, "_attrs"))
	end
	function methods:GetAttributeChangedSignal()
		return Signal.new()
	end
	function methods:GetPropertyChangedSignal()
		return Signal.new()
	end
	function methods:Destroy()
		self.Parent = nil
		rawset(self, "_destroyed", true)
	end
	function methods:ClearAllChildren()
		for _, c in self:GetChildren() do
			c:Destroy()
		end
	end
	function methods:GetFullName()
		local parts = {}
		local i = self
		while i and i.ClassName ~= "DataModel" do
			table.insert(parts, 1, i.Name)
			i = i.Parent
		end
		return table.concat(parts, ".")
	end
	-- RemoteEvent / BindableEvent
	function methods:FireClient(player, ...)
		table.insert(world.clientEvents, { player = player, args = table.pack(...) })
	end
	function methods:FireAllClients(...)
		table.insert(world.clientEvents, { player = "all", args = table.pack(...) })
	end
	function methods:Fire(...)
		self.Event:Fire(...)
	end
	function methods:SetNetworkOwner() end
	function methods:Kick(message)
		table.insert(world.kicks, { player = self, message = message })
	end

	Instance.new = function(className, parent)
		local inst = new(className)
		if className == "IntValue" then
			inst.Value = 0
		end
		if parent then
			inst.Parent = parent
		end
		return inst
	end

	-- DataModel and services
	local game = new("DataModel", "Game")
	game.JobId = ""
	world.closeHandlers = {}
	local services = {}
	function methods:GetService(name)
		if services[name] then
			return services[name]
		end
		local s = new(name, name)
		s.Parent = game
		services[name] = s
		return s
	end
	function methods:BindToClose(fn)
		table.insert(world.closeHandlers, fn)
	end

	local Players = game:GetService("Players")
	world.players = {}
	function methods:GetPlayers()
		return table.clone(world.players)
	end
	function methods:GetPlayerByUserId(id)
		for _, p in world.players do
			if p.UserId == id then
				return p
			end
		end
		return nil
	end
	local Run = game:GetService("RunService")
	local studio = opts.studio ~= false
	function methods:IsStudio()
		return studio
	end
	local guidCounter = 0
	game:GetService("HttpService")
	function methods:GenerateGUID()
		guidCounter += 1
		return string.format("00000000-0000-0000-0000-%012d", guidCounter)
	end
	game:GetService("TextService")
	function methods:FilterStringAsync(text)
		return {
			GetNonChatStringForBroadcastAsync = function()
				return text
			end,
		}
	end
	game:GetService("Stats")
	function methods:GetTotalMemoryUsageMb()
		return 0
	end
	-- DataStore: transform semantics of UpdateAsync, shared across worlds via opts.dataStore
	local dsData = opts.dataStore or {}
	world.dataStore = dsData
	game:GetService("DataStoreService")
	function methods:GetDataStore(name)
		dsData[name] = dsData[name] or {}
		local bucket = dsData[name]
		return {
			UpdateAsync = function(_, key, transform)
				local old = bucket[key]
				local new = transform(if old ~= nil then roblox_clone(old) else nil)
				if new == nil then
					return nil
				end
				bucket[key] = roblox_clone(new)
				return roblox_clone(new)
			end,
			GetAsync = function(_, key)
				return roblox_clone(bucket[key])
			end,
		}
	end
	function methods:GetOrderedDataStore(name)
		dsData["ordered:" .. name] = dsData["ordered:" .. name] or {}
		local bucket = dsData["ordered:" .. name]
		return {
			UpdateAsync = function(_, key, transform)
				local new = transform(bucket[key])
				if new ~= nil then
					bucket[key] = new
				end
				return new
			end,
			GetSortedAsync = function(_, ascending, size)
				local rows = {}
				for k, v in bucket do
					table.insert(rows, { key = k, value = v })
				end
				table.sort(rows, function(a, b)
					return if ascending then a.value < b.value else a.value > b.value
				end)
				while #rows > size do
					table.remove(rows)
				end
				return {
					GetCurrentPage = function()
						return rows
					end,
				}
			end,
		}
	end
	local Market = game:GetService("MarketplaceService")
	local Workspace = game:GetService("Workspace")
	game:GetService("ReplicatedStorage")
	game:GetService("ServerScriptService")
	game:GetService("CollectionService")

	function world.addPlayer(userId, name, position)
		local p = new("Player", name)
		p.UserId = userId
		p.DisplayName = name
		local char = new("Model", name)
		local root = new("Part", "HumanoidRootPart")
		root.Position = position or roblox.Vector3.new(0, 42, 0)
		root.Parent = char
		p.Character = char
		table.insert(world.players, p)
		p.Parent = Players
		Players.PlayerAdded:Fire(p)
		return p
	end
	function world.removePlayer(p)
		local i = table.find(world.players, p)
		if i then
			table.remove(world.players, i)
		end
		Players.PlayerRemoving:Fire(p)
		p.Parent = nil
	end
	function world.close()
		for _, fn in world.closeHandlers do
			sched.task.spawn(fn)
		end
	end

	-- Map stand-in: 48 booths on a ring with the same parts the Booths module expects.
	function world.buildMap(count)
		local cloud = new("Model", "CloudHarbor")
		local folder = new("Folder", "Booths")
		folder.Parent = cloud
		for i = 1, count do
			local angle = (i - 1) / count * math.pi * 2
			local pos = roblox.Vector3.new(math.cos(angle) * 90, 41, math.sin(angle) * 90)
			local model = new("Model", string.format("Booth_%03d", i))
			local counter = new("Part", "CounterTop")
			counter.Position = pos
			counter.Parent = model
			local prompt = new("ProximityPrompt", "ClaimPrompt")
			prompt.Parent = counter
			local board = new("Part", "SignBoard")
			board.Position = pos + roblox.Vector3.new(0, 4, 0)
			board.Parent = model
			local gui = new("SurfaceGui", "SurfaceGui")
			gui.Parent = board
			local label = new("TextLabel", "BoothStatus")
			label.Text = "UNCLAIMED"
			label.Parent = gui
			model.Parent = folder
		end
		cloud.Parent = Workspace
		return cloud
	end

	-- Script tree mirroring default.project.json; ModuleScripts point at repo files.
	local root = opts.root
	local function mount(parent, dir, name)
		local folder = new("Folder", name)
		folder.Parent = parent
		for _, entry in fs.readDir(dir) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				mount(folder, path, entry)
			else
				local base, kind = string.match(entry, "^(.-)%.server%.luau$"), "Script"
				if not base then
					base, kind = string.match(entry, "^(.-)%.client%.luau$"), "LocalScript"
				end
				if not base then
					base, kind = string.match(entry, "^(.-)%.luau$"), "ModuleScript"
				end
				if base then
					local s = new(kind, base)
					rawset(s, "_path", path)
					rawset(s, "_source", fs.readFile(path))
					s.Parent = folder
				end
			end
		end
		return folder
	end
	mount(game:GetService("ReplicatedStorage"), root .. "/src/HarborShared", "HarborShared")
	mount(game:GetService("ServerScriptService"), root .. "/src/HarborServer", "HarborServer")
	mount(game:GetService("ServerScriptService"), root .. "/src/NpcCore", "NpcCore")
	if opts.overrides then
		for fullName, path in opts.overrides do
			local inst = game
			for part in string.gmatch(fullName, "[^%.]+") do
				inst = inst:FindFirstChild(part)
			end
			rawset(inst, "_path", path)
			rawset(inst, "_source", fs.readFile(path))
		end
	end

	-- Environment
	local virtualOs = {
		clock = function()
			return sched.now
		end,
		time = function()
			return (opts.epoch or 1_800_000_000) + math.floor(sched.now)
		end,
		date = os.date,
	}
	local RandomMock = {
		new = function(seed)
			local r = Rng.new(seed or 1)
			return {
				NextNumber = function(_, a, b)
					return r:range(a or 0, b or 1)
				end,
				NextInteger = function(_, a, b)
					return r:int(a, b)
				end,
			}
		end,
	}
	local cache = {}
	local load
	local function resolveString(from, path)
		local inst = from.Parent
		for part in string.gmatch(path, "[^/]+") do
			if part == "." then
				-- stay
			elseif part == ".." then
				inst = inst.Parent
			else
				inst = inst:FindFirstChild(part)
			end
			assert(inst, "cannot resolve " .. path .. " from " .. from:GetFullName())
		end
		return inst
	end
	local function makeRequire(from)
		return function(target)
			if type(target) == "string" then
				if string.sub(target, 1, 1) == "@" then
					return require(target)
				end
				target = resolveString(from, target)
			end
			if type(target) == "table" and rawget(target, "_mockModule") then
				return rawget(target, "_mockModule")
			end
			if cache[target] == nil then
				cache[target] = load(target)
			end
			return cache[target]
		end
	end
	local function env(scriptInst)
		return {
			script = scriptInst, game = game, workspace = Workspace, Instance = Instance, task = sched.task, os = virtualOs,
			require = makeRequire(scriptInst), Random = RandomMock, Enum = roblox.Enum, Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame, Color3 = roblox.Color3, UDim2 = roblox.UDim2,
			print = function(...)
				local parts = table.pack(...)
				for i = 1, parts.n do
					parts[i] = tostring(parts[i])
				end
				table.insert(world.prints, table.concat(parts, " "))
			end,
			warn = function(...)
				local parts = table.pack(...)
				for i = 1, parts.n do
					parts[i] = tostring(parts[i])
				end
				table.insert(world.warnings, table.concat(parts, " "))
			end,
		}
	end
	load = function(inst)
		local path = rawget(inst, "_path") or error("no source for " .. inst:GetFullName())
		local chunk = luau.load(rawget(inst, "_source"), { debugName = path, environment = env(inst) })
		return chunk()
	end
	world.require = makeRequire(game)
	function world.runScript(fullName)
		local inst = game
		for part in string.gmatch(fullName, "[^%.]+") do
			inst = inst:FindFirstChild(part)
		end
		sched.task.spawn(function()
			load(inst)
		end)
	end
	function world.find(fullName)
		local inst = game
		for part in string.gmatch(fullName, "[^%.]+") do
			inst = inst and inst:FindFirstChild(part)
		end
		return inst
	end
	world.game = game
	world.workspace = Workspace
	world.Players = Players
	world.Market = Market
	world.Run = Run
	return world
end

deepCloneImpl = function(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, c in v do
		out[k] = deepCloneImpl(c)
	end
	return out
end

return Mock
