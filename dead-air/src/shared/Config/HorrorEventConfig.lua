--[[
	Scripted scares. They are rare, spaced out and never fire during a chase.
	AlertsMonster = false means the event's audio never creates a gameplay noise event.
	Local events only appear for one player - teammates will not have seen them.
]]

return {
	FirstEventDelay = 50, -- seconds into a run
	CooldownMin = 45,
	CooldownMax = 110,
	CheckInterval = 5,

	Events = {
		LightsFail = {
			Weight = 3,
			Duration = { 3.5, 7 },
			RadiusCells = 1,
			AlertsMonster = false,
		},
		DistantFigure = {
			Weight = 3,
			Local = true,
			MinDistance = 45,
			MaxDistance = 130,
			VanishAfterSeen = 0.7,
			Lifetime = 7,
		},
		DoorSlam = {
			Weight = 2,
			MinDistance = 25,
			MaxDistance = 75,
			AlertsMonster = false,
		},
		DistantVocalization = {
			Weight = 2,
			MinDistance = 70,
			AlertsMonster = false,
		},
		FootstepsBehind = {
			Weight = 2,
			Local = true,
			Steps = 4,
		},
		PipeBurst = {
			Weight = 1,
			AlertsMonster = true, -- deliberately configured to draw the Listener nearby
			Noise = "PropKnock",
			MinDistance = 30,
			MaxDistance = 60,
		},
	},
}
