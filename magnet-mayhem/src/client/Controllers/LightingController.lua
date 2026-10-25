--[[
	LightingController - zone atmosphere and the gate.

	* Tracks which zone you're in and blends Lighting / Atmosphere / colour grading to that
	  zone's preset (ZoneConfig.Lighting) - warm late afternoon in Rustyard, urban dusk in
	  Metro Wreck. Fires ClientState.ZoneChanged for the HUD toast and music.
	* The gate barrier is solid on the server; once YOUR profile has the zone, this client
	  makes it non-solid and see-through locally (your character is simulated on your
	  client, so you can walk through while locked players can't).
	* Broken street lamps flicker (lamps with a "Flicker" attribute).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local ZoneConfig = require(Shared.Config.ZoneConfig)

local ClientState = require(script.Parent.ClientState)

local LightingController = {}

local flickers = {}
local barrier

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

function LightingController.apply(zoneId, instant)
	local zone = ZoneConfig.ById[zoneId]
	local preset = zone and zone.Lighting
	if not preset then
		return
	end
	local info = TweenInfo.new(if instant then 0 else 3, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, {
		ClockTime = preset.ClockTime,
		Brightness = preset.Brightness,
		Ambient = rgb(preset.Ambient),
		OutdoorAmbient = rgb(preset.OutdoorAmbient),
		FogColor = rgb(preset.FogColor),
		FogEnd = preset.FogEnd,
	}):Play()
	local grade = Lighting:FindFirstChild("MM_Grade")
	if grade then
		TweenService:Create(grade, info, { TintColor = rgb(preset.Tint), Saturation = preset.Saturation, Contrast = preset.Contrast }):Play()
	end
	local atmosphere = Lighting:FindFirstChild("MM_Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, { Color = rgb(preset.AtmosphereColor), Decay = rgb(preset.AtmosphereDecay), Density = preset.Density, Haze = preset.Haze }):Play()
	end
end

local function updateBarrier(profile)
	if not barrier then
		local world = workspace:FindFirstChild("MagnetMayhemWorld")
		local gate = world and world:FindFirstChild("MetroGate")
		barrier = gate and gate:FindFirstChild("Barrier")
	end
	if barrier and profile then
		local open = profile.zones and profile.zones[barrier:GetAttribute("Zone")] == true
		barrier.CanCollide = not open
		barrier.Transparency = if open then 0.85 else 0.35
		barrier.Color = if open then Color3.fromRGB(110, 255, 160) else Color3.fromRGB(110, 160, 255)
	end
end
LightingController.updateBarrier = updateBarrier

function LightingController.check()
	local root = ClientState.root()
	if not root then
		return
	end
	local zoneId = ZoneConfig.zoneAt(root.Position.X, root.Position.Z)
	if zoneId and zoneId ~= ClientState.zone then
		ClientState.zone = zoneId
		LightingController.apply(zoneId, false)
		ClientState.ZoneChanged:Fire(zoneId)
	end
end

function LightingController.init()
	local world = workspace:FindFirstChild("MagnetMayhemWorld")
	if world then
		for _, d in ipairs(world:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("Flicker") then
				table.insert(flickers, { part = d, light = d:FindFirstChildOfClass("SpotLight"), seed = math.random() * 100 })
			end
		end
	end
	ClientState.ProfileChanged:Connect(updateBarrier)
	LightingController.apply(ClientState.zone, true)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			LightingController.check()
		end
		if ClientState.setting("ReducedEffects") then
			return
		end
		local t = os.clock()
		for _, f in ipairs(flickers) do
			local on = math.noise(t * 3, f.seed) > -0.25
			if f.light then
				f.light.Enabled = on
			end
			f.part.Transparency = if on then 0 else 0.6
		end
	end)
end

return LightingController
