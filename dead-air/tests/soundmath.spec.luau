local SoundMath = require("../src/shared/SoundMath")
local SoundConfig = require("../src/shared/Config/SoundConfig")
local PlayerConfig = require("../src/shared/Config/PlayerConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "SoundMath: " .. name, fn = fn })
end

local cats = SoundConfig.Categories

test("falloff is 1 at source and 0 at radius", function()
	assert(math.abs(SoundMath.falloff(0, 50, 1) - 1) < 1e-9)
	assert(SoundMath.falloff(50, 50, 1) == 0)
	assert(SoundMath.falloff(60, 50, 1) == 0)
end)

test("walls muffle sound", function()
	local open = SoundMath.perceived(1, 60, 20, SoundMath.occlusion(0, 0, 0, SoundConfig.Occlusion), 1)
	local walled = SoundMath.perceived(1, 60, 20, SoundMath.occlusion(2, 0, 0, SoundConfig.Occlusion), 1)
	assert(walled < open * 0.3, "two walls should muffle strongly")
end)

test("sprinting is heard much farther than crouching", function()
	local d = 15
	local crouch = SoundMath.perceived(cats.FootstepCrouch.Loudness, cats.FootstepCrouch.Radius, d, 1, 1)
	local sprint = SoundMath.perceived(cats.FootstepSprint.Loudness, cats.FootstepSprint.Radius, d, 1, 1)
	assert(crouch == 0, "crouch steps audible at 15 studs")
	assert(sprint > 0.3, "sprint too quiet at 15 studs: " .. sprint)
end)

test("breaker pull carries across the facility", function()
	local v = SoundMath.perceived(cats.BreakerPull.Loudness, cats.BreakerPull.Radius, 100, SoundMath.occlusion(1, 0, 0, SoundConfig.Occlusion), 1)
	assert(v > 0.06, "breaker should be audible 100 studs away through a wall: " .. v)
end)

test("uncertainty grows with distance and muffling, capped", function()
	local cfg = SoundConfig
	local near = SoundMath.uncertainty(10, 1, cfg)
	local far = SoundMath.uncertainty(60, 1, cfg)
	local muffled = SoundMath.uncertainty(60, 0.2, cfg)
	assert(near < far and far < muffled)
	assert(SoundMath.uncertainty(1000, 0, cfg) == cfg.MaxJitter)
end)

test("gait classification", function()
	assert(SoundMath.gait(0, PlayerConfig) == nil)
	assert(SoundMath.gait(5, PlayerConfig) == "Crouch")
	assert(SoundMath.gait(10, PlayerConfig) == "Walk")
	assert(SoundMath.gait(19, PlayerConfig) == "Sprint")
end)

test("creeping while crouched is silent; crouch-running is quiet but heard nearby", function()
	assert(SoundMath.gait(PlayerConfig.CrouchSpeed, PlayerConfig, true) == nil, "creep should be silent")
	-- a bit of network jitter on a creeping player stays silent
	assert(SoundMath.gait(PlayerConfig.CrouchSpeed + 1.4, PlayerConfig, true) == nil, "jitter made noise")
	assert(SoundMath.gait(PlayerConfig.CrouchRunSpeed, PlayerConfig, true) == "CrouchRun")
	local cats = SoundConfig.Categories
	local near = SoundMath.perceived(cats.FootstepCrouchRun.Loudness, cats.FootstepCrouchRun.Radius, 6, 1, 1)
	local far = SoundMath.perceived(cats.FootstepCrouchRun.Loudness, cats.FootstepCrouchRun.Radius, 20, 1, 1)
	assert(near > 0.06, "crouch-run should be audible up close: " .. near)
	assert(far == 0, "crouch-run should not carry 20 studs")
end)

return cases
