--[[
	UI construction helpers and Sprout Valley's cozy visual style (cream panels, chunky
	rounded buttons, brown outlines, FredokaOne titles). Every ScreenGui gets a UIScale
	that shrinks the layout on phones and grows it slightly on big monitors.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local RarityConfig = require(Shared.Config.RarityConfig)
local CropConfig = require(Shared.Config.CropConfig)
local CropModels = require(Shared.CropModels)

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
	Bold = font("GothamBold", "SourceSansBold"),
}

Ui.Colors = {
	Cream = Color3.fromRGB(255, 248, 230),
	CreamDark = Color3.fromRGB(242, 228, 198),
	Brown = Color3.fromRGB(104, 68, 40),
	BrownLight = Color3.fromRGB(168, 120, 78),
	Green = Color3.fromRGB(104, 192, 82),
	GreenDark = Color3.fromRGB(64, 140, 54),
	Orange = Color3.fromRGB(255, 166, 60),
	Sky = Color3.fromRGB(110, 185, 255),
	Red = Color3.fromRGB(236, 92, 80),
	Gold = Color3.fromRGB(255, 205, 60),
	Pink = Color3.fromRGB(255, 130, 200),
	Purple = Color3.fromRGB(170, 120, 255),
	White = Color3.fromRGB(255, 255, 255),
	Dim = Color3.fromRGB(150, 130, 110),
	Shadow = Color3.fromRGB(60, 40, 25),
}
local C = Ui.Colors

function Ui.rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Ui.rarityColor(rarity)
	local tier = RarityConfig.Tiers[rarity]
	return if tier then Ui.rgb(tier.Color) else C.White
end

function Ui.new(className, props, children)
	local instance = Instance.new(className)
	if className == "Frame" or className == "TextLabel" or className == "TextButton" or className == "ScrollingFrame" or className == "ImageLabel" or className == "TextBox" or className == "ViewportFrame" then
		instance.BorderSizePixel = 0
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		instance.Font = Ui.Fonts.Body
		instance.TextColor3 = C.Brown
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

function Ui.stroke(parent, color, thickness, transparency)
	return Ui.new("UIStroke", {
		Color = color or C.Brown,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Ui.textStroke(label, color, thickness)
	return Ui.new("UIStroke", {
		Color = color or C.Shadow,
		Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = label,
	})
end

function Ui.padding(parent, px, py)
	return Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, py or px),
		PaddingBottom = UDim.new(0, py or px),
		Parent = parent,
	})
end

function Ui.list(parent, padding, direction, hAlign, vAlign)
	return Ui.new("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
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

function Ui.label(text, props)
	local label = Ui.new("TextLabel", props)
	label.Text = text
	return label
end

function Ui.title(text, props)
	local label = Ui.new("TextLabel", props)
	label.Text = text
	label.Font = Ui.Fonts.Title
	return label
end

function Ui.panel(props, radius)
	local frame = Ui.new("Frame", props)
	frame.BackgroundColor3 = props.BackgroundColor3 or C.Cream
	Ui.corner(frame, radius or 14)
	Ui.stroke(frame, C.Brown, 3)
	return frame
end

-- Chunky rounded button with a darker bottom edge.
function Ui.button(text, props, color)
	color = color or C.Green
	local button = Ui.new("TextButton", props)
	button.Text = text
	button.AutoButtonColor = true
	button.BackgroundTransparency = 0
	button.BackgroundColor3 = color
	button.Font = Ui.Fonts.Title
	button.TextColor3 = C.White
	button.TextSize = props and props.TextSize or 18
	Ui.corner(button, 10)
	Ui.stroke(button, color:Lerp(Color3.new(0, 0, 0), 0.45), 2.5)
	Ui.textStroke(button, color:Lerp(Color3.new(0, 0, 0), 0.6), 1.5)
	Ui.gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215))
	button.Activated:Connect(function()
		Ui.click()
		local scale = button:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = button })
		scale.Scale = 0.92
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	return button
end

-- Set by EffectsController so every button click makes a sound.
Ui.clickHandler = nil
function Ui.click()
	if Ui.clickHandler then
		Ui.clickHandler()
	end
end

-- Camera viewport size, or nil when there is no camera yet.
function Ui.viewportSize()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ok, size = pcall(function()
		return camera.ViewportSize
	end)
	return if ok then size else nil
end

function Ui.screen(name, displayOrder)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 1,
		Parent = playerGui,
	})
	local scale = Ui.new("UIScale", { Parent = gui })
	local function update()
		local size = Ui.viewportSize()
		if size and size.X > 0 then
			scale.Scale = math.clamp(math.min(size.X / 1150, size.Y / 680), 0.5, 1.2)
		end
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return gui, scale
end

-- The UIScale applied to a ScreenGui (for converting screen pixels to layout pixels).
function Ui.scaleOf(gui)
	local s = gui:FindFirstChildOfClass("UIScale")
	return if s then s.Scale else 1
end

---------------------------------------------------------------------------------------------
-- Windows (only one open at a time)
---------------------------------------------------------------------------------------------

local windows = {}
local openName = nil
Ui.WindowChanged = nil -- set by controllers that want to know (Signal from ClientState)

function Ui.window(gui, name, titleText, width, height, accent)
	accent = accent or C.Green
	local frame = Ui.panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(width, height),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	local header = Ui.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = accent,
		ZIndex = 21,
		Parent = frame,
	})
	Ui.corner(header, 12)
	Ui.gradient(header, Color3.new(1, 1, 1), Color3.fromRGB(220, 220, 220))
	local title = Ui.title(titleText, {
		Size = UDim2.new(1, -110, 1, 0),
		Position = UDim2.fromOffset(18, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 28,
		TextColor3 = C.White,
		ZIndex = 22,
		Parent = header,
	})
	Ui.textStroke(title, accent:Lerp(Color3.new(0, 0, 0), 0.6), 2)
	local close = Ui.button("X", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(40, 38),
		TextSize = 22,
		ZIndex = 23,
		Parent = header,
	}, C.Red)
	close.Activated:Connect(function()
		Ui.closeWindow(name)
	end)
	local body = Ui.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = frame,
	})
	Ui.padding(body, 12, 6)
	windows[name] = { frame = frame, title = title, onOpen = nil }
	return frame, body, title
end

function Ui.onWindowOpen(name, fn)
	if windows[name] then
		windows[name].onOpen = fn
	end
end

function Ui.openWindow(name)
	for n, w in pairs(windows) do
		w.frame.Visible = n == name
	end
	openName = name
	local w = windows[name]
	if w then
		local scale = w.frame:FindFirstChild("PopScale") or Ui.new("UIScale", { Name = "PopScale", Parent = w.frame })
		scale.Scale = 0.85
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if w.onOpen then
			w.onOpen()
		end
	end
	if Ui.WindowChanged then
		Ui.WindowChanged:Fire(name)
	end
end

function Ui.closeWindow(name)
	local w = windows[name]
	if w then
		w.frame.Visible = false
	end
	if openName == name then
		openName = nil
		if Ui.WindowChanged then
			Ui.WindowChanged:Fire(nil)
		end
	end
end

function Ui.toggleWindow(name)
	if openName == name then
		Ui.closeWindow(name)
	else
		Ui.openWindow(name)
	end
end

function Ui.isOpen(name)
	return openName == name
end

function Ui.openWindowName()
	return openName
end

function Ui.closeAll()
	if openName then
		Ui.closeWindow(openName)
	end
end

---------------------------------------------------------------------------------------------
-- Common widgets
---------------------------------------------------------------------------------------------

function Ui.scroll(parent, props)
	local frame = Ui.new("ScrollingFrame", props)
	frame.BackgroundTransparency = 1
	frame.ScrollBarThickness = 8
	frame.ScrollBarImageColor3 = C.BrownLight
	frame.CanvasSize = UDim2.new()
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.ScrollingDirection = Enum.ScrollingDirection.Y
	frame.Parent = parent
	return frame
end

function Ui.clear(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Ui.coinIcon(parent, size, props)
	local coin = Ui.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.Gold,
		Parent = parent,
	})
	for k, v in pairs(props or {}) do
		coin[k] = v
	end
	Ui.corner(coin, size)
	Ui.stroke(coin, Color3.fromRGB(190, 130, 20), 2)
	Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 232, 140),
		ZIndex = coin.ZIndex + 1,
		Parent = coin,
	}, { Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	return coin
end

function Ui.bar(parent, props, color)
	local back = Ui.new("Frame", props)
	back.BackgroundColor3 = C.CreamDark
	back.Parent = parent
	Ui.corner(back, 8)
	Ui.stroke(back, C.BrownLight, 1.5)
	local fill = Ui.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color or C.Green,
		ZIndex = back.ZIndex + 1,
		Parent = back,
	})
	Ui.corner(fill, 8)
	return back, fill
end

-- Small 3D preview of a crop (ripe model) inside a ViewportFrame.
local previewCache = {}
function Ui.cropIcon(parent, cropId, size, props)
	local crop = CropConfig.ById[cropId]
	local vp = Ui.new("ViewportFrame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = if crop then Ui.rarityColor(crop.Rarity):Lerp(C.Cream, 0.55) else C.CreamDark,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = parent,
	})
	for k, v in pairs(props or {}) do
		vp[k] = v
	end
	Ui.corner(vp, 10)
	if not crop then
		return vp
	end
	local ok = pcall(function()
		local template = previewCache[cropId]
		if not template then
			template = CropModels.build(crop, 4, CFrame.new(0, 0, 0), { seed = 7 })
			for _, d in ipairs(template:GetDescendants()) do
				if d:IsA("ParticleEmitter") or d:IsA("PointLight") then
					d:Destroy()
				end
			end
			previewCache[cropId] = template
		end
		local model = template:Clone()
		model.Parent = vp
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		local tall = if crop.Model.Type == "Tree" or crop.Model.Type == "Palm" or crop.Model.Type == "Stalk" then 4.2 else 1.8
		local distance = if tall > 3 then 13 else 7.5
		camera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.6, tall + distance * 0.35, -distance * 0.8), Vector3.new(0, tall * 0.55, 0))
		camera.Parent = vp
		vp.CurrentCamera = camera
	end)
	if not ok then
		vp.BackgroundColor3 = C.CreamDark
	end
	return vp
end

-- Text chip like "Wet" / "Golden" with the mutation colour.
function Ui.chip(parent, text, color, order)
	local chip = Ui.label(text, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		TextColor3 = C.White,
		Font = Ui.Fonts.Bold,
		TextSize = 13,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	Ui.corner(chip, 8)
	Ui.padding(chip, 6, 0)
	Ui.textStroke(chip, color:Lerp(Color3.new(0, 0, 0), 0.6), 1)
	return chip
end

-- Animated rainbow text gradient for Prismatic items.
function Ui.prismatic(label)
	local g = Ui.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 120)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 230, 120)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 255, 170)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(120, 180, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 130, 255)),
		}),
		Parent = label,
	})
	Ui.prismaticGradients = Ui.prismaticGradients or {}
	table.insert(Ui.prismaticGradients, g)
	return g
end

return Ui
