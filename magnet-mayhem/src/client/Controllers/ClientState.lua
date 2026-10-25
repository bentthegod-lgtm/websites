--[[
	ClientState - the client's copy of server state plus signals other controllers listen
	to. Only the server's snapshots are trusted for display; the client never computes
	rewards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local ClientState = {}

ClientState.profile = nil
ClientState.event = nil
ClientState.leaderboard = { value = {}, rare = {} }
ClientState.settings = nil -- local copy (applied instantly, saved to the server)

ClientState.ProfileChanged = Signal.new()
ClientState.SettingsChanged = Signal.new()
ClientState.Notified = Signal.new() -- (text, kind)
ClientState.Announced = Signal.new() -- (text, color)
ClientState.PopupRequested = Signal.new() -- (kind, data)
ClientState.EventChanged = Signal.new()
ClientState.LeaderboardChanged = Signal.new()
ClientState.Attracted = Signal.new() -- (batch, pulses)
ClientState.Collected = Signal.new() -- (batch)
ClientState.Released = Signal.new() -- (ids)
ClientState.Sold = Signal.new() -- (userId, amount, count, big)
ClientState.ZoneChanged = Signal.new() -- (zoneId)

ClientState.zone = ZoneConfig.StartZone

function ClientState.player()
	return Players.LocalPlayer
end

function ClientState.root()
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function ClientState.setting(key)
	local s = ClientState.settings or (ClientState.profile and ClientState.profile.settings)
	return s and s[key]
end

function ClientState.applySettings(changes)
	ClientState.settings = ClientState.settings or {}
	for k, v in pairs(changes) do
		ClientState.settings[k] = v
	end
	ClientState.SettingsChanged:Fire(ClientState.settings)
end

function ClientState.saveSettings()
	if ClientState.settings then
		Net.event("SaveSettings"):FireServer(ClientState.settings)
	end
end

function ClientState.init()
	local function on(name, fn)
		Net.event(name).OnClientEvent:Connect(fn)
	end
	on("Profile", function(snapshot)
		local first = ClientState.profile == nil
		snapshot.receivedAt = os.clock()
		ClientState.profile = snapshot
		if first or not ClientState.settings then
			ClientState.settings = table.clone(snapshot.settings or {})
			ClientState.SettingsChanged:Fire(ClientState.settings)
		end
		ClientState.ProfileChanged:Fire(snapshot)
	end)
	on("Notify", function(text, kind)
		ClientState.Notified:Fire(text, kind)
	end)
	on("Announce", function(text, color)
		ClientState.Announced:Fire(text, color)
	end)
	on("Popup", function(kind, data)
		ClientState.PopupRequested:Fire(kind, data)
	end)
	on("Event", function(view)
		ClientState.event = view
		ClientState.EventChanged:Fire(view)
	end)
	on("Leaderboard", function(rows)
		ClientState.leaderboard = rows or ClientState.leaderboard
		ClientState.LeaderboardChanged:Fire(ClientState.leaderboard)
	end)
	on("Attract", function(batch, pulses)
		ClientState.Attracted:Fire(batch or {}, pulses or {})
	end)
	on("Collected", function(batch)
		ClientState.Collected:Fire(batch or {})
	end)
	on("Released", function(ids)
		ClientState.Released:Fire(ids or {})
	end)
	on("SellFx", function(userId, amount, count, big)
		ClientState.Sold:Fire(userId, amount, count, big)
	end)
end

return ClientState
