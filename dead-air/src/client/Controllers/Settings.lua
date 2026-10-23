--[[
	Settings - local copy of the player's settings (loaded from the profile), applied
	immediately and saved to the server with a debounce.
]]

local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local AudioUtil = require(Shared.AudioUtil)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local Settings = {
	values = {
		Master = 1,
		Music = 0.8,
		Sfx = 1,
		Sensitivity = 1,
		Fov = 78,
		Brightness = 0,
		HeadBob = true,
		ReduceFlicker = false,
		CameraShake = true,
		LargeText = false,
	},
	Changed = Signal.new(),
}

Settings.Definitions = {
	{ key = "Master", label = "Master volume", kind = "slider", min = 0, max = 1, step = 0.1 },
	{ key = "Music", label = "Music volume", kind = "slider", min = 0, max = 1, step = 0.1 },
	{ key = "Sfx", label = "Effects volume", kind = "slider", min = 0, max = 1, step = 0.1 },
	{ key = "Sensitivity", label = "Look sensitivity", kind = "slider", min = 0.2, max = 3, step = 0.1 },
	{ key = "Fov", label = "Field of view", kind = "slider", min = 60, max = 100, step = 2 },
	{ key = "Brightness", label = "Brightness", kind = "slider", min = -0.3, max = 0.6, step = 0.05 },
	{ key = "HeadBob", label = "Head bob", kind = "toggle" },
	{ key = "CameraShake", label = "Camera shake", kind = "toggle" },
	{ key = "ReduceFlicker", label = "Reduce flicker (photosensitivity)", kind = "toggle" },
	{ key = "LargeText", label = "Large text", kind = "toggle" },
}

local saveScheduled = false

local function apply()
	local v = Settings.values
	AudioUtil.group("Master").Volume = v.Master
	AudioUtil.group("SFX").Volume = v.Sfx * v.Master
	AudioUtil.group("Ambience").Volume = v.Sfx * v.Master
	AudioUtil.group("Music").Volume = v.Music * v.Master
	pcall(function()
		UserInputService.MouseDeltaSensitivity = v.Sensitivity
	end)
	local grade = Lighting:FindFirstChild("DA_Grade")
	if grade then
		grade.Brightness = v.Brightness
	end
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera.FieldOfView = v.Fov
	end
	Ui.setTextScale(if v.LargeText then 1.3 else 1)
	Settings.Changed:Fire(v)
end

function Settings.get(key)
	return Settings.values[key]
end

function Settings.set(key, value)
	Settings.values[key] = value
	apply()
	if not saveScheduled then
		saveScheduled = true
		task.delay(1.5, function()
			saveScheduled = false
			Net.event("SaveSettings"):FireServer(Settings.values)
		end)
	end
end

function Settings.init()
	ClientState.ProfileChanged:Connect(function(profile)
		if profile and profile.settings then
			for k, v in pairs(profile.settings) do
				Settings.values[k] = v
			end
			apply()
		end
	end)
	-- The grade effect replicates from the server shortly after join.
	Lighting.ChildAdded:Connect(function(child)
		if child.Name == "DA_Grade" then
			apply()
		end
	end)
	apply()
end

return Settings
