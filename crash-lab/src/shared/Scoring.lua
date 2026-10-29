--[[
	Scoring - the run tracker. Pure: the server feeds it what IT observed (sampled dummy
	positions, contacts it detected), and it turns that into a normalised, capped score.
	Nothing here ever takes a number from a client.

	Run.new(origin, forward, opts)
	  :sample(position, t)          -> "ok" | "anomaly"   (impossible jumps are rejected)
	  :impact(key, speed, t, kind)  -> tier name or nil   (debounced, per-object and per-run caps)
	  :award(kind, id, points)      -> true once per id   (targets, props, rings, zones, objectives)
	  :breakChain(t)                -> chain length (Destruction combo; capped points)
	  :status(t)                    -> nil | "settled" | "stuck" | "timeout"
	  :result(mult)                 -> breakdown table with total score and coins

	opts.tuning (per course, CourseConfig.Courses[*].Tuning) can override DistancePoints /
	HeightPoints and turn on the Free-Fall Bonus (height lost from the run's peak) and the
	destruction Combo; opts.limits replaces GameConfig.Run (per-course run limits).

	Distance is the furthest VALID point down the course (projected on `forward`), never
	the raw path length, so wiggling in place earns nothing. Height is the highest valid
	sample above the floor.
]]

local ScoringConfig = require(script.Parent.Config.ScoringConfig)
local GameConfig = require(script.Parent.Config.GameConfig)

local Scoring = {}

local Run = {}
Run.__index = Run
Scoring.Run = Run

local IMPACT = ScoringConfig.Impact
local RUN = GameConfig.Run

-- opts: { floorY, maxSpeed, impactCap, startTime, tuning, limits }
function Run.new(origin, forward, opts)
	opts = opts or {}
	local self = setmetatable({}, Run)
	self.tuning = opts.tuning or {}
	self.limits = opts.limits or RUN
	self.origin = origin
	self.forward = Vector3.new(forward.X, 0, forward.Z).Unit
	self.floorY = opts.floorY or 0
	self.maxSpeed = opts.maxSpeed or ScoringConfig.MaxLaunchSpeed
	self.impactCap = opts.impactCap or IMPACT.BaseCap
	self.startTime = opts.startTime or 0
	self.last = origin
	self.lastT = self.startTime
	self.distance = 0
	self.maxHeight = 0
	self.samples = 0
	self.anomalies = 0
	self.speed = 0
	self.stillSince = nil
	self.history = {} -- recent { t, pos } for stuck detection
	self.impacts = {} -- list of { key, tier, points }
	self.impactCount = 0
	self.perObject = {}
	self.lastHit = {}
	self.floorHits = 0
	self.awards = {} -- [kind..":"..id] = points
	self.awardList = {}
	self.voided = false
	self.peakY = origin.Y
	self.freeFall = 0 -- largest drop below the run's highest point so far
	self.chain = 0
	self.chainLast = nil
	self.comboBest = 0
	self.comboPoints = 0
	return self
end

-- Largest believable move between two samples: the fastest launch plus gravity's
-- contribution over the gap, with headroom for physics bounces.
function Run:maxStep(dt)
	return (self.maxSpeed * 1.35 + 196.2 * dt + 20) * dt + 2
end

function Run:sample(position, t)
	local dt = math.max(1e-3, t - self.lastT)
	local step = (position - self.last).Magnitude
	if step ~= step or step > self:maxStep(dt) then
		self.anomalies += 1
		if self.anomalies >= self.limits.AnomalyLimit then
			self.voided = true
		end
		-- The anomalous point is ignored entirely (no distance, height or speed from it).
		-- lastT stays with the last accepted point: the next sample is measured from that
		-- point over the real elapsed time, so one physics glitch can't cascade into a void.
		return "anomaly"
	end
	self.samples += 1
	self.speed = step / dt
	self.last = position
	self.lastT = t
	local forwardDistance = (position - self.origin):Dot(self.forward)
	if forwardDistance > self.distance then
		self.distance = forwardDistance
	end
	local height = position.Y - self.floorY
	if height > self.maxHeight then
		self.maxHeight = math.min(height, ScoringConfig.MaxCountedHeight)
	end
	if position.Y > self.peakY then
		self.peakY = position.Y
	end
	if self.peakY - position.Y > self.freeFall then
		self.freeFall = self.peakY - position.Y
	end
	local limits = self.limits
	if self.speed < limits.SettleSpeed then
		self.stillSince = self.stillSince or t
	else
		self.stillSince = nil
	end
	table.insert(self.history, { t = t, pos = position })
	while #self.history > 0 and t - self.history[1].t > limits.StuckWindow do
		table.remove(self.history, 1)
	end
	return "ok"
end

function Scoring.tierFor(speed)
	if type(speed) ~= "number" or speed ~= speed or speed < IMPACT.MinSpeed then
		return nil
	end
	local chosen
	for _, tier in ipairs(IMPACT.Tiers) do
		if speed >= tier.Speed then
			chosen = tier
		end
	end
	return chosen
end

-- kind: "Floor" groups every floor contact under one key with its own cap.
function Run:impact(key, speed, t, kind)
	if self.voided or self.impactCount >= self.impactCap then
		return nil
	end
	local tier = Scoring.tierFor(speed)
	if not tier then
		return nil
	end
	if kind == "Floor" then
		key = "Floor"
		if self.floorHits >= IMPACT.FloorMax then
			return nil
		end
	end
	if self.lastHit[key] and t - self.lastHit[key] < IMPACT.Debounce then
		return nil
	end
	if (self.perObject[key] or 0) >= IMPACT.PerObjectMax and kind ~= "Floor" then
		return nil
	end
	self.lastHit[key] = t
	self.perObject[key] = (self.perObject[key] or 0) + 1
	if kind == "Floor" then
		self.floorHits += 1
	end
	self.impactCount += 1
	table.insert(self.impacts, { key = key, tier = tier.Name, points = tier.Points })
	return tier.Name
end

-- One-off bonuses: kind "Target" | "Prop" | "Ring" | "Zone" | "Objective" | "Distance".
function Run:award(kind, id, points)
	if self.voided then
		return false
	end
	local k = kind .. ":" .. tostring(id)
	if self.awards[k] then
		return false
	end
	self.awards[k] = points
	table.insert(self.awardList, { kind = kind, id = id, points = points })
	return true
end

function Run:has(kind, id)
	return self.awards[kind .. ":" .. tostring(id)] ~= nil
end

function Run:count(kind)
	local n = 0
	for _, a in ipairs(self.awardList) do
		if a.kind == kind then
			n += 1
		end
	end
	return n
end

-- Destruction combo: a break within Combo.Window of the previous one extends the chain.
-- Every break from the 2nd in a chain adds min(chain - 1, MaxStep) * PerStep points, and
-- the run's combo points never exceed Combo.Cap.
function Run:breakChain(t)
	local combo = self.tuning.Combo
	if not combo or self.voided then
		return 0
	end
	if self.chainLast and t - self.chainLast <= combo.Window then
		self.chain += 1
	else
		self.chain = 1
	end
	self.chainLast = t
	self.comboBest = math.max(self.comboBest, self.chain)
	if self.chain >= 2 then
		self.comboPoints = math.min(combo.Cap, self.comboPoints + math.min(self.chain - 1, combo.MaxStep) * combo.PerStep)
	end
	return self.chain
end

-- Free-Fall Bonus points for the run so far (0 where the course has none).
function Run:freeFallPoints()
	local ff = self.tuning.FreeFall
	if not ff or self.voided or self.freeFall < (ff.Min or 0) then
		return 0
	end
	return math.floor(math.min(self.freeFall, ff.Max) * ff.PerStud)
end

function Run:status(t)
	local limits = self.limits
	local elapsed = t - self.startTime
	if elapsed >= limits.MaxDuration then
		return "timeout"
	end
	if elapsed >= limits.MinAirTime and self.stillSince and t - self.stillSince >= limits.SettleTime then
		return "settled"
	end
	if elapsed >= limits.StuckWindow and #self.history >= 2 then
		local first = self.history[1]
		if t - first.t >= limits.StuckWindow * 0.9 and (self.last - first.pos).Magnitude < limits.StuckDistance then
			return "stuck"
		end
	end
	return nil
end

-- mult: { impact, bonus, featured, coins, featuredId }
function Run:result(mult)
	mult = mult or {}
	local impactMult = mult.impact or 1
	local bonusMult = mult.bonus or 1
	local tuning = self.tuning
	local distancePts = math.floor(math.max(0, self.distance) * (tuning.DistancePoints or ScoringConfig.DistancePoints))
	local heightPts = math.floor(math.max(0, self.maxHeight) * (tuning.HeightPoints or ScoringConfig.HeightPoints))
	local impactPts = 0
	local tiers = {}
	for _, i in ipairs(self.impacts) do
		impactPts += i.points
		tiers[i.tier] = (tiers[i.tier] or 0) + 1
	end
	impactPts = math.floor(impactPts * impactMult)
	local bonusPts = 0
	local featuredPts = 0
	local lines = {}
	for _, a in ipairs(self.awardList) do
		local pts = math.floor(a.points * bonusMult)
		if a.kind == "Objective" and a.id == mult.featuredId then
			local extra = math.floor(pts * ((mult.featured or 2) - 1))
			featuredPts += extra
		end
		bonusPts += pts
		table.insert(lines, { kind = a.kind, id = a.id, points = pts })
	end
	local score = distancePts + heightPts + impactPts + bonusPts + featuredPts
	local coins
	if self.voided then
		score = 0
		coins = ScoringConfig.VoidCoins
	else
		coins = math.clamp(math.floor(score * ScoringConfig.CoinsPerPoint * (mult.coins or 1)), ScoringConfig.MinCoins, ScoringConfig.MaxCoinsPerRun)
	end
	return {
		score = score,
		coins = coins,
		distance = math.floor(self.distance * 10) / 10,
		height = math.floor(self.maxHeight * 10) / 10,
		impacts = self.impactCount,
		impactTiers = tiers,
		distancePoints = distancePts,
		heightPoints = heightPts,
		impactPoints = impactPts,
		bonusPoints = bonusPts,
		featuredPoints = featuredPts,
		bonuses = lines,
		voided = self.voided,
		anomalies = self.anomalies,
		freeFall = math.floor(self.freeFall * 10) / 10,
		comboBest = self.comboBest,
		comboPoints = self.comboPoints,
	}
end

-- Ring crossing: did the segment a -> b cross the ring's plane inside its radius?
-- Rings face down the course (normal = +Z).
function Scoring.crossesRing(a, b, center, radius)
	local da, db = a.Z - center.Z, b.Z - center.Z
	if da == db or (da > 0 and db > 0) or (da < 0 and db < 0) then
		return false
	end
	local f = da / (da - db)
	local p = a + (b - a) * f
	local offset = Vector3.new(p.X - center.X, p.Y - center.Y, 0)
	return offset.Magnitude <= radius
end

function Scoring.insideZone(position, center, radius)
	local dx, dz = position.X - center.X, position.Z - center.Z
	return dx * dx + dz * dz <= radius * radius and math.abs(position.Y - center.Y) < 8
end

return Scoring
