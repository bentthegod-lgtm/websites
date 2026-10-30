local L = require("./loader")
local Presence = L.shared("Presence")
local GameConfig = L.shared("Config/GameConfig")
local Rng = L.shared("Rng")

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Presence: " .. name, fn = fn })
end

local P = GameConfig.Presence

test("cues by distance: far call, near breath + steps, heartbeat + vignette inside 30, silhouette band", function()
	local far = Presence.cues(P.FarCall + 10, "Prowl", false)
	assert(far.call and not far.breath and not far.heartbeat and far.vignette == 0)
	local near = Presence.cues(P.Near - 1, "Prowl", false)
	assert(not near.call and near.breath and near.steps and not near.heartbeat)
	local close = Presence.cues(10, "Hunt", false)
	assert(close.heartbeat and close.vignette > 0.5 and not close.chase)
	assert(Presence.cues(P.Heartbeat + 0.1, "Prowl").vignette == 0 and Presence.cues(6, "Prowl").vignette == 1)
	assert(Presence.cues(80, "Prowl").silhouette and not Presence.cues(30, "Prowl").silhouette and not Presence.cues(200, "Prowl").silhouette)
	-- listening: it stands still (no steps) but you still hear it breathe
	local listen = Presence.cues(10, "Listen")
	assert(listen.breath and not listen.steps)
end)

test("asleep (or missing / junk distance) = no cues; chase only when it hunts YOU", function()
	for _, c in ipairs({ Presence.cues(5, "Dormant"), Presence.cues(5, nil), Presence.cues(nil, "Hunt"), Presence.cues(0 / 0, "Hunt") }) do
		assert(not c.call and not c.breath and not c.heartbeat and c.vignette == 0 and not c.chase)
	end
	assert(Presence.cues(40, "Hunt", true).chase and not Presence.cues(40, "Investigate", true).chase and not Presence.cues(40, "Hunt", false).chase)
	assert(Presence.heartRate(6) > Presence.heartRate(29))
end)

test("fog: thicker further out, whiteout closes it hard, reduced effects caps it", function()
	local shore = Presence.fog(GameConfig.Lake.ShoreZ)
	local far = Presence.fog(GameConfig.Lake.ShoreZ + 400)
	assert(math.abs(shore - GameConfig.Lake.FogNear) < 1e-6 and math.abs(far - GameConfig.Lake.FogFar) < 1e-6 and far > shore)
	assert(Presence.fog(100, true) >= 0.8 and Presence.fog(100, true, true) <= 0.45)
	assert(Presence.fog(-50) == shore and Presence.fog(0 / 0) == shore)
end)

test("ambient scares: never in the first minute, spaced out, never the same twice", function()
	assert(not Presence.scareAllowed(100 + P.ScareGraceTime - 1, 100, nil))
	assert(Presence.scareAllowed(100 + P.ScareGraceTime + 1, 100, nil))
	assert(not Presence.scareAllowed(500, 100, 500 - P.ScareGapMin + 1) and Presence.scareAllowed(500, 100, 500 - P.ScareGapMin))
	assert(not Presence.scareAllowed(500, nil, nil), "scare outside a round")
	local rng = Rng.new(5)
	local last
	local seen = {}
	for _ = 1, 60 do
		local kind = Presence.pickScare(rng, last)
		assert(kind ~= last, "same scare twice")
		seen[kind] = true
		last = kind
		local at = Presence.nextScareAt(0, rng)
		assert(at >= P.ScareGapMin and at <= P.ScareGapMax)
	end
	for _, kind in ipairs(Presence.ScareKinds) do
		assert(seen[kind], kind .. " never picked")
	end
end)

test("head pose: slow idle tilt; listening cocks the head hard and lifts the snout", function()
	local maxIdle = 0
	for t = 0, 30, 0.25 do
		local roll = Presence.headPose(t, "Prowl")
		maxIdle = math.max(maxIdle, math.abs(roll))
	end
	local roll, pitch = Presence.headPose(3, "Listen")
	assert(roll > maxIdle and pitch < 0, "listening pose not distinct")
	assert(maxIdle > math.rad(5), "idle too still")
end)

return cases
