--[[
	ClientState - the client's copy of server state plus signals other controllers listen
	to. Only the server's snapshots are trusted for display; the client never computes
	scores or rewards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local ClientState = {}

ClientState.profile = nil
ClientState.pads = {}
ClientState.leaderboard = { score = {}, distance = {} }
ClientState.settings = nil -- local copy (applied instantly, saved to the server)
ClientState.myRun = nil -- { padIndex, model, featuredId, startedAt }
ClientState.duel = nil

ClientState.ProfileChanged = Signal.new()
ClientState.SettingsChanged = Signal.new()
ClientState.PadsChanged = Signal.new()
ClientState.Notified = Signal.new() -- (text, kind)
ClientState.Announced = Signal.new() -- (text, color)
ClientState.PopupRequested = Signal.new() -- (kind, data)
ClientState.LeaderboardChanged = Signal.new()
ClientState.MachineFx = Signal.new() -- (padIndex, machineId, phase, data)
ClientState.RunStarted = Signal.new() -- (userId, padIndex, model, featuredId)
ClientState.RunEvent = Signal.new() -- (userId, kind, data)
ClientState.RunEnded = Signal.new() -- (userId, summary)
ClientState.Results = Signal.new() -- (breakdown)
ClientState.DuelChanged = Signal.new()

function ClientState.player()
	return Players.LocalPlayer
end

function ClientState.root()
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function ClientState.myPad()
	local player = Players.LocalPlayer
	for _, pad in ipairs(ClientState.pads) do
		if pad.userId == player.UserId then
			return pad
		end
	end
	return nil
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
	local player = Players.LocalPlayer
	local function on(name, fn)
		Net.event(name).OnClientEvent:Connect(fn)
	end
	on("Profile", function(snapshot)
		local first = ClientState.profile == nil
		ClientState.profile = snapshot
		if first or not ClientState.settings then
			ClientState.settings = table.clone(snapshot.settings or {})
			ClientState.SettingsChanged:Fire(ClientState.settings)
		end
		ClientState.ProfileChanged:Fire(snapshot)
	end)
	on("PadState", function(pads)
		ClientState.pads = pads or {}
		ClientState.PadsChanged:Fire(ClientState.pads)
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
	on("Leaderboard", function(rows)
		ClientState.leaderboard = rows or ClientState.leaderboard
		ClientState.LeaderboardChanged:Fire(ClientState.leaderboard)
	end)
	on("MachineFx", function(padIndex, machineId, phase, data)
		ClientState.MachineFx:Fire(padIndex, machineId, phase, data or {})
	end)
	on("RunStarted", function(userId, padIndex, model, featuredId)
		if userId == player.UserId then
			ClientState.myRun = { padIndex = padIndex, model = model, featuredId = featuredId, startedAt = os.clock() }
		end
		ClientState.RunStarted:Fire(userId, padIndex, model, featuredId)
	end)
	on("RunEvent", function(userId, kind, data)
		ClientState.RunEvent:Fire(userId, kind, data or {})
	end)
	on("RunEnded", function(userId, summary)
		if userId == player.UserId then
			ClientState.myRun = nil
		end
		ClientState.RunEnded:Fire(userId, summary or {})
	end)
	on("Results", function(breakdown)
		ClientState.Results:Fire(breakdown)
	end)
	on("DuelState", function(state)
		ClientState.duel = state
		ClientState.DuelChanged:Fire(state)
	end)
end

return ClientState
