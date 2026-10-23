--[[
	ClientState - the client's view of the game, fed only by server remotes and replicated
	attributes. Controllers read from here and subscribe to its signals.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local ClientState = {
	roundState = "Lobby",
	roundData = {},
	party = { members = {} },
	objective = nil,
	inventory = {},
	profile = nil,
	results = nil,
	selectedSlot = 1,

	RoundChanged = Signal.new(),
	PartyChanged = Signal.new(),
	ObjectiveChanged = Signal.new(),
	InventoryChanged = Signal.new(),
	ProfileChanged = Signal.new(),
	ResultsReceived = Signal.new(),
	Notified = Signal.new(),
	NoiseFeedback = Signal.new(),
	HorrorEvent = Signal.new(),
	MonsterCue = Signal.new(),
	WorldSound = Signal.new(),
	LoreReceived = Signal.new(),
	SlotChanged = Signal.new(),
}

local player = Players.LocalPlayer

function ClientState.status()
	return player:GetAttribute("DA_Status") or "Lobby"
end

function ClientState.inRun()
	local status = ClientState.status()
	return status == "Alive" or status == "Downed" or status == "Dead" or status == "Escaped"
end

function ClientState.monster()
	return workspace:FindFirstChild("TheListener")
end

function ClientState.setSlot(slot)
	local count = #ClientState.inventory
	if count == 0 then
		ClientState.selectedSlot = 1
	else
		ClientState.selectedSlot = ((slot - 1) % count) + 1
	end
	ClientState.SlotChanged:Fire(ClientState.selectedSlot)
end

function ClientState.init()
	Net.event("RoundState").OnClientEvent:Connect(function(state, data)
		ClientState.roundState = state
		ClientState.roundData = data or {}
		ClientState.RoundChanged:Fire(state, data or {})
	end)
	Net.event("Party").OnClientEvent:Connect(function(party)
		ClientState.party = party
		ClientState.PartyChanged:Fire(party)
	end)
	Net.event("Objective").OnClientEvent:Connect(function(snapshot)
		ClientState.objective = snapshot
		if snapshot and snapshot.extraction and snapshot.extraction.endsAt then
			snapshot.extraction.localEndsAt = os.clock() + snapshot.extraction.endsAt
		end
		ClientState.ObjectiveChanged:Fire(snapshot)
	end)
	Net.event("Inventory").OnClientEvent:Connect(function(items)
		ClientState.inventory = items or {}
		ClientState.setSlot(ClientState.selectedSlot)
		ClientState.InventoryChanged:Fire(ClientState.inventory)
	end)
	Net.event("Profile").OnClientEvent:Connect(function(profile)
		ClientState.profile = profile
		ClientState.ProfileChanged:Fire(profile)
	end)
	Net.event("Results").OnClientEvent:Connect(function(results)
		ClientState.results = results
		ClientState.ResultsReceived:Fire(results)
	end)
	Net.event("Notify").OnClientEvent:Connect(function(text, kind)
		ClientState.Notified:Fire(text, kind)
	end)
	Net.event("NoiseFeedback").OnClientEvent:Connect(function(level)
		ClientState.NoiseFeedback:Fire(level)
	end)
	Net.event("HorrorEvent").OnClientEvent:Connect(function(name, data)
		ClientState.HorrorEvent:Fire(name, data or {})
	end)
	Net.event("MonsterCue").OnClientEvent:Connect(function(cue, data)
		ClientState.MonsterCue:Fire(cue, data or {})
	end)
	Net.event("WorldSound").OnClientEvent:Connect(function(key, position, scale)
		ClientState.WorldSound:Fire(key, position, scale)
	end)
	Net.event("Lore").OnClientEvent:Connect(function(note)
		ClientState.LoreReceived:Fire(note)
	end)
end

return ClientState
