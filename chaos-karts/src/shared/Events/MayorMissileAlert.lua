--[[
	The Mayor's Missile Alert (Disaster, intensity 3) - planned for Stage 5.
	The (fictional) Mayor of Chaos City interrupts every screen with an emergency broadcast, then cartoon missiles rain on marked circles all over the track.
	Catalog entry only: implemented = false, so the Event Director never picks it. To build
	it, follow README "How to add an event" (QuackaroniParade.lua is the reference).
	IP note: see docs/IP-CHECK.md (real meme names only where no owner was found).
]]

local EventBase = require(script.Parent.EventBase)

return EventBase.stub({
	id = "MayorMissileAlert",
	name = "The Mayor's Missile Alert",
	category = "Disaster",
	intensity = 3,
	weight = 4,
	duration = 16,
	warning = 6,
	tags = { "track-wide", "projectile", "screen-effect" },
	conflictsWith = { "BombardiroCrocodilo", "MegaBomb" },
	minLap = 2,
	finalLapBoost = 1.8,
	zoneTags = { "global" },
	blocksLanes = 0,
	effects = { "launch" },
	implemented = false,
	stage = 5,
	description = "The (fictional) Mayor of Chaos City interrupts every screen with an emergency broadcast, then cartoon missiles rain on marked circles all over the track.",
})
