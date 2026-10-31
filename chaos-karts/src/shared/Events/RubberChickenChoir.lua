--[[
	Rubber Chicken Choir (Brainrot, intensity 1) - planned for Stage 4.
	A choir of rubber chickens squawks a song; the screen wobbles in rhythm.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "RubberChickenChoir",
	name = "Rubber Chicken Choir",
	category = "Brainrot",
	intensity = 1,
	weight = 8,
	duration = 10,
	warning = 2,
	tags = { "screen-effect", "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.2,
	zoneTags = { "stadium", "plaza" },
	blocksLanes = 0,
	effects = {},
	implemented = false,
	stage = 4,
	description = "A choir of rubber chickens squawks a song; the screen wobbles in rhythm.",
})
