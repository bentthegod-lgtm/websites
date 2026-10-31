--[[
	Giant Meteor Shower (Disaster, intensity 3) - planned for Stage 5.
	Flaming meteors streak in with glowing landing markers; craters stay as bumps for the rest of the lap.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "MeteorShower",
	name = "Giant Meteor Shower",
	category = "Disaster",
	intensity = 3,
	weight = 4,
	duration = 16,
	warning = 5,
	tags = { "sky", "projectile", "area" },
	conflictsWith = { "MayorMissileAlert" },
	minLap = 2,
	finalLapBoost = 1.8,
	zoneTags = { "global" },
	blocksLanes = 0,
	effects = { "launch", "spinOut" },
	implemented = false,
	stage = 5,
	description = "Flaming meteors streak in with glowing landing markers; craters stay as bumps for the rest of the lap.",
})
