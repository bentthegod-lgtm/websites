--[[
	CameraController - first-person presentation: crouch height, head bob, sprint FOV kick,
	monster-proximity shake, the "caught" look, and spectating teammates after death/escape.
	All of it respects the accessibility settings.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local PlayerConfig = require(Shared.Config.PlayerConfig)
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Signal = require(Shared.Signal)

local ClientState = require(script.Parent.ClientState)
local Settings = require(script.Parent.Settings)
local InputController = require(script.Parent.InputController)

local CameraController = {
	spectating = nil,
	locked = false, -- the jumpscare owns the camera while true
	SpectateChanged = Signal.new(),
}

local player = Players.LocalPlayer
local bobPhase = 0
local crouchOffset = 0
local crouchTarget = 0
local fovKick = 0
local shakeImpulse = 0
local lookAtUntil = 0
local lookAtTarget

local function humanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function CameraController.impulse(amount)
	if Settings.get("CameraShake") then
		shakeImpulse = math.max(shakeImpulse, amount)
	end
end

-- Force the view toward a point for a moment (jumpscare when caught).
function CameraController.lookAt(position, duration)
	lookAtTarget = position
	lookAtUntil = os.clock() + duration
end

local function spectateCandidates()
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other:GetAttribute("DA_Status") == "Alive" and other.Character and other.Character:FindFirstChildOfClass("Humanoid") then
			table.insert(list, other)
		end
	end
	return list
end

function CameraController.cycleSpectate(direction)
	local list = spectateCandidates()
	local camera = Workspace.CurrentCamera
	if #list == 0 then
		CameraController.spectating = nil
		CameraController.SpectateChanged:Fire(nil)
		return
	end
	local index = table.find(list, CameraController.spectating) or 0
	index = ((index - 1 + (direction or 1)) % #list) + 1
	local target = list[index]
	CameraController.spectating = target
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = target.Character:FindFirstChildOfClass("Humanoid")
	CameraController.SpectateChanged:Fire(target)
end

local function refreshSpectate()
	if CameraController.locked then
		return
	end
	local status = ClientState.status()
	local shouldSpectate = (status == "Dead" or status == "Escaped") and ClientState.roundState == "Playing"
	if shouldSpectate then
		local current = CameraController.spectating
		if not current or current:GetAttribute("DA_Status") ~= "Alive" or not current.Character then
			CameraController.cycleSpectate(1)
		end
	elseif CameraController.spectating then
		CameraController.spectating = nil
		local h = humanoid()
		if h then
			Workspace.CurrentCamera.CameraSubject = h
		end
		CameraController.SpectateChanged:Fire(nil)
	end
end

function CameraController.init()
	InputController.CrouchChanged:Connect(function(crouch)
		crouchTarget = if crouch then PlayerConfig.CrouchCameraOffset else 0
	end)

	ClientState.MonsterCue:Connect(function(cue, data)
		if cue == "ChaseStart" then
			if data.targetUserId == player.UserId then
				CameraController.impulse(0.9)
			end
		elseif cue == "AttackWindup" then
			CameraController.impulse(0.6)
		elseif cue == "DoorBurst" then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - data.position).Magnitude < 40 then
				CameraController.impulse(0.5)
			end
		end
	end)

	player:GetAttributeChangedSignal("DA_Status"):Connect(refreshSpectate)
	ClientState.RoundChanged:Connect(refreshSpectate)
	task.spawn(function()
		while true do
			task.wait(1)
			refreshSpectate()
		end
	end)

	CameraController.refresh = refreshSpectate

	RunService:BindToRenderStep("DA_Camera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if CameraController.locked then
			return
		end
		local camera = Workspace.CurrentCamera
		local h = humanoid()
		local status = ClientState.status()

		-- FOV: setting + sprint kick
		local sprinting = player:GetAttribute("DA_Sprinting") == true
		fovKick += ((if sprinting then 6 else 0) - fovKick) * math.min(1, dt * 6)
		camera.FieldOfView = Settings.get("Fov") + fovKick

		crouchOffset += (crouchTarget - crouchOffset) * math.min(1, dt * 10)
		if h and not CameraController.spectating then
			local offset = Vector3.new(0, crouchOffset, 0)
			if status == "Downed" then
				offset = Vector3.new(0, -2.6, 0)
			end
			local root = h.RootPart
			if Settings.get("HeadBob") and root and status == "Alive" and not player:GetAttribute("DA_Hidden") then
				local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
				if speed > 1 and h.FloorMaterial ~= Enum.Material.Air then
					bobPhase += dt * speed * 0.9
					local amp = math.clamp(speed / 20, 0, 1)
					offset += Vector3.new(math.cos(bobPhase * 0.5) * 0.08 * amp, math.abs(math.sin(bobPhase * 0.5)) * 0.16 * amp, 0)
				end
			end
			h.CameraOffset = offset
		end

		-- Monster proximity shake
		local monster = ClientState.monster()
		local mroot = monster and monster.PrimaryPart
		if mroot and Settings.get("CameraShake") then
			local d = (mroot.Position - camera.CFrame.Position).Magnitude
			if d < MonsterConfig.Cues.ShakeRadius then
				shakeImpulse = math.max(shakeImpulse, (1 - d / MonsterConfig.Cues.ShakeRadius) * 0.35)
			end
		end
		if shakeImpulse > 0.01 then
			local t = os.clock() * 40
			local s = shakeImpulse * 0.02
			camera.CFrame = camera.CFrame * CFrame.Angles(math.noise(t, 1) * s, math.noise(t, 2) * s, math.noise(t, 3) * s * 0.5)
			shakeImpulse *= math.max(0, 1 - dt * 3)
		else
			shakeImpulse = 0
		end

		if os.clock() < lookAtUntil and lookAtTarget then
			local pos = camera.CFrame.Position
			camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(pos, lookAtTarget), 0.35)
		end
	end)
end

return CameraController
