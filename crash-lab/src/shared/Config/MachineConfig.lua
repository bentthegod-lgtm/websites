--[[
	MachineConfig - the three launchers. Each one behaves differently:

	* Standard Launcher: catapult arm. Short prep, reliable, the angle you pick is the angle
	  you get. The beginner machine.
	* Spring Cannon: a coiled spring that compresses, then snaps. Much faster, but fires on
	  a FLATTER line (angle shifted down) with backspin, so the dummy skims, bounces and
	  slides a long way - great for ramps, barriers and distance.
	* Experimental Air Cannon: pressure builds behind a warning beacon, then a huge blast.
	  Fastest by far, fires on a STEEPER arc with a forward tumble - big height, rings,
	  long-range landing zones. Needs a heavier dummy class and a minimum pressure.

	BaseSpeed is studs/s at 100% power before upgrades. Speeds are clamped server-side to
	ScoringConfig.MaxLaunchSpeed whatever the upgrades.
	Unlock: coins + a real requirement checked by the server.
]]

local MachineConfig = {}

MachineConfig.Order = { "Standard", "Spring", "AirCannon" }

MachineConfig.ById = {
	Standard = {
		Id = "Standard",
		Name = "Standard Launcher",
		Short = "STANDARD",
		Description = "A reliable catapult arm. What you aim is what you get.",
		BaseSpeed = 112,
		AngleOffset = 0,
		MinPower = 0.25,
		ChargeTime = 0.8, -- prep: the arm cocks back
		Cooldown = 6,
		Spin = Vector3.new(0, 0, 0),
		LaunchHeight = 6.5,
		Cost = 0,
		Requirement = nil,
		Color = { 255, 196, 40 },
		Sound = { Charge = "StandardPrep", Fire = "StandardRelease" },
	},
	Spring = {
		Id = "Spring",
		Name = "Spring Cannon",
		Short = "SPRING",
		Description = "Compress, release, SNAP. Fast and flat with backspin: the dummy skims and slides.",
		BaseSpeed = 150,
		AngleOffset = -12, -- flatter trajectory than the angle you set
		MinPower = 0.3,
		ChargeTime = 1.35,
		Cooldown = 7,
		Spin = Vector3.new(-6, 0, 0), -- backspin (radians/s around the launch's right axis)
		LaunchHeight = 5.2, -- root height: the feet (RootHeight 4.43 below) must clear the 0.3-stud pad
		Cost = 2500,
		Requirement = { Stat = "BestDistance", Value = 140, Text = "Reach 140 studs in one run" },
		Color = { 70, 170, 255 },
		Sound = { Charge = "SpringCompress", Fire = "SpringSnap" },
	},
	AirCannon = {
		Id = "AirCannon",
		Name = "Experimental Air Cannon",
		Short = "AIR CANNON",
		Description = "Pressure builds, lights flash, then BOOM. Huge, steep arcs with a forward tumble.",
		BaseSpeed = 205,
		AngleOffset = 8, -- steeper arc
		MinPower = 0.5, -- the pressure vessel needs at least half pressure to fire
		ChargeTime = 2.6,
		Cooldown = 9,
		Spin = Vector3.new(9, 0, 0), -- forward tumble
		LaunchHeight = 7,
		Cost = 25000,
		Requirement = { Stat = "Payload", Value = 1, Text = "Own the Reinforced dummy (Payload 1)", AndStat = "BestDistance", AndValue = 300, AndText = "and reach 300 studs" },
		Color = { 235, 82, 60 },
		Sound = { Charge = "AirPressure", Fire = "AirBlast" },
	},
}

-- Dummy classes (unlocked by the Payload upgrade). Heavier dummies break sturdier
-- destructibles and bounce less (longer, lower tumbles); the launch speed is the same.
MachineConfig.Dummies = {
	{ Id = "Standard", Name = "Standard Dummy", Density = 0.7, Elasticity = 0.45, Break = 1 },
	{ Id = "Reinforced", Name = "Reinforced Dummy", Density = 1.1, Elasticity = 0.35, Break = 2 },
	{ Id = "Heavy", Name = "Heavy Dummy", Density = 1.6, Elasticity = 0.25, Break = 3 },
	{ Id = "Titan", Name = "Titan Dummy", Density = 2.4, Elasticity = 0.18, Break = 4 },
}

-- Spin modes (unlocked by the Spin upgrade). Added on top of the machine's own spin.
MachineConfig.SpinModes = {
	{ Id = "None", Name = "No spin", Level = 0, Spin = Vector3.new(0, 0, 0) },
	{ Id = "Flip", Name = "Flip", Level = 1, Spin = Vector3.new(8, 0, 0) },
	{ Id = "Corkscrew", Name = "Corkscrew", Level = 2, Spin = Vector3.new(0, 0, 10) },
	{ Id = "Chaos", Name = "Chaos", Level = 3, Spin = Vector3.new(7, 6, 9) },
}
MachineConfig.SpinById = {}
for _, mode in ipairs(MachineConfig.SpinModes) do
	MachineConfig.SpinById[mode.Id] = mode
end

return MachineConfig
