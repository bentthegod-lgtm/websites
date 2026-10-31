--[[
	SpectateController - for players who aren't in the running race (late joiners): the
	camera follows one racer; Q / E (DPad left / right, or the HUD arrows) cycle through the
	field in race order. They're already queued for the next race.
]]

local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)

local SpectateController = {}

local index = 1

function SpectateController.targets()
	local list = {}
	for _, r in ipairs(ClientState.race and ClientState.race.racers or {}) do
		if not r.left then
			table.insert(list, r)
		end
	end
	table.sort(list, function(a, b)
		return (a.place or 99) < (b.place or 99)
	end)
	return list
end

function SpectateController.target()
	if not ClientState.spectating() then
		return nil
	end
	local list = SpectateController.targets()
	if #list == 0 then
		return nil
	end
	index = (index - 1) % #list + 1
	return list[index]
end

function SpectateController.cycle(step)
	local list = SpectateController.targets()
	if #list == 0 then
		return nil
	end
	index = (index - 1 + step) % #list + 1
	return list[index]
end

function SpectateController.init()
	InputController.spectateStep = SpectateController.cycle
	ClientState.RaceChanged:Connect(function(state, before)
		if state.phase == "Countdown" and before ~= "Countdown" then
			index = 1
		end
	end)
end

return SpectateController
