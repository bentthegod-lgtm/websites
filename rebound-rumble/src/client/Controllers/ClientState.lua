--[[
	ClientState - the client's view of the game, fed only by server remotes and
	replicated attributes. Controllers read from here and subscribe to its signals.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local ClientState = {
	matchState = "Lobby",
	matchData = {},
	roster = {},
	profile = nil,
	goals = {},
	ball = { active = false },

	MatchChanged = Signal.new(),
	RosterChanged = Signal.new(),
	ProfileChanged = Signal.new(),
	BallSynced = Signal.new(),
	BallEvent = Signal.new(),
	ParryResult = Signal.new(),
	AbilityFx = Signal.new(),
	Fx = Signal.new(),
	KillFeed = Signal.new(),
	Announce = Signal.new(),
	Results = Signal.new(),
	CrateResult = Signal.new(),
	CodeResult = Signal.new(),
	Notified = Signal.new(),
	GoalsChanged = Signal.new(),
	-- Local-only: the player pressed parry (for instant feedback before the server answers).
	LocalParry = Signal.new(),
}

local player = Players.LocalPlayer

function ClientState.status()
	return player:GetAttribute("RR_Status") or "Lobby"
end

function ClientState.myId()
	return "p" .. tostring(player.UserId)
end

function ClientState.entry(id)
	for _, c in ipairs(ClientState.roster) do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- The character / bot model for a contestant id.
function ClientState.modelFor(id)
	if type(id) ~= "string" then
		return nil
	end
	if id:sub(1, 1) == "p" then
		local userId = tonumber(id:sub(2))
		local p = userId and Players:GetPlayerByUserId(userId)
		return p and p.Character
	end
	local arena = workspace:FindFirstChild("Arena")
	local bots = arena and arena:FindFirstChild("Bots")
	if bots then
		for _, model in ipairs(bots:GetChildren()) do
			if model:GetAttribute("ContestantId") == id then
				return model
			end
		end
	end
	return nil
end

function ClientState.nameFor(id)
	local e = ClientState.entry(id)
	return e and e.name or "?"
end

function ClientState.init()
	Net.event("MatchState").OnClientEvent:Connect(function(state, data)
		ClientState.matchState = state
		ClientState.matchData = data or {}
		ClientState.MatchChanged:Fire(state, data or {})
	end)
	Net.event("Roster").OnClientEvent:Connect(function(roster)
		ClientState.roster = roster or {}
		ClientState.RosterChanged:Fire(ClientState.roster)
	end)
	Net.event("Profile").OnClientEvent:Connect(function(profile)
		ClientState.profile = profile
		ClientState.ProfileChanged:Fire(profile)
	end)
	Net.event("BallSync").OnClientEvent:Connect(function(snapshot)
		ClientState.ball = snapshot or { active = false }
		ClientState.BallSynced:Fire(ClientState.ball)
	end)
	local simple = {
		BallEvent = "BallEvent",
		ParryResult = "ParryResult",
		AbilityFx = "AbilityFx",
		Fx = "Fx",
		KillFeed = "KillFeed",
		Announce = "Announce",
		Results = "Results",
		CrateResult = "CrateResult",
		CodeResult = "CodeResult",
		Notify = "Notified",
	}
	for remote, signalName in pairs(simple) do
		Net.event(remote).OnClientEvent:Connect(function(...)
			ClientState[signalName]:Fire(...)
		end)
	end
	Net.event("Goals").OnClientEvent:Connect(function(goals)
		ClientState.goals = goals or {}
		ClientState.GoalsChanged:Fire(ClientState.goals)
	end)
end

return ClientState
