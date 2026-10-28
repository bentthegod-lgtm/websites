--[[
	InputController - one place for every control (also listed in the Help menu).

	  Action                 Keyboard / mouse       Gamepad            Touch
	  Use launch pad / NPCs  E (prompts)            X (prompts)        tap prompt
	  Launch                 F  or LAUNCH button    R2                 LAUNCH button
	  Power - / +            1 / 2  (or drag bar)   D-pad down / up    drag bar, - / +
	  Angle - / +            3 / 4                  D-pad left / right - / +
	  Aim left / right       5 / 6                  L1 / R1            - / +
	  Spin mode              7                      Y                  SPIN button
	  Skip follow camera     Space (while flying)   B                  SKIP button
	  Upgrades               U                      -                  UPGRADES button
	  Menu / Help            M / H                  L2 (menu)          MENU button
	Movement, camera, jump and Escape keep Roblox's defaults. No key here is one Roblox
	uses by default (Tab, /, I/O and the arrows are left alone).
]]

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("CrashLab")
local Signal = require(Shared.Signal)

local ClientState = require(script.Parent.ClientState)

local InputController = {}

InputController.MenuRequested = Signal.new() -- (tab or nil)

local KEYS = {
	[Enum.KeyCode.F] = { "Launch" },
	[Enum.KeyCode.ButtonR2] = { "Launch" },
	[Enum.KeyCode.One] = { "Adjust", "Power", -1 },
	[Enum.KeyCode.Two] = { "Adjust", "Power", 1 },
	[Enum.KeyCode.DPadDown] = { "Adjust", "Power", -1 },
	[Enum.KeyCode.DPadUp] = { "Adjust", "Power", 1 },
	[Enum.KeyCode.Three] = { "Adjust", "Angle", -1 },
	[Enum.KeyCode.Four] = { "Adjust", "Angle", 1 },
	[Enum.KeyCode.DPadLeft] = { "Adjust", "Angle", -1 },
	[Enum.KeyCode.DPadRight] = { "Adjust", "Angle", 1 },
	[Enum.KeyCode.Five] = { "Adjust", "Aim", -1 },
	[Enum.KeyCode.Six] = { "Adjust", "Aim", 1 },
	[Enum.KeyCode.ButtonL1] = { "Adjust", "Aim", -1 },
	[Enum.KeyCode.ButtonR1] = { "Adjust", "Aim", 1 },
	[Enum.KeyCode.Seven] = { "Adjust", "Spin", 1 },
	[Enum.KeyCode.ButtonY] = { "Adjust", "Spin", 1 },
	[Enum.KeyCode.U] = { "Menu", "Upgrades" },
	[Enum.KeyCode.M] = { "Menu", nil },
	[Enum.KeyCode.ButtonL2] = { "Menu", nil },
	[Enum.KeyCode.H] = { "Menu", "Help" },
}

function InputController.handle(keyCode)
	local CameraController = require(script.Parent.CameraController)
	local LaunchController = require(script.Parent.LaunchController)
	if (keyCode == Enum.KeyCode.Space or keyCode == Enum.KeyCode.ButtonB) and CameraController.following() then
		CameraController.stopFollow()
		return true
	end
	local action = KEYS[keyCode]
	if not action then
		return false
	end
	if action[1] == "Launch" then
		LaunchController.launch()
	elseif action[1] == "Adjust" then
		if ClientState.myPad() then
			LaunchController.adjust(action[2], action[3])
		end
	elseif action[1] == "Menu" then
		InputController.MenuRequested:Fire(action[2])
	end
	return true
end

function InputController.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		InputController.handle(input.KeyCode)
	end)
end

return InputController
