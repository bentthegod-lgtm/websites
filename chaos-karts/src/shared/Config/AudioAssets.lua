--[[
	AudioAssets - every sound slot in CHAOS KARTS (events keep their own slots in their
	Events/<Id>.lua module).

	ID RULE: no audio IDs are invented. Every rbxassetid here already appears in DEAD AIR's
	or LAST LIFEBOAT's AudioAssets in this repo (Roblox's licensed libraries); a unit test
	enforces it. Some are STAND-INS re-pitched to fit a kart racer. Slots with Id = "" are
	empty on purpose: the code skips them until you add your own audio (README "Sound").

	Fields: Id (or Layers = { { Id, Volume, Pitch, Delay } }), Volume, Pitch, Looped, Group
	(Effects / Music / UI / Engine), MaxDistance, MinDistance, Duration, Fade.
]]

return {
	-- Your kart ---------------------------------------------------------------------------
	Engine = { Id = "", Volume = 0.35, Looped = true, Group = "Engine" }, -- add your own engine loop: pitch follows speed
	EngineRemote = { Id = "", Volume = 0.25, Looped = true, Group = "Engine", MaxDistance = 120 }, -- other karts' engines
	DriftSkid = { Id = "", Volume = 0.3, Looped = true, Group = "Effects" }, -- add your own tyre squeal loop
	MiniTurbo = { Id = "rbxassetid://9113880475", Volume = 0.45, Pitch = 1.6, Group = "Effects" }, -- "TerminalBeep" up: a spark level reached
	Boost = { Id = "rbxassetid://9117864897", Volume = 0.5, Pitch = 1.8, Duration = 1.4, Fade = 0.5 }, -- "FuelPour" up: a whoosh (stand-in)
	BoostPad = { Id = "rbxassetid://9117864897", Volume = 0.55, Pitch = 2.1, Duration = 1.2, Fade = 0.4 },
	Hop = { Id = "rbxassetid://9113473249", Volume = 0.25, Pitch = 1.6 }, -- "Land", up and soft
	Land = { Id = "rbxassetid://9113473249", Volume = 0.55, Pitch = 0.9 }, -- DEAD AIR "Land"
	WallHit = { Id = "rbxassetid://9116537007", Volume = 0.6, Pitch = 1.1, MaxDistance = 120 }, -- "MetalDrop"
	Bump = { Id = "rbxassetid://9116612715", Volume = 0.5, Pitch = 1.3 }, -- "CanClatter"
	Respawn = { Id = "rbxassetid://9114533169", Volume = 0.5, Pitch = 1.3 }, -- "ElevatorArrive" ding
	SpinOut = { Id = "rbxassetid://9116892199", Volume = 0.5, Pitch = 1.8, Duration = 1.2, Fade = 0.4 }, -- "PipeCreak" up (stand-in)
	Knockback = { Id = "rbxassetid://9113134899", Volume = 0.6, Pitch = 1.3 }, -- "DistantImpact"

	-- Race --------------------------------------------------------------------------------
	CountdownBeep = { Id = "rbxassetid://9113880475", Volume = 0.6, Group = "UI" }, -- "TerminalBeep"
	CountdownGo = { Id = "rbxassetid://9113880475", Volume = 0.8, Pitch = 1.5, Group = "UI" },
	StartBoost = { Id = "rbxassetid://9117864897", Volume = 0.6, Pitch = 2, Duration = 1.2, Fade = 0.4 },
	Lap = { Id = "rbxassetid://9114533169", Volume = 0.55, Group = "UI" }, -- "ElevatorArrive"
	FinalLap = { Id = "rbxassetid://9119661709", Volume = 0.45, Pitch = 1.4, Group = "UI", Duration = 1.6, Fade = 0.5 }, -- "Alarm", short and high
	Finish = { Id = "rbxassetid://1837953706", Volume = 0.6, Group = "Music" }, -- "EscapeSting"
	FinishLose = { Id = "rbxassetid://9043338697", Volume = 0.5, Group = "Music" }, -- "FailSting"
	WrongWay = { Id = "rbxassetid://9113880475", Volume = 0.4, Pitch = 0.7, Group = "UI" },
	Checkpoint = { Id = "", Volume = 0.3, Group = "UI" }, -- add your own soft tick
	Crowd = { Id = "", Volume = 0.3, Looped = true, MaxDistance = 260 }, -- stadium crowd loop: add your own

	-- Music -------------------------------------------------------------------------------
	LobbyMusic = { Id = "rbxassetid://134959834418523", Volume = 0.3, Looped = true, Group = "Music" },
	RaceMusic = { Id = "rbxassetid://80586845389169", Volume = 0.28, Looped = true, Group = "Music" }, -- "ChaseLayer" (stand-in: add an upbeat racing track)
	FinalLapMusic = { Id = "rbxassetid://9043359885", Volume = 0.32, Looped = true, Group = "Music" }, -- "TensionLayer" (stand-in)

	-- UI ----------------------------------------------------------------------------------
	UIClick = { Id = "rbxassetid://9113880475", Volume = 0.25, Pitch = 1.4, Group = "UI" },
	Coins = { Id = "rbxassetid://9116173869", Volume = 0.4, Pitch = 1.5, Group = "UI" }, -- "Pickup"
	LevelUp = { Id = "rbxassetid://1837953706", Volume = 0.5, Pitch = 1.2, Group = "UI", Duration = 3, Fade = 1 },
	EventWarning = { Id = "rbxassetid://9119661709", Volume = 0.35, Pitch = 1.2, Group = "UI", Duration = 1.5, Fade = 0.5 },
	ItemRoll = { Id = "", Volume = 0.4, Group = "UI" }, -- Stage 3: item roulette tick
}
