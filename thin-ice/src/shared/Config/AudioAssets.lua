--[[
	AudioAssets - every sound slot. No audio IDs are invented: the filled slots reuse IDs
	that the DEAD AIR project in this repo already uses (re-pitched where it helps). Empty
	slots (Id = "") are skipped by the AudioController - add your own Creator Store audio.
]]

return {
	-- Footsteps / ice
	Step = { Id = "rbxassetid://9113473249", Volume = 0.25, Pitch = 1.4 },
	Crack = { Id = "rbxassetid://9116892199", Volume = 0.7, Pitch = 1.6, MaxDistance = 90 },
	Splash = { Id = "rbxassetid://9114591515", Volume = 0.6, Pitch = 0.6, MaxDistance = 120 },
	Chip = { Id = "rbxassetid://9116537007", Volume = 0.6, Pitch = 1.8, MaxDistance = 90 },
	Snowball = { Id = "rbxassetid://9120851227", Volume = 0.5, Pitch = 0.7, MaxDistance = 90 },
	Deliver = { Id = "rbxassetid://9120103996", Volume = 0.7, MaxDistance = 120 },
	Thaw = { Id = "rbxassetid://9114591515", Volume = 0.4, Pitch = 1.6, MaxDistance = 60 },
	Pickup = { Id = "rbxassetid://9116173869", Volume = 0.4 },
	-- Monster
	MonsterBreath = { Id = "rbxassetid://9113983944", Volume = 0.7, Pitch = 0.8, Looped = true, MaxDistance = 45 },
	MonsterVocal = { Id = "rbxassetid://9113985466", Volume = 0.9, Pitch = 0.75, MaxDistance = 180 },
	MonsterListen = { Id = "rbxassetid://9125475729", Volume = 0.8, Pitch = 0.7, MaxDistance = 50 },
	MonsterHunt = { Id = "rbxassetid://9113980319", Volume = 1.2, Pitch = 0.8, MaxDistance = 220 },
	Caught = { Id = "rbxassetid://9043346594", Volume = 1.1 },
	-- Round
	Countdown = { Id = "rbxassetid://9113880475", Volume = 0.5 },
	AllCores = { Id = "rbxassetid://9119661709", Volume = 0.5, Pitch = 1.2 },
	Escape = { Id = "rbxassetid://1837953706", Volume = 0.6 },
	Fail = { Id = "rbxassetid://9043338697", Volume = 0.6 },
	Heartbeat = { Id = "rbxassetid://9043365842", Volume = 0.6, Looped = true },
	-- Ambience / music (add your own)
	Wind = { Id = "", Volume = 0.3, Looped = true },
	GustWind = { Id = "", Volume = 0.5 },
	LobbyMusic = { Id = "", Volume = 0.3, Looped = true },
	LakeMusic = { Id = "", Volume = 0.2, Looped = true },
	UIClick = { Id = "", Volume = 0.4 },
}
