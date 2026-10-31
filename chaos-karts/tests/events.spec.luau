local Loader = require("./loader")
local Registry = Loader.shared("Events/Registry")
local EventBase = Loader.shared("Events/EventBase")
local EventRules = Loader.shared("EventRules")
local GameConfig = Loader.shared("Config/GameConfig")
local MapData = Loader.shared("MapData")
local ChaosCity = Loader.shared("Maps/ChaosCity")
local Rng = Loader.shared("Rng")

local cfg = GameConfig.Events
local data = MapData.compile(ChaosCity)
local zones = data.zones
local L = data.main.length

local function def(over)
	local d = {
		id = "T" .. tostring(math.random(1, 1e9)),
		name = "Test",
		category = "Brainrot",
		intensity = 1,
		weight = 10,
		duration = 10,
		warning = 2,
		tags = {},
		conflictsWith = {},
		minLap = 1,
		finalLapBoost = 1,
		zoneTags = { "straight" },
		blocksLanes = 0,
		implemented = true,
	}
	for k, v in pairs(over or {}) do
		d[k] = v
	end
	return d
end

local function zone(id)
	return data.zoneById[id]
end

local function ctx(now, lap)
	return { now = now, raceStart = 0, lap = lap or 1, totalLaps = 3 }
end

local function copyCatalog()
	local list = {}
	for _, d in ipairs(Registry.catalog) do
		local c = table.clone(d)
		c.implemented = true
		table.insert(list, c)
	end
	return list
end

-- Runs the scheduler like the director does (one attempt per scheduled time).
local function simulate(catalog, lap, seconds, seed)
	local state = EventRules.newState()
	local rng = Rng.new(seed or 7)
	local now = 20
	local maxMajor, maxMinor, starts, laneOk = 0, 0, 0, true
	local intensity3 = 0
	local nextId = 0
	local c = ctx(now, lap)
	EventRules.scheduleNext(state, cfg, c, rng)
	while now < 20 + seconds do
		now += 0.5
		c = ctx(now, lap)
		for id, a in pairs(state.active) do
			if now >= a.endAt then
				EventRules.stop(state, id)
			end
		end
		if now >= state.nextAt then
			local d, z = EventRules.pick(state, catalog, zones, c, cfg, rng, L)
			if d then
				nextId += 1
				EventRules.start(state, d, z, c, cfg, nextId)
				starts += 1
				if d.intensity >= 3 then
					intensity3 += 1
				end
			end
			EventRules.scheduleNext(state, cfg, c, rng)
		end
		local majors, minors = EventRules.activeCount(state)
		maxMajor = math.max(maxMajor, majors)
		maxMinor = math.max(maxMinor, minors)
		-- the lane guarantee, independently checked: every zone keeps a clear lane
		for _, z in ipairs(zones) do
			local blocked = 0
			for _, a in pairs(state.active) do
				if a.lanes > 0 and EventRules.sameRoute(a.zone, z) and (a.zone.id == z.id or MapData.spansOverlap(data.main, a.zone.from, a.zone.span, z.from, z.span)) then
					blocked += a.lanes
				end
			end
			if z.lanes > 0 and blocked >= z.lanes then
				laneOk = false
			end
		end
		local blockers = 0
		for _, a in pairs(state.active) do
			if EventRules.hasTag(a.def, "blocks-lane") then
				blockers += 1
			end
		end
		if blockers > 1 then
			laneOk = false
		end
	end
	return { starts = starts, maxMajor = maxMajor, maxMinor = maxMinor, laneOk = laneOk, intensity3 = intensity3 }
end

return {
	{
		name = "Events: all 35 planned events are in the catalog (25 Brainrot / 5 Fiction / 5 Disaster), one module each",
		fn = function()
			assert(#Registry.catalog == 35, "catalog " .. #Registry.catalog)
			local counts = Registry.countBy("category")
			assert(counts.Brainrot == 25 and counts.Fiction == 5 and counts.Disaster == 5, "split")
			local split = GameConfig.ContentTargets.EventSplit
			assert(split.Brainrot == 25 and split.Fiction == 5 and split.Disaster == 5 and GameConfig.ContentTargets.Events == 35)
			local seen = {}
			for _, id in ipairs(Registry.ORDER) do
				assert(not seen[id], "duplicate " .. id)
				seen[id] = true
				local m = Registry.module(id)
				for _, fn in ipairs({ "serverStart", "serverStep", "serverStop", "play", "step", "cleanup" }) do
					assert(type(m[fn]) == "function", id .. " lacks " .. fn)
				end
				for _, slot in ipairs(EventBase.SoundSlots) do
					assert(type(m.Sounds[slot]) == "table" and type(m.Sounds[slot].Id) == "string", id .. " lacks sound slot " .. slot)
				end
				local d = m.Def
				assert(d.intensity >= 1 and d.intensity <= 3 and d.weight > 0 and d.duration > 0 and d.warning >= 2, id .. " numbers")
				assert(type(d.tags) == "table" and type(d.conflictsWith) == "table" and type(d.zoneTags) == "table" and #d.zoneTags > 0, id .. " lists")
				assert(d.minLap >= 1 and d.minLap <= 3 and d.finalLapBoost >= 1, id .. " lap rules")
				assert(d.category == "Brainrot" or d.category == "Fiction" or d.category == "Disaster")
				for _, other in ipairs(d.conflictsWith) do
					assert(Registry.def(other), id .. " conflicts with unknown " .. other)
				end
				for _, e in ipairs(d.effects or {}) do
					assert(table.find(GameConfig.Effects.Allowed, e), id .. " uses unknown effect " .. e)
				end
			end
		end,
	},
	{
		name = "Events: implemented is respected - only the reference event can ever be picked in Stage 1",
		fn = function()
			local impl = Registry.implemented()
			assert(#impl == 1 and impl[1].id == "QuackaroniParade", "implemented: " .. #impl)
			local state = EventRules.newState()
			local rng = Rng.new(3)
			for i = 1, 300 do
				local d = EventRules.pick(state, Registry.catalog, zones, ctx(100 + i * 50, 1 + i % 3), cfg, rng, L)
				assert(d == nil or d.id == "QuackaroniParade", "picked an unimplemented event: " .. tostring(d and d.id))
			end
			local d = EventRules.pick(state, Registry.catalog, zones, ctx(100, 1), cfg, rng, L)
			assert(d and d.id == "QuackaroniParade")
		end,
	},
	{
		name = "Events: grace period, cooldowns, minLap and one instance per event",
		fn = function()
			local a = def({ id = "A" })
			local z = zone("StartStraight")
			local state = EventRules.newState()
			assert(select(2, EventRules.canStart(state, a, z, ctx(5), cfg, L)) == "grace")
			local ok0, why0 = EventRules.canStart(state, a, z, ctx(30), cfg, L)
			assert(ok0, "first start: " .. tostring(why0))
			EventRules.start(state, a, z, ctx(30), cfg, 1)
			assert(select(2, EventRules.canStart(state, a, z, ctx(31), cfg, L)) == "active")
			EventRules.stop(state, 1)
			local readyAt = 30 + a.warning + a.duration + cfg.DefaultCooldown
			assert(select(2, EventRules.canStart(state, a, z, ctx(readyAt - 1), cfg, L)) == "cooldown")
			local ok, why = EventRules.canStart(state, a, z, ctx(readyAt + 0.1), cfg, L)
			assert(ok, "after the cooldown: " .. tostring(why))
			local late = def({ id = "Late", minLap = 3 })
			assert(select(2, EventRules.canStart(state, late, z, ctx(100, 2), cfg, L)) == "min-lap")
			assert(EventRules.canStart(state, late, z, ctx(100, 3), cfg, L))
			assert(select(2, EventRules.canStart(state, def({ implemented = false }), z, ctx(100), cfg, L)) == "not-implemented")
		end,
	},
	{
		name = "Events: global budget (1 major + 1 minor), conflicts both ways, exclusive tags",
		fn = function()
			local state = EventRules.newState()
			local z1, z2, z3 = zone("StartStraight"), zone("SkylineHighway"), zone("Park")
			local major = def({ id = "M1", intensity = 2 })
			local major2 = def({ id = "M2", intensity = 3 })
			local minor = def({ id = "m1" })
			local minor2 = def({ id = "m2" })
			EventRules.start(state, major, z1, ctx(50), cfg, 1)
			assert(select(2, EventRules.canStart(state, major2, z2, ctx(51), cfg, L)) == "budget", "two majors")
			assert(EventRules.canStart(state, minor, z2, ctx(51), cfg, L))
			EventRules.start(state, minor, z2, ctx(51), cfg, 2)
			assert(select(2, EventRules.canStart(state, minor2, z3, ctx(52), cfg, L)) == "budget", "two minors")
			local s2 = EventRules.newState()
			local quake = def({ id = "Quake", conflictsWith = { "Kaiju" } })
			local kaiju = def({ id = "Kaiju", intensity = 2 })
			EventRules.start(s2, kaiju, z1, ctx(50), cfg, 1)
			assert(select(2, EventRules.canStart(s2, quake, z2, ctx(51), cfg, L)) == "conflict", "conflict (declared on the new event)")
			local s3 = EventRules.newState()
			EventRules.start(s3, quake, z2, ctx(50), cfg, 1)
			assert(select(2, EventRules.canStart(s3, kaiju, z1, ctx(51), cfg, L)) == "conflict", "conflict (declared on the running event)")
			local s4 = EventRules.newState()
			local fx1 = def({ id = "fx1", tags = { "screen-effect" }, zoneTags = { "global" } })
			local fx2 = def({ id = "fx2", intensity = 2, tags = { "screen-effect" }, zoneTags = { "global" } })
			EventRules.start(s4, fx1, zone("Skyline"), ctx(50), cfg, 1)
			assert(select(2, EventRules.canStart(s4, fx2, zone("Skyline"), ctx(51), cfg, L)) == "exclusive:screen-effect")
		end,
	},
	{
		name = "Events: never two blocks-lane events; a blocker always leaves a clear lane (the track stays passable)",
		fn = function()
			local state = EventRules.newState()
			local blocker = def({ id = "B1", tags = { "blocks-lane" }, blocksLanes = 1 })
			local blocker2 = def({ id = "B2", intensity = 2, tags = { "blocks-lane" }, blocksLanes = 1 })
			local z = zone("StartStraight")
			EventRules.start(state, blocker, z, ctx(50), cfg, 1)
			assert(select(2, EventRules.canStart(state, blocker2, zone("Park"), ctx(51), cfg, L)) == "exclusive:blocks-lane")
			-- a greedy blocker can't take every lane
			local greedy = def({ id = "G", tags = { "blocks-lane" }, blocksLanes = 99, zoneTags = { "alley" } })
			local alley = zone("NeonAlley")
			assert(alley.lanes == 1)
			assert(select(2, EventRules.canStart(EventRules.newState(), greedy, alley, ctx(50), cfg, L)) == "lanes", "blocked the single-lane alley")
			local wide = def({ id = "W", tags = { "blocks-lane" }, blocksLanes = 99 })
			assert(EventRules.lanesBlocked(wide, z) == z.lanes - 1, "lanesBlocked not capped")
			-- lane-blocking events can't use a lane-less (sky / track-wide) zone
			local sky = def({ id = "S", tags = { "blocks-lane" }, zoneTags = { "global" } })
			assert(select(2, EventRules.canStart(EventRules.newState(), sky, zone("Skyline"), ctx(50), cfg, L)) == "lanes")
			-- the lane check counts blockers in OVERLAPPING zones (rules relaxed to test it)
			local relaxed = table.clone(cfg)
			relaxed.ExclusiveTags = {}
			relaxed.MaxMajor, relaxed.MaxMinor = 9, 9
			local s = EventRules.newState()
			local plaza = zone("NeonPlaza")
			for i = 1, plaza.lanes - 1 do
				local b = def({ id = "L" .. i, tags = { "blocks-lane" }, blocksLanes = 1, zoneTags = { "plaza", "straight" } })
				relaxed.OneEventPerZone = false
				assert(EventRules.canStart(s, b, plaza, ctx(50), relaxed, L), "lane " .. i)
				EventRules.start(s, b, plaza, ctx(50), relaxed, i)
			end
			local last = def({ id = "Last", tags = { "blocks-lane" }, blocksLanes = 1, zoneTags = { "plaza" } })
			assert(select(2, EventRules.canStart(s, last, plaza, ctx(51), relaxed, L)) == "lanes", "the last lane was blocked")
		end,
	},
	{
		name = "Events: FINAL LAP is more intense (rate, cooldowns, intensity 3) but stays inside every rule",
		fn = function()
			local finalCtx, normalCtx = ctx(100, 3), ctx(100, 2)
			assert(EventRules.interval(cfg, finalCtx) < EventRules.interval(cfg, normalCtx))
			local big = def({ intensity = 3, finalLapBoost = 1.8 })
			assert(EventRules.cooldown(cfg, big, finalCtx) < EventRules.cooldown(cfg, big, normalCtx))
			assert(EventRules.weight(cfg, big, finalCtx) > EventRules.weight(cfg, big, normalCtx) * 3)
			-- the whole catalog (marked implemented for the test), long runs
			local catalog = copyCatalog()
			local normal = simulate(catalog, 2, 900, 11)
			local final = simulate(catalog, 3, 900, 11)
			assert(final.starts > normal.starts * 1.3, string.format("final lap starts %d vs normal %d", final.starts, normal.starts))
			assert(final.intensity3 > normal.intensity3, string.format("intensity-3 final %d vs normal %d", final.intensity3, normal.intensity3))
			for _, r in ipairs({ normal, final }) do
				assert(r.maxMajor <= cfg.MaxMajor and r.maxMinor <= cfg.MaxMinor, "budget exceeded")
				assert(r.laneOk, "a zone was fully blocked")
			end
			-- lap 1: intensity-3 events with minLap 2+ never appear
			local first = simulate(catalog, 1, 900, 5)
			assert(first.intensity3 == 0, "intensity 3 on lap 1")
		end,
	},
	{
		name = "Events: the reference event's path is deterministic (seed + zone) and crosses the road",
		fn = function()
			local Quack = Registry.module("QuackaroniParade")
			local z = zone("NeonPlaza")
			local a = Quack.path(1234, z, data)
			local b = Quack.path(1234, z, data)
			assert(a.from == b.from and a.to == b.to, "not deterministic")
			local c = Quack.path(99, z, data)
			assert(c.from ~= a.from or c.to ~= a.to, "seed ignored")
			local s = data.main:at(a.dist)
			assert(a.length > s.w + 20, "doesn't cross the whole road")
			local timing = { startAt = 10, endAt = 22 }
			local p0, _, phase0 = Quack.positionAt(a, timing, 9)
			local p1, _, phase1 = Quack.positionAt(a, timing, 16)
			local _, _, phase2 = Quack.positionAt(a, timing, 23)
			assert(phase0 == "warning" and phase1 == "walking" and phase2 == "done")
			assert((p0 - a.from).Magnitude < 2 and (p1 - (a.from + a.to) / 2).Magnitude < 2)
		end,
	},
}
