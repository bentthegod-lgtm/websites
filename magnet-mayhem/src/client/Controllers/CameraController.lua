--[[
	CameraController - third person by default (Roblox's camera, with a slight over-the-
	shoulder offset and a comfortable starting zoom so the pile stays in view), optional
	first person (V or Settings), mouse sensitivity, and short FOV "punches" for big
	moments. Reduced camera effects turns punches off.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.ClientState)

local CameraController = {}

local player = Players.LocalPlayer
local BASE_FOV = 70
local SHOULDER = Vector3.new(1.4, 0.8, 0)
local MIN_ZOOM, MAX_ZOOM, RETURN_ZOOM = 8, 60, 16
local lastMode = nil

function CameraController.apply()
	local mode = ClientState.setting("CameraMode") or "Third"
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local wasFirst = lastMode == "First"
	lastMode = mode
	if mode == "First" then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = MAX_ZOOM
		if wasFirst then
			-- Leaving LockFirstPerson keeps Roblox's zoom at ~0.5 (still first person). The
			-- camera only re-clamps when the min zoom property changes, so raise it for a
			-- moment to push the camera back out, then restore it.
			player.CameraMinZoomDistance = RETURN_ZOOM
			task.delay(0.2, function()
				if lastMode ~= "First" then
					player.CameraMinZoomDistance = MIN_ZOOM
				end
			end)
		else
			player.CameraMinZoomDistance = MIN_ZOOM
		end
		if humanoid then
			humanoid.CameraOffset = SHOULDER
		end
	end
	local sensitivity = ClientState.setting("Sensitivity") or 1
	pcall(function()
		UserInputService.MouseDeltaSensitivity = sensitivity
	end)
end

function CameraController.toggleMode()
	local mode = if ClientState.setting("CameraMode") == "First" then "Third" else "First"
	ClientState.applySettings({ CameraMode = mode })
	ClientState.saveSettings()
end

-- A short field-of-view kick (strength 0..1.5).
function CameraController.punch(strength)
	if ClientState.setting("ReducedEffects") then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local kick = math.clamp(strength or 1, 0, 1.5) * 4
	camera.FieldOfView = BASE_FOV + kick
	TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { FieldOfView = BASE_FOV }):Play()
end

function CameraController.init()
	-- Start a bit further out than default so the pile is visible from the first second.
	player.CameraMinZoomDistance = 18
	task.delay(0.5, function()
		if lastMode ~= "First" then
			player.CameraMinZoomDistance = MIN_ZOOM
		end
	end)
	ClientState.SettingsChanged:Connect(CameraController.apply)
	player.CharacterAdded:Connect(function()
		task.defer(CameraController.apply)
	end)
	CameraController.apply()
end

return CameraController
