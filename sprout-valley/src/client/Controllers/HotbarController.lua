--[[
	HotbarController - the bottom tool bar: Hand (harvest / inspect), every seed you own,
	your gear and the Growth Skip tool. Click / tap a slot, press 1-9 (0 / Q = hand), or
	cycle with gamepad L1 / R1. The selected tool is stored in ClientState.tool.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local CropConfig = require(Shared.Config.CropConfig)
local GearConfig = require(Shared.Config.GearConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local HotbarController = {}

local C = Ui.Colors
local gui, bar, hint
local slots = {} -- ordered list of { tool = {...}, button = ... }

local function sameTool(a, b)
	return a.kind == b.kind and a.id == b.id
end

local HINTS = {
	none = "Hand: tap ripe crops to harvest. Hold and drag to harvest a row!",
	seed = "Tap an empty soil tile in your garden to plant.",
	skip = "Tap a growing plant to ripen it instantly.",
}

local function gearHint(id)
	if id == "Trowel" then
		return "Tap a plant, then tap an empty tile to move it."
	end
	local def = GearConfig.Gear[id]
	return def and def.Description or ""
end

local function highlight()
	local tool = ClientState.tool
	for _, slot in ipairs(slots) do
		local selected = sameTool(slot.tool, tool)
		local stroke = slot.button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if selected then C.Gold else C.Brown
			stroke.Thickness = if selected then 4 else 2.5
		end
		slot.button.BackgroundColor3 = if selected then Color3.fromRGB(255, 240, 190) else C.Cream
	end
	if hint then
		hint.Text = if tool.kind == "gear" then gearHint(tool.id) else (HINTS[tool.kind] or "")
	end
end

function HotbarController.select(tool)
	if sameTool(tool, ClientState.tool) and tool.kind ~= "none" then
		tool = { kind = "none" }
	end
	ClientState.setTool(tool)
end

local function slotButton(order, label, count, color)
	local button = Ui.new("TextButton", {
		Size = UDim2.fromOffset(74, 80),
		BackgroundColor3 = C.Cream,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = order,
		Parent = bar,
	})
	Ui.corner(button, 12)
	Ui.stroke(button, C.Brown, 2.5)
	local name = Ui.label(label, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -4, 0, 16),
		TextScaled = true,
		Font = Ui.Fonts.Bold,
		TextColor3 = C.Brown,
		Parent = button,
	})
	Ui.new("UITextSizeConstraint", { MaxTextSize = 13, Parent = name })
	if count then
		local badge = Ui.label(count, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -3, 0, 3),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(22, 20),
			BackgroundTransparency = 0,
			BackgroundColor3 = color or C.Green,
			Font = Ui.Fonts.Title,
			TextSize = 14,
			TextColor3 = C.White,
			ZIndex = 4,
			Parent = button,
		})
		Ui.corner(badge, 8)
		Ui.padding(badge, 4, 0)
	end
	if order <= 10 then
		Ui.label(tostring(order % 10), {
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.fromOffset(14, 14),
			TextSize = 12,
			Font = Ui.Fonts.Bold,
			TextColor3 = C.Dim,
			ZIndex = 4,
			Parent = button,
		})
	end
	return button
end

local function iconBlock(button, color, text)
	local icon = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = color,
		Parent = button,
	})
	Ui.corner(icon, 12)
	Ui.stroke(icon, color:Lerp(Color3.new(0, 0, 0), 0.4), 2)
	local t = Ui.title(text, { Size = UDim2.fromScale(1, 1), TextScaled = true, TextColor3 = C.White, Parent = icon })
	Ui.textStroke(t, color:Lerp(Color3.new(0, 0, 0), 0.6), 1.5)
	Ui.padding(icon, 4, 4)
	return icon
end

local function render(profile)
	Ui.clear(bar)
	slots = {}
	if not profile then
		return
	end
	local order = 0
	local function add(tool, button)
		table.insert(slots, { tool = tool, button = button })
		button.Activated:Connect(function()
			Ui.click()
			HotbarController.select(tool)
		end)
	end
	order += 1
	local hand = slotButton(order, "Hand")
	iconBlock(hand, C.Green, "HAND")
	add({ kind = "none" }, hand)

	local seedIds = {}
	for cropId, n in pairs(profile.seeds or {}) do
		if n > 0 and CropConfig.ById[cropId] then
			table.insert(seedIds, cropId)
		end
	end
	table.sort(seedIds, function(a, b)
		return CropConfig.ById[a].Order < CropConfig.ById[b].Order
	end)
	for _, cropId in ipairs(seedIds) do
		order += 1
		local crop = CropConfig.ById[cropId]
		local button = slotButton(order, crop.Name, tostring(profile.seeds[cropId]), Ui.rarityColor(crop.Rarity):Lerp(Color3.new(0, 0, 0), 0.25))
		Ui.cropIcon(button, cropId, 50, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6) })
		add({ kind = "seed", id = cropId }, button)
	end
	for _, gearId in ipairs(GearConfig.Order) do
		local n = (profile.gear or {})[gearId] or 0
		if n > 0 then
			order += 1
			local def = GearConfig.Gear[gearId]
			local button = slotButton(order, def.Name, if def.Permanent then nil else tostring(n), C.Sky)
			iconBlock(button, Ui.rgb(def.Color), string.upper(string.sub(def.Name, 1, 1)) .. string.lower(string.sub(def.Name, 2, 3)))
			add({ kind = "gear", id = gearId }, button)
		end
	end
	order += 1
	local tokens = (profile.tokens or {}).GrowthSkip or 0
	local skip = slotButton(order, "Growth Skip", if tokens > 0 then tostring(tokens) else "R$", C.Purple)
	iconBlock(skip, C.Purple, "SKIP")
	add({ kind = "skip" }, skip)

	-- Drop the selection if the tool ran out.
	local still = false
	for _, slot in ipairs(slots) do
		if sameTool(slot.tool, ClientState.tool) then
			still = true
		end
	end
	if not still then
		ClientState.setTool({ kind = "none" })
	end
	highlight()
end

function HotbarController.cycle(step)
	if #slots == 0 then
		return
	end
	local index = 1
	for i, slot in ipairs(slots) do
		if sameTool(slot.tool, ClientState.tool) then
			index = i
		end
	end
	index = ((index - 1 + step) % #slots) + 1
	ClientState.setTool(slots[index].tool)
end

local KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

function HotbarController.init()
	gui = Ui.screen("SproutHotbar", 3)
	local holder = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(760, 92),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	bar = Ui.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = holder,
	})
	local layout = Ui.list(bar, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	layout.Padding = UDim.new(0, 6)
	hint = Ui.label("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 15,
		Font = Ui.Fonts.Bold,
		TextColor3 = C.White,
		Parent = holder,
	})
	Ui.textStroke(hint, C.Shadow, 1.5)

	ClientState.ProfileChanged:Connect(render)
	ClientState.ToolChanged:Connect(highlight)
	render(ClientState.profile)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local n = KEYS[input.KeyCode]
		if n then
			if slots[n] then
				HotbarController.select(slots[n].tool)
			end
		elseif input.KeyCode == Enum.KeyCode.Zero or input.KeyCode == Enum.KeyCode.Q then
			ClientState.setTool({ kind = "none" })
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			HotbarController.cycle(1)
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			HotbarController.cycle(-1)
		end
	end)
end

return HotbarController
