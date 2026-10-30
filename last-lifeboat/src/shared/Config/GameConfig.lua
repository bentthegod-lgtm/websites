--[[
	GameConfig - every tunable number for LAST LIFEBOAT in one place.

	Distances are studs, times seconds, rates per second. Sea level is world Y = 0: the
	ocean is static Terrain water, and the ship sinks INTO it with discrete lurches, so any
	deck that drops below Y = 0 floods by itself.

	Ship-local frame (used by ShipGen / ShipBuilder / LurchMath): the origin is the stern on
	the centreline at the waterline, +Z runs to the bow, +Y is up, +X is starboard. The ship
	model's pivot is that origin, so a lurch is one PivotTo that sinks and rotates the ship
	about the stern (bow down, stern up).
]]

local GameConfig = {}

GameConfig.SchemaVersion = 1
GameConfig.DataStoreName = "LastLifeboat_Profiles_v1"
GameConfig.LeaderboardStores = { Escapes = "LastLifeboat_Escapes_v1", Banked = "LastLifeboat_Banked_v1" }
GameConfig.AutosaveInterval = 60
GameConfig.MaxPlayers = 8
GameConfig.Leaderboard = { WriteInterval = 120, Refresh = 75, Rows = 10 }
GameConfig.AttributePrefix = "LL_"

---------------------------------------------------------------------------------------------
-- World layout
---------------------------------------------------------------------------------------------

GameConfig.World = {
	SeaLevel = 0,
	-- The ship is moored broadside to the harbour dock: its stern pivot sits at
	-- (ShipX, 0, -Length / 2) so every ship is centred on Z = 0.
	ShipX = 70,
	DockTop = 3.4, -- top of the dock planks
	DockX = { -70, 22 }, -- the dock's X extent (the ship's port side is at ShipX - Beam/2)
	DockZ = { -70, 70 },
	Spawn = { -36, 0 },
	-- Ocean (static terrain water). A wide shallow harbour and a deep trench under the ship
	-- (the bow of the biggest ship ends up ~170 studs down).
	OceanHalf = 640,
	OceanDepth = 24,
	TrenchDepth = 240,
	TrenchMargin = 48,
	OceanChunk = 160, -- FillBlock this many studs square per frame
}

---------------------------------------------------------------------------------------------
-- Ships (the vote picks one; ShipGen plans it, ShipBuilder builds it a few parts per frame)
---------------------------------------------------------------------------------------------

GameConfig.ShipOrder = { "Gull", "Aurora", "Leviathan" }

GameConfig.Ship = {
	CellLength = 16, -- decks are planned as cells along Z
	DeckHeight = 14,
	DeckBase = 6, -- floor top of the lowest deck (local Y); the hull bottom is at Keel
	Keel = -6,
	BowCells = 3, -- the hull tapers over this many cells at the bow
	BowTip = 4, -- hull width at the very bow
	SternRound = 0.68, -- the hull narrows to this fraction of the beam at the transom
	WalkwayHalf = 4, -- |x| < this stays clear on every deck (props keep out)
	PartsPerStep = 260, -- ShipBuilder: parts per server frame
	MaxLooseProps = 40,
}

GameConfig.Ships = {
	Gull = {
		Order = 1,
		Name = "The Gull",
		Blurb = "A small harbour ferry. 3 decks. Easy.",
		Length = 160,
		Beam = 44,
		Decks = { "CargoHold", "Cabins", "TopDeck" },
		RoundTime = 180,
		LurchEvery = { 18, 22 },
		MaxTilt = 22,
		MaxSink = 8,
		UnlockEscapes = 0,
		Tier = 1,
		LootMult = 1,
		LootPerDeck = 5,
		Funnels = 1,
		PartBudget = 2600,
		Hull = { 30, 52, 86 }, -- dark hull colour
		Funnel = { 236, 226, 200 },
		FunnelBand = { 40, 110, 170 },
		Color = { 120, 220, 150 },
	},
	Aurora = {
		Order = 2,
		Name = "Aurora Grand",
		Blurb = "A cruise liner. 5 decks, a grand dining hall.",
		Length = 240,
		Beam = 56,
		Decks = { "EngineRoom", "CrewQuarters", "Cabins", "DiningHall", "TopDeck" },
		RoundTime = 240,
		LurchEvery = { 19, 23 },
		MaxTilt = 25,
		MaxSink = 11,
		UnlockEscapes = 3,
		Tier = 2,
		LootMult = 1.5,
		LootPerDeck = 5,
		Funnels = 2,
		PartBudget = 4000,
		Hull = { 22, 34, 60 },
		Funnel = { 200, 60, 50 },
		FunnelBand = { 24, 24, 30 },
		Color = { 255, 200, 110 },
	},
	Leviathan = {
		Order = 3,
		Name = "Iron Leviathan",
		Blurb = "A giant liner. 7 decks. Hard.",
		Length = 320,
		Beam = 64,
		Decks = { "EngineRoom", "CargoHold", "CrewQuarters", "Cabins", "DiningHall", "Promenade", "TopDeck" },
		RoundTime = 300,
		LurchEvery = { 20, 25 },
		MaxTilt = 27,
		MaxSink = 14,
		UnlockEscapes = 10,
		Tier = 3,
		LootMult = 2.2,
		LootPerDeck = 5,
		Funnels = 3,
		PartBudget = 5000,
		Hull = { 26, 26, 32 },
		Funnel = { 214, 150, 60 },
		FunnelBand = { 20, 20, 24 },
		Color = { 255, 110, 110 },
	},
}

-- Deck themes: display name, floor / wall colours (RGB) and materials (Enum.Material names).
GameConfig.Themes = {
	EngineRoom = { Name = "Engine Room", Floor = { 92, 96, 104 }, FloorMat = "DiamondPlate", Wall = { 70, 74, 82 }, WallMat = "Metal", Light = { 255, 176, 96 } },
	CargoHold = { Name = "Cargo Hold", Floor = { 78, 82, 88 }, FloorMat = "Metal", Wall = { 96, 84, 70 }, WallMat = "CorrodedMetal", Light = { 255, 214, 150 } },
	CrewQuarters = { Name = "Crew Quarters", Floor = { 110, 124, 118 }, FloorMat = "SmoothPlastic", Wall = { 196, 200, 186 }, WallMat = "SmoothPlastic", Light = { 255, 236, 200 } },
	Cabins = { Name = "Cabins", Floor = { 176, 140, 104 }, FloorMat = "WoodPlanks", Wall = { 232, 222, 196 }, WallMat = "SmoothPlastic", Light = { 255, 220, 160 } },
	DiningHall = { Name = "Grand Dining Hall", Floor = { 120, 78, 48 }, FloorMat = "Wood", Wall = { 150, 98, 60 }, WallMat = "Wood", Light = { 255, 210, 140 } },
	Promenade = { Name = "Promenade", Floor = { 170, 120, 76 }, FloorMat = "WoodPlanks", Wall = { 238, 232, 214 }, WallMat = "SmoothPlastic", Light = { 255, 226, 170 } },
	TopDeck = { Name = "Top Deck", Floor = { 176, 128, 82 }, FloorMat = "WoodPlanks", Wall = { 240, 236, 226 }, WallMat = "SmoothPlastic", Light = { 255, 222, 160 } },
}

---------------------------------------------------------------------------------------------
-- Sinking
---------------------------------------------------------------------------------------------

GameConfig.Sinking = {
	BraceTime = 2, -- warning (horn, red flash, "BRACE!") before every lurch
	TiltCurve = 1.6, -- tilt_k = MaxTilt * (k / N) ^ TiltCurve, N = expected lurches per round
	SlideTilt = 12, -- above this tilt the client pulls characters gently downhill
	SlideAccel = 22, -- studs/s^2 at MaxTilt (Grip reduces it)
	ValveDelay = 6, -- a closed valve wheel pushes the next lurch back this long
	PropNudge = 9, -- loose props get this downhill velocity on a lurch
	ShakeStrength = 0.9,
	FinalPlungeTilt = 8, -- extra tilt for the cinematic after launch
}

---------------------------------------------------------------------------------------------
-- Survival: oxygen, downed, revive
---------------------------------------------------------------------------------------------

GameConfig.Oxygen = {
	Base = 12, -- seconds of breath underwater (Lung Capacity adds more)
	Regen = 4, -- seconds of breath regained per second above water
	HeadDepth = 0.4, -- the head counts as underwater this far below the surface
	ZapLoss = 3, -- sparking wires take this much breath
	ReviveTo = 0.5, -- revived with this fraction of max oxygen
}

GameConfig.Downed = {
	BleedOut = 20,
	ReviveHold = 2,
	ReviveRange = 10,
	LifeJacketDelay = 2, -- a Life Jacket auto-revives you this long after going down
	LifeJacketsPerRound = 1, -- at most this many auto-revives per round (bounded pay-to-win)
	FloatClearance = 2.5, -- a downed body floats up to the surface (or under a ceiling)
}

GameConfig.Move = {
	Walk = 16,
	MinWalk = 9, -- heavy loot never slows you below this
	WeightSlow = 1.6, -- WalkSpeed lost per weight point carried
	SpeedTolerance = 1.6, -- anti-cheat: allowed speed = expected * tolerance + slack
	SpeedSlack = 10,
}

---------------------------------------------------------------------------------------------
-- Co-op obstacles and hazards
---------------------------------------------------------------------------------------------

GameConfig.Obstacles = {
	LeverRange = 8,
	SoloHold = 4, -- one player holding one lever for this long opens a bulkhead when solo
	ValveHold = 1.5,
	PromptRange = 9,
}

GameConfig.Hazards = {
	Steam = { Period = 7, Warn = 1.6, Burst = 1.1, Radius = 7, Damage = 12, Knockback = 55 },
	Chandelier = { Radius = 5, Damage = 30, Knockback = 30, PerLurch = 1 },
	Wires = { Period = 1.6, Radius = 8, Oxygen = 3 },
}

---------------------------------------------------------------------------------------------
-- Lifeboat
---------------------------------------------------------------------------------------------

GameConfig.Lifeboat = {
	FullCrewHold = 3, -- everyone still in the round aboard for this long = early launch
	FullCrewBonus = 1.25,
	CinematicTime = 7,
	LowerDepth = 0, -- the boat is lowered to the sea surface, then rows away
	RowDistance = 80,
	SeatZone = { 9, 8, 15 }, -- (X, Y, Z) size of the boarding zone (ship-local, on the boat)
}

---------------------------------------------------------------------------------------------
-- Round flow
---------------------------------------------------------------------------------------------

GameConfig.Round = {
	Countdown = 6,
	ReadyTimeout = 25, -- once someone is ready, start this long after even if others aren't
	ResultsTime = 10,
	VotePadRadius = 7,
	MaxPrepareFrames = 600,
}

---------------------------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------------------------

GameConfig.RarityOrder = { "Common", "Rare", "Epic", "Legendary" }
GameConfig.Rarities = {
	Common = { Color = { 222, 214, 190 }, Weight = 60 },
	Rare = { Color = { 90, 170, 255 }, Weight = 27 },
	Epic = { Color = { 186, 110, 255 }, Weight = 10 },
	Legendary = { Color = { 255, 196, 60 }, Weight = 3 },
}

-- Value is the base bank value; Weight slows you down while carried (gold, paintings).
GameConfig.LootOrder = {
	"PocketWatch", "SilverSpoons", "LeatherWallet", "BrassSpyglass",
	"PearlNecklace", "CaptainsCompass", "CrystalDecanter",
	"JewelBox", "GoldBar", "Painting",
	"RubyTiara", "GoldenSextant", "StarSapphire",
}
GameConfig.Loot = {
	PocketWatch = { Name = "Pocket Watch", Rarity = "Common", Value = 40, Weight = 0, Model = "Watch" },
	SilverSpoons = { Name = "Silver Spoons", Rarity = "Common", Value = 30, Weight = 0, Model = "Spoons" },
	LeatherWallet = { Name = "Leather Wallet", Rarity = "Common", Value = 35, Weight = 0, Model = "Wallet" },
	BrassSpyglass = { Name = "Brass Spyglass", Rarity = "Common", Value = 50, Weight = 0, Model = "Spyglass" },
	PearlNecklace = { Name = "Pearl Necklace", Rarity = "Rare", Value = 120, Weight = 0, Model = "Necklace" },
	CaptainsCompass = { Name = "Captain's Compass", Rarity = "Rare", Value = 110, Weight = 0, Model = "Compass" },
	CrystalDecanter = { Name = "Crystal Decanter", Rarity = "Rare", Value = 95, Weight = 0, Model = "Decanter" },
	JewelBox = { Name = "Jewel Box", Rarity = "Epic", Value = 240, Weight = 1, Model = "JewelBox" },
	GoldBar = { Name = "Gold Bar", Rarity = "Epic", Value = 300, Weight = 3, Model = "GoldBar" },
	Painting = { Name = "Painting", Rarity = "Epic", Value = 260, Weight = 2, Model = "Painting" },
	RubyTiara = { Name = "Ruby Tiara", Rarity = "Legendary", Value = 600, Weight = 0, Model = "Tiara" },
	GoldenSextant = { Name = "Golden Sextant", Rarity = "Legendary", Value = 550, Weight = 1, Model = "Sextant" },
	StarSapphire = { Name = "Star Sapphire", Rarity = "Legendary", Value = 680, Weight = 0, Model = "Sapphire" },
}

GameConfig.LootRules = {
	BaseSlots = 3,
	PickupRange = 10,
	PickupHold = 0.35,
	-- Deeper decks (the ones that flood first) roll rarer loot: each deck below the top
	-- multiplies the Rare+ weights by (1 + DepthBonus * depth fraction).
	DepthBonus = 1.6,
	-- Higher ship tiers roll rarer loot too.
	TierBonus = 0.35,
}

---------------------------------------------------------------------------------------------
-- Rewards, upgrades, retention
---------------------------------------------------------------------------------------------

GameConfig.Rewards = {
	EscapeBase = 40, -- coins for escaping at all (times the ship's LootMult)
	Participation = 15, -- "LOST AT SEA" still pays this
	ReviveBonus = 10, -- per teammate you revived
	DoubleLoot = 2, -- x2 Loot pass multiplier on banked loot
	VipCoins = 0, -- VIP is cosmetic + 1 slot (no coin bonus: bounded pay-to-win)
}

GameConfig.UpgradeOrder = { "Lungs", "Swim", "Grip", "Slots", "Climb" }
-- Costs[i] buys level i. Effects[i + 1] is the effect AT level i (Effects[1] = level 0).
GameConfig.Upgrades = {
	Lungs = { Name = "Lung Capacity", Unit = "s oxygen", Costs = { 150, 350, 700, 1200, 2000 }, Effects = { 12, 14.5, 17, 19.5, 22, 25 } },
	Swim = { Name = "Swim Speed", Unit = "x swim speed", Costs = { 120, 300, 600, 1000, 1700 }, Effects = { 1, 1.08, 1.16, 1.24, 1.32, 1.4 } },
	Grip = { Name = "Grip", Unit = "x slide", Costs = { 100, 250, 500, 900, 1500 }, Effects = { 1, 0.85, 0.7, 0.55, 0.42, 0.3 } },
	Slots = { Name = "Loot Slots", Unit = " slots", Costs = { 250, 600, 1100, 1800, 2800 }, Effects = { 3, 4, 4, 5, 5, 6 } },
	Climb = { Name = "Climb Speed", Unit = "x climb speed", Costs = { 100, 250, 500, 900, 1500 }, Effects = { 1, 1.1, 1.2, 1.3, 1.4, 1.5 } },
}

GameConfig.DailyRewards = { 60, 80, 100, 130, 160, 200, 300 }

GameConfig.Codes = {
	RELEASE = { Coins = 200 },
	MAYDAY = { Coins = 150, LifeJacket = 1 },
	ABANDONSHIP = { Coins = 250 },
}

-- Session goals: reset every time you join a server (not saved), each pays once.
GameConfig.SessionGoals = {
	{ Id = "Escape2", Text = "Escape 2 times", Stat = "Escapes", Target = 2, Coins = 120 },
	{ Id = "Revive1", Text = "Revive a teammate", Stat = "Revives", Target = 1, Coins = 80 },
	{ Id = "BankRare", Text = "Bank a Rare or better", Stat = "BankedRarePlus", Target = 1, Coins = 100 },
}

GameConfig.Grapple = { Range = 40, Cooldown = 12, PullSpeed = 70 }
GameConfig.Flare = { Radius = 30, ArrowTime = 15 }

-- First-time tutorial hints (client shows these in order during your first rounds).
GameConfig.TutorialHints = {
	"The ship is sinking! Climb UP and head to the STERN - the last lifeboat is on the top deck.",
	"Hold E on glowing valuables to grab them. They only pay out if you ESCAPE.",
	"Watch your OXYGEN underwater. At zero you go down - a friend can hold E to revive you.",
	"BRACE! means a lurch: the ship drops and tilts. Close valve wheels to delay the next one.",
}

return GameConfig
