local L = require("./loader")
local Scoring = L.shared("Scoring")
local ScoringConfig = L.shared("Config/ScoringConfig")
local GameConfig = L.shared("Config/GameConfig")
local Vector3 = L.roblox.Vector3

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Scoring: " .. name, fn = fn })
end

local FORWARD = Vector3.new(0, 0, 1)
local function newRun(cap)
	return Scoring.Run.new(Vector3.new(0, 5, 0), FORWARD, { floorY = 0, impactCap = cap or 10, startTime = 0 })
end

test("distance is the furthest valid point down the course, not path length", function()
	local run = newRun()
	run:sample(Vector3.new(0, 10, 10), 0.1)
	run:sample(Vector3.new(0, 12, 20), 0.2)
	run:sample(Vector3.new(0, 8, 15), 0.3) -- bounced back
	run:sample(Vector3.new(15, 6, 15), 0.4) -- sideways
	local r = run:result()
	assert(r.distance == 20, "distance " .. r.distance)
	assert(r.height == 12, "height " .. r.height)
end)

test("a teleport-sized jump is rejected; three of them void the run", function()
	local run = newRun()
	run:sample(Vector3.new(0, 10, 10), 0.1)
	assert(run:sample(Vector3.new(0, 10, 5000), 0.2) == "anomaly")
	assert(run:result().distance == 10, "teleport counted")
	-- A believable next sample (from the last good point) still works.
	assert(run:sample(Vector3.new(0, 10, 30), 0.3) == "ok")
	run:sample(Vector3.new(0, 900, 30), 0.35)
	run:sample(Vector3.new(0, -900, 30), 0.4)
	local r = run:result()
	assert(r.voided and r.score == 0 and r.coins == ScoringConfig.VoidCoins, "voided run still paid")
	assert(not run:award("Target", "Gong", 300), "awards after voiding")
	assert(run:sample(Vector3.new(0 / 0, 0, 0), 0.5) == "anomaly", "NaN accepted")
end)

test("one physics glitch is one anomaly: later samples are judged over the real elapsed time", function()
	local run = newRun()
	local dt = 1 / GameConfig.Run.SampleRate
	run:sample(Vector3.new(0, 10, 10), dt)
	-- A depenetration fling: 50 studs in one sample gap is faster than any launch.
	assert(run:sample(Vector3.new(0, 10, 60), 2 * dt) == "anomaly")
	-- The dummy carries on from where the glitch left it, at a normal speed.
	assert(run:sample(Vector3.new(0, 10, 64), 3 * dt) == "ok", "a single glitch cascaded")
	assert(run:sample(Vector3.new(0, 10, 68), 4 * dt) == "ok")
	assert(run.anomalies == 1 and not run.voided, "anomalies " .. run.anomalies)
end)

test("fast but legal flight samples are accepted", function()
	local run = newRun()
	local dt = 1 / GameConfig.Run.SampleRate
	local pos = Vector3.new(0, 5, 0)
	for i = 1, 10 do
		pos += Vector3.new(0, 200 * dt, ScoringConfig.MaxLaunchSpeed * 0.9 * dt)
		assert(run:sample(pos, i * dt) == "ok", "legal sample " .. i .. " rejected")
	end
end)

test("impacts: tiers, slow touches ignored, debounce and per-object cap", function()
	local run = newRun(50)
	assert(run:impact("Wall", 10, 1) == nil, "slow touch counted")
	assert(run:impact("Wall", 30, 1) == "Light")
	assert(run:impact("Wall", 120, 1.2) == nil, "debounce ignored")
	assert(run:impact("Wall", 120, 1.6) == "Heavy")
	assert(run:impact("Wall", 200, 2.2) == "Massive")
	assert(run:impact("Wall", 200, 3) == nil, "per-object cap ignored")
	assert(run:impact("Ramp", 60, 3) == "Medium")
	local r = run:result()
	assert(r.impacts == 4 and r.impactTiers.Massive == 1, "counted " .. r.impacts)
	assert(r.impactPoints == 6 + 40 + 75 + 16, "impact points " .. r.impactPoints)
end)

test("impacts: floor bounces are grouped and capped; run cap holds", function()
	local run = newRun(6)
	local n = 0
	for i = 1, 20 do
		if run:impact("FloorTile" .. i, 80, i, "Floor") then
			n += 1
		end
	end
	assert(n == ScoringConfig.Impact.FloorMax, "floor counted " .. n)
	local extra = 0
	for i = 1, 10 do
		if run:impact("Obj" .. i, 80, 100 + i) then
			extra += 1
		end
	end
	assert(n + extra == 6, "run cap ignored: " .. (n + extra))
end)

test("bonuses are awarded once; featured objective multiplies only itself", function()
	local run = newRun()
	assert(run:award("Objective", "RingLow", 100))
	assert(not run:award("Objective", "RingLow", 100), "awarded twice")
	assert(run:award("Target", "Gong", 300))
	run:sample(Vector3.new(0, 5, 50), 0.5)
	local r = run:result({ bonus = 1.5, featured = 3, featuredId = "RingLow", coins = 2 })
	assert(r.bonusPoints == 150 + 450, "bonus " .. r.bonusPoints)
	assert(r.featuredPoints == 300, "featured " .. r.featuredPoints)
	assert(r.score == 50 + 2 + 0 + 600 + 300, "score " .. r.score) -- 2 = height 5 * 0.5
	assert(r.coins == math.floor(r.score * ScoringConfig.CoinsPerPoint * 2))
end)

test("a flop still earns the minimum coins", function()
	local run = newRun()
	run:sample(Vector3.new(0, 5, 0.5), 0.2)
	local r = run:result()
	assert(r.coins == ScoringConfig.MinCoins, "flop paid " .. r.coins)
end)

test("settle, stuck and timeout detection", function()
	local cfg = GameConfig.Run
	local run = newRun()
	run:sample(Vector3.new(0, 1, 10), 0.3)
	assert(run:status(0.4) == nil)
	-- Still, but too early in the run: not settled yet.
	run:sample(Vector3.new(0, 1, 10), 0.5)
	assert(run:status(0.5) == nil, "settled before min air time")
	local t = 0.5
	while t < cfg.MinAirTime + cfg.SettleTime + 0.2 do
		t += 0.1
		run:sample(Vector3.new(0, 1, 10), t)
	end
	assert(run:status(t) == "settled", "did not settle")
	-- Jittering in place fast enough not to "settle" still ends as stuck.
	local stuck = newRun()
	t = 0
	local flip = 1
	while t < cfg.StuckWindow + 1 do
		t += 0.1
		flip = -flip
		stuck:sample(Vector3.new(flip * 0.6, 1, 20), t)
	end
	assert(stuck:status(t) == "stuck", "jitter not detected as stuck: " .. tostring(stuck:status(t)))
	local long = newRun()
	assert(long:status(cfg.MaxDuration + 0.1) == "timeout")
end)

test("ring crossing and landing zones", function()
	local center, radius = Vector3.new(0, 20, 100), 10
	assert(Scoring.crossesRing(Vector3.new(0, 18, 95), Vector3.new(0, 22, 105), center, radius))
	assert(not Scoring.crossesRing(Vector3.new(0, 40, 95), Vector3.new(0, 40, 105), center, radius), "passed over the ring")
	assert(not Scoring.crossesRing(Vector3.new(0, 20, 80), Vector3.new(0, 20, 90), center, radius), "never reached it")
	assert(Scoring.insideZone(Vector3.new(3, 1, 152), Vector3.new(0, 0, 150), 15))
	assert(not Scoring.insideZone(Vector3.new(30, 1, 150), Vector3.new(0, 0, 150), 15))
	assert(not Scoring.insideZone(Vector3.new(0, 40, 150), Vector3.new(0, 0, 150), 15), "hovering above counts as landed")
end)

test("destruction combo: chains within the window, points per step, capped per run", function()
	local CourseConfig = L.shared("Config/CourseConfig")
	local combo = CourseConfig.Courses.Destruction.Tuning.Combo
	local run = Scoring.Run.new(Vector3.new(0, 0, 0), FORWARD, { startTime = 0, tuning = { Combo = combo } })
	assert(run:breakChain(1) == 1 and run.comboPoints == 0, "a single break is not a combo")
	assert(run:breakChain(1 + combo.Window * 0.9) == 2 and run.comboPoints == combo.PerStep)
	assert(run:breakChain(1 + combo.Window * 1.8) == 3 and run.comboPoints == combo.PerStep * 3)
	-- Gap longer than the window: new chain, points kept.
	assert(run:breakChain(10) == 1 and run.comboPoints == combo.PerStep * 3 and run.comboBest == 3)
	for i = 1, 40 do
		run:breakChain(10 + i * 0.1)
		assert(run.comboPoints <= combo.Cap, "combo over the cap")
	end
	assert(run.comboPoints == combo.Cap and run.comboBest == 41)
	-- Courses without a combo never award one.
	local plain = Scoring.Run.new(Vector3.new(0, 0, 0), FORWARD, { startTime = 0 })
	assert(plain:breakChain(1) == 0 and plain:breakChain(1.1) == 0 and plain.comboPoints == 0)
end)

test("free-fall bonus: height lost from the run's peak, min / max, only where tuned", function()
	local CourseConfig = L.shared("Config/CourseConfig")
	local ff = CourseConfig.Courses.HighAltitude.Tuning.FreeFall
	local run = Scoring.Run.new(Vector3.new(0, 0, 0), FORWARD, { startTime = 0, tuning = { FreeFall = ff }, maxSpeed = 420 })
	run.last = Vector3.new(0, 5, 0)
	local t = 0
	local function go(y, z)
		t += 0.1
		assert(run:sample(Vector3.new(0, y, z), t) == "ok")
	end
	go(20, 10)
	go(30, 20) -- peak 30
	go(25, 30)
	assert(run:freeFallPoints() == 0, "a 5-stud drop shouldn't pay")
	for k = 1, 30 do
		go(30 - k * 10, 30 + k * 10)
	end
	assert(math.abs(run.freeFall - 300) < 1e-6, "drop " .. run.freeFall)
	assert(run:freeFallPoints() == math.floor(ff.Max * ff.PerStud), "free fall not capped")
	local hub = Scoring.Run.new(Vector3.new(0, 0, 0), FORWARD, { startTime = 0 })
	hub.last = Vector3.new(0, 50, 0)
	hub:sample(Vector3.new(0, 10, 10), 0.2)
	assert(hub:freeFallPoints() == 0, "hub course pays a free-fall bonus")
	assert(hub:result().freeFall == 0, "hub drop reported as free-fall (records / achievement / daily)")
	assert(run:result().freeFall >= 300, "tuned course lost its free-fall")
end)

test("per-course run limits replace the global ones", function()
	local CourseConfig = L.shared("Config/CourseConfig")
	local limits = CourseConfig.limits(CourseConfig.Courses.GravityLab, GameConfig.Run)
	assert(limits.MaxDuration == 18 and limits.SettleTime == GameConfig.Run.SettleTime and limits.MaxFloatTime == 7)
	local run = Scoring.Run.new(Vector3.new(0, 0, 0), FORWARD, { startTime = 0, limits = limits })
	assert(run:status(17.5) == nil or run:status(17.5) ~= "timeout", "timed out early")
	assert(run:status(18.1) == "timeout", "course time limit ignored")
	assert(GameConfig.Run.MaxDuration ~= 18, "global limits were modified")
end)

return cases
