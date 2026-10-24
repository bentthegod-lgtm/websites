--[[
	Objective chains. One chain is chosen per run (weighted). Each step type:

	collect  - pick up `count` of `item` (any player)
	unlock   - use `item` on the locked door of special room `room`
	deposit  - bring `count` of `item` to `station` (each insert is noisy)
	activate - interact once with `station`
	hold     - hold the interaction on `station` for `duration` seconds; emits `noise`
	           every `noiseInterval` while held
	extract  - call the elevator at `station`, survive the alarm, then board it

	`unlocks` opens the doors of the listed special rooms when the step completes.
	`effects` are applied by ObjectiveService (PowerOn, GeneratorRunning).
	Locks list the initial lock reason for each special room: an item name, "Power" or
	"Override". Text may contain %d/%d which is replaced with progress/count.
]]

return {
	Chains = {
		PowerGrid = {
			Weight = 1,
			Title = "BLACKOUT PROTOCOL",
			PowerRoomVariant = "Electrical",
			Locks = { PowerRoom = "Keycard", Security = "Power", Exit = "Override" },
			Steps = {
				{ Id = "find_keycard", Type = "collect", Item = "Keycard", Count = 1, Text = "Find a security keycard" },
				{ Id = "unlock_power", Type = "unlock", Room = "PowerRoom", Item = "Keycard", Text = "Unlock the electrical maintenance room" },
				{
					Id = "install_fuses",
					Type = "deposit",
					Item = "Fuse",
					Count = 3,
					Station = "FuseBox",
					Noise = "FuseInsert",
					Text = "Install replacement fuses (%d/%d)",
				},
				{
					Id = "restore_power",
					Type = "activate",
					Station = "Breaker",
					Noise = "BreakerPull",
					Text = "Throw the main breaker",
					Effects = { "PowerOn" },
					Unlocks = { "Security" },
				},
				{
					Id = "override",
					Type = "hold",
					Station = "Terminal",
					Duration = 6,
					Noise = "Terminal",
					NoiseInterval = 1.5,
					Text = "Run the exit override at the security terminal",
					Unlocks = { "Exit" },
				},
				{ Id = "extract", Type = "extract", Station = "ExitPanel", Text = "Call the service elevator and survive" },
			},
		},

		Generator = {
			Weight = 1,
			Title = "EMERGENCY GENERATOR",
			PowerRoomVariant = "Generator",
			Locks = { PowerRoom = "Keycard", Security = "Power", Exit = "Override" },
			Steps = {
				{ Id = "find_keycard", Type = "collect", Item = "Keycard", Count = 1, Text = "Find a maintenance keycard" },
				{ Id = "unlock_power", Type = "unlock", Room = "PowerRoom", Item = "Keycard", Text = "Unlock the generator room" },
				{
					Id = "fuel",
					Type = "deposit",
					Item = "FuelCan",
					Count = 2,
					Station = "Generator",
					Noise = "FuelPour",
					Text = "Refuel the generator (%d/%d)",
				},
				{
					Id = "start_generator",
					Type = "hold",
					Station = "Generator",
					Duration = 4,
					Noise = "GeneratorStart",
					NoiseInterval = 1.3,
					Text = "Crank the generator",
					Effects = { "PowerOn", "GeneratorRunning" },
					Unlocks = { "Security" },
				},
				{
					Id = "override",
					Type = "hold",
					Station = "Terminal",
					Duration = 6,
					Noise = "Terminal",
					NoiseInterval = 1.5,
					Text = "Run the exit override at the security terminal",
					Unlocks = { "Exit" },
				},
				{ Id = "extract", Type = "extract", Station = "ExitPanel", Text = "Call the service elevator and survive" },
			},
		},
	},

	-- Optional pickups per run.
	-- Batteries per run come from difficulty (Supplies); throwables are spread separately
	-- (count from difficulty Throwables) and every player starts with one bottle.
	Supplies = { Battery = 1 },
	Throwables = { Bottle = 0.45, Can = 0.4, AlarmClock = 0.15 },
	StartingItem = "Bottle",
	LoreNotesPerRun = 3,
	BlackBoxChance = 0.75, -- chance the optional black box spawns

	Extraction = {
		AlarmInterval = 3, -- alarm noise period while the elevator is on its way
		BoardingTime = 20, -- doors stay open this long (or until everyone alive is inside)
		AllAboardDelay = 3,
	},
}
