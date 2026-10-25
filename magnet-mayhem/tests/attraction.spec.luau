local L = require("./loader")
local Attraction = L.shared("Attraction")
local Economy = L.shared("Economy")
local ScrapConfig = L.shared("Config/ScrapConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Attraction: " .. name, fn = fn })
end

local base = Economy.stats({}, 1, 0)
local strong = Economy.stats({ Strength = 12, Heavy = 5, Speed = 10 }, 6, 0)
local by = ScrapConfig.ById

test("strength gates heavy objects", function()
	assert(Attraction.canPull(by.SodaCan, base))
	local ok, reason = Attraction.canPull(by.SteelSafe, base)
	assert(not ok and reason == "TooHeavy")
	assert(Attraction.canPull(by.SteelSafe, strong))
end)

test("heavier objects are slower and wind up longer", function()
	local d = 12
	assert(Attraction.duration(by.Bolt, d, strong) < Attraction.duration(by.Toolbox, d, strong))
	assert(Attraction.duration(by.Toolbox, d, strong) < Attraction.duration(by.SteelSafe, d, strong))
	assert(Attraction.anticipation(by.Bolt, base) < Attraction.anticipation(by.Toolbox, base))
	assert(Attraction.anticipation(by.Toolbox, base) < Attraction.anticipation(by.MotorcycleEngine, base))
	assert(Attraction.anticipation(by.MagneticReactor, strong) > Attraction.anticipation(by.SteelSafe, strong), "legendaries get extra drama")
end)

test("heavy-lift clamps and spare strength speed up heavy pulls", function()
	local weak = Economy.stats({}, 4, 0)
	local clamps = Economy.stats({ Heavy = 5 }, 4, 0)
	assert(Attraction.anticipation(by.SteelSafe, clamps) < Attraction.anticipation(by.SteelSafe, weak))
	assert(Attraction.speed(by.SteelSafe, Economy.stats({}, 6, 0)) > Attraction.speed(by.SteelSafe, weak))
end)

test("pull speed upgrades shorten every flight", function()
	local fast = Economy.stats({ Speed = 10 }, 1, 0)
	assert(Attraction.duration(by.SodaCan, 15, fast) < Attraction.duration(by.SodaCan, 15, base))
end)

test("durations are bounded (never instant, never forever)", function()
	for _, def in ipairs(ScrapConfig.List) do
		for _, d in ipairs({ 0, 5, 40, 400 }) do
			local t = Attraction.duration(def, d, strong)
			assert(t > 0.2 and t <= 3.4, def.Id .. " " .. d .. " -> " .. t)
			assert(t >= Attraction.anticipation(def, strong))
		end
	end
end)

test("flight curve accelerates from 0 to exactly 1 and arcs", function()
	local last = -1
	for i = 0, 20 do
		local along, lift = Attraction.curve(i / 20, 20, by.Gear)
		assert(along >= last, "curve went backwards")
		last = along
		assert(lift >= 0)
	end
	local a0, l0 = Attraction.curve(0, 20, by.Gear)
	local a1, l1 = Attraction.curve(1, 20, by.Gear)
	assert(a0 == 0 and math.abs(a1 - 1) < 1e-9 and l0 == 0 and l1 < 1e-6)
	local early = Attraction.curve(0.25, 20, by.Gear)
	assert(early < 0.25, "should start slow and accelerate")
end)

test("wind-up shake is larger for heavy objects", function()
	local ampLight = Attraction.windup(0.05, 0.1, by.Bolt)
	local ampHeavy = Attraction.windup(0.05, 0.1, by.SteelSafe)
	assert(ampHeavy > ampLight)
	assert(Attraction.windup(1, 0, by.Bolt) == 0)
end)

return cases
