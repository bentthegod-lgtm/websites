--[[
	Audio references.

	NO asset IDs were invented. The rbxassetid:// entries below are reused from the DEAD AIR
	project's AudioAssets (Roblox licensed partner libraries found through the Creator Store),
	picked where they fit a school. Every other slot is Id = "" and is skipped by AudioUtil
	until you paste an asset you own or that is marked usable in the Creator Store.

	Gameplay never depends on sound: the teacher "hears" taps through the server's noise
	model, not through these files.
]]

return {
	-- Phone
	PhoneTap = { Id = "rbxassetid://9113880475", Volume = 0.25, Pitch = 1.5 }, -- dead-air TerminalBeep
	PhoneOut = { Id = "rbxassetid://9125756882", Volume = 0.35, Pitch = 1.4 }, -- dead-air DrawerOpen
	PhoneAway = { Id = "rbxassetid://9125757128", Volume = 0.35, Pitch = 1.5 }, -- dead-air DrawerClose
	CloutGain = { Id = "rbxassetid://9116173869", Volume = 0.3, Pitch = 1.3 }, -- dead-air Pickup
	SelfieShutter = { Id = "rbxassetid://9114480271", Volume = 0.6, Pitch = 1.4 }, -- reused click from DEAD AIR; swap for a real shutter
	Notification = { Id = "", Volume = 0.4 }, -- add your own message ping

	-- Classroom
	SchoolBell = { Id = "rbxassetid://9113087803", Volume = 0.6 }, -- dead-air AlarmClockRing
	FireAlarm = { Id = "rbxassetid://9119661709", Volume = 0.5, Looped = true }, -- dead-air Alarm
	DoorOpen = { Id = "rbxassetid://9120839599", Volume = 0.5 }, -- dead-air DoorOpen
	DoorClose = { Id = "rbxassetid://9119129301", Volume = 0.5 }, -- dead-air DoorClose
	Locker = { Id = "rbxassetid://9119633070", Volume = 0.5 }, -- dead-air Locker
	PlaneLand = { Id = "rbxassetid://9120851227", Volume = 0.5, Pitch = 1.6 }, -- dead-air ItemDrop
	MarkerSqueak = { Id = "", Volume = 0.25, Looped = true }, -- add your own whiteboard marker loop
	ClassMusic = { Id = "", Volume = 0.2, Looped = true }, -- add your own light comedy loop
	HallwayMusic = { Id = "", Volume = 0.25, Looped = true }, -- add your own lobby loop

	-- Stingers
	Caught = { Id = "rbxassetid://9043338697", Volume = 0.6 }, -- dead-air FailSting
	ClassOver = { Id = "rbxassetid://1837953706", Volume = 0.5 }, -- dead-air EscapeSting
	Suspicious = { Id = "", Volume = 0.5 }, -- add your own "huh?" sting
	Alert = { Id = "", Volume = 0.6 }, -- add your own "!" sting
	QuizSting = { Id = "", Volume = 0.6 },
	PizzaFanfare = { Id = "", Volume = 0.7 },
	LevelUp = { Id = "", Volume = 0.6 },
	Purchase = { Id = "rbxassetid://9113722650", Volume = 0.5 }, -- dead-air CardSwipe
	Click = { Id = "", Volume = 0.35 },
}
