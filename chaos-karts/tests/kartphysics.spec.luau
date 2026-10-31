local Loader = require("./loader")
local KP = Loader.shared("KartPhysics")
local S = Loader.shared("Config/KartStats")
local V3, CF = Loader.roblox.Vector3, Loader.roblox.CFrame

local DT = S.FixedStep
local UP = V3.new(0, 1, 0)

-- A flat test world: ground at y = 0 everywhere, surfaces by region, optional wall plane
-- at x = wallX (normal -X), optional slope (height = slope * -z), optional drop.
local function world(opts)
	opts = opts or {}
	local q = {}
	function q:ground(p)
		local h = 0
		local n = UP
		if opts.slope then
			-- height rises along -Z (the kart's forward at yaw 0) by `slope` per stud
			h = -p.Z * opts.slope
			n = V3.new(0, 1, opts.slope).Unit
		end
		if opts.dropAt and p.Z < opts.dropAt then
			h -= opts.drop
		end
		if opts.ramp and p.Z < opts.ramp.from and p.Z > opts.ramp.to then
			local t = (opts.ramp.from - p.Z) / (opts.ramp.from - opts.ramp.to)
			h = t * opts.ramp.height
			n = V3.new(0, 1, opts.ramp.height / (opts.ramp.from - opts.ramp.to)).Unit
		elseif opts.ramp and p.Z <= opts.ramp.to and p.Z > opts.ramp.to - opts.ramp.gap then
			return nil
		end
		if h > p.Y + 1e-6 then
			return nil
		end
		local surface = "Road"
		if opts.surface then
			surface = opts.surface(p)
		end
		return h, n, surface, "main"
	end
	function q:walls(p, radius)
		if opts.wallX and p.X > opts.wallX - radius then
			return V3.new(-1, 0, 0), p.X - (opts.wallX - radius)
		end
		if opts.wallZ and p.Z < opts.wallZ + radius then
			return V3.new(0, 0, 1), (opts.wallZ + radius) - p.Z
		end
		return nil, 0
	end
	return q
end

local function settle(state, q)
	for _ = 1, 30 do
		KP.step(state, {}, q, DT)
	end
	return state
end

local function run(state, q, seconds, input)
	local t = 0
	local events = {}
	while t < seconds - 1e-9 do
		local i = if type(input) == "function" then input(t, state) else input
		KP.step(state, i, q, DT)
		for _, e in ipairs(state.events) do
			table.insert(events, { name = e.name, value = e.value, t = t })
		end
		t += DT
	end
	return events
end

local function newKart(q, yaw)
	return settle(KP.new(V3.new(0, S.RideHeight + 0.5, 0), yaw or 0), q)
end

local function has(events, name)
	for _, e in ipairs(events) do
		if e.name == name then
			return e
		end
	end
	return nil
end

return {
	{
		name = "KartPhysics: acceleration curve - punchy launch, then tapering to top speed",
		fn = function()
			local q = world()
			local k = newKart(q)
			assert(k.grounded, "not grounded after settling")
			run(k, q, 1, { gas = 1 })
			local v1 = KP.speed(k)
			run(k, q, 2, { gas = 1 })
			local v3 = KP.speed(k)
			assert(v1 > S.TopSpeed * 0.5, "too slow off the line: " .. v1)
			assert(v3 > S.TopSpeed * 0.93, "doesn't reach near top speed in 3 s: " .. v3)
			assert(v3 - v1 < v1, "no taper: " .. v1 .. " -> " .. v3)
		end,
	},
	{
		name = "KartPhysics: top speed is capped (and the same for every kart)",
		fn = function()
			local q = world()
			local k = newKart(q)
			local peak = 0
			run(k, q, 10, function()
				peak = math.max(peak, KP.speed(k))
				return { gas = 1 }
			end)
			assert(math.abs(KP.speed(k) - S.TopSpeed) < 1, "terminal speed " .. KP.speed(k))
			assert(peak <= S.TopSpeed + 0.5, "overshot top speed: " .. peak)
		end,
	},
	{
		name = "KartPhysics: braking stops quickly, then reverses up to ReverseSpeed",
		fn = function()
			local q = world()
			local k = newKart(q)
			run(k, q, 6, { gas = 1 })
			local t = 0
			while KP.forwardSpeed(k) > 0.5 and t < 5 do
				KP.step(k, { brake = 1 }, q, DT)
				t += DT
			end
			assert(t < 1, "braking from top speed took " .. t)
			run(k, q, 3, { brake = 1 })
			local v = KP.forwardSpeed(k)
			assert(v < -S.ReverseSpeed * 0.9 and v >= -S.ReverseSpeed - 0.5, "reverse speed " .. v)
		end,
	},
	{
		name = "KartPhysics: speed-sensitive steering (turns tighter slow than fast) with a slight slide",
		fn = function()
			local q = world()
			local slow = newKart(q)
			run(slow, q, 0.6, { gas = 1 })
			local slowSpeed = KP.speed(slow)
			run(slow, q, 0.5, { gas = 0.4, steer = 1 })
			local fast = newKart(q)
			run(fast, q, 6, { gas = 1 })
			run(fast, q, 0.5, { gas = 1, steer = 1 })
			assert(math.abs(slow.yawRate) > math.abs(fast.yawRate) * 1.1, string.format("yaw rate slow %.2f vs fast %.2f", slow.yawRate, fast.yawRate))
			assert(slow.yawRate < 0 and fast.yawRate < 0, "steer right must turn right (yaw decreasing)")
			-- grip: the velocity lags the heading a little (slide) but follows it
			local fwd = KP.forward(fast.yaw)
			local dir = V3.new(fast.vel.X, 0, fast.vel.Z).Unit
			local slip = math.deg(math.acos(math.clamp(fwd:Dot(dir), -1, 1)))
			assert(slip > 1 and slip < 15, "slip angle " .. slip)
			assert(KP.speed(fast) > S.TopSpeed * 0.85, "full lock at top speed lost too much speed: " .. KP.speed(fast))
			local _ = slowSpeed
		end,
	},
	{
		name = "KartPhysics: drift charges 3 mini-turbo levels (blue/orange/purple) and releases a boost",
		fn = function()
			local q = world()
			local k = newKart(q)
			run(k, q, 4, { gas = 1 })
			local events = run(k, q, 3.2, { gas = 1, steer = 1, drift = true })
			assert(has(events, "hop"), "pressing drift didn't hop")
			assert(k.drift == 1, "not drifting right: " .. k.drift)
			local levels = {}
			for _, e in ipairs(events) do
				if e.name == "driftLevel" then
					table.insert(levels, { level = e.value, t = e.t })
				end
			end
			assert(#levels == 3 and levels[1].level == 1 and levels[2].level == 2 and levels[3].level == 3, "levels " .. #levels)
			assert(levels[1].t < levels[2].t and levels[2].t < levels[3].t)
			assert(k.driftLevel == 3)
			-- release: a level-3 boost
			local after = run(k, q, 0.1, { gas = 1 })
			local boost = has(after, "boost")
			assert(boost and boost.value == "drift3", "no drift3 boost on release")
			assert(k.drift == 0 and k.boostT > S.DriftBoostTime[3] - 0.15, "boost time " .. k.boostT)
			run(k, q, 0.6, { gas = 1 })
			assert(KP.speed(k) > S.TopSpeed * 1.1, "boost didn't push past top speed: " .. KP.speed(k))
			-- and it decays back to the cap afterwards
			run(k, q, 5, { gas = 1 })
			assert(KP.speed(k) < S.TopSpeed + 1.5, "stuck over the cap: " .. KP.speed(k))
		end,
	},
	{
		name = "KartPhysics: a short drift gives a level-1 boost; drifting needs speed and a steer direction",
		fn = function()
			local q = world()
			local k = newKart(q)
			run(k, q, 4, { gas = 1 })
			run(k, q, 1.0, { gas = 1, steer = -1, drift = true })
			assert(k.drift == -1 and k.driftLevel == 1, "level " .. k.driftLevel)
			run(k, q, 0.05, { gas = 1 })
			assert(math.abs(k.boostT - S.DriftBoostTime[1]) < 0.06, "level-1 boost " .. k.boostT)
			-- too slow to drift: just a hop
			local slow = newKart(q)
			slow.vel = KP.forward(0) * (S.DriftMinSpeed - 10)
			run(slow, q, 1, { gas = 0, steer = 1, drift = true })
			assert(slow.drift == 0, "drifted below DriftMinSpeed")
			-- no steer: hop only
			local straight = newKart(q)
			run(straight, q, 4, { gas = 1 })
			run(straight, q, 1, { gas = 1, drift = true })
			assert(straight.drift == 0, "drifted without steering")
		end,
	},
	{
		name = "KartPhysics: walls glance (keep most speed on a shallow hit, never a dead stop head-on)",
		fn = function()
			-- shallow: heading 20 degrees toward a wall on the right (x = 12)
			local q = world({ wallX = 12 })
			local k = newKart(q, math.rad(-20))
			k.vel = KP.forward(k.yaw) * S.TopSpeed
			local before = KP.speed(k)
			local events = run(k, q, 0.6, { gas = 1 })
			assert(has(events, "wall"), "no wall contact")
			assert(k.pos.X <= 12 - S.Radius + 0.05, "went through the wall: " .. k.pos.X)
			assert(KP.speed(k) > before * 0.8, string.format("shallow glance lost too much: %.1f -> %.1f", before, KP.speed(k)))
			assert(k.vel.Z < -20, "not sliding along the wall")
			-- head-on into a wall ahead (z = -20)
			local q2 = world({ wallZ = -20 })
			local h = newKart(q2, 0)
			h.vel = KP.forward(0) * S.TopSpeed
			run(h, q2, 0.4, {})
			assert(h.pos.Z >= -20 + S.Radius - 0.05, "through the head-on wall")
			assert(KP.speed(h) > 3, "dead stop head-on: " .. KP.speed(h))
			assert(KP.speed(h) < S.TopSpeed * 0.6, "head-on kept too much speed")
		end,
	},
	{
		name = "KartPhysics: slopes - uphill is slower, downhill faster; the body aligns to the slope",
		fn = function()
			local flat = world()
			local a = newKart(flat)
			run(a, flat, 8, { gas = 1 })
			local up = world({ slope = 0.2 })
			local b = settle(KP.new(V3.new(0, S.RideHeight + 1, 0), 0), up)
			run(b, up, 8, { gas = 1 })
			local down = world({ slope = -0.2 })
			local c = settle(KP.new(V3.new(0, S.RideHeight + 1, 0), 0), down)
			run(c, down, 8, { gas = 1 })
			assert(KP.speed(b) < KP.speed(a) - 4, string.format("uphill %.1f vs flat %.1f", KP.speed(b), KP.speed(a)))
			assert(KP.speed(c) > KP.speed(a) + 2, string.format("downhill %.1f vs flat %.1f", KP.speed(c), KP.speed(a)))
			assert(b.grounded and b.up.Z > 0.15, "body didn't align to the slope")
			assert(b.pos.Y > 20, "didn't climb")
		end,
	},
	{
		name = "KartPhysics: ramps give air time with air control, landing squashes",
		fn = function()
			local q = world({ ramp = { from = -60, to = -100, height = 10, gap = 40 } })
			local k = newKart(q)
			k.vel = KP.forward(0) * S.TopSpeed
			local airTime, maxY = 0, 0
			local events = run(k, q, 3, function(_, s)
				if not s.grounded then
					airTime += DT
				end
				maxY = math.max(maxY, s.pos.Y)
				return { gas = 1, steer = 0.3 }
			end)
			assert(airTime > 0.4, "air time " .. airTime)
			assert(maxY > 10, "max height " .. maxY)
			local land = has(events, "land")
			assert(land and land.value > 6, "no landing impact")
			assert(math.abs(k.yaw) > 0.05, "no air control")
			-- squash right after a landing
			local q2 = world()
			local d = KP.new(V3.new(0, 20, 0), 0)
			local squash = 0
			run(d, q2, 1.2, function(_, s)
				squash = math.max(squash, s.squash)
				return {}
			end)
			assert(squash > 0.1 and squash <= S.LandSquashMax, "squash " .. squash)
		end,
	},
	{
		name = "KartPhysics: Jump surfaces launch, boost pads boost, off-road slows",
		fn = function()
			local jump = world({
				surface = function(p)
					return if p.Z < -30 and p.Z > -40 then "Jump" else "Road"
				end,
			})
			local k = newKart(jump)
			k.vel = KP.forward(0) * S.TopSpeed
			local events = run(k, jump, 0.6, { gas = 1 })
			local j = has(events, "jump")
			assert(j and j.value >= S.JumpLaunch, "no kicker launch")
			local pad = world({
				surface = function(p)
					return if p.Z < -30 and p.Z > -45 then "Boost" else "Road"
				end,
			})
			local b = newKart(pad)
			b.vel = KP.forward(0) * S.TopSpeed
			local evs = run(b, pad, 0.8, { gas = 1 })
			assert(has(evs, "pad"), "no pad event")
			assert(KP.speed(b) > S.TopSpeed * 1.08, "pad boost speed " .. KP.speed(b))
			local grass = world({
				surface = function()
					return "Offroad"
				end,
			})
			local g = newKart(grass)
			run(g, grass, 8, { gas = 1 })
			assert(math.abs(KP.speed(g) - S.TopSpeed * S.OffroadMul) < 1.5, "off-road speed " .. KP.speed(g))
			-- a boost ignores off-road (classic shortcut trick)
			KP.boost(g, 1)
			run(g, grass, 0.5, { gas = 1 })
			assert(KP.speed(g) > S.TopSpeed, "boost on grass " .. KP.speed(g))
		end,
	},
	{
		name = "KartPhysics: deterministic - the same inputs give bit-identical results",
		fn = function()
			local function script(t)
				return { gas = 1, steer = math.sin(t * 1.7), drift = (t % 3) > 1.6, brake = if t > 7 and t < 7.5 then 1 else 0 }
			end
			local q = world({ wallX = 40, ramp = { from = -300, to = -330, height = 6, gap = 10 } })
			local a = newKart(q)
			local b = newKart(q)
			run(a, q, 10, script)
			run(b, q, 10, script)
			assert(a.pos == b.pos and a.vel == b.vel and a.yaw == b.yaw and a.driftT == b.driftT, "runs diverged")
			-- and advance() with odd frame times matches the fixed steps
			local c = newKart(q)
			local acc = 0
			for _ = 1, 300 do
				acc = KP.advance(c, { gas = 1 }, q, DT * 2, acc)
			end
			local d = newKart(q)
			run(d, q, 10, { gas = 1 })
			assert((c.pos - d.pos).Magnitude < 1e-6, "advance() differs from fixed steps")
		end,
	},
	{
		name = "KartPhysics: KartEffects (spin out, slow, launch, freeze, knockback), ghost ignores them, respawn",
		fn = function()
			local q = world()
			local k = newKart(q)
			run(k, q, 4, { gas = 1 })
			assert(KP.applyEffect(k, "spinOut", {}))
			run(k, q, 0.3, { gas = 1, steer = 1 })
			assert(k.spinT > 0 and k.yawRate > 5, "spin out didn't spin")
			run(k, q, 2, { gas = 1 })
			assert(k.spinT == 0)
			assert(KP.applyEffect(k, "slow", { mul = 0.5, duration = 1 }))
			run(k, q, 0.9, { gas = 1 })
			assert(KP.speed(k) < S.TopSpeed * 0.6, "slow " .. KP.speed(k))
			run(k, q, 2, { gas = 1 })
			assert(k.slowMul == 1)
			assert(KP.applyEffect(k, "launch", { up = 40 }))
			assert(not k.grounded and k.vel.Y == 40)
			run(k, q, 2, {})
			assert(KP.applyEffect(k, "freeze", { duration = 1 }))
			run(k, q, 0.5, { gas = 1, steer = 1 })
			assert(KP.speed(k) < 15, "frozen kart moving " .. KP.speed(k))
			run(k, q, 1, {})
			local before = k.vel
			assert(KP.applyEffect(k, "knockback", { impulse = V3.new(30, 10, 0) }))
			assert((k.vel - before - V3.new(30, 10, 0)).Magnitude < 1e-6)
			assert(not KP.applyEffect(k, "eliminate", {}), "unknown effects must be refused")
			KP.respawn(k, CF.new(10, 5, 10))
			assert(k.ghostT == S.GhostTime and k.vel.Magnitude == 0 and k.pos == V3.new(10, 5, 10))
			assert(not KP.applyEffect(k, "spinOut", {}), "ghost was hit")
		end,
	},
	{
		name = "KartPhysics: start boost for gas at the right moment, stall for gas too early, bumps push apart",
		fn = function()
			assert(KP.startResult(9.8, 10) == "boost")
			assert(KP.startResult(8.0, 10) == "stall")
			assert(KP.startResult(9.2, 10) == nil)
			assert(KP.startResult(nil, 10) == nil and KP.startResult(10.2, 10) == nil)
			local q = world()
			local k = newKart(q)
			KP.applyStart(k, "boost")
			run(k, q, 1, { gas = 1 })
			assert(KP.speed(k) > S.TopSpeed * 0.75, "start boost launch " .. KP.speed(k))
			local s = newKart(q)
			KP.applyStart(s, "stall")
			run(s, q, 0.5, { gas = 1 })
			assert(KP.speed(s) < 1, "stall didn't stall")
			local a = newKart(q)
			assert(KP.bump(a, a.pos + V3.new(2, 0, 0), V3.new()), "no bump")
			assert(a.vel.X < -5, "not pushed away")
			assert(not KP.bump(a, a.pos + V3.new(20, 0, 0), V3.new()), "bumped from 20 studs")
		end,
	},
	{
		name = "KartPhysics: flags round-trip (drift side and level, boost, air)",
		fn = function()
			local k = KP.new(V3.new(0, 10, 0), 0)
			k.drift, k.driftLevel, k.boostT, k.grounded = 1, 3, 1, false
			local f = KP.flags(k)
			assert(KP.hasFlag(f, KP.Flags.Drifting) and KP.hasFlag(f, KP.Flags.DriftRight) and KP.hasFlag(f, KP.Flags.Boost) and KP.hasFlag(f, KP.Flags.Air))
			assert(KP.driftLevelOf(f) == 3)
			k.drift, k.driftLevel = -1, 2
			f = KP.flags(k)
			assert(not KP.hasFlag(f, KP.Flags.DriftRight) and KP.driftLevelOf(f) == 2)
			local cf = KP.cframe(k)
			assert((cf.LookVector - KP.forward(0)).Magnitude < 1e-5, "cframe heading")
		end,
	},
}
