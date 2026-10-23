--[[
	EffectsController - local visual presentation.

	* Fluorescent flicker on faulty fixtures, and violent flicker near the Listener (an
	  early warning cue that it is close, even when you cannot see it). "Reduce flicker"
	  replaces strobing with a gentle dim.
	* Proximity vignette, downed blur/tint, caught flash, blackout dimming.
	* The first-person flashlight viewmodel: held in view, beam from its lens, click on
	  toggle, stutters when the battery is nearly dead (other players see the server one).
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
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)
local FlashlightModel = require(Shared.FlashlightModel)

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
local localLight, viewmodel, viewLens, viewGlow
local swayPhase, raiseUntil, batteryDropUntil = 0, 0, 0

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

-- The server mounts a flashlight on every character for other players to see. Locally we
-- hide our own copy (light and model) and show the first-person viewmodel instead.
local function hideServerFlashlight(character)
	local function hook(d)
		if d:IsA("SpotLight") and d.Name == "DA_Flashlight" then
			d.Enabled = false
			d:GetPropertyChangedSignal("Enabled"):Connect(function()
				if d.Enabled then
					d.Enabled = false
				end
			end)
		elseif d:IsA("BasePart") and d:FindFirstAncestor("DA_FlashlightModel") then
			d.Transparency = 1
		end
	end
	for _, d in ipairs(character:GetDescendants()) do
		hook(d)
	end
	character.DescendantAdded:Connect(hook)
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

	-- First-person flashlight viewmodel; the beam comes from its lens.
	viewmodel, viewLens = FlashlightModel.build("DA_Viewmodel")
	for _, d in ipairs(viewmodel:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	localLight = Instance.new("SpotLight")
	localLight.Face = Enum.NormalId.Front
	localLight.Range = PlayerConfig.Flashlight.Range
	localLight.Angle = PlayerConfig.Flashlight.Angle
	localLight.Brightness = PlayerConfig.Flashlight.Brightness
	localLight.Shadows = true
	localLight.Enabled = false
	localLight.Parent = viewLens
	-- A soft glow so the lens reads as lit even when pointed at open space.
	local glow = Instance.new("PointLight")
	glow.Range = 3
	glow.Brightness = 0.4
	glow.Enabled = false
	glow.Parent = viewLens
	viewGlow = glow
	player:GetAttributeChangedSignal("DA_Flashlight"):Connect(function()
		raiseUntil = os.clock() + 0.18
		if ClientState.status() == "Alive" then
			AudioUtil.play2D(AudioAssets.FlashlightClick, "SFX")
		end
	end)

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
		-- First-person flashlight: held whenever you are alive in a run, lit when switched on.
		local holding = status == "Alive" and ClientState.roundState == "Playing" and not player:GetAttribute("DA_Hidden")
		local on = holding and player:GetAttribute("DA_Flashlight") == true
		if holding then
			if viewmodel.Parent ~= camera then
				viewmodel.Parent = camera
			end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
			swayPhase += dt * (1 + speed * 0.5)
			local amp = if Settings.get("HeadBob") then math.clamp(speed / 20, 0.05, 1) else 0.05
			local raise = if os.clock() < raiseUntil then 0.06 else 0
			local offset = CFrame.new(0.85 + math.sin(swayPhase * 0.5) * 0.04 * amp, -0.8 + math.abs(math.cos(swayPhase * 0.5)) * 0.05 * amp + raise, -1.7)
			viewmodel:PivotTo(camera.CFrame * offset * CFrame.Angles(math.rad(3), math.rad(4), 0))
		elseif viewmodel.Parent then
			viewmodel.Parent = nil
		end

		-- Dying battery: the beam stutters (a gentle dim with "Reduce flicker").
		local battery = player:GetAttribute("DA_Battery") or 100
		local level = 1
		if on and battery < 15 then
			if Settings.get("ReduceFlicker") then
				level = 0.55
			elseif os.clock() < batteryDropUntil then
				level = 0.08
			elseif math.random() < dt * (1.5 - battery / 15) then
				batteryDropUntil = os.clock() + 0.05 + math.random() * 0.2
			end
		end
		localLight.Enabled = on
		viewGlow.Enabled = on
		if on then
			local color = cosmeticColor()
			localLight.Color = color
			localLight.Brightness = PlayerConfig.Flashlight.Brightness * level
			FlashlightModel.setLens(viewLens, level > 0.3, color)
		else
			FlashlightModel.setLens(viewLens, false)
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
