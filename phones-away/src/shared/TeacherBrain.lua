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

---------------------------------------------------------------------------------------------
-- Navigation: the 12 desks (+ chairs) are obstacles. A straight line from the board to the
-- door, or from the back aisle to the board, cuts right through them, so when the direct
-- line is blocked she routes through the aisles (shortest path over a few lane nodes).
---------------------------------------------------------------------------------------------

local DESK_HALF_X, DESK_FRONT, DESK_BACK = 2, 1.3, 3.45 -- desk top + chair, around (column, row)
local BODY = 1.2 -- her half-width (+ a little room)

local function deskRects(L)
	local rects = {}
	for _, z in ipairs(L.DeskRows) do
		for _, x in ipairs(L.DeskColumns) do
			table.insert(rects, { x - DESK_HALF_X - BODY, z - DESK_FRONT - BODY, x + DESK_HALF_X + BODY, z + DESK_BACK + BODY })
		end
	end
	return rects
end

local function inside(r, x, z)
	return x > r[1] and x < r[3] and z > r[2] and z < r[4]
end

-- Slab test: does the segment (x0, z0) -> (x1, z1) pass through rectangle r?
local function segmentHits(r, x0, z0, x1, z1)
	local t0, t1 = 0, 1
	local d = { x1 - x0, z1 - z0 }
	local o = { x0, z0 }
	local lo, hi = { r[1], r[2] }, { r[3], r[4] }
	for axis = 1, 2 do
		if math.abs(d[axis]) < 1e-9 then
			if o[axis] <= lo[axis] or o[axis] >= hi[axis] then
				return false
			end
		else
			local a = (lo[axis] - o[axis]) / d[axis]
			local b = (hi[axis] - o[axis]) / d[axis]
			if a > b then
				a, b = b, a
			end
			t0, t1 = math.max(t0, a), math.min(t1, b)
			if t0 >= t1 then
				return false
			end
		end
	end
	return true
end

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
	self._rects = deskRects(layout)
	-- Lane nodes: where each aisle meets the front / back aisle, plus a lane down the right
	-- side of the room (toward the door).
	local laneX = table.clone(layout.Aisles)
	local maxColumn = -math.huge
	for _, x in ipairs(layout.DeskColumns) do
		maxColumn = math.max(maxColumn, x)
	end
	table.insert(laneX, maxColumn + DESK_HALF_X + BODY + 2.8)
	self._nodes = {}
	for _, x in ipairs(laneX) do
		table.insert(self._nodes, { x, layout.FrontAisleZ })
		table.insert(self._nodes, { x, layout.BackAisleZ })
	end
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

function TeacherBrain:_clear(x0, z0, x1, z1)
	for _, r in ipairs(self._rects) do
		-- A rectangle she is already standing in can't block her way out of it.
		if not inside(r, x0, z0) and segmentHits(r, x0, z0, x1, z1) then
			return false
		end
	end
	return true
end

-- Next point to walk to on the way to (tx, tz): the target itself when the way is clear.
function TeacherBrain:_nextWaypoint(tx, tz)
	if self:_clear(self.x, self.z, tx, tz) then
		return tx, tz
	end
	local nodes = { { self.x, self.z } }
	for _, n in ipairs(self._nodes) do
		table.insert(nodes, n)
	end
	table.insert(nodes, { tx, tz })
	local goal = #nodes
	local dist, prev, done = { [1] = 0 }, {}, {}
	while true do
		local best, bestD = nil, math.huge
		for i = 1, #nodes do
			if not done[i] and dist[i] and dist[i] < bestD then
				best, bestD = i, dist[i]
			end
		end
		if not best or best == goal then
			break
		end
		done[best] = true
		local a = nodes[best]
		for i = 2, #nodes do
			if not done[i] and i ~= best then
				local b = nodes[i]
				if self:_clear(a[1], a[2], b[1], b[2]) then
					local d = bestD + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
					if d < (dist[i] or math.huge) then
						dist[i], prev[i] = d, best
					end
				end
			end
		end
	end
	if not dist[goal] then
		return tx, tz -- no route found: fall back to the straight line
	end
	-- Walk back from the goal to the first step that actually moves her.
	local path = {}
	local i = goal
	while i and i ~= 1 do
		table.insert(path, 1, i)
		i = prev[i]
	end
	for _, index in ipairs(path) do
		local n = nodes[index]
		if (n[1] - self.x) ^ 2 + (n[2] - self.z) ^ 2 > 0.01 then
			return n[1], n[2]
		end
	end
	return tx, tz
end

-- Like _moveToward, but around the desks. Returns arrived (at the target), heading.
function TeacherBrain:_navTo(tx, tz, speed, dt)
	local wx, wz = self:_nextWaypoint(tx, tz)
	local arrived, heading = self:_moveToward(wx, wz, speed, dt)
	if wx ~= tx or wz ~= tz then
		return false, heading
	end
	return arrived, heading
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
		self:_navTo(L.BoardSpot[1], L.BoardSpot[2], cfg.WalkSpeed, dt)
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
		self:_navTo(tx, L.LectureSpot[2], cfg.WalkSpeed * 0.4, dt)
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
			local arrived, moveHeading = self:_navTo(wp[1], wp[2], cfg.WalkSpeed, dt)
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
		self:_navTo(L.LectureSpot[1] + math.sin(now * 1.3) * 10, L.LectureSpot[2] + 3, cfg.WalkSpeed, dt)
		self.targetHeading = Detection.wrap(now * 2.6)
	elseif self.phase == "LunchCheck" then
		local arrived = self:_navTo(L.DoorSpot[1] - 2, L.DoorSpot[2], cfg.WalkSpeed * 1.2, dt)
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
