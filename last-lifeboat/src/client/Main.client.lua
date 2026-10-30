--[[
	LAST LIFEBOAT - client bootstrap. Starts every controller (each in a pcall so one
	failure can't take the whole UI down), then asks the server for the current state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local ORDER = {
	"ClientState",
	"AudioController",
	"InputController",
	"MovementController",
	"HudController",
	"MenuController",
	"EffectsController",
	"SocialController",
}

for _, name in ipairs(ORDER) do
	local ok, err = pcall(function()
		require(Controllers[name]).init()
	end)
	if not ok then
		warn("[LastLifeboat] Failed to start " .. name .. ": " .. tostring(err))
	end
end

Net.event("RequestState"):FireServer()
