--[[
	Audio slots.

	NO audio IDs are invented here. The rbxassetid:// values below are reused from the
	DEAD AIR project (Roblox licensed partner library sounds that are free to use in
	experiences). Every slot with Id = "" is skipped by the code until you add an asset
	you own or that the Creator Store marks as usable, e.g. "rbxassetid://123456789".
	See README "Audio" and POLISH.md for what each empty slot should sound like.
]]

return {
	-- UI
	Click = { Id = "rbxassetid://9113880475", Volume = 0.35, Pitch = 1.4 }, -- TerminalBeep, pitched up
	Purchase = { Id = "rbxassetid://9113880475", Volume = 0.55, Pitch = 1.0 }, -- TerminalBeep
	Error = { Id = "rbxassetid://9113880475", Volume = 0.4, Pitch = 0.55 },
	Reward = { Id = "rbxassetid://1837953706", Volume = 0.5 }, -- EscapeSting (short positive sting)

	-- Economy
	CollectCash = { Id = "rbxassetid://9116173869", Volume = 0.5, Pitch = 1.25 }, -- Pickup
	Coin = { Id = "rbxassetid://9116173869", Volume = 0.35, Pitch = 1.6 },
	BuyBlobby = { Id = "rbxassetid://9113722650", Volume = 0.55 }, -- CardSwipe

	-- Stealing
	StealGrab = { Id = "rbxassetid://9120851227", Volume = 0.6, Pitch = 1.2 }, -- ItemDrop
	StealAlarm = { Id = "rbxassetid://9119661709", Volume = 0.6, Duration = 2.5 }, -- Alarm (cut short)
	StealSuccess = { Id = "rbxassetid://1837953706", Volume = 0.6, Pitch = 1.1 },
	Slap = { Id = "rbxassetid://9116612715", Volume = 0.8, Pitch = 1.3 }, -- CanClatter
	Drop = { Id = "rbxassetid://9116537007", Volume = 0.5, Pitch = 1.4 }, -- MetalDrop

	-- Base
	LockOn = { Id = "rbxassetid://9119631707", Volume = 0.6, Pitch = 1.2 }, -- HeavyDoor
	LockOff = { Id = "rbxassetid://9120839599", Volume = 0.5 }, -- DoorOpen
	LaserZap = { Id = "rbxassetid://9114591515", Volume = 0.5, Pitch = 1.6 }, -- GlassBreak, pitched up

	-- Events / bragging
	EventStart = { Id = "rbxassetid://9114533169", Volume = 0.7 }, -- ElevatorArrive (ding)
	RareSpawn = { Id = "rbxassetid://9113087803", Volume = 0.35, Pitch = 1.3, Duration = 1.5 }, -- AlarmClockRing, short
	Rebirth = { Id = "rbxassetid://1837953706", Volume = 0.8, Pitch = 0.9 },

	-- Add your own: upbeat lobby / tycoon music loop (2D).
	Music = { Id = "", Volume = 0.3, Looped = true },
	-- Add your own: a cute squeak for Blobbies arriving on a pedestal.
	BlobbySqueak = { Id = "", Volume = 0.5 },
}
