--[[
	GORGANTOR (Fiction, intensity 3) - planned for Stage 5.
	Our own giant monster (classic monster-movie style, original design) rises behind downtown, stomps the road and roars; footprints launch karts.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "Gorgantor",
	name = "GORGANTOR",
	category = "Fiction",
	intensity = 3,
	weight = 4,
	duration = 16,
	warning = 5,
	tags = { "area", "sky", "blocks-lane", "chase" },
	conflictsWith = { "CityQuake" },
	minLap = 2,
	finalLapBoost = 1.8,
	zoneTags = { "downtown", "plaza" },
	blocksLanes = 1,
	effects = { "knockback", "launch" },
	implemented = false,
	stage = 5,
	description = "Our own giant monster (classic monster-movie style, original design) rises behind downtown, stomps the road and roars; footprints launch karts.",
})
