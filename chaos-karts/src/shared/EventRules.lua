--[[
	EventRules - the Event Director's scheduling rules (pure, unit-tested).

	* Weighted picks among events that are implemented, unlocked for this lap, off cooldown
	  and have a suitable zone on this map.
	* Per-event cooldowns.
	* A global budget: at most MaxMajor major (intensity >= 2) and MaxMinor minor
	  (intensity 1) events at the same time.
	* conflictsWith (both directions) and exclusive tags: never two "blocks-lane" events.
	* The track is never unpassable: an event that blocks lanes blocks some lanes of its
	  zone, and the lanes blocked in overlapping zones always leave at least one clear lane
	  (zones with a shortcut alternative count the main road as the route around).
	* A grace period after GO.
	* FINAL LAP = MORE INTENSE: shorter intervals, shorter cooldowns, intensity-3 events
	  unlocked (minLap) and weighted up, each event's finalLapBoost applied - but every rule
	  above (budget, conflicts, lanes, cooldowns) still holds.

	cfg = GameConfig.Events. ctx = { now, raceStart, lap, totalLaps }.
	A "def" is an event catalog entry (Events/Registry). A zone comes from MapData.
]]

local EventRules = {}

function EventRules.newState()
	return { active = {}, cooldowns = {}, nextAt = nil, started = 0, history = {} }
end

function EventRules.isFinalLap(ctx)
	return ctx.lap ~= nil and ctx.totalLaps ~= nil and ctx.lap >= ctx.totalLaps
end

function EventRules.isMajor(def)
	return def.intensity >= 2
end

function EventRules.hasTag(def, tag)
	return table.find(def.tags, tag) ~= nil
end

function EventRules.interval(cfg, ctx)
	local base = cfg.Interval
	if EventRules.isFinalLap(ctx) then
		return base * cfg.FinalLapIntervalMul
	end
	return base
end

function EventRules.cooldown(cfg, def, ctx)
	local c = def.cooldown or cfg.DefaultCooldown
	if EventRules.isFinalLap(ctx) then
		c *= cfg.FinalLapCooldownMul
	end
	return c
end

function EventRules.unlocked(def, ctx)
	return (ctx.lap or 1) >= (def.minLap or 1)
end

function EventRules.weight(cfg, def, ctx)
	if not def.implemented or not EventRules.unlocked(def, ctx) then
		return 0
	end
	local w = def.weight
	if EventRules.isFinalLap(ctx) then
		w *= def.finalLapBoost or 1
		if def.intensity >= 3 then
			w *= cfg.FinalLapIntensity3Mul
		end
	elseif def.intensity >= 3 then
		w *= cfg.Intensity3NormalMul
	end
	return w
end

-- Zones on the map this event can use (any of def.zoneTags; an empty list = any zone).
function EventRules.zonesFor(def, zones)
	local out = {}
	for _, zone in ipairs(zones) do
		local ok = #def.zoneTags == 0
		for _, tag in ipairs(def.zoneTags) do
			if zone.tags[tag] then
				ok = true
			end
		end
		if ok then
			table.insert(out, zone)
		end
	end
	return out
end

function EventRules.lanesBlocked(def, zone)
	if not EventRules.hasTag(def, "blocks-lane") then
		return 0
	end
	local n = def.blocksLanes or 1
	return math.min(n, math.max(0, (zone.lanes or 0) - 1))
end

-- Zones on different routes (the main road vs a shortcut road) never block each other:
-- they are alternative ways through.
function EventRules.sameRoute(a, b)
	return (a.shortcut or "main") == (b.shortcut or "main")
end

local function overlaps(a, b, length)
	if a.id == b.id then
		return true
	end
	if not EventRules.sameRoute(a, b) then
		return false
	end
	if a.trackWide or b.trackWide then
		return true
	end
	if not length then
		return false
	end
	local function inside(x, s0, span)
		return (x - s0) % length <= span
	end
	return inside(a.from, b.from, b.span) or inside(b.from, a.from, a.span)
end

--[[
	The lane guarantee: after adding `def` in `zone`, every zone touched by a lane-blocking
	event keeps at least one clear lane. A lane-blocking event can't use a zone without
	lanes (sky / track-wide).
]]
function EventRules.laneCheck(state, def, zone, length)
	local blocked = EventRules.lanesBlocked(def, zone)
	if not EventRules.hasTag(def, "blocks-lane") then
		return true
	end
	if (zone.lanes or 0) < 2 or zone.trackWide or blocked < 1 then
		return false
	end
	local total = blocked
	for _, a in pairs(state.active) do
		if a.lanes > 0 and overlaps(a.zone, zone, length) then
			total += a.lanes
		end
	end
	return total <= zone.lanes - 1
end

function EventRules.canStart(state, def, zone, ctx, cfg, length)
	if not def.implemented then
		return false, "not-implemented"
	end
	if ctx.now - (ctx.raceStart or -math.huge) < cfg.GraceSeconds then
		return false, "grace"
	end
	if not EventRules.unlocked(def, ctx) then
		return false, "min-lap"
	end
	for _, a in pairs(state.active) do
		if a.def.id == def.id then
			return false, "active"
		end
	end
	if (state.cooldowns[def.id] or -math.huge) > ctx.now then
		return false, "cooldown"
	end
	local majors, minors = 0, 0
	for _, a in pairs(state.active) do
		if EventRules.isMajor(a.def) then
			majors += 1
		else
			minors += 1
		end
		if table.find(def.conflictsWith or {}, a.def.id) or table.find(a.def.conflictsWith or {}, def.id) then
			return false, "conflict"
		end
		for _, tag in ipairs(cfg.ExclusiveTags) do
			if EventRules.hasTag(def, tag) and EventRules.hasTag(a.def, tag) then
				return false, "exclusive:" .. tag
			end
		end
		if a.zone.id == zone.id and not zone.trackWide and cfg.OneEventPerZone then
			return false, "zone-busy"
		end
	end
	if EventRules.isMajor(def) and majors >= cfg.MaxMajor then
		return false, "budget"
	end
	if not EventRules.isMajor(def) and minors >= cfg.MaxMinor then
		return false, "budget"
	end
	local suitable = false
	for _, z in ipairs(EventRules.zonesFor(def, { zone })) do
		if z == zone then
			suitable = true
		end
	end
	if not suitable then
		return false, "zone"
	end
	if not EventRules.laneCheck(state, def, zone, length) then
		return false, "lanes"
	end
	return true
end

--[[
	Picks an event + zone, weighted. Returns def, zone or nil, reason. `rng` has
	NextNumber() (Random or Rng).
]]
function EventRules.pick(state, catalog, zones, ctx, cfg, rng, length)
	local options, total = {}, 0
	local lastReason = "none"
	for _, def in ipairs(catalog) do
		local w = EventRules.weight(cfg, def, ctx)
		if w > 0 then
			local usable = EventRules.zonesFor(def, zones)
			for _, zone in ipairs(usable) do
				local ok, reason = EventRules.canStart(state, def, zone, ctx, cfg, length)
				if ok then
					local share = w / #usable
					table.insert(options, { def = def, zone = zone, w = share })
					total += share
				else
					lastReason = reason
				end
			end
		else
			lastReason = if def.implemented then "min-lap" else "not-implemented"
		end
	end
	if total <= 0 then
		return nil, lastReason
	end
	local roll = rng:NextNumber() * total
	for _, o in ipairs(options) do
		roll -= o.w
		if roll <= 0 then
			return o.def, o.zone
		end
	end
	local last = options[#options]
	return last.def, last.zone
end

function EventRules.start(state, def, zone, ctx, cfg, instanceId)
	local total = def.warning + def.duration
	local instance = {
		id = instanceId,
		def = def,
		zone = zone,
		lanes = EventRules.lanesBlocked(def, zone),
		warnAt = ctx.now,
		startAt = ctx.now + def.warning,
		endAt = ctx.now + total,
		hardEnd = ctx.now + total + cfg.HardTimeoutSlack,
	}
	state.active[instanceId] = instance
	state.cooldowns[def.id] = ctx.now + total + EventRules.cooldown(cfg, def, ctx)
	state.started += 1
	table.insert(state.history, { id = def.id, at = ctx.now, final = EventRules.isFinalLap(ctx), intensity = def.intensity, zone = zone.id })
	return instance
end

function EventRules.stop(state, instanceId)
	state.active[instanceId] = nil
end

function EventRules.activeCount(state)
	local majors, minors = 0, 0
	for _, a in pairs(state.active) do
		if EventRules.isMajor(a.def) then
			majors += 1
		else
			minors += 1
		end
	end
	return majors, minors
end

-- When to try the next event (jittered so it never feels like a metronome).
function EventRules.scheduleNext(state, cfg, ctx, rng)
	local interval = EventRules.interval(cfg, ctx)
	state.nextAt = ctx.now + interval * (0.75 + 0.5 * rng:NextNumber())
	return state.nextAt
end

return EventRules
