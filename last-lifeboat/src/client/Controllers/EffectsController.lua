--[[
	EffectsController - screen and camera effects:
	  * BRACE: a red flash at the screen edges; LURCH: camera shake (Camera shake setting)
	  * underwater: a teal colour grade and a little blur while the camera is below the sea
	  * downed: desaturated, darker
	  * the grapple rope (a Beam from you to the hook point)
	  * the launch cinematic: letterbox and a camera that follows the lifeboat
	  * spectating: once you're out, the camera follows a teammate who is still in it
	Reduced effects tones down the flash and the blur.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local HudController = require(script.Parent.HudController)
local MovementController = require(script.Parent.MovementController)

local EffectsController = {}

local gui, flash
local grade, blur
local shakeAmount, shakeUntil = 0, 0
local flashUntil = 0
local cinematic = nil
local spectateIndex = 1
local spectating = nil
local rope = nil
local rng = Random.new()

function EffectsController.shake(strength, seconds)
	if ClientState.setting("CameraShake") == false then
		return false
	end
	shakeAmount = math.max(shakeAmount, strength)
	shakeUntil = math.max(shakeUntil, os.clock() + (seconds or 0.6))
	return true
end

function EffectsController.braceFlash()
	flashUntil = os.clock() + GameConfig.Sinking.BraceTime + 0.3
	EffectsController.shake(0.2, GameConfig.Sinking.BraceTime)
end

-- Colour grade target for the current situation (underwater / downed / normal).
function EffectsController.gradeFor(underwater, downed, reduced)
	if downed then
		return { saturation = -0.6, brightness = -0.08, tint = Color3.fromRGB(255, 220, 220), blur = if reduced then 0 else 4 }
	elseif underwater then
		return { saturation = -0.15, brightness = -0.05, tint = Color3.fromRGB(150, 220, 230), blur = if reduced then 2 else 7 }
	end
	return { saturation = 0.05, brightness = 0, tint = Color3.fromRGB(255, 248, 240), blur = 0 }
end

function EffectsController.setRope(target)
	if rope then
		rope.beam:Destroy()
		rope.a1:Destroy()
		rope.a0:Destroy()
		rope = nil
	end
	local root = ClientState.root()
	if not target or not root then
		return nil
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local a0 = Instance.new("Attachment")
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = target
	a1.Parent = terrain or root
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0, beam.Width1 = 0.2, 0.2
	beam.Color = ColorSequence.new(Color3.fromRGB(200, 170, 120))
	beam.FaceCamera = true
	beam.Parent = root
	rope = { beam = beam, a0 = a0, a1 = a1 }
	return beam
end

function EffectsController.startCinematic(kind, data)
	if kind ~= "Launch" or type(data) ~= "table" then
		return
	end
	cinematic = { boat = data.boat, untilAt = os.clock() + (data.duration or GameConfig.Lifeboat.CinematicTime) + 0.5, angle = 0 }
	HudController.setLetterbox(true)
end

local function aliveTeammates()
	local list = {}
	for _, row in ipairs(ClientState.team) do
		if (row.state == "Alive" or row.state == "Downed") and row.userId ~= Players.LocalPlayer.UserId then
			local p = Players:GetPlayerByUserId(row.userId)
			if p and p.Character then
				table.insert(list, p)
			end
		end
	end
	return list
end

function EffectsController.nextSpectate()
	spectateIndex += 1
	spectating = nil
end

-- Who I should be watching (nil = myself).
function EffectsController.spectateTarget()
	local me = ClientState.me()
	if not (ClientState.round.phase == "Running" and me.inRound and me.state == "Out") then
		return nil
	end
	local list = aliveTeammates()
	if #list == 0 then
		return nil
	end
	spectateIndex = (spectateIndex - 1) % #list + 1
	return list[spectateIndex]
end

function EffectsController.step(dt)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local reduced = ClientState.setting("ReducedEffects") == true
	-- brace flash
	local flashing = now < flashUntil
	flash.Visible = flashing
	if flashing then
		local pulse = 0.5 + 0.5 * math.sin(now * 14)
		flash.BackgroundTransparency = if reduced then 0.85 else 0.55 + 0.3 * pulse
	end
	-- colour grade
	local me = ClientState.me()
	local underwater = camera ~= nil and camera.CFrame.Position.Y < GameConfig.World.SeaLevel
	local target = EffectsController.gradeFor(underwater, me.state == "Downed" and ClientState.inRound(), reduced)
	local k = math.clamp((dt or 0.016) * 6, 0, 1)
	grade.Saturation += (target.saturation - grade.Saturation) * k
	grade.Brightness += (target.brightness - grade.Brightness) * k
	grade.TintColor = grade.TintColor:Lerp(target.tint, k)
	blur.Size += (target.blur - blur.Size) * k
	-- camera shake
	local humanoid = ClientState.humanoid()
	if humanoid then
		if now < shakeUntil then
			local a = shakeAmount * math.clamp((shakeUntil - now) / 0.6, 0, 1)
			humanoid.CameraOffset = Vector3.new(rng:NextNumber(-a, a), rng:NextNumber(-a, a), 0)
		elseif shakeAmount > 0 then
			shakeAmount = 0
			humanoid.CameraOffset = Vector3.zero
		end
	end
	-- cinematic
	if cinematic and camera then
		if now > cinematic.untilAt or not cinematic.boat or not cinematic.boat.Parent then
			cinematic = nil
			camera.CameraType = Enum.CameraType.Custom
			HudController.setLetterbox(false)
		else
			cinematic.angle += (dt or 0.016) * 0.25
			local boatPos = cinematic.boat:GetPivot().Position
			local eye = boatPos + Vector3.new(math.cos(cinematic.angle) * 46, 18, math.sin(cinematic.angle) * 46)
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAt(eye, boatPos)
		end
	end
	-- spectating
	local target2 = EffectsController.spectateTarget()
	if camera and not cinematic then
		if target2 and target2 ~= spectating then
			spectating = target2
			local h = target2.Character and target2.Character:FindFirstChildOfClass("Humanoid")
			if h then
				camera.CameraSubject = h
			end
			HudController.setSpectating(target2.DisplayName)
		elseif not target2 and spectating then
			spectating = nil
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
	return flashing
end

function EffectsController.init()
	gui = Ui.screen("LifeboatFx", 4)
	gui.IgnoreGuiInset = true
	flash = Ui.new("Frame", { Name = "BraceFlash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(200, 20, 20), BackgroundTransparency = 0.7, Visible = false, Parent = gui })
	Ui.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0) }), Parent = flash })
	grade = Lighting:FindFirstChild("LL_Grade") or Instance.new("ColorCorrectionEffect")
	grade.Name = "LL_Grade"
	grade.Parent = Lighting
	blur = Lighting:FindFirstChild("LL_Blur") or Instance.new("BlurEffect")
	blur.Name = "LL_Blur"
	blur.Size = 0
	blur.Parent = Lighting
	MovementController.shake = EffectsController.shake
	MovementController.rope = EffectsController.setRope
	HudController.onNextSpectate = EffectsController.nextSpectate
	ClientState.Braced:Connect(EffectsController.braceFlash)
	ClientState.Cinematic:Connect(EffectsController.startCinematic)
	RunService.RenderStepped:Connect(EffectsController.step)
end

return EffectsController
