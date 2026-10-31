--[[
	Jelly Cube Avalanche (Brainrot, intensity 2) - planned for Stage 4.
	Wobbly jelly cubes tumble into a corner; driving through them is like driving through jam.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "JellyAvalanche",
	name = "Jelly Cube Avalanche",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 10,
	warning = 4,
	tags = { "blocks-lane", "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "hairpin", "turn" },
	blocksLanes = 1,
	effects = { "slow" },
	implemented = false,
	stage = 4,
	description = "Wobbly jelly cubes tumble into a corner; driving through them is like driving through jam.",
})
