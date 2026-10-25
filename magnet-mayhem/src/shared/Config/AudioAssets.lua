--[[
	AudioAssets - every sound the game plays, by name.

	IMPORTANT: no Roblox audio asset IDs are invented. The rbxassetid:// entries below are
	reused from DEAD AIR's AudioAssets (same account's checked Creator Store picks). Every
	other slot is Id = "" and is skipped silently: add your own audio there.

	Group = volume category: Effects | Ambient | Music | UI   (all under Master)
]]

return {
	-- Magnet
	MagnetSwitch = { Id = "rbxassetid://9120098454", Volume = 0.5, Pitch = 1.3, Group = "Effects" },
	MagnetHum = { Id = "rbxassetid://9112889082", Volume = 0.25, Looped = true, Group = "Effects" },
	MagnetCharge = { Id = "", Volume = 0.4, Group = "Effects" }, -- add: rising electrical charge
	PulseWave = { Id = "rbxassetid://9119631707", Volume = 0.55, Pitch = 1.6, Group = "Effects" },
	-- Collection by weight class
	ClinkLight = { Id = "rbxassetid://9116612715", Volume = 0.32, Pitch = 1.5, Group = "Effects" },
	SnapLight = { Id = "rbxassetid://9116173869", Volume = 0.3, Pitch = 1.2, Group = "Effects" },
	ClunkMedium = { Id = "rbxassetid://9120851227", Volume = 0.5, Pitch = 0.9, Group = "Effects" },
	ChainRattle = { Id = "", Volume = 0.45, Group = "Effects" }, -- add: chain rattle
	HeavyGroan = { Id = "rbxassetid://9116892199", Volume = 0.55, Pitch = 0.7, Group = "Effects" },
	HeavyImpact = { Id = "rbxassetid://9116537007", Volume = 0.7, Pitch = 0.75, Group = "Effects" },
	RareSting = { Id = "rbxassetid://1837953706", Volume = 0.6, Group = "Effects" },
	TooHeavy = { Id = "rbxassetid://9043338697", Volume = 0.35, Pitch = 1.4, Group = "Effects" },
	-- Shredder
	ShredderStart = { Id = "rbxassetid://9120103996", Volume = 0.6, Pitch = 0.8, Group = "Effects" },
	ShredderLoop = { Id = "rbxassetid://9119386548", Volume = 0.45, Looped = true, Group = "Effects" },
	ShredderCrunch = { Id = "rbxassetid://9116537007", Volume = 0.6, Pitch = 1.1, Group = "Effects" },
	ShredderSlam = { Id = "rbxassetid://1837829565", Volume = 0.6, Group = "Effects" },
	SaleDing = { Id = "rbxassetid://9114533169", Volume = 0.5, Pitch = 1.2, Group = "UI" },
	-- UI
	Click = { Id = "rbxassetid://9114480271", Volume = 0.35, Pitch = 1.2, Group = "UI" },
	Purchase = { Id = "rbxassetid://9113722650", Volume = 0.5, Group = "UI" },
	Denied = { Id = "rbxassetid://9043338697", Volume = 0.35, Pitch = 1.6, Group = "UI" },
	Beep = { Id = "rbxassetid://9113880475", Volume = 0.35, Group = "UI" },
	ZoneUnlock = { Id = "rbxassetid://1837953706", Volume = 0.7, Pitch = 0.9, Group = "UI" },
	QuestDone = { Id = "", Volume = 0.5, Group = "UI" }, -- add: short success jingle
	LevelUp = { Id = "", Volume = 0.6, Group = "UI" }, -- add: tier-up / prestige fanfare
	-- Events
	StormSiren = { Id = "rbxassetid://9119661709", Volume = 0.35, Group = "Effects", Duration = 4 },
	-- Ambient (3D emitters placed by WorldBuilder, played at random intervals)
	Wind = { Id = "rbxassetid://9125446564", Volume = 0.18, Looped = true, Group = "Ambient" },
	Machinery = { Id = "rbxassetid://9119386548", Volume = 0.12, Looped = true, Group = "Ambient" },
	Creak = { Id = "rbxassetid://9116892199", Volume = 0.25, Group = "Ambient" },
	Hum = { Id = "rbxassetid://9112823813", Volume = 0.1, Looped = true, Group = "Ambient" },
	UrbanWind = { Id = "rbxassetid://9125446564", Volume = 0.2, Pitch = 0.85, Looped = true, Group = "Ambient" },
	DistantClang = { Id = "rbxassetid://9113134899", Volume = 0.25, Group = "Ambient" },
	Birds = { Id = "", Volume = 0.15, Looped = true, Group = "Ambient" }, -- add: outdoor birds
	-- Music (none bundled: add licensed tracks)
	MusicRustyard = { Id = "", Volume = 0.25, Looped = true, Group = "Music" },
	MusicMetro = { Id = "", Volume = 0.25, Looped = true, Group = "Music" },
}
