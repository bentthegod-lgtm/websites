--[[
	BotBrain - turns a kart state + the track into an input for KartPhysics (the same input
	a player's controller produces). Bots therefore drive with exactly the same physics as
	players. Variation comes ONLY from driving behaviour (look-ahead, line choice, drift
	habit, throttle discipline, small steering noise), never from kart stats.

	BotBrain.new(seed) -> memory
	BotBrain.think(memory, state, track, dt) -> input { gas, brake, steer, drift }
]]

local KartPhysics = require(script.Parent.KartPhysics)
local KartStats = require(script.Parent.Config.KartStats)
local Rng = require(script.Parent.Rng)

local BotBrain = {}

function BotBrain.new(seed, skill)
	local rng = Rng.new(seed or 1)
	skill = skill or rng:NextNumber(0.85, 1)
	return {
		rng = rng,
		skill = skill,
		hint = nil,
		look = rng:NextNumber(0.5, 0.62), -- look-ahead seconds
		lineBias = rng:NextNumber(-5, 5), -- preferred lateral offset
		lineGain = rng:NextNumber(1400, 2200), -- how much it cuts to the inside
		driftHabit = 0.55 + 0.45 * skill, -- chance to drift a long corner
		throttle = 0.955 + 0.045 * skill,
		noise = 0,
		noiseT = 0,
		drifting = false,
		driftWant = false,
		driftHold = 0,
		progress = 0,
	}
end

local function curvatureAhead(track, d, length)
	local sum, peak = 0, 0
	local n = 0
	local step = 12
	for x = 0, length, step do
		local c = track:at(d + x).curvature
		sum += c
		n += 1
		if math.abs(c) > math.abs(peak) then
			peak = c
		end
	end
	return sum / math.max(1, n), peak
end

function BotBrain.think(mem, state, track, dt)
	local hit = track:project(state.pos, mem.hint)
	if not hit then
		return { gas = 1, brake = 0, steer = 0, drift = false }
	end
	mem.hint = hit.index
	mem.progress = hit.dist
	local speed = KartPhysics.speed(state)
	local s = track:at(hit.dist)
	local half = s.w / 2

	-- racing line: cut to the inside of what is coming
	local avg, peak = curvatureAhead(track, hit.dist + 10, 90)
	local inside = math.clamp(avg * mem.lineGain, -(half - 9), half - 9)
	mem.noiseT -= dt
	if mem.noiseT <= 0 then
		mem.noiseT = mem.rng:NextNumber(0.6, 1.8)
		mem.noise = mem.rng:NextNumber(-1, 1) * (1.15 - mem.skill) * 10
	end
	local lateral = math.clamp(inside + mem.lineBias * 0.5 + mem.noise, -(half - 7), half - 7)
	local lookDist = 16 + speed * mem.look
	local target = track:point(hit.dist + lookDist, lateral)

	-- steering toward the target
	local fwd = KartPhysics.forward(state.yaw)
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	local to = Vector3.new(target.X - state.pos.X, 0, target.Z - state.pos.Z)
	local angle = math.atan2(to:Dot(right), to:Dot(fwd))
	local steer = math.clamp(angle * 2.6, -1, 1)

	-- wrong way / stuck against something: turn hard
	local heading = fwd:Dot(s.flat)
	if heading < -0.2 then
		steer = if to:Dot(right) >= 0 then 1 else -1
	end

	-- drifting long corners
	local sharp = math.abs(peak)
	local long = math.abs(avg)
	if not mem.drifting then
		local wantDrift = long > 1 / 240 and sharp > 1 / 160 and speed > KartStats.DriftMinSpeed + 14 and math.abs(angle) < 0.5
		if wantDrift and mem.rng:NextNumber() < mem.driftHabit * dt * 6 then
			mem.drifting = true
			mem.driftDir = if avg > 0 then 1 else -1
			mem.driftHold = 0
		end
	else
		mem.driftHold += dt
		local straightening = long < 1 / 420 or (avg > 0) ~= (mem.driftDir > 0)
		local charged = state.driftLevel >= 2 and long < 1 / 300
		if straightening or charged or mem.driftHold > 4 or speed < KartStats.DriftMinSpeed then
			mem.drifting = false
		end
	end
	local drift = mem.drifting
	if drift and state.drift == 0 and state.grounded then
		-- steer into the corner when the hop lands so the drift starts
		steer = mem.driftDir
	elseif drift and state.drift ~= 0 then
		-- in a drift, steering is "tighter / wider" around the drift's own arc
		local want = math.clamp(angle * 2.2, -1, 1)
		steer = want
		if state.drift ~= mem.driftDir then
			mem.drifting = false
			drift = false
		end
	end

	-- throttle: lift for very sharp stuff, always floor it on straights
	local gas = mem.throttle
	local brake = 0
	local turnCap = KartStats.TurnRateHigh / math.max(sharp, 1e-4)
	if not drift and speed > turnCap * 1.12 and math.abs(angle) > 0.3 then
		gas = 0.2
	end
	if math.abs(angle) > 1.1 and speed > 30 then
		gas = 0
		brake = 0.6
	end
	if state.stuckT > 0.8 then
		gas = 0
		brake = 1
		steer = -steer
	end
	return { gas = gas, brake = brake, steer = steer, drift = drift }
end

return BotBrain
