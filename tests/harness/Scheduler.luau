-- Deterministic virtual-time scheduler implementing Roblox's `task` library for headless tests.
-- Time only advances when run() pops the next event, so hours of gameplay run in seconds.
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new()
	local self = setmetatable({ now = 0, queue = {}, seq = 0, errors = {} }, Scheduler)
	local s = self
	self.task = {
		spawn = function(f, ...)
			return s:resume(if type(f) == "thread" then f else coroutine.create(f), ...)
		end,
		defer = function(f, ...)
			local co = if type(f) == "thread" then f else coroutine.create(f)
			s:schedule(0, co, table.pack(...))
			return co
		end,
		delay = function(seconds, f, ...)
			local co = if type(f) == "thread" then f else coroutine.create(f)
			s:schedule(seconds or 0, co, table.pack(...))
			return co
		end,
		wait = function(seconds)
			local co = coroutine.running()
			local started = s.now
			s:schedule(seconds or 0, co, table.pack())
			coroutine.yield()
			return s.now - started
		end,
		cancel = function(co)
			for i, ev in s.queue do
				if ev.co == co then
					table.remove(s.queue, i)
					break
				end
			end
		end,
	}
	return self
end

function Scheduler.schedule(self, seconds: number, co: thread, args)
	self.seq += 1
	local ev = { t = self.now + math.max(0, seconds), seq = self.seq, co = co, args = args }
	-- binary insertion keeps the queue ordered by (t, seq)
	local lo, hi = 1, #self.queue
	while lo <= hi do
		local mid = (lo + hi) // 2
		local m = self.queue[mid]
		if m.t < ev.t or (m.t == ev.t and m.seq < ev.seq) then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	table.insert(self.queue, lo, ev)
end

function Scheduler.resume(self, co: thread, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(self.errors, debug.traceback(co, tostring(err)))
	end
	return co
end

function Scheduler.run(self, untilT: number)
	while #self.queue > 0 and self.queue[1].t <= untilT do
		local ev = table.remove(self.queue, 1)
		self.now = ev.t
		if coroutine.status(ev.co) == "suspended" then
			self:resume(ev.co, table.unpack(ev.args, 1, ev.args.n))
		end
	end
	self.now = math.max(self.now, untilT)
end

function Scheduler.advance(self, seconds: number)
	self:run(self.now + seconds)
end

return Scheduler
