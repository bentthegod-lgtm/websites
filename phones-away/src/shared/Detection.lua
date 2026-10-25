--[[
	Detection - pure "can the teacher see / hear your phone" math (the stealth core).

	Inspired by the sight + noise split of DEAD AIR's MonsterBrain, but for a classroom:
	  * SIGHT: a field-of-view cone with a soft edge. A phone that is out (or coming out, or
	    still going away, or still glowing in the desk for a moment) is visible inside the
	    cone. Closer = worse. Phone case dims glow, hood / textbook cover blocks some of it.
	    Selfie flashes are 5x brighter.
	  * DESK CHECK: while walking the rows she checks desks up close; cover barely helps.
	  * HEARING: screen taps make noise (earbuds reduce it) heard in every direction.

	Observers and students are plain tables of numbers, so this runs in Lune unit tests and
	on the server unchanged. The server is the only caller in the game: clients never decide
	what the teacher sees.

	observer = { x, z, heading (radians, facing = (sin h, cos h)), fov (deg half-angle),
	             sight (multiplier), hearing (multiplier), checking (bool) }
	student  = { x, z, phone = "down"|"raising"|"up"|"hiding", sinceHidden (s), linger (s),
	             glow, cover (multipliers), noise (0..MaxNoise), flash (bool) }
]]

local Detection = {}

local function wrap(angle)
	angle = (angle + math.pi) % (2 * math.pi)
	if angle < 0 then
		angle += 2 * math.pi
	end
	return angle - math.pi
end
Detection.wrap = wrap

function Detection.headingTo(fromX, fromZ, toX, toZ)
	return math.atan2(toX - fromX, toZ - fromZ)
end

-- Turns `current` toward `target` by at most `maxStep` radians (shortest way round).
function Detection.turnToward(current, target, maxStep)
	local diff = wrap(target - current)
	if math.abs(diff) <= maxStep then
		return wrap(target)
	end
	return wrap(current + (if diff > 0 then maxStep else -maxStep))
end

-- How visible the phone itself is (0..1), before any cone / cover maths.
function Detection.visibility(student, sightCfg)
	local phone = student.phone
	if phone == "up" or phone == "hiding" then
		return 1
	elseif phone == "raising" then
		return sightCfg.RaiseVisibility
	end
	if (student.sinceHidden or math.huge) < (student.linger or 0) then
		return sightCfg.LingerVisibility
	end
	return 0
end

-- 0..1 inside the cone (soft edge), plus the angle (deg) and distance.
function Detection.cone(observer, x, z, sightCfg)
	local dx, dz = x - observer.x, z - observer.z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 0.01 then
		return 1, 0, dist
	end
	if dist > sightCfg.Range then
		return 0, 180, dist
	end
	local angle = math.deg(math.abs(wrap(math.atan2(dx, dz) - observer.heading)))
	local fov = observer.fov or sightCfg.FovDegrees
	local factor = math.clamp((fov - angle) / sightCfg.EdgeSoftness + 0.5, 0, 1)
	return factor, angle, dist
end

--[[
	Returns sightGain, noiseGain (suspicion per second), seenFlash (bool: she saw a flash this
	tick, for the instant bump) for one observer and one student.
]]
function Detection.gain(observer, student, cfg)
	local sightCfg, hearCfg = cfg.Sight, cfg.Hearing
	local sightGain, noiseGain, seenFlash = 0, 0, false
	local vis = Detection.visibility(student, sightCfg)
	local sightMult = observer.sight or 1
	if student.flash then
		vis = math.max(vis, 1)
	end
	if vis > 0 and sightMult > 0 then
		local cone, _, dist = Detection.cone(observer, student.x, student.z, sightCfg)
		if cone > 0 then
			local near = sightCfg.NearBonus * math.clamp(1 - dist / sightCfg.Range, 0, 1)
			local glow = student.glow or 1
			if student.flash then
				glow = math.max(glow, 1) * sightCfg.FlashMultiplier
				seenFlash = true
			end
			sightGain = sightCfg.Rate * (1 + near) * vis * cone * glow * (student.cover or 1) * sightMult
		end
		if observer.checking and dist <= sightCfg.DeskCheckRange then
			-- Up close she just looks at your desk: cover helps a little, glow doesn't.
			local coverEffect = math.sqrt(student.cover or 1)
			sightGain += sightCfg.DeskCheckRate * vis * coverEffect * math.max(sightMult, 0.5)
		end
	end
	local noise = student.noise or 0
	if student.flash then
		noise += hearCfg.FlashNoise
	end
	local hearMult = observer.hearing or 1
	if noise > (hearCfg.MinNoise or 0) and hearMult > 0 then
		local dx, dz = student.x - observer.x, student.z - observer.z
		local dist = math.sqrt(dx * dx + dz * dz)
		local falloff = math.clamp(1 - dist / hearCfg.Range, 0, 1)
		noiseGain = hearCfg.Rate * noise * falloff * hearMult
	end
	return sightGain, noiseGain, seenFlash
end

--[[
	Advances one student's suspicion. `state` = { value, quietFor } is updated in place.
	`gain` is the total suspicion per second from every observer this tick; `instant` is an
	immediate bump (seen flash, report). Returns the new value.
]]
function Detection.step(state, gain, instant, dt, suspicionCfg)
	local value = state.value or 0
	if gain > 0.001 or (instant or 0) > 0 then
		value += gain * dt + (instant or 0)
		state.quietFor = 0
	else
		state.quietFor = (state.quietFor or 0) + dt
		if state.quietFor >= suspicionCfg.DecayDelay then
			value -= suspicionCfg.DecayPerSecond * dt
		end
	end
	state.value = math.clamp(value, 0, suspicionCfg.Catch)
	return state.value
end

function Detection.mark(value, suspicionCfg)
	if value >= suspicionCfg.Alert then
		return "!"
	elseif value >= suspicionCfg.Question then
		return "?"
	end
	return ""
end

-- Noise from screen taps: each tap adds NoisePerTap x earbuds multiplier, decays over time.
function Detection.addNoise(current, taps, earbuds, hearCfg)
	return math.min(hearCfg.MaxNoise, (current or 0) + taps * hearCfg.NoisePerTap * (earbuds or 1))
end

function Detection.decayNoise(current, dt, hearCfg)
	return math.max(0, (current or 0) - hearCfg.NoiseDecay * dt)
end

return Detection
