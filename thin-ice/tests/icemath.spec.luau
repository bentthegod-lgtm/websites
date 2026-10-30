local L = require("./loader")
local IceMath = L.shared("IceMath")
local GameConfig = L.shared("Config/GameConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "IceMath: " .. name, fn = fn })
end

local function near(a, b)
	return math.abs(a - b) < 1e-6
end

test("speeds: sneak < walk < sprint; carrying slower; water slowest", function()
	assert(IceMath.speed("Sneak") < IceMath.speed("Walk") and IceMath.speed("Walk") < IceMath.speed("Sprint"))
	assert(IceMath.speed("Walk", true) < IceMath.speed("Walk", false))
	assert(IceMath.speed("Sprint", false, true) == GameConfig.Move.WaterSpeed)
	assert(IceMath.speed("Bogus") == GameConfig.Move.Walk)
	assert(IceMath.maxStep(14, 0.5) > 14 * 0.5, "no tolerance")
end)

test("stamina: sprint drains to exhaustion, no sprint until RecoverTo, regen after delay", function()
	local s, ex, since, mode = 100, false, 99, nil
	local t = 0
	repeat
		s, ex, since, mode = IceMath.stepStamina(s, ex, since, "Sprint", true, 0.1)
		t += 0.1
	until ex or t > 60
	assert(ex and s == 0 and mode == "Walk", "never exhausted")
	assert(t > 4 and t < 5, "drain time " .. t)
	s, ex, since, mode = IceMath.stepStamina(s, ex, since, "Sprint", true, 0.1)
	assert(mode == "Walk", "sprinted while exhausted")
	for _ = 1, 60 do
		s, ex, since, mode = IceMath.stepStamina(s, ex, since, "Walk", true, 0.1)
	end
	assert(not ex and s >= GameConfig.Stamina.RecoverTo, "did not recover")
	local _, _, _, still = IceMath.stepStamina(50, false, 0, "Sprint", false, 0.1)
	assert(still == "Walk", "standing still counts as sprinting")
end)

test("warmth: ice drains, water drains fast, fire and shore warm, gust adds chill, clamped", function()
	local base = IceMath.stepWarmth(50, {}, 1)
	assert(near(base, 50 - GameConfig.Warmth.IceDrain))
	assert(IceMath.stepWarmth(50, { inWater = true }, 1) < base - 5)
	assert(IceMath.stepWarmth(50, { nearFire = true }, 1) > 60)
	assert(IceMath.stepWarmth(50, { onShore = true }, 1) > 50)
	assert(IceMath.stepWarmth(50, { gust = true }, 1) < base)
	assert(near(IceMath.stepWarmth(50, { onShore = true, gust = true }, 1), 50 + GameConfig.Warmth.ShoreRegen), "gust chills the shore")
	assert(IceMath.stepWarmth(50, { drainScale = 2 }, 1) < base)
	assert(IceMath.stepWarmth(1, { inWater = true }, 10) == 0 and IceMath.stepWarmth(99, { nearFire = true }, 10) == GameConfig.Warmth.Max)
end)

test("stress: cracks once at half strength, breaks at full, recovers when empty", function()
	local s, event, cracked = 0, nil, false
	local events = {}
	for _ = 1, 400 do
		s, event = IceMath.stepStress(s, 1, IceMath.stressRate("Sprint", true, false), 0.05, cracked)
		if event then
			table.insert(events, event)
			if event == "crack" then
				cracked = true
			end
			if event == "break" then
				break
			end
		end
	end
	assert(events[1] == "crack" and events[2] == "break" and #events == 2, table.concat(events, ","))
	local r = IceMath.stepStress(20, 2, 0, 1, false)
	assert(near(r, 20 - GameConfig.Ice.Recover))
	assert(IceMath.stepStress(1, 2, 0, 10, false) == 0)
	-- Thin ice under a sprinter breaks in about 1.5 s; thick ice holds a walker for a long time.
	local thinTime = GameConfig.Ice.Strength[1] / IceMath.stressRate("Sprint", true, false)
	local thickTime = GameConfig.Ice.Strength[3] / IceMath.stressRate("Walk", true, false)
	assert(thinTime < 2 and thickTime > 20, string.format("%.1f / %.1f", thinTime, thickTime))
	assert(IceMath.stressRate("Sneak", true, false) < IceMath.stressRate("Walk", true, false))
	assert(IceMath.stressRate("Walk", true, true) > IceMath.stressRate("Walk", true, false))
	assert(IceMath.damage(35, 2) == 0.5 and IceMath.damage(999, 1) == 1)
end)

test("noise: gait by mode, linear falloff, silent past radius, hearing scales it", function()
	assert(IceMath.gait("Sneak", true) == "StepSneak" and IceMath.gait("Sprint", true) == "StepSprint" and IceMath.gait("Walk", false) == nil)
	local close = IceMath.perceived("StepSprint", 5, 1)
	local far = IceMath.perceived("StepSprint", 50, 1)
	assert(close > far and far > 0)
	assert(IceMath.perceived("StepSneak", 12, 1) == 0, "sneaking heard from far away")
	assert(IceMath.perceived("Splash", 1000, 1) == 0 and IceMath.perceived("Nope", 1, 1) == 0 and IceMath.perceived("Chip", 0 / 0, 1) == 0)
	assert(near(IceMath.perceived("Chip", 10, 0.5), IceMath.perceived("Chip", 10, 1) * 0.5))
	-- A sprint is loud enough to start a hunt from close by; a sneak never is.
	assert(IceMath.perceived("StepSprint", 10, 1) >= GameConfig.Noise.HuntThreshold)
	assert(IceMath.perceived("StepSneak", 0, 1.3) < GameConfig.Noise.HearThreshold)
end)

return cases
