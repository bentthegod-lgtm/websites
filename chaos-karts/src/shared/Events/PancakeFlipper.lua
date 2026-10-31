--[[
	Pancake Flipper (Brainrot, intensity 3) - planned for Stage 4.
	A giant spatula slaps the road and flips every kart on a pancake-shaped patch.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "PancakeFlipper",
	name = "Pancake Flipper",
	category = "Brainrot",
	intensity = 3,
	weight = 4,
	duration = 10,
	warning = 4,
	tags = { "area", "blocks-lane" },
	conflictsWith = {},
	minLap = 2,
	finalLapBoost = 1.6,
	zoneTags = { "straight", "plaza" },
	blocksLanes = 2,
	effects = { "launch" },
	implemented = false,
	stage = 4,
	description = "A giant spatula slaps the road and flips every kart on a pancake-shaped patch.",
})
