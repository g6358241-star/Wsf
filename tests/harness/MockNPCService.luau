-- Stand-in for NPCService in headless integration tests: same director-facing API, with walking and
-- holding modelled as virtual-time delays and occasional path failures / lost rigs.
local Rng = require(game:GetService("ServerScriptService").NpcCore.Logic.Rng)
local M = { Running = false, Agents = {}, Events = {}, Stats = { Spawned = 0, Despawned = 0, Lost = 0, LateCallbacks = 0 } }
M.Events.Lost = Instance.new("BindableEvent")
local rng = Rng.new("mock-movement")
local nextHandle = 0
M.failVisitChance = 0.03
M.loseChance = 0.002

local function alive(handle)
	return M.Agents[handle] ~= nil
end
local function later(seconds, handle, fn)
	task.delay(seconds, function()
		if alive(handle) then
			fn()
		else
			M.Stats.LateCallbacks += 1 -- dropped on purpose: despawned characters never call back
		end
	end)
end

function M.Start()
	M.Running = true
end
function M.Stop()
	M.Running = false
	table.clear(M.Agents)
end
function M.Spawn(spec, onReady)
	task.delay(0.2, function()
		if not M.Running then
			onReady(nil)
			return
		end
		nextHandle += 1
		local handle = "h" .. nextHandle
		M.Agents[handle] = { id = spec.id, name = spec.name, model = nil }
		M.Stats.Spawned += 1
		onReady(handle)
	end)
end
function M.BoothModel(boothId)
	return workspace.CloudHarbor.Booths:FindFirstChild(boothId)
end
function M.VisitBooth(handle, booth, onArrive, onFail)
	assert(booth, "VisitBooth without booth model")
	local fail = rng:chance(M.failVisitChance)
	later(rng:range(6, 20), handle, if fail then onFail else onArrive)
end
function M.Hold(handle, seconds, onDone)
	later(seconds, handle, onDone)
end
M.approachFailChance = 0.05
M.said = {}
function M.ApproachPlayer(handle, player, onArrive, onFail)
	local fail = rng:chance(M.approachFailChance) or not player.Parent
	later(rng:range(4, 12), handle, if fail then onFail else onArrive)
end
function M.Say(handle, text)
	if M.Agents[handle] then
		table.insert(M.said, text)
	end
end
function M.Model(_handle)
	return nil
end
function M.Wander(handle, onDone)
	if rng:chance(M.loseChance) then
		task.delay(1, function()
			local a = M.Agents[handle]
			if a then
				M.Agents[handle] = nil
				M.Stats.Lost += 1
				M.Events.Lost:Fire(a.id)
			end
		end)
		return
	end
	later(rng:range(5, 15), handle, onDone)
end
function M.Despawn(handle)
	if M.Agents[handle] then
		M.Agents[handle] = nil
		M.Stats.Despawned += 1
	end
end
return M
