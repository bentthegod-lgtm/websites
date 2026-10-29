--[[
	LightingPresets - the look of each facility. Lighting is one global service, so the
	server applies the hub's preset and each CLIENT re-applies the preset of the facility
	its character is in (LightingController). Changes made on a client stay local to it,
	so players in different facilities each see their own sky.

	apply(lighting, preset) sets the Lighting properties and the four effects the server
	created (CL_Atmosphere, CL_Grade, CL_Bloom, CL_SunRays), creating any that are missing.
]]

local rgb = Color3.fromRGB

local LightingPresets = {}

LightingPresets.IndustrialLab = {
	-- Bright, clean industrial daylight: warm sun, cool shadows, a little atmospheric depth.
	Lighting = { ClockTime = 14.2, GeographicLatitude = 30, Brightness = 2.4, Ambient = rgb(120, 122, 132), OutdoorAmbient = rgb(140, 144, 156), EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 0.55, ShadowSoftness = 0.2 },
	Atmosphere = { Density = 0.22, Offset = 0.1, Color = rgb(200, 210, 225), Decay = rgb(120, 130, 150), Glare = 0.2, Haze = 0.8 },
	Grade = { TintColor = rgb(255, 250, 242), Saturation = 0.05, Contrast = 0.07, Brightness = 0.02 },
	Bloom = { Intensity = 0.3, Size = 20, Threshold = 1.7 },
	SunRays = { Intensity = 0.04, Spread = 0.5 },
}

LightingPresets.HighAltitude = {
	-- Sunny mountain: high sun, crisp thin air, deep blue sky and a hazy canyon below.
	Lighting = { ClockTime = 11.4, GeographicLatitude = 41, Brightness = 3.1, Ambient = rgb(118, 128, 146), OutdoorAmbient = rgb(150, 162, 186), EnvironmentDiffuseScale = 0.6, EnvironmentSpecularScale = 0.6, ShadowSoftness = 0.12 },
	Atmosphere = { Density = 0.28, Offset = 0.05, Color = rgb(186, 210, 240), Decay = rgb(96, 128, 172), Glare = 0.45, Haze = 1.1 },
	Grade = { TintColor = rgb(246, 250, 255), Saturation = 0.12, Contrast = 0.1, Brightness = 0.03 },
	Bloom = { Intensity = 0.25, Size = 22, Threshold = 1.8 },
	SunRays = { Intensity = 0.09, Spread = 0.6 },
}

LightingPresets.Destruction = {
	-- Dusty orange floodlit yard at dusk: low sun, thick warm dust, floodlights doing the work.
	Lighting = { ClockTime = 17.7, GeographicLatitude = 25, Brightness = 1.6, Ambient = rgb(120, 92, 70), OutdoorAmbient = rgb(150, 112, 82), EnvironmentDiffuseScale = 0.4, EnvironmentSpecularScale = 0.35, ShadowSoftness = 0.3 },
	Atmosphere = { Density = 0.42, Offset = 0.2, Color = rgb(230, 160, 100), Decay = rgb(150, 90, 50), Glare = 0.3, Haze = 2.2 },
	Grade = { TintColor = rgb(255, 232, 205), Saturation = 0.08, Contrast = 0.12, Brightness = 0 },
	Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.6 },
	SunRays = { Intensity = 0.12, Spread = 0.8 },
}

LightingPresets.GravityLab = {
	-- Sci-fi night lab: dark room, cyan / purple neon, restrained bloom so the neon glows
	-- without washing the screen out.
	Lighting = { ClockTime = 0.3, GeographicLatitude = 0, Brightness = 0.8, Ambient = rgb(52, 46, 78), OutdoorAmbient = rgb(64, 58, 96), EnvironmentDiffuseScale = 0.3, EnvironmentSpecularScale = 0.7, ShadowSoftness = 0.4 },
	Atmosphere = { Density = 0.3, Offset = 0, Color = rgb(90, 70, 150), Decay = rgb(40, 30, 80), Glare = 0, Haze = 1.4 },
	Grade = { TintColor = rgb(232, 236, 255), Saturation = 0.15, Contrast = 0.14, Brightness = 0.02 },
	Bloom = { Intensity = 0.45, Size = 16, Threshold = 1.4 },
	SunRays = { Intensity = 0, Spread = 0.2 },
}

local EFFECTS = {
	{ key = "Atmosphere", class = "Atmosphere", name = "CL_Atmosphere" },
	{ key = "Grade", class = "ColorCorrectionEffect", name = "CL_Grade" },
	{ key = "Bloom", class = "BloomEffect", name = "CL_Bloom" },
	{ key = "SunRays", class = "SunRaysEffect", name = "CL_SunRays" },
}

function LightingPresets.apply(lighting, preset)
	if not preset then
		return false
	end
	for k, v in pairs(preset.Lighting) do
		lighting[k] = v
	end
	for _, e in ipairs(EFFECTS) do
		local props = preset[e.key]
		if props then
			local inst = lighting:FindFirstChild(e.name)
			if not inst then
				inst = Instance.new(e.class)
				inst.Name = e.name
				inst.Parent = lighting
			end
			for k, v in pairs(props) do
				inst[k] = v
			end
		end
	end
	return true
end

return LightingPresets
