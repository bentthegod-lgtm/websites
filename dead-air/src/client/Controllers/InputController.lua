--[[
	InputController - keyboard/mouse, gamepad and touch bindings via ContextActionService
	(touch buttons are created automatically on mobile). Sends intent to the server; the
	server decides actual speed, stamina and noise.

	Keyboard: Shift sprint (hold; crouch-run while crouched) | C / Ctrl crouch (toggle) | F flashlight | G throw bottle
	          Q drop selected item | 1-5 select slot | E interact (prompts) | Tab settings
	Gamepad:  L3 sprint (toggle) | B crouch | Y flashlight | R1 throw | DPad down drop
	          DPad left/right select slot | X interact | Select settings
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local ClientState = require(script.Parent.ClientState)

local InputController = {
	sprint = false,
	crouch = false,
	SettingsToggled = Signal.new(),
	CrouchChanged = Signal.new(),
}

local player = Players.LocalPlayer
local sent = { sprint = nil, crouch = nil }

local function send()
	if sent.sprint ~= InputController.sprint or sent.crouch ~= InputController.crouch then
		sent.sprint = InputController.sprint
		sent.crouch = InputController.crouch
		Net.event("SetMovement"):FireServer(InputController.sprint, InputController.crouch)
	end
end

local function alive()
	return ClientState.status() == "Alive"
end

local function isTouchOrPad(inputObject)
	local t = inputObject and inputObject.UserInputType
	return t == Enum.UserInputType.Touch or (t and t.Name:sub(1, 7) == "Gamepad")
end

local function onSprint(_, inputState, inputObject)
	if isTouchOrPad(inputObject) then
		if inputState == Enum.UserInputState.Begin then
			-- While crouched this toggles crouch-running instead of standing up.
			InputController.sprint = not InputController.sprint
		end
	else
		InputController.sprint = inputState == Enum.UserInputState.Begin
	end
	send()
	return Enum.ContextActionResult.Pass
end

local function onCrouch(_, inputState)
	if inputState == Enum.UserInputState.Begin and alive() then
		InputController.crouch = not InputController.crouch
		InputController.CrouchChanged:Fire(InputController.crouch)
		send()
	end
	return Enum.ContextActionResult.Sink
end

local function onFlashlight(_, inputState)
	if inputState == Enum.UserInputState.Begin and alive() then
		Net.event("ToggleFlashlight"):FireServer()
	end
	return Enum.ContextActionResult.Sink
end

local function onThrow(_, inputState)
	if inputState == Enum.UserInputState.Begin and alive() then
		local camera = Workspace.CurrentCamera
		Net.event("ThrowItem"):FireServer(camera.CFrame.LookVector, ClientState.selectedSlot)
	end
	return Enum.ContextActionResult.Sink
end

local function onDrop(_, inputState)
	if inputState == Enum.UserInputState.Begin and alive() and #ClientState.inventory > 0 then
		Net.event("DropItem"):FireServer(ClientState.selectedSlot)
	end
	return Enum.ContextActionResult.Sink
end

local function onSlot(actionName, inputState, inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if actionName == "DA_SlotPrev" then
		ClientState.setSlot(ClientState.selectedSlot - 1)
	elseif actionName == "DA_SlotNext" then
		ClientState.setSlot(ClientState.selectedSlot + 1)
	else
		local map = {
			[Enum.KeyCode.One] = 1,
			[Enum.KeyCode.Two] = 2,
			[Enum.KeyCode.Three] = 3,
			[Enum.KeyCode.Four] = 4,
			[Enum.KeyCode.Five] = 5,
		}
		local slot = map[inputObject.KeyCode]
		if slot and slot <= #ClientState.inventory then
			ClientState.setSlot(slot)
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onExitHide(_, inputState)
	if inputState == Enum.UserInputState.Begin and player:GetAttribute("DA_Hidden") then
		Net.event("ExitHide"):FireServer()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function onSettings(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		InputController.SettingsToggled:Fire()
	end
	return Enum.ContextActionResult.Sink
end

local bound = false
local function bindRunActions()
	if bound then
		return
	end
	bound = true
	ContextActionService:BindAction("DA_Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:BindAction("DA_Crouch", onCrouch, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("DA_Flashlight", onFlashlight, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("DA_Throw", onThrow, true, Enum.KeyCode.G, Enum.KeyCode.ButtonR1)
	ContextActionService:BindAction("DA_Drop", onDrop, true, Enum.KeyCode.Q, Enum.KeyCode.DPadDown)
	ContextActionService:BindAction("DA_SlotKeys", onSlot, false, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five)
	ContextActionService:BindAction("DA_SlotPrev", onSlot, false, Enum.KeyCode.DPadLeft)
	ContextActionService:BindAction("DA_SlotNext", onSlot, false, Enum.KeyCode.DPadRight)
	ContextActionService:BindActionAtPriority("DA_ExitHide", onExitHide, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	for action, title in pairs({ DA_Sprint = "Run", DA_Crouch = "Crouch", DA_Flashlight = "Light", DA_Throw = "Throw", DA_Drop = "Drop" }) do
		ContextActionService:SetTitle(action, title)
	end
	ContextActionService:SetPosition("DA_Sprint", UDim2.new(1, -190, 1, -130))
	ContextActionService:SetPosition("DA_Crouch", UDim2.new(1, -250, 1, -80))
	ContextActionService:SetPosition("DA_Flashlight", UDim2.new(1, -130, 1, -200))
	ContextActionService:SetPosition("DA_Throw", UDim2.new(1, -200, 1, -200))
	ContextActionService:SetPosition("DA_Drop", UDim2.new(1, -270, 1, -150))
end

local function unbindRunActions()
	if not bound then
		return
	end
	bound = false
	for _, name in ipairs({ "DA_Sprint", "DA_Crouch", "DA_Flashlight", "DA_Throw", "DA_Drop", "DA_SlotKeys", "DA_SlotPrev", "DA_SlotNext", "DA_ExitHide" }) do
		ContextActionService:UnbindAction(name)
	end
	InputController.sprint = false
	InputController.crouch = false
	InputController.CrouchChanged:Fire(false)
	send()
end

function InputController.init()
	ContextActionService:BindAction("DA_Settings", onSettings, false, Enum.KeyCode.Tab, Enum.KeyCode.ButtonSelect)

	local function refresh()
		if ClientState.status() == "Alive" or ClientState.status() == "Downed" then
			bindRunActions()
		else
			unbindRunActions()
		end
		if ClientState.status() ~= "Alive" then
			InputController.sprint = false
			send()
		end
	end
	player:GetAttributeChangedSignal("DA_Status"):Connect(refresh)
	-- Exhaustion cancels a toggled sprint.
	player:GetAttributeChangedSignal("DA_Exhausted"):Connect(function()
		if player:GetAttribute("DA_Exhausted") then
			InputController.sprint = false
			send()
		end
	end)
	-- The server is authoritative for crouch; keep in sync if it changes it.
	player:GetAttributeChangedSignal("DA_Crouch"):Connect(function()
		local crouch = player:GetAttribute("DA_Crouch") == true
		if crouch ~= InputController.crouch then
			InputController.crouch = crouch
			sent.crouch = crouch
			InputController.CrouchChanged:Fire(crouch)
		end
	end)
	refresh()
end

return InputController
