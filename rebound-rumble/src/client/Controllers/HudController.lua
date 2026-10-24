--[[
	HudController - in-round and lobby HUD: coins/streak, round status, target warning,
	parry + ability buttons with cooldown rings, ball speed, kill feed, announcements,
	session goals, toasts, coin popups and the results screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local AbilityConfig = require(Shared.Config.AbilityConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GameConfig = require(Shared.Config.GameConfig)
local AudioUtil = require(Shared.AudioUtil)
local BallMath = require(Shared.BallMath)
local Clock = require(Shared.Clock)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)
local BallController = require(script.Parent.BallController)

local HudController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui
local coinsLabel, streakLabel, multLabel
local statusLabel, subLabel
local warningFrame, warningLabel, vignette
local feedbackLabel
local speedLabel
local parryButton, parryCooldown, abilityButtons
local feedList
local bannerLabel
local toastList
local goalsFrame, goalsList
local resultsFrame, resultsBody
local lastCoins
local wasTarget = false

local function tween(instance, time, goals)
	TweenService:Create(instance, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

local function buildTopLeft()
	local panel = Ui.panel({ Name = "Stats", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(230, 92), Parent = gui })
	Ui.stroke(panel, C.Gold, 0.4)
	Ui.padding(panel, 10)
	coinsLabel = Ui.label("0 coins", { Font = Ui.Fonts.Title, TextSize = 26, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
	streakLabel = Ui.label("Win streak 0", { Font = Ui.Fonts.Bold, TextSize = 15, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
	multLabel = Ui.label("", { TextSize = 13, TextColor3 = C.Accent2, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
end

local function buildStatus()
	statusLabel = Ui.label("", {
		Font = Ui.Fonts.Title,
		TextSize = 34,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(600, 40),
		TextStrokeTransparency = 0.4,
		Parent = gui,
	})
	subLabel = Ui.label("", {
		Font = Ui.Fonts.Bold,
		TextSize = 16,
		TextColor3 = C.Dim,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 54),
		Size = UDim2.fromOffset(600, 20),
		TextStrokeTransparency = 0.6,
		Parent = gui,
	})
end

local function buildWarning()
	vignette = Ui.new("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	for _, spec in ipairs({
		{ UDim2.new(1, 0, 0.2, 0), UDim2.fromScale(0, 0), 90 },
		{ UDim2.new(1, 0, 0.2, 0), UDim2.fromScale(0, 0.8), -90 },
		{ UDim2.new(0.15, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ UDim2.new(0.15, 0, 1, 0), UDim2.fromScale(0.85, 0), 180 },
	}) do
		local edge = Ui.new("Frame", { Size = spec[1], Position = spec[2], BackgroundColor3 = C.Danger, BackgroundTransparency = 0, Parent = vignette })
		Ui.new("UIGradient", { Rotation = spec[3], Transparency = NumberSequence.new(0, 1), Parent = edge })
	end
	vignette.Visible = false
	warningFrame = Ui.panel({ Name = "Warning", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 84), Size = UDim2.fromOffset(460, 50), BackgroundColor3 = Color3.fromRGB(120, 0, 0), BackgroundTransparency = 0.15, Visible = false, Parent = gui })
	Ui.stroke(warningFrame, C.Danger, 0, 3)
	warningLabel = Ui.label("THE BALL IS HUNTING YOU!", { Font = Ui.Fonts.Title, TextSize = 28, Size = UDim2.fromScale(1, 1), Parent = warningFrame })
	feedbackLabel = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 44, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromOffset(500, 60), TextStrokeTransparency = 0.2, TextTransparency = 1, TextStrokeColor3 = Color3.new(0, 0, 0), Parent = gui })
	speedLabel = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 18, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(300, 24), TextStrokeTransparency = 0.5, Parent = gui })
end

local function cooldownOverlay(button)
	local overlay = Ui.new("Frame", { Name = "Cooldown", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 3, Parent = button })
	Ui.corner(overlay, 60)
	return overlay
end

local function buildButtons()
	local holder = Ui.new("Frame", { Name = "Actions", AnchorPoint = Vector2.new(1, 1), Position = if UserInputService.TouchEnabled then UDim2.new(1, -200, 1, -18) else UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(300, 220), BackgroundTransparency = 1, Parent = gui })
	-- On touch screens the panel sits left of Roblox's Jump button instead of on top of it.
	parryButton = Ui.button("PARRY", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(130, 130), TextSize = 30, Parent = holder }, C.Accent)
	Ui.corner(parryButton, 65)
	Ui.gradient(parryButton, Color3.fromRGB(255, 120, 220), Color3.fromRGB(200, 30, 140))
	Ui.label("F / Click / R1", { TextSize = 12, TextColor3 = C.Text, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, 0, 0, 14), ZIndex = 2, Parent = parryButton })
	parryCooldown = cooldownOverlay(parryButton)
	parryButton.Activated:Connect(function()
		InputController.parry()
	end)
	abilityButtons = {}
	for slot = 1, AbilityConfig.MaxSlotsWithPass do
		local button = Ui.button("", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -140 - (slot - 1) * 84, 1, -6), Size = UDim2.fromOffset(76, 76), TextSize = 14, TextWrapped = true, Visible = false, Parent = holder }, C.PanelLight)
		Ui.corner(button, 38)
		Ui.label(if slot == 1 then "Q / X" else "E / Y", { TextSize = 11, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, 0, 0, 12), ZIndex = 2, Parent = button })
		local overlay = cooldownOverlay(button)
		button.Activated:Connect(function()
			InputController.ability(slot)
		end)
		abilityButtons[slot] = { button = button, overlay = overlay }
	end
end

local function buildFeed()
	feedList = Ui.new("Frame", { Name = "KillFeed", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(330, 220), BackgroundTransparency = 1, Parent = gui })
	Ui.list(feedList, 4, nil, Enum.HorizontalAlignment.Right)
	bannerLabel = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 36, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.24), Size = UDim2.fromOffset(900, 50), TextStrokeTransparency = 0.2, TextTransparency = 1, Parent = gui })
	toastList = Ui.new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -50), Size = UDim2.fromOffset(520, 160), BackgroundTransparency = 1, Parent = gui })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = toastList })
end

local function buildGoals()
	goalsFrame = Ui.panel({ Name = "Goals", AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(12, 112), Size = UDim2.fromOffset(230, 96), BackgroundTransparency = 0.3, Parent = gui })
	Ui.padding(goalsFrame, 8)
	Ui.label("SESSION GOALS", { Font = Ui.Fonts.Title, TextSize = 14, TextColor3 = C.Accent2, Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, Parent = goalsFrame })
	goalsList = Ui.new("Frame", { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 1, -18), BackgroundTransparency = 1, Parent = goalsFrame })
	Ui.list(goalsList, 2)
end

local function buildResults()
	resultsFrame = Ui.panel({ Name = "Results", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 420), Visible = false, ZIndex = 20, Parent = gui })
	Ui.stroke(resultsFrame, C.Gold, 0.2, 3)
	Ui.padding(resultsFrame, 16)
	resultsBody = Ui.new("Frame", { Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1, ZIndex = 20, Parent = resultsFrame })
	Ui.list(resultsBody, 4, nil, Enum.HorizontalAlignment.Center)
	local close = Ui.button("NICE", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(160, 38), ZIndex = 21, Parent = resultsFrame }, C.Accent)
	close.Activated:Connect(function()
		resultsFrame.Visible = false
	end)
end

---------------------------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------------------------

local function flashFeedback(text, color)
	feedbackLabel.Text = text
	feedbackLabel.TextColor3 = color
	feedbackLabel.TextTransparency = 0
	feedbackLabel.TextStrokeTransparency = 0.2
	feedbackLabel.Size = UDim2.fromOffset(560, 70)
	tween(feedbackLabel, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1, Size = UDim2.fromOffset(500, 60) })
end

function HudController.notify(text, kind)
	if type(text) ~= "string" then
		return
	end
	local color = if kind == "warn" then C.Danger elseif kind == "good" then C.Good else C.Text
	local toast = Ui.panel({ Size = UDim2.fromOffset(500, 30), BackgroundTransparency = 0.2, Parent = toastList })
	Ui.label(text, { Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = color, Size = UDim2.fromScale(1, 1), TextWrapped = true, Parent = toast })
	task.delay(3.5, function()
		toast:Destroy()
	end)
	local children = 0
	for _, child in ipairs(toastList:GetChildren()) do
		if child:IsA("Frame") then
			children += 1
		end
	end
	if children > 4 then
		for _, child in ipairs(toastList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
				break
			end
		end
	end
end

local function coinPopup(amount)
	local label = Ui.label("+" .. Ui.formatNumber(amount), { Font = Ui.Fonts.Title, TextSize = 30, TextColor3 = C.Gold, Position = UDim2.fromOffset(140, 30), Size = UDim2.fromOffset(160, 34), TextStrokeTransparency = 0.3, Parent = gui })
	tween(label, 1.2, { Position = UDim2.fromOffset(140, -10), TextTransparency = 1, TextStrokeTransparency = 1 })
	task.delay(1.3, function()
		label:Destroy()
	end)
	AudioUtil.play(AudioAssets.Coin, nil, 0.05)
end

local function renderProfile(profile)
	if not profile then
		return
	end
	coinsLabel.Text = Ui.formatNumber(profile.coins) .. " coins"
	streakLabel.Text = string.format("Win streak %d  (best %d)", profile.winStreak or 0, profile.bestStreak or 0)
	multLabel.Text = if (profile.multiplier or 1) > 1 then string.format("Coin boost x%.1f", profile.multiplier) else ""
	if lastCoins and profile.coins > lastCoins then
		coinPopup(profile.coins - lastCoins)
	end
	lastCoins = profile.coins
	for slot, entry in ipairs(abilityButtons) do
		local id = profile.loadout and profile.loadout[slot]
		local def = id and AbilityConfig.Abilities[id]
		entry.button.Visible = def ~= nil and slot <= (profile.maxSlots or 1)
		if def then
			entry.button.Text = def.Name
			entry.button.BackgroundColor3 = Ui.rgb(def.Color):Lerp(Color3.new(0, 0, 0), 0.45)
		end
	end
end

local function renderGoals(goals)
	for _, child in ipairs(goalsList:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, goal in ipairs(goals or {}) do
		Ui.label(string.format("%s %s  %d/%d", if goal.done then "[DONE]" else "-", goal.text, goal.progress, goal.target), {
			TextSize = 13,
			TextColor3 = if goal.done then C.Good else C.Text,
			Size = UDim2.new(1, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
			Parent = goalsList,
		})
	end
end

local function renderMatch(state, data)
	local status = ClientState.status()
	if state == "Countdown" then
		statusLabel.Text = string.format("NEXT ROUND IN %d", data.countdown or 0)
		statusLabel.TextColor3 = C.Accent2
		subLabel.Text = string.format("%d ready", data.readyCount or 0)
		if (data.countdown or 0) <= 3 then
			AudioUtil.play(AudioAssets.Countdown)
		end
	elseif state == "Playing" then
		statusLabel.Text = string.format("%d ALIVE", data.alive or 0)
		statusLabel.TextColor3 = C.Accent
		subLabel.Text = string.format("Round %d - %s%s", data.round or 0, data.arenaName or "", if status == "Out" then "  (eliminated - spectating)" else "")
	elseif state == "Results" then
		statusLabel.Text = "ROUND OVER"
		statusLabel.TextColor3 = C.Gold
		subLabel.Text = ""
	else
		statusLabel.Text = "WAITING FOR PLAYERS"
		statusLabel.TextColor3 = C.Text
		subLabel.Text = "Solo? Bots will join you."
	end
end

function HudController.addFeed(entry)
	local text
	if entry.cause == "shield" then
		text = string.format("%s's SHIELD saved them!", entry.victim)
	elseif entry.killer then
		text = string.format("%s%s  >>  %s%s%s", entry.killer, if entry.killerBot then " [BOT]" else "", entry.victim, if entry.victimBot then " [BOT]" else "", if entry.speed then string.format("  (%d)", entry.speed) else "")
	elseif entry.cause == "fell" then
		text = entry.victim .. " fell off"
	elseif entry.cause == "left" then
		text = entry.victim .. " left"
	else
		text = entry.victim .. " was blasted"
	end
	local row = Ui.panel({ Size = UDim2.fromOffset(330, 26), BackgroundTransparency = 0.25, LayoutOrder = -math.floor(os.clock() * 100), Parent = feedList })
	Ui.label(text, { Font = Ui.Fonts.Bold, TextSize = 14, Size = UDim2.new(1, -10, 1, 0), Position = UDim2.fromOffset(5, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = if entry.killer == player.DisplayName then C.Gold else C.Text, Parent = row })
	task.delay(7, function()
		row:Destroy()
	end)
	local rows = {}
	for _, child in ipairs(feedList:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(rows, child)
		end
	end
	if #rows > 6 then
		table.sort(rows, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		rows[1]:Destroy()
	end
end

function HudController.banner(text, kind)
	local color = C.Text
	if kind == "streak" then
		color = C.Accent
	elseif kind == "win" then
		color = C.Gold
	elseif kind == "party" then
		color = C.Accent2
	elseif kind and CosmeticConfig.Rarities[kind] then
		color = Ui.rgb(CosmeticConfig.Rarities[kind].Color)
	end
	bannerLabel.Text = text
	bannerLabel.TextColor3 = color
	bannerLabel.TextTransparency = 0
	bannerLabel.TextStrokeTransparency = 0.2
	bannerLabel.Size = UDim2.fromOffset(1000, 60)
	tween(bannerLabel, 0.25, { Size = UDim2.fromOffset(900, 50) })
	task.delay(2.6, function()
		if bannerLabel.Text == text then
			tween(bannerLabel, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
end

function HudController.showResults(results)
	for _, child in ipairs(resultsBody:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local title = if results.won then "VICTORY!" else "ELIMINATED"
	Ui.label(title, { Font = Ui.Fonts.Title, TextSize = 44, TextColor3 = if results.won then C.Gold else C.Danger, Size = UDim2.new(1, 0, 0, 50), ZIndex = 20, LayoutOrder = 1, Parent = resultsBody })
	local sub = if results.winner then string.format("Winner: %s%s", results.winner, if results.winnerBot then " [BOT]" else "") else "No winner"
	if not results.ranked then
		sub ..= "  (practice vs bots: wins don't count for the board)"
	end
	Ui.label(sub, { TextSize = 14, TextColor3 = C.Dim, TextWrapped = true, Size = UDim2.new(1, 0, 0, 34), ZIndex = 20, LayoutOrder = 2, Parent = resultsBody })
	local order = 3
	if results.reward then
		for _, line in ipairs(results.reward.lines) do
			Ui.label(string.format("%s   +%d", line.label, line.amount), { Font = Ui.Fonts.Bold, TextSize = 16, Size = UDim2.new(1, 0, 0, 20), ZIndex = 20, LayoutOrder = order, Parent = resultsBody })
			order += 1
		end
		if results.reward.multiplier > 1 then
			Ui.label(string.format("Pass bonus x%.1f", results.reward.multiplier), { TextSize = 14, TextColor3 = C.Accent2, Size = UDim2.new(1, 0, 0, 18), ZIndex = 20, LayoutOrder = order, Parent = resultsBody })
			order += 1
		end
		Ui.label(string.format("TOTAL  +%s coins", Ui.formatNumber(results.reward.total)), { Font = Ui.Fonts.Title, TextSize = 24, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 30), ZIndex = 20, LayoutOrder = order, Parent = resultsBody })
		order += 1
	end
	if results.streak and results.streak > 0 then
		Ui.label(string.format("Win streak: %d", results.streak), { Font = Ui.Fonts.Bold, TextSize = 16, TextColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 20), ZIndex = 20, LayoutOrder = order, Parent = resultsBody })
		order += 1
	end
	for i, s in ipairs(results.standings or {}) do
		if i > 5 then
			break
		end
		Ui.label(string.format("#%d  %s%s  -  %d kills, %ds", i, s.name, if s.isBot then " [BOT]" else "", s.kills, s.survived), { TextSize = 13, TextColor3 = if s.won then C.Gold else C.Dim, Size = UDim2.new(1, 0, 0, 16), ZIndex = 20, LayoutOrder = order + i, Parent = resultsBody })
	end
	resultsFrame.Visible = true
	AudioUtil.play(if results.won then AudioAssets.Win else AudioAssets.Eliminated)
	task.delay(GameConfig.Lobby.ResultsSeconds + 2, function()
		resultsFrame.Visible = false
	end)
end

local function update()
	local now = Clock.now()
	local inArena = ClientState.status() == "Arena"
	local ballOn = BallController.active()
	local isTarget = inArena and ballOn and BallController.targetId() == ClientState.myId()
	warningFrame.Visible = isTarget
	vignette.Visible = isTarget
	if isTarget then
		local distance = BallController.distanceToMe() or 999
		local range = BallMath.parryRange(BallController.speed(), GameConfig.Parry)
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * (if distance < range * 1.5 then 30 else 12))
		vignette.BackgroundTransparency = 1
		for _, edge in ipairs(vignette:GetChildren()) do
			edge.BackgroundTransparency = 0.2 + 0.5 * pulse
		end
		warningLabel.Text = if distance <= range then "PARRY NOW!" else "THE BALL IS HUNTING YOU!"
		warningLabel.TextColor3 = if distance <= range then C.Gold else C.Text
		if not wasTarget then
			AudioUtil.play(AudioAssets.TargetWarning)
		end
	end
	wasTarget = isTarget
	speedLabel.Text = if ballOn and ClientState.matchState == "Playing" then string.format("BALL SPEED %d", BallController.speed()) else ""
	parryButton.Visible = inArena
	local cd = InputController.parryCooldown or 0
	local left = math.max(0, InputController.parryReadyAt - now)
	parryCooldown.Size = UDim2.fromScale(1, if cd > 0 then math.clamp(left / cd, 0, 1) else 0)
	for slot, entry in ipairs(abilityButtons) do
		local total = InputController.abilityCooldown[slot] or 0
		local remaining = math.max(0, (InputController.abilityReadyAt[slot] or 0) - now)
		entry.overlay.Size = UDim2.fromScale(1, if total > 0 then math.clamp(remaining / total, 0, 1) else 0)
	end
	goalsFrame.Visible = not inArena
end

function HudController.init()
	gui = Ui.screen("RR_HUD", player:WaitForChild("PlayerGui"), 1)
	buildTopLeft()
	buildStatus()
	buildWarning()
	buildButtons()
	buildFeed()
	buildGoals()
	buildResults()

	-- Gamepad / keyboard players get a smaller parry button; touch players get the big one.
	if not UserInputService.TouchEnabled then
		parryButton.Size = UDim2.fromOffset(100, 100)
	end

	ClientState.ProfileChanged:Connect(renderProfile)
	ClientState.GoalsChanged:Connect(renderGoals)
	ClientState.MatchChanged:Connect(renderMatch)
	ClientState.KillFeed:Connect(HudController.addFeed)
	ClientState.Announce:Connect(HudController.banner)
	ClientState.Notified:Connect(HudController.notify)
	ClientState.Results:Connect(HudController.showResults)
	ClientState.ParryResult:Connect(function(ok, reason)
		if ok then
			flashFeedback("PARRY!", C.Good)
		elseif reason == "early" then
			flashFeedback("TOO EARLY!", C.Danger)
		elseif reason == "not_target" then
			flashFeedback("WHIFF", C.Dim)
		elseif reason == "late" then
			flashFeedback("TOO LATE!", C.Danger)
		end
	end)
	ClientState.BallEvent:Connect(function(kind, data)
		if kind == "deflect" and data.by == ClientState.myId() then
			local target = ClientState.entry(data.to)
			if target then
				HudController.notify(string.format("Sent it to %s at %d!", target.name, data.speed), "good")
			end
		end
	end)
	-- Gold [VIP] chat tag for VIP pass owners (server sets the RR_VIP attribute).
	pcall(function()
		TextChatService.OnIncomingMessage = function(message)
			local props = Instance.new("TextChatMessageProperties")
			local source = message.TextSource
			local speaker = source and Players:GetPlayerByUserId(source.UserId)
			if speaker and speaker:GetAttribute("RR_VIP") then
				props.PrefixText = "<font color='#FFD246'>[VIP]</font> " .. message.PrefixText
			end
			return props
		end
	end)
	renderMatch(ClientState.matchState, ClientState.matchData)
	renderProfile(ClientState.profile)
	renderGoals(ClientState.goals)
	RunService.RenderStepped:Connect(update)
end

return HudController
