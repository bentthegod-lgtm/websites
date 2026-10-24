--[[
	REBOUND RUMBLE - client bootstrap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local order = {
	"ClientState",
	"InputController",
	"BallController",
	"EffectsController",
	"HudController",
	"MenuController",
	"SpectateController",
	"LightingController",
}

for _, name in ipairs(order) do
	local ok, err = pcall(function()
		require(Controllers[name]).init()
	end)
	if not ok then
		warn("[ReboundRumble] Failed to start " .. name .. ": " .. tostring(err))
	end
end

Net.event("RequestState"):FireServer()
