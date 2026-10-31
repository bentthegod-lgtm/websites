--[[
	Sock Puppet Siege (Brainrot, intensity 2) - planned for Stage 4.
	An army of googly-eyed sock puppets storms out of the stadium and blocks a lane.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "SockPuppetSiege",
	name = "Sock Puppet Siege",
	category = "Brainrot",
	intensity = 2,
	weight = 6,
	duration = 12,
	warning = 3,
	tags = { "area", "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.4,
	zoneTags = { "stadium", "plaza" },
	blocksLanes = 1,
	effects = { "knockback" },
	implemented = false,
	stage = 4,
	description = "An army of googly-eyed sock puppets storms out of the stadium and blocks a lane.",
})
