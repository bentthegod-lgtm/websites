--[[
	HorrorController - local-only scares sent by HorrorEventService.

	DistantFigure: a Listener silhouette appears at the far end of whatever the player is
	looking down, and vanishes once it has been seen. Only this player saw it.
	FootstepsBehind: a few footsteps creep up behind the camera, then stop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)

local ClientState = require(script.Parent.ClientState)

local HorrorController = {}

local player = Players.LocalPlayer
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function silhouette(position, facing)
	local model = Instance.new("Model")
	model.Name = "Silhouette"
	local color = Color3.fromRGB(150, 142, 126)
	local base = CFrame.lookAt(position, position + facing)
	local function p(size, offset)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = true
		part.Size = size
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = base * offset
		part.Parent = model
	end
	p(Vector3.new(0.4, 5.6, 0.4), CFrame.new(-0.4, 2.8, 0))
	p(Vector3.new(0.4, 5.6, 0.4), CFrame.new(0.4, 2.8, 0))
	p(Vector3.new(1.2, 3, 0.6), CFrame.new(0, 7, 0.3) * CFrame.Angles(math.rad(-18), 0, 0))
	p(Vector3.new(0.3, 1, 0.3), CFrame.new(0, 8.9, -0.2))
	p(Vector3.new(0.8, 1.8, 1.2), CFrame.new(0, 10, -0.5) * CFrame.Angles(math.rad(25), 0, 0))
	p(Vector3.new(0.05, 2, 1.4), CFrame.new(-0.55, 10.6, -0.4) * CFrame.Angles(0, 0, math.rad(20)))
	p(Vector3.new(0.05, 2, 1.4), CFrame.new(0.55, 10.6, -0.4) * CFrame.Angles(0, 0, math.rad(-20)))
	p(Vector3.new(0.25, 6.5, 0.25), CFrame.new(-0.9, 5.4, -0.2))
	p(Vector3.new(0.25, 6.5, 0.25), CFrame.new(0.9, 5.4, -0.2))
	model.Parent = Workspace.CurrentCamera
	return model
end

local function distantFigure(data)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	rayParams.FilterDescendantsInstances = { character, camera }
	local origin = camera.CFrame.Position
	local spot
	for attempt = 0, 6 do
		local yaw = if attempt == 0 then 0 else (math.random() - 0.5) * math.rad(60)
		local dir = (CFrame.Angles(0, yaw, 0) * camera.CFrame).LookVector
		dir = Vector3.new(dir.X, 0, dir.Z).Unit
		local result = Workspace:Raycast(origin, dir * data.maxDistance, rayParams)
		local hitDistance = if result then (result.Position - origin).Magnitude else data.maxDistance
		if hitDistance >= data.minDistance then
			local point = origin + dir * (hitDistance - 3)
			local ground = Workspace:Raycast(point, Vector3.new(0, -20, 0), rayParams)
			if ground then
				spot = { position = ground.Position, facing = -dir }
				break
			end
		end
	end
	if not spot then
		return
	end
	local model = silhouette(spot.position, spot.facing)
	local seenFor = 0
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		local head = spot.position + Vector3.new(0, 9, 0)
		local _, onScreen = cam:WorldToViewportPoint(head)
		local distance = (head - cam.CFrame.Position).Magnitude
		if onScreen then
			seenFor += dt
		end
		if seenFor >= data.vanishAfterSeen or os.clock() - started > data.lifetime or distance < 25 then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

local function footstepsBehind(data)
	local def = AudioAssets.Footstep.Default
	for i = 1, data.steps do
		task.delay(i * 0.55, function()
			local cam = Workspace.CurrentCamera
			local behind = cam.CFrame.Position - cam.CFrame.LookVector * (9 - i * 1.2) - Vector3.new(0, 4, 0)
			AudioUtil.playAt(def, behind, "SFX", { Volume = def.Volume * 0.8, Pitch = def.Pitch * 0.85 })
		end)
	end
end

function HorrorController.init()
	ClientState.HorrorEvent:Connect(function(name, data)
		if ClientState.status() ~= "Alive" then
			return
		end
		if name == "DistantFigure" then
			distantFigure(data)
		elseif name == "FootstepsBehind" then
			footstepsBehind(data)
		elseif name == "PipeBurst" then
			local smoke = Instance.new("Smoke")
			smoke.Color = Color3.fromRGB(220, 220, 210)
			smoke.Opacity = 0.15
			smoke.RiseVelocity = -2
			smoke.Size = 4
			local attachment = Instance.new("Attachment")
			attachment.Parent = Workspace.Terrain
			attachment.WorldPosition = data.position
			smoke.Parent = attachment
			task.delay(4, function()
				smoke.Enabled = false
				task.wait(4)
				attachment:Destroy()
			end)
		end
	end)
end

return HorrorController
