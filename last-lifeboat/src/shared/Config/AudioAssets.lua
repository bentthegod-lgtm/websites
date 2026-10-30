--[[
	AudioAssets - every sound slot in LAST LIFEBOAT.

	ID RULE: no audio IDs are invented. Every rbxassetid here is one the DEAD AIR project in
	this repo already uses (dead-air/src/shared/Config/AudioAssets.lua - Roblox's licensed
	partner libraries). A unit test enforces it. Several are STAND-INS re-pitched to fit a
	sinking ship (marked "stand-in"). Slots with Id = "" are empty on purpose: the code skips
	them until you add your own audio (see README "Sound").

	Fields: Id (or Layers = { { Id, Volume, Pitch, Delay } } played together), Volume, Pitch,
	Looped, Group (Effects / Ambient / Music / UI), MaxDistance / MinDistance (3D roll-off),
	Duration (one-shot lifetime), Fade (fade-out at the end).
]]

return {
	-- Sinking ------------------------------------------------------------------------------
	Brace = { Id = "rbxassetid://9119661709", Volume = 0.55, Pitch = 0.9, Duration = 2, Fade = 0.5 }, -- DEAD AIR "Alarm", short
	Horn = { Id = "rbxassetid://9119661709", Volume = 0.6, Pitch = 0.5, Duration = 2, Fade = 0.6 }, -- ship's horn: "Alarm" pitched way down (stand-in)
	Lurch = {
		-- the hull groaning and a deep impact ("PipeCreak" + "DistantImpact" + "DoorSlam", low)
		Volume = 0.8,
		Duration = 4,
		Fade = 1.5,
		Layers = {
			{ Id = "rbxassetid://9113134899", Volume = 1, Pitch = 0.55 },
			{ Id = "rbxassetid://9116892199", Volume = 0.8, Pitch = 0.5, Delay = 0.1 },
			{ Id = "rbxassetid://1837829565", Volume = 0.5, Pitch = 0.45 },
		},
	},
	ShipCreak = { Id = "rbxassetid://9116892199", Volume = 0.35, Pitch = 0.6, Group = "Ambient", Duration = 4, Fade = 1.5 }, -- random creaks between lurches
	ShipHum = { Id = "rbxassetid://9125446564", Volume = 0.18, Pitch = 0.5, Looped = true, Group = "Ambient" }, -- "VentilationLoop" low: the engines (stand-in)
	Waves = { Id = "", Volume = 0.3, Looped = true, Group = "Ambient" }, -- add your own sea / waves loop
	Seagulls = { Id = "", Volume = 0.25, Group = "Ambient" }, -- add your own (lobby ambience)

	-- Players ------------------------------------------------------------------------------
	Pickup = { Id = "rbxassetid://9116173869", Volume = 0.45, Group = "UI" },
	PickupRare = { Id = "rbxassetid://9116173869", Volume = 0.6, Pitch = 1.3, Group = "UI" },
	Legendary = { Id = "rbxassetid://1837953706", Volume = 0.45, Pitch = 1.2, Group = "Music", Duration = 3, Fade = 1 }, -- "EscapeSting" up: a legendary find
	Drop = { Id = "rbxassetid://9120851227", Volume = 0.5 }, -- "ItemDrop"
	Splash = { Id = "", Volume = 0.6, MaxDistance = 90 }, -- add your own splash
	Gasp = { Id = "", Volume = 0.5 }, -- add your own: surfacing for air
	LowOxygen = { Id = "rbxassetid://9043365842", Volume = 0.5, Looped = true }, -- "Heartbeat"
	Downed = { Id = "rbxassetid://9113134899", Volume = 0.6, Pitch = 0.7 }, -- "DistantImpact"
	Revive = { Id = "rbxassetid://9120098454", Volume = 0.6, Pitch = 1.3, Duration = 2.5, Fade = 1 }, -- breaker-pull hit, up
	Grapple = { Id = "rbxassetid://9116612715", Volume = 0.5, Pitch = 1.4, MaxDistance = 80 }, -- "CanClatter" up: the hook biting
	Flare = { Id = "rbxassetid://9117864897", Volume = 0.55, Pitch = 1.6, MaxDistance = 140, Duration = 3, Fade = 1 }, -- "FuelPour" hiss (stand-in)

	-- Obstacles and hazards ----------------------------------------------------------------
	Lever = { Id = "rbxassetid://9120098454", Volume = 0.6, MaxDistance = 80 }, -- breaker pull
	Bulkhead = { Id = "rbxassetid://9119631707", Volume = 0.8, MaxDistance = 120 }, -- "HeavyDoor"
	Valve = {
		Volume = 0.6,
		MaxDistance = 90,
		Layers = { { Id = "rbxassetid://9116892199", Volume = 0.7, Pitch = 1.5 }, { Id = "rbxassetid://9120103996", Volume = 0.5 } },
	}, -- "PipeCreak" up + "FuseInsert" clunk
	SteamHiss = { Id = "rbxassetid://9117864897", Volume = 0.6, Pitch = 1.8, MaxDistance = 70, Duration = 2, Fade = 0.6 }, -- "FuelPour" up into a hiss (stand-in)
	SteamBurst = { Id = "rbxassetid://9117864897", Volume = 0.9, Pitch = 1.2, MaxDistance = 90, Duration = 1.6, Fade = 0.5 },
	Spark = { Id = "rbxassetid://9112823813", Volume = 0.6, Pitch = 1.8, MaxDistance = 50, Duration = 0.6 }, -- "FluorescentBuzz", short and high
	ChandelierFall = {
		Volume = 0.9,
		MaxDistance = 140,
		Layers = { { Id = "rbxassetid://9114591515", Volume = 1 }, { Id = "rbxassetid://9116537007", Volume = 0.8, Pitch = 0.7, Delay = 0.05 } },
	}, -- "GlassBreak" + "MetalDrop"
	PropSlide = { Id = "rbxassetid://9116612715", Volume = 0.35, Pitch = 0.6, MaxDistance = 60 }, -- "CanClatter" low

	-- Lifeboat -----------------------------------------------------------------------------
	Winch = { Id = "rbxassetid://9116892199", Volume = 0.6, Pitch = 1.2, MaxDistance = 160, Duration = 4, Fade = 1 }, -- davits lowering (stand-in)
	Oars = { Id = "", Volume = 0.4, MaxDistance = 120 }, -- add your own oar splashes

	-- Music / round ------------------------------------------------------------------------
	LobbyMusic = { Id = "rbxassetid://134959834418523", Volume = 0.3, Looped = true, Group = "Music" },
	RoundMusic = { Id = "rbxassetid://9043359885", Volume = 0.3, Looped = true, Group = "Music" }, -- "TensionLayer"
	FinalMinute = { Id = "rbxassetid://80586845389169", Volume = 0.35, Looped = true, Group = "Music" }, -- "ChaseLayer": the last 60 s
	Countdown = { Id = "rbxassetid://9113880475", Volume = 0.5, Group = "UI" }, -- "TerminalBeep"
	UIClick = { Id = "rbxassetid://9113880475", Volume = 0.25, Pitch = 1.4, Group = "UI" },
	Coins = { Id = "rbxassetid://9116173869", Volume = 0.4, Pitch = 1.5, Group = "UI" },
	Escape = { Id = "rbxassetid://1837953706", Volume = 0.6, Group = "Music" }, -- "EscapeSting"
	LostAtSea = { Id = "rbxassetid://9043338697", Volume = 0.6, Group = "Music" }, -- "FailSting"
}
