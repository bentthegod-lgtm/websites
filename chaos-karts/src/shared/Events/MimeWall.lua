--[[
	Invisible Mime Wall (Brainrot, intensity 1) - planned for Stage 4.
	A mime builds an invisible wall across one lane. You can only see it shimmer.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "MimeWall",
	name = "Invisible Mime Wall",
	category = "Brainrot",
	intensity = 1,
	weight = 7,
	duration = 8,
	warning = 3,
	tags = { "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.3,
	zoneTags = { "straight", "bridge" },
	blocksLanes = 1,
	effects = { "knockback" },
	implemented = false,
	stage = 4,
	description = "A mime builds an invisible wall across one lane. You can only see it shimmer.",
})
