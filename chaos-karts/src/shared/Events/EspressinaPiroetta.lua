--[[
	Espressina Piroetta (Brainrot, intensity 2) - planned for Stage 4.
	A teacup-headed ballerina (parody, own design) pirouettes down the road; touch her twirl and you spin out.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "EspressinaPiroetta",
	name = "Espressina Piroetta",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 10,
	warning = 3,
	tags = { "area", "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.5,
	zoneTags = { "plaza", "straight" },
	blocksLanes = 1,
	effects = { "spinOut" },
	implemented = false,
	stage = 4,
	description = "A teacup-headed ballerina (parody, own design) pirouettes down the road; touch her twirl and you spin out.",
})
