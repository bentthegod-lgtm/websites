--[[
	Player movement, stamina, flashlight, inventory and survival rules.
]]

return {
	WalkSpeed = 10,
	SprintSpeed = 19,
	CrouchSpeed = 5, -- creeping: completely silent
	CrouchRunSpeed = 8, -- crouch + sprint key: faster, quiet but audible
	DownedSpeed = 1.5,
	CrouchCameraOffset = -1.8,

	Stamina = {
		Max = 100,
		SprintDrainPerSecond = 14, -- ~7 seconds of sprint
		RegenPerSecond = 11,
		RegenDelay = 1.0, -- seconds after sprinting before regen starts
		ExhaustedRecoverAt = 30, -- after hitting 0, sprint is locked until this much returns
		PantingBelow = 40, -- hiding with less stamina than this makes audible breathing
	},

	Flashlight = {
		MaxBattery = 100,
		DrainPerSecond = 0.55, -- ~3 minutes per full battery
		BatteryPickupAmount = 55,
		Range = 46,
		Angle = 50,
		Brightness = 2.4,
	},

	Inventory = {
		Capacity = 5,
	},

	Throw = {
		Speed = 62,
		UpBoost = 14,
		MaxFlightTime = 2.5,
		Cooldown = 1.0,
	},

	Downed = {
		ReviveHoldTime = 4,
		ReviveDistance = 7,
	},

	Interaction = {
		MaxDistance = 9, -- server-side distance check for prompt interactions
		MinInterval = 0.2, -- per-player interaction rate limit
	},

	-- Server noise tick for movement analysis.
	MovementTick = 0.1,
}
