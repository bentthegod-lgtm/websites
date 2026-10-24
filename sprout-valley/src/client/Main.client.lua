--[[
	SPROUT VALLEY - client bootstrap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local Net = require(Shared.Net)

local Controllers = script.Parent:WaitForChild("Controllers")

-- The game has its own hotbar; hide the default backpack.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- VIP chat tag (TextChatService). Skipped quietly on the legacy chat.
pcall(function()
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		if sender and sender:GetAttribute("SV_VIP") then
			props.PrefixText = "<font color='#FF8CD2'>[VIP]</font> " .. message.PrefixText
		end
		return props
	end
end)

local ORDER = {
	"ClientState",
	"HudController",
	"HotbarController",
	"PlotController",
	"PanelsController",
	"StoreController",
	"EffectsController",
	"WeatherController",
}

for _, name in ipairs(ORDER) do
	local ok, err = pcall(function()
		require(Controllers[name]).init()
	end)
	if not ok then
		warn("[SproutValley] Failed to start " .. name .. ": " .. tostring(err))
	end
end

Net.event("RequestState"):FireServer()
