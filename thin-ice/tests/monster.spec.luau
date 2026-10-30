local L = require("./loader")
local MonsterBrain = L.shared("MonsterBrain")
local GameConfig = L.shared("Config/GameConfig")
local Rng = L.shared("Rng")
local V3 = L.roblox.Vector3

local cases = {}
local function test(name, fn)
	table.insert(cases, { name = "MonsterBrain: " .. name, fn = fn })
end

local M = GameConfig.Monster
local function brain(wakeAt)
	return MonsterBrain.new({
		huntSpeed = 17,
		wakeAt = wakeAt or 10,
		prowlPoint = function(from)
			return from + V3.new(30, 0, 0)
		end,
		rng = Rng.new(3),
	})
end

test("dormant during the grace period: deaf, then wakes and prowls", function()
	local b = brain(10)
	assert(not b:hear({ position = V3.new(), intensity = 1 }, 5), "heard while dormant")
	assert(b:update(5, V3.new()).state == "Dormant")
	local intent = b:update(10, V3.new())
	assert(intent.state == "Prowl" and intent.goal and intent.speed == M.ProwlSpeed)
end)

test("faint sound -> investigate; loud sound -> hunt the source; quiet sounds ignored", function()
	local b = brain(0)
	b:update(0, V3.new())
	assert(not b:hear({ position = V3.new(5, 0, 5), intensity = GameConfig.Noise.HearThreshold * 0.5 }, 1), "heard a whisper")
	assert(b:hear({ position = V3.new(5, 0, 5), intensity = 0.3 }, 1) and b.state == "Investigate")
	local intent = b:update(1.1, V3.new())
	assert(intent.speed == M.InvestigateSpeed and intent.goal.X == 5)
	b:hear({ position = V3.new(9, 0, 9), intensity = 0.9, source = "alice" }, 2)
	assert(b.state == "Hunt" and b.target == "alice")
	assert(b:update(2.1, V3.new()).speed == 17)
	-- While hunting, even a faint new sound redirects it.
	b:hear({ position = V3.new(-4, 0, 0), intensity = 0.2, source = "bob" }, 3)
	assert(b.state == "Hunt" and b.goal.X == -4)
end)

test("feels footsteps beside it; catching -> recover -> prowl", function()
	local b = brain(0)
	b:update(0, V3.new())
	assert(b:feel("carl", V3.new(2, 0, 2), 1) and b.state == "Hunt" and b.target == "carl")
	b:caught(2)
	assert(b.state == "Recover" and not b:awake() and b.target == nil)
	assert(not b:hear({ position = V3.new(), intensity = 1 }, 3), "heard while recovering")
	assert(b:update(2 + M.RecoverTime * 0.5, V3.new()).speed == 0)
	assert(b:update(2 + M.RecoverTime, V3.new()).state == "Prowl")
end)

test("hunt goes quiet -> search around the last sound -> gives up and prowls", function()
	local b = brain(0)
	b:update(0, V3.new())
	b:hear({ position = V3.new(20, 0, 0), intensity = 0.9 }, 1)
	local s = b:update(1 + M.InvestigateTime, V3.new(0, 0, 0))
	assert(s.state == "Search", s.state)
	local intent = b:update(1 + M.InvestigateTime + 0.1, V3.new(20, 0, 0))
	assert(intent.goal and (intent.goal - V3.new(20, 0, 0)).Magnitude <= 16.01, "search strays from the sound")
	assert(b:update(1 + M.InvestigateTime + M.SearchTime + 0.2, V3.new()).state == "Prowl")
end)

test("losing the target falls back to searching; listen pause after reaching a prowl point", function()
	local b = brain(0)
	b:update(0, V3.new())
	b:hear({ position = V3.new(9, 0, 0), intensity = 0.9, source = "dee" }, 1)
	b:loseTarget(2)
	assert(b.state == "Search" and b.target == nil)
	local c = brain(0)
	local intent = c:update(0, V3.new())
	c:update(1, intent.goal)
	assert(c.state == "Listen")
	assert(c:update(1 + M.ListenPause * 0.5, intent.goal).speed == 0)
	assert(c:update(1 + M.ListenPause, intent.goal).state == "Prowl")
	assert(#c.history >= 3 and c.history[1].from == "Dormant")
end)

test("arrive: an unreachable goal counts as reached, so prowling never stalls", function()
	local b = brain(0)
	local intent = b:update(0, V3.new())
	assert(intent.state == "Prowl")
	b:arrive(V3.new(5, 0, 0))
	assert(b:update(0.2, V3.new(5, 0, 0)).state == "Listen", "still walking at an unreachable point")
	b:hear({ position = V3.new(40, 0, 0), intensity = 0.3 }, 3)
	assert(b.state == "Investigate")
	b:arrive(V3.new(10, 0, 0))
	assert(b:update(3.2, V3.new(10, 0, 0)).state == "Search")
end)

test("smarter on Hard / Nightmare: it keeps searching around a lost sound longer", function()
	local function searchLength(scale)
		local b = MonsterBrain.new({ huntSpeed = 19, wakeAt = 0, searchScale = scale, prowlPoint = function(from)
			return from + V3.new(30, 0, 0)
		end, rng = Rng.new(2) })
		b:update(0, V3.new())
		b:hear({ position = V3.new(9, 0, 0), intensity = 0.9 }, 1)
		b:loseTarget(2)
		local t = 2
		while b.state == "Search" and t < 60 do
			t += 0.1
			b:update(t, V3.new(9, 0, 0))
		end
		return t - 2
	end
	assert(searchLength(2) > searchLength(1) * 1.8, "search scale ignored")
	assert(GameConfig.Difficulties.Nightmare.MonsterSearch > GameConfig.Difficulties.Normal.MonsterSearch)
end)

return cases
