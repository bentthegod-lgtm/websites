--[[
	PhoneController - hold to use your phone.

	Hold F (keyboard), L2 (gamepad) or the big PHONE button (touch / mouse). Release to hide
	it: the hide takes your Hide Speed upgrade's time (the server decides when it's really
	away). While it's out the camera zooms in and the phone UI slides up with 4 apps:

	  FEED    tap LIKE on posts (NEXT for a new one)    keys: Space/E like, S next
	  TEXT    reply with the word your bestie asks for (type it, or tap a quick reply: 1-3)
	  GAME    Tap Dash: tap when the marker is in the green (Space / E / R2)
	  SELFIE  huge Clout, but the FLASH is very risky (Space / E / R2)

	Switch apps with the tabs, Q / Tab (keyboard) or R1 / L1 (gamepad).
	Only "phone up/down", the app and minigame inputs are sent; the server validates all.
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
local Minigames = require(Shared.Minigames)
local CrateRoll = require(Shared.CrateRoll)
local Clock = require(Shared.Clock)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local PhoneController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui, phoneFrame, screen, wallpaper, appArea, tabs, hideBar, hideFill, holdButton, statusTime, capLabel
local apps = {}
local currentApp = "Feed"
local holding = false
local localUp = false
local popupParent
local camera

local POST_COLORS = {
	cat = { 255, 180, 120 }, meme = { 255, 230, 120 }, food = { 255, 140, 90 }, dance = { 200, 120, 255 },
	sports = { 90, 200, 120 }, art = { 120, 200, 255 }, dog = { 230, 190, 140 }, music = { 255, 120, 200 },
	fail = { 160, 160, 180 }, news = { 120, 255, 220 },
}
local POST_ART = {
	cat = "=^.^=", meme = "( -_-)", food = "[PIZZA]", dance = "\\o/ \\o/", sports = "o  -->  (O)", art = "*~*~*",
	dog = "U o_o U", music = "~ d(^_^)b ~", fail = "  _o/ ... ouch", news = "!!! BREAKING !!!",
}

local function play(def)
	AudioUtil.play(def, nil, 0.08)
end

local function canUse()
	return ClientState.status() == "Seated" and ClientState.roundState == "Class"
end

local function view()
	return ClientState.phone and ClientState.phone.view or nil
end

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
-- Apps
---------------------------------------------------------------------------------------------

local function clearArea()
	for _, child in ipairs(appArea:GetChildren()) do
		if not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function sendAction(kind, value)
	if not localUp then
		return
	end
	play(AudioAssets.PhoneTap)
	Net.event("PhoneAction"):FireServer(kind, value)
end

local renderers = {}

function renderers.Feed(v)
	local post = v and v.post
	if not post then
		return
	end
	local card = Ui.panel({ Size = UDim2.new(1, 0, 0, 250), BackgroundColor3 = Color3.fromRGB(250, 250, 255), BackgroundTransparency = 0, ZIndex = 23, Parent = appArea })
	local color = POST_COLORS[post.kind] or { 200, 200, 220 }
	local photo = Ui.new("Frame", { Position = UDim2.fromOffset(8, 30), Size = UDim2.new(1, -16, 0, 150), BackgroundColor3 = Ui.rgb(color), ZIndex = 24, Parent = card })
	Ui.corner(photo, 10)
	Ui.gradient(photo, Ui.rgb(color), Ui.rgb(color):Lerp(Color3.new(1, 1, 1), 0.5), 45)
	Ui.label(POST_ART[post.kind] or "...", { Font = Ui.Fonts.Title, TextSize = 30, TextColor3 = Color3.fromRGB(40, 40, 60), Size = UDim2.fromScale(1, 1), ZIndex = 25, Parent = photo })
	Ui.label("@" .. post.kind .. "_daily", { Font = Ui.Fonts.Bold, TextSize = 14, TextColor3 = Color3.fromRGB(40, 40, 60), Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24, Parent = card })
	if post.viral then
		local badge = Ui.label("VIRAL x4", { Font = Ui.Fonts.Title, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BackgroundColor3 = C.Accent, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(80, 22), ZIndex = 26, Parent = card })
		Ui.corner(badge, 8)
	end
	Ui.label(post.caption, { TextSize = 14, TextColor3 = Color3.fromRGB(50, 50, 70), TextWrapped = true, Position = UDim2.fromOffset(10, 184), Size = UDim2.new(1, -20, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24, Parent = card })
	Ui.label(string.format("%d likes", post.likes + (if post.liked then 1 else 0)), { Font = Ui.Fonts.Bold, TextSize = 13, TextColor3 = Color3.fromRGB(120, 120, 140), Position = UDim2.fromOffset(10, 222), Size = UDim2.new(1, -20, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24, Parent = card })
	local like = Ui.button(if post.liked then "LIKED" else "<3 LIKE", { Position = UDim2.fromOffset(0, 262), Size = UDim2.new(0.5, -4, 0, 56), TextSize = 20, ZIndex = 24, Parent = appArea }, if post.liked then C.PanelLight else C.Accent)
	like.Name = "Primary"
	like.Activated:Connect(function()
		if not post.liked then
			sendAction("like", post.id)
		end
	end)
	local nextButton = Ui.button("NEXT  v", { Position = UDim2.new(0.5, 4, 0, 262), Size = UDim2.new(0.5, -4, 0, 56), TextSize = 20, ZIndex = 24, Parent = appArea }, C.PanelLight)
	nextButton.Name = "Secondary"
	nextButton.Activated:Connect(function()
		sendAction("scroll")
	end)
end

function renderers.Text(v)
	local t = v and v.text
	if not t then
		return
	end
	Ui.label("bestie <3", { Font = Ui.Fonts.Title, TextSize = 18, Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24, Parent = appArea })
	local bubble = Ui.panel({ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(0.85, 0, 0, 70), BackgroundColor3 = Color3.fromRGB(235, 235, 245), BackgroundTransparency = 0, ZIndex = 23, Parent = appArea })
	Ui.label(t.prompt, { TextSize = 16, TextColor3 = Color3.fromRGB(40, 40, 60), TextWrapped = true, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24, Parent = bubble })
	for i, option in ipairs(t.options or {}) do
		local b = Ui.button(string.format("%d  %s", i, option), { Position = UDim2.new(0, 0, 0, 110 + (i - 1) * 50), Size = UDim2.new(1, 0, 0, 44), TextSize = 18, ZIndex = 24, Parent = appArea }, C.Accent2:Lerp(Color3.new(0, 0, 0), 0.25))
		b.Name = "Reply" .. i
		b.Activated:Connect(function()
			sendAction("text", option)
		end)
	end
	local box = Ui.new("TextBox", {
		Name = "Typing",
		PlaceholderText = "or type it + Enter",
		Text = "",
		ClearTextOnFocus = true,
		Font = Ui.Fonts.Bold,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(30, 30, 40),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Position = UDim2.fromOffset(0, 270),
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 24,
		Parent = appArea,
	})
	Ui.corner(box, 10)
	box.FocusLost:Connect(function(enter)
		if enter and box.Text ~= "" then
			sendAction("text", box.Text)
		end
	end)
end

local markerFrame, comboLabel, gameStart
function renderers.Game(v)
	local g = v and v.game
	if not g then
		return
	end
	gameStart = g.start
	local cfg = PhoneConfig.Game
	Ui.label("TAP DASH", { Font = Ui.Fonts.Title, TextSize = 26, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 34), ZIndex = 24, Parent = appArea })
	comboLabel = Ui.label(string.format("combo x%d", v.combo or 0), { Font = Ui.Fonts.Bold, TextSize = 16, TextColor3 = C.Dim, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 20), ZIndex = 24, Parent = appArea })
	local bar = Ui.new("Frame", { Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = Color3.fromRGB(40, 40, 60), ZIndex = 24, Parent = appArea })
	Ui.corner(bar, 12)
	local good = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(cfg.GoodZone * 2, 1), BackgroundColor3 = C.Good:Lerp(Color3.new(0, 0, 0), 0.25), ZIndex = 25, Parent = bar })
	Ui.corner(good, 8)
	local perfect = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(cfg.PerfectZone * 2, 1), BackgroundColor3 = C.Gold, ZIndex = 26, Parent = bar })
	Ui.corner(perfect, 6)
	markerFrame = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 8, 1, 14), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 27, Parent = bar })
	Ui.corner(markerFrame, 4)
	local tap = Ui.button("TAP!", { Position = UDim2.fromOffset(0, 150), Size = UDim2.new(1, 0, 0, 110), TextSize = 40, ZIndex = 24, Parent = appArea }, C.Accent)
	tap.Name = "Primary"
	tap.Activated:Connect(function()
		sendAction("tap", Clock.now())
	end)
	Ui.label("Perfect = gold, Good = green. Combos stack!", { TextSize = 13, TextColor3 = C.Dim, Position = UDim2.fromOffset(0, 270), Size = UDim2.new(1, 0, 0, 20), ZIndex = 24, Parent = appArea })
end

local selfieButton, selfieAt
function renderers.Selfie(v)
	local finder = Ui.panel({ Size = UDim2.new(1, 0, 0, 200), BackgroundColor3 = Color3.fromRGB(20, 20, 30), BackgroundTransparency = 0, ZIndex = 23, Parent = appArea })
	Ui.stroke(finder, Color3.new(1, 1, 1), 0.5, 2)
	local face = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(110, 110), BackgroundColor3 = Color3.fromRGB(255, 210, 170), ZIndex = 24, Parent = finder })
	Ui.corner(face, 55)
	Ui.label("^ ^\n  v", { Font = Ui.Fonts.Title, TextSize = 28, TextColor3 = Color3.fromRGB(60, 40, 40), Size = UDim2.fromScale(1, 1), ZIndex = 25, Parent = face })
	Ui.label("[ REC ]", { Font = Ui.Fonts.Bold, TextSize = 14, TextColor3 = C.Danger, Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(80, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 24, Parent = finder })
	Ui.label("FLASH ON  -  very risky, huge Clout", { Font = Ui.Fonts.Bold, TextSize = 13, TextColor3 = C.Warn, Position = UDim2.fromOffset(0, 206), Size = UDim2.new(1, 0, 0, 20), ZIndex = 24, Parent = appArea })
	selfieButton = Ui.button("SNAP", { Position = UDim2.fromOffset(0, 232), Size = UDim2.new(1, 0, 0, 80), TextSize = 34, ZIndex = 24, Parent = appArea }, Color3.fromRGB(200, 120, 255))
	selfieButton.Name = "Primary"
	selfieButton.Activated:Connect(function()
		sendAction("selfie")
	end)
	selfieAt = v and v.selfieAt or -1e9
end

function PhoneController.render()
	if not appArea then
		return
	end
	clearArea()
	markerFrame, comboLabel, selfieButton = nil, nil, nil
	local renderer = renderers[currentApp]
	if renderer then
		renderer(view())
	end
	for id, tab in pairs(tabs) do
		tab.BackgroundColor3 = if id == currentApp then Ui.rgb(apps[id].Color) else C.PanelLight
	end
	local caps = ClientState.phone and ClientState.phone.caps
	if capLabel then
		capLabel.Text = if caps and caps.used >= caps.total then "Clout cap reached this class - just vibe" else ""
	end
end

function PhoneController.setApp(id)
	if not apps[id] then
		return
	end
	currentApp = id
	Net.event("PhoneApp"):FireServer(id)
	PhoneController.render()
end

local function cycleApp(dir)
	local index = table.find(PhoneConfig.AppOrder, currentApp) or 1
	index = ((index - 1 + dir) % #PhoneConfig.AppOrder) + 1
	PhoneController.setApp(PhoneConfig.AppOrder[index])
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
	-- App tabs
	tabs = {}
	local tabBar = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 50), BackgroundTransparency = 1, ZIndex = 30, Parent = screen })
	for i, def in ipairs(PhoneConfig.Apps) do
		apps[def.Id] = def
		local tab = Ui.button(string.upper(def.Id), { Position = UDim2.new((i - 1) / 4, 2, 0, 0), Size = UDim2.new(0.25, -4, 1, 0), TextSize = 13, ZIndex = 31, Parent = tabBar }, C.PanelLight)
		tab.Activated:Connect(function()
			PhoneController.setApp(def.Id)
		end)
		tabs[def.Id] = tab
	end
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
end

local function primaryAction()
	if not localUp then
		return
	end
	if currentApp == "Feed" then
		local v = view()
		if v and v.post and not v.post.liked then
			sendAction("like", v.post.id)
		end
	elseif currentApp == "Game" then
		sendAction("tap", Clock.now())
	elseif currentApp == "Selfie" then
		sendAction("selfie")
	end
end

local function updateVisibility()
	local seated = canUse()
	holdButton.Visible = seated
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
	end)
	ClientState.PhoneResult:Connect(function(kind, data)
		if data.amount and data.amount > 0 then
			popup(string.format("+%s", if data.amount >= 10 then tostring(math.floor(data.amount)) else string.format("%.1f", data.amount)), C.Gold)
			play(AudioAssets.CloutGain)
		end
		if kind == "tap" and data.info then
			popup(string.upper(data.info), if data.info == "Perfect" then C.Gold elseif data.info == "Good" then C.Good else C.Danger)
		elseif kind == "text" and data.info == "wrong" then
			popup("bestie: ??? wrong word", C.Danger)
		elseif kind == "text" and data.info == "toofast" then
			popup("too fast lol", C.Warn)
		elseif kind == "selfie" and data.ok then
			ClientState.Effect:Fire("SelfFlash", {})
		end
		if data.capped then
			capLabel.Text = "Clout cap reached this class - just vibe"
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
		if processed or not localUp then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Space or key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonR2 or key == Enum.KeyCode.ButtonA then
			primaryAction()
		elseif key == Enum.KeyCode.S and currentApp == "Feed" then
			sendAction("scroll")
		elseif key == Enum.KeyCode.Q or key == Enum.KeyCode.Tab or key == Enum.KeyCode.ButtonR1 then
			cycleApp(1)
		elseif key == Enum.KeyCode.ButtonL1 then
			cycleApp(-1)
		elseif currentApp == "Text" and (key == Enum.KeyCode.One or key == Enum.KeyCode.Two or key == Enum.KeyCode.Three or key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadUp or key == Enum.KeyCode.DPadRight) then
			local index = if key == Enum.KeyCode.One or key == Enum.KeyCode.DPadLeft then 1 elseif key == Enum.KeyCode.Two or key == Enum.KeyCode.DPadUp then 2 else 3
			local v = view()
			local option = v and v.text and v.text.options and v.text.options[index]
			if option then
				sendAction("text", option)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = Clock.now()
		if markerFrame and gameStart then
			markerFrame.Position = UDim2.fromScale(Minigames.markerAt({ start = gameStart }, now, PhoneConfig.Game.Period), 0.5)
		end
		if comboLabel then
			local v = view()
			comboLabel.Text = string.format("combo x%d", v and v.combo or 0)
		end
		if selfieButton then
			local left = PhoneConfig.Selfie.Cooldown - (now - (selfieAt or -1e9))
			selfieButton.Text = if left > 0 then string.format("%.0fs", left) else "SNAP"
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
PhoneController._renderers = renderers
PhoneController._primary = primaryAction

return PhoneController
