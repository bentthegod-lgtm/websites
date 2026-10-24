--[[
	BallController - renders the server's ball smoothly.

	The server sends BallSync snapshots ~15 times a second. Between them the client
	predicts with the same BallMath the server uses (homing toward the target's replicated
	position), and blends any correction out over a few frames. The visual ball is a
	client-only model: it never decides anything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local GameConfig = require(Shared.Config.GameConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local BallMath = require(Shared.BallMath)
local CrateRoll = require(Shared.CrateRoll)
local Clock = require(Shared.Clock)

local ClientState = require(script.Parent.ClientState)

local BallController = {}

local B = GameConfig.Ball
local player = Players.LocalPlayer

local model, core, shell, light, trail, sparks, a0, a1
local sim -- { pos, dir, speed, curve, phase, target, slow }
local offset = Vector3.zero
local renderPos
local trailId
local hue = 0

local function makePart(name, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = model
	return p
end

local function build()
	model = Instance.new("Model")
	model.Name = "RR_BallVisual"
	core = makePart("Core", Vector3.new(2.4, 2.4, 2.4), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	shell = makePart("Shell", Vector3.new(3.6, 3.6, 3.6), Color3.fromRGB(255, 120, 220), Enum.Material.ForceField, 0.2)
	light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 3
	light.Shadows = false
	light.Parent = core
	a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = core
	a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = core
	trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = core
	sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 0
	sparks.LightEmission = 1
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(2, 6)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparks.Parent = core
	model.PrimaryPart = core
	model.Parent = nil
end

local function trailItem(id)
	return id and CrateRoll.find(CosmeticConfig, id) or CrateRoll.find(CosmeticConfig, "Basic")
end

local function applyTrail(id)
	if id == trailId then
		return
	end
	trailId = id
	local item = trailItem(id)
	local c1, c2 = item.Colors[1], item.Colors[2]
	trail.Color = ColorSequence.new(Color3.fromRGB(c1[1], c1[2], c1[3]), Color3.fromRGB(c2[1], c2[2], c2[3]))
	sparks.Rate = if item.Sparkles or item.Animated then 40 else 0
	sparks.Color = ColorSequence.new(Color3.fromRGB(c1[1], c1[2], c1[3]))
end

local function targetPosition(id)
	local m = ClientState.modelFor(id)
	local root = m and m:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

function BallController.position()
	return renderPos
end

function BallController.active()
	return sim ~= nil
end

function BallController.targetId()
	return sim and sim.target
end

function BallController.speed()
	return sim and sim.speed or 0
end

-- Distance from the ball to my character (nil if unknown).
function BallController.distanceToMe()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not renderPos then
		return nil
	end
	return (renderPos - root.Position).Magnitude
end

local function onSync(snapshot)
	if not snapshot or not snapshot.active then
		sim = nil
		renderPos = nil
		if model then
			model.Parent = nil
		end
		return
	end
	local fresh = {
		pos = snapshot.p,
		dir = snapshot.d,
		speed = snapshot.s,
		curve = snapshot.c or 0,
		phase = snapshot.ph,
		target = snapshot.t,
		slow = snapshot.slow or 1,
	}
	-- Advance the snapshot to "now" so it lines up with what we're rendering.
	local lag = math.clamp(Clock.now() - (snapshot.st or Clock.now()), 0, 0.3)
	if fresh.phase == "chasing" and lag > 0 then
		local tp = targetPosition(fresh.target)
		if tp then
			BallMath.step(fresh, tp, lag, B, fresh.slow)
		end
	end
	if renderPos and (renderPos - fresh.pos).Magnitude < 25 then
		offset = renderPos - fresh.pos
	else
		offset = Vector3.zero
	end
	sim = fresh
	applyTrail(snapshot.trail)
	if not model.Parent then
		model.Parent = workspace
	end
end

local function speedColor(speed)
	local t = math.clamp((speed - B.BaseSpeed) / (B.MaxSpeed - B.BaseSpeed), 0, 1)
	if t < 0.5 then
		return Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(255, 200, 60), t * 2)
	end
	return Color3.fromRGB(255, 200, 60):Lerp(Color3.fromRGB(255, 40, 40), (t - 0.5) * 2)
end

local function render(dt)
	if not sim or not model then
		return
	end
	if sim.phase == "chasing" then
		local tp = targetPosition(sim.target)
		if tp then
			BallMath.step(sim, tp, dt, B, sim.slow)
		end
	end
	offset *= math.exp(-dt * 12)
	renderPos = sim.pos + offset
	local t = os.clock()
	local wobble = if sim.phase == "charging" or sim.phase == "respawn" then Vector3.new(0, math.sin(t * 4) * 0.6, 0) else Vector3.zero
	model:PivotTo(CFrame.new(renderPos + wobble) * CFrame.Angles(t * 3, t * 5, 0))
	local color = speedColor(sim.speed)
	local mine = sim.target == ClientState.myId()
	if mine then
		color = color:Lerp(Color3.fromRGB(255, 30, 30), 0.5 + 0.5 * math.sin(t * 18))
	end
	if sim.slow < 1 then
		color = Color3.fromRGB(160, 230, 255)
	end
	core.Color = color
	shell.Color = color
	light.Color = color
	local charge = if sim.phase == "charging" or sim.phase == "respawn" then 1 + 0.15 * math.sin(t * 10) else 1
	shell.Size = Vector3.new(3.6, 3.6, 3.6) * charge
	light.Range = 14 + math.min(30, sim.speed / 8)
	local item = trailItem(trailId)
	if item.Animated then
		hue = (hue + dt * 0.6) % 1
		trail.Color = ColorSequence.new(Color3.fromHSV(hue, 1, 1), Color3.fromHSV((hue + 0.3) % 1, 1, 1))
	end
	trail.Lifetime = 0.25 + math.min(0.35, sim.speed / 600)
end

function BallController.init()
	build()
	applyTrail(nil)
	ClientState.BallSynced:Connect(onSync)
	ClientState.BallEvent:Connect(function(kind, data)
		if kind == "clear" then
			onSync({ active = false })
		elseif kind == "deflect" and sim then
			sim.target = data.to
			sim.speed = data.speed
			applyTrail(data.trail)
		elseif kind == "target" and sim then
			sim.target = data.id
		end
	end)
	RunService.RenderStepped:Connect(render)
	onSync(ClientState.ball)
end

-- For tests.
BallController._render = render
BallController._sync = onSync

return BallController
