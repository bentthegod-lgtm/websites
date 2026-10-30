--[[
	MonsterBrain - the Antlered's decisions, independent of Roblox (unit-tested in Lune).

	It is blind. It only knows what it hears (noises the server reports, already scaled by
	distance and weather) and what it feels through the ice right next to it. MonsterService
	feeds it those perceptions and moves the body toward the goal it returns.

	States:
	  Dormant      asleep under the ice until the grace period ends
	  Prowl        wander between points out on the lake
	  Listen       stop dead and listen (after a faint sound, or while searching)
	  Investigate  walk to where a sound came from
	  Hunt         run at a loud or close sound; keeps updating from new sounds
	  Search       sweep around the last sound it heard
	  Recover      a pause after catching someone
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local MonsterBrain = {}
MonsterBrain.__index = MonsterBrain

local States = {
	Dormant = "Dormant",
	Prowl = "Prowl",
	Listen = "Listen",
	Investigate = "Investigate",
	Hunt = "Hunt",
	Search = "Search",
	Recover = "Recover",
}
MonsterBrain.States = States

local M = GameConfig.Monster
local N = GameConfig.Noise

local function flat(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
MonsterBrain.flatDistance = flat

--[[
	opts = {
	  huntSpeed = number,         -- from the difficulty
	  wakeAt = number,            -- clock time the grace period ends
	  prowlPoint = function(from) -> Vector3,
	  rng = Random-like,
	}
]]
function MonsterBrain.new(opts)
	local self = setmetatable({}, MonsterBrain)
	self.opts = opts
	self.state = States.Dormant
	self.since = 0
	self.goal = nil
	self.lastHeard = nil
	self.lastHeardAt = -math.huge
	self.target = nil -- a player it is hunting (when the loud sound came from one)
	self.history = {}
	return self
end

function MonsterBrain:_enter(state, now, reason)
	if self.state ~= state then
		table.insert(self.history, { from = self.state, to = state, at = now, reason = reason })
		if #self.history > 50 then
			table.remove(self.history, 1)
		end
	end
	self.state = state
	self.since = now
end

-- Is it awake and able to react to sounds?
function MonsterBrain:awake()
	return self.state ~= States.Dormant and self.state ~= States.Recover
end

--[[
	A sound reached it. noise = { position, intensity (already perceived 0..1), source }
	Faint sounds make it stop and listen / investigate; loud ones start a hunt.
]]
function MonsterBrain:hear(noise, now)
	if not self:awake() or noise.intensity < N.HearThreshold then
		return false
	end
	self.lastHeard = noise.position
	self.lastHeardAt = now
	if noise.intensity >= N.HuntThreshold or self.state == States.Hunt then
		self.goal = noise.position
		self.target = noise.source
		self:_enter(States.Hunt, now, "loud")
	elseif self.state == States.Prowl or self.state == States.Search or self.state == States.Listen then
		self.goal = noise.position
		self:_enter(States.Investigate, now, "faint")
	elseif self.state == States.Investigate then
		self.goal = noise.position -- keep following
		self.since = now
	end
	return true
end

-- Footsteps right beside it, felt through the ice (works even when it can't "hear").
function MonsterBrain:feel(source, position, now)
	if not self:awake() then
		return false
	end
	self.goal = position
	self.target = source
	self.lastHeard = position
	self.lastHeardAt = now
	self:_enter(States.Hunt, now, "felt")
	return true
end

-- The body got as close to the goal as the ice allows (the goal is over water, behind
-- rocks, or it is stuck): count it as arrived, so every state moves on instead of
-- walking at an unreachable point forever.
function MonsterBrain:arrive(position)
	if self.goal then
		self.goal = position
	end
end

-- It caught someone: pause, then go back to prowling.
function MonsterBrain:caught(now)
	self.target = nil
	self.goal = nil
	self:_enter(States.Recover, now, "caught")
end

-- The hunted player is gone (frozen, escaped, left): fall back to searching.
function MonsterBrain:loseTarget(now)
	self.target = nil
	if self.state == States.Hunt then
		self:_enter(States.Search, now, "lost target")
	end
end

--[[
	Called every monster tick with its current position. Returns the intent:
	  { state, goal (Vector3 or nil), speed }
]]
function MonsterBrain:update(now, position)
	local s = self.state
	local opts = self.opts
	local elapsed = now - self.since
	if s == States.Dormant then
		if now >= (opts.wakeAt or 0) then
			self:_enter(States.Prowl, now, "woke")
			self.goal = opts.prowlPoint(position)
		end
		return { state = self.state, goal = self.goal, speed = M.ProwlSpeed }
	elseif s == States.Recover then
		if elapsed >= M.RecoverTime then
			self:_enter(States.Prowl, now, "recovered")
			self.goal = opts.prowlPoint(position)
		end
		return { state = self.state, goal = nil, speed = 0 }
	elseif s == States.Prowl then
		if not self.goal or flat(position, self.goal) < 4 then
			self:_enter(States.Listen, now, "arrived")
			self.goal = nil
		end
		return { state = self.state, goal = self.goal, speed = M.ProwlSpeed }
	elseif s == States.Listen then
		if elapsed >= M.ListenPause then
			self.goal = opts.prowlPoint(position)
			self:_enter(States.Prowl, now, "nothing heard")
		end
		return { state = self.state, goal = nil, speed = 0 }
	elseif s == States.Investigate then
		if self.goal and flat(position, self.goal) < 4 then
			self:_enter(States.Search, now, "reached the sound")
		elseif elapsed >= M.InvestigateTime then
			self:_enter(States.Search, now, "gave up walking")
		end
		return { state = self.state, goal = self.goal, speed = M.InvestigateSpeed }
	elseif s == States.Hunt then
		-- No new sound for a while and it reached the last one: start searching.
		local quiet = now - self.lastHeardAt
		if quiet >= M.InvestigateTime or (self.goal and flat(position, self.goal) < 3 and quiet > 1.5) then
			self:_enter(States.Search, now, "went quiet")
			self.target = nil
		end
		return { state = self.state, goal = self.goal, speed = opts.huntSpeed or 18 }
	elseif s == States.Search then
		if elapsed >= M.SearchTime * (opts.searchScale or 1) then
			self.goal = opts.prowlPoint(position)
			self:_enter(States.Prowl, now, "search over")
		elseif not self.goal or flat(position, self.goal) < 3 then
			local center = self.lastHeard or position
			local rng = opts.rng
			local angle = (rng and rng:NextNumber() or 0.5) * math.pi * 2
			local radius = 6 + (rng and rng:NextNumber() or 0.5) * 10
			self.goal = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		end
		return { state = self.state, goal = self.goal, speed = M.InvestigateSpeed }
	end
	return { state = s, goal = nil, speed = 0 }
end

return MonsterBrain
