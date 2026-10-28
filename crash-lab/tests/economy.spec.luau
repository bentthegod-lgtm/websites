local L = require("./loader")
local Economy = L.shared("Economy")
local Scoring = L.shared("Scoring")
local UpgradeConfig = L.shared("Config/UpgradeConfig")
local MachineConfig = L.shared("Config/MachineConfig")
local ScoringConfig = L.shared("Config/ScoringConfig")
local Rng = L.shared("Rng")
local Vector3 = L.roblox.Vector3

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "Economy: " .. name, fn = fn })
end

local function profileWith(upgrades, extra)
	local p = { Upgrades = upgrades or {}, Prestige = { Credits = 0 } }
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	return p
end

-- A simple ballistic flight sampled like the server does (no bounces), fed to the real
-- run tracker. Returns the run result.
local function simulateFlight(machineId, upgrades, request)
	local machine = MachineConfig.ById[machineId]
	local stats = Economy.stats(profileWith(upgrades))
	local launch = Economy.launch(machine, stats, request or { Power = 1, Angle = 45 }, 0, nil)
	local origin = Vector3.new(0, machine.LaunchHeight, 0)
	local run = Scoring.Run.new(origin, Vector3.new(0, 0, 1), { floorY = 0, impactCap = stats.ImpactCap, startTime = 0 })
	local v = launch.Velocity
	local pos = origin
	local t = 0
	local dt = 1 / 12
	while t < 20 do
		t += dt
		local nextPos = pos + v * dt + Vector3.new(0, -0.5 * 196.2 * dt * dt, 0)
		v = v + Vector3.new(0, -196.2 * dt, 0)
		if nextPos.Y <= 1 then
			-- Land: one floor impact, then slide to a stop.
			run:impact("Floor", v.Magnitude, t, "Floor")
			nextPos = Vector3.new(nextPos.X, 1, nextPos.Z)
			run:sample(nextPos, t)
			pos = nextPos
			for i = 1, 30 do
				run:sample(pos, t + i * dt)
			end
			break
		end
		run:sample(nextPos, t)
		pos = nextPos
	end
	return run:result({ impact = stats.ImpactMultiplier, bonus = stats.BonusMultiplier, coins = stats.CoinMultiplier }), launch, stats
end

test("upgrade prices rise every level and stop at max", function()
	for _, def in ipairs(UpgradeConfig.List) do
		local last = 0
		for level = 0, def.Max - 1 do
			local price = Economy.cost(def.Key, level)
			assert(price and price > last, def.Key .. " level " .. level .. " price " .. tostring(price))
			last = price
		end
		assert(Economy.cost(def.Key, def.Max) == nil, def.Key .. " should be maxed")
	end
	assert(Economy.cost("Bogus", 0) == nil)
end)

test("every upgrade level changes how a launch plays (no dead upgrades)", function()
	local fields = { "SpeedMultiplier", "CooldownReduction", "AngleMin", "AngleMax", "ChargeMultiplier", "SpreadDegrees", "ImpactCap", "ImpactMultiplier", "BonusMultiplier", "FeaturedMultiplier", "CoinMultiplier" }
	for _, def in ipairs(UpgradeConfig.List) do
		for level = 0, def.Max - 1 do
			local a = Economy.stats(profileWith({ [def.Key] = level }))
			local b = Economy.stats(profileWith({ [def.Key] = level + 1 }))
			local changed = a.Dummy ~= b.Dummy or #a.SpinModes ~= #b.SpinModes
			for _, f in ipairs(fields) do
				if a[f] ~= b[f] then
					changed = true
				end
			end
			assert(changed, def.Key .. " level " .. (level + 1) .. " changes nothing")
		end
	end
end)

test("client requests are clamped to what the player has unlocked", function()
	local machine = MachineConfig.ById.Standard
	local stats = Economy.stats(profileWith({}))
	local r = Economy.sanitise(machine, stats, { Power = 0 / 0, Angle = 89, Aim = 400, Spin = "Chaos" })
	assert(r.Power == 1 and r.Angle == 45 and r.Aim == Economy.MaxAim and r.Spin == "None", "bad clamp")
	r = Economy.sanitise(machine, stats, { Power = -5, Angle = -10 })
	assert(r.Power == machine.MinPower and r.Angle == 45)
	r = Economy.sanitise(machine, stats, "garbage")
	assert(r.Power == 1 and r.Angle == 45 and r.Aim == 0)
	local wide = Economy.stats(profileWith({ Angles = 3, Spin = 3 }))
	r = Economy.sanitise(machine, wide, { Angle = 17, Spin = "Chaos", Power = 0.73 })
	assert(r.Angle == 15 and r.Spin == "Chaos" and math.abs(r.Power - 0.75) < 1e-6, "snap failed: " .. r.Angle .. " " .. r.Power)
	-- Air cannon refuses to fire below half pressure.
	assert(Economy.sanitise(MachineConfig.ById.AirCannon, stats, { Power = 0.1 }).Power == 0.5)
end)

test("no combination of upgrades exceeds the server speed clamp", function()
	local maxed = {}
	for _, def in ipairs(UpgradeConfig.List) do
		maxed[def.Key] = def.Max
	end
	local stats = Economy.stats(profileWith(maxed, { Prestige = { Credits = 999 } }))
	for _, id in ipairs(MachineConfig.Order) do
		local l = Economy.launch(MachineConfig.ById[id], stats, { Power = 1, Angle = 45 }, 0, Rng.new(4))
		assert(l.Speed <= ScoringConfig.MaxLaunchSpeed + 1e-6, id .. " launches at " .. l.Speed)
		assert(math.abs(l.Velocity.Magnitude - l.Speed) < 1e-3)
	end
	assert(stats.CoinMultiplier <= (1 + 0.06 * 8) * 2 + 1e-6, "credit bonus not capped")
end)

test("the three machines really behave differently", function()
	local stats = Economy.stats(profileWith({}))
	local request = { Power = 1, Angle = 45 }
	local s = Economy.launch(MachineConfig.ById.Standard, stats, request, 0, nil)
	local sp = Economy.launch(MachineConfig.ById.Spring, stats, request, 0, nil)
	local air = Economy.launch(MachineConfig.ById.AirCannon, stats, request, 0, nil)
	assert(sp.Elevation < s.Elevation and air.Elevation > s.Elevation, "trajectories are the same")
	assert(s.Speed < sp.Speed and sp.Speed < air.Speed, "speeds should rise Standard < Spring < Air")
	assert(s.Spin.Magnitude == 0 and sp.Spin.X < 0 and air.Spin.X > 0, "spin profiles")
	assert(Economy.chargeTime(MachineConfig.ById.AirCannon, stats) > Economy.chargeTime(MachineConfig.ById.Standard, stats))
	-- Precision removes the random spread entirely at max.
	local precise = Economy.stats(profileWith({ Precision = 5 }))
	local a = Economy.launch(MachineConfig.ById.Standard, precise, request, 0, Rng.new(1))
	local b = Economy.launch(MachineConfig.ById.Standard, precise, request, 0, Rng.new(99))
	assert((a.Direction - b.Direction).Magnitude < 1e-6, "precision 5 still has spread")
end)

test("first launch earns enough for the first upgrade within ~3 launches", function()
	local result = simulateFlight("Standard", {}, nil)
	assert(result.distance > 40, "first launch only reached " .. result.distance)
	local launches = math.ceil(Economy.cost("Power", 0) / result.coins)
	assert(launches <= 3, string.format("first upgrade needs %d launches (%d coins each)", launches, result.coins))
	-- Power 1 is a visible difference (>= 10% further).
	local better = simulateFlight("Standard", { Power = 1 }, nil)
	assert(better.distance >= result.distance * 1.1, string.format("Power 1: %.1f -> %.1f", result.distance, better.distance))
end)

test("machine unlock requirements are reachable with the previous machine", function()
	local maxPower = { Power = 12, Angles = 3 }
	local stats = Economy.stats(profileWith(maxPower))
	local standardReach = Economy.reach(MachineConfig.ById.Standard, stats)
	assert(standardReach >= MachineConfig.ById.Spring.Requirement.Value * 1.2, "Spring unreachable: " .. standardReach)
	local springReach = Economy.reach(MachineConfig.ById.Spring, stats)
	assert(springReach >= MachineConfig.ById.AirCannon.Requirement.AndValue * 1.1, "Air Cannon unreachable: " .. springReach)
	local fresh = Economy.stats(profileWith({}))
	assert(Economy.reach(MachineConfig.ById.Standard, fresh) < MachineConfig.ById.Spring.Requirement.Value, "Spring requirement trivially met on day one")
	assert(Economy.meets(MachineConfig.ById.AirCannon.Requirement, { Payload = 1, BestDistance = 300 }))
	assert(not Economy.meets(MachineConfig.ById.AirCannon.Requirement, { Payload = 1, BestDistance = 299 }))
	assert(not Economy.meets(MachineConfig.ById.AirCannon.Requirement, { Payload = 0, BestDistance = 999 }))
end)

test("cooldown and charge time never drop below sane floors", function()
	local stats = Economy.stats(profileWith({ Cooldown = 5, Precision = 5 }))
	for _, id in ipairs(MachineConfig.Order) do
		local m = MachineConfig.ById[id]
		assert(Economy.cooldown(m, stats) >= 2)
		assert(Economy.chargeTime(m, stats) >= m.ChargeTime * 0.5 - 1e-6)
	end
end)

return cases
