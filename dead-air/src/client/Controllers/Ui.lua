--[[
	Tiny UI construction helpers and the shared visual style.
]]

local Ui = {}

local function font(name, fallback)
	local ok, value = pcall(function()
		return Enum.Font[name]
	end)
	return if ok and value then value else Enum.Font[fallback]
end

Ui.Fonts = {
	Title = font("SpecialElite", "Antique"),
	Body = font("GothamMedium", "SourceSans"),
	Bold = font("GothamBold", "SourceSansBold"),
	Mono = Enum.Font.Code,
}

Ui.Colors = {
	Text = Color3.fromRGB(236, 228, 204),
	Dim = Color3.fromRGB(160, 152, 130),
	Accent = Color3.fromRGB(232, 196, 96),
	Danger = Color3.fromRGB(222, 72, 60),
	Good = Color3.fromRGB(120, 220, 140),
	Panel = Color3.fromRGB(14, 13, 10),
	PanelLight = Color3.fromRGB(34, 31, 24),
}

Ui.TextScale = 1

function Ui.new(className, props, children)
	local instance = Instance.new(className)
	if className == "Frame" or className == "TextLabel" or className == "TextButton" or className == "ScrollingFrame" or className == "ImageLabel" then
		instance.BorderSizePixel = 0
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		instance.Font = Ui.Fonts.Body
		instance.TextColor3 = Ui.Colors.Text
		instance.BackgroundTransparency = 1
		instance.TextSize = 16
	end
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if props and props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function Ui.corner(parent, radius)
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

function Ui.padding(parent, px)
	return Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		Parent = parent,
	})
end

function Ui.stroke(parent, color, transparency)
	return Ui.new("UIStroke", {
		Color = color or Ui.Colors.Accent,
		Transparency = transparency or 0.6,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Ui.list(parent, padding, direction, align)
	return Ui.new("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Ui.panel(props)
	local frame = Ui.new("Frame", props)
	frame.BackgroundColor3 = props.BackgroundColor3 or Ui.Colors.Panel
	frame.BackgroundTransparency = props.BackgroundTransparency or 0.25
	Ui.corner(frame, 6)
	return frame
end

function Ui.button(text, props)
	local button = Ui.new("TextButton", props)
	button.Text = text
	button.AutoButtonColor = true
	button.BackgroundTransparency = props and props.BackgroundTransparency or 0.15
	button.BackgroundColor3 = props and props.BackgroundColor3 or Ui.Colors.PanelLight
	button.Font = Ui.Fonts.Bold
	button.TextSize = props and props.TextSize or 16
	Ui.corner(button, 5)
	Ui.stroke(button, Ui.Colors.Accent, 0.65)
	return button
end

function Ui.screen(name, playerGui, displayOrder)
	return Ui.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 1,
		Parent = playerGui,
	})
end

-- Registers a text element so the "Large text" setting can scale it.
local scalable = {}
function Ui.scalable(label)
	scalable[label] = label.TextSize
	label.TextSize = math.floor(label.TextSize * Ui.TextScale)
	return label
end

function Ui.setTextScale(scale)
	Ui.TextScale = scale
	for label, base in pairs(scalable) do
		if label.Parent then
			label.TextSize = math.floor(base * scale)
		else
			scalable[label] = nil
		end
	end
end

return Ui
