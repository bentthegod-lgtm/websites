--[[
	HudController - the always-on HUD:
	  top:     cash counter (+$/s, multiplier), server feed
	  left:    SHOP / REBIRTH / DAILY / INDEX / CODES / INVITE buttons (+ settings gear)
	  right:   events with countdowns, session goals
	  bottom:  SLAP, LOCK and DROP action buttons, toasts
	  center:  carry banner, thief alarm
	Works with mouse, touch and gamepad (all buttons are Selectable; see InputController).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local GameConfig = require(Shared.Config.GameConfig)
local RarityConfig = require(Shared.Config.RarityConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local HudController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui
local cashLabel, ipsLabel, multLabel, slotsLabel
local feedFrame, toastFrame
local eventsFrame, goalsFrame
local lockButton, slapButton, dropButton
local carryBanner, carryText, alarmFrame, alarmText
local menuButtons = {}
local goalsCollapsed = false
local shownCash = 0
local lastSlapPress = 0

-- Set by MenuController so HUD buttons can open panels without a require cycle.
HudController.openPanel = function(_name) end

---------------------------------------------------------------------------------------------
-- Actions (also bound to keys by InputController)
---------------------------------------------------------------------------------------------

function HudController.slap()
	local now = os.clock()
	if now - lastSlapPress < GameConfig.Slap.Cooldown then
		return
	end
	lastSlapPress = now
	Net.event("Slap"):FireServer()
	if slapButton then
		Ui.pop(slapButton, 0.8)
	end
end

function HudController.lock()
	Net.event("LockBase"):FireServer()
	AudioController.play("Click")
end

function HudController.drop()
	if ClientState.carry then
		Net.event("DropCarried"):FireServer()
	end
end

function HudController.invite()
	task.spawn(function()
		local okCan, canInvite = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if okCan and canInvite then
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		else
			HudController.toast("Invites aren't available right now.", "warn")
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Toasts and feed
---------------------------------------------------------------------------------------------

local KIND_COLORS = {
	info = C.Blue,
	warn = C.Orange,
	danger = C.Danger,
	good = C.Good,
	gold = C.Accent,
}

function HudController.toast(text, kind)
	if not toastFrame then
		return
	end
	local color = KIND_COLORS[kind or "info"] or C.Blue
	local toast = Ui.panel({
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Ui.darken(color, 0.45),
		LayoutOrder = -math.floor(os.clock() * 10),
		Parent = toastFrame,
	})
	Ui.label(text, { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Parent = toast })
	Ui.pop(toast, 0.7)
	local children = toastFrame:GetChildren()
	local frames = {}
	for _, child in ipairs(children) do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	if #frames > 3 then
		table.sort(frames, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		frames[#frames]:Destroy()
	end
	task.delay(3.5, function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			task.wait(0.4)
			toast:Destroy()
		end
	end)
end

function HudController.feed(text, color)
	if not feedFrame then
		return
	end
	local c = if type(color) == "table" then Ui.rgb(color) else C.Text
	local line = Ui.label(text, {
		Size = UDim2.new(1, 0, 0, 24),
		TextScaled = true,
		TextColor3 = c,
		LayoutOrder = -math.floor(os.clock() * 100),
		Parent = feedFrame,
	})
	Ui.pop(line, 0.85)
	local lines = {}
	for _, child in ipairs(feedFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	if #lines > 4 then
		table.sort(lines, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		for i = 5, #lines do
			lines[i]:Destroy()
		end
	end
	task.delay(8, function()
		if line.Parent then
			TweenService:Create(line, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			task.wait(0.6)
			line:Destroy()
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

local function buildCash()
	local frame = Ui.panel({
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0, 300, 0, 86),
		Parent = gui,
	})
	Ui.gradient(frame, Color3.fromRGB(70, 52, 120), Color3.fromRGB(40, 28, 72))
	cashLabel = Ui.label("$0", { Font = Ui.Fonts.Title, Size = UDim2.new(1, -20, 0, 50), Position = UDim2.new(0, 10, 0, 4), TextScaled = true, TextColor3 = C.Good, StrokeThickness = 3, Parent = frame })
	ipsLabel = Ui.label("+$0/s", { Size = UDim2.new(0.6, -10, 0, 24), Position = UDim2.new(0, 10, 0, 56), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 255, 200), Parent = frame })
	multLabel = Ui.label("x1", { Size = UDim2.new(0.4, -10, 0, 24), Position = UDim2.new(0.6, 0, 0, 56), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Accent, Parent = frame })
	Ui.new("UIScale", { Parent = frame })
	slotsLabel = Ui.label("", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.new(1, 0, 0, 20), TextScaled = true, TextColor3 = C.Dim, Parent = frame })

	feedFrame = Ui.new("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 124),
		Size = UDim2.new(0, 560, 0, 112),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.list(feedFrame, 2)
end

local function menuButton(name, text, color, order)
	local button = Ui.button(text, color, { Name = name, Size = UDim2.new(0, 132, 0, 48), LayoutOrder = order, TextSize = 22 })
	menuButtons[name] = button
	Ui.badge(button)
	return button
end

local function buildMenu()
	local column = Ui.new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		-- a bit below centre so it clears the chat window in the top-left corner
		Position = UDim2.new(0, 12, 0.5, 40),
		Size = UDim2.new(0, 140, 0, 420),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.list(column, 8, nil, Enum.HorizontalAlignment.Left)
	local defs = {
		{ "Shop", "SHOP", C.Good },
		{ "Rebirth", "REBIRTH", C.Accent },
		{ "Daily", "DAILY", C.Blue },
		{ "Index", "INDEX", C.Purple },
		{ "Codes", "CODES", C.Pink },
		{ "Invite", "INVITE", C.Cyan },
	}
	for i, def in ipairs(defs) do
		local button = menuButton(def[1], def[2], def[3], i)
		button.Parent = column
		button.Activated:Connect(function()
			AudioController.play("Click")
			if def[1] == "Invite" then
				HudController.invite()
			else
				HudController.openPanel(def[1])
			end
		end)
	end
	menuButtons.Shop.Size = UDim2.new(0, 140, 0, 60)
	menuButtons.Shop.TextSize = 28
	local gear = Ui.button("SETTINGS", C.Grey, { Name = "Settings", Size = UDim2.new(0, 132, 0, 34), TextSize = 16, LayoutOrder = 10, Parent = column })
	gear.Activated:Connect(function()
		HudController.openPanel("Settings")
	end)
end

local function buildRight()
	-- Starts below the top-right corner, where Roblox shows the player list.
	eventsFrame = Ui.new("Frame", {
		Name = "Events",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0.27, 0),
		Size = UDim2.new(0, 270, 0, 150),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.list(eventsFrame, 4, nil, Enum.HorizontalAlignment.Right)

	goalsFrame = Ui.panel({
		Name = "Goals",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0.27, 160),
		Size = UDim2.new(0, 270, 0, 196),
		BackgroundTransparency = 0.2,
		ClipsDescendants = true,
		Parent = gui,
	})
	Ui.padding(goalsFrame, 8)
	Ui.list(goalsFrame, 6)
	-- Phones: goals start collapsed so they don't cover the action buttons; tap to open.
	goalsCollapsed = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function HudController.toggleGoals()
	goalsCollapsed = not goalsCollapsed
	goalsFrame.Size = UDim2.new(0, 270, 0, if goalsCollapsed then 40 else 196)
end

local function buildActions()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local holder = Ui.new("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = if touch then UDim2.new(1, -24, 1, -180) else UDim2.new(1, -24, 1, -24),
		Size = UDim2.new(0, 260, 0, 120),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	slapButton = Ui.button("SLAP!", C.Danger, { Name = "Slap", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0, 104, 0, 104), TextSize = 30, Radius = 52, Parent = holder })
	slapButton.Activated:Connect(HudController.slap)
	lockButton = Ui.button("LOCK", C.Blue, { Name = "Lock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -116, 1, 0), Size = UDim2.new(0, 140, 0, 50), TextSize = 20, Parent = holder })
	lockButton.Activated:Connect(HudController.lock)
	dropButton = Ui.button("DROP", C.Orange, { Name = "Drop", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -116, 1, -58), Size = UDim2.new(0, 140, 0, 44), TextSize = 18, Visible = false, Parent = holder })
	dropButton.Activated:Connect(HudController.drop)
	local hint = if UserInputService.KeyboardEnabled then "F slap  |  L lock  |  G drop  |  B shop" else ""
	Ui.label(hint, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 1, 4), Size = UDim2.new(0, 260, 0, 16), TextScaled = true, TextColor3 = C.Dim, Parent = holder })
end

local function buildCenter()
	toastFrame = Ui.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.new(0, 460, 0, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.list(toastFrame, 6, nil, nil, Enum.VerticalAlignment.Bottom)

	carryBanner = Ui.panel({
		Name = "Carry",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.26, 0),
		Size = UDim2.new(0, 520, 0, 64),
		BackgroundColor3 = Color3.fromRGB(150, 30, 40),
		Visible = false,
		Parent = gui,
	})
	carryText = Ui.label("", { Font = Ui.Fonts.Title, Size = UDim2.new(1, -20, 1, -8), Position = UDim2.new(0, 10, 0, 4), TextScaled = true, Parent = carryBanner })

	alarmFrame = Ui.new("Frame", {
		Name = "Alarm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 0, 30),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 0,
		Parent = gui,
	})
	alarmText = Ui.label("", {
		Font = Ui.Fonts.Title,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, 0),
		Size = UDim2.new(0.8, 0, 0, 56),
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 230, 90),
		StrokeThickness = 4,
		Parent = alarmFrame,
	})
end

---------------------------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------------------------

local renderGoals
function renderGoals(profile)
	for _, child in ipairs(goalsFrame:GetChildren()) do
		-- GuiObject also covers the TextButton header, so it isn't stacked up on every render
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local header = Ui.new("TextButton", { Text = if goalsCollapsed then "GOALS  +" else "GOALS  -", Font = Ui.Fonts.Title, Size = UDim2.new(1, 0, 0, 22), TextScaled = true, TextColor3 = C.Accent, LayoutOrder = 0, Parent = goalsFrame })
	Ui.textStroke(header, 2)
	header.Activated:Connect(function()
		HudController.toggleGoals()
		renderGoals(profile)
	end)
	goalsFrame.Size = UDim2.new(0, 270, 0, if goalsCollapsed then 40 else 196)
	for i, goal in ipairs(profile.goals or {}) do
		local row = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, LayoutOrder = i, Parent = goalsFrame })
		Ui.label(goal.text, { Size = UDim2.new(0.72, 0, 0, 22), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Ui.label("+" .. Format.cash(goal.reward), { Position = UDim2.new(0.72, 0, 0, 0), Size = UDim2.new(0.28, 0, 0, 22), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Good, Parent = row })
		local _, fill = Ui.progressBar(row, { Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 14), FillColor = C.Accent })
		fill.Size = UDim2.fromScale(math.clamp(goal.progress / math.max(goal.target, 1), 0, 1), 1)
	end
end

local function renderMenuBadges(profile)
	menuButtons.Daily.Badge.Visible = profile.daily and profile.daily.canClaim == true
	menuButtons.Rebirth.Badge.Visible = profile.rebirth and profile.cash >= profile.rebirth.cost
end

local function renderProfile(profile)
	if not profile then
		return
	end
	multLabel.Text = (string.gsub(string.format("x%.2f cash", profile.mult), "%.?0+ cash$", " cash"))
	slotsLabel.Text = string.format("Base %d/%d%s", profile.usedSlots, profile.slots, if profile.queued > 0 then ("  (+" .. profile.queued .. " waiting)") else "")
	renderGoals(profile)
	renderMenuBadges(profile)
end

function HudController.renderEvents()
	if not eventsFrame then
		return
	end
	for _, child in ipairs(eventsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local events = ClientState.events
	if not events then
		return
	end
	local at = ClientState.eventsReceivedAt
	local function chip(text, color, order, big)
		local chipFrame = Ui.panel({ Size = UDim2.new(1, 0, 0, if big then 38 else 28), BackgroundColor3 = Ui.darken(color, 0.4), LayoutOrder = order, Parent = eventsFrame })
		Ui.label(text, { Size = UDim2.new(1, -12, 1, -4), Position = UDim2.new(0, 6, 0, 2), TextScaled = true, TextColor3 = Ui.lighten(color, 0.3), Parent = chipFrame })
	end
	for i, ev in ipairs(events.active or {}) do
		chip(ev.name .. "  " .. Format.time(ClientState.countdown(ev.remaining, at)), Ui.rgb(ev.color), i, true)
	end
	if events.nextName then
		chip("Next: " .. events.nextName .. " in " .. Format.time(ClientState.countdown(events.nextIn, at)), C.PanelLight, 10)
	end
	if (events.luckyIn or 0) > 0 then
		chip("Lucky Hour in " .. Format.time(ClientState.countdown(events.luckyIn, at)), C.Good, 11)
	end
	if (events.luck or 1) > 1 then
		chip("LUCK x" .. tostring(events.luck), C.Blue, 12)
	end
end

local function renderLock(tick)
	if not lockButton or not tick or not tick.lock then
		return
	end
	local status, remaining = tick.lock.status, tick.lock.remaining
	if status == "Locked" then
		lockButton.Text = "LOCKED " .. Format.time(remaining)
		Ui.setButtonColor(lockButton, C.Good)
	elseif status == "Cooldown" then
		lockButton.Text = if (tick.lockTokens or 0) > 0 then "LOCK (TOKEN)" else ("WAIT " .. Format.time(remaining))
		Ui.setButtonColor(lockButton, C.Grey)
	else
		lockButton.Text = "LOCK BASE"
		Ui.setButtonColor(lockButton, C.Blue)
	end
end

local function renderCarry()
	local carry = ClientState.carry
	carryBanner.Visible = carry ~= nil
	dropButton.Visible = carry ~= nil
	if carry then
		local left = ClientState.countdown(carry.timeout, ClientState.carryReceivedAt)
		carryText.Text = string.format("CARRYING %s! RUN HOME! %s", string.upper(carry.name), Format.time(left))
		local tier = RarityConfig.Tiers[carry.rarity]
		carryText.TextColor3 = if tier then Ui.lighten(Ui.rgb(tier.Color), 0.3) else C.Accent
	end
end

function HudController.alarm(thiefName, blobbyName)
	alarmFrame.Visible = true
	alarmText.Text = string.format("THIEF! %s is stealing your %s! SLAP THEM!", thiefName, blobbyName)
	AudioController.play("StealAlarm")
	task.spawn(function()
		for _ = 1, 4 do
			alarmFrame.BackgroundTransparency = 0.7
			TweenService:Create(alarmFrame, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
			task.wait(0.5)
		end
		alarmFrame.Visible = false
	end)
end

function HudController.bumpCash()
	local scale = cashLabel.Parent:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.08
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

function HudController.init()
	gui = Ui.autoScale(Ui.screen("SnatchHUD", player:WaitForChild("PlayerGui"), 1))
	buildCash()
	buildMenu()
	buildRight()
	buildActions()
	buildCenter()

	ClientState.ProfileChanged:Connect(renderProfile)
	ClientState.TickChanged:Connect(function(tick)
		ipsLabel.Text = "+" .. Format.perSecond(tick.ips)
		renderLock(tick)
		if ClientState.profile then
			renderMenuBadges(ClientState.profile)
		end
	end)
	ClientState.EventsChanged:Connect(HudController.renderEvents)
	ClientState.CarryChanged:Connect(renderCarry)
	ClientState.Feed:Connect(HudController.feed)
	ClientState.Notify:Connect(HudController.toast)
	ClientState.Alarm:Connect(HudController.alarm)

	-- Smooth cash counter + 1 Hz countdown refresh.
	task.spawn(function()
		local acc = 0
		while true do
			local dt = task.wait(0.05) or 0.05
			local target = ClientState.profile and ClientState.profile.cash or 0
			if math.abs(target - shownCash) < 1 then
				shownCash = target
			else
				shownCash += (target - shownCash) * math.min(1, dt * 8)
			end
			cashLabel.Text = Format.cash(shownCash)
			acc += dt
			if acc >= 1 then
				acc = 0
				HudController.renderEvents()
				renderCarry()
			end
		end
	end)
end

return HudController
