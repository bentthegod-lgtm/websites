--[[
	WeatherController - client-side visuals for the server's weather (workspace attribute
	SV_Weather): lighting / fog / sky colour tweens, falling particles around the camera
	(rain, snow, golden motes, embers), a giant moon for night events, aurora ribbons and
	storm flicker. Purely cosmetic; the gameplay effects are on the server.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local WeatherConfig = require(Shared.Config.WeatherConfig)

local Audio = require(script.Parent.Audio)

local WeatherController = {}

local folder, emitterPart, emitter, moon, auroraParts
local currentKey = ""

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local PARTICLES = {
	Rain = { Color = { 170, 200, 255 }, Rate = 450, Speed = { 70, 85 }, Lifetime = { 0.9, 1.2 }, Size = 0.18, Spread = 4, Transparency = 0.35, Squash = 3 },
	Snow = { Color = { 255, 255, 255 }, Rate = 220, Speed = { 6, 10 }, Lifetime = { 5, 7 }, Size = 0.4, Spread = 25, Transparency = 0.1, RotSpeed = 60 },
	Motes = { Color = { 255, 215, 110 }, Rate = 70, Speed = { 2, 4 }, Lifetime = { 5, 8 }, Size = 0.3, Spread = 60, Transparency = 0.2, Light = 1 },
	Embers = { Color = { 255, 70, 70 }, Rate = 60, Speed = { 3, 6 }, Lifetime = { 5, 8 }, Size = 0.28, Spread = 50, Transparency = 0.2, Light = 1 },
	Aurora = { Color = { 140, 255, 210 }, Rate = 40, Speed = { 1, 3 }, Lifetime = { 6, 9 }, Size = 0.3, Spread = 80, Transparency = 0.3, Light = 1 },
}

local function setParticles(kind)
	local def = PARTICLES[kind]
	if not def then
		emitter.Enabled = false
		return
	end
	emitter.Enabled = true
	emitter.Color = ColorSequence.new(rgb(def.Color))
	emitter.Rate = def.Rate
	emitter.Speed = NumberRange.new(def.Speed[1], def.Speed[2])
	emitter.Lifetime = NumberRange.new(def.Lifetime[1], def.Lifetime[2])
	emitter.Size = NumberSequence.new(def.Size)
	emitter.SpreadAngle = Vector2.new(def.Spread, def.Spread)
	emitter.Transparency = NumberSequence.new(def.Transparency)
	emitter.LightEmission = def.Light or 0
	emitter.RotSpeed = NumberRange.new(-(def.RotSpeed or 0), def.RotSpeed or 0)
	emitter.Orientation = if def.Squash then Enum.ParticleOrientation.VelocityParallel else Enum.ParticleOrientation.FacingCamera
	pcall(function()
		-- Stretches raindrops into streaks (newer engine property; skipped if missing).
		emitter.Squash = NumberSequence.new(def.Squash and -def.Squash or 0)
	end)
end

local function tweenLighting(preset)
	local info = TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, info, {
		ClockTime = preset.ClockTime,
		Brightness = preset.Brightness,
		Ambient = rgb(preset.Ambient),
		OutdoorAmbient = rgb(preset.OutdoorAmbient),
		FogColor = rgb(preset.Fog),
	}):Play()
	local atmosphere = Lighting:FindFirstChild("SV_Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, { Color = rgb(preset.Fog), Haze = preset.Haze, Density = preset.Density }):Play()
	end
	local grade = Lighting:FindFirstChild("SV_Grade")
	if grade then
		TweenService:Create(grade, info, { TintColor = rgb(preset.Tint), Saturation = preset.Saturation }):Play()
	end
end

local function setMoon(color)
	if color then
		moon.Color = color
		moon.Transparency = 0
	else
		moon.Transparency = 1
	end
end

local function setAurora(on)
	for _, p in ipairs(auroraParts) do
		p.Transparency = if on then 0.55 else 1
	end
end

function WeatherController.apply(key)
	currentKey = key or ""
	local def = WeatherConfig.Events[currentKey]
	tweenLighting(if def then def.Lighting else WeatherConfig.Clear)
	setParticles(def and def.Particles)
	setMoon(if currentKey == "BloodMoon" then Color3.fromRGB(230, 50, 50) elseif currentKey == "Aurora" then Color3.fromRGB(230, 240, 255) else nil)
	setAurora(currentKey == "Aurora")
	Audio.loop("RainLoop", currentKey == "Rain" or currentKey == "Thunderstorm")
	Audio.loop("WindLoop", currentKey == "Frost")
end

local function build()
	folder = Instance.new("Folder")
	folder.Name = "SproutWeather"
	folder.Parent = workspace
	emitterPart = Instance.new("Part")
	emitterPart.Name = "WeatherEmitter"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(140, 1, 140)
	emitterPart.Parent = folder
	emitter = Instance.new("ParticleEmitter")
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Enabled = false
	emitter.Parent = emitterPart

	moon = Instance.new("Part")
	moon.Name = "Moon"
	moon.Shape = Enum.PartType.Ball
	moon.Anchored = true
	moon.CanCollide = false
	moon.CanQuery = false
	moon.Material = Enum.Material.Neon
	moon.Size = Vector3.new(70, 70, 70)
	moon.Transparency = 1
	moon.CastShadow = false
	moon.Parent = folder

	auroraParts = {}
	local colors = { Color3.fromRGB(110, 255, 190), Color3.fromRGB(150, 120, 255), Color3.fromRGB(90, 230, 255) }
	for i = 1, 3 do
		local ribbon = Instance.new("Part")
		ribbon.Name = "Aurora"
		ribbon.Anchored = true
		ribbon.CanCollide = false
		ribbon.CanQuery = false
		ribbon.CastShadow = false
		ribbon.Material = Enum.Material.Neon
		ribbon.Color = colors[i]
		ribbon.Size = Vector3.new(500, 30, 1)
		ribbon.Transparency = 1
		ribbon.CFrame = CFrame.new(-20, 170 + i * 12, -60 - i * 40) * CFrame.Angles(math.rad(-15), 0, math.rad(4 * i))
		ribbon.Parent = folder
		table.insert(auroraParts, ribbon)
	end
end

function WeatherController.init()
	build()
	workspace:GetAttributeChangedSignal("SV_Weather"):Connect(function()
		WeatherController.apply(workspace:GetAttribute("SV_Weather"))
	end)
	WeatherController.apply(workspace:GetAttribute("SV_Weather"))
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local pos = camera.CFrame.Position
		emitterPart.CFrame = CFrame.new(pos.X, pos.Y + 45, pos.Z)
		if moon.Transparency < 1 then
			moon.CFrame = CFrame.new(pos + Vector3.new(-600, 420, -500))
		end
		if currentKey == "Aurora" then
			for i, p in ipairs(auroraParts) do
				p.CFrame = CFrame.new(pos.X - 20, 170 + i * 12 + math.sin(t * 0.5 + i) * 6, pos.Z - 160 - i * 40) * CFrame.Angles(math.rad(-15), math.sin(t * 0.2 + i) * 0.15, math.rad(4 * i))
				p.Transparency = 0.5 + math.sin(t + i * 2) * 0.15
			end
		elseif currentKey == "Thunderstorm" and math.random() < dt * 0.15 then
			local grade = Lighting:FindFirstChild("SV_Grade")
			if grade then
				grade.Brightness = 0.27
				TweenService:Create(grade, TweenInfo.new(0.3), { Brightness = 0.02 }):Play()
			end
		end
	end)
end

return WeatherController
