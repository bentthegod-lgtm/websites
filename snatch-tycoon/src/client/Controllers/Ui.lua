--[[
	Ui - construction helpers and the shared cartoon style (chunky outlines, bright
	gradients, bouncy tweens).
]]

local TweenService = game:GetService("TweenService")

local Ui = {}

local function font(name, fallback)
	local ok, value = pcall(function()
		return Enum.Font[name]
	end)
	return if ok and value then value else Enum.Font[fallback]
end

Ui.Fonts = {
	Title = font("LuckiestGuy", "FredokaOne"),
	Bold = font("FredokaOne", "GothamBold"),
	Body = font("GothamMedium", "SourceSans"),
}

Ui.Colors = {
	Text = Color3.fromRGB(255, 255, 255),
	Dim = Color3.fromRGB(196, 186, 226),
	Outline = Color3.fromRGB(24, 16, 40),
	Panel = Color3.fromRGB(42, 30, 74),
	PanelLight = Color3.fromRGB(64, 50, 104),
	Accent = Color3.fromRGB(255, 210, 60),
	Good = Color3.fromRGB(90, 220, 110),
	Danger = Color3.fromRGB(255, 76, 90),
	Blue = Color3.fromRGB(70, 160, 255),
	Purple = Color3.fromRGB(176, 100, 255),
	Pink = Color3.fromRGB(255, 110, 190),
	Cyan = Color3.fromRGB(60, 220, 230),
	Orange = Color3.fromRGB(255, 150, 50),
	Grey = Color3.fromRGB(120, 116, 140),
}

function Ui.rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Ui.new(className, props, children)
	local instance = Instance.new(className)
	if className == "Frame" or className == "TextLabel" or className == "TextButton" or className == "ScrollingFrame" or className == "ImageLabel" or className == "TextBox" or className == "ViewportFrame" then
		instance.BorderSizePixel = 0
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		instance.Font = Ui.Fonts.Bold
		instance.TextColor3 = Ui.Colors.Text
		instance.BackgroundTransparency = 1
		instance.TextSize = 18
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

function Ui.stroke(parent, color, thickness, transparency)
	return Ui.new("UIStroke", {
		Color = color or Ui.Colors.Outline,
		Thickness = thickness or 3,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Outline for text (contextual stroke).
function Ui.textStroke(label, thickness)
	return Ui.new("UIStroke", {
		Color = Ui.Colors.Outline,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = label,
	})
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

function Ui.list(parent, padding, direction, hAlign, vAlign)
	return Ui.new("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Ui.gradient(parent, top, bottom)
	return Ui.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
		Parent = parent,
	})
end

local function lighten(c, k)
	return Color3.new(math.min(1, c.R + (1 - c.R) * k), math.min(1, c.G + (1 - c.G) * k), math.min(1, c.B + (1 - c.B) * k))
end
local function darken(c, k)
	return Color3.new(c.R * (1 - k), c.G * (1 - k), c.B * (1 - k))
end
Ui.lighten = lighten
Ui.darken = darken

function Ui.label(text, props)
	props = props or {}
	local label = Ui.new("TextLabel", props)
	label.Text = text
	if props.Font == nil then
		label.Font = Ui.Fonts.Bold
	end
	Ui.textStroke(label, props.StrokeThickness)
	return label
end

function Ui.panel(props)
	local frame = Ui.new("Frame", props)
	frame.BackgroundColor3 = props.BackgroundColor3 or Ui.Colors.Panel
	frame.BackgroundTransparency = props.BackgroundTransparency or 0.05
	Ui.corner(frame, props.Radius or 14)
	Ui.stroke(frame, Ui.Colors.Outline, 3)
	return frame
end

-- Chunky gradient button with a press bounce.
function Ui.button(text, color, props)
	props = props or {}
	color = color or Ui.Colors.Blue
	local button = Ui.new("TextButton", props)
	button.Text = text
	button.AutoButtonColor = false
	button.BackgroundTransparency = 0
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.Font = Ui.Fonts.Title
	button.TextSize = props.TextSize or 20
	button.TextColor3 = Ui.Colors.Text
	button.Selectable = true
	Ui.corner(button, props.Radius or 12)
	Ui.stroke(button, Ui.Colors.Outline, 3)
	Ui.textStroke(button, 2)
	local grad = Ui.gradient(button, lighten(color, 0.25), darken(color, 0.15))
	local scale = Ui.new("UIScale", { Scale = 1, Parent = button })
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.06 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	button:SetAttribute("BaseColor", color)
	return button, grad
end

function Ui.setButtonColor(button, color)
	local grad = button:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(lighten(color, 0.25), darken(color, 0.15))
	end
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

-- Adds a UIScale that shrinks the UI on small (phone) screens.
function Ui.autoScale(screenGui)
	local scale = Ui.new("UIScale", { Scale = 1, Parent = screenGui })
	local function update()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local size = camera.ViewportSize
		if size.X <= 1 or size.Y <= 1 then
			return
		end
		scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.55, 1.2)
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

-- Pops an element in with a bounce (needs or adds a UIScale).
function Ui.pop(instance, from)
	local scale = instance:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = instance })
	scale.Scale = from or 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Little red notification dot on a button.
function Ui.badge(parent)
	local dot = Ui.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.new(0, 18, 0, 18),
		BackgroundColor3 = Ui.Colors.Danger,
		Visible = false,
		ZIndex = (parent.ZIndex or 1) + 2,
		Parent = parent,
	})
	Ui.corner(dot, 9)
	Ui.stroke(dot, Color3.new(1, 1, 1), 2)
	return dot
end

function Ui.progressBar(parent, props)
	local back = Ui.new("Frame", props)
	back.BackgroundColor3 = Ui.Colors.Outline
	back.BackgroundTransparency = 0.2
	Ui.corner(back, 8)
	local fill = Ui.new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = props.FillColor or Ui.Colors.Good, Parent = back })
	Ui.corner(fill, 8)
	back.Parent = parent
	return back, fill
end

return Ui
