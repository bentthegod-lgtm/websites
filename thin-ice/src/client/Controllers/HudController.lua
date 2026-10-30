--[[
	HudController - the on-screen game:
	  * top bar: phase, difficulty, timer, cores delivered, blizzard warning
	  * warmth + stamina bars, snowballs, move mode (bottom left)
	  * team list with each friend's state and warmth (left)
	  * lobby panel: READY and the difficulty vote (with live counts and the auto-start timer)
	  * toasts (Notify), big announcements, the "ice is forming" progress
	  * frozen overlay (who can thaw you, time until you're lost) and the in-water warning
	  * the results card at the end of a round
	  * touch buttons (sprint / sneak / throw / menu) on phones and tablets
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local InputController = require(script.Parent.InputController)

local HudController = {}

local C = Ui.Colors
local gui
local refs = {}
local toasts = {}
local resultsOpen = false

local STATE_ICON = { Active = "OK", Frozen = "FROZEN", Lost = "LOST", Escaped = "SAFE", Water = "WATER", Left = "LEFT" }
local STATE_COLOR = { Active = C.Green, Frozen = C.Accent, Lost = C.Red, Escaped = C.Warm, Water = C.Blue, Left = C.Dim }

function HudController.warmthColor(w)
	w = math.clamp((w or 100) / 100, 0, 1)
	return Color3.fromRGB(110, 170, 255):Lerp(Color3.fromRGB(255, 170, 90), w)
end

function HudController.timerText(state)
	local phase = state.phase
	if phase == "Running" then
		return string.format("%s  |  %s  |  Cores %d/%d", (state.difficulty or ""):upper(), Format.clock(state.timeLeft), state.delivered or 0, state.total or 0)
	elseif phase == "Sled" then
		return string.format("SLED LEAVES IN %s  -  GET TO THE SHORE!", Format.clock(state.timeLeft))
	elseif phase == "Countdown" then
		return string.format("Heading out in %d...", state.timeLeft or 0)
	elseif phase == "Preparing" then
		return string.format("The ice is forming... %d%%", state.building or 100)
	elseif phase == "Results" then
		return "Back to camp..."
	end
	return "THIN ICE  -  ready up at camp"
end

function HudController.lobbyText(state)
	local players = state.players or 0
	local readyN = state.ready or 0
	if state.phase == "Countdown" then
		return string.format("%d/%d ready - leaving in %ds", readyN, players, state.timeLeft or 0)
	end
	if readyN > 0 and state.autoStartIn then
		return string.format("%d/%d ready - starting in %ds", readyN, players, state.autoStartIn)
	end
	return string.format("%d/%d ready", readyN, players)
end

local function bar(parent, name, y, color, label)
	local holder = Ui.new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, y), Parent = parent })
	Ui.label(label, { Size = UDim2.fromOffset(80, 26), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, TextSize = 14, TextColor3 = C.Dim, Parent = holder })
	local back, fill = Ui.bar(holder, { Size = UDim2.new(1, -86, 0, 16), Position = UDim2.fromOffset(84, 5) }, color)
	return back, fill
end

local function build()
	gui = Ui.screen("IceHUD", 5)

	-- Top bar
	local top = Ui.panel({ Name = "TopBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(560, 44), BackgroundTransparency = 0.15, Parent = gui }, 12)
	refs.timer = Ui.title("THIN ICE", { Name = "Timer", Size = UDim2.fromScale(1, 1), TextSize = 20, TextColor3 = C.Text, Parent = top })
	refs.gust = Ui.label("BLIZZARD - it can barely hear you", { Name = "Gust", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.fromOffset(420, 26), Font = Ui.Fonts.Bold, TextSize = 16, TextColor3 = C.Accent, Visible = false, Parent = gui })

	-- Coins + menu button
	refs.coins = Ui.label("0 coins", { Name = "Coins", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(220, 30), TextXAlignment = Enum.TextXAlignment.Right, Font = Ui.Fonts.Bold, TextSize = 20, TextColor3 = C.Warm, Parent = gui })
	refs.level = Ui.label("Level 1", { Name = "Level", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 42), Size = UDim2.fromOffset(220, 22), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 14, TextColor3 = C.Dim, Parent = gui })
	refs.menuButton = Ui.button("MENU (M)", { Name = "MenuButton", Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(120, 38), TextSize = 16 }, C.PanelLighter)
	refs.menuButton.Parent = gui
	refs.menuButton.Activated:Connect(function()
		if InputController.menuToggle then
			InputController.menuToggle()
		end
	end)

	-- Survival panel
	local survival = Ui.panel({ Name = "Survival", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(320, 112), BackgroundTransparency = 0.2, Visible = false, Parent = gui }, 12)
	Ui.padding(survival, 12, 10)
	refs.survival = survival
	refs.warmthBack, refs.warmthFill = bar(survival, "Warmth", 0, C.Warm, "WARMTH")
	refs.staminaBack, refs.staminaFill = bar(survival, "Stamina", 30, C.Green, "STAMINA")
	refs.snowballs = Ui.label("Snowballs 3", { Name = "Snowballs", Position = UDim2.fromOffset(0, 62), Size = UDim2.fromOffset(150, 24), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, TextSize = 15, Parent = survival })
	refs.mode = Ui.label("WALK", { Name = "Mode", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 62), Size = UDim2.fromOffset(140, 24), TextXAlignment = Enum.TextXAlignment.Right, Font = Ui.Fonts.Title, TextSize = 16, TextColor3 = C.Accent, Parent = survival })

	-- Team list
	refs.team = Ui.new("Frame", { Name = "Team", Position = UDim2.new(0, 16, 0, 70), Size = UDim2.fromOffset(230, 240), BackgroundTransparency = 1, Parent = gui })
	Ui.list(refs.team, 4)

	-- Lobby panel
	local lobby = Ui.panel({ Name = "Lobby", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(600, 150), BackgroundTransparency = 0.1, Parent = gui }, 14)
	Ui.padding(lobby, 14, 10)
	refs.lobby = lobby
	refs.lobbyStatus = Ui.title("0/0 ready", { Name = "Status", Size = UDim2.new(1, 0, 0, 28), TextSize = 20, Parent = lobby })
	refs.readyButton = Ui.button("READY", { Name = "Ready", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(220, 40), TextSize = 20 }, C.Green)
	refs.readyButton.Parent = lobby
	refs.readyButton.Activated:Connect(function()
		local mine = ClientState.round.readyIds and ClientState.round.readyIds[tostring(Players.LocalPlayer.UserId)]
		Net.event("SetReady"):FireServer(not mine)
	end)
	local votes = Ui.new("Frame", { Name = "Votes", Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = lobby })
	Ui.list(votes, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	refs.voteButtons = {}
	for i, name in ipairs(GameConfig.DifficultyOrder) do
		local color = Ui.rgb(GameConfig.Difficulties[name].Color)
		local b = Ui.button(name, { Name = name, LayoutOrder = i, Size = UDim2.fromOffset(130, 38), TextSize = 15 }, C.PanelLighter)
		Ui.stroke(b, color, 2, 0)
		b.Parent = votes
		b.Activated:Connect(function()
			Net.event("Vote"):FireServer(name)
		end)
		refs.voteButtons[name] = b
	end

	-- Overlays
	refs.frozen = Ui.new("Frame", { Name = "Frozen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(190, 230, 255), BackgroundTransparency = 0.55, Visible = false, ZIndex = 5, Parent = gui })
	Ui.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(1, 0) }), Rotation = 90, Parent = refs.frozen })
	refs.frozenTitle = Ui.title("FROZEN", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(600, 80), TextSize = 64, TextColor3 = C.Text, ZIndex = 6, Parent = refs.frozen })
	refs.frozenText = Ui.label("", { Name = "Text", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(700, 60), TextSize = 20, TextWrapped = true, Font = Ui.Fonts.Bold, TextColor3 = C.Black, ZIndex = 6, Parent = refs.frozen })
	refs.water = Ui.new("Frame", { Name = "Water", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 30, 70), BackgroundTransparency = 0.45, Visible = false, ZIndex = 4, Parent = gui })
	Ui.title("IN THE WATER - climbing out...", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(700, 60), TextSize = 32, ZIndex = 5, Parent = refs.water })

	-- Announce banner + toasts
	refs.announce = Ui.title("", { Name = "Announce", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.fromOffset(900, 60), TextSize = 34, TextStrokeTransparency = 0.4, Visible = false, Parent = gui })
	refs.toasts = Ui.new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 74), Size = UDim2.fromOffset(380, 300), BackgroundTransparency = 1, Parent = gui })
	Ui.list(refs.toasts, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right)

	-- Results card
	local results, body = Ui.window(gui, "Results", "RESULTS", 520, 470)
	refs.results = results
	refs.resultsBody = body

	-- Touch buttons
	if UserInputService.TouchEnabled then
		local touch = Ui.new("Frame", { Name = "Touch", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -150), Size = UDim2.fromOffset(250, 120), BackgroundTransparency = 1, Parent = gui })
		local uiScale = gui:FindFirstChildOfClass("UIScale")
		local function layout()
			touch.Position = HudController.touchPosition(Ui.viewportSize(), if uiScale then uiScale.Scale else 1)
		end
		layout()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				task.defer(layout) -- after Ui.screen's UIScale has refitted
			end)
		end
		local sprint = Ui.button("SPRINT", { Name = "Sprint", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(120, 54) }, C.PanelLighter)
		sprint.Parent = touch
		-- Hold to sprint. (GuiObject.InputBegan also fires for mouse movement over the button,
		-- so only a touch or click counts; a finger that slides off still releases it.)
		local sprintInput = nil
		sprint.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				sprintInput = input
				InputController.setSprint(true)
			end
		end)
		local function release(input)
			if sprintInput and input == sprintInput then
				sprintInput = nil
				InputController.setSprint(false)
			end
		end
		sprint.InputEnded:Connect(release)
		UserInputService.TouchEnded:Connect(release)
		UserInputService.InputEnded:Connect(release)
		local sneak = Ui.button("SNEAK", { Name = "Sneak", Position = UDim2.fromOffset(130, 0), Size = UDim2.fromOffset(120, 54) }, C.PanelLighter)
		sneak.Parent = touch
		sneak.Activated:Connect(function()
			InputController.toggleSneak()
		end)
		local throw = Ui.button("THROW", { Name = "Throw", Position = UDim2.fromOffset(65, 62), Size = UDim2.fromOffset(120, 54) }, C.Accent)
		throw.Parent = touch
		throw.Activated:Connect(InputController.throw)
		refs.touch = touch
	end
end

--[[
	Where the touch buttons go: bottom-right, stacked just above Roblox's own Jump button
	(70 px at the bottom-right corner on phones, 120 px and higher up on tablets - see the
	default TouchJump module), never on top of it. `scale` is the HUD's UIScale: offsets
	are scaled by it, the core Jump button is not.
]]
function HudController.touchPosition(viewport, scale)
	scale = math.max(scale or 1, 0.01)
	local small = math.min(viewport.X, viewport.Y) <= 500
	local jumpTop = if small then 70 + 20 else 120 * 1.75
	return UDim2.new(1, -16 / scale, 1, -(jumpTop + 12) / scale)
end

function HudController.toast(text, kind)
	local color = if kind == "good" then C.Green elseif kind == "error" then C.Red elseif kind == "warn" then C.Warm else C.Accent
	local t = Ui.panel({ Size = UDim2.fromOffset(380, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.1, Parent = refs.toasts }, 10)
	Ui.padding(t, 12, 8)
	Ui.stroke(t, color, 2, 0)
	Ui.label(tostring(text), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, TextSize = 15, Parent = t })
	table.insert(toasts, t)
	while #toasts > 4 do
		table.remove(toasts, 1):Destroy()
	end
	task.delay(5, function()
		local i = table.find(toasts, t)
		if i then
			table.remove(toasts, i)
			t:Destroy()
		end
	end)
	return t
end

function HudController.announce(text, color)
	refs.announce.Text = tostring(text)
	refs.announce.TextColor3 = if type(color) == "table" then Ui.rgb(color) else C.Text
	refs.announce.Visible = true
	refs.announce.TextTransparency = 0
	local stamp = os.clock()
	refs.announceAt = stamp
	task.delay(3.5, function()
		if refs.announceAt == stamp then
			refs.announce.Visible = false
		end
	end)
end

function HudController.renderTeam()
	Ui.clear(refs.team)
	local inRound = ClientState.round.phase == "Running" or ClientState.round.phase == "Sled"
	if not inRound then
		return
	end
	for i, row in ipairs(ClientState.team) do
		local r = Ui.panel({ Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, BackgroundTransparency = 0.25, Parent = refs.team }, 8)
		local name = row.name .. (if row.vip then "  [VIP]" else "") .. (if row.carrying then "  *core*" else "")
		Ui.label(name, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -90, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, Parent = r })
		Ui.label(STATE_ICON[row.state] or row.state, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(70, 34), TextXAlignment = Enum.TextXAlignment.Right, Font = Ui.Fonts.Title, TextSize = 13, TextColor3 = STATE_COLOR[row.state] or C.Text, Parent = r })
		local back, fill = Ui.bar(r, { Size = UDim2.new(1, -20, 0, 3), Position = UDim2.new(0, 10, 1, -5) }, HudController.warmthColor(row.warmth))
		back.BackgroundTransparency = 0.6
		fill.Size = UDim2.fromScale(math.clamp((row.warmth or 0) / 100, 0, 1), 1)
	end
end

function HudController.renderRound()
	local state = ClientState.round
	refs.timer.Text = HudController.timerText(state)
	local lobbyPhase = state.phase == "Lobby" or state.phase == "Countdown"
	refs.lobby.Visible = lobbyPhase
	refs.gust.Visible = state.gust == true and (state.phase == "Running" or state.phase == "Sled")
	if lobbyPhase then
		refs.lobbyStatus.Text = HudController.lobbyText(state)
		local mine = state.readyIds and state.readyIds[tostring(Players.LocalPlayer.UserId)]
		refs.readyButton.Text = if mine then "READY!  (click to cancel)" else "READY"
		Ui.setButtonColor(refs.readyButton, if mine then C.PanelLighter else C.Green)
		for name, b in pairs(refs.voteButtons) do
			local n = state.votes and state.votes[name] or 0
			b.Text = if n > 0 then string.format("%s (%d)", name, n) else name
		end
	end
	HudController.renderTeam()
end

function HudController.renderProfile()
	local p = ClientState.profile
	if not p then
		return
	end
	refs.coins.Text = Format.short(p.coins) .. " coins"
	refs.level.Text = string.format("Level %d  -  %s / %s XP", p.level or 1, Format.short(p.xp or 0), Format.short(p.nextLevelXp or 0))
end

-- Per-frame: my bars, overlays.
function HudController.tick()
	local me = ClientState.me()
	local playing = ClientState.inRound() and me.state ~= nil
	refs.survival.Visible = playing and me.state == "Active"
	if me.warmth then
		refs.warmthFill.Size = UDim2.fromScale(math.clamp(me.warmth / 100, 0, 1), 1)
		refs.warmthFill.BackgroundColor3 = HudController.warmthColor(me.warmth)
	end
	if me.stamina then
		refs.staminaFill.Size = UDim2.fromScale(math.clamp(me.stamina / 100, 0, 1), 1)
	end
	refs.snowballs.Text = string.format("Snowballs %d  (F)", me.snowballs or 0)
	local mode = me.mode or ClientState.mode
	refs.mode.Text = string.upper(mode) .. (if me.carrying then " + CORE" else "")
	refs.mode.TextColor3 = if mode == "Sprint" then C.Red elseif mode == "Sneak" then C.Green else C.Accent
	refs.frozen.Visible = playing and me.state == "Frozen"
	if refs.frozen.Visible then
		local frozenAt = Players.LocalPlayer:GetAttribute("TI_FrozenAt") or 0
		local flask = ClientState.profile and ClientState.profile.boosts and ClientState.profile.boosts.Flask or 0
		local left = math.max(0, math.ceil(GameConfig.Warmth.FrozenLostAfter - (workspace:GetServerTimeNow() - frozenAt)))
		refs.frozenText.Text = string.format("A friend can thaw you - they hold E by your ice block.%s\nLost to the ice in %ds", if flask > 0 then "\nYour Thermos Flask will thaw you in a few seconds." else "", left)
	end
	refs.water.Visible = playing and me.inWater and me.state == "Active"
end

function HudController.showResults(summary)
	local body = refs.resultsBody
	Ui.clear(body)
	Ui.list(body, 6)
	local escaped = summary.outcome == "Escaped"
	local title = if escaped then "YOU ESCAPED!" elseif summary.outcome == "LeftBehind" then "LEFT BEHIND" else "THE ICE WON"
	Ui.title(title, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 40), TextSize = 32, TextColor3 = if escaped then C.Green else C.Red, Parent = body })
	Ui.label(tostring(summary.reason or ""), { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 24), TextColor3 = C.Dim, TextSize = 15, TextWrapped = true, Parent = body })
	Ui.label(string.format("%s  -  cores %d/%d  -  %s", summary.difficulty or "", summary.delivered or 0, summary.total or 0, Format.clock(summary.time or 0)), { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 22), Font = Ui.Fonts.Bold, TextSize = 15, Parent = body })
	for i, line in ipairs(summary.lines or {}) do
		local row = Ui.new("Frame", { LayoutOrder = 3 + i, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = body })
		Ui.label(tostring(line[1]), { Size = UDim2.fromScale(0.7, 1), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 15, Parent = row })
		Ui.label("+" .. tostring(line[2]), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.3, 1), TextXAlignment = Enum.TextXAlignment.Right, Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = C.Warm, Parent = row })
	end
	Ui.title(string.format("+%s coins   +%s XP", Format.short(summary.coins or 0), Format.short(summary.xp or 0)), { LayoutOrder = 50, Size = UDim2.new(1, 0, 0, 34), TextSize = 24, TextColor3 = C.Warm, Parent = body })
	if summary.level then
		Ui.title("LEVEL UP!  Level " .. summary.level, { LayoutOrder = 51, Size = UDim2.new(1, 0, 0, 28), TextSize = 20, TextColor3 = C.Green, Parent = body })
	end
	local names = {}
	for _, row in ipairs(summary.team or {}) do
		table.insert(names, row.name .. " (" .. (STATE_ICON[row.state] or row.state) .. ")")
	end
	Ui.label(table.concat(names, "   "), { LayoutOrder = 60, Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = body })
	Ui.openWindow("Results")
	resultsOpen = true
	task.delay(GameConfig.Round.ResultsTime + 4, function()
		if Ui.isOpen("Results") then
			Ui.closeWindow("Results")
		end
	end)
end

function HudController.resultsShown()
	return resultsOpen
end

function HudController.gui()
	return gui
end

function HudController.init()
	build()
	ClientState.RoundChanged:Connect(HudController.renderRound)
	ClientState.TeamChanged:Connect(HudController.renderTeam)
	ClientState.ProfileChanged:Connect(HudController.renderProfile)
	ClientState.Notified:Connect(HudController.toast)
	ClientState.Announced:Connect(HudController.announce)
	ClientState.Results:Connect(HudController.showResults)
	HudController.renderRound()
	RunService.RenderStepped:Connect(HudController.tick)
	-- Your own ice block's "Thaw" prompt is for your friends: hide it from you (locally).
	pcall(function()
		game:GetService("ProximityPromptService").PromptShown:Connect(function(prompt)
			local block = prompt.Parent
			if prompt.Name == "ThawPrompt" and block and block.Parent and block.Parent.Name == "Frozen_" .. Players.LocalPlayer.Name then
				prompt.Enabled = false
			end
		end)
	end)
end

return HudController
