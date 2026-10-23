--[[
	HorrorEventService - rare, purposeful scares (configured in HorrorEventConfig).

	Events are spaced out by a cooldown, never fire while the Listener is chasing, and most
	never touch gameplay: they exist to create doubt. "Local" events are shown to a single
	player only, so teammates did not see what they saw.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local HorrorEventConfig = require(Shared.Config.HorrorEventConfig)
local MazeGen = require(Shared.MazeGen)

local HorrorEventService = {}

local services
local current

function HorrorEventService.init(registry)
	services = registry
end

local function randomAlive(rng)
	local alive = {}
	for _, state in ipairs(services.PlayerService.inRound()) do
		if state.status == "Alive" and state.root and state.root.Parent and not state.hiddenIn then
			table.insert(alive, state)
		end
	end
	return rng:pick(alive)
end

local function cellsAround(map, index, radius)
	local list = { index }
	local cell = map.layout.cells[index]
	for _, n in ipairs(MazeGen.neighbors(map.layout, cell)) do
		if radius >= 1 then
			table.insert(list, n.cell.index)
		end
	end
	return list
end

local function cellAtDistance(map, rng, position, minD, maxD)
	local options = {}
	for index in ipairs(map.layout.cells) do
		local d = (map:cellCenter(index) - Vector3.new(position.X, 0, position.Z)).Magnitude
		if d >= minD and (not maxD or d <= maxD) then
			table.insert(options, index)
		end
	end
	return rng:pick(options)
end

local Events = {}

function Events.LightsFail(cfg, map, rng, state)
	local index = map:cellAt(state.root.Position)
	if not index then
		return false
	end
	local cells = cellsAround(map, index, cfg.RadiusCells)
	local duration = rng:range(cfg.Duration[1], cfg.Duration[2])
	map:blackout(cells, duration)
	services.Remotes.HorrorEvent:FireAllClients("LightsFail", { cells = cells, duration = duration })
	return true
end

function Events.DistantFigure(cfg, _map, _rng, state)
	services.Remotes.HorrorEvent:FireClient(state.player, "DistantFigure", {
		minDistance = cfg.MinDistance,
		maxDistance = cfg.MaxDistance,
		vanishAfterSeen = cfg.VanishAfterSeen,
		lifetime = cfg.Lifetime,
	})
	return true
end

function Events.DoorSlam(cfg, _map, rng, state)
	local door = services.DoorService.slamRandom(state.root.Position, cfg.MinDistance, cfg.MaxDistance, rng)
	if door and cfg.AlertsMonster then
		services.NoiseService:emit("DoorSlam", door.panel.Position, {})
	end
	return door ~= nil
end

function Events.DistantVocalization(cfg, map, rng, state)
	local index = cellAtDistance(map, rng, state.root.Position, cfg.MinDistance)
	if not index then
		return false
	end
	services.Remotes.HorrorEvent:FireAllClients("Vocalization", { position = map:cellCenter(index) + Vector3.new(0, 8, 0) })
	return true
end

function Events.FootstepsBehind(cfg, _map, _rng, state)
	services.Remotes.HorrorEvent:FireClient(state.player, "FootstepsBehind", { steps = cfg.Steps })
	return true
end

function Events.PipeBurst(cfg, map, rng, state)
	local index = cellAtDistance(map, rng, state.root.Position, cfg.MinDistance, cfg.MaxDistance)
	if not index then
		return false
	end
	local position = map:cellCenter(index) + Vector3.new(rng:range(-6, 6), 10, rng:range(-6, 6))
	if cfg.AlertsMonster then
		services.NoiseService:emit(cfg.Noise, position, {})
	end
	services.Remotes.HorrorEvent:FireAllClients("PipeBurst", { position = position })
	return true
end

function HorrorEventService.start(map, rng)
	HorrorEventService.stop()
	local record = { map = map, rng = rng, alive = true }
	current = record
	task.spawn(function()
		task.wait(HorrorEventConfig.FirstEventDelay)
		local nextAt = 0
		while record.alive do
			local now = os.clock()
			local monsterState = services.MonsterService.state()
			local busy = monsterState == "Chase" or monsterState == "Attack" or monsterState == "Lost"
			if not busy and now >= nextAt then
				local state = randomAlive(rng)
				if state then
					local weights = {}
					for name, cfg in pairs(HorrorEventConfig.Events) do
						weights[name] = cfg.Weight
					end
					local name = rng:weighted(weights)
					local ok, fired = pcall(Events[name], HorrorEventConfig.Events[name], map, rng, state)
					if not ok then
						warn("[DeadAir] Horror event " .. name .. " failed: " .. tostring(fired))
					end
					nextAt = now + rng:range(HorrorEventConfig.CooldownMin, HorrorEventConfig.CooldownMax)
				end
			end
			task.wait(HorrorEventConfig.CheckInterval)
		end
	end)
end

function HorrorEventService.stop()
	if current then
		current.alive = false
		current = nil
	end
end

return HorrorEventService
