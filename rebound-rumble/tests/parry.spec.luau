local roblox = require("@lune/roblox")
local load = require("./loader")
local BallMath = load("BallMath")
local ParryJudge = load("ParryJudge")
local GameConfig = load("Config/GameConfig")
local Vector3 = roblox.Vector3

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "ParryJudge: " .. name, fn = fn })
end

local P = GameConfig.Parry

-- Ball flying along -X toward a player at the origin at `speed`, sampled at 60 Hz up to `now`.
local function approach(speed, now, startDist)
	local h = BallMath.newHistory()
	for i = 0, 120 do
		local t = now - 1 + i / 120
		local x = startDist - speed * (t - (now - 1))
		BallMath.record(h, t, Vector3.new(math.max(0, x), 0, 0), 2)
	end
	return h
end

test("press inside the window parries", function()
	local now = 100
	local speed = 60
	-- At `now` the ball is at 60 - 60*1 = 0 + ... choose start so it's 8 studs away now.
	local h = approach(speed, now, 8 + speed)
	local r = ParryJudge.judge({ now = now, clientTime = now, history = h, playerPos = Vector3.zero, isTarget = true, speed = speed }, P)
	assert(r.ok, "expected parry, got " .. r.reason .. " at " .. tostring(r.distance))
end)

test("early press is a whiff", function()
	local now = 100
	local h = approach(60, now, 60 + 60)
	local r = ParryJudge.judge({ now = now, clientTime = now, history = h, playerPos = Vector3.zero, isTarget = true, speed = 60 }, P)
	assert(not r.ok and r.reason == "early", r.reason)
end)

test("pressing while not targeted is a whiff", function()
	local h = approach(60, 100, 61)
	local r = ParryJudge.judge({ now = 100, clientTime = 100, history = h, playerPos = Vector3.zero, isTarget = false, speed = 60 }, P)
	assert(not r.ok and r.reason == "not_target")
end)

test("lag compensation rewinds to the press time (bounded)", function()
	local now = 100
	local speed = 80
	-- At `now` the ball has already reached the player; 0.1s ago it was 8 studs away.
	local h = approach(speed, now, speed * 1 - 0 + 0)
	local r = ParryJudge.judge({ now = now, clientTime = now - 0.1, history = h, playerPos = Vector3.zero, isTarget = true, speed = speed, hitTime = now - 0.02 }, P)
	assert(r.ok, "laggy but honest press should parry: " .. r.reason)
	assert(math.abs(r.rewind - 0.1) < 1e-6)
	-- A client claiming it pressed 5 seconds ago only gets MaxRewind.
	assert(ParryJudge.rewindFor(now - 5, now, P) == P.MaxRewind)
end)

test("press after the hit moment is late", function()
	local now = 100
	local h = approach(80, now, 80)
	local r = ParryJudge.judge({ now = now, clientTime = now, history = h, playerPos = Vector3.zero, isTarget = true, speed = 80, hitTime = now - 0.1 }, P)
	assert(not r.ok and r.reason == "late", r.reason)
end)

test("bad timestamps are treated as now", function()
	local now = 50
	assert(ParryJudge.rewindFor(nil, now, P) == 0)
	assert(ParryJudge.rewindFor(0 / 0, now, P) == 0)
	assert(ParryJudge.rewindFor(math.huge, now, P) == 0)
	assert(ParryJudge.rewindFor(-math.huge, now, P) == 0)
	assert(ParryJudge.rewindFor(now + 10, now, P) == 0, "future timestamps must not rewind")
	assert(ParryJudge.rewindFor("x", now, P) == 0)
end)

test("cooldowns: whiffs lock out longer than parries, rate limit holds", function()
	local memo = {}
	assert(ParryJudge.canAttempt(memo, 10, P))
	ParryJudge.applyCooldown(memo, 10, false, P)
	assert(not ParryJudge.canAttempt(memo, 10 + P.WhiffCooldown - 0.01, P))
	assert(ParryJudge.canAttempt(memo, 10 + P.WhiffCooldown + 0.01, P))
	ParryJudge.applyCooldown(memo, 20, true, P)
	assert(not ParryJudge.canAttempt(memo, 20.01, P))
	assert(ParryJudge.canAttempt(memo, 20 + P.SuccessCooldown + 0.01, P))
	assert(P.WhiffCooldown > P.SuccessCooldown * 2, "whiff should be punished")
end)

test("mashing the button parries far less often than one timed press", function()
	local speed = 60
	local function attempt(phase, strategy)
		local memo = {}
		local h = BallMath.newHistory()
		local x, t = 150 + phase, 0
		local range = BallMath.parryRange(speed, P)
		while x > GameConfig.Ball.HitRadius do
			t += 1 / 60
			x -= speed / 60
			BallMath.record(h, t, Vector3.new(x, 0, 0), 1)
			local press
			if strategy == "mash" then
				press = math.floor(t * 30) ~= math.floor((t - 1 / 60) * 30)
			else
				press = x <= range * 0.6 and not memo.lastPress
			end
			if press and ParryJudge.canAttempt(memo, t, P) then
				local r = ParryJudge.judge({ now = t, clientTime = t, history = h, playerPos = Vector3.zero, isTarget = true, speed = speed }, P)
				ParryJudge.applyCooldown(memo, t, r.ok, P)
				if r.ok then
					return true
				end
			end
		end
		return false
	end
	local mash, timed, runs = 0, 0, 40
	for i = 1, runs do
		local phase = i * 1.37
		mash += if attempt(phase, "mash") then 1 else 0
		timed += if attempt(phase, "timed") then 1 else 0
	end
	assert(timed == runs, "timed presses should always parry: " .. timed)
	assert(mash <= runs * 0.6, "mashing succeeded too often: " .. mash .. "/" .. runs)
end)

return cases
