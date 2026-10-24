local roblox = require("@lune/roblox")
local load = require("./loader")
local BallMath = load("BallMath")
local GameConfig = load("Config/GameConfig")
local Vector3 = roblox.Vector3

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "BallMath: " .. name, fn = fn })
end

local B, P = GameConfig.Ball, GameConfig.Parry

test("rotateToward never turns more than the max angle", function()
	local from = Vector3.new(1, 0, 0)
	local to = Vector3.new(0, 0, 1)
	local r = BallMath.rotateToward(from, to, math.rad(10))
	local angle = math.deg(math.acos(math.clamp(r:Dot(from), -1, 1)))
	assert(math.abs(angle - 10) < 0.01, "turned " .. angle)
	assert(math.abs(r.Magnitude - 1) < 1e-6, "not unit")
	-- Exactly opposite directions still turn (no NaN).
	local back = BallMath.rotateToward(from, -from, math.rad(30))
	assert(back.X == back.X and math.abs(back.Magnitude - 1) < 1e-6, "opposite produced NaN")
end)

test("ball reaches a still target from any starting direction (no orbiting)", function()
	for _, speed in ipairs({ B.BaseSpeed, 120, B.MaxSpeed }) do
		for _, start in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0) }) do
			local state = { pos = Vector3.new(0, 20, 0), dir = start, speed = speed, curve = B.CurveDelay }
			local target = Vector3.new(40, 3, 0)
			local hit = false
			for _ = 1, 60 * 12 do
				local _, d = BallMath.step(state, target, 1 / 60, B)
				if d <= B.HitRadius then
					hit = true
					break
				end
			end
			assert(hit, string.format("speed %d from %s never hit", speed, tostring(start)))
		end
	end
end)

test("ball catches a target running in circles", function()
	local state = { pos = Vector3.new(0, 20, 0), dir = Vector3.new(0, 0, 1), speed = 90, curve = 0 }
	local t, hit = 0, false
	for _ = 1, 60 * 15 do
		t += 1 / 60
		local target = Vector3.new(math.cos(t * 1.2) * 30, 3, math.sin(t * 1.2) * 30)
		local _, d = BallMath.step(state, target, 1 / 60, B)
		if d <= B.HitRadius then
			hit = true
			break
		end
	end
	assert(hit, "circling target was never caught")
end)

test("deflect speeds up and is capped", function()
	local s = B.BaseSpeed
	local last = s
	for _ = 1, 200 do
		s = BallMath.deflectSpeed(s, B)
		assert(s >= last and s <= B.MaxSpeed)
		last = s
	end
	assert(s == B.MaxSpeed, "never reached cap")
end)

test("parry range grows with speed but is bounded", function()
	assert(BallMath.parryRange(B.BaseSpeed, P) < BallMath.parryRange(200, P))
	assert(BallMath.parryRange(1e6, P) == P.MaxRange)
end)

test("pickTarget prefers players inside the aim cone", function()
	local origin = Vector3.new(0, 0, 0)
	local candidates = {
		{ id = "near_wrong_way", pos = Vector3.new(-5, 0, 0) },
		{ id = "aimed", pos = Vector3.new(40, 0, 2) },
		{ id = "side", pos = Vector3.new(0, 0, 30) },
	}
	assert(BallMath.pickTarget(origin, Vector3.new(1, 0, 0), candidates, P.AimConeDot) == "aimed")
	assert(BallMath.pickTarget(origin, Vector3.new(0, 0, 1), candidates, P.AimConeDot) == "side")
	-- Nobody in the cone: the one closest to the aim direction.
	assert(BallMath.pickTarget(origin, Vector3.new(0, 1, 0), { candidates[1], candidates[2] }, 0.99) ~= nil)
	-- NaN / zero aim never errors.
	local nan = 0 / 0
	assert(BallMath.pickTarget(origin, Vector3.new(nan, nan, nan), candidates, P.AimConeDot) ~= nil)
	assert(BallMath.pickTarget(origin, Vector3.zero, candidates, P.AimConeDot) ~= nil)
	assert(BallMath.pickTarget(origin, Vector3.new(1, 0, 0), {}, P.AimConeDot) == nil)
end)

test("history interpolates and trims old samples", function()
	local h = BallMath.newHistory()
	for i = 0, 100 do
		BallMath.record(h, i * 0.1, Vector3.new(i, 0, 0), 1)
	end
	assert(#h.samples <= 13, "history not trimmed: " .. #h.samples)
	local p = BallMath.sample(h, 9.55)
	assert(math.abs(p.X - 95.5) < 1e-6, "bad interpolation " .. p.X)
	assert(BallMath.sample(h, 0).X == h.samples[1].pos.X, "clamps to oldest")
	assert(BallMath.sample(h, 999).X == 100, "clamps to newest")
	assert(BallMath.sample(BallMath.newHistory(), 1) == nil)
end)

test("freeze slow factor reduces distance travelled", function()
	local a = { pos = Vector3.zero, dir = Vector3.new(1, 0, 0), speed = 100, curve = 0 }
	local b = { pos = Vector3.zero, dir = Vector3.new(1, 0, 0), speed = 100, curve = 0 }
	BallMath.step(a, Vector3.new(500, 0, 0), 0.1, B)
	BallMath.step(b, Vector3.new(500, 0, 0), 0.1, B, 0.3)
	assert(math.abs(a.pos.X - 10) < 1e-6 and math.abs(b.pos.X - 3) < 1e-6)
end)

return cases
