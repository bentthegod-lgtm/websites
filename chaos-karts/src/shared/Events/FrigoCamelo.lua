--[[
	Frigo Camelo (Brainrot, intensity 2) - planned for Stage 4.
	The fridge-camel opens its door and blows icy breath across one lane; karts in the cloud freeze for a moment.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "FrigoCamelo",
	name = "Frigo Camelo",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "area", "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "straight", "highway" },
	blocksLanes = 1,
	effects = { "freeze" },
	implemented = false,
	stage = 4,
	description = "The fridge-camel opens its door and blows icy breath across one lane; karts in the cloud freeze for a moment.",
})
