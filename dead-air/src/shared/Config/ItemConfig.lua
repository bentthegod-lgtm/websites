--[[
	Carryable items. Colour/size are for the procedurally built pickup models.
	DropNoise is the noise category when the item hits the floor.
]]

return {
	Keycard = {
		DisplayName = "Security Keycard",
		Color = { 70, 120, 200 },
		Size = { 0.9, 0.08, 1.3 },
		Glow = { 90, 150, 255 },
		DropNoise = "ItemDrop",
		Objective = true,
	},
	Fuse = {
		DisplayName = "Fuse",
		Color = { 196, 120, 48 },
		Size = { 0.5, 1.4, 0.5 },
		Glow = { 255, 150, 60 },
		DropNoise = "MetalDrop",
		Objective = true,
	},
	FuelCan = {
		DisplayName = "Fuel Can",
		Color = { 150, 36, 30 },
		Size = { 1.4, 1.8, 0.8 },
		Glow = { 255, 80, 60 },
		DropNoise = "MetalDrop",
		Objective = true,
	},
	Bottle = {
		DisplayName = "Glass Bottle",
		Color = { 70, 110, 70 },
		Size = { 0.45, 1.2, 0.45 },
		Glow = nil,
		DropNoise = "GlassBreak",
		Throwable = true,
		ImpactNoise = "GlassBreak", -- loudest lure, but it shatters (single use)
		Breaks = true,
		Transparency = 0.25,
	},
	Can = {
		DisplayName = "Tin Can",
		Color = { 150, 152, 144 },
		Size = { 0.5, 0.8, 0.5 },
		Glow = nil,
		DropNoise = "CanClatter",
		Throwable = true,
		ImpactNoise = "CanClatter", -- clatters where it lands; pick it up and throw it again
	},
	AlarmClock = {
		DisplayName = "Alarm Clock",
		Color = { 168, 42, 36 },
		Size = { 0.8, 0.8, 0.45 },
		Glow = { 255, 120, 90 },
		DropNoise = "ItemDrop",
		Throwable = true,
		ImpactNoise = "ItemDrop",
		-- Keeps ringing after it lands, holding the Listener's attention (until picked up).
		Ring = { Category = "AlarmClock", Interval = 1.3, Count = 6 },
	},
	BlackBox = {
		DisplayName = "Black Box Recorder",
		Color = { 30, 30, 32 },
		Size = { 1.6, 1.0, 1.2 },
		Glow = { 255, 40, 40 },
		DropNoise = "MetalDrop",
		Optional = true,
	},
	-- Consumed on pickup (not stored in inventory).
	Battery = {
		DisplayName = "Battery",
		Color = { 40, 40, 40 },
		Size = { 0.4, 0.9, 0.4 },
		Glow = { 140, 255, 140 },
		Consumable = true,
	},
}
