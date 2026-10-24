--[[
	MonsterBrain - the Listener's decision-making, independent of Roblox physics.

	MonsterService feeds it perceptions (heard noises, sight observations, chase target
	state) and executes the intent it returns (where to walk, how fast, what to face,
	whether to attack or check a hiding spot). Keeping the state machine pure means it is
	unit-tested in Lune (tests/monster_brain.spec.luau).

	States:
	  Patrol       walk between patrol points, sometimes stop to listen
	  Suspicion    a faint noise or a glimpse: stop, turn, creep toward it
	  Investigate  travel to where a noise came from (speed depends on intensity)
	  Search       sweep nearby rooms, pause to listen, check hiding spots
	  CheckHiding  open a hiding spot (resolved by the service)
	  Chase        visual contact: sprint after a specific player
	  Attack       wind-up / strike (resolved by the service)
	  Lost         lost sight mid-chase: head for the predicted position, then search hard
	  Recover      brief listening pause after a hunt, then patrol or search

	Positions are whatever vector type the caller uses (Roblox Vector3 in game, Lune's
	roblox Vector3 in tests). The brain only adds, subtracts and scales them.
]]

local MonsterBrain = {}
MonsterBrain.__index = MonsterBrain

local States = {
	Patrol = "Patrol",
	Suspicion = "Suspicion",
	Investigate = "Investigate",
	Search = "Search",
	CheckHiding = "CheckHiding",
	Chase = "Chase",
	Attack = "Attack",
	Lost = "Lost",
	Recover = "Recover",
}
MonsterBrain.States = States

local function flatDistance(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
MonsterBrain.flatDistance = flatDistance

-- The Listener has no eyes: it senses movement. A still player is only noticed when it is
-- close enough to brush against them.
function MonsterBrain.sensesMotion(speed, distance, sightConfig)
	return speed >= sightConfig.MotionThreshold or distance <= sightConfig.StillDetectRange
end

local DEFAULT_MODS = { speed = 1, hearing = 1, sight = 1, searchTime = 1, recoverTime = 1 }

--[[
	provider:
	  patrolPoint(fromPosition) -> position
	  searchPoints(center, radius, count) -> { { position = v, hidingSpotId = string? } }
	  sawHidingEntry(hidingSpotId) -> boolean   (optional)
]]
function MonsterBrain.new(cfg, rng, provider, mods)
	local self = setmetatable({}, MonsterBrain)
	self.cfg = cfg
	self.rng = rng
	self.provider = provider
	self.mods = mods or DEFAULT_MODS
	self.state = States.Patrol
	self.stateSince = 0
	self.awareness = {}
	self.recentSounds = {}
	self.history = {} -- recent state transitions, for debugging/tests
	return self
end

function MonsterBrain:_enter(state, now, reason)
	if self.state ~= state then
		table.insert(self.history, { from = self.state, to = state, at = now, reason = reason })
		if #self.history > 40 then
			table.remove(self.history, 1)
		end
	end
	self.state = state
	self.stateSince = now
	self.goal = nil
end

function MonsterBrain:_speed(name)
	return self.cfg.Speeds[name] * self.mods.speed
end

---------------------------------------------------------------------------------------------
-- State entry helpers
---------------------------------------------------------------------------------------------

function MonsterBrain:_enterPatrol(now, reason)
	self:_enter(States.Patrol, now, reason)
	self.listenUntil = nil
	self.patrolGoal = nil
end

function MonsterBrain:_enterSuspicion(position, now, reason)
	if self.state ~= States.Suspicion then
		self.suspicionReturn = self.state
	end
	self:_enter(States.Suspicion, now, reason)
	self.suspicionPos = position
	self.suspicionUntil = now + self.cfg.Suspicion.Duration
end

function MonsterBrain:_enterInvestigate(position, intensity, rush, now, reason)
	local wasInvestigating = self.state == States.Investigate
	self:_enter(States.Investigate, now, reason)
	if wasInvestigating and self.investigatePos and flatDistance(self.investigatePos, position) < 6 then
		self.investigateIntensity = math.max(self.investigateIntensity or 0, intensity)
		self.investigateRush = self.investigateRush or rush
	else
		self.investigateIntensity = intensity
		self.investigateRush = rush
	end
	self.investigatePos = position
	self.investigateSince = now
	self.arrivedAt = nil
end

function MonsterBrain:_enterSearch(center, afterChase, now, reason)
	self:_enter(States.Search, now, reason)
	local s = self.cfg.Search
	local radius = if afterChase then s.AfterChaseRadius else s.Radius
	local count = if afterChase then s.AfterChasePoints else s.Points
	local duration = (if afterChase then s.AfterChaseDuration else s.Duration) * self.mods.searchTime
	self.searchPoints = self.provider.searchPoints(center, radius, count) or {}
	self.searchIndex = 1
	self.searchUntil = now + duration
	self.searchAfterChase = afterChase
	self.evidencePos = center
	self.pauseUntil = nil
end

function MonsterBrain:_enterChase(targetId, position, velocity, now, reason)
	self:_enter(States.Chase, now, reason)
	self.targetId = targetId
	self.lastKnown = position
	self.lastVelocity = velocity
	self.lastEvidenceAt = now
	self.chaseSince = now
end

function MonsterBrain:_enterLost(now, reason)
	self:_enter(States.Lost, now, reason)
	local predicted = self.lastKnown
	if self.lastVelocity then
		predicted = self.lastKnown + self.lastVelocity * self.cfg.Chase.PredictTime
	end
	self.lostGoal = predicted
	self.lostFallback = false
end

function MonsterBrain:_enterRecover(duration, nextState, now, reason)
	self:_enter(States.Recover, now, reason)
	self.recoverUntil = now + duration * self.mods.recoverTime
	self.recoverNext = nextState
end

---------------------------------------------------------------------------------------------
-- Perception input
---------------------------------------------------------------------------------------------

--[[
	stimulus = { position = v (already approximate), intensity = number, category = string }
	Returns true when the noise changed what the monster is doing.
]]
function MonsterBrain:hear(stimulus, now)
	local h = self.cfg.Hearing
	local intensity = stimulus.intensity
	if intensity < h.Threshold then
		return false
	end

	-- Track recent noises to recognise a series (e.g. repeated footsteps, repeated cranks).
	local recent = self.recentSounds
	for i = #recent, 1, -1 do
		if now - recent[i].at > h.SeriesWindow then
			table.remove(recent, i)
		end
	end
	table.insert(recent, { position = stimulus.position, at = now, intensity = intensity })
	local series = 0
	for _, s in ipairs(recent) do
		if flatDistance(s.position, stimulus.position) <= h.SeriesRadius then
			series += 1
		end
	end
	self.lastSeries = series

	local state = self.state
	if state == States.Attack or state == States.CheckHiding then
		return false
	end

	if state == States.Chase then
		if self.lastKnown and flatDistance(stimulus.position, self.lastKnown) <= h.ChaseHearRadius then
			self.lastKnown = stimulus.position
			self.lastEvidenceAt = now
		end
		return false
	end

	if state == States.Recover and intensity < h.RecoverWakeThreshold and series < 2 then
		return false
	end

	local rush = intensity >= h.HighIntensity or series >= h.SeriesForRush
	local calm = state == States.Patrol or state == States.Recover or (state == States.Search and not self.searchAfterChase)

	if calm and not rush and intensity < h.SuspicionBelow and series < 2 then
		self:_enterSuspicion(stimulus.position, now, "faint:" .. tostring(stimulus.category))
		return true
	end

	if state == States.Investigate and not rush then
		local age = now - (self.investigateSince or now)
		local weaker = intensity < (self.investigateIntensity or 0) * h.RetargetRatio
		local far = flatDistance(stimulus.position, self.investigatePos) > 15
		if weaker and far and age < 4 then
			return false
		end
	end

	self:_enterInvestigate(stimulus.position, intensity, rush, now, "noise:" .. tostring(stimulus.category))
	return true
end

--[[
	observations = { { id, position, velocity, gain, distance } } for every candidate this tick
	(gain = 0 when not visible). Awareness accumulates while visible and decays otherwise.
]]
function MonsterBrain:perceive(observations, dt, now)
	local sight = self.cfg.Sight
	local seen = {}
	local best, bestAwareness = nil, -1
	for _, obs in ipairs(observations) do
		local a = self.awareness[obs.id] or 0
		if obs.gain > 0 then
			a += obs.gain * dt
		else
			a -= sight.DecayPerSecond * dt
		end
		a = math.clamp(a, 0, 1.5)
		self.awareness[obs.id] = a
		seen[obs.id] = true
		if obs.gain > 0 and a > bestAwareness then
			best, bestAwareness = obs, a
		end
	end
	for id in pairs(self.awareness) do
		if not seen[id] then
			self.awareness[id] = nil
		end
	end

	if not best then
		return
	end
	local state = self.state
	if state == States.Chase or state == States.Attack or state == States.CheckHiding then
		return
	end

	if bestAwareness >= sight.ChaseAt or best.distance <= sight.InstantChaseRange then
		self:_enterChase(best.id, best.position, best.velocity, now, "sighted")
	elseif bestAwareness >= sight.SuspicionAt then
		if state == States.Suspicion then
			self.suspicionPos = best.position
			self.suspicionUntil = math.max(self.suspicionUntil, now + 0.5)
		elseif not (state == States.Investigate and self.investigateRush) then
			self:_enterSuspicion(best.position, now, "glimpse")
		end
	end
end

function MonsterBrain:attackResolved(hit, now)
	if self.state ~= States.Attack then
		return
	end
	if hit then
		self:_enterRecover(self.cfg.Recover.AfterAttackDuration, States.Search, now, "attack-hit")
	else
		self.state = States.Chase
		self.stateSince = now
	end
end

function MonsterBrain:hidingResolved(found, targetId, position, now)
	if self.state ~= States.CheckHiding then
		return
	end
	if found then
		self:_enterChase(targetId, position, nil, now, "found-hiding")
	else
		self.state = States.Search
		self.stateSince = now
		self.pauseUntil = now + 0.6
	end
end

-- Used by the service when movement keeps failing: pick a fresh nearby search.
function MonsterBrain:forceSearch(center, now)
	self:_enterSearch(center, false, now, "stuck")
end

---------------------------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------------------------

local function idle(self, extra)
	local intent = { state = self.state, goal = nil, speed = 0, listening = true }
	if extra then
		for k, v in pairs(extra) do
			intent[k] = v
		end
	end
	return intent
end

local function move(self, goal, speed, extra)
	self.goal = goal
	local intent = { state = self.state, goal = goal, speed = speed }
	if extra then
		for k, v in pairs(extra) do
			intent[k] = v
		end
	end
	return intent
end

--[[
	ctx = {
		position = v,
		pathFailed = boolean,      -- the last path to the current goal could not be computed
		target = { valid, visible, position, velocity, distance }   -- chase target, if any
	}
]]
function MonsterBrain:update(now, ctx)
	local cfg = self.cfg
	local pos = ctx.position
	local state = self.state

	local function arrived(goal, radius)
		return goal ~= nil and flatDistance(pos, goal) <= (radius or cfg.Path.ReachDistance + 0.5)
	end

	if state == States.Patrol then
		if self.listenUntil then
			if now < self.listenUntil then
				return idle(self)
			end
			self.listenUntil = nil
			self.patrolGoal = nil
		end
		if self.patrolGoal == nil or ctx.pathFailed or arrived(self.patrolGoal) then
			if self.patrolGoal ~= nil and not ctx.pathFailed and self.rng:chance(cfg.Patrol.ListenChance) then
				self.patrolGoal = nil
				self.listenUntil = now + self.rng:range(cfg.Patrol.ListenMin, cfg.Patrol.ListenMax)
				return idle(self)
			end
			self.patrolGoal = self.provider.patrolPoint(pos)
		end
		return move(self, self.patrolGoal, self:_speed("Patrol"))
	elseif state == States.Suspicion then
		if now >= self.suspicionUntil then
			if self.rng:chance(0.55) then
				self:_enterInvestigate(self.suspicionPos, cfg.Hearing.MidIntensity * 0.5, false, now, "suspicion-followup")
			elseif self.suspicionReturn == States.Search and self.searchPoints then
				self.state = States.Search
				self.stateSince = now
			else
				self:_enterPatrol(now, "suspicion-cleared")
			end
			return idle(self)
		end
		if flatDistance(pos, self.suspicionPos) > 4 then
			return move(self, self.suspicionPos, self:_speed("Suspicion"), { face = self.suspicionPos, listening = true })
		end
		return idle(self, { face = self.suspicionPos })
	elseif state == States.Investigate then
		if ctx.pathFailed or now - self.investigateSince > cfg.Investigate.MaxTime then
			self:_enterSearch(self.investigatePos, false, now, "investigate-abort")
			return idle(self)
		end
		if not self.arrivedAt and arrived(self.investigatePos, cfg.Investigate.ArriveRadius) then
			self.arrivedAt = now
		end
		if self.arrivedAt then
			if now - self.arrivedAt >= cfg.Investigate.ListenTime then
				self:_enterSearch(self.investigatePos, false, now, "investigate-done")
			end
			return idle(self)
		end
		local speed
		if self.investigateRush then
			speed = self:_speed("InvestigateHigh")
		elseif self.investigateIntensity >= cfg.Hearing.MidIntensity then
			speed = self:_speed("InvestigateMid")
		else
			speed = self:_speed("InvestigateLow")
		end
		return move(self, self.investigatePos, speed, { rush = self.investigateRush })
	elseif state == States.Search then
		if now > self.searchUntil or self.searchIndex > #self.searchPoints then
			if self.searchAfterChase then
				self:_enterRecover(cfg.Recover.Duration, States.Patrol, now, "search-exhausted")
			else
				self:_enterPatrol(now, "search-exhausted")
			end
			return idle(self)
		end
		if self.pauseUntil then
			if now < self.pauseUntil then
				return idle(self)
			end
			self.pauseUntil = nil
			self.searchIndex += 1
			return idle(self)
		end
		local point = self.searchPoints[self.searchIndex]
		if arrived(point.position) or ctx.pathFailed then
			if point.hidingSpotId and not ctx.pathFailed and self:_shouldCheckHiding(point) then
				self:_enter(States.CheckHiding, now, "check-hiding")
				self.hidingSpotId = point.hidingSpotId
				return idle(self, { action = "checkHiding", hidingSpotId = point.hidingSpotId })
			end
			self.pauseUntil = now + self.rng:range(cfg.Search.PauseMin, cfg.Search.PauseMax)
			return idle(self)
		end
		local speed = self:_speed("Search") * (if self.searchAfterChase then 1.2 else 1)
		return move(self, point.position, speed)
	elseif state == States.CheckHiding then
		if now - self.stateSince > cfg.Search.HidingCheckDuration + 4 then
			-- Service never resolved it (spot destroyed, etc.)
			self.state = States.Search
			self.stateSince = now
			self.searchIndex += 1
			return idle(self)
		end
		return idle(self, { action = "checkHiding", hidingSpotId = self.hidingSpotId })
	elseif state == States.Chase then
		local target = ctx.target
		if not target or not target.valid then
			self:_enterLost(now, "target-invalid")
			return idle(self)
		end
		if target.visible then
			self.lastKnown = target.position
			self.lastVelocity = target.velocity
			self.lastEvidenceAt = now
		end
		local sinceEvidence = now - self.lastEvidenceAt
		if sinceEvidence > cfg.Chase.LoseSightTime then
			self:_enterLost(now, "lost-sight")
			return idle(self)
		end
		if now - self.chaseSince > cfg.Chase.MaxDuration and not target.visible then
			self:_enterLost(now, "chase-timeout")
			return idle(self)
		end
		if target.visible and target.distance <= cfg.Chase.AttackRange then
			self:_enter(States.Attack, now, "in-range")
			self.attackSince = now
			return idle(self, { action = "attack", targetId = self.targetId, face = target.position })
		end
		local ramp = math.clamp((now - self.chaseSince) / cfg.Speeds.ChaseRampTime, 0, 1)
		local speed = (cfg.Speeds.ChaseStart + (cfg.Speeds.Chase - cfg.Speeds.ChaseStart) * ramp) * self.mods.speed
		local goal = if target.visible then target.position else self.lastKnown
		return move(self, goal, speed, { targetId = self.targetId, chasing = true, direct = target.visible })
	elseif state == States.Attack then
		if now - self.attackSince > cfg.Chase.AttackTimeout then
			self.state = States.Chase
			self.stateSince = now
			return idle(self)
		end
		return idle(self, { action = "attack", targetId = self.targetId, face = self.lastKnown })
	elseif state == States.Lost then
		if ctx.pathFailed and not self.lostFallback then
			self.lostFallback = true
			self.lostGoal = self.lastKnown
		elseif ctx.pathFailed or arrived(self.lostGoal) or now - self.stateSince > 12 then
			self:_enterSearch(self.lastKnown, true, now, "lost-arrived")
			return idle(self)
		end
		return move(self, self.lostGoal, self:_speed("Lost"))
	elseif state == States.Recover then
		if now >= self.recoverUntil then
			if self.recoverNext == States.Search then
				self:_enterSearch(self.lastKnown or pos, true, now, "recover-search")
			else
				self:_enterPatrol(now, "recovered")
			end
		end
		return idle(self)
	end

	self:_enterPatrol(now, "unknown-state")
	return idle(self)
end

function MonsterBrain:_shouldCheckHiding(point)
	local s = self.cfg.Search
	if self.provider.sawHidingEntry and self.provider.sawHidingEntry(point.hidingSpotId) then
		return true
	end
	if self.evidencePos and flatDistance(point.position, self.evidencePos) <= s.HidingEvidenceRadius then
		return true
	end
	local chance = s.HidingCheckChance * (if self.searchAfterChase then 1.6 else 1)
	return self.rng:chance(chance)
end

return MonsterBrain
