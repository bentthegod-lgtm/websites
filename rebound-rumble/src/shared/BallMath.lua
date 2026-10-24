--[[
	BallMath - pure ball simulation helpers shared by the server (authoritative simulation)
	and the client (smooth local prediction between server syncs).

	No Instances, no services: only Vector3 math, so it runs in the Lune unit tests.

	state = { pos: Vector3, dir: Vector3 (unit), speed: number, curve: number }
	  curve - seconds left in which homing is weakened right after a deflect, so the ball
	          visibly flies the way you aimed before bending toward its new target.
]]

local BallMath = {}

local EPS = 1e-6

function BallMath.parryRange(speed, parryCfg)
	return math.min(parryCfg.MaxRange, parryCfg.BaseRange + speed * parryCfg.WindowSeconds)
end

function BallMath.deflectSpeed(speed, ballCfg)
	return math.min(ballCfg.MaxSpeed, speed * ballCfg.DeflectMultiplier + ballCfg.DeflectAdd)
end

-- Max turn rate (radians / second) for the given speed and distance to the target.
function BallMath.turnRate(ballCfg, speed, distance)
	local rate = ballCfg.TurnRate + speed * ballCfg.TurnRatePerSpeed
	-- Keep the turning circle small enough that a fast ball can never orbit its target.
	rate = math.max(rate, speed / ballCfg.MaxTurnRadius)
	if distance < ballCfg.CloseDistance then
		rate *= 1 + ballCfg.CloseTurnBoost * (1 - distance / ballCfg.CloseDistance)
	end
	return rate
end

-- Rotates unit vector `from` toward unit vector `to` by at most `maxAngle` radians.
function BallMath.rotateToward(from, to, maxAngle)
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle or angle < EPS then
		return to
	end
	local axis = from:Cross(to)
	if axis.Magnitude < EPS then
		-- Exactly opposite: pick any perpendicular axis (prefer turning sideways).
		axis = from:Cross(Vector3.new(0, 1, 0))
		if axis.Magnitude < EPS then
			axis = from:Cross(Vector3.new(1, 0, 0))
		end
	end
	axis = axis.Unit
	-- Rodrigues' rotation formula.
	local c, s = math.cos(maxAngle), math.sin(maxAngle)
	local rotated = from * c + axis:Cross(from) * s + axis * axis:Dot(from) * (1 - c)
	return rotated.Unit
end

-- Advances the ball by dt toward targetPos. `slow` (0..1] scales speed (Freeze ability).
-- Returns the new state (mutated in place) and the distance to the target afterwards.
function BallMath.step(state, targetPos, dt, ballCfg, slow)
	local toTarget = targetPos - state.pos
	local distance = toTarget.Magnitude
	if distance > EPS then
		local desired = toTarget / distance
		local rate = BallMath.turnRate(ballCfg, state.speed, distance)
		if state.curve and state.curve > 0 then
			rate *= 0.15
			state.curve = math.max(0, state.curve - dt)
		end
		state.dir = BallMath.rotateToward(state.dir, desired, rate * dt)
	end
	local move = state.speed * (slow or 1) * dt
	-- Never overshoot a target we are flying straight at.
	if distance > EPS and move >= distance and state.dir:Dot((targetPos - state.pos).Unit) > 0.9 then
		state.pos = targetPos
	else
		state.pos += state.dir * move
	end
	return state, (targetPos - state.pos).Magnitude
end

--[[
	Picks a deflect target from the aim direction.
	candidates = { { id = any, pos = Vector3 } } (the parrying player is NOT included)
	Prefers candidates inside the aim cone (highest dot, ties broken by distance);
	otherwise the candidate closest to the aim direction.
]]
function BallMath.pickTarget(origin, aimDir, candidates, coneDot)
	if #candidates == 0 then
		return nil
	end
	local aim = aimDir
	if typeof(aim) ~= "Vector3" or aim.Magnitude < EPS or aim.Magnitude ~= aim.Magnitude then
		aim = Vector3.new(0, 0, -1)
	end
	aim = aim.Unit
	local best, bestScore
	for _, c in ipairs(candidates) do
		local offset = c.pos - origin
		local dist = offset.Magnitude
		local dot = if dist > EPS then aim:Dot(offset / dist) else 1
		-- Inside the cone, closer players win ties; distance matters a little.
		local score = dot - dist * 0.0005
		if dot >= coneDot then
			score += 10
		end
		if not bestScore or score > bestScore then
			best, bestScore = c, score
		end
	end
	return best.id
end

---------------------------------------------------------------------------------------------
-- Position history (for lag-compensated parries)
---------------------------------------------------------------------------------------------

function BallMath.newHistory()
	return { samples = {} }
end

function BallMath.record(history, t, pos, maxAge)
	local samples = history.samples
	table.insert(samples, { t = t, pos = pos })
	local cutoff = t - maxAge
	while #samples > 2 and samples[1].t < cutoff do
		table.remove(samples, 1)
	end
end

function BallMath.clearHistory(history)
	table.clear(history.samples)
end

-- Interpolated ball position at time t (clamped to the recorded range).
function BallMath.sample(history, t)
	local samples = history.samples
	local n = #samples
	if n == 0 then
		return nil
	end
	if t <= samples[1].t then
		return samples[1].pos
	end
	if t >= samples[n].t then
		return samples[n].pos
	end
	for i = n - 1, 1, -1 do
		local a = samples[i]
		if a.t <= t then
			local b = samples[i + 1]
			local span = b.t - a.t
			local alpha = if span > EPS then (t - a.t) / span else 0
			return a.pos:Lerp(b.pos, alpha)
		end
	end
	return samples[n].pos
end

return BallMath
