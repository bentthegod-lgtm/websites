--[[
	InputController - keyboard / gamepad / touch controls.
	  Shift (hold) / L3      sprint (loud, heavy on the ice)
	  C (toggle or hold) / B  sneak (quiet, light on the ice)
	  F / R2                  throw a snowball where the camera faces (a lure)
	  M / Select              menu
	Touch gets on-screen SPRINT / SNEAK / THROW buttons from the HUD (same functions).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local Net = require(Shared.Net)

local ClientState = require(script.Parent.ClientState)

local InputController = {}

local sprintHeld = false
local sneakOn = false
InputController.menuToggle = nil -- set by MenuController

local function apply()
	ClientState.setMode(if sprintHeld then "Sprint" elseif sneakOn then "Sneak" else "Walk")
end

function InputController.setSprint(on)
	sprintHeld = on
	apply()
end

function InputController.toggleSneak(on)
	if on == nil then
		sneakOn = not sneakOn
	else
		sneakOn = on
	end
	apply()
end

function InputController.throw()
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local look = camera.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z)
	if dir.Magnitude < 0.05 then
		local root = ClientState.root()
		if not root then
			return false
		end
		dir = root.CFrame.LookVector
	end
	Net.event("Throw"):FireServer(dir)
	return true
end

-- Returns true if the key did something (also used by the harness).
function InputController.handle(keyCode, began)
	if keyCode == Enum.KeyCode.LeftShift or keyCode == Enum.KeyCode.RightShift or keyCode == Enum.KeyCode.ButtonL3 then
		InputController.setSprint(began)
		return true
	elseif keyCode == Enum.KeyCode.C or keyCode == Enum.KeyCode.ButtonB then
		if ClientState.setting("ToggleSneak") ~= false then
			if began then
				InputController.toggleSneak()
			end
		else
			InputController.toggleSneak(began)
		end
		return true
	elseif began and (keyCode == Enum.KeyCode.F or keyCode == Enum.KeyCode.ButtonR2) then
		return InputController.throw()
	elseif began and (keyCode == Enum.KeyCode.M or keyCode == Enum.KeyCode.ButtonSelect) then
		if InputController.menuToggle then
			InputController.menuToggle()
		end
		return true
	end
	return false
end

function InputController.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		InputController.handle(input.KeyCode, true)
	end)
	UserInputService.InputEnded:Connect(function(input)
		InputController.handle(input.KeyCode, false)
	end)
	-- A respawn resets you to walking.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		sprintHeld, sneakOn = false, false
		apply()
	end)
end

return InputController
