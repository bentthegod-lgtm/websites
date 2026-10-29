--[[
	AudioAssets - every sound the game plays, grouped for the volume settings
	(Master / Music / Effects / Ambient / UI).

	IMPORTANT: no audio asset IDs are invented here. Every rbxassetid below is one already
	used and verified in DEAD AIR (dead-air/src/shared/Config/AudioAssets.lua, Roblox's
	licensed sound library), re-pitched to fit. Slots with Id = "" are empty and simply
	skipped: add your own audio (see POLISH.md). A unit test enforces this list.
	PitchVar adds a small random pitch change on each play so repeats don't grate.
]]

local AudioAssets = {}

AudioAssets.Sounds = {
	-- Pickups (by loot category)
	CashPickup = { Id = "rbxassetid://9116173869", Group = "Effects", Volume = 0.45, Pitch = 1.25, PitchVar = 0.08 },
	GoldPickup = { Id = "rbxassetid://9116537007", Group = "Effects", Volume = 0.4, Pitch = 1.35, PitchVar = 0.06 },
	GemPickup = { Id = "rbxassetid://9113880475", Group = "Effects", Volume = 0.4, Pitch = 1.6, PitchVar = 0.1 },
	MetalPickup = { Id = "rbxassetid://9116612715", Group = "Effects", Volume = 0.4, Pitch = 1.1, PitchVar = 0.06 },
	ArtifactPickup = { Id = "rbxassetid://9120851227", Group = "Effects", Volume = 0.45, Pitch = 0.9, PitchVar = 0.05 },
	HeavyPickup = { Id = "rbxassetid://9116537007", Group = "Effects", Volume = 0.55, Pitch = 0.8, PitchVar = 0.04 },
	StackFull = { Id = "rbxassetid://9113880475", Group = "UI", Volume = 0.35, Pitch = 0.7 },
	-- Deposit machine
	DepositInsert = { Id = "rbxassetid://9120103996", Group = "Effects", Volume = 0.6, Pitch = 0.95 },
	DepositMachine = { Id = "rbxassetid://9120098454", Group = "Effects", Volume = 0.5, Pitch = 1.15 },
	DepositReward = { Id = "rbxassetid://9113722650", Group = "Effects", Volume = 0.55, Pitch = 1.2 },
	-- Progression
	UpgradeBuy = { Id = "rbxassetid://9113722650", Group = "UI", Volume = 0.5, Pitch = 1 },
	NoFunds = { Id = "rbxassetid://9043338697", Group = "UI", Volume = 0.35, Pitch = 1.3 },
	FloorUnlock = { Id = "rbxassetid://1837953706", Group = "Effects", Volume = 0.6, Pitch = 1 },
	RareDiscovery = { Id = "rbxassetid://1837953706", Group = "Effects", Volume = 0.5, Pitch = 1.25 },
	Achievement = { Id = "rbxassetid://9113722650", Group = "UI", Volume = 0.45, Pitch = 1.45 },
	UiClick = { Id = "rbxassetid://9114480271", Group = "UI", Volume = 0.3, Pitch = 1.2, PitchVar = 0.04 },
	-- Elevator and doors
	ElevatorDoor = { Id = "rbxassetid://9120839599", Group = "Effects", Volume = 0.55, Pitch = 0.8 },
	ElevatorDoorClose = { Id = "rbxassetid://9119129301", Group = "Effects", Volume = 0.55, Pitch = 0.8 },
	ElevatorMotor = { Id = "rbxassetid://9119386548", Group = "Effects", Volume = 0.45, Pitch = 1.1, Looped = true },
	ElevatorArrive = { Id = "rbxassetid://9114533169", Group = "Effects", Volume = 0.5, Pitch = 1 },
	VaultDoor = { Id = "rbxassetid://9119631707", Group = "Effects", Volume = 0.8, Pitch = 0.75 },
	-- Ambience (3D emitters placed by the world builder, plus 2D beds)
	Ventilation = { Id = "rbxassetid://9125446564", Group = "Ambient", Volume = 0.16, Looped = true },
	ElectricalHum = { Id = "rbxassetid://9112889082", Group = "Ambient", Volume = 0.1, Looped = true },
	LightBuzz = { Id = "rbxassetid://9112823813", Group = "Ambient", Volume = 0.06, Looped = true },
	Machinery = { Id = "rbxassetid://9119386548", Group = "Ambient", Volume = 0.12, Pitch = 0.7, Looped = true },
	DistantClank = { Id = "rbxassetid://9113134899", Group = "Ambient", Volume = 0.25, Pitch = 1.1 },
	PipeCreak = { Id = "rbxassetid://9116892199", Group = "Ambient", Volume = 0.18, Pitch = 1.2 },
	-- Music: empty until you add licensed tracks (see POLISH.md)
	MusicTop = { Id = "", Group = "Music", Volume = 0.3, Looped = true },
	MusicDeep = { Id = "", Group = "Music", Volume = 0.3, Looped = true },
	MusicLegendary = { Id = "", Group = "Music", Volume = 0.3, Looped = true },
	-- Empty slots (no suitable verified asset yet)
	CoinShower = { Id = "", Group = "Effects", Volume = 0.5 },
	CrystalChime = { Id = "", Group = "Ambient", Volume = 0.2 },
}

-- Footsteps use Roblox's default character sounds (per-material), so they need no slot.

-- Per-depth ambience: 2D beds (Loops, with volume scale) and occasional one-shots.
AudioAssets.Ambience = {
	CashVault = { Loops = { Ventilation = 1, LightBuzz = 1 }, OneShots = { "DistantClank" }, Gap = { 18, 34 }, Music = "MusicTop" },
	GoldReserve = { Loops = { Ventilation = 1, Machinery = 0.8 }, OneShots = { "DistantClank", "PipeCreak" }, Gap = { 16, 30 }, Music = "MusicTop" },
	DiamondChamber = { Loops = { ElectricalHum = 1, Ventilation = 0.6 }, OneShots = { "CrystalChime" }, Gap = { 20, 40 }, Music = "MusicDeep" },
	EmeraldReserve = { Loops = { ElectricalHum = 1.2, Ventilation = 0.7 }, OneShots = { "PipeCreak" }, Gap = { 20, 36 }, Music = "MusicDeep" },
	PlatinumReserve = { Loops = { Machinery = 1.4, Ventilation = 0.8 }, OneShots = { "DistantClank" }, Gap = { 10, 22 }, Music = "MusicDeep" },
	ArtifactChamber = { Loops = { Ventilation = 0.5, ElectricalHum = 0.6 }, OneShots = { "PipeCreak", "CrystalChime" }, Gap = { 24, 44 }, Music = "MusicDeep" },
	LegendaryReserve = { Loops = { ElectricalHum = 0.8, Machinery = 0.5 }, OneShots = { "DistantClank" }, Gap = { 26, 48 }, Music = "MusicLegendary" },
}

return AudioAssets
