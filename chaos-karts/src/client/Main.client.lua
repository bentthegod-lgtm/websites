--[[
	CHAOS KARTS - client bootstrap. Starts every controller (each in a pcall so one failure
	can't take the whole UI down), connects the frame loop, then asks the server for the
	current state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local ORDER = {
	"ClientState",
	"AudioController",
	"InputController",
	"KartController",
	"RemoteKarts",
	"EffectsController",
	"SpectateController",
	"CameraController",
	"EventController",
	"HudController",
	"MenuController",
	"FrameLoop",
}

for _, name in ipairs(ORDER) do
	local ok, err = pcall(function()
		require(Controllers[name]).init()
	end)
	if not ok then
		warn("[ChaosKarts] Failed to start " .. name .. ": " .. tostring(err))
	end
end

local FrameLoop = require(Controllers.FrameLoop)
RunService.RenderStepped:Connect(FrameLoop.step)

Net.event("RequestState"):FireServer()
