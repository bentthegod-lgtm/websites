--[[
	Core tuning for Snatch a Blobby. Every gameplay number lives here or in the other
	Config modules so balancing never needs a code change.
]]

return {
	DataStoreName = "SnatchTycoon_Profiles_v1",
	LeaderboardStoreName = "SnatchTycoon_BestIncome_v1",
	SchemaVersion = 1,
	AutosaveInterval = 90,
	LeaderboardRefresh = 60,
	MaxPlayers = 8,

	StartCash = 100,
	WalkSpeed = 18,
	JumpPower = 50,

	-- Offline earnings: a share of your income per second while you were away, capped.
	OfflineCapHours = 3,
	OfflineRate = 0.5,
	OfflineMinimumSeconds = 120,

	-- Pedestal slots
	BaseSlots = 8,
	MaxRebirthSlots = 5, -- +1 slot per rebirth, up to this many
	VipSlots = 1,
	ExtraSlotsPass = 3,
	MaxPedestals = 20, -- physical pedestals built per base (>= the largest possible slot count)

	-- Friends in the same server boost everyone's income.
	FriendBoostPer = 0.1,
	FriendBoostMax = 0.3,

	SellRefund = 0.5,

	-- World layout (studs). The carpet runs along Z through the middle of the map;
	-- four bases sit on each side, facing it.
	Carpet = {
		StartZ = -165,
		EndZ = 165,
		Width = 14,
		Speed = 4.5,
		SpawnInterval = 2.6,
		MaxOnCarpet = 28,
	},
	Plot = {
		Width = 52, -- along the carpet
		Depth = 56, -- away from the carpet
		WallHeight = 14,
		EntranceWidth = 20,
		Spacing = 66,
		OffsetX = 43,
		PerSide = 4,
		Columns = 4,
		Rows = 5,
		ColumnSpacing = 11.5,
		RowSpacing = 9.5,
		BackRowZ = 22, -- local Z of the back row (front of the base is -Depth/2)
		PedestalHeight = 2.4,
	},

	BuyDistance = 16,
	WalkHomeSpeed = 16,

	Steal = {
		HoldDuration = 1.5,
		PromptDistance = 9,
		CarrySpeedMult = 0.55, -- of WalkSpeed
		FastCarrySpeedMult = 0.75, -- with the Speedy Snatcher pass (still slower than walking)
		CarryJumpPower = 30,
		CarryTimeout = 45, -- the Blobby wriggles free and runs home after this
		ReturnSpeed = 14,
		StunAfterSlap = 1.6,
		AttemptAnnounceCooldown = 8,
	},
	Slap = {
		Range = 10,
		Cooldown = 0.9,
		Knockback = 70,
	},
	Lock = {
		Duration = 45,
		Cooldown = 60,
		MinGapAfterPaid = 8, -- a paid lock can never chain back-to-back: the base opens for at least this long
	},
	Rebirth = {
		BaseCost = 50000,
		CostGrowth = 6,
		MultPer = 0.5, -- +50% income per rebirth
	},
	Events = {
		FirstAdminDelay = 300,
		AdminInterval = 900, -- an "admin abuse" style event every 15 minutes
		AdminDuration = 180,
		LuckyHourMinutes = 10, -- Lucky Hour: the first 10 minutes of every UTC hour
		ServerLuckPerPurchase = 900, -- 15 minutes
		ServerLuckCap = 7200,
		CoinInterval = 0.35,
		CoinLifetime = 12,
		CoinIncomeSeconds = 4, -- each coin is worth this many seconds of the collector's income
		CoinMinimum = 25,
	},
}
