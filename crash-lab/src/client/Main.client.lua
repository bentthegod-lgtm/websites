--[[
	CRASH LAB - client bootstrap. Starts every controller (each one in a pcall so one
	failure can't take the whole UI down), then asks the server for the current state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")

-- The game has its own HUD; the default backpack bar isn't used.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local ORDER = {
	"ClientState",
	"AudioController",
	"CameraController",
	"InputController",
	"LaunchController",
	"HudController",
	"ResultsController",
	"JuiceController",
	"EffectsController",
	"TutorialController",
	"MenuController",
	"LightingController",
}

for _, name in ipairs(ORDER) do
	local ok, err = pcall(function()
		require(Controllers[name]).init()
	end)
	if not ok then
		warn("[CrashLab] Failed to start " .. name .. ": " .. tostring(err))
	end
end

Net.event("RequestState"):FireServer()
