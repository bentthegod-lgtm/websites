--[[
	AudioController - everything the player hears (presentation only; detection is server-side).

	* Surface-aware footsteps for every nearby character, generated locally from movement.
	* The Listener's heavy footsteps (from its replicated velocity) - spatialised, so you
	  can tell roughly where it is without the HUD ever showing it.
	* Quiet ambience: ventilation, fluorescent buzz once power is on, rare distant impacts.
	  Ambient one-shots are local only and never create gameplay noise.
	* Chase / tension layers that fade in by distance and state. Silence is the default.
	* Lobby music between runs, fading out as the elevator descends.
	* WorldSound replication from the server (doors, drops, objective machinery).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)

local ClientState = require(script.Parent.ClientState)

local AudioController = {}

local player = Players.LocalPlayer
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local stepState = {}
local loops = {}
local monsterStep = { accum = 0 }
local chaseLevel, tensionLevel = 0, 0
local lobbyLevel = 0

local function loop(name, def, group)
	local sound = AudioUtil.make(def, SoundService, group)
	if sound then
		sound.Volume = 0
		sound:Play()
	end
	loops[name] = { sound = sound, base = def.Volume or 0.5 }
	return loops[name]
end

local function setLoop(name, level)
	local entry = loops[name]
	if entry and entry.sound then
		entry.sound.Volume = entry.base * level
	end
end

local function surfaceAt(position, exclude)
	rayParams.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(position, Vector3.new(0, -7, 0), rayParams)
	if not result then
		return "Default"
	end
	local surface = result.Instance:GetAttribute("Surface")
	if surface then
		return surface
	end
	local m = result.Material
	if m == Enum.Material.DiamondPlate or m == Enum.Material.Metal then
		return "Metal"
	elseif m == Enum.Material.Concrete then
		return "Concrete"
	end
	return "Default"
end

local function characterFootsteps(dt)
	local camera = Workspace.CurrentCamera
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - camera.CFrame.Position).Magnitude < 90 then
			local s = stepState[other] or { accum = 0 }
			stepState[other] = s
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			if speed > 1 and math.abs(v.Y) < 3 and not root.Anchored then
				s.accum += speed * dt
				local stride = if speed > 15 then 5.8 elseif speed > 7 then 4.4 else 3.2
				if s.accum >= stride then
					s.accum = 0
					local surface = surfaceAt(root.Position, { character })
					local def = AudioAssets.Footstep[surface] or AudioAssets.Footstep.Default
					local loudness = if speed > 15 then 1.4 elseif speed > 7 then 1 else 0.45
					AudioUtil.playAt(def, root.Position - Vector3.new(0, 2.5, 0), "SFX", {
						Volume = def.Volume * loudness * (if other == player then 0.7 else 1),
						Pitch = def.Pitch * (0.92 + math.random() * 0.16),
					})
				end
			else
				s.accum = 0
			end
		end
	end
end

local function monsterAudio(dt)
	local monster = ClientState.monster()
	local root = monster and monster.PrimaryPart
	local camera = Workspace.CurrentCamera
	if not root then
		chaseLevel = math.max(0, chaseLevel - dt * 0.3)
		tensionLevel = math.max(0, tensionLevel - dt * 0.3)
		setLoop("Chase", chaseLevel)
		setLoop("Heartbeat", chaseLevel)
		setLoop("Tension", tensionLevel)
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if speed > 1 then
		monsterStep.accum += speed * dt
		local stride = if speed > 16 then 8 else 6
		if monsterStep.accum >= stride then
			monsterStep.accum = 0
			AudioUtil.playAt(AudioAssets.MonsterStep, root.Position - Vector3.new(0, 5.5, 0), "SFX", {
				Pitch = AudioAssets.MonsterStep.Pitch * (0.9 + math.random() * 0.2) * (if speed > 16 then 1.15 else 1),
			})
		end
	end

	local distance = (root.Position - camera.CFrame.Position).Magnitude
	local state = monster:GetAttribute("State")
	local chasingMe = monster:GetAttribute("TargetUserId") == player.UserId
	local chaseTarget = 0
	if state == "Chase" or state == "Attack" then
		chaseTarget = if chasingMe then 1 else math.clamp(1 - distance / 90, 0, 1)
	elseif state == "Lost" then
		chaseTarget = math.clamp(1 - distance / 70, 0, 0.6)
	end
	local tensionTarget = 0
	if state == "Investigate" or state == "Search" or state == "Suspicion" or state == "CheckHiding" then
		tensionTarget = math.clamp(1 - distance / 50, 0, 1)
	end
	chaseLevel += (chaseTarget - chaseLevel) * math.min(1, dt * (if chaseTarget > chaseLevel then 3 else 0.5))
	tensionLevel += (tensionTarget - tensionLevel) * math.min(1, dt * 0.8)
	setLoop("Chase", chaseLevel)
	setLoop("Heartbeat", math.max(chaseLevel, tensionLevel * 0.6))
	setLoop("Tension", tensionLevel * (1 - chaseLevel))
end

local function ambientOneShots()
	while true do
		task.wait(30 + math.random() * 50)
		if ClientState.roundState == "Playing" and ClientState.status() == "Alive" then
			local camera = Workspace.CurrentCamera
			local angle = math.random() * math.pi * 2
			local distance = 40 + math.random() * 50
			local position = camera.CFrame.Position + Vector3.new(math.cos(angle) * distance, 6, math.sin(angle) * distance)
			local def = if math.random() < 0.5 then AudioAssets.DistantImpact else AudioAssets.PipeCreak
			AudioUtil.playAt(def, position, "Ambience")
		end
	end
end

function AudioController.playAt(key, position, scale)
	local def = AudioAssets[key]
	if def then
		AudioUtil.playAt(def, position, "SFX", { Volume = (def.Volume or 0.5) * (scale or 1) })
	end
end

function AudioController.init()
	loop("Vent", AudioAssets.VentilationLoop, "Ambience")
	loop("Buzz", AudioAssets.FluorescentBuzz, "Ambience")
	loop("Hum", AudioAssets.ElectricalHum, "Ambience")
	loop("Chase", AudioAssets.ChaseLayer, "Music")
	loop("Tension", AudioAssets.TensionLayer, "Music")
	loop("Heartbeat", AudioAssets.Heartbeat, "Music")
	loop("Lobby", AudioAssets.LobbyMusic, "Music")

	ClientState.WorldSound:Connect(function(key, position, scale)
		AudioController.playAt(key, position, scale)
	end)
	ClientState.HorrorEvent:Connect(function(name, data)
		if name == "Vocalization" then
			AudioUtil.playAt(AudioAssets.MonsterVocal, data.position, "SFX")
		elseif name == "Knocks" then
			for i = 0, 2 do
				task.delay(0.8 + i * 0.45, function()
					AudioUtil.playAt(AudioAssets.DistantImpact, data.position, "SFX", { Volume = 0.8, Pitch = 0.9 })
				end)
			end
		elseif name == "PipeBurst" then
			AudioUtil.playAt(AudioAssets.DistantImpact, data.position, "SFX", { Volume = 1 })
		end
	end)
	ClientState.ResultsReceived:Connect(function(results)
		AudioUtil.play2D(if results.outcome == "Escaped" then AudioAssets.EscapeSting else AudioAssets.FailSting, "Music")
	end)

	task.spawn(ambientOneShots)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.05 then
			return
		end
		local step = accumulator
		accumulator = 0
		local inRun = ClientState.roundState == "Playing" and ClientState.inRun()
		local facility = Workspace:FindFirstChild("Facility")
		local powered = facility and facility:GetAttribute("Powered") == true
		-- Lobby music: plays outside a run (lobby, spectating, results), fades out on descent.
		local lobbyTarget = if inRun then 0 else 1
		lobbyLevel += (lobbyTarget - lobbyLevel) * math.min(1, step * (if lobbyTarget > lobbyLevel then 0.5 else 1.5))
		setLoop("Lobby", lobbyLevel)
		setLoop("Vent", if inRun then 1 else 0)
		setLoop("Buzz", if inRun and powered then 1 else 0)
		setLoop("Hum", if inRun and powered then 1 else 0.4)
		characterFootsteps(step)
		monsterAudio(step)
	end)
	Players.PlayerRemoving:Connect(function(other)
		stepState[other] = nil
	end)
end

return AudioController
