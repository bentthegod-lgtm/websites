--[[
	EventDirector - runs server-wide world events during a race.

	Scheduling is the pure EventRules module (weighted picks, cooldowns, 1 major + 1 minor
	budget, conflicts, never two lane-blockers, a clear lane always left, grace period, the
	FINAL LAP running hotter but inside the same rules). Only catalog entries with
	implemented = true are ever picked (Stage 1: the reference event).

	Each running event is an INSTANCE with its own Maid and a hard timeout:
	  start  -> module.serverStart(ctx); EventStart { instanceId, id, seed, warnAt,
	            serverStartTime, endAt, zone } to every client (they play it locally from
	            the server clock)
	  frame  -> module.serverStep(ctx, dt): the server resolves hits through KartEffects
	  end    -> module.serverStop(ctx); maid:clean(); EventStop to every client
	  stuck  -> past hardEnd (or a module error) the instance is force-stopped and cleaned.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local EventRules = require(Shared.EventRules)
local Registry = require(Shared.Events.Registry)
local Maid = require(Shared.Maid)
local Rng = require(Shared.Rng)

local EventDirector = {}

local cfg = GameConfig.Events
local services
local world
local state = EventRules.newState()
local instances = {}
local race = nil
local rng = Rng.new(12345)
local nextInstance = 0
EventDirector.log = {}

local function now()
	return workspace:GetServerTimeNow()
end

function EventDirector.init(registry)
	services = registry
end

function EventDirector.setWorld(newWorld)
	world = newWorld
end

function EventDirector.state()
	return state
end

function EventDirector.instances()
	return instances
end

local function ctxNow()
	return {
		now = now(),
		raceStart = race and race.goAt or now(),
		lap = services.RaceService.leaderLap(),
		totalLaps = GameConfig.Race.Laps,
	}
end
EventDirector.context = ctxNow

local function racerViews()
	local list = {}
	local t = now()
	for _, r in ipairs(services.RaceService.racers()) do
		if not r.left and not r.progress.finished then
			table.insert(list, { id = r.id, pos = r.kart.pos, vel = r.kart.vel, ghost = t < (r.ghostUntil or 0), racer = r })
		end
	end
	return list
end

local function payload(inst)
	return {
		instanceId = inst.instanceId,
		id = inst.def.id,
		seed = inst.seed,
		warnAt = inst.warnAt,
		serverStartTime = inst.startAt,
		endAt = inst.endAt,
		zone = inst.zone.id,
	}
end
EventDirector.payload = payload

function EventDirector.onRaceBegin(r)
	EventDirector.stopAll("new race")
	race = r
	state = EventRules.newState()
	rng = Rng.new(r.id * 7919 + 17)
	services.KartEffects.reset()
end

function EventDirector.onRaceStart(r)
	race = r
	-- the first attempt comes after the grace period
	state.nextAt = r.goAt + cfg.GraceSeconds + rng:NextNumber(0, 4)
end

function EventDirector.startInstance(def, zone, seed)
	local module = Registry.module(def.id)
	local c = ctxNow()
	nextInstance += 1
	local rules = EventRules.start(state, def, zone, c, cfg, nextInstance)
	local inst = {
		instanceId = nextInstance,
		def = def,
		zone = zone,
		seed = seed or rng:NextInteger(1, 2 ^ 30),
		warnAt = rules.warnAt,
		startAt = rules.startAt,
		endAt = rules.endAt,
		hardEnd = rules.hardEnd,
		module = module,
	}
	local maid = Maid.new()
	inst.maid = maid
	inst.ctx = {
		id = def.id,
		instanceId = inst.instanceId,
		def = def,
		seed = inst.seed,
		rng = Rng.new(inst.seed),
		zone = zone,
		data = world.data,
		warnAt = inst.warnAt,
		startAt = inst.startAt,
		endAt = inst.endAt,
		hitCooldown = cfg.HitCooldown,
		now = now,
		maid = maid,
		racers = racerViews,
		hit = function(view, kind, params)
			return services.KartEffects.apply(view.racer, kind, params, def.id)
		end,
	}
	instances[inst.instanceId] = inst
	local ok, err = pcall(module.serverStart, inst.ctx)
	if not ok then
		warn("[ChaosKarts] event " .. def.id .. " failed to start: " .. tostring(err))
		EventDirector.stopInstance(inst, "error")
		return nil
	end
	table.insert(EventDirector.log, { id = def.id, zone = zone.id, at = c.now, lap = c.lap, final = EventRules.isFinalLap(c) })
	services.Remotes.EventStart:FireAllClients(payload(inst))
	return inst
end

function EventDirector.stopInstance(inst, reason)
	if not instances[inst.instanceId] then
		return
	end
	instances[inst.instanceId] = nil
	local ok, err = pcall(inst.module.serverStop, inst.ctx)
	if not ok then
		warn("[ChaosKarts] event " .. inst.def.id .. " serverStop error: " .. tostring(err))
	end
	inst.maid:clean()
	EventRules.stop(state, inst.instanceId)
	inst.stoppedBecause = reason
	services.Remotes.EventStop:FireAllClients(inst.instanceId, reason)
end

function EventDirector.stopAll(reason)
	for _, inst in pairs(instances) do
		EventDirector.stopInstance(inst, reason)
	end
end

--[[
	Starts a specific event now (Studio testing and the harness). Still obeys every rule
	unless `force` is set; returns the instance or nil + reason.
]]
function EventDirector.trigger(id, zoneId, force, seed)
	local def = Registry.def(id)
	local zone = world and world.data.zoneById[zoneId]
	if not def or not zone or not race then
		return nil, "unknown"
	end
	if not force then
		local ok, reason = EventRules.canStart(state, def, zone, ctxNow(), cfg, world.data.main.length)
		if not ok then
			return nil, reason
		end
	end
	return EventDirector.startInstance(def, zone, seed)
end

function EventDirector.step(dt)
	if not race or not world then
		return
	end
	local t = now()
	for _, inst in pairs(instances) do
		if t >= inst.endAt then
			EventDirector.stopInstance(inst, "done")
		elseif t >= inst.hardEnd then
			EventDirector.stopInstance(inst, "timeout")
		else
			local ok, err = pcall(inst.module.serverStep, inst.ctx, dt)
			if not ok then
				warn("[ChaosKarts] event " .. inst.def.id .. " serverStep error: " .. tostring(err))
				EventDirector.stopInstance(inst, "error")
			end
		end
	end
	if cfg.Enabled and state.nextAt and t >= state.nextAt then
		local c = ctxNow()
		local def, zone = EventRules.pick(state, Registry.catalog, world.data.zones, c, cfg, rng, world.data.main.length)
		if def then
			EventDirector.startInstance(def, zone)
		end
		EventRules.scheduleNext(state, cfg, c, rng)
	end
end

-- Hard-timeout sweep (also called when a module's step never ends an instance).
function EventDirector.sweep()
	local t = now()
	for _, inst in pairs(instances) do
		if t >= inst.hardEnd then
			EventDirector.stopInstance(inst, "timeout")
		end
	end
end

function EventDirector.onRaceEnd()
	EventDirector.stopAll("race over")
	race = nil
	state.nextAt = nil
end

-- Late joiners / spectators get the events already running.
function EventDirector.syncPlayer(player)
	for _, inst in pairs(instances) do
		services.Remotes.EventStart:FireClient(player, payload(inst))
	end
end

function EventDirector.onPlayerRemoving(_player)
	-- per-racer hit memory lives in each instance ctx and is keyed by racer id; nothing
	-- else is held per player.
end

return EventDirector
