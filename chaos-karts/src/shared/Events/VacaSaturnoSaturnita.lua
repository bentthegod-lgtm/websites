--[[
	La Vaca Saturno Saturnita (Brainrot, intensity 2) - planned for Stage 5.
	The Saturn-cow floats overhead and her rings make low gravity: every jump flies much higher and floatier.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "VacaSaturnoSaturnita",
	name = "La Vaca Saturno Saturnita",
	category = "Brainrot",
	intensity = 2,
	weight = 5,
	duration = 14,
	warning = 4,
	tags = { "sky", "track-wide" },
	conflictsWith = {},
	minLap = 2,
	finalLapBoost = 1.5,
	zoneTags = { "global" },
	blocksLanes = 0,
	effects = { "launch" },
	implemented = false,
	stage = 5,
	description = "The Saturn-cow floats overhead and her rings make low gravity: every jump flies much higher and floatier.",
})
