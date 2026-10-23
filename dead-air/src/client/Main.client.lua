--[[
	DEAD AIR - client bootstrap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")

-- The game supplies its own HUD; hide the default health bar and backpack.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local order = {
	"ClientState",
	"Settings",
	"InputController",
	"CameraController",
	"HudController",
	"MenuController",
	"AudioController",
	"EffectsController",
	"HorrorController",
	"MonsterAnimator",
}

for _, name in ipairs(order) do
	local ok, err = pcall(function()
		require(Controllers[name]).init()
	end)
	if not ok then
		warn("[DeadAir] Failed to start " .. name .. ": " .. tostring(err))
	end
end

Net.event("RequestState"):FireServer()
