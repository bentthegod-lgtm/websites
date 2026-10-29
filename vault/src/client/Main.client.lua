--[[
	VAULT - client bootstrap. Starts every controller (each one in a pcall so one failure
	can't take the whole UI down), then asks the server for the current state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")

-- The game has its own HUD; the default backpack bar isn't used.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local ORDER = {
	"ClientState",
	"AudioController",
	"CollectController",
	"InputController",
	"StackController",
	"DepositController",
	"ElevatorController",
	"HudController",
	"MenuController",
	"TutorialController",
	"EffectsController",
}

local started = {}
for _, name in ipairs(ORDER) do
	local ok, err = pcall(function()
		require(Controllers[name]).init()
	end)
	if ok then
		table.insert(started, name)
	else
		warn("[Vault] Failed to start " .. name .. ": " .. tostring(err))
	end
end
script:SetAttribute("Started", table.concat(started, ","))

Net.event("RequestState"):FireServer()
