--[[
	InputController - one place for every control.

	  Action              Keyboard / mouse      Gamepad          Touch
	  Magnet (hold)       Left mouse            R2               MAGNET button (hold)
	  Magnetic pulse      R                     R1               PULSE button
	  Sprint (hold)       Left Shift            L3 (toggle)      SPRINT button (toggle)
	  Interact            E (prompts)           X (prompts)      tap prompt
	  Menu                M                     D-pad up         MENU button
	  Camera mode         V                     D-pad down       Settings
	Shift lock is disabled for this game (StarterPlayer.EnableMouseLockOption = false), so
	Shift is free for sprinting. Tab keeps Roblox's player list.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local InputController = {}

InputController.MagnetChanged = Signal.new() -- (on)
InputController.MenuRequested = Signal.new()

local player = Players.LocalPlayer
local magnetOn = false
local sprintOn = false
local holders = {} -- magnet "hold" sources: mouse / gamepad / touch

function InputController.setMagnet(source, on)
	holders[source] = on or nil
	local want = next(holders) ~= nil
	if want ~= magnetOn then
		magnetOn = want
		Net.event("Magnet"):FireServer(want)
		InputController.MagnetChanged:Fire(want)
	end
end

function InputController.magnetOn()
	return magnetOn
end

function InputController.pulse()
	Net.event("Pulse"):FireServer()
end

function InputController.setSprint(on)
	if on ~= sprintOn then
		sprintOn = on
		Net.event("Sprint"):FireServer(on)
	end
end

function InputController.toggleSprint()
	InputController.setSprint(not sprintOn)
end

function InputController.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not processed then
				InputController.setMagnet("mouse", true)
			end
			return
		end
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonR2 then
			InputController.setMagnet("gamepad", true)
		elseif key == Enum.KeyCode.R or key == Enum.KeyCode.ButtonR1 then
			InputController.pulse()
		elseif key == Enum.KeyCode.LeftShift then
			InputController.setSprint(true)
		elseif key == Enum.KeyCode.ButtonL3 then
			InputController.toggleSprint()
		elseif key == Enum.KeyCode.M or key == Enum.KeyCode.DPadUp then
			InputController.MenuRequested:Fire()
		elseif key == Enum.KeyCode.V or key == Enum.KeyCode.DPadDown then
			require(script.Parent.CameraController).toggleMode()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.setMagnet("mouse", false)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			InputController.setMagnet("gamepad", false)
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			InputController.setSprint(false)
		end
	end)
	-- Losing focus (alt-tab) never leaves the magnet stuck on.
	UserInputService.WindowFocusReleased:Connect(function()
		holders = {}
		InputController.setMagnet("mouse", false)
		InputController.setSprint(false)
	end)
	player.CharacterAdded:Connect(function()
		holders = {}
		magnetOn = false
		sprintOn = false
		InputController.MagnetChanged:Fire(false)
	end)
end

return InputController
