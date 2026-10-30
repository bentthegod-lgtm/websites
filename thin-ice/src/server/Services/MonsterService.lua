--[[
	MonsterService - the Antlered's body. MonsterBrain decides; this moves the model,
	feeds it perceptions and resolves catches.

	  * Perception: it is blind. NoiseService hands it every noise; it hears them scaled by
	    distance, the difficulty and blizzard gusts (which drown sound out). It also FEELS
	    footsteps through the ice right next to it - standing perfectly still is the only
	    way to hide that close.
	  * It sleeps under the ice for the difficulty's grace period, then bursts out.
	  * It never leaves the ice: the shore is safe.
	  * Catching someone freezes them (SurvivalService.freeze) and it pauses to recover.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local IceMath = require(Shared.IceMath)
local LakeGen = require(Shared.LakeGen)
local Models = require(Shared.Models)
local MonsterBrain = require(Shared.MonsterBrain)

local MonsterService = {}

local services
local run
local brain, model, position
local accumulator = 0
local lastState
local intent
local rng = Random.new()

local Mon = GameConfig.Monster
local L = GameConfig.Lake
local MARGIN = 3

function MonsterService.init(registry)
	services = registry
end

local function flat(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function bounds()
	local half = L.Columns * L.TileSize / 2
	return -half + MARGIN, half - MARGIN, L.ShoreZ + 4, L.ShoreZ + LakeGen.Rows * L.TileSize - MARGIN
end

local function clampToLake(p)
	local minX, maxX, minZ, maxZ = bounds()
	return Vector3.new(math.clamp(p.X, minX, maxX), L.IceTop, math.clamp(p.Z, minZ, maxZ))
end
MonsterService.clampToLake = clampToLake

local function activeRoots()
	local list = {}
	for player, rec in pairs(services.SurvivalService.records()) do
		if rec.state == "Active" then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(list, { player = player, rec = rec, root = root })
			end
		end
	end
	return list
end

-- Where it wanders next: often toward someone on the lake (it drifts toward life), else
-- anywhere walkable.
local function prowlPoint(from)
	local targets = {}
	for _, a in ipairs(activeRoots()) do
		if a.root.Position.Z > L.ShoreZ then
			table.insert(targets, a.root.Position)
		end
	end
	if #targets > 0 and rng:NextNumber() < 0.55 then
		local p = targets[rng:NextInteger(1, #targets)]
		local angle = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber(14, 34)
		return clampToLake(p + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end
	local order = run.layout.order
	for _ = 1, 30 do
		local tile = order[rng:NextInteger(1, #order)]
		if LakeGen.walkable(tile) and tile.r >= 2 then
			local x, z = LakeGen.cellToWorld(tile.c, tile.r)
			local p = Vector3.new(x, L.IceTop, z)
			if flat(p, from) > 20 then
				return clampToLake(p)
			end
		end
	end
	return clampToLake(from + Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-30, 30)))
end

function MonsterService.startRun(newRun)
	run = newRun
	local c, r = run.layout.monsterCell[1], run.layout.monsterCell[2]
	local x, z = LakeGen.cellToWorld(c, r)
	position = Vector3.new(x, L.IceTop, z)
	model = Models.monster(CFrame.new(x, L.IceTop - 16, z), run.folder)
	model:SetAttribute("TI_State", "Dormant")
	brain = MonsterBrain.new({
		huntSpeed = run.diff.MonsterSpeed,
		wakeAt = run.wakeAt,
		prowlPoint = prowlPoint,
		rng = rng,
	})
	lastState = brain.state
	accumulator = 0
	intent = nil
end

function MonsterService.stopRun()
	if model then
		model:Destroy()
	end
	model, brain, run, position, intent = nil, nil, nil, nil, nil
end

function MonsterService.brain()
	return brain
end

function MonsterService.position()
	return position
end

function MonsterService.model()
	return model
end

-- Test / debug helper: put the monster somewhere on the lake.
function MonsterService.place(p)
	position = clampToLake(p)
	if model then
		model:PivotTo(CFrame.new(position))
	end
end

local CUES = { Listen = "Listen", Investigate = "Investigate", Hunt = "Hunt", Prowl = "Prowl", Search = "Search", Recover = "Recover" }

local function announceState()
	if not brain or brain.state == lastState then
		return
	end
	local from = lastState
	lastState = brain.state
	if model then
		model:SetAttribute("TI_State", brain.state)
	end
	if from == "Dormant" then
		if model then
			model:PivotTo(CFrame.new(position))
		end
		services.Remotes.MonsterCue:FireAllClients("Wake", position)
		services.Remotes.Announce:FireAllClients("Something woke up under the ice...", { 150, 200, 255 })
	elseif CUES[brain.state] then
		services.Remotes.MonsterCue:FireAllClients(CUES[brain.state], position)
	end
end

function MonsterService.hearing()
	local h = run and run.diff.MonsterHearing or 1
	if services.WeatherService and services.WeatherService.gusting() then
		h *= GameConfig.Noise.GustHearing
	end
	return h
end

function MonsterService.hear(category, where, source)
	if not brain or not brain:awake() then
		return false
	end
	local intensity = IceMath.perceived(category, flat(position, where), MonsterService.hearing())
	local heard = brain:hear({ position = clampToLake(where), intensity = intensity, source = source }, os.clock())
	announceState()
	return heard
end

-- Perception + decision, every Monster.StepInterval.
local function tick()
	local now = os.clock()
	local actives = activeRoots()
	if brain:awake() then
		-- Its quarry froze, escaped or left.
		if brain.target then
			local rec = services.SurvivalService.record(brain.target)
			if not rec or rec.state ~= "Active" then
				brain:loseTarget(now)
			end
		end
		for _, a in ipairs(actives) do
			local p = a.root.Position
			if p.Z >= L.ShoreZ then
				local d = flat(p, position)
				if d <= Mon.CatchRadius then
					services.SurvivalService.freeze(a.player, "monster")
					brain:caught(now)
					services.Remotes.MonsterCue:FireAllClients("Catch", position, a.player.UserId)
					break
				elseif d <= Mon.FeelRadius and a.rec.moving then
					brain:feel(a.player, p, now)
				end
			end
		end
	end
	intent = brain:update(now, position)
	announceState()
end

-- Moves the body toward the current goal (every frame, so it glides instead of ticking).
local function move(dt)
	if not intent or not intent.goal or intent.speed <= 0 or brain.state == "Dormant" then
		return
	end
	local to = clampToLake(intent.goal)
	local delta = Vector3.new(to.X - position.X, 0, to.Z - position.Z)
	local dist = delta.Magnitude
	if dist > 0.05 then
		local stepLen = math.min(dist, intent.speed * dt)
		position = clampToLake(position + delta / dist * stepLen)
		if model then
			model:PivotTo(CFrame.lookAt(position, position + delta / dist))
		end
	end
end

function MonsterService.step(dt)
	if not brain then
		return
	end
	accumulator += dt
	while accumulator >= Mon.StepInterval do
		accumulator -= Mon.StepInterval
		tick()
		if not brain then
			return
		end
	end
	move(dt)
end

return MonsterService
