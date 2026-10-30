--[[
	LightingController - the night on the client: a cold colour grade, fog that closes in
	during blizzard gusts, and a frosty tint while you are frozen or in the water.
	(Reduced Effects keeps the fog light.)
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.ClientState)

local LightingController = {}

local grade
local atmosphere

-- Target values for the current situation (pure, tested).
function LightingController.target(gust, frozen, inWater, reduced)
	local density = 0.32
	if gust then
		density = if reduced then 0.42 else 0.58
	end
	local tint = Color3.fromRGB(235, 242, 255)
	local saturation = -0.1
	if frozen then
		tint = Color3.fromRGB(190, 225, 255)
		saturation = -0.5
	elseif inWater then
		tint = Color3.fromRGB(150, 190, 240)
		saturation = -0.3
	end
	return { density = density, tint = tint, saturation = saturation }
end

function LightingController.step(dt)
	local me = ClientState.me()
	local t = LightingController.target(workspace:GetAttribute("TI_Gust") == true, me.state == "Frozen", me.inWater, ClientState.setting("ReducedEffects") == true)
	local k = math.clamp((dt or 0.016) * 2, 0, 1)
	if atmosphere then
		atmosphere.Density += (t.density - atmosphere.Density) * k
	end
	if grade then
		grade.TintColor = grade.TintColor:Lerp(t.tint, k)
		grade.Saturation += (t.saturation - grade.Saturation) * k
	end
	return t
end

function LightingController.init()
	grade = Lighting:FindFirstChild("TI_Grade")
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "TI_Grade"
		grade.Contrast = 0.08
		grade.Saturation = -0.1
		grade.TintColor = Color3.fromRGB(235, 242, 255)
		grade.Parent = Lighting
	end
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	RunService.RenderStepped:Connect(LightingController.step)
end

return LightingController
