--[[
	Rocket Grandma Recliner (Brainrot, intensity 2) - planned for Stage 4.
	An original grandma character on a rocket-powered recliner overtakes the pack, knitting.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "RocketRecliner",
	name = "Rocket Grandma Recliner",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 10,
	warning = 3,
	tags = { "chase", "projectile" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "straight", "highway" },
	blocksLanes = 0,
	effects = { "knockback" },
	implemented = false,
	stage = 4,
	description = "An original grandma character on a rocket-powered recliner overtakes the pack, knitting.",
})
