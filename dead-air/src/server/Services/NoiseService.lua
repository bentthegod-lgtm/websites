--[[
	NoiseService - the server-authoritative sound event system.

	Gameplay code calls NoiseService:emit(category, position, opts). The service:
	  1. looks up loudness/radius in SoundConfig and applies surface/room/crouch modifiers;
	  2. merges duplicates and rate-limits per source so repeated actions cannot flood it;
	  3. for every registered listener (the Listener), estimates occlusion with a few
	     raycasts (walls, doors, large props), computes perceived loudness, and - if audible -
	     delivers an APPROXIMATE source position (jittered by distance and muffling);
	  4. records "heat" in the cell, which biases future patrol routes;
	  5. replicates matching presentation audio to clients and a noise meter to the source.

	Client audio never decides detection. Ambient/horror-event audio is played directly on
	clients and never reaches emit() unless an event is explicitly configured to.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local SoundConfig = require(Shared.Config.SoundConfig)
local SoundMath = require(Shared.SoundMath)
local Rng = require(Shared.Rng)

local NoiseService = {}

local services
local listeners = {}
local active = {}
local perSource = {}
local heat = {}
local lastFeedback = {}
local rng = Rng.new(os.time())
local map

-- Noise categories that also play a sound for everyone nearby. Footsteps and breathing are
-- presented locally by each client from character movement, so they are not sent.
local AUDIO_FOR = {
	DoorOpen = "DoorOpen",
	DoorClose = "DoorClose",
	DoorSlam = "DoorSlam",
	HeavyDoor = "HeavyDoor",
	ItemDrop = "ItemDrop",
	MetalDrop = "MetalDrop",
	GlassBreak = "GlassBreak",
	CanClatter = "CanClatter",
	CabinetOpen = "CabinetOpen",
	CabinetClose = "CabinetClose",
	AlarmClock = "AlarmClockRing",
	FuseInsert = "FuseInsert",
	BreakerPull = "BreakerPull",
	GeneratorStart = "BreakerPull",
	Terminal = "TerminalBeep",
	PropKnock = "DistantImpact",
	LockerEnter = "Locker",
	LockerExit = "Locker",
	LandHard = "Land",
	Pickup = "Pickup",
	KeycardSwipe = "CardSwipe",
	FuelPour = "FuelPour",
	ElevatorCall = "ElevatorArrive",
}

function NoiseService.init(registry)
	services = registry
end

function NoiseService.setMap(newMap)
	map = newMap
	table.clear(active)
	table.clear(heat)
end

--[[
	listener = {
		getEar = function() -> Vector3?      (nil = currently deaf, e.g. not spawned)
		hearingMultiplier = function() -> number
		exclude = function() -> { Instance }
		onHear = function(stimulus)
	}
]]
function NoiseService.addListener(listener)
	table.insert(listeners, listener)
	return function()
		local i = table.find(listeners, listener)
		if i then
			table.remove(listeners, i)
		end
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Counts obstacles between two points. Returns walls, doors, props.
function NoiseService.countObstacles(from, to, exclude)
	local occ = SoundConfig.Occlusion
	local filter = table.clone(exclude or {})
	local walls, doorsHit, props = 0, 0, 0
	local origin = from
	local direction = to - from
	for _ = 1, occ.MaxHits + 3 do
		rayParams.FilterDescendantsInstances = filter
		local result = Workspace:Raycast(origin, direction, rayParams)
		if not result then
			break
		end
		local kind = result.Instance:GetAttribute("Occluder")
		if kind == "Wall" then
			walls += 1
		elseif kind == "Door" then
			doorsHit += 1
		elseif kind == "Prop" then
			props += 1
		end
		if walls + doorsHit + props >= occ.MaxHits then
			break
		end
		table.insert(filter, result.Instance)
		origin = result.Position
		direction = to - origin
		if direction.Magnitude < 0.1 then
			break
		end
	end
	return walls, doorsHit, props
end

local function sourceAllowed(source, now)
	if not source then
		return true
	end
	local entry = perSource[source]
	if not entry or now - entry.windowStart >= 1 then
		perSource[source] = { windowStart = now, count = 1 }
		return true
	end
	entry.count += 1
	return entry.count <= SoundConfig.MaxEventsPerSecondPerSource
end

local function debugMark(position, radius, loudness)
	if not Workspace:GetAttribute(SoundConfig.DebugAttribute) then
		return
	end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.ForceField
	p.Color = Color3.fromHSV(math.clamp(0.33 - loudness * 0.3, 0, 0.33), 1, 1)
	p.Size = Vector3.one * math.min(radius * 2, 120)
	p.Position = position
	p.Transparency = 0.6
	p.Parent = Workspace
	Debris:AddItem(p, 0.6)
end

--[[
	opts = {
		source = Player?,            -- who caused it (rate limiting, feedback)
		multiplier = number?,        -- crouch / special modifiers
		surfaceMultiplier = number?, -- footsteps on metal etc.
		silentAudio = boolean?,      -- do not replicate presentation audio
	}
]]
function NoiseService:emit(category, position, opts)
	local def = SoundConfig.Categories[category]
	if not def then
		warn("[DeadAir] Unknown noise category " .. tostring(category))
		return nil
	end
	opts = opts or {}
	local now = os.clock()

	local cellIndex = map and map:cellAt(position)
	local acoustics = 1
	if cellIndex and map.layout.cells[cellIndex] then
		acoustics = map.layout.cells[cellIndex].acoustics or 1
	end
	local mult = (opts.multiplier or 1) * (opts.surfaceMultiplier or 1) * acoustics
	local loudness = def.Loudness * mult
	local radius = def.Radius * math.clamp(math.sqrt(math.max(mult, 0.01)), 0.4, 1.6)

	-- Merge with a near-identical recent event.
	for i = #active, 1, -1 do
		local e = active[i]
		if now > e.expires then
			table.remove(active, i)
		elseif e.category == category and e.source == opts.source and now - e.time < SoundConfig.MergeWindow and (e.position - position).Magnitude < SoundConfig.MergeDistance then
			e.loudness = math.max(e.loudness, loudness)
			return e
		end
	end
	if not sourceAllowed(opts.source, now) then
		return nil
	end

	local event = {
		category = category,
		position = position,
		loudness = loudness,
		radius = radius,
		time = now,
		expires = now + SoundConfig.EventLifetime,
		source = opts.source,
		cell = cellIndex,
	}
	table.insert(active, event)
	while #active > SoundConfig.MaxActiveEvents do
		table.remove(active, 1)
	end

	if cellIndex then
		local h = heat[cellIndex]
		local value = if h then SoundMath.decay(h.value, now - h.at, SoundConfig.HeatHalfLife) else 0
		heat[cellIndex] = { value = value + loudness, at = now }
	end

	-- Deliver to listeners.
	for _, listener in ipairs(listeners) do
		local ear = listener.getEar()
		if ear then
			local hearing = listener.hearingMultiplier()
			local distance = (ear - position).Magnitude
			if distance < radius * hearing then
				local walls, doorsHit, props = NoiseService.countObstacles(position + Vector3.new(0, 1.5, 0), ear, listener.exclude())
				local occlusion = SoundMath.occlusion(walls, doorsHit, props, SoundConfig.Occlusion)
				local perceived = SoundMath.perceived(loudness, radius, distance, occlusion, hearing)
				if perceived > 0 then
					local jitter = SoundMath.uncertainty(distance, occlusion, SoundConfig)
					local angle = rng:next() * math.pi * 2
					local r = rng:next() * jitter
					local estimate = position + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
					listener.onHear({
						position = estimate,
						intensity = perceived,
						category = category,
						distance = distance,
						source = opts.source,
						occlusion = occlusion,
					})
				end
			end
		end
	end

	-- Feedback to the player who made the noise (HUD noise meter).
	local source = opts.source
	if source and typeof(source) == "Instance" and source:IsA("Player") and source.Parent then
		if not lastFeedback[source] or now - lastFeedback[source] > 0.12 then
			lastFeedback[source] = now
			services.Remotes.NoiseFeedback:FireClient(source, math.clamp(loudness, 0, 1.3))
		end
	end

	if not opts.silentAudio and AUDIO_FOR[category] then
		services.Remotes.WorldSound:FireAllClients(AUDIO_FOR[category], position, math.clamp(mult, 0.3, 1.5))
	end

	debugMark(position, radius, loudness)
	return event
end

-- Heat-weighted random cell (for patrol bias). Returns nil when there is no heat.
function NoiseService.hotCell(randomizer)
	local now = os.clock()
	local weights = {}
	local any = false
	for index, h in pairs(heat) do
		local value = SoundMath.decay(h.value, now - h.at, SoundConfig.HeatHalfLife)
		if value > 0.05 then
			weights[tostring(index)] = value
			any = true
		end
	end
	if not any then
		return nil
	end
	return tonumber(randomizer:weighted(weights))
end

function NoiseService.activeEvents()
	return active
end

Players.PlayerRemoving:Connect(function(player)
	perSource[player] = nil
	lastFeedback[player] = nil
end)

return NoiseService
