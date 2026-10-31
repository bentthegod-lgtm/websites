local Loader = require("./loader")
local RaceMath = Loader.shared("RaceMath")
local MapData = Loader.shared("MapData")
local ChaosCity = Loader.shared("Maps/ChaosCity")
local GameConfig = Loader.shared("Config/GameConfig")
local V3, CF = Loader.roblox.Vector3, Loader.roblox.CFrame

local data = MapData.compile(ChaosCity)
local gates = data.checkpoints
local main = data.main

-- Moves a racer along the main track from distance a to b in small steps, feeding gates.
local function drive(progress, a, b, now, laps, lateral)
	local events = {}
	local step = 5
	local d = a
	local prev = main:point(d, lateral or 0) + V3.new(0, 1.4, 0)
	while d < b do
		d = math.min(b, d + step)
		local p = main:point(d % main.length, lateral or 0) + V3.new(0, 1.4, 0)
		local e, lapTime = RaceMath.feed(progress, gates, prev, p, now + d / 100, laps)
		if e then
			table.insert(events, { e = e, lapTime = lapTime, d = d })
		end
		prev = p
	end
	return events
end

local function count(events, name)
	local n = 0
	for _, e in ipairs(events) do
		if e.e == name then
			n += 1
		end
	end
	return n
end

return {
	{
		name = "Race: gates count forward crossings inside their width only",
		fn = function()
			local gate = { cframe = CF.lookAt(V3.new(0, 0, 0), V3.new(0, 0, -1)), halfWidth = 10 }
			assert(RaceMath.crossed(gate, V3.new(0, 1, 2), V3.new(0, 1, -2)), "forward")
			assert(not RaceMath.crossed(gate, V3.new(0, 1, -2), V3.new(0, 1, 2)), "backward counted")
			assert(RaceMath.crossedBackwards(gate, V3.new(0, 1, -2), V3.new(0, 1, 2)), "backward not detected")
			assert(not RaceMath.crossed(gate, V3.new(15, 1, 2), V3.new(15, 1, -2)), "outside the gate")
			assert(not RaceMath.crossed(gate, V3.new(0, 40, 2), V3.new(0, 40, -2)), "far above (the overpass) counted")
		end,
	},
	{
		name = "Race: 3 clean laps -> start, every checkpoint in order, 2 laps, finish with lap times",
		fn = function()
			local p = RaceMath.newProgress()
			local events = drive(p, main.length - 60, main.length * 4 + 30, 0, 3)
			assert(events[1].e == "start", "first event " .. events[1].e)
			assert(count(events, "checkpoint") == (#gates - 1) * 3, "checkpoints " .. count(events, "checkpoint"))
			assert(count(events, "lap") == 2 and count(events, "finish") == 1, "laps")
			assert(p.finished and p.lap == 4 and #p.lapTimes == 3 and p.best, "finished state")
			assert(count(events, "skip") == 0)
			assert(RaceMath.feed(p, gates, V3.new(), V3.new(1, 0, 0), 999, 3) == nil, "finished racer still fed")
		end,
	},
	{
		name = "Race: skipping checkpoints never counts a lap (cut across, reverse over the line)",
		fn = function()
			local p = RaceMath.newProgress()
			drive(p, main.length - 60, main.length + 900, 0, 3) -- start + a couple of gates
			local lapBefore, nextBefore = p.lap, p.nextCp
			-- teleport-free cut: straight from here to just before the finish line, then over it
			local here = main:point(900, 0) + V3.new(0, 1.4, 0)
			local nearLine = main:point(main.length - 20, 0) + V3.new(0, 1.4, 0)
			local over = main:point(20, 0) + V3.new(0, 1.4, 0)
			local e1 = RaceMath.feed(p, gates, here, nearLine, 50, 3)
			local e2 = RaceMath.feed(p, gates, nearLine, over, 51, 3)
			assert(p.lap == lapBefore and p.nextCp == nextBefore, "a cut changed the lap / checkpoint")
			assert(e1 == "skip" or e2 == "skip", "the skip was not flagged")
			assert(p.skips >= 1)
			-- driving backwards over the line doesn't count either
			local q = RaceMath.newProgress()
			drive(q, main.length - 60, main.length + 30, 0, 3)
			assert(q.lap == 1)
			local a = main:point(30, 0) + V3.new(0, 1.4, 0)
			local b = main:point(main.length - 30, 0) + V3.new(0, 1.4, 0)
			RaceMath.feed(q, gates, a, b, 5, 3)
			RaceMath.feed(q, gates, b, a, 6, 3)
			assert(q.lap == 1, "reverse + forward over the line counted a lap")
		end,
	},
	{
		name = "Race: positions rank by finished, lap, checkpoint, then distance to the next checkpoint",
		fn = function()
			local function racer(lap, nextCp, dist, finished, finishTime, join)
				local p = RaceMath.newProgress()
				p.lap, p.nextCp, p.finished, p.finishTime = lap, nextCp, finished or false, finishTime
				return { progress = p, dist = dist, joinOrder = join, name = tostring(join) }
			end
			local cp = gates
			local list = {
				racer(2, 5, cp[4].dist + 10, false, nil, 1), -- lap 2, just past gate 4
				racer(2, 5, cp[4].dist + 80, false, nil, 2), -- lap 2, further along -> ahead of #1
				racer(3, 2, cp[1].dist + 5, false, nil, 3), -- lap 3 -> ahead of both
				racer(4, 2, 0, true, 300, 4), -- finished
				racer(4, 2, 0, true, 290, 5), -- finished earlier -> 1st
				racer(2, 4, cp[3].dist + 50, false, nil, 6), -- lap 2, one gate behind
				racer(0, 1, main.length - 30, false, nil, 7), -- not started, near the line
				racer(0, 1, main.length - 90, false, nil, 8), -- not started, further back
			}
			RaceMath.rank(list, gates, main.length)
			local order = {}
			for _, e in ipairs(list) do
				table.insert(order, e.name)
			end
			assert(table.concat(order, ",") == "5,4,3,2,1,6,7,8", "order " .. table.concat(order, ","))
			assert(list[1].place == 1 and list[8].place == 8)
			-- exact ties fall back to grid order
			local t = { racer(1, 3, 500, false, nil, 2), racer(1, 3, 500, false, nil, 1) }
			RaceMath.rank(t, gates, main.length)
			assert(t[1].joinOrder == 1)
		end,
	},
	{
		name = "Race: wrong-way detection and rewards",
		fn = function()
			local flat = V3.new(1, 0, 0)
			assert(RaceMath.wrongWay(V3.new(-40, 0, 0), flat))
			assert(not RaceMath.wrongWay(V3.new(40, 0, 0), flat))
			assert(not RaceMath.wrongWay(V3.new(-5, 0, 0), flat), "slow reversing counted")
			local R = GameConfig.Rewards
			local c1, x1 = RaceMath.reward(R, 1, 8)
			local c8, x8 = RaceMath.reward(R, 8, 8)
			local cd = RaceMath.reward(R, nil, 8, true)
			assert(c1 > c8 and x1 > x8 and c8 >= cd and cd == R.Participation)
		end,
	},
}
