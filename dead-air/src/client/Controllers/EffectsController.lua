--[[
	EffectsController - local visual presentation.

	* Fluorescent flicker on faulty fixtures, and violent flicker near the Listener (an
	  early warning cue that it is close, even when you cannot see it). "Reduce flicker"
	  replaces strobing with a gentle dim.
	* Proximity vignette, downed blur/tint, caught flash, blackout dimming.
	* The local flashlight follows the camera exactly (other players see the server light).
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local MonsterConfig = require(Shared.Config.MonsterConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local Settings = require(script.Parent.Settings)

local EffectsController = {}

local player = Players.LocalPlayer
local lights = {}
local flickerUntil = {}
local vignette = {}
local flash
local blur, tint
local localLight, lightAnchor

local function trackLight(tube)
	local light = tube:FindFirstChildOfClass("PointLight")
	if light then
		lights[tube] = light
	end
end

local function buildVignette(gui)
	-- Four edge gradients (no image assets needed).
	local specs = {
		{ Vector2.new(0, 0), UDim2.new(1, 0, 0.35, 0), 90 },
		{ Vector2.new(0, 1), UDim2.new(1, 0, 0.35, 0), -90 },
		{ Vector2.new(0, 0), UDim2.new(0.3, 0, 1, 0), 0 },
		{ Vector2.new(1, 0), UDim2.new(0.3, 0, 1, 0), 180 },
	}
	for i, spec in ipairs(specs) do
		local frame = Ui.new("Frame", {
			AnchorPoint = spec[1],
			Position = UDim2.fromScale(spec[1].X, spec[1].Y),
			Size = spec[2],
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0,
			Parent = gui,
		})
		Ui.new("UIGradient", {
			Rotation = spec[3],
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Parent = frame,
		})
		vignette[i] = frame
	end
end

local function setVignette(strength)
	for _, frame in ipairs(vignette) do
		frame.BackgroundTransparency = 1 - math.clamp(strength, 0, 0.95)
	end
end

local function cosmeticColor()
	local profile = ClientState.profile
	local id = profile and profile.equipped or "Standard"
	for _, c in ipairs(ProgressionConfig.Cosmetics) do
		if c.Id == id then
			return Color3.fromRGB(c.Color[1], c.Color[2], c.Color[3])
		end
	end
	return Color3.fromRGB(255, 244, 214)
end

local function hideServerFlashlight(character)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	local function hook(light)
		if light:IsA("SpotLight") and light.Name == "DA_Flashlight" then
			light.Enabled = false
			light:GetPropertyChangedSignal("Enabled"):Connect(function()
				if light.Enabled then
					light.Enabled = false
				end
			end)
		end
	end
	for _, child in ipairs(head:GetChildren()) do
		hook(child)
	end
	head.ChildAdded:Connect(hook)
end

function EffectsController.init()
	local gui = Ui.screen("DeadAirEffects", player:WaitForChild("PlayerGui"), 2)
	buildVignette(gui)
	setVignette(0.35)
	flash = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 240, 230), BackgroundTransparency = 1, Parent = gui })

	blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = Lighting
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "DA_LocalTint"
	tint.Parent = Lighting

	lightAnchor = Instance.new("Part")
	lightAnchor.Name = "DA_LocalFlashlight"
	lightAnchor.Anchored = true
	lightAnchor.CanCollide = false
	lightAnchor.CanQuery = false
	lightAnchor.CanTouch = false
	lightAnchor.Transparency = 1
	lightAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	lightAnchor.Parent = Workspace.CurrentCamera
	localLight = Instance.new("SpotLight")
	localLight.Face = Enum.NormalId.Front
	localLight.Range = PlayerConfig.Flashlight.Range
	localLight.Angle = PlayerConfig.Flashlight.Angle
	localLight.Brightness = PlayerConfig.Flashlight.Brightness
	localLight.Shadows = true
	localLight.Enabled = false
	localLight.Parent = lightAnchor

	for _, tube in ipairs(CollectionService:GetTagged("DA_Light")) do
		trackLight(tube)
	end
	CollectionService:GetInstanceAddedSignal("DA_Light"):Connect(function(tube)
		task.defer(trackLight, tube)
	end)
	CollectionService:GetInstanceRemovedSignal("DA_Light"):Connect(function(tube)
		lights[tube] = nil
		flickerUntil[tube] = nil
	end)

	if player.Character then
		task.spawn(hideServerFlashlight, player.Character)
	end
	player.CharacterAdded:Connect(hideServerFlashlight)

	ClientState.MonsterCue:Connect(function(cue)
		if cue == "Caught" then
			flash.BackgroundTransparency = 0.1
			TweenService:Create(flash, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
		elseif cue == "Spotted" then
			flash.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
			flash.BackgroundTransparency = 0.6
			TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
			task.delay(0.7, function()
				flash.BackgroundColor3 = Color3.fromRGB(255, 240, 230)
			end)
		end
	end)
	ClientState.HorrorEvent:Connect(function(name, data)
		if name == "LightsFail" then
			for tube in pairs(lights) do
				if table.find(data.cells, tube:GetAttribute("Cell")) then
					flickerUntil[tube] = os.clock() + 0.6
				end
			end
		end
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local status = ClientState.status()
		-- Local flashlight follows the camera.
		local on = player:GetAttribute("DA_Flashlight") == true and status == "Alive" and not player:GetAttribute("DA_Hidden")
		localLight.Enabled = on
		if on then
			lightAnchor.CFrame = camera.CFrame * CFrame.new(0.6, -0.5, 0)
			localLight.Color = cosmeticColor()
		end

		accumulator += dt
		if accumulator < 0.08 then
			return
		end
		accumulator = 0

		local reduce = Settings.get("ReduceFlicker")
		local monster = ClientState.monster()
		local mroot = monster and monster.PrimaryPart
		local camPos = camera.CFrame.Position
		local now = os.clock()
		for tube, light in pairs(lights) do
			if tube.Parent and tube:GetAttribute("On") then
				local base = tube:GetAttribute("BaseBrightness") or 1
				local factor = 1
				if (tube.Position - camPos).Magnitude < 140 then
					local near = mroot and (tube.Position - mroot.Position).Magnitude < MonsterConfig.Cues.FlickerRadius
					if near then
						factor = if reduce then 0.35 else (if math.random() < 0.45 then 0.05 else 0.6 + math.random() * 0.4)
					elseif flickerUntil[tube] and now < flickerUntil[tube] then
						factor = if reduce then 0.5 else math.random() * 0.3
					elseif tube:GetAttribute("Flicker") then
						if reduce then
							factor = 0.85 + math.sin(now * 2 + tube.Position.X) * 0.1
						elseif math.random() < 0.06 then
							flickerUntil[tube] = now + 0.05 + math.random() * 0.25
							factor = 0.05
						end
					end
				end
				light.Brightness = base * factor
				tube.Transparency = if factor < 0.2 then 0.6 else 0
			end
		end

		-- Proximity vignette and tint.
		local strength = 0.35
		if mroot then
			local d = (mroot.Position - camPos).Magnitude
			strength += math.clamp(1 - d / 45, 0, 1) * 0.45
		end
		if status == "Downed" then
			strength = 0.85
		end
		if player:GetAttribute("DA_Hidden") then
			strength = math.max(strength, 0.6)
		end
		setVignette(strength)
		blur.Size = if status == "Downed" then 10 else 0
		tint.Saturation = if status == "Downed" then -0.6 elseif status == "Dead" then -1 else 0
		tint.TintColor = if status == "Downed" then Color3.fromRGB(255, 190, 180) else Color3.new(1, 1, 1)
	end)
end

return EffectsController
