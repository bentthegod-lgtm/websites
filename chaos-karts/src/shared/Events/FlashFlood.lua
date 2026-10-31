--[[
	Flash Flood (Disaster, intensity 3) - planned for Stage 5.
	The river bursts its banks: water floods one side of the tunnel or bridge.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "FlashFlood",
	name = "Flash Flood",
	category = "Disaster",
	intensity = 3,
	weight = 3,
	duration = 14,
	warning = 5,
	tags = { "area", "blocks-lane" },
	conflictsWith = { "BubbleBathFlood", "FreakBlizzard" },
	minLap = 3,
	finalLapBoost = 2.0,
	zoneTags = { "tunnel", "river", "bridge" },
	blocksLanes = 1,
	effects = { "slow" },
	implemented = false,
	stage = 5,
	description = "The river bursts its banks: water floods one side of the tunnel or bridge.",
})
