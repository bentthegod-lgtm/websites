--[[
	PhoneController - hold to use your phone, screenshot your test, read the answers.

	Hold F (keyboard), L2 (gamepad) or the big PHONE button (touch / mouse). Release to hide
	it: the hide takes your Hide Speed upgrade's time (the server decides when it's really
	away). While it's out the camera zooms in and the phone UI slides up with the scanner:

	  SNAP     Space / E / R2 / the SNAP button: aim at your test (the camera "lines up"),
	           click + flash, then the scanner app processes. KEEP THE PHONE OUT until the
	           bar fills, or the screenshot is lost.
	  ANSWERS  the answers you have earned (only you can see them): "Q3 -> C".
	  WATCH    (Smart Watch upgrade) W / Y / the WATCH button: works with the phone AWAY.
	  PEEK     Answer Key Peek token: P / the PEEK button.

	Then put the phone away and click those answers on your test (TestController).
	Only Phone(up/down) and PhoneAction("snap" | "watch" | "peek") are sent.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local Net = require(Shared.Net)
local PhoneConfig = require(Shared.Config.PhoneConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)
local CrateRoll = require(Shared.CrateRoll)
local Clock = require(Shared.Clock)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local PhoneController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui, phoneFrame, screen, wallpaper, appArea, hideBar, hideFill, holdButton, statusTime, capLabel, watchButton
local progressFill, progressLabel, snapButton
local holding = false
local localUp = false
local popupParent
local camera

local function play(def)
	AudioUtil.play(def, nil, 0.08)
end

local function canUse()
	return ClientState.status() == "Seated" and ClientState.roundState == "Class"
end

local function phone()
	return ClientState.phone or {}
end

local LETTERS = { "A", "B", "C", "D" }

---------------------------------------------------------------------------------------------
-- Floating "+3" popups
---------------------------------------------------------------------------------------------

local function popup(text, color)
	if not popupParent then
		return
	end
	local label = Ui.label(text, {
		Font = Ui.Fonts.Title,
		TextSize = 26,
		TextColor3 = color or C.Gold,
		TextStrokeTransparency = 0.3,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5 + (math.random() - 0.5) * 0.4, 0, 0.35, 0),
		Size = UDim2.fromOffset(160, 34),
		ZIndex = 40,
		Parent = popupParent,
	})
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = label.Position - UDim2.fromOffset(0, 70), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1, function()
		label:Destroy()
	end)
end
PhoneController.popup = popup

---------------------------------------------------------------------------------------------
-- Scanner app
---------------------------------------------------------------------------------------------

local function sendAction(kind)
	play(AudioAssets.PhoneTap)
	Net.event("PhoneAction"):FireServer(kind)
end

function PhoneController.render()
	if not appArea then
		return
	end
	for _, child in ipairs(appArea:GetChildren()) do
		if not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	local p = phone()
	Ui.label("ScanBuddy", { Font = Ui.Fonts.Title, TextSize = 26, TextColor3 = C.Accent2, Size = UDim2.new(1, 0, 0, 30), ZIndex = 24, Parent = appArea })
	Ui.label(string.format("%d answers per snap  |  %.1fs scan", p.answersPerSnap or 2, p.scanSeconds or 6), { Font = Ui.Fonts.Bold, TextSize = 13, TextColor3 = C.Dim, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 18), ZIndex = 24, Parent = appArea })
	-- Viewfinder over the test
	local finder = Ui.panel({ Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 120), BackgroundColor3 = Color3.fromRGB(250, 250, 240), BackgroundTransparency = 0, ZIndex = 23, Parent = appArea })
	Ui.stroke(finder, Color3.new(1, 1, 1), 0.3, 2)
	for i = 1, 5 do
		Ui.new("Frame", { Position = UDim2.new(0.12, 0, 0, 14 + i * 17), Size = UDim2.new(0.76, 0, 0, 3), BackgroundColor3 = Color3.fromRGB(120, 130, 180), ZIndex = 24, Parent = finder })
	end
	Ui.label("[  TEST  ]", { Font = Ui.Fonts.Bold, TextSize = 13, TextColor3 = Color3.fromRGB(80, 80, 120), Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 18), ZIndex = 25, Parent = finder })
	local scan = p.scan
	local progress = Ui.new("Frame", { Position = UDim2.fromOffset(0, 182), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.PanelLight, ZIndex = 24, Parent = appArea })
	Ui.corner(progress, 8)
	progressFill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Good, ZIndex = 25, Parent = progress })
	Ui.corner(progressFill, 8)
	progressLabel = Ui.label(if scan then (if scan.stage == "aim" then "LINING UP..." else "SCANNING... keep it out!") else "ready", { Font = Ui.Fonts.Bold, TextSize = 14, Size = UDim2.fromScale(1, 1), ZIndex = 26, Parent = progress })
	local remaining = p.remaining or 0
	snapButton = Ui.button(if scan then "SCANNING..." elseif remaining <= 0 then "ALL REVEALED" else "SNAP TEST", { Name = "Primary", Position = UDim2.fromOffset(0, 214), Size = UDim2.new(1, 0, 0, 64), TextSize = 26, ZIndex = 24, Parent = appArea }, if scan or remaining <= 0 then C.PanelLight else Color3.fromRGB(200, 120, 255))
	snapButton.Activated:Connect(function()
		PhoneController.snap()
	end)
	-- Answers revealed so far (only this player ever receives these).
	Ui.label("YOUR ANSWERS", { Font = Ui.Fonts.Title, TextSize = 15, TextColor3 = C.Gold, Position = UDim2.fromOffset(0, 284), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24, Parent = appArea })
	local list = {}
	for _, r in ipairs(p.revealed or {}) do
		table.insert(list, string.format("Q%d: %s", r.slot, LETTERS[r.option] or "?"))
	end
	Ui.label(if #list > 0 then table.concat(list, "   ") else "none yet - snap your test!", { Font = Ui.Fonts.Bold, TextSize = 16, TextWrapped = true, TextColor3 = C.Text, Position = UDim2.fromOffset(0, 304), Size = UDim2.new(1, 0, 0, 70), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 24, Parent = appArea })
	capLabel.Text = "Aim + flash + scan = risk. Hide it and it's lost!"
end

function PhoneController.snap()
	if localUp then
		sendAction("snap")
	end
end

function PhoneController.watch()
	if canUse() then
		sendAction("watch")
	end
end

---------------------------------------------------------------------------------------------
-- Up / down
---------------------------------------------------------------------------------------------

local function applyWallpaper()
	local profile = ClientState.profile
	local item = profile and CrateRoll.find(CosmeticConfig, "Wallpaper", profile.equipped and profile.equipped.Wallpaper or "Default")
	local colors = item and item.Colors or { { 30, 30, 60 }, { 10, 10, 25 } }
	local g = wallpaper:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(Ui.rgb(colors[1]), Ui.rgb(colors[2]))
	end
end

local function slide(up)
	localUp = up
	ClientState.LocalPhone:Fire(up)
	local target = if up then UDim2.new(0.5, 0, 1, -12) else UDim2.new(0.5, 0, 1, 600)
	local hide = ClientState.phone and ClientState.phone.hide or 0.45
	TweenService:Create(phoneFrame, TweenInfo.new(if up then 0.18 else hide, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
	camera = workspace.CurrentCamera or camera -- the current camera can be replaced
	if camera then
		TweenService:Create(camera, TweenInfo.new(0.25), { FieldOfView = if up then 52 else 70 }):Play()
	end
	if up then
		play(AudioAssets.PhoneOut)
		hideBar.Visible = false
	else
		play(AudioAssets.PhoneAway)
		hideBar.Visible = true
		hideFill.Size = UDim2.fromScale(0, 1)
		TweenService:Create(hideFill, TweenInfo.new(hide, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
		task.delay(hide + 0.05, function()
			if not localUp then
				hideBar.Visible = false
			end
		end)
	end
end

function PhoneController.press()
	if holding then
		return
	end
	holding = true
	local phone = ClientState.phone
	if not canUse() or (phone and (phone.confiscated or Clock.now() < (phone.cooldownUntil or 0))) then
		if phone and phone.confiscated then
			ClientState.Notified:Fire("Your phone is in the CONFISCATED basket!", "warn")
		elseif phone and Clock.now() < (phone.cooldownUntil or 0) then
			ClientState.Notified:Fire("Lay low for a few seconds first...", "warn")
		end
		return
	end
	Net.event("Phone"):FireServer(true)
	slide(true)
	PhoneController.render()
end

function PhoneController.release()
	if not holding then
		return
	end
	holding = false
	if localUp then
		Net.event("Phone"):FireServer(false)
		slide(false)
	end
end

function PhoneController.isUp()
	return localUp
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

local function build()
	gui = Ui.screen("PA_Phone", player:WaitForChild("PlayerGui"), 4)
	popupParent = gui
	phoneFrame = Ui.new("Frame", { Name = "Phone", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 600), Size = UDim2.fromOffset(310, 560), BackgroundColor3 = Color3.fromRGB(16, 16, 20), ZIndex = 20, Parent = gui })
	Ui.corner(phoneFrame, 40)
	Ui.stroke(phoneFrame, Color3.fromRGB(90, 90, 110), 0.2, 3)
	screen = Ui.new("Frame", { Name = "Screen", Position = UDim2.fromOffset(12, 14), Size = UDim2.new(1, -24, 1, -28), BackgroundColor3 = Color3.new(1, 1, 1), ClipsDescendants = true, ZIndex = 21, Parent = phoneFrame })
	Ui.corner(screen, 30)
	wallpaper = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 21, Parent = screen })
	Ui.corner(wallpaper, 30)
	Ui.gradient(wallpaper, Color3.fromRGB(30, 30, 60), Color3.fromRGB(10, 10, 25), 90)
	-- Status bar
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(90, 22), BackgroundColor3 = Color3.fromRGB(10, 10, 12), ZIndex = 30, Parent = screen }, { Ui.new("UICorner", { CornerRadius = UDim.new(0, 11) }) })
	statusTime = Ui.label("10:05", { Font = Ui.Fonts.Bold, TextSize = 14, Position = UDim2.fromOffset(22, 8), Size = UDim2.fromOffset(60, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 30, Parent = screen })
	Ui.label("5G  [|||]", { Font = Ui.Fonts.Bold, TextSize = 12, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 9), Size = UDim2.fromOffset(80, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 30, Parent = screen })
	appArea = Ui.new("Frame", { Name = "AppArea", Position = UDim2.fromOffset(14, 40), Size = UDim2.new(1, -28, 1, -112), BackgroundTransparency = 1, ZIndex = 22, Parent = screen })
	capLabel = Ui.label("", { TextSize = 12, TextColor3 = C.Warn, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -66), Size = UDim2.new(1, -28, 0, 16), ZIndex = 30, Parent = screen })
	-- "Hiding..." bar
	hideBar = Ui.panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150), Size = UDim2.fromOffset(240, 34), Visible = false, ZIndex = 35, Parent = gui })
	Ui.label("HIDING...", { Font = Ui.Fonts.Title, TextSize = 16, Size = UDim2.fromScale(1, 1), ZIndex = 37, Parent = hideBar })
	hideFill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Good, BackgroundTransparency = 0.4, ZIndex = 36, Parent = hideBar })
	Ui.corner(hideFill, 12)
	-- Big hold button (touch + mouse); also the visual hint for F / L2.
	holdButton = Ui.button("HOLD\nPHONE", { Name = "HoldPhone", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -150), Size = UDim2.fromOffset(120, 120), TextSize = 22, Visible = false, ZIndex = 15, Parent = gui }, C.Accent)
	Ui.corner(holdButton, 60)
	Ui.label("F / L2", { Font = Ui.Fonts.Bold, TextSize = 13, TextColor3 = C.Text, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(120, 18), ZIndex = 15, Parent = holdButton })
	holdButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			PhoneController.press()
			-- The button's InputEnded doesn't fire when the finger / mouse slides off it before
			-- letting go, which left the phone stuck out. Watch this input itself instead.
			local connection
			connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
					connection:Disconnect()
					PhoneController.release()
				end
			end)
		end
	end)
	holdButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			PhoneController.release()
		end
	end)
	-- Smart watch (works with the phone away) and Answer Key Peek buttons.
	watchButton = Ui.button("WATCH", { Name = "Watch", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -150, 1, -150), Size = UDim2.fromOffset(90, 50), TextSize = 16, Visible = false, ZIndex = 15, Parent = gui }, C.Accent2:Lerp(Color3.new(0, 0, 0), 0.3))
	watchButton.Activated:Connect(PhoneController.watch)
end

local function primaryAction()
	if localUp then
		PhoneController.snap()
	end
end

local function updateVisibility()
	local seated = canUse()
	holdButton.Visible = seated
	watchButton.Visible = seated and phone().watch ~= nil
	if not seated and localUp then
		holding = false
		slide(false)
	end
	-- No jumping out of your chair during class.
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function()
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, ClientState.status() == "Hallway")
		end)
	end
end

function PhoneController.init()
	camera = workspace.CurrentCamera
	build()
	ClientState.PhoneChanged:Connect(function(data)
		if data and (data.confiscated or data.state == "down") and localUp and not holding then
			slide(false)
		end
		if data and data.confiscated and localUp then
			holding = false
			slide(false)
		end
		PhoneController.render()
		updateVisibility()
	end)
	ClientState.PhoneResult:Connect(function(kind, data)
		if kind == "aim" then
			popup("lining up...", C.Accent2)
		elseif kind == "shutter" then
			play(AudioAssets.SelfieShutter)
			ClientState.Effect:Fire("SelfFlash", {})
			popup("*CLICK*", C.Warn)
		elseif kind == "scanFailed" then
			popup("SCAN LOST! (phone hidden)", C.Danger)
		elseif kind == "watch" then
			popup("checking your watch...", C.Accent2)
		elseif kind == "reveal" then
			local parts = {}
			for _, r in ipairs(data.answers or {}) do
				table.insert(parts, string.format("Q%d = %s", r.slot, LETTERS[r.option] or "?"))
			end
			if #parts > 0 then
				popup(table.concat(parts, "  "), C.Gold)
				play(AudioAssets.CloutGain)
			end
			if ClientState.phone and data.all then
				ClientState.phone.revealed = data.all
			end
			ClientState.AnswersRevealed:Fire(data.all or {}, data.source)
		end
		PhoneController.render()
	end)
	ClientState.ProfileChanged:Connect(applyWallpaper)
	ClientState.RoundChanged:Connect(function()
		updateVisibility()
	end)
	player:GetAttributeChangedSignal("PA_Status"):Connect(updateVisibility)
	player.CharacterAdded:Connect(function()
		task.defer(updateVisibility)
	end)

	ContextActionService:BindAction("PA_PhoneHold", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			PhoneController.press()
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			PhoneController.release()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonL2)

	-- Alt-tab / app switch while holding: the key-up never arrives, so hide the phone.
	UserInputService.WindowFocusReleased:Connect(function()
		PhoneController.release()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if localUp and (key == Enum.KeyCode.Space or key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonR2 or key == Enum.KeyCode.ButtonA) then
			primaryAction()
		elseif key == Enum.KeyCode.W or key == Enum.KeyCode.ButtonY then
			PhoneController.watch()
		elseif key == Enum.KeyCode.P then
			if canUse() then
				sendAction("peek")
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = Clock.now()
		local p = phone()
		local scan = p.scan
		if progressFill then
			if scan and scan.untilT then
				local length = if scan.stage == "aim" then PhoneConfig.Snap.AimSeconds else (p.scanSeconds or 6)
				progressFill.Size = UDim2.fromScale(math.clamp(1 - (scan.untilT - now) / length, 0, 1), 1)
				progressFill.BackgroundColor3 = if scan.stage == "aim" then C.Warn else C.Good
				if progressLabel then
					progressLabel.Text = if scan.stage == "aim" then "LINING UP..." else string.format("SCANNING %.1fs - keep it out!", math.max(0, scan.untilT - now))
				end
			else
				progressFill.Size = UDim2.fromScale(0, 1)
			end
		end
		if watchButton and p.watch then
			local w = p.watch
			if w.untilT and now < w.untilT then
				watchButton.Text = "LOOKING..."
			elseif now < (w.cooldownUntil or 0) then
				watchButton.Text = string.format("WATCH %ds", math.ceil(w.cooldownUntil - now))
			else
				watchButton.Text = "WATCH (W)"
			end
		end
		if statusTime then
			statusTime.Text = workspace:GetAttribute("PA_Clock") or "10:05"
		end
	end)
	applyWallpaper()
	updateVisibility()
	PhoneController.render()
end

-- Harness hooks
PhoneController._primary = primaryAction

return PhoneController
