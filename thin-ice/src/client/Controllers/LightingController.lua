--[[
	LightingController - the night on the client.
	  * Fog thickens the further you walk out from the shore (Presence.fog), and closes in
	    hard in a whiteout. The camp stays clear and warm: the contrast is the point.
	  * A cold colour grade out on the ice, a warm glow when you stand by a fire, a frosty
	    tint while you're frozen or in the water.
	  * Never pitch black: the grade only darkens a little, and Reduced Effects caps the fog.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local Presence = require(Shared.Presence)

local ClientState = require(script.Parent.ClientState)

local LightingController = {}

local grade
local atmosphere

local COLD = Color3.fromRGB(220, 232, 255)
local CAMP = Color3.fromRGB(240, 238, 236)
local WARM = Color3.fromRGB(255, 226, 196)

-- Target values for the current situation (pure, tested). z: how far out you stand.
function LightingController.target(gust, frozen, inWater, reduced, z, nearFire)
	local density = Presence.fog(z or 0, gust, reduced)
	local onLake = (z or 0) > 40
	local tint = if onLake then COLD else CAMP
	local saturation = if onLake then -0.18 else -0.05
	local brightness = if onLake then -0.04 else 0.02
	if nearFire then
		tint = WARM
		saturation = 0.02
		brightness = 0.04
	end
	if frozen then
		tint = Color3.fromRGB(190, 225, 255)
		saturation = -0.5
	elseif inWater then
		tint = Color3.fromRGB(150, 190, 240)
		saturation = -0.3
	end
	return { density = density, tint = tint, saturation = saturation, brightness = brightness }
end

function LightingController.step(dt)
	local me = ClientState.me()
	local root = ClientState.root()
	local nearFire = ClientState.player():GetAttribute("TI_NearFire") == true
	local t = LightingController.target(workspace:GetAttribute("TI_Gust") == true, me.state == "Frozen", me.inWater, ClientState.setting("ReducedEffects") == true, root and root.Position.Z or 0, nearFire)
	local k = math.clamp((dt or 0.016) * 1.5, 0, 1)
	if atmosphere then
		atmosphere.Density += (t.density - atmosphere.Density) * k
	end
	if grade then
		grade.TintColor = grade.TintColor:Lerp(t.tint, k)
		grade.Saturation += (t.saturation - grade.Saturation) * k
		grade.Brightness += (t.brightness - grade.Brightness) * k
	end
	return t
end

function LightingController.init()
	grade = Lighting:FindFirstChild("TI_Grade")
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "TI_Grade"
		grade.Contrast = 0.1
		grade.Saturation = -0.1
		grade.TintColor = CAMP
		grade.Parent = Lighting
	end
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	RunService.RenderStepped:Connect(LightingController.step)
end

return LightingController
