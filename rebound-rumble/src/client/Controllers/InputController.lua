--[[
	InputController - parry and ability input for keyboard/mouse, gamepad and touch.

	Keyboard/mouse: F or Left Click = PARRY | Q = ability 1 | E = ability 2
	Gamepad:        R1 / R2 = PARRY | X = ability 1 | Y = ability 2
	Touch:          on-screen PARRY and ability buttons (HudController calls parry()/ability()).

	The camera direction picks who the ball is sent at. The client only sends intent plus
	the server-synchronised press time; the server decides whether the parry counts.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Clock = require(Shared.Clock)

local ClientState = require(script.Parent.ClientState)

local InputController = {
	parryReadyAt = 0,
	abilityReadyAt = {},
	abilityCooldown = {},
	CooldownsChanged = Signal.new(),
}

local player = Players.LocalPlayer

local function aimDirection()
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
end

function InputController.canParry()
	return ClientState.status() == "Arena"
end

function InputController.parry()
	if not InputController.canParry() then
		return
	end
	local now = Clock.now()
	ClientState.LocalParry:Fire(now >= InputController.parryReadyAt)
	if now < InputController.parryReadyAt then
		return
	end
	-- Optimistic lockout until the server answers with the real cooldown.
	InputController.parryReadyAt = now + 0.25
	Net.event("Parry"):FireServer(now, aimDirection())
end

function InputController.ability(slot)
	local now = Clock.now()
	if (InputController.abilityReadyAt[slot] or 0) > now then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local move = humanoid and humanoid.MoveDirection
	if not move or move.Magnitude < 0.1 then
		local look = aimDirection()
		move = Vector3.new(look.X, 0, look.Z)
	end
	Net.event("UseAbility"):FireServer(slot, move)
end

local function onAction(actionName, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if actionName == "RR_Parry" then
		InputController.parry()
	elseif actionName == "RR_Ability1" then
		InputController.ability(1)
	elseif actionName == "RR_Ability2" then
		InputController.ability(2)
	end
	return Enum.ContextActionResult.Sink
end

local function applyMovement(kind, data)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if kind == "Dash" then
		local attachment = Instance.new("Attachment")
		attachment.Parent = root
		local lv = Instance.new("LinearVelocity")
		lv.Attachment0 = attachment
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.MaxForce = 1e6
		lv.VectorVelocity = data.dir * data.power + Vector3.new(0, 6, 0)
		lv.Parent = root
		task.delay(data.duration or 0.18, function()
			lv:Destroy()
			attachment:Destroy()
		end)
	elseif kind == "SuperJump" then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, data.power, v.Z)
	end
end

function InputController.init()
	ContextActionService:BindAction("RR_Parry", onAction, false, Enum.KeyCode.F, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("RR_Ability1", onAction, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("RR_Ability2", onAction, false, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
	-- Left click parries unless the click was on UI.
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.parry()
		end
	end)

	ClientState.ParryResult:Connect(function(_ok, _reason, cooldown)
		if type(cooldown) == "number" then
			InputController.parryReadyAt = Clock.now() + cooldown
			InputController.parryCooldown = cooldown
			InputController.CooldownsChanged:Fire()
		end
	end)
	ClientState.AbilityFx:Connect(function(kind, data)
		if kind == "Cooldown" then
			InputController.abilityReadyAt[data.slot] = Clock.now() + data.cooldown
			InputController.abilityCooldown[data.slot] = data.cooldown
			InputController.CooldownsChanged:Fire()
		else
			applyMovement(kind, data)
		end
	end)
end

return InputController
