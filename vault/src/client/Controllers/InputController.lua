--[[
	InputController - the pickup key and menu shortcuts.

	E (keyboard) / ButtonX (gamepad) / the HUD's PICKUP button collect the targeted item;
	holding any of them keeps collecting at the pickup interval. While a ProximityPrompt is
	on screen (deposit machine, elevator panel, upgrade terminal) the key belongs to the
	prompt, so pressing E at the machine deposits instead of grabbing a bill next to it.

	Shortcuts (keyboard): U upgrades, G depths, B collection book, J achievements, L
	leaderboards, K stats, P shop, O settings. Typing in a text box never triggers them.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CollectController = require(script.Parent.CollectController)

local InputController = {}

local promptsShown = 0
local held = {}
local menuOpener

InputController.SHORTCUTS = {
	[Enum.KeyCode.U] = "Upgrades",
	[Enum.KeyCode.G] = "Depths",
	[Enum.KeyCode.B] = "Book",
	[Enum.KeyCode.J] = "Achievements",
	[Enum.KeyCode.L] = "Leaderboards",
	[Enum.KeyCode.K] = "Stats",
	[Enum.KeyCode.P] = "Shop",
	[Enum.KeyCode.O] = "Settings",
}

-- MenuController registers how to toggle a window (avoids a require cycle).
function InputController.setMenuOpener(fn)
	menuOpener = fn
end

function InputController.promptVisible()
	return promptsShown > 0
end

-- source: "key", "pad" or "touch"; the HUD's PICKUP button uses "touch".
function InputController.setHeld(source, down)
	held[source] = down or nil
	if down then
		CollectController.tryCollect()
	end
end

local function anyHeld()
	return next(held) ~= nil
end

function InputController.init()
	ProximityPromptService.PromptShown:Connect(function()
		promptsShown += 1
	end)
	ProximityPromptService.PromptHidden:Connect(function()
		promptsShown = math.max(0, promptsShown - 1)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
			if promptsShown > 0 then
				return -- the prompt takes this press
			end
			InputController.setHeld(if input.KeyCode == Enum.KeyCode.E then "key" else "pad", true)
			return
		end
		local window = InputController.SHORTCUTS[input.KeyCode]
		if window and menuOpener then
			menuOpener(window)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.E then
			held.key = nil
		elseif input.KeyCode == Enum.KeyCode.ButtonX then
			held.pad = nil
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(held)
	end)
	RunService.Heartbeat:Connect(function()
		if anyHeld() and promptsShown == 0 then
			CollectController.tryCollect()
		end
	end)
end

return InputController
