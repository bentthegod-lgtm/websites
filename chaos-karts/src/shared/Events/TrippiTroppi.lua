--[[
	Trippi Troppi (Brainrot, intensity 1) - planned for Stage 4.
	The shrimp-cat hops lane to lane like a pogo stick; land under it and you get bounced into the air.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "TrippiTroppi",
	name = "Trippi Troppi",
	category = "Brainrot",
	intensity = 1,
	weight = 8,
	duration = 10,
	warning = 3,
	tags = { "area" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.3,
	zoneTags = { "straight", "bridge" },
	blocksLanes = 0,
	effects = { "launch" },
	implemented = false,
	stage = 4,
	description = "The shrimp-cat hops lane to lane like a pogo stick; land under it and you get bounced into the air.",
})
