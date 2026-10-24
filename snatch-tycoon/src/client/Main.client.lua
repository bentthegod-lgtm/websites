--[[
	Snatch a Blobby - client bootstrap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local order = {
	"ClientState",
	"AudioController",
	"HudController",
	"MenuController",
	"EffectsController",
	"WorldController",
	"InputController",
	"ChatController",
}

for _, name in ipairs(order) do
	local ok, err = pcall(function()
		require(Controllers[name]).init()
	end)
	if not ok then
		warn("[SnatchTycoon] Failed to start " .. name .. ": " .. tostring(err))
	end
end

Net.event("RequestState"):FireServer()
