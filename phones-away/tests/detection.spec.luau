local load = require("./loader")
local Detection = load("Detection")
local TeacherConfig = load("Config/TeacherConfig")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Detection: " .. name, fn = fn })
end

local function observer(heading, extra)
	local o = { x = 0, z = -15, heading = heading or 0, fov = TeacherConfig.Sight.FovDegrees, sight = 1, hearing = 1, checking = false }
	for k, v in pairs(extra or {}) do
		o[k] = v
	end
	return o
end

local function student(extra)
	local s = { x = 0, z = 4, phone = "up", sinceHidden = math.huge, linger = 1.0, glow = 1, cover = 1, noise = 0 }
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

test("a phone in front of her is seen; behind her it is not", function()
	local seen = Detection.gain(observer(0), student(), TeacherConfig)
	local behind = Detection.gain(observer(math.pi), student(), TeacherConfig)
	assert(seen > 0.2, "front gain " .. seen)
	assert(behind == 0, "back gain " .. behind)
end)

test("hidden phone is invisible, a just-hidden one still glows a little", function()
	assert(Detection.gain(observer(0), student({ phone = "down" }), TeacherConfig) == 0)
	local linger = Detection.gain(observer(0), student({ phone = "down", sinceHidden = 0.3 }), TeacherConfig)
	local full = Detection.gain(observer(0), student(), TeacherConfig)
	assert(linger > 0 and linger < full, "linger " .. linger)
	assert(Detection.gain(observer(0), student({ phone = "down", sinceHidden = 2 }), TeacherConfig) == 0)
end)

test("the cone edge is soft and the far side is out of view", function()
	local o = observer(0)
	local inside = Detection.cone(o, 0, 10, TeacherConfig.Sight)
	-- 70 degrees off the cone: outside
	local x = math.sin(math.rad(70)) * 20
	local z = -15 + math.cos(math.rad(70)) * 20
	local outside = Detection.cone(o, x, z, TeacherConfig.Sight)
	local fov = TeacherConfig.Sight.FovDegrees
	local edgeX = math.sin(math.rad(fov)) * 20
	local edgeZ = -15 + math.cos(math.rad(fov)) * 20
	local edge = Detection.cone(o, edgeX, edgeZ, TeacherConfig.Sight)
	assert(inside == 1, "inside " .. inside)
	assert(outside == 0, "outside " .. outside)
	assert(edge > 0.3 and edge < 0.7, "edge " .. edge)
end)

test("case, cover and distance reduce sight gain", function()
	local base = Detection.gain(observer(0), student(), TeacherConfig)
	local cased = Detection.gain(observer(0), student({ glow = 0.6 }), TeacherConfig)
	local covered = Detection.gain(observer(0), student({ cover = 0.7 }), TeacherConfig)
	local far = Detection.gain(observer(0), student({ z = 30 }), TeacherConfig)
	assert(cased < base and covered < base and far < base)
end)

test("board phase (sight 0) only hears; earbuds reduce noise", function()
	local o = observer(math.pi, { sight = 0, hearing = 0.7 })
	local sight, noise = Detection.gain(o, student({ noise = 0.5 }), TeacherConfig)
	assert(sight == 0 and noise > 0)
	local loud = Detection.addNoise(0, 3, 1, TeacherConfig.Hearing)
	local quiet = Detection.addNoise(0, 3, 0.4, TeacherConfig.Hearing)
	assert(quiet < loud)
	assert(Detection.decayNoise(loud, 10, TeacherConfig.Hearing) == 0)
end)

test("desk checks up close are brutal even with cover", function()
	local o = observer(math.pi, { x = 0, z = 0, checking = true }) -- facing away!
	local s = student({ x = 2, z = 2, cover = 0.64 })
	local gain = Detection.gain(o, s, TeacherConfig)
	assert(gain >= 0.8, "desk check gain " .. gain)
end)

test("selfie flash in view is reported and much brighter", function()
	local normal = Detection.gain(observer(0), student(), TeacherConfig)
	local flash, _, seen = Detection.gain(observer(0), student({ flash = true }), TeacherConfig)
	assert(seen and flash > normal * 3)
	local _, _, seenBehind = Detection.gain(observer(math.pi), student({ flash = true }), TeacherConfig)
	assert(not seenBehind)
end)

test("suspicion rises, waits, then decays; marks at ? and !", function()
	local cfg = TeacherConfig.Suspicion
	local state = { value = 0 }
	for _ = 1, 10 do
		Detection.step(state, 0.5, 0, 0.1, cfg)
	end
	assert(math.abs(state.value - 0.5) < 1e-6)
	assert(Detection.mark(state.value, cfg) == "?")
	Detection.step(state, 0, 0, 0.5, cfg)
	assert(math.abs(state.value - 0.5) < 1e-6, "decayed before the delay")
	for _ = 1, 30 do
		Detection.step(state, 0, 0, 0.1, cfg)
	end
	assert(state.value < 0.5)
	Detection.step(state, 0, 0.9, 0.1, cfg)
	assert(state.value == 1 and Detection.mark(state.value, cfg) == "!")
end)

test("turnToward is rate limited and wraps the short way", function()
	local h = Detection.turnToward(math.rad(170), math.rad(-170), math.rad(5))
	assert(math.abs(math.deg(h) - 175) < 1e-6, "turned the long way: " .. math.deg(h))
	local done = Detection.turnToward(0, 0.1, 1)
	assert(math.abs(done - 0.1) < 1e-9)
end)

return cases
