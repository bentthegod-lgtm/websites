--[[
	Fridge Squadron (Brainrot, intensity 2) - planned for Stage 4.
	A squadron of flying fridges dive-bombs the highway, doors flapping.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "FridgeSquadron",
	name = "Fridge Squadron",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 10,
	warning = 3,
	tags = { "sky", "projectile" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "sky", "highway" },
	blocksLanes = 0,
	effects = { "launch" },
	implemented = false,
	stage = 4,
	description = "A squadron of flying fridges dive-bombs the highway, doors flapping.",
})
