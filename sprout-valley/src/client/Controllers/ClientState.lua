--[[
	ClientState - the client's view of the game, fed only by server remotes and replicated
	attributes. Controllers read from here and subscribe to its signals.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local ClientState = {
	profile = nil,
	stock = nil,
	leaderboard = {},
	tool = { kind = "none" },

	ProfileChanged = Signal.new(),
	StockChanged = Signal.new(),
	LeaderboardChanged = Signal.new(),
	Notified = Signal.new(),
	Announced = Signal.new(),
	EffectFired = Signal.new(),
	PanelRequested = Signal.new(),
	ToolChanged = Signal.new(),
	WindowChanged = Signal.new(),
}

local player = Players.LocalPlayer

function ClientState.serverNow()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.time()
end

function ClientState.myPlotId()
	return player:GetAttribute("SV_Plot")
end

function ClientState.setTool(tool)
	ClientState.tool = tool or { kind = "none" }
	ClientState.ToolChanged:Fire(ClientState.tool)
end

function ClientState.hasPass(key)
	local p = ClientState.profile
	return p ~= nil and p.passes ~= nil and p.passes[key] == true
end

function ClientState.init()
	Net.event("Profile").OnClientEvent:Connect(function(profile)
		ClientState.profile = profile
		ClientState.ProfileChanged:Fire(profile)
	end)
	Net.event("Stock").OnClientEvent:Connect(function(stock)
		ClientState.stock = stock
		ClientState.StockChanged:Fire(stock)
	end)
	Net.event("Leaderboard").OnClientEvent:Connect(function(rows)
		ClientState.leaderboard = rows or {}
		ClientState.LeaderboardChanged:Fire(ClientState.leaderboard)
	end)
	Net.event("Notify").OnClientEvent:Connect(function(text, kind)
		ClientState.Notified:Fire(text, kind)
	end)
	Net.event("Announce").OnClientEvent:Connect(function(text, color)
		ClientState.Announced:Fire(text, color)
	end)
	Net.event("Effect").OnClientEvent:Connect(function(kind, data)
		ClientState.EffectFired:Fire(kind, data or {})
	end)
	Net.event("OpenPanel").OnClientEvent:Connect(function(name)
		ClientState.PanelRequested:Fire(name)
	end)
end

return ClientState
