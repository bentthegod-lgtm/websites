--[[
	EffectsController - atmosphere and feedback:
	  * falling snow around the camera (heavier in a blizzard gust, lighter with Reduced
	    Effects)
	  * dread: a dark vignette that closes in as the Antlered gets near you
	  * the catch scare (13+, tasteful): a split-second close-up of its blind face with a
	    cold white flash and a camera jolt. With Scare Effects off it is a gentle blue fade.
	  * camera shake when ice cracks / breaks close to you
	  * snowball arcs (the server tells everyone where a snowball was thrown)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local Models = require(Shared.Models)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local EffectsController = {}

local gui, vignette
local snowPart, snow
local shake = 0
local rng = Random.new()

function EffectsController.dread(distance)
	if not distance then
		return 0
	end
	return math.clamp(1 - (distance - 6) / 50, 0, 1)
end

local function buildSnow()
	snowPart = Instance.new("Part")
	snowPart.Name = "TI_Snow"
	snowPart.Anchored = true
	snowPart.CanCollide = false
	snowPart.CanQuery = false
	snowPart.CanTouch = false
	snowPart.Transparency = 1
	snowPart.Size = Vector3.new(90, 1, 90)
	snowPart.Parent = workspace
	snow = Instance.new("ParticleEmitter")
	snow.Name = "Snow"
	snow.Color = ColorSequence.new(Color3.fromRGB(240, 246, 255))
	snow.LightEmission = 0.4
	snow.Size = NumberSequence.new(0.18)
	snow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	snow.Lifetime = NumberRange.new(5, 7)
	snow.Speed = NumberRange.new(4, 7)
	snow.SpreadAngle = Vector2.new(20, 20)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Rate = 160
	snow.Parent = snowPart
end

function EffectsController.snowRate(gust, reduced)
	local rate = if gust then 600 else 160
	if reduced then
		rate *= 0.35
	end
	return rate
end

-- The catch scare. Returns the overlay frame (destroyed after ~1 s).
function EffectsController.scare(full)
	local overlay = Ui.new("Frame", { Name = "Scare", Size = UDim2.fromScale(1, 1), BackgroundColor3 = if full then Color3.fromRGB(230, 244, 255) else Color3.fromRGB(120, 170, 230), BackgroundTransparency = if full then 0 else 0.4, ZIndex = 50, Parent = gui })
	if full then
		local view = Ui.new("ViewportFrame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(120, 140, 170), LightColor = Color3.fromRGB(220, 235, 255), LightDirection = Vector3.new(0, -0.4, -1), ZIndex = 51, Parent = overlay })
		local monster = Models.monster(CFrame.new(), nil)
		monster.Parent = view
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 12.6, -8), Vector3.new(0, 12.4, -1.6))
		camera.Parent = view
		view.CurrentCamera = camera
		shake = math.max(shake, 1)
	end
	TweenService:Create(overlay, TweenInfo.new(if full then 0.9 else 1.4), { BackgroundTransparency = 1 }):Play()
	task.delay(if full then 0.75 else 1.4, function()
		overlay:Destroy()
	end)
	return overlay
end

function EffectsController.throwArc(from, to)
	local ball = Instance.new("Part")
	ball.Name = "Snowball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.9, 0.9, 0.9)
	ball.Color = Color3.fromRGB(245, 248, 255)
	ball.Material = Enum.Material.Snow
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CFrame = CFrame.new(from + Vector3.new(0, 2, 0))
	ball.Parent = workspace
	local start = os.clock()
	local duration = 0.9
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / duration, 0, 1)
		local p = from:Lerp(to, t) + Vector3.new(0, 2 + math.sin(t * math.pi) * 10, 0)
		ball.CFrame = CFrame.new(p)
		if t >= 1 then
			conn:Disconnect()
			ball:Destroy()
		end
	end)
	return ball
end

function EffectsController.step(dt)
	local camera = workspace.CurrentCamera
	local gust = workspace:GetAttribute("TI_Gust") == true
	local reduced = ClientState.setting("ReducedEffects") == true
	if snowPart and camera then
		snowPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 25, 0))
		snow.Rate = EffectsController.snowRate(gust, reduced)
	end
	-- Dread vignette.
	local root = ClientState.root()
	local monster = ClientState.monster()
	local body = monster and monster.PrimaryPart
	local bodyPos = body and monster:GetPivot().Position
	local d = nil
	if root and body then
		d = (Vector3.new(bodyPos.X, 0, bodyPos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	end
	local dread = EffectsController.dread(d)
	if vignette then
		vignette.BackgroundTransparency = 1 - dread * 0.55
	end
	-- Camera shake.
	if shake > 0 and camera then
		if ClientState.setting("CameraShake") ~= false then
			local s = shake * 0.4
			camera.CFrame = camera.CFrame * CFrame.Angles(rng:NextNumber(-s, s) * 0.05, rng:NextNumber(-s, s) * 0.05, 0)
		end
		shake = math.max(0, shake - dt * 2.5)
	end
	return dread
end

function EffectsController.init()
	gui = Ui.screen("IceFx", 20)
	gui.IgnoreGuiInset = true
	vignette = Ui.new("Frame", { Name = "Dread", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 4, 14), BackgroundTransparency = 1, Parent = gui })
	Ui.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.35, 0.85), NumberSequenceKeypoint.new(0.65, 0.85), NumberSequenceKeypoint.new(1, 0) }), Parent = vignette })
	buildSnow()
	ClientState.MonsterCue:Connect(function(kind)
		if kind == "Caught" then
			EffectsController.scare(ClientState.setting("ScareEffects") ~= false)
		end
	end)
	ClientState.WorldSound:Connect(function(category, position, extra)
		if category == "Throw" and typeof(position) == "Vector3" and typeof(extra) == "Vector3" then
			EffectsController.throwArc(position, extra)
		elseif (category == "Crack" or category == "Break") and typeof(position) == "Vector3" then
			local root = ClientState.root()
			if root and (root.Position - position).Magnitude < 14 then
				shake = math.max(shake, if category == "Break" then 0.9 else 0.4)
			end
		end
	end)
	RunService.RenderStepped:Connect(EffectsController.step)
end

return EffectsController
