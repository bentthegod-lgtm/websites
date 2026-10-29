--[[
	AudioAssets - every sound the game plays, by name.

	IMPORTANT: no Roblox audio asset IDs are invented. Every rbxassetid:// entry below is
	reused from DEAD AIR's AudioAssets (the same account's checked Creator Store picks); the
	tests fail if any other id appears here. Every other slot is Id = "" and is skipped
	silently: add your own audio there (see POLISH.md).

	Group = volume category: Effects | Ambient | Music | UI   (all under Master)
]]

return {
	-- Standard launcher
	StandardPrep = { Id = "rbxassetid://9120098454", Volume = 0.45, Pitch = 1.1, Group = "Effects" }, -- mechanical cock-back
	StandardRelease = { Id = "rbxassetid://9119631707", Volume = 0.6, Pitch = 1.3, Group = "Effects" },
	-- Spring cannon
	SpringCompress = { Id = "rbxassetid://9116892199", Volume = 0.45, Pitch = 1.5, Group = "Effects", Duration = 2 },
	SpringSnap = { Id = "rbxassetid://9116537007", Volume = 0.7, Pitch = 1.4, Group = "Effects" },
	-- Air cannon
	AirPressure = { Id = "rbxassetid://9112889082", Volume = 0.45, Pitch = 1.6, Group = "Effects", Duration = 3 },
	AirWarning = { Id = "rbxassetid://9113880475", Volume = 0.45, Pitch = 1.3, Group = "Effects" },
	AirBlast = { Id = "rbxassetid://9119631707", Volume = 0.9, Pitch = 0.7, Group = "Effects", Duration = 3 },
	AirHiss = { Id = "rbxassetid://9125446564", Volume = 0.35, Pitch = 2.4, Group = "Effects", Duration = 1.2 }, -- ventilation loop pitched up (swap for a real hiss)
	Whoosh = { Id = "rbxassetid://9125446564", Volume = 0.3, Pitch = 2, Group = "Effects", Duration = 0.8 }, -- ventilation loop pitched up (swap for a real whoosh)
	-- Crash impacts by tier
	ImpactLight = { Id = "rbxassetid://9120851227", Volume = 0.4, Pitch = 1.2, Group = "Effects" },
	ImpactMedium = { Id = "rbxassetid://9116537007", Volume = 0.5, Pitch = 1.05, Group = "Effects" },
	ImpactHeavy = { Id = "rbxassetid://9113134899", Volume = 0.75, Pitch = 1, Group = "Effects", MaxDistance = 220 },
	ImpactMetal = { Id = "rbxassetid://9116537007", Volume = 0.6, Pitch = 0.8, Group = "Effects" },
	SoftLanding = { Id = "rbxassetid://9120851227", Volume = 0.4, Pitch = 0.6, Group = "Effects" }, -- light impact pitched down
	Boing = { Id = "", Volume = 0.45, Group = "Effects" }, -- add: comedic boing for crash pads
	-- Destructibles
	BoxCrunch = { Id = "rbxassetid://9120851227", Volume = 0.55, Pitch = 0.8, Group = "Effects" },
	PlasticPop = { Id = "rbxassetid://9116612715", Volume = 0.55, Pitch = 1.1, Group = "Effects" },
	WoodSnap = { Id = "rbxassetid://1837829565", Volume = 0.6, Pitch = 1.2, Group = "Effects" },
	PanelShatter = { Id = "rbxassetid://9114591515", Volume = 0.7, Group = "Effects" },
	GongHit = { Id = "rbxassetid://9119661709", Volume = 0.5, Pitch = 0.6, Group = "Effects", Duration = 3 },
	RingPass = { Id = "rbxassetid://9113880475", Volume = 0.5, Pitch = 1.6, Group = "Effects" },
	-- Destruction Testing Zone props (pitched reuses; swap for real recordings)
	BrickCrumble = { Id = "rbxassetid://9120851227", Volume = 0.6, Pitch = 0.55, Group = "Effects" }, -- box crunch pitched down
	BarrelClang = { Id = "rbxassetid://9116537007", Volume = 0.6, Pitch = 0.7, Group = "Effects" }, -- metal impact pitched down
	-- Facility hazards
	WindGust = { Id = "rbxassetid://9125446564", Volume = 0.3, Pitch = 1.7, Group = "Effects", Duration = 1 }, -- ventilation pitched up (swap for a real gust)
	GravityShift = { Id = "rbxassetid://9112889082", Volume = 0.35, Pitch = 2, Group = "Effects", Duration = 1 }, -- air pressure pitched up
	BounceField = { Id = "", Volume = 0.45, Group = "Effects" }, -- add: sci-fi bounce / spring zap
	TransitWhoosh = { Id = "", Volume = 0.4, Group = "UI" }, -- add: teleport / transit whoosh
	-- Feedback
	ObjectiveDone = { Id = "rbxassetid://1837953706", Volume = 0.6, Group = "UI" },
	NewRecord = { Id = "rbxassetid://1837953706", Volume = 0.7, Pitch = 1.2, Group = "UI" },
	ResultsTally = { Id = "rbxassetid://9113880475", Volume = 0.3, Pitch = 1.8, Group = "UI" },
	Coins = { Id = "rbxassetid://9114533169", Volume = 0.5, Pitch = 1.2, Group = "UI" },
	Purchase = { Id = "rbxassetid://9113722650", Volume = 0.5, Group = "UI" },
	Denied = { Id = "rbxassetid://9043338697", Volume = 0.35, Pitch = 1.6, Group = "UI" },
	Click = { Id = "rbxassetid://9114480271", Volume = 0.35, Pitch = 1.2, Group = "UI" },
	MachineUnlock = { Id = "rbxassetid://1837953706", Volume = 0.7, Pitch = 0.9, Group = "UI" },
	Achievement = { Id = "rbxassetid://1837953706", Volume = 0.55, Pitch = 1.3, Group = "UI" }, -- objective chime pitched up
	ChallengeDone = { Id = "rbxassetid://9113722650", Volume = 0.55, Pitch = 1.2, Group = "UI" }, -- purchase chime pitched up
	Countdown = { Id = "rbxassetid://9113880475", Volume = 0.4, Group = "UI" },
	-- Ambient (3D emitters placed by the facility builder)
	Ventilation = { Id = "rbxassetid://9125446564", Volume = 0.14, Looped = true, Group = "Ambient" },
	Machinery = { Id = "rbxassetid://9119386548", Volume = 0.1, Looped = true, Group = "Ambient" },
	ElectricHum = { Id = "rbxassetid://9112823813", Volume = 0.08, Looped = true, Group = "Ambient" },
	Clank = { Id = "rbxassetid://9113134899", Volume = 0.2, Pitch = 1.3, Group = "Ambient" },
	CanyonWind = { Id = "rbxassetid://9125446564", Volume = 0.2, Pitch = 0.55, Looped = true, Group = "Ambient" }, -- ventilation pitched down (swap for real mountain wind)
	DemolitionRumble = { Id = "rbxassetid://9119386548", Volume = 0.12, Pitch = 0.7, Looped = true, Group = "Ambient" }, -- machinery pitched down
	GravityHum = { Id = "rbxassetid://9112823813", Volume = 0.1, Pitch = 1.5, Looped = true, Group = "Ambient" }, -- electric hum pitched up
	-- Music (none bundled: add licensed tracks)
	MusicLobby = { Id = "", Volume = 0.25, Looped = true, Group = "Music" },
	MusicRun = { Id = "", Volume = 0.3, Looped = true, Group = "Music" },
}
