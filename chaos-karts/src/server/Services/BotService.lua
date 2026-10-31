--[[
	BotService - bots fill empty grid slots (GameConfig.Bots: optional, on by default) so a
	solo player still races a full field. Bots run on the server with the SAME KartPhysics
	and KartStats as players, against the analytic TrackQuery, driven by BotBrain (which
	varies only driving behaviour: line, look-ahead, drift habit, throttle discipline).

	Fixed 1/60 s physics steps, kart-to-kart bumps against every other kart (players' last
	accepted positions too), and auto-respawn at the last checkpoint when a bot falls off,
	gets stuck or ends up off the course.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local KartStats = require(Shared.Config.KartStats)
local KartPhysics = require(Shared.KartPhysics)
local BotBrain = require(Shared.BotBrain)
local RaceMath = require(Shared.RaceMath)
local VehicleRegistry = require(Shared.Vehicles.Registry)

local BotService = {}

local services
local world
local bots = {}
local seedBase = 1

function BotService.init(registry)
	services = registry
end

function BotService.setWorld(newWorld)
	world = newWorld
end

function BotService.bots()
	return bots
end

function BotService.makeRacer(race, slot)
	local index = #bots + 1
	local names = GameConfig.Bots.Names
	local colors = GameConfig.Bots.Colors
	local vehicles = VehicleRegistry.ORDER
	seedBase += 1
	local racer = {
		id = "b" .. index,
		kind = "bot",
		name = names[(index - 1) % #names + 1],
		vehicle = vehicles[(index - 1) % #vehicles + 1],
		color = colors[(slot - 1) % #colors + 1],
		slot = slot,
		joinOrder = slot,
		progress = RaceMath.newProgress(),
		dist = 0,
		place = slot,
		kart = { pos = Vector3.new(), vel = Vector3.new(), yaw = 0, flags = 0, at = 0 },
		ghostUntil = 0,
		effectUntil = 0,
		wrongT = 0,
		strikes = 0,
	}
	local cf = race.data.grid[slot]
	racer.bot = {
		state = KartPhysics.new(cf),
		brain = BotBrain.new(race.id * 1000 + index * 37 + seedBase),
		acc = 0,
		started = false,
	}
	table.insert(bots, racer)
	return racer
end

function BotService.respawned(racer, cf, ghost)
	KartPhysics.respawn(racer.bot.state, cf, ghost)
end

function BotService.clear()
	bots = {}
end

function BotService.applyEffect(racer, kind, params)
	return racer.bot and KartPhysics.applyEffect(racer.bot.state, kind, params)
end

local function stepBot(racer, race, phase, query, others)
	local b = racer.bot
	local s = b.state
	local dt = KartStats.FixedStep
	local input
	if phase == "Countdown" then
		input = {}
	else
		if not b.started then
			b.started = true
			-- some bots nail the start boost, a few stall
			local roll = b.brain.rng:NextNumber()
			if roll < 0.35 * b.brain.skill then
				KartPhysics.applyStart(s, "boost")
			elseif roll > 0.95 then
				KartPhysics.applyStart(s, "stall")
			end
		end
		input = BotBrain.think(b.brain, s, race.data.main, dt)
		if racer.progress.finished then
			input.gas *= 0.6 -- cruise after the line
		end
	end
	local from = s.pos
	KartPhysics.step(s, input, query, dt)
	if phase == "Countdown" then
		-- held on the grid
		s.vel = Vector3.new(0, s.vel.Y, 0)
		s.pos = Vector3.new(from.X, s.pos.Y, from.Z)
	end
	local t = workspace:GetServerTimeNow()
	for _, o in ipairs(others) do
		-- ghosted karts (just respawned) don't collide
		if o ~= racer and not o.left and t >= (o.ghostUntil or 0) then
			KartPhysics.bump(s, o.kart.pos, o.kart.vel)
		end
	end
	racer.kart = { pos = s.pos, vel = s.vel, yaw = s.yaw, flags = KartPhysics.flags(s), at = t }
	services.RaceService.onMoved(racer, from, s.pos, s.vel, dt)
	if phase == "Racing" and not racer.progress.finished then
		local R = GameConfig.Respawn
		if s.pos.Y < race.data.killY or s.stuckT > R.StuckTime or s.offCourseT > R.OffCourseTime or racer.wrongT > 4 then
			services.RaceService.respawn(racer, "auto")
		end
	end
end

function BotService.step(dt)
	local race = services.RaceService.race()
	if not race or not world then
		return
	end
	local phase = services.RaceService.phase()
	local query = world.query
	local others = race.racers
	for _, racer in ipairs(bots) do
		if not racer.left and race.byId[racer.id] == racer then
			local b = racer.bot
			b.acc = math.min(b.acc + dt, KartStats.FixedStep * KartStats.MaxSubsteps)
			while b.acc >= KartStats.FixedStep - 1e-9 do
				b.acc -= KartStats.FixedStep
				stepBot(racer, race, phase, query, others)
				if services.RaceService.race() ~= race then
					return
				end
			end
		end
	end
end

return BotService
