--[[
	ClientState - the client's copy of server state, plus signals other controllers use.
	Remotes are only listened to here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local ClientState = {
	profile = nil,
	tick = nil,
	events = nil,
	eventsReceivedAt = 0,
	carry = nil,
	carryReceivedAt = 0,
}

ClientState.ProfileChanged = Signal.new()
ClientState.TickChanged = Signal.new()
ClientState.EventsChanged = Signal.new()
ClientState.CarryChanged = Signal.new()
ClientState.Feed = Signal.new() -- (text, color, chat)
ClientState.Notify = Signal.new() -- (text, kind)
ClientState.Popup = Signal.new() -- (kind, data)
ClientState.Alarm = Signal.new() -- (thiefName, blobbyName)
ClientState.Sfx = Signal.new() -- (key, position?)
ClientState.Knockback = Signal.new() -- (velocity)
ClientState.SlapFx = Signal.new() -- (from, to, hit)

function ClientState.init()
	Net.event("Profile").OnClientEvent:Connect(function(profile)
		ClientState.profile = profile
		ClientState.ProfileChanged:Fire(profile)
	end)
	Net.event("Tick").OnClientEvent:Connect(function(tick)
		ClientState.tick = tick
		if ClientState.profile then
			ClientState.profile.cash = tick.cash
			ClientState.profile.ips = tick.ips
		end
		ClientState.TickChanged:Fire(tick)
	end)
	Net.event("Events").OnClientEvent:Connect(function(events)
		ClientState.events = events
		ClientState.eventsReceivedAt = os.clock()
		ClientState.EventsChanged:Fire(events)
	end)
	Net.event("Carry").OnClientEvent:Connect(function(info)
		ClientState.carry = info
		ClientState.carryReceivedAt = os.clock()
		ClientState.CarryChanged:Fire(info)
	end)
	Net.event("Feed").OnClientEvent:Connect(function(...)
		ClientState.Feed:Fire(...)
	end)
	Net.event("Notify").OnClientEvent:Connect(function(...)
		ClientState.Notify:Fire(...)
	end)
	Net.event("Popup").OnClientEvent:Connect(function(...)
		ClientState.Popup:Fire(...)
	end)
	Net.event("Alarm").OnClientEvent:Connect(function(...)
		ClientState.Alarm:Fire(...)
	end)
	Net.event("Sfx").OnClientEvent:Connect(function(...)
		ClientState.Sfx:Fire(...)
	end)
	Net.event("Knockback").OnClientEvent:Connect(function(...)
		ClientState.Knockback:Fire(...)
	end)
	Net.event("SlapFx").OnClientEvent:Connect(function(...)
		ClientState.SlapFx:Fire(...)
	end)
end

-- Seconds left on something the server reported `remaining` for, `at` os.clock() ago.
function ClientState.countdown(remaining, at)
	return math.max(0, (remaining or 0) - (os.clock() - (at or os.clock())))
end

return ClientState
