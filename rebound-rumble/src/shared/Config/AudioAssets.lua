--[[
	Audio references.

	No asset IDs are invented. The rbxassetid:// entries below are reused from the
	DEAD AIR project's AudioAssets (Roblox licensed partner libraries found through the
	Creator Store), re-pitched where useful. Built-in rbxasset://sounds/ files ship with
	the Roblox client. Every slot with Id = "" is skipped by AudioUtil until you add your
	own audio (see README "Audio").
]]

return {
	Parry = { Id = "rbxassetid://9116537007", Volume = 0.9, Pitch = 1.45 }, -- metal clang
	ParryRemote = { Id = "rbxassetid://9116537007", Volume = 0.5, Pitch = 1.3, MaxDistance = 160 },
	Whiff = { Id = "", Volume = 0.4 },
	Explosion = { Id = "rbxassetid://9113134899", Volume = 1.2, MaxDistance = 300 },
	Confetti = { Id = "", Volume = 0.8 },
	GlassBurst = { Id = "rbxassetid://9114591515", Volume = 0.6, MaxDistance = 200 },
	Coin = { Id = "rbxassetid://9116173869", Volume = 0.5, Pitch = 1.2 },
	Countdown = { Id = "rbxassetid://9113880475", Volume = 0.5 },
	TargetWarning = { Id = "rbxassetid://9113880475", Volume = 0.6, Pitch = 1.7 },
	Click = { Id = "rbxassetid://9113880475", Volume = 0.25, Pitch = 1.3 },
	CrateTick = { Id = "rbxassetid://9113880475", Volume = 0.3, Pitch = 2 },
	CrateReveal = { Id = "rbxassetid://9116173869", Volume = 0.7, Pitch = 0.8 },
	Win = { Id = "rbxassetid://1837953706", Volume = 0.6 },
	Eliminated = { Id = "rbxassetid://9043338697", Volume = 0.6 },
	Jump = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.5, Pitch = 0.7 },
	Dash = { Id = "", Volume = 0.6 },
	FreezeCast = { Id = "", Volume = 0.6 },
	ShieldBreak = { Id = "rbxassetid://9114591515", Volume = 0.8, Pitch = 1.3 },
	SwapWarp = { Id = "", Volume = 0.6 },
	LobbyMusic = { Id = "", Volume = 0.3, Looped = true },
	BattleMusic = { Id = "", Volume = 0.3, Looped = true },
}
