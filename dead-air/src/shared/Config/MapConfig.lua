--[[
	Layout and geometry settings for the procedurally assembled facility.
	Pure data: MazeGen reads it in both Roblox and the Lune tests.
]]

return {
	-- Grid of cells. Each cell is one room or corridor section.
	GridWidth = 8,
	GridHeight = 8,
	StartX = 3,
	StartY = 0,

	-- Geometry (studs).
	CellSize = 28,
	WallHeight = 14,
	WallThickness = 1,
	DoorWidth = 8,
	DoorHeight = 12,
	OpenWidth = 12,
	-- Each quadrant prop/locker sits this far from the cell centre on both axes.
	QuadrantOffset = 8.5,
	-- Half-width of the cross-shaped lane through every cell that props never occupy,
	-- which keeps every doorway reachable for players and for monster pathfinding.
	ClearLaneHalfWidth = 4.5,

	-- Generation.
	BranchBias = 0.3, -- 0 = long winding corridors, 1 = bushy
	LoopChance = 0.24, -- extra connections beyond the spanning tree (escape loops)
	DoorChance = 0.4, -- fraction of ordinary connections that get a door instead of an open arch
	MinSpecialDistance = 3, -- special rooms are at least this many steps from the start room
	PropChance = 0.65,
	LockerCount = 22,
	MaxLockersPerCell = 2,
	LitChanceBeforePower = 0.75,
	FlickerChance = 0.22,
	AnomalyCount = 1,
	StruggleCount = 2,

	-- Special rooms placed on dead ends of the spanning tree, in priority order.
	-- Each has exactly one entrance so it can be locked without breaking connectivity.
	SpecialRooms = { "Exit", "PowerRoom", "Security" },

	RoomWeights = {
		Office = 6,
		Hallway = 5,
		Storage = 2,
		Maintenance = 2,
		Restroom = 1,
		BreakRoom = 1,
	},

	-- Room kinds that can hold lockers.
	LockerKinds = { Office = true, Hallway = true, Storage = true, Maintenance = true, BreakRoom = true, Restroom = true },
	-- Hiding spots in these room kinds are wooden supply cabinets instead of metal lockers.
	CabinetKinds = { Office = true, BreakRoom = true },

	AnomalyVariants = { "TallRoom", "ChairRoom", "InvertedRoom", "FalseDoor" },

	-- Abstract floor names. MapBuilder maps them to Enum.Material; SoundConfig maps them to noise.
	FloorByKind = {
		Start = "Carpet",
		Office = "Carpet",
		Hallway = { "Carpet", "Tile", "Tile" },
		Storage = "Concrete",
		Maintenance = "Metal",
		Restroom = "Tile",
		BreakRoom = "Tile",
		Exit = "Metal",
		PowerRoom = "Metal",
		Security = "Tile",
		Anomaly = "Carpet",
	},

	-- Multiplier applied to every noise made inside a cell of this kind (echo / damping).
	Acoustics = {
		Office = 0.9,
		Hallway = 1.05,
		Storage = 1.0,
		Maintenance = 1.2,
		Restroom = 1.15,
		BreakRoom = 1.0,
		Start = 0.85,
		Exit = 1.2,
		PowerRoom = 1.2,
		Security = 1.0,
		Anomaly = 1.0,
		TallRoom = 1.4,
	},

	-- Ceiling height override for anomaly variants.
	TallRoomHeight = 46,

	-- Lobby is built far away from the facility.
	LobbyPosition = { 0, 400, -300 },
}
