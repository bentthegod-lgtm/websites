--[[
	TeacherBrain - where the teacher stands, where she looks and how alert she is, per lesson
	phase. Pure (numbers only), driven by RoundService at GameConfig.TickRate and unit-tested
	in Lune.

	Phases
	  Board       writing on the whiteboard, back to the class (safe). Every few seconds she
	              may glance over her shoulder; the glance is telegraphed by a pause first.
	  Lecture     front of the room facing the class, sweeping her gaze slowly; she drifts
	              toward the most suspicious student.
	  Walk        walks the aisles, scanning desks left / right, checking desks up close.
	  Quiz        front and centre, watching everyone.
	  FireDrill   chaos: spins around looking at everything and nothing.
	  LunchCheck  walks to the door and peeks into the hallway (back to the class).

	Overrides: distract (paper airplane noise -> she turns toward it), caught (points at the
	student), nap (sleepy substitute).

	Exposed state each tick: x, z, heading, fov, sight, hearing, checking, pose, warn.
]]

local Detection = require(script.Parent.Detection)

local TeacherBrain = {}
TeacherBrain.__index = TeacherBrain

local rad = math.rad

--[[
	cfg = TeacherConfig, layout = GameConfig.Classroom, rng = Rng
	opts = { substitute = bool, detection = number (global multiplier), turnScale = number }
]]
function TeacherBrain.new(cfg, layout, rng, opts)
	opts = opts or {}
	local self = setmetatable({}, TeacherBrain)
	self.cfg = cfg
	self.layout = layout
	self.rng = rng
	self.substitute = opts.substitute == true
	self.detection = opts.detection or 1
	self.turnScale = opts.turnScale or 1
	self.x, self.z = layout.BoardSpot[1], layout.BoardSpot[2]
	self.heading = math.pi
	self.targetHeading = math.pi
	self.fov = cfg.Sight.FovDegrees
	self.phase = "Board"
	self.pose = "Write"
	self.sight, self.hearing = 0, 1
	self.checking = false
	self.warn = false
	self.path = nil
	self.pathIndex = 1
	self.lookFlip = 1
	self.nextLookFlip = 0
	self.nextGlance = 0
	self.glanceState = nil
	self.napUntil = 0
	self.nextNap = math.huge
	return self
end

function TeacherBrain:setDetection(multiplier)
	self.detection = multiplier
end

local function between(rng, range)
	return rng:range(range[1], range[2])
end

-- Path through the aisles: front aisle -> down one aisle -> back aisle -> up another.
function TeacherBrain:_makeWalkPath()
	local L = self.layout
	local aisles = L.Aisles
	local a = aisles[self.rng:integer(1, #aisles)]
	local b = aisles[self.rng:integer(1, #aisles)]
	if b == a then
		b = aisles[(table.find(aisles, a) % #aisles) + 1]
	end
	return {
		{ a, L.FrontAisleZ },
		{ a, L.BackAisleZ },
		{ b, L.BackAisleZ },
		{ b, L.FrontAisleZ },
		{ L.LectureSpot[1], L.LectureSpot[2] },
	}
end

function TeacherBrain:setPhase(phase, now)
	self.phase = phase
	self.glanceState = nil
	self.warn = false
	self.path = nil
	if phase == "Board" then
		self.nextGlance = now + between(self.rng, self.cfg.Board.GlanceEvery)
	elseif phase == "Walk" then
		self.path = self:_makeWalkPath()
		self.pathIndex = 1
	end
	if self.substitute and self.nextNap == math.huge then
		self.nextNap = now + 8
	end
end

-- A paper airplane landed at (x, z): she turns toward the noise and stops moving for a bit.
function TeacherBrain:distract(x, z, now, seconds)
	if now < (self.caughtUntil or 0) then
		return false
	end
	self.distractX, self.distractZ = x, z
	self.distractUntil = now + seconds
	return true
end

function TeacherBrain:caught(x, z, now)
	self.caughtX, self.caughtZ = x, z
	self.caughtUntil = now + 2.2
	self.distractUntil = nil
end

function TeacherBrain:isDistracted(now)
	return self.distractUntil ~= nil and now < self.distractUntil
end

function TeacherBrain:_moveToward(tx, tz, speed, dt)
	local dx, dz = tx - self.x, tz - self.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 0.05 then
		return true, nil
	end
	local step = math.min(dist, speed * dt)
	self.x += dx / dist * step
	self.z += dz / dist * step
	return dist - step < 0.05, math.atan2(dx, dz)
end

--[[
	ctx = { focus = { x, z } or nil } (the most suspicious student, from the service)
	Returns self for chaining.
]]
function TeacherBrain:update(dt, now, ctx)
	ctx = ctx or {}
	local cfg = self.cfg
	local phaseCfg = cfg.Phases[self.phase] or cfg.Phases.Lecture
	local turn = cfg.Turn.Lecture
	local sight, hearing = phaseCfg.Sight, phaseCfg.Hearing
	local L = self.layout
	self.checking = false
	self.warn = false

	if self.phase == "Board" then
		self.pose = "Write"
		self:_moveToward(L.BoardSpot[1], L.BoardSpot[2], cfg.WalkSpeed, dt)
		self.targetHeading = math.pi
		local g = self.glanceState
		if not g and now >= self.nextGlance then
			if self.rng:chance(cfg.Board.GlanceChance) then
				self.glanceState = { phase = "warn", untilT = now + cfg.Board.WarnSeconds }
			else
				self.nextGlance = now + between(self.rng, cfg.Board.GlanceEvery)
			end
		elseif g and g.phase == "warn" then
			self.warn = true
			self.pose = "Pause"
			if now >= g.untilT then
				self.glanceState = { phase = "glance", untilT = now + cfg.Board.GlanceSeconds, side = if self.rng:chance(0.5) then 1 else -1 }
			end
		elseif g and g.phase == "glance" then
			self.pose = "Glance"
			self.targetHeading = rad(10) * g.side
			turn = cfg.Turn.Glance
			-- Sight ramps in as she turns round.
			local facing = 1 - math.abs(Detection.wrap(self.heading)) / math.pi
			sight = cfg.Board.GlanceSight * math.clamp(facing * 1.5 - 0.3, 0, 1)
			if now >= g.untilT then
				self.glanceState = nil
				self.nextGlance = now + between(self.rng, cfg.Board.GlanceEvery)
			end
		end
		if not self.glanceState or self.glanceState.phase ~= "glance" then
			-- Turning back to the board: she stops seeing as soon as she faces away.
			local facing = 1 - math.abs(Detection.wrap(self.heading)) / math.pi
			sight = cfg.Board.GlanceSight * math.clamp(facing * 1.5 - 0.6, 0, 1)
			turn = cfg.Turn.Glance
			if sight > 0.01 and not self.glanceState then
				self.pose = "Glance" -- still turning back to the board
			end
		end
	elseif self.phase == "Lecture" or self.phase == "Quiz" then
		self.pose = if self.phase == "Quiz" then "Quiz" else "Lecture"
		local tx = L.LectureSpot[1] + (if self.phase == "Lecture" then math.sin(now * 0.3) * cfg.LecturePace else 0)
		self:_moveToward(tx, L.LectureSpot[2], cfg.WalkSpeed * 0.4, dt)
		self.targetHeading = rad(math.sin(now * 0.45) * cfg.LectureSweep)
		if ctx.focus then
			self.targetHeading = Detection.headingTo(self.x, self.z, ctx.focus[1], ctx.focus[2])
		end
	elseif self.phase == "Walk" then
		self.pose = "Walk"
		turn = cfg.Turn.Walk
		self.checking = true
		local path = self.path or self:_makeWalkPath()
		self.path = path
		local wp = path[self.pathIndex]
		if wp then
			local arrived, moveHeading = self:_moveToward(wp[1], wp[2], cfg.WalkSpeed, dt)
			if moveHeading then
				if now >= self.nextLookFlip then
					self.lookFlip = -self.lookFlip
					self.nextLookFlip = now + 1.6
				end
				self.targetHeading = moveHeading + rad(38) * self.lookFlip
			end
			if arrived then
				self.pathIndex += 1
			end
		else
			-- Finished a lap: start another.
			self.path = self:_makeWalkPath()
			self.pathIndex = 1
			self.targetHeading = 0
		end
		if ctx.focus then
			local toFocus = Detection.headingTo(self.x, self.z, ctx.focus[1], ctx.focus[2])
			self.targetHeading = toFocus
		end
	elseif self.phase == "FireDrill" then
		self.pose = "Panic"
		turn = cfg.Turn.Distract
		self:_moveToward(L.LectureSpot[1] + math.sin(now * 1.3) * 10, L.LectureSpot[2] + 3, cfg.WalkSpeed, dt)
		self.targetHeading = Detection.wrap(now * 2.6)
	elseif self.phase == "LunchCheck" then
		local arrived = self:_moveToward(L.DoorSpot[1] - 2, L.DoorSpot[2], cfg.WalkSpeed * 1.2, dt)
		self.pose = if arrived then "Door" else "Walk"
		turn = cfg.Turn.Walk
		self.targetHeading = if arrived then math.pi / 2 else Detection.headingTo(self.x, self.z, L.DoorSpot[1], L.DoorSpot[2])
	end

	-- Sleepy substitute: naps now and then (sees nothing, barely hears).
	if self.substitute and self.phase ~= "FireDrill" then
		local sub = cfg.Events.Substitute
		if now >= self.nextNap and now >= self.napUntil then
			self.napUntil = now + sub.NapSeconds
			self.nextNap = self.napUntil + between(self.rng, sub.NapEvery)
		end
		if now < self.napUntil then
			self.pose = "Nap"
			sight, hearing = 0, hearing * 0.3
		end
	end

	-- Overrides
	if self.caughtUntil and now < self.caughtUntil then
		self.pose = "Point"
		turn = cfg.Turn.Caught
		self.targetHeading = Detection.headingTo(self.x, self.z, self.caughtX, self.caughtZ)
		self.checking = false
	elseif self:isDistracted(now) then
		self.pose = "Distracted"
		turn = cfg.Turn.Distract
		self.targetHeading = Detection.headingTo(self.x, self.z, self.distractX, self.distractZ)
		self.checking = false
	end

	self.heading = Detection.turnToward(self.heading, self.targetHeading, rad(turn * self.turnScale) * dt)
	self.sight = sight * self.detection
	self.hearing = hearing * self.detection
	return self
end

-- Observer table for Detection.gain.
function TeacherBrain:observer()
	return { x = self.x, z = self.z, heading = self.heading, fov = self.fov, sight = self.sight, hearing = self.hearing, checking = self.checking }
end

return TeacherBrain
