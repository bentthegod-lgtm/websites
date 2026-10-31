--[[
	InputController - keyboard, gamepad and touch, merged into one kart input.

	  Keyboard  W / Up = gas, S / Down = brake & reverse, A D / Left Right = steer,
	            Shift or Space = drift / hop, R = respawn, F = item (Stage 3 stub),
	            M = menu, Q / E = previous / next kart while spectating
	  Gamepad   RT = gas, LT = brake, left stick = steer, RB (or A) = drift / hop,
	            Y = respawn, X = item, Select = menu, DPad left / right = spectate
	  Touch     on-screen STEER pad (left / right, or a slider stick in Settings), GAS,
	            BRAKE, DRIFT, RESPAWN and ITEM buttons (shown while racing)

	read() -> { gas, brake, steer, drift }. Actions go to the server as requests only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local Net = require(Shared.Net)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local InputController = {}

InputController.menuToggle = nil -- set by MenuController
InputController.spectateStep = nil -- set by SpectateController
InputController.touch = { gas = false, brake = false, left = false, right = false, drift = false, stick = 0 }

local K = Enum.KeyCode
local lastRespawn = -math.huge
local gui

local function down(key)
	local ok, v = pcall(function()
		return UserInputService:IsKeyDown(key)
	end)
	return ok and v == true
end

local function padDown(key)
	local ok, v = pcall(function()
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
	end)
	return ok and v == true
end

local function padState()
	local out = { gas = 0, brake = 0, steer = 0, drift = false }
	local ok, state = pcall(function()
		return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	end)
	if not ok or type(state) ~= "table" then
		return out
	end
	for _, input in ipairs(state) do
		if input.KeyCode == K.ButtonR2 then
			out.gas = math.max(out.gas, input.Position.Z)
		elseif input.KeyCode == K.ButtonL2 then
			out.brake = math.max(out.brake, input.Position.Z)
		elseif input.KeyCode == K.Thumbstick1 then
			local x = input.Position.X
			out.steer = if math.abs(x) < 0.15 then 0 else x
		elseif (input.KeyCode == K.ButtonR1 or input.KeyCode == K.ButtonA) and input.UserInputState == Enum.UserInputState.Begin then
			out.drift = true
		end
	end
	return out
end

function InputController.read()
	local t = InputController.touch
	local pad = padState()
	local gas = if down(K.W) or down(K.Up) or t.gas then 1 else pad.gas
	local brake = if down(K.S) or down(K.Down) or t.brake then 1 else pad.brake
	local steer = 0
	if down(K.A) or down(K.Left) or t.left then
		steer -= 1
	end
	if down(K.D) or down(K.Right) or t.right then
		steer += 1
	end
	if steer == 0 then
		steer = if math.abs(t.stick) > 0.05 then t.stick else pad.steer
	end
	local drift = down(K.LeftShift) or down(K.RightShift) or down(K.Space) or t.drift or pad.drift or padDown(K.ButtonR1) or padDown(K.ButtonA)
	return { gas = math.clamp(gas, 0, 1), brake = math.clamp(brake, 0, 1), steer = math.clamp(steer, -1, 1), drift = drift }
end

function InputController.respawn(reason)
	if not ClientState.inRace() then
		return false
	end
	local now = os.clock()
	if now - lastRespawn < 2.5 then
		return false
	end
	lastRespawn = now
	Net.event("Respawn"):FireServer(reason or "button")
	return true
end

function InputController.item()
	if ClientState.inRace() then
		Net.event("UseItem"):FireServer()
		return true
	end
	return false
end

-- Returns true if the key did something (also used by the harness).
function InputController.handle(keyCode, began)
	if not began then
		return false
	end
	if keyCode == K.R or keyCode == K.ButtonY then
		return InputController.respawn("button")
	elseif keyCode == K.F or keyCode == K.ButtonX then
		return InputController.item()
	elseif keyCode == K.M or keyCode == K.ButtonSelect then
		if InputController.menuToggle then
			InputController.menuToggle()
		end
		return true
	elseif keyCode == K.Q or keyCode == K.DPadLeft or keyCode == K.E or keyCode == K.DPadRight then
		if ClientState.spectating() and InputController.spectateStep then
			InputController.spectateStep(if keyCode == K.Q or keyCode == K.DPadLeft then -1 else 1)
			return true
		end
	end
	return false
end

local function holdButton(parent, name, text, position, size, color, field)
	local b = Ui.button(text, { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = size, TextSize = 20, BackgroundTransparency = 0.25 }, color)
	b.Parent = parent
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.touch[field] = true
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.touch[field] = false
		end
	end)
	return b
end

-- The on-screen controls (touch devices): built once, shown while racing.
function InputController.buildTouch()
	gui = Ui.screen("KartTouch", 5)
	local root = Ui.new("Frame", { Name = "Controls", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })
	local C = Ui.Colors
	holdButton(root, "SteerLeft", "<", UDim2.new(0, 80, 1, -110), UDim2.fromOffset(110, 110), C.PanelLighter, "left")
	holdButton(root, "SteerRight", ">", UDim2.new(0, 205, 1, -110), UDim2.fromOffset(110, 110), C.PanelLighter, "right")
	holdButton(root, "Gas", "GAS", UDim2.new(1, -90, 1, -120), UDim2.fromOffset(130, 130), C.Green, "gas")
	holdButton(root, "Brake", "BRAKE", UDim2.new(1, -230, 1, -80), UDim2.fromOffset(100, 80), C.Red, "brake")
	holdButton(root, "Drift", "DRIFT", UDim2.new(1, -90, 1, -270), UDim2.fromOffset(110, 90), C.Pink, "drift")
	local respawn = Ui.button("RESPAWN", { Name = "Respawn", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -230, 1, -190), Size = UDim2.fromOffset(100, 56), TextSize = 15, BackgroundTransparency = 0.25 }, C.PanelLighter)
	respawn.Parent = root
	respawn.Activated:Connect(function()
		InputController.respawn("button")
	end)
	local item = Ui.button("ITEM", { Name = "Item", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -230, 1, -270), Size = UDim2.fromOffset(90, 56), TextSize = 15, BackgroundTransparency = 0.25 }, C.Accent)
	item.Parent = root
	item.Activated:Connect(InputController.item)
	-- slider stick (Settings > Mobile stick): drag horizontally
	local stick = Ui.new("Frame", { Name = "Stick", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 150, 1, -110), Size = UDim2.fromOffset(240, 70), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.3, Visible = false, Parent = root })
	Ui.corner(stick, 35)
	local knob = Ui.new("Frame", { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = C.Line, Parent = stick })
	Ui.corner(knob, 32)
	stick.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			local x = (input.Position.X - stick.AbsolutePosition.X) / math.max(1, stick.AbsoluteSize.X)
			InputController.touch.stick = math.clamp(x * 2 - 1, -1, 1)
			knob.Position = UDim2.fromScale(math.clamp(x, 0, 1), 0.5)
		end
	end)
	stick.InputEnded:Connect(function()
		InputController.touch.stick = 0
		knob.Position = UDim2.fromScale(0.5, 0.5)
	end)
	InputController.touchRoot = root
	return root
end

function InputController.refreshTouch()
	local root = InputController.touchRoot
	if not root then
		return
	end
	local touch = UserInputService.TouchEnabled == true
	root.Visible = touch and ClientState.inRace()
	local useStick = ClientState.setting("MobileStick") == true
	root.Stick.Visible = useStick
	root.SteerLeft.Visible = not useStick
	root.SteerRight.Visible = not useStick
end

function InputController.init()
	InputController.buildTouch()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		InputController.handle(input.KeyCode, true)
	end)
	ClientState.RaceChanged:Connect(InputController.refreshTouch)
	ClientState.SettingsChanged:Connect(InputController.refreshTouch)
	InputController.refreshTouch()
end

return InputController
