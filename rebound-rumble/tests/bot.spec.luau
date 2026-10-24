local load = require("./loader")
local BotBrain = load("BotBrain")
local Rng = load("Rng")
local BallMath = load("BallMath")
local GameConfig = load("Config/GameConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "BotBrain: " .. name, fn = fn })
end

test("chance falls with ball speed and stays bounded", function()
	local slow = BotBrain.chance(0.8, GameConfig.Ball.BaseSpeed, GameConfig.Bots, GameConfig.Ball)
	local fast = BotBrain.chance(0.8, 250, GameConfig.Bots, GameConfig.Ball)
	assert(slow > fast, "faster ball should be harder")
	assert(BotBrain.chance(5, 0, GameConfig.Bots, GameConfig.Ball) == GameConfig.Bots.MaxChance)
	assert(BotBrain.chance(-1, 999, GameConfig.Bots, GameConfig.Ball) == GameConfig.Bots.MinChance)
end)

test("successful plans press inside the parry window; failures press early or never", function()
	local rng = Rng.new(3)
	local speed = 100
	local range = BallMath.parryRange(speed, GameConfig.Parry)
	local successes = 0
	for _ = 1, 500 do
		local plan = BotBrain.plan(0.75, speed, rng, GameConfig)
		if plan.success then
			successes += 1
			assert(plan.pressAt <= range and plan.pressAt > GameConfig.Ball.HitRadius, "success outside window")
		else
			assert(plan.pressAt == nil or plan.pressAt > range, "failure inside window")
		end
	end
	local expected = BotBrain.chance(0.75, speed, GameConfig.Bots, GameConfig.Ball) * 500
	assert(math.abs(successes - expected) < 60, "success rate off: " .. successes .. " vs " .. expected)
end)

test("shouldPress triggers once at the planned distance", function()
	local plan = { pressAt = 10, success = true }
	assert(not BotBrain.shouldPress(plan, 11))
	assert(BotBrain.shouldPress(plan, 9.5))
	plan.pressed = true
	assert(not BotBrain.shouldPress(plan, 5))
	assert(not BotBrain.shouldPress({ pressAt = nil }, 1))
end)

test("chooseAim never picks itself", function()
	local rng = Rng.new(11)
	local list = { { id = "a" }, { id = "b" }, { id = "c" } }
	for _ = 1, 200 do
		local c = BotBrain.chooseAim("a", list, "b", rng)
		assert(c and c.id ~= "a")
	end
	assert(BotBrain.chooseAim("a", { { id = "a" } }, nil, rng) == nil)
end)

return cases
