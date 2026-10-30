--[[
	HudController - the in-game HUD (nautical palette: navy, brass, cream, signal red):
	  * lifeboat timer ("LIFEBOAT LAUNCHES IN m:ss") and the next-lurch countdown
	  * tilt / depth indicator: a ship silhouette tilting over the water line, tilt in
	    degrees, your deck and how far above the sea you are
	  * oxygen bar (teal -> red), carried-loot slots with rarity colours (tap to drop)
	  * BRACE! warning, downed overlay with bleed-out timer and revive progress bar,
	    the spectate bar once you're out, the flare route arrow, cinematic letterbox
	  * lobby panel: READY + a vote card per ship (locked ones say when they unlock)
	  * team list, toasts, announcements, results card, first-round tutorial hints
	  * side buttons (SHOP, MENU) and touch buttons (GRAPPLE, FLARE)
	Every value shown comes from the server (attributes / remotes).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local LootMath = require(Shared.LootMath)
local Progress = require(Shared.Progress)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local InputController = require(script.Parent.InputController)

local HudController = {}

local C = Ui.Colors
local gui
local refs = {}
local toasts = {}
local braceUntil = 0
local arrow = nil
local resultsShown = false
local slotKey = ""
local hintIndex = 0
local hintAt = 0

HudController.onMenu = nil -- fn(tab) set by MenuController
HudController.onNextSpectate = nil -- fn() set by EffectsController

local function isTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function HudController.timerText(seconds)
	return "LIFEBOAT LAUNCHES IN " .. Format.clock(seconds)
end

function HudController.lobbyText(state)
	if state.phase == "Countdown" then
		return string.format("Boarding in %ds...", state.timeLeft or 0)
	elseif state.phase == "Preparing" then
		return string.format("The ship is coming in... %d%%", state.building or 0)
	elseif state.phase == "Running" or state.phase == "Launching" then
		return "A round is underway - you'll sail on the next one"
	elseif state.phase == "Results" then
		return "Back to the harbour..."
	end
	local text = string.format("%d/%d ready", state.ready or 0, state.players or 0)
	if state.autoStartIn then
		text ..= string.format(" - starting in %ds", state.autoStartIn)
	end
	return text
end

local KIND_COLOR = {
	good = C.Green,
	error = C.Red,
	warn = C.Warm,
	info = C.Cream,
}

function HudController.toast(text, kind)
	if not refs.Toasts then
		return nil
	end
	local color = KIND_COLOR[kind] or C.Cream
	if type(kind) == "string" and string.sub(kind, 1, 5) == "loot:" then
		color = Ui.rarityColor(string.sub(kind, 6))
	end
	local t = Ui.panel({ Name = "Toast", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 0.12, LayoutOrder = os.clock() * 1000 % 1e6 }, 10)
	t.UIStroke.Color = color
	Ui.label(text, { Name = "Text", Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), TextColor3 = color, Font = Ui.Fonts.Bold, TextSize = 16, TextWrapped = true, Parent = t })
	t.Parent = refs.Toasts
	table.insert(toasts, t)
	while #toasts > 4 do
		local old = table.remove(toasts, 1)
		old:Destroy()
	end
	task.delay(4.5, function()
		local i = table.find(toasts, t)
		if i then
			table.remove(toasts, i)
		end
		t:Destroy()
	end)
	return t
end

function HudController.announce(text, color)
	local a = refs.Announce
	if not a then
		return
	end
	a.Visible = true
	a.Text.Text = text
	a.Text.TextColor3 = if type(color) == "table" then Ui.rgb(color) else C.Accent
	refs.announceUntil = os.clock() + 4
end

function HudController.brace(seconds)
	braceUntil = os.clock() + math.max(1.2, seconds or GameConfig.Sinking.BraceTime) + 0.4
end

function HudController.showArrow(seconds, target)
	arrow = { untilAt = os.clock() + (seconds or 15), target = target }
end

---------------------------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------------------------

local function buildTop()
	local top = Ui.panel({ Name = "TopBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(440, 64), BackgroundTransparency = 0.08 }, 14)
	top.UIStroke.Thickness = 2
	Ui.title("", { Name = "Timer", Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 4), TextSize = 24, TextColor3 = C.Accent, Parent = top })
	Ui.label("", { Name = "Sub", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 38), TextSize = 15, TextColor3 = C.Dim, Parent = top })
	top.Parent = gui
	refs.TopBar = top
end

local function buildTilt()
	local p = Ui.panel({ Name = "Tilt", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(210, 132), BackgroundTransparency = 0.08 }, 14)
	local view = Ui.new("Frame", { Name = "View", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 66), BackgroundColor3 = Color3.fromRGB(240, 170, 120), ClipsDescendants = true, Parent = p })
	Ui.corner(view, 8)
	Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(120, 90, 140), Color3.fromRGB(250, 180, 120)), Parent = view })
	local ship = Ui.new("Frame", { Name = "Ship", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(150, 20), BackgroundColor3 = C.Panel, Parent = view })
	Ui.corner(ship, 4)
	Ui.new("Frame", { Name = "Deck", Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = C.Cream, Parent = ship })
	Ui.new("Frame", { Name = "Funnel", Position = UDim2.new(0.42, 0, 0, -11), Size = UDim2.fromOffset(9, 12), BackgroundColor3 = C.Accent, Parent = ship })
	Ui.new("Frame", { Name = "Boat", Position = UDim2.new(0, 4, 0, -6), Size = UDim2.fromOffset(12, 6), BackgroundColor3 = C.Green, Parent = ship })
	Ui.new("Frame", { Name = "Water", Position = UDim2.new(0, 0, 0.62, 0), Size = UDim2.new(1, 0, 0.38, 0), BackgroundColor3 = Color3.fromRGB(30, 90, 120), BackgroundTransparency = 0.15, Parent = view })
	Ui.title("TILT 0°", { Name = "TiltText", Position = UDim2.fromOffset(10, 80), Size = UDim2.new(1, -20, 0, 22), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Cream, Parent = p })
	Ui.label("", { Name = "DepthText", Position = UDim2.fromOffset(10, 102), Size = UDim2.new(1, -20, 0, 20), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, Parent = p })
	p.Parent = gui
	refs.Tilt = p
end

local function buildOxygen()
	local holder = Ui.new("Frame", { Name = "Oxygen", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(380, 30), BackgroundTransparency = 1, Parent = gui })
	local back, fill = Ui.bar(holder, { Size = UDim2.new(1, 0, 1, 0) }, C.Sea)
	back.Name = "Bar"
	Ui.stroke(back, C.Line, 2, 0.2)
	fill.Name = "Fill"
	Ui.title("OXYGEN", { Name = "Label", Size = UDim2.new(1, 0, 1, 0), TextSize = 16, TextColor3 = C.Cream, Parent = back })
	refs.Oxygen = holder
	refs.OxygenFill = fill
	refs.OxygenLabel = back.Label
end

local function buildSlots()
	local s = Ui.new("Frame", { Name = "Slots", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -54), Size = UDim2.fromOffset(560, 74), BackgroundTransparency = 1, Parent = gui })
	Ui.list(s, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	refs.Slots = s
end

local function buildTeam()
	local t = Ui.new("Frame", { Name = "Team", Position = UDim2.new(0, 12, 0, 160), Size = UDim2.fromOffset(220, 300), BackgroundTransparency = 1, Parent = gui })
	Ui.list(t, 5)
	refs.Team = t
end

local function buildBrace()
	local b = Ui.title("BRACE!", { Name = "Brace", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromOffset(600, 110), TextSize = 96, TextColor3 = C.Red, TextStrokeTransparency = 0.2, TextStrokeColor3 = C.Black, Visible = false, Parent = gui })
	refs.Brace = b
end

local function buildDowned()
	local d = Ui.new("Frame", { Name = "Downed", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(80, 10, 14), BackgroundTransparency = 0.55, Visible = false, ZIndex = 5, Parent = gui })
	Ui.title("YOU'RE DOWN", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(600, 70), TextSize = 56, TextColor3 = C.Cream, ZIndex = 6, Parent = d })
	Ui.label("", { Name = "Timer", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(600, 30), TextSize = 22, Font = Ui.Fonts.Bold, TextColor3 = C.Warm, ZIndex = 6, Parent = d })
	local barHolder = Ui.new("Frame", { Name = "Revive", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.fromOffset(360, 26), BackgroundTransparency = 1, ZIndex = 6, Parent = d })
	local back, fill = Ui.bar(barHolder, { Size = UDim2.fromScale(1, 1) }, C.Green)
	back.ZIndex, fill.ZIndex = 6, 7
	Ui.label("Being revived...", { Name = "Label", Size = UDim2.fromScale(1, 1), TextSize = 15, Font = Ui.Fonts.Bold, ZIndex = 8, Parent = back })
	Ui.label("A teammate can hold E beside you to revive you.", { Name = "Help", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromOffset(600, 24), TextSize = 17, TextColor3 = C.Cream, ZIndex = 6, Parent = d })
	refs.Downed = d
	refs.ReviveFill = fill
	refs.ReviveBar = barHolder
end

local function buildSpectate()
	local s = Ui.panel({ Name = "Spectate", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(460, 52), Visible = false }, 12)
	Ui.label("LOST AT SEA - spectating", { Name = "Text", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -120, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 17, Font = Ui.Fonts.Bold, TextColor3 = C.Cream, Parent = s })
	local nextB = Ui.button("NEXT", { Name = "Next", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(90, 36) }, C.Accent)
	nextB.Parent = s
	nextB.Activated:Connect(function()
		if HudController.onNextSpectate then
			HudController.onNextSpectate()
		end
	end)
	s.Parent = gui
	refs.Spectate = s
end

local function shipCard(parent, key, order)
	local def = GameConfig.Ships[key]
	local card = Ui.panel({ Name = key, LayoutOrder = order, Size = UDim2.fromOffset(176, 132), BackgroundColor3 = C.PanelLight }, 12)
	card.UIStroke.Color = Ui.rgb(def.Color)
	Ui.title(string.upper(def.Name), { Name = "Title", Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 22), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Ui.rgb(def.Color), Parent = card })
	Ui.label(string.format("%d decks - %s", #def.Decks, Format.clock(def.RoundTime)), { Name = "Info", Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 18), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, Parent = card })
	Ui.label("", { Name = "Votes", Position = UDim2.fromOffset(10, 48), Size = UDim2.new(1, -20, 0, 18), TextSize = 14, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Cream, Parent = card })
	local b = Ui.button("VOTE", { Name = "Vote", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -20, 0, 36), TextSize = 15 }, C.Accent)
	b.Parent = card
	b.Activated:Connect(function()
		Net.event("Vote"):FireServer(key)
	end)
	card.Parent = parent
	return card
end

local function buildLobby()
	local l = Ui.panel({ Name = "Lobby", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(780, 196), BackgroundTransparency = 0.06 }, 16)
	l.UIStroke.Thickness = 2
	Ui.title("LAST LIFEBOAT", { Name = "Title", Position = UDim2.fromOffset(16, 8), Size = UDim2.fromOffset(240, 30), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Accent, Parent = l })
	Ui.label("The ship is sinking. One boat. Go!", { Name = "Pitch", Position = UDim2.fromOffset(16, 38), Size = UDim2.fromOffset(240, 20), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, Parent = l })
	local ready = Ui.button("READY", { Name = "Ready", Position = UDim2.fromOffset(16, 70), Size = UDim2.fromOffset(200, 60), TextSize = 26 }, C.Green)
	ready.Parent = l
	ready.Activated:Connect(function()
		local mine = ClientState.round.readyIds and ClientState.round.readyIds[tostring(Players.LocalPlayer.UserId)]
		Net.event("SetReady"):FireServer(not mine)
	end)
	Ui.label("", { Name = "Status", Position = UDim2.fromOffset(16, 138), Size = UDim2.fromOffset(220, 44), TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, TextColor3 = C.Cream, Parent = l })
	local cards = Ui.new("Frame", { Name = "Cards", Position = UDim2.fromOffset(240, 14), Size = UDim2.new(1, -254, 1, -28), BackgroundTransparency = 1, Parent = l })
	Ui.list(cards, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	for i, key in ipairs(GameConfig.ShipOrder) do
		shipCard(cards, key, i)
	end
	l.Parent = gui
	refs.Lobby = l
end

local function buildButtons()
	local b = Ui.new("Frame", { Name = "Buttons", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(110, 260), BackgroundTransparency = 1, Parent = gui })
	Ui.list(b, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right)
	local function add(name, text, color, order, fn)
		local btn = Ui.button(text, { Name = name, LayoutOrder = order, Size = UDim2.fromOffset(104, 46), TextSize = 16 }, color)
		Ui.stroke(btn, C.Line, 1.5, 0.2)
		btn.Parent = b
		btn.Activated:Connect(fn)
		return btn
	end
	add("Shop", "SHOP", C.Accent, 1, function()
		if HudController.onMenu then
			HudController.onMenu("Shop")
		end
	end)
	add("Menu", "MENU (M)", C.PanelLighter, 2, function()
		if InputController.menuToggle then
			InputController.menuToggle()
		end
	end)
	add("Grapple", if isTouch() then "GRAPPLE" else "GRAPPLE (Q)", C.Sea, 3, function()
		InputController.grapple()
	end)
	add("Flare", if isTouch() then "FLARE" else "FLARE (F)", C.Red, 4, function()
		InputController.flare()
	end)
	refs.Buttons = b
end

local function buildMisc()
	local toastsFrame = Ui.new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 84), Size = UDim2.fromOffset(520, 170), BackgroundTransparency = 1, Parent = gui })
	Ui.list(toastsFrame, 4, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
	refs.Toasts = toastsFrame
	local a = Ui.new("Frame", { Name = "Announce", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromOffset(820, 60), BackgroundColor3 = C.Black, BackgroundTransparency = 0.35, Visible = false, Parent = gui })
	Ui.corner(a, 12)
	Ui.title("", { Name = "Text", Size = UDim2.fromScale(1, 1), TextSize = 30, TextColor3 = C.Accent, TextStrokeTransparency = 0.4, Parent = a })
	refs.Announce = a
	local hint = Ui.panel({ Name = "Hint", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -14), Size = UDim2.fromOffset(330, 78), Visible = false, BackgroundColor3 = C.PanelLight }, 12)
	Ui.title("TIP", { Name = "Tag", Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(60, 18), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Accent, Parent = hint })
	Ui.label("", { Name = "Text", Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -24, 1, -30), TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = hint })
	hint.Parent = gui
	refs.Hint = hint
	local box = Ui.new("Frame", { Name = "Letterbox", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 4, Parent = gui })
	Ui.new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0.11, 0), BackgroundColor3 = C.Black, ZIndex = 4, Parent = box })
	Ui.new("Frame", { Name = "Bottom", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.11, 0), BackgroundColor3 = C.Black, ZIndex = 4, Parent = box })
	refs.Letterbox = box
	local ar = Ui.new("Frame", { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(120, 120), BackgroundTransparency = 1, Visible = false, Parent = gui })
	Ui.title("^", { Name = "Glyph", Size = UDim2.fromScale(1, 1), TextSize = 110, TextColor3 = C.Green, TextStrokeTransparency = 0.3, Parent = ar })
	Ui.title("LIFEBOAT", { Name = "Tag", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(160, 22), TextSize = 16, TextColor3 = C.Green, Parent = ar })
	refs.Arrow = ar
end

local function buildResults()
	local r = Ui.panel({ Name = "Results", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 470), Visible = false, ZIndex = 10 }, 16)
	r.UIStroke.Thickness = 2
	Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.PanelLight, C.Panel), Parent = r })
	Ui.title("", { Name = "Title", Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 8), TextSize = 40, ZIndex = 11, Parent = r })
	Ui.label("", { Name = "Sub", Size = UDim2.new(1, -40, 0, 22), Position = UDim2.fromOffset(20, 62), TextSize = 16, TextColor3 = C.Dim, ZIndex = 11, Parent = r })
	local body = Ui.scroll(r, { Name = "Body", Position = UDim2.fromOffset(20, 92), Size = UDim2.new(1, -40, 1, -150), ZIndex = 11 })
	Ui.list(body, 6)
	local close = Ui.button("CONTINUE", { Name = "Close", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(200, 42), ZIndex = 12 }, C.Accent)
	close.Parent = r
	close.Activated:Connect(function()
		r.Visible = false
		resultsShown = false
	end)
	r.Parent = gui
	refs.Results = r
	refs.ResultsBody = body
end

---------------------------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------------------------

function HudController.refreshSlots()
	local me = ClientState.me()
	local key = table.concat(me.carried, ",") .. "|" .. me.slots .. "|" .. tostring(ClientState.inRound())
	if key == slotKey then
		return
	end
	slotKey = key
	local s = refs.Slots
	Ui.clear(s)
	if not ClientState.inRound() then
		return
	end
	for i = 1, me.slots do
		local item = me.carried[i]
		local def = item and GameConfig.Loot[item]
		local color = if def then Ui.rarityColor(def.Rarity) else C.Dim
		local slot = Ui.new("TextButton", { Name = "Slot" .. i, LayoutOrder = i, Size = UDim2.fromOffset(66, 66), BackgroundColor3 = C.Panel, BackgroundTransparency = if def then 0.05 else 0.4, AutoButtonColor = false, Text = "", Parent = s })
		Ui.corner(slot, 10)
		Ui.stroke(slot, color, if def then 2.5 else 1, if def then 0 else 0.5)
		if def then
			Ui.lootIcon(slot, item, 46, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2) })
			Ui.label(def.Name, { Name = "Name", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, -4, 0, 16), TextSize = 11, TextScaled = true, Font = Ui.Fonts.Bold, TextColor3 = color, Parent = slot })
			if def.Weight >= 2 then
				Ui.label("HEAVY", { Name = "Heavy", Position = UDim2.fromOffset(3, 2), Size = UDim2.fromOffset(36, 12), TextSize = 9, Font = Ui.Fonts.Bold, TextColor3 = C.Red, Parent = slot })
			end
			slot.Activated:Connect(function()
				Net.event("DropLoot"):FireServer(i)
			end)
		else
			Ui.label(tostring(i), { Name = "Index", Size = UDim2.fromScale(1, 1), TextSize = 18, TextColor3 = C.Dim, Parent = slot })
		end
	end
	local value = LootMath.value(me.carried)
	Ui.label(string.format("%s\ncarried", Format.short(value)), { Name = "Value", LayoutOrder = 99, Size = UDim2.fromOffset(70, 66), TextSize = 15, Font = Ui.Fonts.Bold, TextColor3 = C.Accent, Parent = s })
end

function HudController.refreshLobby()
	local state = ClientState.round
	local l = refs.Lobby
	local inLobby = state.phase == "Lobby" or state.phase == "Countdown" or state.phase == "Preparing" or ((state.phase == "Running" or state.phase == "Launching") and not ClientState.inRound())
	l.Visible = inLobby and not resultsShown
	if not l.Visible then
		return
	end
	l.Status.Text = HudController.lobbyText(state)
	local mine = state.readyIds and state.readyIds[tostring(Players.LocalPlayer.UserId)]
	l.Ready.Text = if mine then "READY!" else "READY"
	Ui.setButtonColor(l.Ready, if mine then C.Accent else C.Green)
	local myVote = state.voteIds and state.voteIds[tostring(Players.LocalPlayer.UserId)]
	for _, shipKey in ipairs(GameConfig.ShipOrder) do
		local card = l.Cards:FindFirstChild(shipKey)
		local def = GameConfig.Ships[shipKey]
		local unlocked = Progress.shipUnlocked(shipKey, ClientState.escapes())
		local votes = state.votes and state.votes[shipKey] or 0
		card.Votes.Text = if unlocked then string.format("%d vote%s%s", votes, if votes == 1 then "" else "s", if state.leading == shipKey and votes > 0 then "  - LEADING" else "") else string.format("Unlocks at %d escapes (%d)", def.UnlockEscapes, ClientState.escapes())
		card.Votes.TextColor3 = if unlocked then C.Cream else C.Red
		card.Vote.Text = if not unlocked then "LOCKED" elseif myVote == shipKey then "VOTED" else "VOTE"
		Ui.setButtonColor(card.Vote, if not unlocked then C.PanelLighter elseif myVote == shipKey then C.Green else C.Accent)
	end
end

local function refreshTeam()
	local t = refs.Team
	Ui.clear(t)
	if not ClientState.inRound() then
		return
	end
	for i, row in ipairs(ClientState.team) do
		local f = Ui.panel({ Name = "Row", LayoutOrder = i, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 0.15 }, 8)
		local color = if row.state == "Alive" then C.Cream elseif row.state == "Downed" then C.Red elseif row.state == "Escaped" then C.Green else C.Dim
		local status = if row.aboard then "ABOARD" elseif row.state == "Alive" then "" else string.upper(row.state)
		Ui.label(row.name, { Name = "Name", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -90, 0, 22), TextSize = 14, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if row.vip then Color3.fromRGB(255, 205, 70) else color, Parent = f })
		Ui.label(status, { Name = "Status", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(80, 22), TextSize = 12, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = if row.aboard then C.Green else color, Parent = f })
		local _, fill = Ui.bar(f, { Position = UDim2.new(0, 10, 1, -9), Size = UDim2.new(1, -20, 0, 5) }, C.Sea)
		fill.Size = UDim2.fromScale(row.oxygen or 1, 1)
		f.Parent = t
	end
end

function HudController.showResults(summary)
	local r = refs.Results
	resultsShown = true
	r.Visible = true
	local escaped = summary.outcome == "Escaped"
	r.Title.Text = if escaped then "ESCAPED!" else "LOST AT SEA"
	r.Title.TextColor3 = if escaped then C.Green else C.Red
	local def = GameConfig.Ships[summary.ship]
	r.Sub.Text = string.format("%s%s - %s", def and def.Name or "", if summary.fullCrew then " - FULL CREW!" else "", Format.clock(summary.time or 0))
	local body = refs.ResultsBody
	Ui.clear(body)
	local order = 0
	local function row(text, right, color)
		order += 1
		local f = Ui.new("Frame", { Name = "Line", LayoutOrder = order, Size = UDim2.new(1, -8, 0, 24), BackgroundTransparency = 1, ZIndex = 11, Parent = body })
		Ui.label(text, { Name = "L", Size = UDim2.new(1, -110, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, TextColor3 = color or C.Text, ZIndex = 11, Parent = f })
		if right then
			Ui.label(right, { Name = "R", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 110, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 16, Font = Ui.Fonts.Bold, TextColor3 = C.Accent, ZIndex = 11, Parent = f })
		end
		return f
	end
	local function header(text)
		order += 1
		Ui.title(text, { Name = "Header", LayoutOrder = order, Size = UDim2.new(1, -8, 0, 24), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Accent, ZIndex = 11, Parent = body })
	end
	header("ESCAPED")
	row(if #(summary.escapedNames or {}) > 0 then table.concat(summary.escapedNames, ", ") else "Nobody made it...", nil, C.Cream)
	header("LOOT BANKED")
	if #(summary.items or {}) == 0 then
		row(if escaped then "(empty hands)" else "Carried loot sank with the ship.", nil, C.Dim)
	end
	for _, key in ipairs(summary.items or {}) do
		local item = GameConfig.Loot[key]
		row(string.format("%s  (%s)", item.Name, item.Rarity), Format.short(item.Value), Ui.rarityColor(item.Rarity))
	end
	header("COINS")
	for _, line in ipairs(summary.lines or {}) do
		row(line[1], "+" .. Format.short(line[2]))
	end
	row("TOTAL", "+" .. Format.short(summary.coins or 0), C.Green)
	header("SESSION GOALS")
	for _, goal in ipairs(summary.goals or {}) do
		row(goal.text, if goal.done then "DONE" else string.format("%d/%d", goal.progress, goal.target), if goal.done then C.Green else C.Cream)
	end
	return r
end

function HudController.resultsShown()
	return resultsShown
end

local function setVisible(name, v)
	if refs[name] then
		refs[name].Visible = v
	end
end

function HudController.tick()
	if not gui then
		return
	end
	local now = os.clock()
	local serverNow = ClientState.serverNow()
	local me = ClientState.me()
	local round = ClientState.round
	local playing = ClientState.inRound()
	-- timer + next lurch
	local launchAt = workspace:GetAttribute("LL_LaunchAt")
	setVisible("TopBar", playing or round.phase == "Running")
	if launchAt then
		refs.TopBar.Timer.Text = HudController.timerText(math.max(0, launchAt - serverNow))
		refs.TopBar.Timer.TextColor3 = if launchAt - serverNow < 30 then C.Red else C.Accent
		local nextLurch = workspace:GetAttribute("LL_NextLurch")
		refs.TopBar.Sub.Text = if nextLurch then string.format("Next lurch in %ds  -  valves delay it", math.max(0, math.ceil(nextLurch - serverNow))) else ""
	elseif round.phase == "Launching" then
		refs.TopBar.Timer.Text = "THE LIFEBOAT IS LAUNCHING"
		refs.TopBar.Sub.Text = ""
	end
	-- tilt / depth
	setVisible("Tilt", playing)
	if playing then
		local tilt = workspace:GetAttribute("LL_Tilt") or 0
		refs.Tilt.View.Ship.Rotation = tilt
		refs.Tilt.TiltText.Text = string.format("TILT %d°", math.floor(tilt + 0.5))
		refs.Tilt.TiltText.TextColor3 = if tilt >= GameConfig.Sinking.SlideTilt then C.Red else C.Cream
		local root = ClientState.root()
		local ship = ClientState.ship()
		if root and ship then
			local localY = ship:GetPivot():PointToObjectSpace(root.CFrame.Position).Y
			local deck = math.clamp(math.floor((localY - GameConfig.Ship.DeckBase) / GameConfig.Ship.DeckHeight) + 1, 1, 9)
			local above = root.CFrame.Position.Y - 3 - GameConfig.World.SeaLevel
			refs.Tilt.DepthText.Text = if above < 0 then string.format("Deck %d - UNDERWATER", deck) else string.format("Deck %d - sea %d studs below", deck, math.floor(above))
			refs.Tilt.DepthText.TextColor3 = if above < 4 then C.Red else C.Dim
		end
	end
	-- oxygen
	local showOxygen = playing and me.state == "Alive"
	setVisible("Oxygen", showOxygen)
	if showOxygen then
		local f = math.clamp(me.oxygen / math.max(1, me.oxygenMax), 0, 1)
		refs.OxygenFill.Size = UDim2.fromScale(f, 1)
		refs.OxygenFill.BackgroundColor3 = if f < 0.3 then C.Red elseif f < 0.6 then C.Warm else C.Sea
		refs.OxygenLabel.Text = string.format("OXYGEN  %.0fs", me.oxygen)
	end
	HudController.refreshSlots()
	-- brace
	local bracing = now < braceUntil
	refs.Brace.Visible = bracing
	if bracing then
		refs.Brace.TextTransparency = 0.15 * math.abs(math.sin(now * 12))
		refs.Brace.Rotation = math.sin(now * 30) * 2
	end
	-- downed
	local downed = playing and me.state == "Downed"
	refs.Downed.Visible = downed
	if downed then
		local left = if me.bleedEnds then math.max(0, me.bleedEnds - serverNow) else 0
		refs.Downed.Timer.Text = string.format("Bleeding out in %ds%s", math.ceil(left), if me.jackets > 0 then "  (Life Jacket ready)" else "")
		local progress = if me.reviveStart then math.clamp((serverNow - me.reviveStart) / GameConfig.Downed.ReviveHold, 0, 1) else 0
		refs.ReviveBar.Visible = me.reviveStart ~= nil
		refs.ReviveFill.Size = UDim2.fromScale(progress, 1)
	end
	-- spectate
	refs.Spectate.Visible = round.phase == "Running" and me.inRound and me.state == "Out"
	if refs.Spectate.Visible and refs.spectating then
		refs.Spectate.Text.Text = "LOST AT SEA - spectating " .. refs.spectating
	end
	-- arrow to the lifeboat (flare)
	if arrow and now < arrow.untilAt and playing then
		local camera = workspace.CurrentCamera
		refs.Arrow.Visible = true
		if camera then
			local rel = camera.CFrame:PointToObjectSpace(arrow.target)
			refs.Arrow.Rotation = math.deg(math.atan2(rel.X, -rel.Z))
		end
	else
		refs.Arrow.Visible = false
		if arrow and now >= arrow.untilAt then
			arrow = nil
		end
	end
	-- buttons
	refs.Buttons.Grapple.Visible = me.grapple
	refs.Buttons.Flare.Visible = playing and me.flares > 0
	refs.Buttons.Flare.Text = string.format(if isTouch() then "FLARE x%d" else "FLARE x%d (F)", me.flares)
	if me.grapple and me.grappleReady and serverNow < me.grappleReady then
		refs.Buttons.Grapple.Text = string.format("GRAPPLE %ds", math.ceil(me.grappleReady - serverNow))
	elseif me.grapple then
		refs.Buttons.Grapple.Text = if isTouch() then "GRAPPLE" else "GRAPPLE (Q)"
	end
	-- announcements
	if refs.announceUntil and now > refs.announceUntil then
		refs.Announce.Visible = false
		refs.announceUntil = nil
	end
	-- tutorial hints during the first rounds
	local p = ClientState.profile
	local wantHints = playing and p ~= nil and not p.tutorialDone and ClientState.setting("Hints") ~= false
	if wantHints then
		if hintIndex == 0 or now - hintAt > 9 then
			hintIndex = hintIndex % #GameConfig.TutorialHints + 1
			hintAt = now
			refs.Hint.Text.Text = GameConfig.TutorialHints[hintIndex]
		end
	end
	refs.Hint.Visible = wantHints
	HudController.refreshLobby()
end

function HudController.setLetterbox(on)
	refs.Letterbox.Visible = on
end

function HudController.setSpectating(name)
	refs.spectating = name
end

function HudController.refs()
	return refs
end

function HudController.init()
	gui = Ui.screen("LifeboatHUD", 5)
	buildTop()
	buildTilt()
	buildOxygen()
	buildSlots()
	buildTeam()
	buildBrace()
	buildDowned()
	buildSpectate()
	buildLobby()
	buildButtons()
	buildMisc()
	buildResults()
	ClientState.Notified:Connect(HudController.toast)
	ClientState.Announced:Connect(HudController.announce)
	ClientState.Braced:Connect(HudController.brace)
	ClientState.FlareArrow:Connect(HudController.showArrow)
	ClientState.TeamChanged:Connect(refreshTeam)
	ClientState.Results:Connect(HudController.showResults)
	ClientState.RoundChanged:Connect(function(state)
		if state.phase == "Lobby" and resultsShown then
			-- keep the card up a moment in the harbour, then clear it
			task.delay(6, function()
				if ClientState.round.phase == "Lobby" then
					refs.Results.Visible = false
					resultsShown = false
				end
			end)
		end
		HudController.refreshLobby()
		refreshTeam()
	end)
	ClientState.ProfileChanged:Connect(function()
		slotKey = ""
		HudController.refreshLobby()
	end)
	RunService.RenderStepped:Connect(HudController.tick)
	HudController.tick()
end

return HudController
