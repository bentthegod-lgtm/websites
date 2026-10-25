--[[
	ClientState - the client's view of the game, fed only by server remotes and replicated
	attributes. Controllers read from here and subscribe to its signals.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local ClientState = {
	profile = nil,
	roundState = "Hallway",
	roundData = {},
	phase = nil,
	suspicion = 0,
	mark = "",
	pending = 0,
	phone = nil, -- PhoneState payload
	quiz = nil,
	test = nil, -- { version, questions = { { slot, subject, tier, text, options } }, answers, ripped }

	ProfileChanged = Signal.new(),
	RoundChanged = Signal.new(),
	PhaseChanged = Signal.new(),
	SuspicionChanged = Signal.new(),
	PhoneChanged = Signal.new(),
	PhoneResult = Signal.new(),
	QuizChanged = Signal.new(),
	TestChanged = Signal.new(), -- (kind, test)
	AnswersRevealed = Signal.new(), -- (all revealed { slot, option }, source)
	QuizResult = Signal.new(),
	Chat = Signal.new(),
	Results = Signal.new(),
	CrateResult = Signal.new(),
	CodeResult = Signal.new(),
	Notified = Signal.new(),
	Announced = Signal.new(),
	Effect = Signal.new(),
	-- Local-only: the phone is (requested) out, for instant camera feedback.
	LocalPhone = Signal.new(),
}

local player = Players.LocalPlayer

function ClientState.status()
	return player:GetAttribute("PA_Status") or "Hallway"
end

function ClientState.desk()
	return player:GetAttribute("PA_Desk") or 0
end

-- Players by desk index, from replicated attributes.
function ClientState.deskOccupants()
	local map = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local desk = p:GetAttribute("PA_Desk")
		local status = p:GetAttribute("PA_Status")
		if type(desk) == "number" and desk > 0 and status ~= "Hallway" then
			map[desk] = p
		end
	end
	return map
end

function ClientState.init()
	Net.event("Profile").OnClientEvent:Connect(function(profile)
		ClientState.profile = profile
		ClientState.ProfileChanged:Fire(profile)
	end)
	Net.event("RoundState").OnClientEvent:Connect(function(state, data)
		ClientState.roundState = state
		ClientState.roundData = data or {}
		if state ~= "Class" then
			ClientState.phase = nil
		end
		ClientState.RoundChanged:Fire(state, data or {})
	end)
	Net.event("PhaseChanged").OnClientEvent:Connect(function(data)
		ClientState.phase = data
		ClientState.PhaseChanged:Fire(data)
	end)
	Net.event("Suspicion").OnClientEvent:Connect(function(value, mark, pending)
		ClientState.suspicion = tonumber(value) or 0
		ClientState.mark = mark or ""
		ClientState.pending = tonumber(pending) or 0
		ClientState.SuspicionChanged:Fire(ClientState.suspicion, ClientState.mark, ClientState.pending)
	end)
	Net.event("PhoneState").OnClientEvent:Connect(function(data)
		ClientState.phone = data
		ClientState.PhoneChanged:Fire(data)
	end)
	Net.event("PhoneResult").OnClientEvent:Connect(function(kind, data)
		if ClientState.phone and data and data.view then
			ClientState.phone.view = data.view
		end
		ClientState.PhoneResult:Fire(kind, data or {})
	end)
	Net.event("Test").OnClientEvent:Connect(function(kind, data)
		if kind == "view" then
			ClientState.test = data
			if data then
				data.answers = data.answers or {}
			end
		elseif kind == "ack" and ClientState.test and data then
			ClientState.test.answers[data.slot] = data.option
		elseif kind == "ripped" and ClientState.test then
			ClientState.test.ripped = true
			ClientState.test.answers = {}
		elseif kind == "clear" then
			ClientState.test = nil
		end
		ClientState.TestChanged:Fire(kind, ClientState.test)
	end)
	Net.event("Quiz").OnClientEvent:Connect(function(data)
		ClientState.quiz = data
		ClientState.QuizChanged:Fire(data)
	end)
	local simple = {
		QuizResult = "QuizResult",
		Chat = "Chat",
		Results = "Results",
		CrateResult = "CrateResult",
		CodeResult = "CodeResult",
		Notify = "Notified",
		Announce = "Announced",
		Effect = "Effect",
	}
	for remote, signalName in pairs(simple) do
		Net.event(remote).OnClientEvent:Connect(function(...)
			ClientState[signalName]:Fire(...)
		end)
	end
end

return ClientState
