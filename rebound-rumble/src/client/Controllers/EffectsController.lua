--[[
	EffectsController - all the flash: parry weapon swings, explosions (or confetti during a
	Server Explosion Party), shield pops, freeze shells, swap warps, win fireworks and
	camera shake. Everything here is client-side and purely visual.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)
local CrateRoll = require(Shared.CrateRoll)
local WeaponModels = require(Shared.WeaponModels)

local ClientState = require(script.Parent.ClientState)
local BallController = require(script.Parent.BallController)

local EffectsController = {
	shakeEnabled = true,
}

local player = Players.LocalPlayer
local fxFolder
local shakeAmount, shakeUntil = 0, 0

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function fxPart(props)
	local p = Instance.new("Part")
	p.Anchored = props.Anchored ~= false
	p.CanCollide = props.CanCollide == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = props.Material or Enum.Material.Neon
	p.Color = props.Color or Color3.new(1, 1, 1)
	p.Size = props.Size or Vector3.new(1, 1, 1)
	p.Transparency = props.Transparency or 0
	if props.Shape then
		p.Shape = props.Shape
	end
	p.CFrame = props.CFrame or CFrame.new()
	p.Parent = fxFolder
	Debris:AddItem(p, props.Life or 2)
	return p
end

local function tween(instance, time, goals, style)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	t:Play()
	return t
end

function EffectsController.shake(amount, duration)
	if not EffectsController.shakeEnabled then
		return
	end
	shakeAmount = math.max(shakeAmount, amount)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

local function rootOf(id)
	local m = ClientState.modelFor(id)
	return m and m:FindFirstChild("HumanoidRootPart")
end

local function burst(position, color, count, speed)
	local holder = fxPart({ Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(position), Transparency = 1, Life = 2 })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.3, 0.8)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(count)
end

---------------------------------------------------------------------------------------------
-- Parry swing
---------------------------------------------------------------------------------------------

function EffectsController.swing(id, itemId, ok)
	local root = rootOf(id)
	if not root then
		return
	end
	local item = CrateRoll.find(CosmeticConfig, itemId or "Blade") or CrateRoll.find(CosmeticConfig, "Blade")
	local weapon = WeaponModels.build(item)
	weapon.Parent = fxFolder
	local start = os.clock()
	local duration = 0.2
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.clamp((os.clock() - start) / duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		if not root.Parent then
			connection:Disconnect()
			weapon:Destroy()
			return
		end
		-- Sweep from the right shoulder across the front of the body.
		local angle = math.rad(-110 + 220 * eased)
		local cf = root.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -1.4) * CFrame.Angles(math.rad(-80), 0, 0)
		weapon:PivotTo(cf)
		if alpha >= 1 then
			connection:Disconnect()
			task.delay(0.08, function()
				weapon:Destroy()
			end)
		end
	end)
	-- Swing arc ribbon.
	local arc = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 9, 9),
		CFrame = root.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(item.Color),
		Transparency = if ok then 0.35 else 0.75,
		Life = 0.4,
	})
	tween(arc, 0.3, { Transparency = 1, Size = Vector3.new(0.05, 12, 12) })
	if ok then
		local pos = BallController.position() or root.Position
		burst(pos, rgb(item.Color), 30, 40)
		local flash = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(pos), Color = Color3.new(1, 1, 1), Life = 0.4 })
		tween(flash, 0.25, { Size = Vector3.new(10, 10, 10), Transparency = 1 })
		if id == ClientState.myId() then
			AudioUtil.play(AudioAssets.Parry, nil, 0.05)
			EffectsController.shake(0.35, 0.15)
		else
			AudioUtil.play(AudioAssets.ParryRemote, root, 0.08)
		end
	elseif id == ClientState.myId() then
		AudioUtil.play(AudioAssets.Whiff)
	end
end

---------------------------------------------------------------------------------------------
-- Explosions
---------------------------------------------------------------------------------------------

local function confetti(position)
	for _, c in ipairs(CosmeticConfig.ConfettiColors) do
		burst(position, rgb(c), 25, 45)
	end
	for i = 1, 30 do
		local piece = fxPart({
			Anchored = false,
			Material = Enum.Material.SmoothPlastic,
			Size = Vector3.new(0.6, 0.08, 0.35),
			CFrame = CFrame.new(position + Vector3.new(0, 2, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Color = rgb(CosmeticConfig.ConfettiColors[(i % #CosmeticConfig.ConfettiColors) + 1]),
			Life = 4,
		})
		piece.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(30, 60), math.random(-30, 30))
		piece.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
	end
	AudioUtil.play(AudioAssets.Confetti)
end

function EffectsController.explode(data)
	local position = data.pos
	if typeof(position) ~= "Vector3" then
		return
	end
	if data.confetti then
		confetti(position)
	else
		local color = if data.color then rgb(data.color) else Color3.fromRGB(255, 140, 40)
		local sphere = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(position), Color = color, Life = 1 })
		tween(sphere, 0.45, { Size = Vector3.new(22, 22, 22), Transparency = 1 })
		local core = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(position), Color = Color3.new(1, 1, 1), Life = 1 })
		tween(core, 0.25, { Size = Vector3.new(12, 12, 12), Transparency = 1 })
		local ring = fxPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4, 4), CFrame = CFrame.new(position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Life = 1 })
		tween(ring, 0.5, { Size = Vector3.new(0.1, 40, 40), Transparency = 1 })
		for i = 1, 12 do
			local shard = fxPart({
				Anchored = false,
				Size = Vector3.new(0.6, 0.6, 0.6) * (0.6 + math.random()),
				CFrame = CFrame.new(position),
				Color = if data.rainbow then Color3.fromHSV(i / 12, 1, 1) else color,
				Life = 2.5,
			})
			shard.AssemblyLinearVelocity = Vector3.new(math.random(-50, 50), math.random(30, 80), math.random(-50, 50))
		end
		burst(position, color, 60, 50)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 40
		light.Brightness = 6
		light.Parent = core
		AudioUtil.play(AudioAssets.Explosion, sphere)
	end
	-- Camera punch scaled by distance.
	local camera = workspace.CurrentCamera
	if camera then
		local d = (camera.CFrame.Position - position).Magnitude
		EffectsController.shake(math.clamp(1.6 - d / 60, 0.1, 1.6), 0.4)
	end
	if data.victim == ClientState.myId() then
		AudioUtil.play(AudioAssets.Eliminated)
	end
end

---------------------------------------------------------------------------------------------
-- Abilities / misc
---------------------------------------------------------------------------------------------

function EffectsController.shieldPop(data)
	local root = rootOf(data.id)
	local pos = if root then root.Position else data.pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	local bubble = fxPart({ Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Size = Vector3.new(7, 7, 7), CFrame = CFrame.new(pos), Color = Color3.fromRGB(255, 215, 100), Life = 1 })
	tween(bubble, 0.5, { Size = Vector3.new(14, 14, 14), Transparency = 1 })
	burst(pos, Color3.fromRGB(255, 220, 120), 50, 35)
	AudioUtil.play(AudioAssets.ShieldBreak, bubble)
end

function EffectsController.freeze(data)
	local duration = data.duration or 1
	local shell = fxPart({ Shape = Enum.PartType.Ball, Material = Enum.Material.Ice, Size = Vector3.new(5, 5, 5), Color = Color3.fromRGB(170, 230, 255), Transparency = 0.3, Life = duration + 0.5 })
	local stop = os.clock() + duration
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local pos = BallController.position()
		if os.clock() > stop or not pos or not shell.Parent then
			connection:Disconnect()
			if shell.Parent then
				burst(shell.Position, Color3.fromRGB(200, 240, 255), 30, 25)
				shell:Destroy()
			end
			return
		end
		shell.CFrame = CFrame.new(pos)
	end)
	AudioUtil.play(AudioAssets.FreezeCast)
end

function EffectsController.swap(data)
	for _, pos in ipairs({ data.a, data.b }) do
		if typeof(pos) == "Vector3" then
			local pillar = fxPart({ Size = Vector3.new(4, 14, 4), CFrame = CFrame.new(pos), Color = Color3.fromRGB(200, 140, 255), Transparency = 0.2, Life = 0.8 })
			tween(pillar, 0.5, { Size = Vector3.new(0.2, 20, 0.2), Transparency = 1 })
			burst(pos, Color3.fromRGB(200, 140, 255), 30, 25)
		end
	end
	AudioUtil.play(AudioAssets.SwapWarp)
end

function EffectsController.movement(kind, data)
	local p = Players:GetPlayerByUserId(data.userId or 0)
	local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local color = if kind == "Dash" then Color3.fromRGB(120, 220, 255) else Color3.fromRGB(140, 255, 160)
	burst(root.Position - Vector3.new(0, 2.5, 0), color, 25, 20)
	if p == player then
		AudioUtil.play(if kind == "Dash" then AudioAssets.Dash else AudioAssets.Jump)
	end
end

function EffectsController.win(data)
	local pos = data.pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	for i = 1, 5 do
		task.delay(i * 0.25, function()
			local p = pos + Vector3.new(math.random(-12, 12), math.random(14, 24), math.random(-12, 12))
			burst(p, Color3.fromHSV(math.random(), 0.9, 1), 50, 30)
		end)
	end
end

function EffectsController.init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "RR_Fx"
	fxFolder.Parent = workspace

	ClientState.Fx:Connect(function(kind, data)
		data = data or {}
		if kind == "Swing" then
			-- My own swing was already shown instantly on press.
			if data.id ~= ClientState.myId() then
				EffectsController.swing(data.id, data.item, data.ok)
			elseif data.ok then
				local pos = BallController.position()
				if pos then
					burst(pos, Color3.new(1, 1, 1), 30, 40)
				end
				AudioUtil.play(AudioAssets.Parry, nil, 0.05)
				EffectsController.shake(0.35, 0.15)
			end
		elseif kind == "Explode" then
			EffectsController.explode(data)
		elseif kind == "ShieldPop" then
			EffectsController.shieldPop(data)
		elseif kind == "Freeze" then
			EffectsController.freeze(data)
		elseif kind == "Swap" then
			EffectsController.swap(data)
		elseif kind == "Dash" or kind == "SuperJump" then
			EffectsController.movement(kind, data)
		elseif kind == "Win" then
			EffectsController.win(data)
		end
	end)
	ClientState.LocalParry:Connect(function(allowed)
		if allowed then
			local profile = ClientState.profile
			EffectsController.swing(ClientState.myId(), profile and profile.equipped and profile.equipped.ParryFx, false)
		end
	end)
	ClientState.ProfileChanged:Connect(function(profile)
		if profile and profile.settings then
			EffectsController.shakeEnabled = profile.settings.Shake ~= false
		end
	end)
	RunService:BindToRenderStep("RR_Shake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now < shakeUntil and shakeAmount > 0 then
			local camera = workspace.CurrentCamera
			local a = shakeAmount * ((shakeUntil - now) / 0.4)
			camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * a * 2), math.rad((math.random() - 0.5) * a * 2), 0)
		else
			shakeAmount = 0
		end
	end)
end

return EffectsController
