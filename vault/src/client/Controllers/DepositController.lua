--[[
	DepositController - what a deposit looks and sounds like (the payout itself is the
	server's; this only presents the Deposited message).

	* Your stack's pieces fly from your hands into the machine's chute, one after another.
	* The machine reacts: its lamps chase, the drum spins, the screen counts up "+$X" and
	  then returns to idle, the status light flashes; insert / machine / reward sounds.
	* Your equipped deposit effect plays at the chute (Standard sparks, Coin Burst, Confetti).
	* Idle: when you carry loot, the machines on your floor pulse their lamps to say "here".
	Other players' deposits play the machine reaction and a quieter 3D sound.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local LootConfig = require(Shared.Config.LootConfig)
local Format = require(Shared.Format)
local LootModels = require(Shared.LootModels)

local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local DepositController = {}

local machines = {} -- [id] = { model, chute, drum, lamps, status, amount, title, depth, busyUntil }
local pulseClock = 0

local function index()
	local vault = Workspace:WaitForChild("Vault")
	for _, d in ipairs(vault:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("MachineId") then
			local screen = d:FindFirstChild("Screen", true)
			local lamps = {}
			for i = 1, 5 do
				lamps[i] = d:FindFirstChild("Lamp" .. i, true)
			end
			local depthFolder = d:FindFirstAncestorWhichIsA("Folder")
			machines[d:GetAttribute("MachineId")] = {
				model = d,
				chute = d:FindFirstChild("Chute", true),
				drum = d:FindFirstChild("Drum", true),
				lamps = lamps,
				status = d:FindFirstChild("StatusLight", true),
				amount = screen and screen:FindFirstChild("Amount", true),
				title = screen and screen:FindFirstChild("Title", true),
				code = depthFolder and depthFolder.Name,
				busyUntil = 0,
			}
		end
	end
end

function DepositController.machine(id)
	return machines[id]
end

-- Nearest machine on the character's floor (HUD arrow when the stack is full).
function DepositController.nearest(position)
	local best, bestDist
	for _, m in pairs(machines) do
		if m.chute then
			local d = (m.chute.Position - position).Magnitude
			if math.abs(m.chute.Position.Y - position.Y) < 40 and (not bestDist or d < bestDist) then
				best, bestDist = m, d
			end
		end
	end
	return best, bestDist
end

local LAMP_ON = Color3.fromRGB(120, 255, 160)
local LAMP_OFF = Color3.fromRGB(40, 90, 60)

local function react(m, payout, record)
	m.busyUntil = os.clock() + 2.6
	for i, lamp in ipairs(m.lamps) do
		task.delay(i * 0.07, function()
			lamp.Color = if record then Color3.fromRGB(255, 220, 90) else LAMP_ON
			TweenService:Create(lamp, TweenInfo.new(0.9), { Color = LAMP_OFF }):Play()
		end)
	end
	if m.drum then
		local start = m.drum.CFrame
		local spins = 0
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			spins += dt
			m.drum.CFrame = start * CFrame.Angles(spins * 14, 0, 0)
			if spins > 1.4 then
				connection:Disconnect()
				m.drum.CFrame = start
			end
		end)
	end
	if m.status then
		m.status.Color = Color3.fromRGB(255, 230, 120)
		TweenService:Create(m.status, TweenInfo.new(1.2), { Color = Color3.fromRGB(92, 210, 110) }):Play()
	end
	if m.amount then
		local label = m.amount
		local idle = label:GetAttribute("Idle") or label.Text
		label:SetAttribute("Idle", idle)
		local t0 = os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local t = math.min(1, (os.clock() - t0) / 0.8)
			label.Text = "+$" .. Format.short(payout * t)
			if t >= 1 then
				connection:Disconnect()
			end
		end)
		task.delay(3, function()
			if os.clock() >= m.busyUntil then
				label.Text = idle
			end
		end)
	end
end

local function burst(m, kind)
	if not m.chute or ClientState.setting("ReducedEffects") then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = m.chute.Position + m.chute.CFrame.LookVector * -0.5 + Vector3.new(0, 1, 0)
	attachment.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(50, 50)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.LightEmission = 0.4
	emitter.Size = NumberSequence.new(0.35)
	if kind == "CoinBurst" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 205, 70))
		emitter.Size = NumberSequence.new(0.5)
	elseif kind == "Confetti" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 90, 140), Color3.fromRGB(90, 200, 255))
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-200, 200)
	else
		emitter.Color = ColorSequence.new(Color3.fromRGB(140, 255, 170))
		emitter.Size = NumberSequence.new(0.22)
	end
	emitter.Parent = attachment
	emitter:Emit(if kind == "Standard" then 14 else 28)
	task.delay(1.5, function()
		attachment:Destroy()
	end)
end

-- Pieces of the stack fly into the chute (your own deposit only).
local function transfer(m, items)
	local root = ClientState.root()
	if not root or not m.chute or ClientState.setting("ReducedEffects") then
		return
	end
	local categories = {}
	for id, n in pairs(items or {}) do
		local def = LootConfig.ById[id]
		if def then
			categories[def.Category] = (categories[def.Category] or 0) + n
		end
	end
	local list = {}
	for _, category in ipairs(LootConfig.CategoryOrder) do
		if categories[category] then
			table.insert(list, category)
		end
	end
	local pieces = math.min(8, math.max(#list, 3))
	for i = 1, pieces do
		local category = list[(i - 1) % math.max(1, #list) + 1] or "Cash"
		task.delay((i - 1) * 0.06, function()
			local from = (root.CFrame * CFrame.new(0, 0.5, -1.3)).Position
			local to = m.chute.Position
			local piece = LootModels.piece(category, Players.LocalPlayer:GetAttribute("V_Theme"), CFrame.new(from), true, 0.8)
			piece.Parent = Workspace.CurrentCamera
			local t0 = os.clock()
			local pivot0 = piece:GetPivot()
			local connection
			connection = RunService.RenderStepped:Connect(function()
				local t = math.min(1, (os.clock() - t0) / 0.32)
				local pos = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 2, 0)
				piece:PivotTo(CFrame.new(pos) * pivot0.Rotation * CFrame.Angles(t * 3, 0, 0))
				if t >= 1 then
					connection:Disconnect()
					piece:Destroy()
				end
			end)
		end)
	end
end

local function onDeposited(userId, summary)
	local m = machines[summary.machine]
	if not m then
		return
	end
	local mine = userId == Players.LocalPlayer.UserId
	if mine then
		transfer(m, summary.items)
		task.delay(0.3, function()
			react(m, summary.payout or 0, summary.record)
			burst(m, ClientState.profile and ClientState.profile.cosmetics and ClientState.profile.cosmetics.DepositFx or "Standard")
		end)
		AudioController.play("DepositInsert")
		task.delay(0.25, function()
			AudioController.play("DepositMachine", { position = m.chute and m.chute.Position })
		end)
		task.delay(0.85, function()
			AudioController.play("DepositReward", { pitch = if summary.record then 1.12 else 1 })
		end)
	else
		react(m, summary.payout or 0, false)
		AudioController.play("DepositMachine", { position = m.chute and m.chute.Position, volume = 0.5 })
	end
end

-- While you carry something, the machines on your floor breathe their lamps.
local function pulse(dt)
	pulseClock += dt
	if pulseClock < 0.1 then
		return
	end
	pulseClock = 0
	local carrying = (ClientState.inventory.count or 0) > 0
	local root = ClientState.root()
	local t = os.clock()
	for _, m in pairs(machines) do
		if os.clock() >= m.busyUntil and root and m.chute and math.abs(m.chute.Position.Y - root.Position.Y) < 40 then
			local glow = if carrying then (math.sin(t * 4) + 1) / 2 else 0
			for i, lamp in ipairs(m.lamps) do
				local phase = if carrying then (math.sin(t * 4 - i * 0.6) + 1) / 2 else glow
				lamp.Color = LAMP_OFF:Lerp(LAMP_ON, phase * 0.7)
			end
		end
	end
end

function DepositController.init()
	index()
	ClientState.Deposited:Connect(onDeposited)
	RunService.Heartbeat:Connect(pulse)
end

return DepositController
