--[[
	UI construction helpers and the shared bright "school notebook" style.
]]

local Ui = {}

local function font(name, fallback)
	local ok, value = pcall(function()
		return Enum.Font[name]
	end)
	return if ok and value then value else Enum.Font[fallback]
end

Ui.Fonts = {
	Title = font("FredokaOne", "SourceSansBold"),
	Body = font("GothamMedium", "SourceSans"),
	Bold = font("GothamBlack", "SourceSansBold"),
}

Ui.Colors = {
	Text = Color3.fromRGB(250, 250, 255),
	Dim = Color3.fromRGB(180, 186, 215),
	Accent = Color3.fromRGB(255, 96, 140), -- bubblegum
	Accent2 = Color3.fromRGB(80, 200, 255), -- sky
	Gold = Color3.fromRGB(255, 205, 70), -- Clout
	Danger = Color3.fromRGB(255, 80, 80),
	Warn = Color3.fromRGB(255, 200, 60),
	Good = Color3.fromRGB(110, 235, 140),
	Panel = Color3.fromRGB(26, 28, 52),
	PanelLight = Color3.fromRGB(46, 50, 90),
	Paper = Color3.fromRGB(255, 252, 240),
	Ink = Color3.fromRGB(40, 50, 110),
}

function Ui.rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Ui.new(className, props, children)
	local instance = Instance.new(className)
	if className == "Frame" or className == "TextLabel" or className == "TextButton" or className == "ScrollingFrame" or className == "ImageLabel" or className == "TextBox" then
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
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = parent })
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

function Ui.stroke(parent, color, transparency, thickness)
	return Ui.new("UIStroke", {
		Color = color or Ui.Colors.Accent,
		Transparency = transparency or 0.3,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Ui.gradient(parent, a, b, rotation)
	return Ui.new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rotation or 90, Parent = parent })
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
	frame.BackgroundTransparency = props.BackgroundTransparency or 0.1
	Ui.corner(frame, 12)
	return frame
end

function Ui.label(text, props)
	local label = Ui.new("TextLabel", props)
	label.Text = text
	return label
end

function Ui.button(text, props, color)
	local button = Ui.new("TextButton", props)
	button.Text = text
	button.AutoButtonColor = true
	button.BackgroundTransparency = props and props.BackgroundTransparency or 0
	button.BackgroundColor3 = color or (props and props.BackgroundColor3) or Ui.Colors.PanelLight
	button.Font = Ui.Fonts.Title
	button.TextSize = props and props.TextSize or 18
	button.TextColor3 = props and props.TextColor3 or Ui.Colors.Text
	Ui.corner(button, 10)
	Ui.stroke(button, Color3.new(1, 1, 1), 0.75, 2)
	return button
end

-- `fullScreen` = true covers the Roblox top bar too (flashes, tints). Everything else stays
-- below it: the UIScale also shrinks offsets, so on a phone a "52 px from the top" HUD would
-- otherwise slide up under the top bar's menu / chat buttons.
function Ui.screen(name, playerGui, displayOrder, fullScreen)
	local gui = Ui.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = fullScreen == true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 1,
		Parent = playerGui,
	})
	-- Shrinks everything on small (phone) screens.
	local scale = Ui.new("UIScale", { Parent = gui })
	local camera = workspace.CurrentCamera
	local function update()
		local ok, size = pcall(function()
			return camera and camera.ViewportSize
		end)
		if ok and size and size.X > 0 then
			scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.55, 1.15)
		end
	end
	update()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return gui, scale
end

function Ui.formatNumber(n)
	local s = tostring(math.floor(n or 0))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

return Ui
