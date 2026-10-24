--[[
	Arena themes. Arenas are built procedurally by ArenaBuilder at Origin and rotated each
	round. Lighting is applied on the client while the local player is in (or watching)
	the arena; the lobby has its own look.
]]

return {
	Origin = { 0, 0, 900 }, -- arenas are built far from the lobby
	Radius = 70,
	Order = { "FloatingIsland", "NeonGrid", "Volcano", "FrostRing" },

	Themes = {
		FloatingIsland = {
			Name = "Sky Isle",
			Floor = { 96, 170, 72 },
			FloorMaterial = "Grass",
			Edge = { 120, 92, 70 },
			EdgeMaterial = "Rock",
			Accent = { 255, 230, 140 },
			Lighting = { ClockTime = 14, Brightness = 2.6, Ambient = { 120, 130, 140 }, Fog = { 190, 220, 255 }, FogEnd = 1200, Atmosphere = 0.28 },
		},
		NeonGrid = {
			Name = "Neon Grid",
			Floor = { 18, 18, 32 },
			FloorMaterial = "SmoothPlastic",
			Edge = { 40, 10, 70 },
			EdgeMaterial = "Metal",
			Accent = { 255, 60, 220 },
			Accent2 = { 60, 220, 255 },
			Lighting = { ClockTime = 0, Brightness = 0.5, Ambient = { 70, 50, 110 }, Fog = { 20, 0, 40 }, FogEnd = 700, Atmosphere = 0.35 },
		},
		Volcano = {
			Name = "Magma Crater",
			Floor = { 60, 50, 48 },
			FloorMaterial = "Basalt",
			Edge = { 40, 30, 30 },
			EdgeMaterial = "Basalt",
			Accent = { 255, 90, 20 },
			Lighting = { ClockTime = 18.2, Brightness = 1.2, Ambient = { 120, 60, 40 }, Fog = { 80, 30, 20 }, FogEnd = 600, Atmosphere = 0.45 },
		},
		FrostRing = {
			Name = "Frost Ring",
			Floor = { 220, 235, 255 },
			FloorMaterial = "Ice",
			Edge = { 150, 180, 210 },
			EdgeMaterial = "Glacier",
			Accent = { 120, 220, 255 },
			Lighting = { ClockTime = 9, Brightness = 2.2, Ambient = { 150, 170, 200 }, Fog = { 210, 230, 255 }, FogEnd = 900, Atmosphere = 0.3 },
		},
	},

	Lobby = {
		Origin = { 0, 0, 0 },
		Lighting = { ClockTime = 15.5, Brightness = 2.4, Ambient = { 120, 120, 140 }, Fog = { 200, 210, 240 }, FogEnd = 1500, Atmosphere = 0.25 },
	},
}
