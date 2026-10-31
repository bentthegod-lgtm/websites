--[[
	Mega Burger Roll (Brainrot, intensity 2) - planned for Stage 4.
	A bus-sized burger rolls down one lane of a straight, cheese first. Get flipped if you don't dodge.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "MegaBurgerRoll",
	name = "Mega Burger Roll",
	category = "Brainrot",
	intensity = 2,
	weight = 7,
	duration = 10,
	warning = 3,
	tags = { "chase", "blocks-lane", "projectile" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "straight", "highway" },
	blocksLanes = 1,
	effects = { "launch" },
	implemented = false,
	stage = 4,
	description = "A bus-sized burger rolls down one lane of a straight, cheese first. Get flipped if you don't dodge.",
})
