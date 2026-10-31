--[[
	KartController - YOUR kart, client-predicted.

	Every frame: input -> KartPhysics fixed steps (1/60 s) against the real track
	(WorldQuery raycasts) -> the invisible chassis is CFramed (the cosmetic model is welded
	to it) -> ~20 times a second the state goes to the server (KartState), which validates
	it and rebroadcasts it to everyone else.

	Also here: the start boost (gas pressed in the last moment before GO; too early =
	stall), kart-to-kart bumps against the interpolated remote karts, auto-respawn requests
	(fell off, stuck, off the course), server corrections / respawns / KartEffects, the
	ghost flicker after a respawn, and an autopilot cruise after you cross the line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local KartStats = require(Shared.Config.KartStats)
local KartPhysics = require(Shared.KartPhysics)
local BotBrain = require(Shared.BotBrain)
local TrackQuery = require(Shared.TrackQuery)
local VehicleModels = require(Shared.VehicleModels)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)
local WorldQuery = require(script.Parent.WorldQuery)

local KartController = {}

local state = nil
local model, rig = nil, nil
local raceId = nil
local acc = 0
local sendAcc = 0
local seq = 0
local gasPressedAt = nil
local startApplied = false
local lastAutoRespawn = -math.huge
local query = nil
local fallback = nil
local autopilot = nil
local folder = nil
local lastInput = { gas = 0, brake = 0, steer = 0, drift = false }
KartController.remotePositions = nil -- set by RemoteKarts: function() -> list of { pos, vel }

local function ground()
	if query then
		return query
	end
	local root = workspace:FindFirstChild("ChaosKartsWorld")
	local track = root and root:FindFirstChild("Track")
	if track and track:FindFirstChild("Ground") and track:FindFirstChild("Walls") then
		query = WorldQuery.new(track)
		KartController.queryKind = "raycast"
	else
		KartController.queryKind = "analytic"
		fallback = fallback or TrackQuery.new(ClientState.mapData())
		return fallback
	end
	return query
end

function KartController.state()
	return state
end

function KartController.model()
	return model
end

function KartController.rig()
	return rig
end

function KartController.input()
	return lastInput
end

function KartController.despawn()
	if model then
		model:Destroy()
	end
	model, rig, state = nil, nil, nil
	raceId = nil
	autopilot = nil
end

function KartController.spawn(racer, race)
	KartController.despawn()
	local data = ClientState.mapData()
	local cf = data.grid[racer.slot]
	state = KartPhysics.new(cf)
	raceId = race.raceId
	acc, sendAcc = 0, 0
	gasPressedAt, startApplied = nil, false
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "CK_LocalKart"
		folder.Parent = workspace
	end
	model, rig = VehicleModels.build(racer.vehicle, { cframe = cf, name = "MyKart", driverColor = racer.color, parent = folder })
	return state
end

local function onRace(race)
	local me = ClientState.myRacer()
	if ClientState.inRace() and me then
		if race.raceId ~= raceId then
			KartController.spawn(me, race)
		end
	elseif race.phase == "Lobby" or not me then
		if state then
			KartController.despawn()
		end
	end
end

local function finished()
	return ClientState.player():GetAttribute("CK_Finished") == true
end

local function send()
	seq += 1
	Net.event("KartState"):FireServer(state.pos, state.vel, state.yaw, KartPhysics.flags(state), seq)
end

-- One frame. Returns the physics events of this frame (for effects / audio / camera).
function KartController.step(dt)
	if not state then
		return nil
	end
	local race = ClientState.race
	local phase = race.phase
	local now = ClientState.serverNow()
	local input = InputController.read()
	if phase == "Countdown" or (race.goAt and now < race.goAt) then
		-- held on the grid; the start boost is judged on when gas went down
		if input.gas > 0.5 then
			gasPressedAt = gasPressedAt or now
		else
			gasPressedAt = nil
		end
		input = { gas = 0, brake = 0, steer = 0, drift = false }
	elseif not startApplied then
		startApplied = true
		KartPhysics.applyStart(state, KartPhysics.startResult(gasPressedAt, race.goAt or now))
	end
	if finished() then
		autopilot = autopilot or BotBrain.new(seq + 3, 0.9)
		input = BotBrain.think(autopilot, state, ClientState.mapData().main, dt)
		input.gas *= 0.65
	end
	lastInput = input
	local q = ground()
	local events = {}
	acc = math.min(acc + dt, KartStats.FixedStep * KartStats.MaxSubsteps)
	local hold = if phase == "Countdown" then state.pos else nil
	while acc >= KartStats.FixedStep - 1e-9 do
		acc -= KartStats.FixedStep
		KartPhysics.step(state, input, q, KartStats.FixedStep)
		if hold then
			state.pos = Vector3.new(hold.X, state.pos.Y, hold.Z)
			state.vel = Vector3.new(0, state.vel.Y, 0)
		end
		for _, e in ipairs(state.events) do
			table.insert(events, e)
		end
	end
	-- bumps against the other karts (simple circle push; the server checks the speed)
	if KartController.remotePositions and phase == "Racing" then
		for _, other in ipairs(KartController.remotePositions()) do
			if KartPhysics.bump(state, other.pos, other.vel) then
				table.insert(events, { name = "bump" })
			end
		end
	end
	-- auto-respawn: fell off, stuck, or off the course
	if phase == "Racing" and not finished() then
		local R = GameConfig.Respawn
		local data = ClientState.mapData()
		local why = nil
		if state.pos.Y < data.killY then
			why = "fell"
		elseif state.stuckT > R.StuckTime then
			why = "stuck"
		elseif state.offCourseT > R.OffCourseTime then
			why = "offcourse"
		end
		if why and os.clock() - lastAutoRespawn > 3 then
			lastAutoRespawn = os.clock()
			Net.event("Respawn"):FireServer(why)
		end
	end
	-- the model follows the chassis
	if model and model.PrimaryPart then
		model.PrimaryPart.CFrame = KartPhysics.cframe(state)
		VehicleModels.animate(rig, { speed = KartPhysics.forwardSpeed(state), steer = input.steer, drift = state.drift, squash = state.squash, dt = dt })
		local ghost = state.ghostT > 0 and math.floor(os.clock() * 10) % 2 == 0
		if ghost ~= KartController.ghostShown then
			KartController.ghostShown = ghost
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d ~= model.PrimaryPart and d.Name ~= "Body" and d.Name ~= "WheelHub" then
					d.LocalTransparencyModifier = if ghost then 0.6 else 0
				end
			end
		end
	end
	-- replicate (throttled)
	sendAcc += dt
	local interval = 1 / GameConfig.Net.SendRate
	if sendAcc >= interval then
		sendAcc %= interval
		send()
	end
	if #events > 0 then
		ClientState.KartEvents:Fire(events)
	end
	return events
end

function KartController.init()
	ClientState.RaceChanged:Connect(onRace)
	ClientState.KartCorrected:Connect(function(cf, vel)
		if state then
			KartPhysics.respawn(state, cf, 0)
			state.vel = vel or Vector3.new()
			KartController.corrections = (KartController.corrections or 0) + 1
		end
	end)
	ClientState.KartRespawned:Connect(function(cf, ghost)
		if state then
			KartPhysics.respawn(state, cf, ghost)
		end
	end)
	ClientState.KartEffected:Connect(function(kind, params)
		if state then
			KartPhysics.applyEffect(state, kind, params)
		end
	end)
	onRace(ClientState.race)
end

return KartController
