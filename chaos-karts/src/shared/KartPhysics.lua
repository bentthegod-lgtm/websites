--[[
	KartPhysics - the arcade kart controller. PURE and DETERMINISTIC: no Instances, no
	services, no randomness. The same code drives
	  * the local player's kart on its client (client-predicted, every frame),
	  * the server's bots,
	  * the unit tests and the headless harness.

	KartPhysics.step(state, input, ground, dt)
	  state  from KartPhysics.new(cframe)
	  input  { gas = 0..1, brake = 0..1, steer = -1..1 (+ = right), drift = bool (held) }
	  ground the groundQuery interface:
	           ground:ground(probe: Vector3) -> height, normal, surface, course | nil
	             (the highest walkable surface at or below `probe`; surface is "Road",
	             "Offroad", "Boost" or "Jump"; course is "main", a shortcut id or "floor")
	           ground:walls(pos: Vector3, radius) -> pushNormal: Vector3?, depth
	         In the game: workspace raycasts against the track (client/WorldQuery).
	         Bots / harness / tests: the analytic TrackQuery built from the track data.
	  dt     a fixed step (KartStats.FixedStep); use KartPhysics.advance for frame times.

	Feel features: acceleration curve, top speed, braking and reverse, speed-sensitive
	steering, grip with a slight slide (lateral decay with partial transfer back into
	forward speed), hop, drift with 3 mini-turbo levels, boost pads, start boost, air time
	with air control, landing squash, slope gravity and alignment to slopes / banking, wall
	glances, off-road slowdown, kart-to-kart bumps and the KartEffects (spin out, slow,
	launch, freeze, knockback).

	Every vehicle uses KartStats: physics are identical for everyone.
]]

local KartStats = require(script.Parent.Config.KartStats)

local KartPhysics = {}
KartPhysics.Stats = KartStats

local S = KartStats
local Y = Vector3.new(0, 1, 0)
local ZERO = Vector3.new(0, 0, 0)

KartPhysics.Flags = {
	Drifting = 1,
	DriftRight = 2,
	Level1 = 4,
	Level2 = 8, -- level 3 = Level1 + Level2
	Boost = 16,
	Air = 32,
	Ghost = 64,
	Spin = 128,
	Frozen = 256,
	Braking = 512,
	Offroad = 1024,
}
local F = KartPhysics.Flags

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

function KartPhysics.forward(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function KartPhysics.yawOf(look)
	return math.atan2(-look.X, -look.Z)
end

-- A fresh kart at a CFrame (or a position + yaw).
function KartPhysics.new(where, yaw)
	local pos
	if typeof(where) == "CFrame" then
		pos = where.Position
		yaw = KartPhysics.yawOf(where.LookVector)
	else
		pos = where or ZERO
	end
	return {
		pos = pos,
		vel = ZERO,
		yaw = yaw or 0,
		yawRate = 0,
		up = Y,
		grounded = false,
		airTime = 0,
		surface = "Road",
		course = "main",
		drift = 0, -- -1 left, +1 right, 0 none
		driftT = 0,
		driftLevel = 0,
		hopT = math.huge, -- seconds since the last hop
		driftHeld = false,
		boostT = 0,
		spinT = 0,
		frozenT = 0,
		slowT = 0,
		slowMul = 1,
		ghostT = 0,
		stallT = 0,
		squash = 0,
		stuckT = 0,
		offCourseT = 0,
		time = 0,
		events = {},
	}
end

function KartPhysics.speed(state)
	return Vector3.new(state.vel.X, 0, state.vel.Z).Magnitude
end

-- Signed speed along the kart's heading.
function KartPhysics.forwardSpeed(state)
	return state.vel:Dot(KartPhysics.forward(state.yaw))
end

local function event(state, name, value)
	table.insert(state.events, { name = name, value = value })
end

function KartPhysics.boost(state, seconds, source)
	if seconds > state.boostT then
		state.boostT = seconds
	end
	event(state, "boost", source or "boost")
end

-- Samples the ground under the four wheel points.
local function probe(state, ground)
	local fwd = KartPhysics.forward(state.yaw)
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	local base = state.pos.Y - S.RideHeight + S.StepUp
	local heights, normals = 0, ZERO
	local found = 0
	local boost, jump, offroad, road = false, false, 0, 0
	local course = nil
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = state.pos + fwd * (S.WheelZ * sz) + right * (S.WheelX * sx)
			local h, n, surface, c = ground:ground(Vector3.new(p.X, base, p.Z))
			if h then
				found += 1
				heights += h
				normals += n
				if surface == "Boost" then
					boost = true
				elseif surface == "Jump" then
					jump = true
				elseif surface == "Offroad" then
					offroad += 1
				else
					road += 1
				end
				if c ~= "floor" or course == nil then
					course = c
				end
			end
		end
	end
	if found < 2 then
		return nil
	end
	local surface = if jump then "Jump" elseif boost then "Boost" elseif offroad > road then "Offroad" else "Road"
	return heights / found, (normals / found).Unit, surface, course
end

local function resolveWalls(state, ground)
	for _ = 1, 2 do
		local normal, depth = ground:walls(state.pos, S.Radius)
		if not normal or depth <= 0 then
			return
		end
		state.pos += normal * depth
		local v = state.vel
		local vn = v:Dot(normal)
		if vn < 0 then
			local planar = Vector3.new(v.X, 0, v.Z)
			local speed = planar.Magnitude
			local tangent = planar - normal * planar:Dot(normal)
			local impact = -vn
			if impact <= 4 then
				-- resting / sliding contact: just stop moving into the wall
				state.vel = Vector3.new(tangent.X, v.Y, tangent.Z)
			else
				local tangentSpeed = tangent.Magnitude * S.WallKeep
				-- even a head-on hit glances along the wall (never a dead stop)
				local minSpeed = speed * S.WallMinKeep * 0.5
				if tangentSpeed < minSpeed then
					local fwd = KartPhysics.forward(state.yaw)
					local t = fwd - normal * fwd:Dot(normal)
					if t.Magnitude < 0.05 then
						t = Vector3.new(-normal.Z, 0, normal.X)
					end
					tangent = t
					tangentSpeed = minSpeed
				end
				local dir = if tangent.Magnitude > 1e-6 then tangent.Unit else ZERO
				state.vel = dir * tangentSpeed + normal * (impact * S.WallRestitution) + Vector3.new(0, v.Y, 0)
				-- turn the nose toward the wall tangent (a glance, not a bounce-back)
				if dir.Magnitude > 0 then
					local want = KartPhysics.yawOf(dir)
					local diff = (want - state.yaw + math.pi) % (2 * math.pi) - math.pi
					state.yaw += math.clamp(diff, -0.5, 0.5) * 0.7
					state.yawRate *= 0.3
				end
				event(state, "wall", impact)
				if state.drift ~= 0 and impact > 30 then
					state.drift = 0
					state.driftT = 0
					state.driftLevel = 0
				end
			end
		end
	end
end

local function endDrift(state, release)
	if state.drift ~= 0 and release and state.driftLevel > 0 then
		KartPhysics.boost(state, S.DriftBoostTime[state.driftLevel], "drift" .. state.driftLevel)
	end
	state.drift = 0
	state.driftT = 0
	state.driftLevel = 0
end

--[[
	One fixed step. Mutates and returns `state`. state.events lists what happened this
	step: hop, drift, driftLevel(level), boost(source), wall(impact), land(impact), pad,
	jump.
]]
function KartPhysics.step(state, input, ground, dt)
	state.events = {}
	state.time += dt
	input = input or {}
	local gas = clamp(tonumber(input.gas) or 0, 0, 1)
	local brake = clamp(tonumber(input.brake) or 0, 0, 1)
	local steer = clamp(tonumber(input.steer) or 0, -1, 1)
	local driftHeld = input.drift == true

	-- effect timers
	state.boostT = math.max(0, state.boostT - dt)
	state.spinT = math.max(0, state.spinT - dt)
	state.frozenT = math.max(0, state.frozenT - dt)
	state.ghostT = math.max(0, state.ghostT - dt)
	state.stallT = math.max(0, state.stallT - dt)
	state.squash = math.max(0, state.squash - dt * 2.2)
	if state.slowT > 0 then
		state.slowT = math.max(0, state.slowT - dt)
		if state.slowT == 0 then
			state.slowMul = 1
		end
	end
	if state.frozenT > 0 or state.spinT > 0 or state.stallT > 0 then
		gas, brake = 0, 0
		if state.frozenT > 0 or state.spinT > 0 then
			steer = 0
			driftHeld = false
		end
		if state.drift ~= 0 then
			endDrift(state, false)
		end
	end
	local pressed = driftHeld and not state.driftHeld
	state.driftHeld = driftHeld
	state.hopT += dt

	local fwd = KartPhysics.forward(state.yaw)
	local up = state.up
	local fwdG = fwd - up * fwd:Dot(up)
	fwdG = if fwdG.Magnitude > 1e-6 then fwdG.Unit else fwd
	local rightG = fwdG:Cross(up).Unit
	local v = state.vel
	local speed = v:Dot(fwdG)
	local absSpeed = math.abs(speed)

	-- hop (the drift button)
	if pressed and state.grounded then
		state.vel += up * S.HopVelocity
		state.grounded = false
		state.hopT = 0
		event(state, "hop")
		v = state.vel
	end

	if state.grounded then
		local surfaceMul = if state.surface == "Offroad" and state.boostT <= 0 then S.OffroadMul else 1
		local cap = S.TopSpeed * surfaceMul * state.slowMul
		if state.boostT > 0 then
			cap = S.TopSpeed * S.BoostTopMul * state.slowMul
		end
		local lat = v:Dot(rightG)
		-- engine / brake / coast
		if gas > 0 and speed >= -1 then
			if speed < cap then
				local f = clamp(speed / cap, 0, 1)
				speed += S.Accel * gas * (1 - f ^ S.AccelCurve) * dt
			end
		elseif brake > 0 then
			if speed > 1 then
				speed = math.max(0, speed - S.Brake * brake * dt)
			else
				speed = math.max(-S.ReverseSpeed, speed - S.ReverseAccel * brake * dt)
			end
		elseif gas > 0 and speed < -1 then
			speed = math.min(0, speed + S.Brake * gas * dt)
		else
			local drag = S.CoastDrag * dt
			speed = if speed > 0 then math.max(0, speed - drag) else math.min(0, speed + drag)
		end
		if gas > 0 and speed < -1 then
			speed = math.min(0, speed + S.Brake * dt)
		end
		if state.boostT > 0 and speed >= 0 and speed < cap then
			speed = math.min(cap, speed + S.BoostAccel * dt)
		end
		if speed > cap then
			speed -= (speed - cap) * math.min(1, S.OverspeedDecay * dt)
			if surfaceMul < 1 then
				speed = math.max(cap, speed - S.OffroadDrag * dt)
			end
			if speed > cap * 1.6 then
				speed = cap * 1.6
			end
		end
		if state.drift ~= 0 then
			speed -= S.DriftDrag * dt
		end
		-- slope gravity (uphill slower, downhill faster, banking pulls inward)
		local g = Vector3.new(0, -S.Gravity, 0)
		local gt = g - up * g:Dot(up)
		speed += gt:Dot(fwdG) * S.SlopeGravity * dt
		lat += gt:Dot(rightG) * S.SlopeGravity * dt

		-- drift start / charge / release
		if state.drift == 0 and driftHeld and state.hopT <= S.DriftStartWindow + 0.6 and math.abs(steer) > 0.35 and speed > S.DriftMinSpeed then
			state.drift = if steer > 0 then 1 else -1
			state.driftT = 0
			state.driftLevel = 0
			event(state, "drift", state.drift)
		end
		if state.drift ~= 0 then
			if not driftHeld then
				endDrift(state, true)
			elseif speed < S.DriftMinSpeed * 0.75 then
				endDrift(state, false)
			else
				local into = math.max(0, steer * state.drift)
				state.driftT += dt * (1 + S.DriftChargeOuterBonus * into)
				local level = 0
				for i, threshold in ipairs(S.DriftChargeLevels) do
					if state.driftT >= threshold then
						level = i
					end
				end
				if level > state.driftLevel then
					state.driftLevel = level
					event(state, "driftLevel", level)
				end
			end
		end

		-- steering (speed sensitive)
		absSpeed = math.abs(speed)
		local fade = clamp(absSpeed / S.TurnFullSpeed, 0, 1)
		local rate = lerp(S.TurnRateLow, S.TurnRateHigh, clamp(absSpeed / S.TopSpeed, 0, 1)) * fade
		local target = -steer * rate * (if speed < -0.5 then -1 else 1)
		if state.drift ~= 0 then
			target = -state.drift * (S.DriftBaseTurn + S.DriftSteerRange * steer * state.drift) * fade
		end
		if state.spinT > 0 then
			target = 10
		end
		state.yawRate += (target - state.yawRate) * math.min(1, S.SteerResponse * dt)
		state.yaw += state.yawRate * dt

		-- rebuild the velocity under the new heading: grip kills the slide, most of the
		-- killed sideways speed goes back into forward speed (karts keep speed in turns)
		local planar = fwdG * speed + rightG * lat
		local nf = KartPhysics.forward(state.yaw)
		nf = nf - up * nf:Dot(up)
		nf = if nf.Magnitude > 1e-6 then nf.Unit else fwdG
		local nr = nf:Cross(up).Unit
		local sp = planar:Dot(nf)
		local la = planar:Dot(nr)
		local grip = if state.drift ~= 0 then S.DriftGrip elseif state.spinT > 0 then 1.2 else S.Grip
		local laAfter = la * math.exp(-grip * dt)
		local lost = math.abs(la) - math.abs(laAfter)
		if state.spinT <= 0 and sp >= 0 then
			sp = math.min(sp + lost * S.GripTransfer, math.max(sp, cap))
		elseif state.spinT <= 0 then
			sp -= lost * S.GripTransfer
		end
		if state.frozenT > 0 then
			sp *= math.exp(-3 * dt)
			laAfter *= math.exp(-3 * dt)
		end
		state.vel = nf * sp + nr * laAfter
		state.airTime = 0
		state.stuckT = if gas > 0.5 and math.abs(sp) < 3 then state.stuckT + dt else 0
	else
		-- air: gravity, a little air control, momentum kept
		state.airTime += dt
		local target = -steer * S.AirSteer
		if state.drift ~= 0 then
			target = -state.drift * S.DriftBaseTurn
		end
		if state.spinT > 0 then
			target = 10
		end
		state.yawRate += (target - state.yawRate) * math.min(1, S.SteerResponse * 0.5 * dt)
		state.yaw += state.yawRate * dt
		local nf = KartPhysics.forward(state.yaw)
		local nr = Vector3.new(-nf.Z, 0, nf.X)
		local planar = Vector3.new(v.X, 0, v.Z)
		local la = planar:Dot(nr)
		planar -= nr * (la * (1 - math.exp(-S.AirGrip * dt)))
		state.vel = Vector3.new(planar.X, v.Y - S.Gravity * dt, planar.Z)
		-- the drift button held through a hop arms a drift on landing
		if state.drift == 0 and driftHeld and math.abs(steer) > 0.35 and state.hopT < S.DriftStartWindow then
			state.pendingDrift = if steer > 0 then 1 else -1
		end
		state.up = state.up:Lerp(Y, math.min(1, dt * 1.5)).Unit
	end

	-- integrate, then walls
	state.pos += state.vel * dt
	resolveWalls(state, ground)

	-- ground
	local h, n, surface, course = probe(state, ground)
	local wasGrounded = state.grounded
	if h then
		local bottom = state.pos.Y - S.RideHeight
		local planarSpeed = KartPhysics.speed(state)
		local snap = if wasGrounded then S.SnapDown + planarSpeed * dt * 0.35 else 0.15
		local rising = state.vel:Dot(n)
		local touching = if wasGrounded then bottom <= h + snap and rising < 8 else bottom <= h + 0.15
		if touching then
			if not wasGrounded then
				local impact = math.max(0, -rising)
				state.squash = math.min(S.LandSquashMax, impact / 120)
				if impact > 6 then
					event(state, "land", impact)
				end
				if state.pendingDrift and driftHeld and planarSpeed > S.DriftMinSpeed then
					state.drift = state.pendingDrift
					state.driftT = 0
					state.driftLevel = 0
					event(state, "drift", state.drift)
				end
			end
			state.pendingDrift = nil
			state.grounded = true
			state.pos = Vector3.new(state.pos.X, h + S.RideHeight, state.pos.Z)
			local vn = state.vel:Dot(n)
			if vn < 0 or wasGrounded then
				state.vel -= n * vn
			end
			state.up = state.up:Lerp(n, math.min(1, S.AlignRate * dt)).Unit
			local before = state.surface
			state.surface = surface
			state.course = course
			if surface == "Boost" then
				if before ~= "Boost" or state.boostT < 0.2 then
					KartPhysics.boost(state, S.PadBoostTime, "pad")
					event(state, "pad")
				end
			elseif surface == "Jump" and state.vel:Dot(KartPhysics.forward(state.yaw)) > 20 then
				local vy = math.max(state.vel.Y, S.JumpLaunch)
				state.vel = Vector3.new(state.vel.X, vy, state.vel.Z)
				state.pos += Vector3.new(0, 0.3, 0)
				state.grounded = false
				event(state, "jump", vy)
			end
		else
			state.grounded = false
		end
	else
		state.grounded = false
		state.surface = "Air"
	end
	if state.grounded and state.course == "floor" then
		state.offCourseT += dt
	elseif state.grounded then
		state.offCourseT = 0
	end
	return state
end

--[[
	Runs as many fixed steps as `frameDt` (plus the carried accumulator) covers.
	Returns the new accumulator and the number of steps. Rendering can interpolate with
	accumulator / FixedStep.
]]
function KartPhysics.advance(state, input, ground, frameDt, accumulator)
	accumulator = (accumulator or 0) + math.min(frameDt, S.FixedStep * S.MaxSubsteps)
	local steps = 0
	while accumulator >= S.FixedStep - 1e-9 and steps < S.MaxSubsteps do
		KartPhysics.step(state, input, ground, S.FixedStep)
		accumulator -= S.FixedStep
		steps += 1
	end
	return math.max(0, accumulator), steps
end

-- KartEffects, applied to a state (server-chosen; clients apply their own kart's).
function KartPhysics.applyEffect(state, kind, params)
	params = params or {}
	if state.ghostT > 0 and kind ~= "respawnToCheckpoint" then
		return false
	end
	if kind == "spinOut" then
		state.spinT = math.max(state.spinT, params.duration or S.SpinOutTime)
		state.vel *= 0.55
		endDrift(state, false)
	elseif kind == "slow" then
		state.slowMul = math.clamp(params.mul or S.SlowMul, 0.3, 1)
		state.slowT = math.max(state.slowT, params.duration or S.SlowTime)
	elseif kind == "launch" then
		local vy = math.clamp(params.up or 45, 0, 90)
		state.vel = Vector3.new(state.vel.X * 0.6, vy, state.vel.Z * 0.6)
		state.grounded = false
		state.spinT = math.max(state.spinT, params.spin or 0.6)
		endDrift(state, false)
	elseif kind == "freeze" then
		state.frozenT = math.max(state.frozenT, params.duration or S.FreezeTime)
		state.vel *= 0.25
	elseif kind == "knockback" then
		local impulse = params.impulse or ZERO
		if impulse.Magnitude > 80 then
			impulse = impulse.Unit * 80
		end
		state.vel += impulse
		if impulse.Y > 5 then
			state.grounded = false
		end
		endDrift(state, false)
	else
		return false
	end
	event(state, "effect", kind)
	return true
end

-- Teleports a kart (respawn), facing along `cframe`, with a ghost window.
function KartPhysics.respawn(state, cframe, ghost)
	state.pos = cframe.Position
	state.yaw = KartPhysics.yawOf(cframe.LookVector)
	state.vel = ZERO
	state.yawRate = 0
	state.up = Y
	state.grounded = false
	state.boostT, state.spinT, state.frozenT, state.slowT, state.slowMul = 0, 0, 0, 0, 1
	state.ghostT = ghost or S.GhostTime
	state.stuckT, state.offCourseT = 0, 0
	endDrift(state, false)
	return state
end

-- Simple circle push between two karts (client: me vs a remote kart; server: bots).
-- Returns true if they touched. Only `a` is changed.
function KartPhysics.bump(a, otherPos, otherVel)
	if a.ghostT > 0 then
		return false
	end
	local d = a.pos - otherPos
	d = Vector3.new(d.X, 0, d.Z)
	local dist = d.Magnitude
	local min = S.Radius * 2
	if dist >= min or math.abs(a.pos.Y - otherPos.Y) > 4 then
		return false
	end
	local n = if dist > 1e-4 then d / dist else Vector3.new(1, 0, 0)
	a.pos += n * ((min - dist) * 0.5)
	local closing = (otherVel - a.vel):Dot(n)
	a.vel += n * (S.BumpPush * 0.5 + math.max(0, closing) * S.BumpShare)
	event(a, "bump", dist)
	return true
end

-- Start boost: gas pressed at `pressedAt` (seconds, same clock as goAt) and held to GO.
function KartPhysics.startResult(pressedAt, goAt)
	if not pressedAt then
		return nil
	end
	local early = goAt - pressedAt
	if early < 0 then
		return nil
	end
	if early <= S.StartBoostWindow then
		return "boost"
	elseif early > 1.25 then
		return "stall"
	end
	return nil
end

function KartPhysics.applyStart(state, result)
	if result == "boost" then
		KartPhysics.boost(state, S.StartBoostTime, "start")
	elseif result == "stall" then
		state.stallT = S.StartStallTime
		event(state, "stall")
	end
end

-- The chassis CFrame: heading `yaw`, aligned to the smoothed ground normal.
function KartPhysics.cframe(state)
	local up = state.up
	local fwd = KartPhysics.forward(state.yaw)
	local look = fwd - up * fwd:Dot(up)
	look = if look.Magnitude > 1e-6 then look.Unit else fwd
	local right = look:Cross(up).Unit
	return CFrame.fromMatrix(state.pos, right, up, -look)
end

function KartPhysics.flags(state)
	local f = 0
	if state.drift ~= 0 then
		f += F.Drifting
		if state.drift > 0 then
			f += F.DriftRight
		end
		local level = state.driftLevel
		if level == 1 or level == 3 then
			f += F.Level1
		end
		if level >= 2 then
			f += F.Level2
		end
	end
	if state.boostT > 0 then
		f += F.Boost
	end
	if not state.grounded then
		f += F.Air
	end
	if state.ghostT > 0 then
		f += F.Ghost
	end
	if state.spinT > 0 then
		f += F.Spin
	end
	if state.frozenT > 0 then
		f += F.Frozen
	end
	if state.surface == "Offroad" then
		f += F.Offroad
	end
	return f
end

function KartPhysics.hasFlag(flags, flag)
	return (flags // flag) % 2 == 1
end

function KartPhysics.driftLevelOf(flags)
	local level = 0
	if KartPhysics.hasFlag(flags, F.Level1) then
		level += 1
	end
	if KartPhysics.hasFlag(flags, F.Level2) then
		level += 2
	end
	return level
end

return KartPhysics
