local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local Rng = require("../src/shared/Rng")
local MonsterBrain = require("../src/shared/MonsterBrain")
local MonsterConfig = require("../src/shared/Config/MonsterConfig")

local S = MonsterBrain.States

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "MonsterBrain: " .. name, fn = fn })
end

local function makeProvider(hidingSpot)
	return {
		patrolPoint = function(from)
			return from + Vector3.new(30, 0, 0)
		end,
		searchPoints = function(center, _radius, count)
			local points = {}
			for i = 1, count do
				points[i] = { position = center + Vector3.new(i * 6, 0, 0) }
			end
			if hidingSpot then
				points[1] = { position = center + Vector3.new(2, 0, 0), hidingSpotId = hidingSpot }
			end
			return points
		end,
	}
end

local function newBrain(seed, hidingSpot)
	return MonsterBrain.new(MonsterConfig, Rng.new(seed or 1), makeProvider(hidingSpot))
end

local origin = Vector3.new(0, 0, 0)

test("it cannot sense a player standing still unless it is right on top of them", function()
	local sight = MonsterConfig.Sight
	assert(not MonsterBrain.sensesMotion(0, 20, sight), "a still player 20 studs away was sensed")
	assert(not MonsterBrain.sensesMotion(0.5, 8, sight), "a nearly still player was sensed")
	assert(MonsterBrain.sensesMotion(0, 3, sight), "should bump into a still player at 3 studs")
	assert(MonsterBrain.sensesMotion(5, 40, sight), "a moving (even creeping) player should be sensed")
end)

test("starts patrolling and moves to a patrol point", function()
	local brain = newBrain()
	local intent = brain:update(0, { position = origin })
	assert(brain.state == S.Patrol)
	assert(intent.goal and intent.speed == MonsterConfig.Speeds.Patrol)
end)

test("a loud noise sends it to investigate the noise position, not the player", function()
	local brain = newBrain()
	local noisePos = Vector3.new(40, 0, 10)
	assert(brain:hear({ position = noisePos, intensity = 0.7, category = "MetalDrop" }, 1))
	assert(brain.state == S.Investigate)
	local intent = brain:update(1.1, { position = origin })
	assert(intent.goal == noisePos, "should head to the noise position")
	assert(intent.rush, "loud noise should cause a rush")
	assert(intent.speed == MonsterConfig.Speeds.InvestigateHigh)
end)

test("a single faint noise only causes suspicion", function()
	local brain = newBrain()
	brain:hear({ position = Vector3.new(20, 0, 0), intensity = 0.1, category = "FootstepWalk" }, 1)
	assert(brain.state == S.Suspicion, "got " .. brain.state)
end)

test("a series of faint noises escalates to investigation", function()
	local brain = newBrain()
	local p = Vector3.new(20, 0, 0)
	brain:hear({ position = p, intensity = 0.1, category = "FootstepWalk" }, 1)
	brain:hear({ position = p + Vector3.new(2, 0, 0), intensity = 0.1, category = "FootstepWalk" }, 1.5)
	assert(brain.state == S.Investigate, "got " .. brain.state)
end)

test("ignores noise below the hearing threshold", function()
	local brain = newBrain()
	assert(not brain:hear({ position = Vector3.new(5, 0, 0), intensity = 0.01, category = "FootstepCrouch" }, 1))
	assert(brain.state == S.Patrol)
end)

test("arrival -> listen -> search", function()
	local brain = newBrain()
	local p = Vector3.new(10, 0, 0)
	brain:hear({ position = p, intensity = 0.4, category = "DoorSlam" }, 0)
	brain:update(0.1, { position = p })
	assert(brain.state == S.Investigate and brain.arrivedAt, "should register arrival")
	brain:update(0.1 + MonsterConfig.Investigate.ListenTime + 0.05, { position = p })
	assert(brain.state == S.Search, "got " .. brain.state)
end)

test("search does not instantly give up after arriving", function()
	local brain = newBrain()
	brain:forceSearch(origin, 0)
	local t = 0
	local pos = origin
	for _ = 1, 30 do
		t += 0.1
		local intent = brain:update(t, { position = pos })
		if intent.goal then
			pos = intent.goal
		end
	end
	assert(brain.state == S.Search, "left search after 3s: " .. brain.state)
end)

test("sustained sight escalates to chase; a glimpse only to suspicion", function()
	local brain = newBrain()
	local playerPos = Vector3.new(40, 0, 0)
	brain:perceive({ { id = 1, position = playerPos, velocity = origin, gain = 0.4, distance = 40 } }, 1, 0)
	assert(brain.state == S.Suspicion, "glimpse should cause suspicion, got " .. brain.state)
	for i = 1, 5 do
		brain:perceive({ { id = 1, position = playerPos, velocity = origin, gain = 0.4, distance = 40 } }, 1, i)
	end
	assert(brain.state == S.Chase and brain.targetId == 1)
end)

test("point-blank sight triggers immediate chase", function()
	local brain = newBrain()
	brain:perceive({ { id = 7, position = Vector3.new(5, 0, 0), velocity = origin, gain = 0.1, distance = 5 } }, 0.1, 0)
	assert(brain.state == S.Chase)
end)

test("chase ramps speed up and attacks in range", function()
	local brain = newBrain()
	brain:perceive({ { id = 1, position = Vector3.new(30, 0, 0), velocity = origin, gain = 2, distance = 30 } }, 1, 0)
	local early = brain:update(0.1, { position = origin, target = { valid = true, visible = true, position = Vector3.new(30, 0, 0), velocity = origin, distance = 30 } })
	local later = brain:update(3, { position = origin, target = { valid = true, visible = true, position = Vector3.new(30, 0, 0), velocity = origin, distance = 30 } })
	assert(later.speed > early.speed, "chase should accelerate")
	assert(math.abs(later.speed - MonsterConfig.Speeds.Chase) < 1e-6)
	local attack = brain:update(3.1, { position = origin, target = { valid = true, visible = true, position = Vector3.new(3, 0, 0), velocity = origin, distance = 3 } })
	assert(attack.action == "attack" and brain.state == S.Attack)
end)

test("losing line of sight -> goes to predicted last known position, then searches", function()
	local brain = newBrain()
	local seen = Vector3.new(30, 0, 0)
	local vel = Vector3.new(0, 0, 10)
	brain:perceive({ { id = 1, position = seen, velocity = vel, gain = 2, distance = 30 } }, 1, 0)
	brain:update(0.1, { position = origin, target = { valid = true, visible = true, position = seen, velocity = vel, distance = 30 } })
	brain:update(0.2 + MonsterConfig.Chase.LoseSightTime + 0.1, { position = origin, target = { valid = true, visible = false, distance = 30 } })
	assert(brain.state == S.Lost, "got " .. brain.state)
	local intent = brain:update(3, { position = origin })
	local expected = seen + vel * MonsterConfig.Chase.PredictTime
	assert(intent.goal == expected, "should head toward predicted position")
	assert(intent.goal ~= seen)
	brain:update(3.1, { position = expected })
	assert(brain.state == S.Search and brain.searchAfterChase, "should search after chase")
end)

test("target disconnect/death ends the chase cleanly", function()
	local brain = newBrain()
	brain:perceive({ { id = 1, position = Vector3.new(10, 0, 0), velocity = origin, gain = 2, distance = 10 } }, 1, 0)
	brain:update(0.1, { position = origin, target = { valid = false } })
	assert(brain.state == S.Lost)
end)

test("noise during a chase refreshes the last known position only when nearby", function()
	local brain = newBrain()
	brain:perceive({ { id = 1, position = Vector3.new(10, 0, 0), velocity = origin, gain = 2, distance = 10 } }, 1, 0)
	brain:hear({ position = Vector3.new(14, 0, 0), intensity = 0.6, category = "FootstepSprint" }, 1)
	assert(brain.lastKnown == Vector3.new(14, 0, 0))
	brain:hear({ position = Vector3.new(200, 0, 0), intensity = 0.9, category = "MetalDrop" }, 1.2)
	assert(brain.lastKnown == Vector3.new(14, 0, 0), "distant noise should not steal a chase")
	assert(brain.state == S.Chase)
end)

test("searches check hiding spots near the evidence", function()
	local brain = newBrain(3, "locker_1")
	brain:forceSearch(origin, 0)
	local intent = brain:update(0.1, { position = Vector3.new(2, 0, 0) })
	assert(intent.action == "checkHiding" and intent.hidingSpotId == "locker_1")
	brain:hidingResolved(false, nil, nil, 1)
	assert(brain.state == S.Search)
	brain:forceSearch(origin, 2)
	brain:update(2.1, { position = Vector3.new(2, 0, 0) })
	brain:hidingResolved(true, 5, Vector3.new(2, 0, 0), 3)
	assert(brain.state == S.Chase and brain.targetId == 5)
end)

test("successful attack -> recover -> search, not instantly harmless forever", function()
	local brain = newBrain()
	brain:perceive({ { id = 1, position = Vector3.new(3, 0, 0), velocity = origin, gain = 2, distance = 3 } }, 1, 0)
	brain:update(0.1, { position = origin, target = { valid = true, visible = true, position = Vector3.new(3, 0, 0), velocity = origin, distance = 3 } })
	brain:attackResolved(true, 0.5)
	assert(brain.state == S.Recover)
	brain:update(0.5 + MonsterConfig.Recover.AfterAttackDuration + 0.1, { position = origin })
	assert(brain.state == S.Search)
end)

test("recover ignores small noises but wakes for loud ones", function()
	local brain = newBrain()
	brain:_enterRecover(5, S.Patrol, 0, "test")
	brain:hear({ position = Vector3.new(10, 0, 0), intensity = 0.2, category = "DoorOpen" }, 1)
	assert(brain.state == S.Recover)
	brain:hear({ position = Vector3.new(10, 0, 0), intensity = 0.8, category = "MetalDrop" }, 1.2)
	assert(brain.state == S.Investigate)
end)

test("path failure while investigating falls back to searching", function()
	local brain = newBrain()
	brain:hear({ position = Vector3.new(50, 0, 0), intensity = 0.5, category = "DoorSlam" }, 0)
	brain:update(0.1, { position = origin, pathFailed = true })
	assert(brain.state == S.Search)
end)

return cases
