--[[
	ZoneConfig - zones are added here. A zone needs: bounds (for "which zone am I in"),
	an unlock requirement, a lighting preset and an ambient set. Its scrap comes from
	ScrapConfig entries with the matching Zone, and WorldBuilder builds its map.

	Only zones with Built = true exist in the world. The others are listed so the gate UI
	can show the road ahead; they are not empty placeholder maps.
]]

local ZoneConfig = {}

ZoneConfig.List = {
	{
		Id = "Rustyard",
		Name = "Rustyard",
		Description = "A sun-baked junkyard full of bolts, pipes and the odd rusty treasure.",
		Built = true,
		Center = { 0, 0, 0 },
		Size = { 300, 300 },
		Unlock = nil, -- starting zone
		MaxScrap = 150,
		Lighting = {
			ClockTime = 16.6,
			Brightness = 2.6,
			Ambient = { 118, 104, 92 },
			OutdoorAmbient = { 150, 132, 112 },
			FogColor = { 214, 182, 140 },
			FogEnd = 900,
			Tint = { 255, 238, 214 },
			Saturation = -0.08,
			Contrast = 0.08,
			AtmosphereColor = { 222, 190, 150 },
			AtmosphereDecay = { 160, 120, 90 },
			Density = 0.3,
			Haze = 1.4,
		},
		Ambient = { "Wind", "Machinery", "Creak" },
		Categories = "Cans, bolts, pipes, toolboxes, engines",
	},
	{
		Id = "MetroWreck",
		Name = "Metro Wreck",
		Description = "A wrecked city block at dusk: car doors, traffic lights and armored ATMs.",
		Built = true,
		Center = { 305, 0, 0 },
		Size = { 280, 260 },
		Unlock = { Coins = 15000, Strength = 6 },
		MaxScrap = 120,
		Lighting = {
			ClockTime = 18.1,
			Brightness = 1.8,
			Ambient = { 92, 96, 122 },
			OutdoorAmbient = { 110, 114, 140 },
			FogColor = { 120, 120, 156 },
			FogEnd = 700,
			Tint = { 230, 232, 255 },
			Saturation = -0.05,
			Contrast = 0.12,
			AtmosphereColor = { 150, 150, 190 },
			AtmosphereDecay = { 120, 90, 120 },
			Density = 0.34,
			Haze = 1.6,
		},
		Ambient = { "UrbanWind", "Hum" },
		Categories = "Hubcaps, traffic lights, car doors, ATMs",
	},
	{ Id = "IndustrialCore", Name = "Industrial Core", Description = "Coming in a future update.", Built = false, Unlock = { Coins = 1500000, Strength = 18 } },
	{ Id = "MilitarySalvage", Name = "Military Salvage", Description = "Coming in a future update.", Built = false, Unlock = { Coins = 20000000, Strength = 24 } },
	{ Id = "OrbitalGraveyard", Name = "Orbital Graveyard", Description = "Coming in a future update.", Built = false, Unlock = { Coins = 250000000, Strength = 30 } },
}

ZoneConfig.ById = {}
for index, zone in ipairs(ZoneConfig.List) do
	zone.Order = index
	ZoneConfig.ById[zone.Id] = zone
end

ZoneConfig.StartZone = "Rustyard"

-- Which built zone contains a world position (x, z)? Returns the zone id or nil.
function ZoneConfig.zoneAt(x, z)
	for _, zone in ipairs(ZoneConfig.List) do
		if zone.Built then
			local cx, cz = zone.Center[1], zone.Center[3]
			if math.abs(x - cx) <= zone.Size[1] / 2 and math.abs(z - cz) <= zone.Size[2] / 2 then
				return zone.Id
			end
		end
	end
	return nil
end

return ZoneConfig
