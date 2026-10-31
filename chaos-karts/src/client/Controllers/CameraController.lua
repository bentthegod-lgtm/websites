--[[
	CameraController - the racing camera.
	  lobby     the normal Roblox character camera
	  intro     a swooping flyover of the grid before the lights (Countdown)
	  chase     behind your kart, smoothed, looking ahead INTO turns (steer + yaw rate),
	            FOV kick on boosts and a little extra FOV with speed, screen shake from
	            EffectsController (landings, wall hits, events)
	  orbit     after you cross the line: a slow orbit around your kart
	  spectate  chase-cam on the racer SpectateController picks
	  results   a slow orbit around the start / finish gantry
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local KartStats = require(Shared.Config.KartStats)
local KartPhysics = require(Shared.KartPhysics)

local ClientState = require(script.Parent.ClientState)
local KartController = require(script.Parent.KartController)
local RemoteKarts = require(script.Parent.RemoteKarts)
local EffectsController = require(script.Parent.EffectsController)
local SpectateController = require(script.Parent.SpectateController)

local CameraController = {}

local G = GameConfig.Camera
local camPos = nil
local fov = G.BaseFov
local look = 0
local orbitAngle = 0
local Y = Vector3.new(0, 1, 0)

function CameraController.mode()
	local phase = ClientState.phase()
	local race = ClientState.race
	if phase == "Results" then
		return "results"
	end
	if ClientState.inRace() and KartController.state() then
		if ClientState.player():GetAttribute("CK_Finished") then
			return "orbit"
		end
		local introEnd = (race.goAt or 0) - GameConfig.Race.CountdownTime
		if phase == "Countdown" and ClientState.serverNow() < introEnd then
			return "intro"
		end
		return "chase"
	end
	if ClientState.spectating() then
		return "spectate"
	end
	return "lobby"
end

local function chase(camera, pos, fwd, speed, steer, yawRate, boosting, dt)
	local wantLook = math.clamp(steer * G.LookAhead + yawRate * 0.1, -0.6, 0.6)
	look += (wantLook - look) * math.min(1, dt * 4)
	local dir = (CFrame.Angles(0, -look, 0) * CFrame.lookAt(Vector3.new(), fwd)).LookVector
	local back = math.clamp(speed / KartStats.TopSpeed, 0, 1.4)
	local desired = pos - dir * (G.Distance + back * 3) + Y * (G.Height + back * 0.6)
	camPos = if camPos then camPos:Lerp(desired, 1 - math.exp(-G.Smooth * dt)) else desired
	local target = pos + dir * 12 + Y * 2.2
	local wantFov = G.BaseFov + G.SpeedFov * math.clamp(speed / KartStats.TopSpeed, 0, 1) + (if boosting then G.BoostFov - G.BaseFov else 0)
	fov += (wantFov - fov) * math.min(1, dt * 5)
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(camPos, target) * EffectsController.shakeOffset()
end

local function orbit(camera, centre, radius, height, dt)
	orbitAngle += dt * 0.45
	local p = centre + Vector3.new(math.cos(orbitAngle) * radius, height, math.sin(orbitAngle) * radius)
	camPos = p
	camera.FieldOfView = G.BaseFov
	camera.CFrame = CFrame.lookAt(p, centre + Vector3.new(0, 2, 0))
end

function CameraController.step(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mode = CameraController.mode()
	if mode == "lobby" then
		if camera.CameraType ~= Enum.CameraType.Custom then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = G.BaseFov
			local character = ClientState.player().Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		camPos = nil
		return mode
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if mode == "chase" then
		local s = KartController.state()
		local input = KartController.input()
		local fwd = KartPhysics.forward(s.yaw)
		chase(camera, s.pos, fwd, KartPhysics.speed(s), input.steer or 0, s.yawRate, s.boostT > 0, dt)
	elseif mode == "intro" then
		local race = ClientState.race
		local grid = ClientState.mapData().grid
		local mine = ClientState.myRacer()
		local cf = grid[mine and mine.slot or 1]
		local introEnd = race.goAt - GameConfig.Race.CountdownTime
		local u = math.clamp(1 - (introEnd - ClientState.serverNow()) / GameConfig.Race.IntroTime, 0, 1)
		local a = math.rad(160) * (1 - u)
		local radius = 70 - 50 * u
		local p = cf.Position + (CFrame.Angles(0, a, 0) * CFrame.lookAt(Vector3.new(), -cf.LookVector)).LookVector * radius + Y * (40 - 33 * u)
		camPos = p
		camera.FieldOfView = G.BaseFov
		camera.CFrame = CFrame.lookAt(p, cf.Position + cf.LookVector * (30 * u))
	elseif mode == "orbit" then
		orbit(camera, KartController.state().pos, 20, 8, dt)
	elseif mode == "spectate" then
		local target = SpectateController.target()
		local entry = target and RemoteKarts.get(target.id)
		if entry and entry.pos then
			local fwd = entry.model.PrimaryPart.CFrame.LookVector
			fwd = Vector3.new(fwd.X, 0, fwd.Z).Unit
			local speed = Vector3.new(entry.vel.X, 0, entry.vel.Z).Magnitude
			chase(camera, entry.pos, fwd, speed, 0, 0, KartPhysics.hasFlag(entry.flags or 0, KartPhysics.Flags.Boost), dt)
		else
			local cf = ClientState.mapData().checkpoints[1].cframe
			orbit(camera, cf.Position, 60, 30, dt)
		end
	elseif mode == "results" then
		local cf = ClientState.mapData().checkpoints[1].cframe
		orbit(camera, cf.Position + Vector3.new(0, 10, 0), 70, 22, dt)
	end
	return mode
end

function CameraController.fov()
	return fov
end

function CameraController.init() end

return CameraController
