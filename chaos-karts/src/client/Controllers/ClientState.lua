--[[
	ClientState - the client's copy of what the server says (profile, race, boards, kart
	snapshots) plus the signals the other controllers listen to. The client never decides
	race outcomes: it simulates only its own kart (prediction) and displays server state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local GameConfig = require(Shared.Config.GameConfig)
local MapData = require(Shared.MapData)

local ClientState = {}

ClientState.profile = nil
ClientState.race = { phase = "Lobby", queued = 0, players = 0, queueIds = {} }
ClientState.settings = nil
ClientState.leaderboard = { Wins = {}, BestLap = {} }
ClientState.lastResults = nil
ClientState.lastSnapshot = nil

ClientState.ProfileChanged = Signal.new()
ClientState.SettingsChanged = Signal.new()
ClientState.RaceChanged = Signal.new() -- (state, previousPhase)
ClientState.Notified = Signal.new() -- (text, kind)
ClientState.Announced = Signal.new() -- (text, color)
ClientState.ResultsReceived = Signal.new() -- (summary)
ClientState.LeaderboardChanged = Signal.new()
ClientState.MenuRequested = Signal.new() -- (tab)
ClientState.KartsSnapshot = Signal.new() -- (snapshot)
ClientState.KartCorrected = Signal.new() -- (cframe, vel, reason)
ClientState.KartRespawned = Signal.new() -- (cframe, ghost, reason)
ClientState.KartEffected = Signal.new() -- (kind, params, source)
ClientState.RaceEvent = Signal.new() -- (kind, info)
ClientState.EventStarted = Signal.new() -- (payload)
ClientState.EventStopped = Signal.new() -- (instanceId, reason)
ClientState.KartEvents = Signal.new() -- (list of physics events from my kart this frame)

function ClientState.player()
	return Players.LocalPlayer
end

function ClientState.serverNow()
	return workspace:GetServerTimeNow()
end

local mapCache = {}
function ClientState.mapData()
	local id = (ClientState.race and ClientState.race.map) or GameConfig.Race.Map
	if not mapCache[id] then
		mapCache[id] = MapData.compile(require(Shared.Maps[id]))
	end
	return mapCache[id]
end

function ClientState.phase()
	return ClientState.race and ClientState.race.phase or "Lobby"
end

-- My entry in the current race's racer list (nil if I'm not racing).
function ClientState.myRacer()
	local race = ClientState.race
	if not race or not race.racers then
		return nil
	end
	local id = "p" .. tostring(Players.LocalPlayer.UserId)
	for _, r in ipairs(race.racers) do
		if r.id == id and not r.left then
			return r
		end
	end
	return nil
end

function ClientState.racerById(id)
	local race = ClientState.race
	for _, r in ipairs(race and race.racers or {}) do
		if r.id == id then
			return r
		end
	end
	return nil
end

function ClientState.racing()
	local phase = ClientState.phase()
	return phase == "Countdown" or phase == "Racing"
end

function ClientState.inRace()
	return ClientState.racing() and ClientState.myRacer() ~= nil
end

function ClientState.spectating()
	return ClientState.racing() and ClientState.myRacer() == nil
end

function ClientState.queued()
	local race = ClientState.race
	return race ~= nil and race.queueIds ~= nil and race.queueIds[tostring(Players.LocalPlayer.UserId)] == true
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

local savePending = false
function ClientState.saveSettings()
	if not ClientState.settings or savePending then
		return
	end
	savePending = true
	task.delay(1.2, function()
		savePending = false
		if ClientState.settings then
			Net.event("SaveSettings"):FireServer(ClientState.settings)
		end
	end)
end

function ClientState.setRace(state)
	local before = ClientState.race and ClientState.race.phase
	ClientState.race = state or ClientState.race
	ClientState.RaceChanged:Fire(ClientState.race, before)
end

function ClientState.init()
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
	on("RaceState", ClientState.setRace)
	on("Karts", function(snapshot)
		ClientState.lastSnapshot = snapshot
		ClientState.KartsSnapshot:Fire(snapshot)
	end)
	on("KartCorrect", function(cf, vel, reason)
		ClientState.KartCorrected:Fire(cf, vel, reason)
	end)
	on("KartRespawn", function(cf, ghost, reason)
		ClientState.KartRespawned:Fire(cf, ghost, reason)
	end)
	on("KartEffect", function(kind, params, source)
		ClientState.KartEffected:Fire(kind, params, source)
	end)
	on("RaceEvent", function(kind, info)
		ClientState.RaceEvent:Fire(kind, info)
	end)
	on("Results", function(summary)
		ClientState.lastResults = summary
		ClientState.ResultsReceived:Fire(summary)
	end)
	on("EventStart", function(payload)
		ClientState.EventStarted:Fire(payload)
	end)
	on("EventStop", function(id, reason)
		ClientState.EventStopped:Fire(id, reason)
	end)
	on("Notify", function(text, kind)
		ClientState.Notified:Fire(text, kind)
	end)
	on("Announce", function(text, color)
		ClientState.Announced:Fire(text, color)
	end)
	on("Leaderboard", function(rows)
		ClientState.leaderboard = rows or { Wins = {}, BestLap = {} }
		ClientState.LeaderboardChanged:Fire(ClientState.leaderboard)
	end)
	on("OpenMenu", function(tab)
		ClientState.MenuRequested:Fire(tab)
	end)
end

return ClientState
