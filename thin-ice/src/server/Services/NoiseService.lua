--[[
	NoiseService - every sound that matters to the Antlered goes through emit():
	footsteps, cracking ice, splashes, chipping cores, snowballs, deliveries and thaws.

	The monster gets the raw position and category (MonsterService scales it by distance,
	difficulty and weather). Clients get the loud ones as WorldSound so they can play the
	sound in 3D - footsteps are played locally by each client instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)

local NoiseService = {}

local services
local LOCAL_ONLY = { StepSneak = true, StepWalk = true, StepSprint = true }

NoiseService.log = {}

function NoiseService.init(registry)
	services = registry
end

-- source: the player who made it (nil for a thrown snowball - that's the point of a lure)
function NoiseService.emit(category, position, source)
	if not GameConfig.Noise.Categories[category] or typeof(position) ~= "Vector3" then
		return
	end
	table.insert(NoiseService.log, { category = category, position = position, source = source, at = os.clock() })
	if #NoiseService.log > 60 then
		table.remove(NoiseService.log, 1)
	end
	if not LOCAL_ONLY[category] then
		services.Remotes.WorldSound:FireAllClients(category, position)
	end
	if services.MonsterService then
		services.MonsterService.hear(category, position, source)
	end
end

function NoiseService.count(category)
	local n = 0
	for _, entry in ipairs(NoiseService.log) do
		if entry.category == category then
			n += 1
		end
	end
	return n
end

return NoiseService
