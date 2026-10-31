--[[
	MEGA BOMB (Disaster, intensity 3) - planned for Stage 5.
	A giant cartoon bomb with a ticking timer lands off-track; a huge candy-colored shockwave flashes the screen and launches everyone nearby (cartoon, no realistic nuke imagery).
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "MegaBomb",
	name = "MEGA BOMB",
	category = "Disaster",
	intensity = 3,
	weight = 3,
	duration = 14,
	warning = 7,
	tags = { "track-wide", "screen-effect", "area" },
	conflictsWith = { "MayorMissileAlert", "Gorgantor" },
	minLap = 3,
	finalLapBoost = 2.0,
	zoneTags = { "open", "park", "stadium" },
	blocksLanes = 0,
	effects = { "launch" },
	implemented = false,
	stage = 5,
	description = "A giant cartoon bomb with a ticking timer lands off-track; a huge candy-colored shockwave flashes the screen and launches everyone nearby (cartoon, no realistic nuke imagery).",
})
