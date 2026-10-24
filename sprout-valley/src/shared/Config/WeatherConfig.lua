--[[
	Server-wide weather events. One starts every MinGap..MaxGap seconds (picked by Weight).
	During an event every plant that has reached the "full" stage rolls TickChance every
	TickInterval seconds to gain the event's Mutation. Thunderstorm also strikes one plant in
	the village with lightning every StrikeInterval seconds (guaranteed Shocked).

	Lighting / Sky values are applied on the client by WeatherController.
]]

return {
	MinGap = 600,
	MaxGap = 900,
	FirstEventDelay = 240,
	TickInterval = 8,
	Order = { "Rain", "Thunderstorm", "Frost", "GoldenHour", "BloodMoon", "Aurora" },
	Events = {
		Rain = {
			Name = "Rain",
			Weight = 40,
			Duration = 150,
			Growth = 1.5,
			Mutation = "Wet",
			TickChance = 0.05,
			Color = { 110, 170, 255 },
			Blurb = "Crops grow 50% faster and may turn Wet (2x).",
			Lighting = { ClockTime = 13, Brightness = 1.2, Ambient = { 120, 130, 150 }, OutdoorAmbient = { 110, 120, 140 }, Fog = { 150, 165, 185 }, Tint = { 220, 230, 255 }, Saturation = -0.1, Haze = 2.2, Density = 0.38 },
			Particles = "Rain",
		},
		Thunderstorm = {
			Name = "Thunderstorm",
			Weight = 22,
			Duration = 150,
			Growth = 1.5,
			Mutation = "Wet",
			TickChance = 0.04,
			StrikeInterval = 12,
			StrikeMutation = "Shocked",
			Color = { 255, 235, 90 },
			Blurb = "Lightning strikes gardens: Shocked fruit sells for 6x!",
			Lighting = { ClockTime = 18.2, Brightness = 0.7, Ambient = { 80, 85, 110 }, OutdoorAmbient = { 70, 75, 100 }, Fog = { 70, 75, 95 }, Tint = { 200, 205, 235 }, Saturation = -0.25, Haze = 3, Density = 0.5 },
			Particles = "Rain",
		},
		Frost = {
			Name = "Frost",
			Weight = 20,
			Duration = 150,
			Growth = 1,
			Mutation = "Chilled",
			TickChance = 0.05,
			Color = { 190, 235, 255 },
			Blurb = "Crops may turn Chilled (2x). Wet + Chilled = Frozen (8x)!",
			Lighting = { ClockTime = 9, Brightness = 2, Ambient = { 170, 190, 220 }, OutdoorAmbient = { 170, 195, 230 }, Fog = { 220, 235, 255 }, Tint = { 225, 240, 255 }, Saturation = -0.15, Haze = 1.4, Density = 0.32 },
			Particles = "Snow",
		},
		GoldenHour = {
			Name = "Golden Hour",
			Weight = 12,
			Duration = 120,
			Growth = 1.2,
			Variant = "Golden",
			TickChance = 0.012,
			Color = { 255, 200, 60 },
			Blurb = "A warm glow... fruit may turn Golden (10x)!",
			Lighting = { ClockTime = 17.6, Brightness = 2.6, Ambient = { 200, 160, 110 }, OutdoorAmbient = { 220, 170, 110 }, Fog = { 255, 205, 140 }, Tint = { 255, 225, 180 }, Saturation = 0.2, Haze = 1.2, Density = 0.3 },
			Particles = "Motes",
		},
		BloodMoon = {
			Name = "Blood Moon",
			Weight = 4,
			Duration = 150,
			Growth = 1,
			Mutation = "Bloodlit",
			TickChance = 0.04,
			Rare = true,
			Color = { 230, 50, 70 },
			Blurb = "RARE! The moon bleeds. Fruit may become Bloodlit (5x).",
			Lighting = { ClockTime = 0.5, Brightness = 1, Ambient = { 120, 40, 50 }, OutdoorAmbient = { 140, 40, 50 }, Fog = { 90, 20, 30 }, Tint = { 255, 190, 190 }, Saturation = 0.1, Haze = 2, Density = 0.4 },
			Particles = "Embers",
		},
		Aurora = {
			Name = "Aurora",
			Weight = 2,
			Duration = 150,
			Growth = 1.3,
			Mutation = "Aurora",
			TickChance = 0.03,
			Rare = true,
			Color = { 120, 255, 200 },
			Blurb = "RARE! Ribbons of light. Fruit may gain Aurora (9x).",
			Lighting = { ClockTime = 23, Brightness = 1.4, Ambient = { 70, 140, 140 }, OutdoorAmbient = { 80, 150, 160 }, Fog = { 30, 60, 80 }, Tint = { 210, 255, 240 }, Saturation = 0.3, Haze = 1, Density = 0.28 },
			Particles = "Aurora",
		},
	},
	-- Default sunny village day.
	Clear = { ClockTime = 14.5, Brightness = 2.4, Ambient = { 140, 135, 120 }, OutdoorAmbient = { 150, 150, 140 }, Fog = { 200, 225, 255 }, Tint = { 255, 250, 240 }, Saturation = 0.12, Haze = 0.6, Density = 0.22 },
}
