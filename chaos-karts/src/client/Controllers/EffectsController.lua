--[[
	EffectsController - game feel.
	  * SPEED LINES streaking in from the screen edges at high speed and on boosts
	  * DRIFT SPARKS at the rear wheels: blue -> orange -> purple as the mini-turbo charges
	    (yours and everyone else's, from the replicated flags)
	  * BOOST FLAMES from the exhaust
	  * TIRE MARKS while drifting: a pooled, capped set of dark strips that fade
	  * SCREEN SHAKE on landings, wall hits and event stomps (the camera reads shakeOffset)
	  * a white flash on boost pads / big boosts
	Reduced Effects (Settings) turns the shake and speed lines down.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local KartStats = require(Shared.Config.KartStats)
local KartPhysics = require(Shared.KartPhysics)
local Parts = require(Shared.Parts)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local KartController = require(script.Parent.KartController)
local RemoteKarts = require(script.Parent.RemoteKarts)

local EffectsController = {}

local gui, lines, flash
local shake = 0
local shakeSeed = 0
local marks = {}
local markIndex = 0
local markAcc = 0
local markFolder
local rng = Random.new()
local DRIFT_COLORS = {}
for i, c in ipairs(GameConfig.Effects.DriftColors) do
	DRIFT_COLORS[i] = Color3.fromRGB(c[1], c[2], c[3])
end

function EffectsController.shake(amount)
	local scale = if ClientState.setting("CameraShake") == false then 0 elseif ClientState.setting("ReducedEffects") then 0.4 else 1
	shake = math.min(1.2, shake + amount * scale)
end

function EffectsController.shakeAmount()
	return shake
end

function EffectsController.shakeOffset()
	if shake <= 0.001 then
		return CFrame.new()
	end
	shakeSeed += 1
	local s = shake
	return CFrame.new(math.noise(shakeSeed * 0.31, 0, 0) * s, math.noise(0, shakeSeed * 0.29, 0) * s, 0) * CFrame.Angles(0, 0, math.noise(0, 0, shakeSeed * 0.23) * s * 0.03)
end

local function emitter(parent, name)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Rate = 60
	e.Lifetime = NumberRange.new(0.15, 0.3)
	e.Speed = NumberRange.new(10, 18)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.LightEmission = 1
	e.Parent = parent
	return e
end

-- Sparks / flames on a kart rig from its flags (used for my kart and the remote karts).
function EffectsController.kartVisuals(rig, flags, _speed, _dt)
	if not rig then
		return
	end
	if not rig.fx then
		rig.fx = { sparks = {} }
		for i, a in ipairs(rig.sparks) do
			rig.fx.sparks[i] = emitter(a, "DriftSparks")
		end
		if rig.exhaust then
			local flame = emitter(rig.exhaust, "BoostFlame")
			flame.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 80, 30))
			flame.Speed = NumberRange.new(14, 24)
			flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
			rig.fx.flame = flame
		end
	end
	local drifting = KartPhysics.hasFlag(flags, KartPhysics.Flags.Drifting)
	local level = KartPhysics.driftLevelOf(flags)
	for _, e in ipairs(rig.fx.sparks) do
		e.Enabled = drifting and level >= 1
		if level >= 1 then
			e.Color = ColorSequence.new(DRIFT_COLORS[math.min(level, 3)])
			e.Rate = 40 + level * 30
		end
	end
	if rig.fx.flame then
		rig.fx.flame.Enabled = KartPhysics.hasFlag(flags, KartPhysics.Flags.Boost)
	end
	rig.fx.drifting = drifting
	rig.fx.level = level
end

local function placeMark(pos, look)
	local cap = GameConfig.Effects.TireMarks.Max
	markIndex = markIndex % cap + 1
	local part = marks[markIndex]
	if not part then
		part = Parts.new({ Name = "TireMark", Size = Vector3.new(0.9, 0.05, 2.6), CFrame = CFrame.new(), Color = Color3.fromRGB(20, 20, 24), Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = markFolder })
		marks[markIndex] = part
	end
	part.CFrame = CFrame.lookAt(pos, pos + look)
	part.Transparency = 0.35
	part:SetAttribute("Born", os.clock())
	return part
end

function EffectsController.markCount()
	return #marks
end

local function buildGui()
	gui = Ui.screen("KartFx", 2)
	lines = {}
	for i = 1, 20 do
		local a = i / 20 * math.pi * 2
		local line = Ui.new("Frame", {
			Name = "SpeedLine",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.cos(a) * 0.45, 0.5 + math.sin(a) * 0.45),
			Size = UDim2.fromOffset(3, 90),
			Rotation = math.deg(a) + 90,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		lines[i] = { frame = line, angle = a, phase = rng:NextNumber() }
	end
	flash = Ui.new("Frame", { Name = "BoostFlash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 240, 200), BackgroundTransparency = 1, Parent = gui })
end

function EffectsController.onKartEvents(events)
	for _, e in ipairs(events) do
		if e.name == "land" then
			EffectsController.shake(math.clamp((e.value or 0) / 60, 0.1, 1) * GameConfig.Camera.ShakeLand)
		elseif e.name == "wall" then
			EffectsController.shake(math.clamp((e.value or 0) / 50, 0.1, 1) * GameConfig.Camera.ShakeWall)
		elseif e.name == "boost" or e.name == "pad" then
			EffectsController.flashT = 0.25
		elseif e.name == "effect" then
			EffectsController.shake(0.6)
		end
	end
end

function EffectsController.step(dt)
	shake = math.max(0, shake - dt * 2.5)
	local state = KartController.state()
	local intensity = 0
	if state then
		local speed = KartPhysics.speed(state)
		intensity = math.clamp((speed - KartStats.TopSpeed * 0.7) / (KartStats.TopSpeed * 0.5), 0, 1)
		if state.boostT > 0 then
			intensity = math.max(intensity, 0.9)
		end
		EffectsController.kartVisuals(KartController.rig(), KartPhysics.flags(state), speed, dt)
		-- tire marks under the rear wheels while drifting on the ground
		if state.drift ~= 0 and state.grounded then
			markAcc += dt
			if markAcc >= GameConfig.Effects.TireMarks.Every then
				markAcc = 0
				local cf = KartPhysics.cframe(state)
				for _, sx in ipairs({ -1, 1 }) do
					local p = cf * CFrame.new(sx * KartStats.WheelX, -KartStats.RideHeight + 0.04, KartStats.WheelZ)
					placeMark(p.Position, cf.LookVector)
				end
			end
		end
	end
	if ClientState.setting("SpeedLines") == false or ClientState.setting("ReducedEffects") then
		intensity *= 0.3
	end
	local t = os.clock()
	for _, l in ipairs(lines) do
		local wave = (t * 3 + l.phase) % 1
		l.frame.BackgroundTransparency = 1 - intensity * 0.55 * (1 - wave)
		l.frame.Size = UDim2.fromOffset(3, 60 + 120 * intensity)
	end
	EffectsController.flashT = math.max(0, (EffectsController.flashT or 0) - dt)
	flash.BackgroundTransparency = 1 - (EffectsController.flashT or 0) * 1.2
	-- fade tire marks
	local life = GameConfig.Effects.TireMarks.Life
	for _, m in ipairs(marks) do
		local born = m:GetAttribute("Born")
		if born then
			local age = os.clock() - born
			m.Transparency = math.clamp(0.35 + age / life * 0.65, 0.35, 1)
		end
	end
	return intensity
end

function EffectsController.speedLineIntensity()
	local total = 0
	for _, l in ipairs(lines) do
		total += 1 - l.frame.BackgroundTransparency
	end
	return total / #lines
end

function EffectsController.init()
	buildGui()
	markFolder = Instance.new("Folder")
	markFolder.Name = "CK_TireMarks"
	markFolder.Parent = workspace
	ClientState.KartEvents:Connect(EffectsController.onKartEvents)
	ClientState.KartEffected:Connect(function()
		EffectsController.shake(0.7)
	end)
	RemoteKarts.onVisuals = EffectsController.kartVisuals
end

return EffectsController
