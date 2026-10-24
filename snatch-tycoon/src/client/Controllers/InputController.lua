--[[
	InputController - keyboard and gamepad bindings (touch uses the HUD buttons).
	  F / R1           slap
	  L / L1           lock your base
	  G / DPad down    drop what you carry
	  B / Select       shop
	ProximityPrompts (buy, steal, sell, lock console) use E / gamepad X by default.
]]

local ContextActionService = game:GetService("ContextActionService")

local HudController = require(script.Parent.HudController)
local MenuController = require(script.Parent.MenuController)

local InputController = {}

local function bind(name, fn, ...)
	ContextActionService:BindAction(name, function(_, state)
		if state == Enum.UserInputState.Begin then
			fn()
		end
		return Enum.ContextActionResult.Pass
	end, false, ...)
end

function InputController.init()
	bind("ST_Slap", HudController.slap, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	bind("ST_Lock", HudController.lock, Enum.KeyCode.L, Enum.KeyCode.ButtonL1)
	bind("ST_Drop", HudController.drop, Enum.KeyCode.G, Enum.KeyCode.DPadDown)
	bind("ST_Shop", function()
		MenuController.toggle("Shop")
	end, Enum.KeyCode.B, Enum.KeyCode.ButtonSelect)
end

return InputController
