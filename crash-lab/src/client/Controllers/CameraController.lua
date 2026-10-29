--[[
	CameraController - third person by default (Roblox's camera with a slight shoulder
	offset and a comfortable zoom), plus:
	  * Follow cam: during YOUR run the camera smoothly chases your dummy from behind and
	    above (looking down the course), then returns to your character when the run ends.
	    Settings > Follow cam turns it off; Space / the SKIP button returns early.
	  * Camera shake on heavy impacts (Settings > Camera shake) and short FOV punches on
	    launches. Reduced effects disables both.
	The follow cam only reads replicated positions; it never moves anything.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.ClientState)

local CameraController = {}

local player = Players.LocalPlayer
local BASE_FOV = 70
local SHOULDER = Vector3.new(1.2, 0.6, 0)
local following = nil -- { root, cf }
local shake = 0
local transition = 0

CameraController.following = function()
	return following ~= nil
end

function CameraController.apply()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = 70
	player.CameraMinZoomDistance = 6
	if humanoid then
		humanoid.CameraOffset = SHOULDER
	end
	pcall(function()
		UserInputService.MouseDeltaSensitivity = ClientState.setting("Sensitivity") or 1
	end)
end

local function effectsAllowed()
	return not ClientState.setting("ReducedEffects")
end

function CameraController.punch(strength)
	if not effectsAllowed() then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.FieldOfView = BASE_FOV + math.clamp(strength or 1, 0, 1.5) * 5
	TweenService:Create(camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { FieldOfView = BASE_FOV }):Play()
end

function CameraController.shake(amount)
	if not effectsAllowed() or ClientState.setting("CameraShake") == false then
		return
	end
	shake = math.min(1.2, shake + (amount or 0.5))
end

function CameraController.follow(model)
	if ClientState.setting("FollowCam") == false or not model then
		return
	end
	local root = model:FindFirstChild("Root")
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return
	end
	following = { root = root, cf = camera.CFrame }
	transition = 0
	camera.CameraType = Enum.CameraType.Scriptable
end

function CameraController.stopFollow()
	if not following then
		return
	end
	following = nil
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = BASE_FOV
	end
end

-- Impact feel by tier: FOV punch strength, shake amount, hit-stop length (seconds).
CameraController.TierFeel = {
	Light = { punch = 0, shake = 0, stop = 0 },
	Medium = { punch = 0.25, shake = 0.15, stop = 0 },
	Heavy = { punch = 0.6, shake = 0.45, stop = 0 },
	Massive = { punch = 1.2, shake = 0.8, stop = 0.12 },
}

-- Hit-stop: a short slow-motion beat on the CAMERA only (the follow cam nearly freezes,
-- then eases back) plus a quick brightness flash. The server's physics never pauses.
local timeScale = 1
local stopUntil = 0
local flash
function CameraController.hitStop(duration)
	if not effectsAllowed() or (duration or 0) <= 0 then
		return false
	end
	stopUntil = os.clock() + duration
	timeScale = 0.06
	local camera = workspace.CurrentCamera
	if camera then
		if not flash or not flash.Parent then
			flash = Instance.new("ColorCorrectionEffect")
			flash.Name = "CL_HitFlash"
			flash.Parent = camera
		end
		flash.Brightness = 0.25
		flash.Contrast = 0.15
		TweenService:Create(flash, TweenInfo.new(0.3), { Brightness = 0, Contrast = 0 }):Play()
	end
	return true
end

function CameraController.timeScale()
	return timeScale
end

function CameraController.impact(tier)
	local feel = CameraController.TierFeel[tier]
	if not feel then
		return
	end
	if feel.punch > 0 then
		CameraController.punch(feel.punch)
	end
	if feel.shake > 0 then
		CameraController.shake(feel.shake)
	end
	if feel.stop > 0 then
		CameraController.hitStop(feel.stop)
	end
end

-- Pure camera maths for one frame (exposed for tests).
function CameraController.followFrame(current, target, dt)
	local behind = target + Vector3.new(0, 14, -30)
	local look = target + Vector3.new(0, 2, 30)
	local goal = CFrame.lookAt(behind, look)
	local alpha = 1 - math.exp(-dt * 4)
	return current:Lerp(goal, alpha)
end

function CameraController.step(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if following then
		if not following.root.Parent then
			CameraController.stopFollow()
			return
		end
		transition = math.min(1, transition + dt * 1.5)
		if os.clock() >= stopUntil and timeScale < 1 then
			timeScale = math.min(1, timeScale + dt * 4) -- ease back over ~0.25 s
		end
		following.cf = CameraController.followFrame(following.cf, following.root.Position, dt * timeScale)
		local cf = following.cf
		if shake > 0 then
			local s = shake * 0.4
			cf = cf * CFrame.Angles(math.noise(os.clock() * 25, 1) * s * 0.05, math.noise(os.clock() * 25, 2) * s * 0.05, 0)
		end
		camera.CFrame = cf
	elseif shake > 0 then
		camera.CFrame = camera.CFrame * CFrame.Angles(math.noise(os.clock() * 25, 3) * shake * 0.02, math.noise(os.clock() * 25, 4) * shake * 0.02, 0)
	end
	shake = math.max(0, shake - dt * 2.5)
end

function CameraController.init()
	ClientState.SettingsChanged:Connect(CameraController.apply)
	player.CharacterAdded:Connect(function()
		task.defer(CameraController.apply)
	end)
	CameraController.apply()
	ClientState.RunStarted:Connect(function(userId, _padIndex, model)
		if userId == player.UserId then
			CameraController.punch(1)
			CameraController.follow(model)
		end
	end)
	ClientState.RunEnded:Connect(function(userId)
		if userId == player.UserId then
			task.delay(1, CameraController.stopFollow)
		end
	end)
	ClientState.RunEvent:Connect(function(userId, kind, data)
		if userId == player.UserId and kind == "Impact" then
			CameraController.impact(data.tier)
		end
	end)
	RunService:BindToRenderStep("CrashLabCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		CameraController.step(dt)
	end)
end

return CameraController
