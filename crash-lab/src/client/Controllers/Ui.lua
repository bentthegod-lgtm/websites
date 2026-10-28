--[[
	Ui - construction helpers and CRASH LAB's visual language: charcoal and steel-grey
	panels, safety-yellow accent, white primary and muted grey secondary text, green for
	successful upgrades, red for invalid actions, restrained rounded corners.

	Every ScreenGui gets a UIScale that shrinks the layout on phones.
	Windows: one at a time (Ui.openWindow / closeWindow), so menus never stack up.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local DummyModel = require(Shared.DummyModel)
local MachineModels = require(Shared.MachineModels)

local Ui = {}

local function font(name, fallback)
	local ok, value = pcall(function()
		return Enum.Font[name]
	end)
	return if ok and value then value else Enum.Font[fallback]
end

Ui.Fonts = {
	Title = font("GothamBlack", "SourceSansBold"),
	Bold = font("GothamBold", "SourceSansBold"),
	Body = font("GothamMedium", "SourceSans"),
}

Ui.Colors = {
	Panel = Color3.fromRGB(30, 32, 36),
	PanelLight = Color3.fromRGB(44, 47, 54),
	PanelLighter = Color3.fromRGB(62, 66, 76),
	Line = Color3.fromRGB(88, 92, 102),
	Accent = Color3.fromRGB(255, 200, 40),
	AccentDark = Color3.fromRGB(214, 160, 20),
	Text = Color3.fromRGB(245, 245, 245),
	Dim = Color3.fromRGB(160, 162, 170),
	Green = Color3.fromRGB(92, 210, 110),
	Red = Color3.fromRGB(235, 82, 72),
	Blue = Color3.fromRGB(110, 170, 255),
	Purple = Color3.fromRGB(180, 120, 255),
	Black = Color3.fromRGB(10, 10, 12),
}
local C = Ui.Colors

function Ui.rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end


function Ui.new(className, props, children)
	local instance = Instance.new(className)
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
	end
	if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
		instance.Font = Ui.Fonts.Body
		instance.TextColor3 = C.Text
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
	return Ui.new("UIStroke", { Color = color or C.Line, Thickness = thickness or 1, Transparency = transparency or 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
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

function Ui.label(text, props)
	props = props or {}
	props.Text = text
	return Ui.new("TextLabel", props)
end

function Ui.title(text, props)
	props = props or {}
	props.Text = text
	props.Font = Ui.Fonts.Title
	return Ui.new("TextLabel", props)
end

function Ui.panel(props, radius)
	props = props or {}
	props.BackgroundColor3 = props.BackgroundColor3 or C.Panel
	local frame = Ui.new("Frame", props)
	Ui.corner(frame, radius or 12)
	Ui.stroke(frame, C.Line, 1, 0.45)
	return frame
end

Ui.clickHandler = nil
function Ui.click()
	if Ui.clickHandler then
		Ui.clickHandler()
	end
end

function Ui.button(text, props, color)
	props = props or {}
	props.Text = text
	props.AutoButtonColor = false
	props.BackgroundTransparency = 0
	props.BackgroundColor3 = color or C.Accent
	props.Font = props.Font or Ui.Fonts.Bold
	props.TextColor3 = props.TextColor3 or (if color == nil or color == C.Accent or color == C.Green then C.Black else C.Text)
	local button = Ui.new("TextButton", props)
	Ui.corner(button, 8)
	local base = button.BackgroundColor3
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.1), { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play()
	end)
	button.Activated:Connect(Ui.click)
	return button
end

function Ui.setButtonColor(button, color)
	button.BackgroundColor3 = color
	button.TextColor3 = if color == C.Accent or color == C.Green then C.Black else C.Text
end

function Ui.viewportSize()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

function Ui.screen(name, displayOrder)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local gui = Ui.new("ScreenGui", { Name = name, ResetOnSpawn = false, DisplayOrder = displayOrder or 0, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
	local scale = Ui.new("UIScale", { Parent = gui })
	local function fit()
		local size = Ui.viewportSize()
		scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.58, 1.15)
	end
	fit()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	return gui
end

-- Windows -------------------------------------------------------------------------------

local windows = {}
local openName = nil
Ui.WindowOpened = nil -- optional callback(name)

function Ui.window(gui, name, titleText, width, height)
	local frame = Ui.panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		Visible = false,
		Parent = gui,
	}, 14)
	Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.PanelLight, C.Panel), Parent = frame })
	local header = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = frame })
	Ui.title(titleText, { Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(18, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 22, TextColor3 = C.Accent, Parent = header })
	local close = Ui.button("X", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(32, 32), TextSize = 16 }, C.PanelLighter)
	close.Parent = header
	close.Activated:Connect(function()
		Ui.closeWindow(name)
	end)
	local body = Ui.new("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1, Parent = frame })
	Ui.padding(body, 14, 8)
	windows[name] = { frame = frame, body = body, onOpen = {} }
	return frame, body
end

function Ui.onWindowOpen(name, fn)
	if windows[name] then
		table.insert(windows[name].onOpen, fn)
	end
end

function Ui.openWindow(name)
	if openName and openName ~= name then
		Ui.closeWindow(openName)
	end
	local w = windows[name]
	if not w then
		return
	end
	openName = name
	w.frame.Visible = true
	local scale = w.frame:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = w.frame })
	scale.Scale = 0.94
	TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	for _, fn in ipairs(w.onOpen) do
		fn()
	end
	if Ui.WindowOpened then
		Ui.WindowOpened(name)
	end
end

function Ui.closeWindow(name)
	local w = windows[name]
	if w then
		w.frame.Visible = false
	end
	if openName == name then
		openName = nil
		if Ui.WindowOpened then
			Ui.WindowOpened(nil)
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

-- Misc ----------------------------------------------------------------------------------

function Ui.scroll(parent, props)
	props = props or {}
	props.BackgroundTransparency = 1
	props.ScrollBarThickness = props.ScrollBarThickness or 6
	props.ScrollBarImageColor3 = C.Line
	props.CanvasSize = UDim2.new()
	props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	props.Parent = parent
	return Ui.new("ScrollingFrame", props)
end

function Ui.clear(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Ui.bar(parent, props, color)
	local back = Ui.new("Frame", { BackgroundColor3 = C.Black, BackgroundTransparency = 0.35, Size = props.Size, Position = props.Position, AnchorPoint = props.AnchorPoint, LayoutOrder = props.LayoutOrder, Parent = parent })
	Ui.corner(back, 6)
	local fill = Ui.new("Frame", { Name = "Fill", BackgroundColor3 = color or C.Accent, Size = UDim2.fromScale(0, 1), Parent = back })
	Ui.corner(fill, 6)
	return back, fill
end

local function viewport(parent, size, props)
	props = props or {}
	return Ui.new("ViewportFrame", {
		Size = UDim2.fromOffset(size, size),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 150, 150),
		LightColor = Color3.fromRGB(255, 244, 228),
		LightDirection = Vector3.new(-1, -1.4, -0.8),
		Parent = parent,
	})
end

local function frame(view, model, eye, target)
	model.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.CFrame = CFrame.lookAt(eye, target)
	camera.Parent = view
	view.CurrentCamera = camera
end

-- 3D icon of a dummy design.
function Ui.dummyIcon(parent, skinId, size, props)
	local view = viewport(parent, size, props)
	local model = DummyModel.build(skinId, CFrame.new() * CFrame.Angles(0, math.rad(200), 0), { ragdoll = false })
	frame(view, model, Vector3.new(4, 1.5, -14), Vector3.new(0, -1, 0))
	return view
end

-- 3D icon of a launcher.
function Ui.machineIcon(parent, machineId, size, props)
	local view = viewport(parent, size, props)
	local model = MachineModels.build(machineId, CFrame.new())
	frame(view, model, Vector3.new(14, 11, -14), Vector3.new(0, 3, 1))
	return view
end

return Ui
