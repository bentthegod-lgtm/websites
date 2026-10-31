--[[
	Sofa Surf Stampede (Brainrot, intensity 2) - planned for Stage 4.
	A stampede of sofas surfs down the highway with lamps still attached.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "SofaStampede",
	name = "Sofa Surf Stampede",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 10,
	warning = 3,
	tags = { "chase", "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "straight", "highway" },
	blocksLanes = 1,
	effects = { "spinOut" },
	implemented = false,
	stage = 4,
	description = "A stampede of sofas surfs down the highway with lamps still attached.",
})
