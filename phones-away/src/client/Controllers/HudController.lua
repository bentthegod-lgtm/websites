--[[
	HudController - everything on screen except the phone and the menus:

	  top        class clock + phase ("WRITING ON THE BOARD - SAFE") + event chips, or the
	             hallway countdown between classes
	  left       Clout, this class's pending Clout, rank + level bar, session goals
	  bottom-left  the teacher's suspicion of YOU (eye meter) + red screen edges
	  right      class group chat feed
	  centre     pop quiz, results, detention (buy back), seating chart picker
	  bottom     AIRPLANE / NOTE / REPORT (Teacher's Pet) buttons, toasts, banners
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local Net = require(Shared.Net)
local GameConfig = require(Shared.Config.GameConfig)
local TeacherConfig = require(Shared.Config.TeacherConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)
local Format = require(Shared.Format)
local Clock = require(Shared.Clock)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local HudController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui
local top = {}
local hall = {}
local wallet = {}
local goalsFrame
local meter = {}
local edges = {}
local chatFrame
local toastFrame
local bannerLabel
local quiz = {}
local results
local detention = {}
local actions = {}
local chart = {}
local shownCloutValue = 0
local phaseLength = 20

local TIPS = {
	"Every class is a TEST. Hold F (or the PHONE button), then SNAP to screenshot it.",
	"Keep the phone out while ScanBuddy scans - hide it and the screenshot is lost!",
	"She can't see you while she writes on the board... unless she glances back. Watch for the '...' pause!",
	"Walking the rows = VERY RISKY. She checks desks up close.",
	"Answering is safe: memorise the answers, put the phone away, then click them.",
	"Friends get the same test version. Help each other!",
	"Caught = phone confiscated, test RIPPED UP, detention.",
	"Upgrades: better phone = more answers per snap, Scanner = faster scans, Dim Screen = smaller flash.",
	"Pizza Party gives the WHOLE server a chill class with 2x Clout.",
}

---------------------------------------------------------------------------------------------
-- Build helpers
---------------------------------------------------------------------------------------------

local function chip(parent, text, color, props)
	local label = Ui.label(text, props)
	label.Font = Ui.Fonts.Title
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = color
	label.TextColor3 = Color3.fromRGB(20, 20, 30)
	Ui.corner(label, 10)
	label.Parent = parent
	return label
end

local function buildTop()
	top.frame = Ui.new("Frame", { Name = "Top", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(560, 92), BackgroundTransparency = 1, Parent = gui })
	local clockBox = Ui.panel({ Size = UDim2.fromOffset(120, 64), Parent = top.frame })
	Ui.stroke(clockBox, C.Gold, 0.3, 2)
	top.clock = Ui.label("10:05", { Font = Ui.Fonts.Title, TextSize = 34, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 40), Parent = clockBox })
	top.left = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 13, TextColor3 = C.Dim, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 18), Parent = clockBox })
	top.phase = chip(top.frame, "", C.Good, { TextSize = 22, Position = UDim2.fromOffset(130, 0), Size = UDim2.fromOffset(430, 40) })
	top.barBack = Ui.new("Frame", { Position = UDim2.fromOffset(130, 46), Size = UDim2.fromOffset(430, 10), BackgroundColor3 = C.Panel, Parent = top.frame })
	Ui.corner(top.barBack, 5)
	top.bar = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Good, Parent = top.barBack })
	Ui.corner(top.bar, 5)
	top.event = chip(top.frame, "", C.Accent2, { TextSize = 15, Position = UDim2.fromOffset(130, 62), Size = UDim2.fromOffset(212, 26), Visible = false })
	top.pizza = chip(top.frame, "PIZZA PARTY 2x", Color3.fromRGB(255, 160, 70), { TextSize = 15, Position = UDim2.fromOffset(348, 62), Size = UDim2.fromOffset(212, 26), Visible = false })

	hall.frame = Ui.panel({ Name = "Hallway", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(520, 86), Parent = gui })
	Ui.stroke(hall.frame, C.Accent, 0.3, 2)
	hall.title = Ui.label("NEXT CLASS IN 0:20", { Font = Ui.Fonts.Title, TextSize = 30, TextColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 42), Parent = hall.frame })
	hall.tip = Ui.label(TIPS[1], { TextSize = 14, TextColor3 = C.Dim, TextWrapped = true, Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 40), Parent = hall.frame })
end

local function buildWallet()
	wallet.frame = Ui.panel({ Name = "Wallet", Position = UDim2.fromOffset(12, 52), Size = UDim2.fromOffset(230, 104), Parent = gui })
	wallet.clout = Ui.label("0", { Font = Ui.Fonts.Title, TextSize = 30, TextColor3 = C.Gold, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, Parent = wallet.frame })
	Ui.label("CLOUT", { Font = Ui.Fonts.Bold, TextSize = 12, TextColor3 = C.Dim, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 14), Size = UDim2.fromOffset(60, 16), TextXAlignment = Enum.TextXAlignment.Right, Parent = wallet.frame })
	wallet.pending = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = C.Good, Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -24, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, Parent = wallet.frame })
	wallet.rank = Ui.label("Freshman  Lv 1", { Font = Ui.Fonts.Title, TextSize = 16, Position = UDim2.fromOffset(12, 60), Size = UDim2.new(1, -24, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, Parent = wallet.frame })
	local back = Ui.new("Frame", { Position = UDim2.fromOffset(12, 84), Size = UDim2.new(1, -24, 0, 8), BackgroundColor3 = C.PanelLight, Parent = wallet.frame })
	Ui.corner(back, 4)
	wallet.xp = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent2, Parent = back })
	Ui.corner(wallet.xp, 4)
	goalsFrame = Ui.new("Frame", { Name = "Goals", Position = UDim2.fromOffset(12, 164), Size = UDim2.fromOffset(230, 140), BackgroundTransparency = 1, Parent = gui })
	Ui.list(goalsFrame, 4)
end

local function buildMeter()
	meter.frame = Ui.panel({ Name = "Suspicion", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -24), Size = UDim2.fromOffset(250, 76), Visible = false, Parent = gui })
	meter.title = Ui.label("SHE'S NOT LOOKING", { Font = Ui.Fonts.Title, TextSize = 18, TextColor3 = C.Good, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -60, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, Parent = meter.frame })
	meter.mark = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 40, TextColor3 = C.Warn, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(44, 44), Parent = meter.frame })
	local back = Ui.new("Frame", { Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 0, 22), BackgroundColor3 = C.PanelLight, Parent = meter.frame })
	Ui.corner(back, 8)
	meter.fill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Good, Parent = back })
	Ui.corner(meter.fill, 8)
	for _, at in ipairs({ TeacherConfig.Suspicion.Question, TeacherConfig.Suspicion.Alert }) do
		Ui.new("Frame", { Position = UDim2.new(at, -1, 0, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.4, Parent = back })
	end
	-- Red screen edges that grow with suspicion.
	local specs = {
		{ UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.18, 0), 90 },
		{ UDim2.new(0, 0, 0.82, 0), UDim2.new(1, 0, 0.18, 0), 270 },
		{ UDim2.new(0, 0, 0, 0), UDim2.new(0.12, 0, 1, 0), 0 },
		{ UDim2.new(0.88, 0, 0, 0), UDim2.new(0.12, 0, 1, 0), 180 },
	}
	for i, spec in ipairs(specs) do
		local f = Ui.new("Frame", { Name = "Edge" .. i, Position = spec[1], Size = spec[2], BackgroundColor3 = Color3.fromRGB(255, 30, 30), BackgroundTransparency = 1, ZIndex = 1, Parent = gui })
		Ui.new("UIGradient", { Rotation = spec[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = f })
		table.insert(edges, f)
	end
end

local function buildChat()
	chatFrame = Ui.panel({ Name = "GroupChat", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 150), Size = UDim2.fromOffset(270, 230), BackgroundTransparency = 0.35, Parent = gui })
	Ui.label("CLASS GROUP CHAT", { Font = Ui.Fonts.Title, TextSize = 15, TextColor3 = C.Accent2, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = chatFrame })
	local list = Ui.new("Frame", { Name = "List", Position = UDim2.fromOffset(8, 28), Size = UDim2.new(1, -16, 1, -34), BackgroundTransparency = 1, ClipsDescendants = true, Parent = chatFrame })
	local layout = Ui.list(list, 4)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
end

function HudController.addChat(author, text, color)
	local list = chatFrame:FindFirstChild("List")
	local bubble = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.2, LayoutOrder = math.floor(os.clock() * 100), Parent = list })
	Ui.corner(bubble, 8)
	Ui.padding(bubble, 5)
	Ui.label(string.format("<b>@%s</b>  %s", author, text), {
		RichText = true,
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = if color then Ui.rgb(color) else C.Text,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bubble,
	})
	local bubbles = {}
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(bubbles, child)
		end
	end
	table.sort(bubbles, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #bubbles > 6 do
		table.remove(bubbles, 1):Destroy()
	end
	AudioUtil.play(AudioAssets.Notification)
end

local function buildToasts()
	toastFrame = Ui.new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(520, 160), BackgroundTransparency = 1, ZIndex = 50, Parent = gui })
	local layout = Ui.list(toastFrame, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	bannerLabel = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 26, TextStrokeTransparency = 0.2, TextWrapped = true, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 152), Size = UDim2.fromOffset(760, 64), TextTransparency = 1, TextStrokeColor3 = Color3.new(0, 0, 0), ZIndex = 50, Parent = gui })
end

function HudController.toast(text, kind)
	local color = if kind == "good" then C.Good elseif kind == "warn" then C.Warn elseif kind == "bad" then C.Danger else C.Accent2
	local t = Ui.panel({ Size = UDim2.fromOffset(500, 34), BackgroundTransparency = 0.15, LayoutOrder = math.floor(os.clock() * 100), ZIndex = 50, Parent = toastFrame })
	Ui.stroke(t, color, 0.2, 2)
	Ui.label(text, { Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = color, TextWrapped = true, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), ZIndex = 51, Parent = t })
	task.delay(3.5, function()
		if t.Parent then
			t:Destroy()
		end
	end)
	local list = {}
	for _, child in ipairs(toastFrame:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #list > 4 do
		table.remove(list, 1):Destroy()
	end
end

function HudController.banner(text, color)
	bannerLabel.Text = text
	bannerLabel.TextColor3 = if color then Ui.rgb(color) else C.Gold
	bannerLabel.TextTransparency = 0
	bannerLabel.TextStrokeTransparency = 0.2
	local token = os.clock()
	bannerLabel:SetAttribute("Token", token)
	task.delay(4.5, function()
		if bannerLabel:GetAttribute("Token") == token then
			TweenService:Create(bannerLabel, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Quiz
---------------------------------------------------------------------------------------------

local function buildQuiz()
	quiz.frame = Ui.panel({ Name = "Quiz", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(460, 280), BackgroundColor3 = C.Paper, BackgroundTransparency = 0, Visible = false, ZIndex = 30, Parent = gui })
	Ui.stroke(quiz.frame, Color3.fromRGB(190, 120, 255), 0, 4)
	Ui.label("BONUS QUESTION!", { Font = Ui.Fonts.Title, TextSize = 32, TextColor3 = Color3.fromRGB(150, 70, 220), Size = UDim2.new(1, 0, 0, 44), ZIndex = 31, Parent = quiz.frame })
	quiz.question = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 24, TextColor3 = C.Ink, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, ZIndex = 31, Parent = quiz.frame })
	quiz.buttons = {}
	for i = 1, 4 do
		local b = Ui.button("", { Position = UDim2.new((i - 1) / 4, 6, 0, 100), Size = UDim2.new(1 / 4, -12, 0, 70), TextSize = 17, ZIndex = 31, Parent = quiz.frame }, Color3.fromRGB(150, 90, 230))
		b.TextWrapped = true
		b.Activated:Connect(function()
			if quiz.answered then
				return
			end
			quiz.answered = i
			Net.event("QuizAnswer"):FireServer(i)
			for j, other in ipairs(quiz.buttons) do
				other.BackgroundColor3 = if j == i then C.Accent2 else C.PanelLight
			end
		end)
		quiz.buttons[i] = b
	end
	quiz.timer = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 20, TextColor3 = C.Ink, Position = UDim2.fromOffset(0, 184), Size = UDim2.new(1, 0, 0, 26), ZIndex = 31, Parent = quiz.frame })
	quiz.warning = Ui.label("PHONE OUT = WRONG ANSWER. Put it away!", { Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = C.Danger, Position = UDim2.fromOffset(0, 220), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, ZIndex = 31, Parent = quiz.frame })
end

function HudController.showQuiz(data)
	quiz.data = data
	quiz.answered = nil
	if not data then
		quiz.frame.Visible = false
		return
	end
	quiz.question.Text = data.question
	for i, b in ipairs(quiz.buttons) do
		b.Text = data.options[i] or ""
		b.BackgroundColor3 = Color3.fromRGB(150, 90, 230)
	end
	quiz.frame.Visible = true
	AudioUtil.play(AudioAssets.QuizSting)
end

---------------------------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------------------------

function HudController.showResults(data)
	if results then
		results:Destroy()
	end
	results = Ui.panel({ Name = "Results", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(500, 380), BackgroundColor3 = C.Paper, BackgroundTransparency = 0, ZIndex = 40, Parent = gui })
	Ui.stroke(results, C.Gold, 0, 4)
	Ui.label("PENCILS DOWN!", { Font = Ui.Fonts.Title, TextSize = 32, TextColor3 = C.Accent, Size = UDim2.new(0.7, 0, 0, 48), ZIndex = 41, Parent = results })
	local g = data.grade
	-- Big red-pen grade in the corner.
	local letter = Ui.label(g and g.letter or "-", { Font = Ui.Fonts.Title, TextSize = 64, TextColor3 = if g and (g.letter == "F" or g.ripped) then C.Danger else Color3.fromRGB(220, 40, 60), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 6), Size = UDim2.fromOffset(120, 80), Rotation = 8, ZIndex = 42, Parent = results })
	Ui.stroke(letter, Color3.fromRGB(220, 40, 60), 0.2, 3)
	local bonus = {}
	if g and g.aplus > 0 then
		table.insert(bonus, "A+ bonus")
	end
	if g and g.ghost > 0 then
		table.insert(bonus, "GHOST bonus (never suspected!)")
	end
	local lines = {
		if g and g.ripped then "Your test was RIPPED UP: F, 0 points." elseif g then string.format("Score: %d / %d  (%d%%)  version %s", g.correct, g.count, g.percent, g.version) else "No test this class.",
		string.format("Clout banked: +%s%s", Format.number(data.clout), if #bonus > 0 then "  (" .. table.concat(bonus, ", ") .. ")" else ""),
		if data.caught then string.format("CAUGHT! Lost %s side Clout to the basket", Format.number(data.lost)) else "Never caught. Smooth.",
		if data.quiz == "correct" then "Bonus question: correct" elseif data.quiz == "phone" then "Bonus question: wrong (phone out!)" elseif data.quiz == "wrong" then "Bonus question: wrong" else "",
		string.format("Screenshots taken: %d", data.snaps or 0),
	}
	if data.pizza then
		table.insert(lines, "Pizza party class: 2x Clout!")
	end
	for i, text in ipairs(lines) do
		Ui.label(text, { Font = Ui.Fonts.Bold, TextSize = 17, TextColor3 = if (i == 3 and data.caught) or (i == 1 and g and g.ripped) then C.Danger else C.Ink, TextWrapped = true, Position = UDim2.fromOffset(20, 56 + (i - 1) * 28), Size = UDim2.new(1, -40, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41, Parent = results })
	end
	Ui.label("TOP OF THE CLASS", { Font = Ui.Fonts.Title, TextSize = 18, TextColor3 = Color3.fromRGB(150, 70, 220), Position = UDim2.fromOffset(20, 240), Size = UDim2.new(1, -40, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41, Parent = results })
	for i = 1, 3 do
		local row = data.top and data.top[i]
		if row then
			Ui.label(string.format("%d. %s  %s  %s%s", i, row.name, row.letter or "", Format.number(row.clout), if row.caught then "  (caught)" else ""), { TextSize = 16, TextColor3 = C.Ink, Position = UDim2.fromOffset(28, 264 + (i - 1) * 22), Size = UDim2.new(1, -56, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41, Parent = results })
		end
	end
	if data.legend then
		Ui.label("PHONE LEGEND: " .. data.legend, { Font = Ui.Fonts.Title, TextSize = 18, TextColor3 = Color3.fromRGB(220, 150, 20), Position = UDim2.fromOffset(0, 340), Size = UDim2.new(1, 0, 0, 30), ZIndex = 41, Parent = results })
	end
	AudioUtil.play(AudioAssets.ClassOver)
	local frame = results
	task.delay(GameConfig.ResultsSeconds, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Detention
---------------------------------------------------------------------------------------------

local function detentionPassProduct()
	for _, p in ipairs(ShopConfig.Products) do
		if p.Key == "DetentionPass" then
			return p
		end
	end
	return nil
end

local function buildDetention()
	detention.frame = Ui.panel({ Name = "Detention", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 160), Size = UDim2.fromOffset(440, 220), BackgroundColor3 = Color3.fromRGB(70, 20, 30), BackgroundTransparency = 0.05, Visible = false, ZIndex = 30, Parent = gui })
	Ui.stroke(detention.frame, C.Danger, 0, 4)
	Ui.label("DETENTION", { Font = Ui.Fonts.Title, TextSize = 38, TextColor3 = C.Danger, Size = UDim2.new(1, 0, 0, 48), ZIndex = 31, Parent = detention.frame })
	detention.sub = Ui.label("Phone CONFISCATED, test RIPPED UP. Sit tight until the bell (F)... or escape for a fresh copy:", { TextSize = 14, TextWrapped = true, Position = UDim2.fromOffset(16, 48), Size = UDim2.new(1, -32, 0, 40), ZIndex = 31, Parent = detention.frame })
	detention.bail = Ui.button("TALK YOUR WAY OUT", { Position = UDim2.fromOffset(16, 96), Size = UDim2.new(0.5, -20, 0, 54), TextSize = 16, ZIndex = 31, Parent = detention.frame }, C.Gold:Lerp(Color3.new(0, 0, 0), 0.25))
	detention.bail.Activated:Connect(function()
		Net.event("Bail"):FireServer()
	end)
	detention.pass = Ui.button("USE PASS", { Position = UDim2.new(0.5, 4, 0, 96), Size = UDim2.new(0.5, -20, 0, 54), TextSize = 16, ZIndex = 31, Parent = detention.frame }, C.Accent)
	detention.pass.Activated:Connect(function()
		local profile = ClientState.profile
		if profile and profile.tokens and profile.tokens.DetentionPass > 0 then
			Net.event("UseDetentionPass"):FireServer()
		else
			Net.event("ShopBuy"):FireServer("DetentionPass")
		end
	end)
	detention.note = Ui.label("One escape per class. The round goes on without you!", { TextSize = 13, TextColor3 = C.Dim, Position = UDim2.fromOffset(16, 160), Size = UDim2.new(1, -32, 0, 40), TextWrapped = true, ZIndex = 31, Parent = detention.frame })
end

local function refreshDetention()
	local inDetention = ClientState.status() == "Detention"
	detention.frame.Visible = inDetention
	if not inDetention then
		return
	end
	local profile = ClientState.profile
	detention.bail.Text = string.format("TALK YOUR WAY OUT\n%s Clout", Format.number(profile and profile.bailCost or GameConfig.DetentionBailBase))
	local passes = profile and profile.tokens and profile.tokens.DetentionPass or 0
	local product = detentionPassProduct()
	detention.pass.Text = if passes > 0 then string.format("USE PASS (%d)", passes) else string.format("GET OUT PASS\nR$ %d", product and product.Robux or 25)
end

---------------------------------------------------------------------------------------------
-- Actions + seating chart
---------------------------------------------------------------------------------------------

local function closeChart()
	chart.frame.Visible = false
	chart.mode = nil
end

local function openChart(mode)
	chart.mode = mode
	chart.frame.Visible = true
	chart.title.Text = if mode == "plane" then "THROW A PAPER AIRPLANE AT..." elseif mode == "note" then "PASS A NOTE TO... (next to you)" else "REPORT A PHONE USER (Teacher's Pet)"
	local occupants = ClientState.deskOccupants()
	local myDesk = ClientState.desk()
	local cols = #GameConfig.Classroom.DeskColumns
	for index, b in pairs(chart.buttons) do
		local who = occupants[index]
		local row = math.ceil(index / cols)
		local col = (index - 1) % cols + 1
		local myRow = math.ceil(myDesk / cols)
		local myCol = (myDesk - 1) % cols + 1
		local enabled
		if mode == "plane" then
			enabled = index ~= myDesk
		elseif mode == "note" then
			enabled = who ~= nil and who ~= player and row == myRow and math.abs(col - myCol) == 1
		else
			enabled = who ~= nil and who ~= player
		end
		b.Text = if index == myDesk then "YOU" elseif who then who.DisplayName else "(empty)"
		b.BackgroundColor3 = if enabled then C.Accent2:Lerp(Color3.new(0, 0, 0), 0.2) else C.PanelLight
		b.AutoButtonColor = enabled
		b:SetAttribute("Enabled", enabled)
	end
end

local function buildActions()
	actions.frame = Ui.new("Frame", { Name = "Actions", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -150, 1, -24), Size = UDim2.fromOffset(300, 50), BackgroundTransparency = 1, Visible = false, Parent = gui })
	local specs = { { "AIRPLANE", "plane", C.Accent2 }, { "NOTE", "note", C.Good }, { "REPORT", "report", C.Warn } }
	for i, spec in ipairs(specs) do
		local b = Ui.button(spec[1], { Position = UDim2.new((i - 1) / 3, 4, 0, 0), Size = UDim2.new(1 / 3, -8, 1, 0), TextSize = 16, Parent = actions.frame }, spec[3]:Lerp(Color3.new(0, 0, 0), 0.3))
		b.Name = spec[2]
		b.Activated:Connect(function()
			if chart.mode == spec[2] then
				closeChart()
			else
				openChart(spec[2])
			end
		end)
		actions[spec[2]] = b
	end
	chart.frame = Ui.panel({ Name = "SeatingChart", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 300), Visible = false, ZIndex = 35, Parent = gui })
	Ui.stroke(chart.frame, C.Accent2, 0.2, 3)
	chart.title = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 20, TextColor3 = C.Accent2, Size = UDim2.new(1, -110, 0, 36), Position = UDim2.fromOffset(12, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 36, Parent = chart.frame })
	local close = Ui.button("CLOSE", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(90, 30), ZIndex = 36, Parent = chart.frame }, C.Danger)
	close.Activated:Connect(closeChart)
	local boardLabel = Ui.label("WHITEBOARD (front)", { Font = Ui.Fonts.Bold, TextSize = 13, TextColor3 = C.Ink, BackgroundTransparency = 0, BackgroundColor3 = C.Paper, Position = UDim2.fromOffset(60, 44), Size = UDim2.new(1, -120, 0, 20), ZIndex = 36, Parent = chart.frame })
	Ui.corner(boardLabel, 6)
	chart.buttons = {}
	local cols = #GameConfig.Classroom.DeskColumns
	local rows = #GameConfig.Classroom.DeskRows
	for row = 1, rows do
		for col = 1, cols do
			local index = (row - 1) * cols + col
			local b = Ui.button("", { Position = UDim2.new((col - 1) / cols, 8, 0, 74 + (row - 1) * 72), Size = UDim2.new(1 / cols, -16, 0, 62), TextSize = 14, ZIndex = 36, Parent = chart.frame })
			b.TextWrapped = true
			b.Activated:Connect(function()
				if not b:GetAttribute("Enabled") then
					return
				end
				local mode = chart.mode
				local who = ClientState.deskOccupants()[index]
				if mode == "plane" then
					Net.event("ThrowPlane"):FireServer(index)
				elseif mode == "note" and who then
					Net.event("PassNote"):FireServer(who.UserId)
				elseif mode == "report" and who then
					Net.event("Report"):FireServer(who.UserId)
				end
				closeChart()
			end)
			chart.buttons[index] = b
		end
	end
end

local function refreshActions()
	local seated = ClientState.status() == "Seated" and ClientState.roundState == "Class"
	actions.frame.Visible = seated
	actions.report.Visible = player:GetAttribute("PA_Pet") == true
	if not seated then
		closeChart()
	end
end

---------------------------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------------------------

local function renderGoals(profile)
	for _, child in ipairs(goalsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, goal in ipairs(profile and profile.goals or {}) do
		local row = Ui.panel({ Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 0.35, LayoutOrder = i, Parent = goalsFrame })
		Ui.label(goal.text, { TextSize = 12, TextWrapped = true, Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Ui.label(string.format("%d / %d   +%d", goal.progress, goal.target, goal.clout), { Font = Ui.Fonts.Bold, TextSize = 11, TextColor3 = C.Gold, Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 12), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	end
end

function HudController.renderProfile(profile)
	if not profile then
		return
	end
	wallet.rank.Text = string.format("%s  Lv %d", profile.rank or "Freshman", profile.level or 1)
	if profile.rankColor then
		wallet.rank.TextColor3 = Ui.rgb(profile.rankColor)
	end
	wallet.xp.Size = UDim2.fromScale(math.clamp((profile.xp or 0) / math.max(1, profile.xpNext or 1), 0, 1), 1)
	renderGoals(profile)
	refreshDetention()
end

local function updateMeter(value, mark)
	local color = if mark == "!" then C.Danger elseif mark == "?" then C.Warn else C.Good
	meter.fill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
	meter.fill.BackgroundColor3 = color
	meter.title.Text = if mark == "!" then "SHE SEES YOU!" elseif mark == "?" then "SHE'S SUSPICIOUS..." else "SHE'S NOT LOOKING"
	meter.title.TextColor3 = color
	meter.mark.Text = mark
	meter.mark.TextColor3 = color
	for _, edge in ipairs(edges) do
		edge.BackgroundTransparency = 1 - math.clamp((value - 0.25) * 0.9, 0, 0.6)
	end
end

function HudController.step()
	local now = Clock.now()
	local state = ClientState.roundState
	local inClass = state == "Class"
	top.frame.Visible = inClass
	hall.frame.Visible = state == "Hallway" or state == "Bell" or state == "Results"
	if hall.frame.Visible then
		local left = math.max(0, (workspace:GetAttribute("PA_StateEnds") or now) - now)
		hall.title.Text = if state == "Bell" then "BELL! FIND YOUR SEAT" elseif state == "Results" then "CLASS DISMISSED!" else "NEXT CLASS IN " .. Format.clock(left)
		local index = math.floor(now / 6) % #TIPS + 1
		hall.tip.Text = TIPS[index]
	end
	if inClass then
		top.clock.Text = workspace:GetAttribute("PA_Clock") or "10:05"
		local ends = workspace:GetAttribute("PA_StateEnds") or now
		top.left.Text = Format.clock(ends - now) .. " left"
		local phase = ClientState.phase
		if phase then
			top.phase.Text = string.format("%s - %s", phase.label, phase.risk)
			top.phase.BackgroundColor3 = Ui.rgb(phase.color)
			top.bar.BackgroundColor3 = Ui.rgb(phase.color)
			local phaseEnds = phase.endsAt or now
			top.bar.Size = UDim2.fromScale(math.clamp((phaseEnds - now) / phaseLength, 0, 1), 1)
		end
		local event = workspace:GetAttribute("PA_Event")
		local principal = workspace:GetAttribute("PA_Principal")
		top.event.Visible = (event == "Substitute") or principal == true
		top.event.Text = if principal then "PRINCIPAL WATCHING x2" else "SUBSTITUTE (chill)"
		top.event.BackgroundColor3 = if principal then C.Danger else C.Accent2
		top.pizza.Visible = workspace:GetAttribute("PA_Pizza") == true
	end
	meter.frame.Visible = inClass and ClientState.status() == "Seated"
	if not meter.frame.Visible then
		for _, edge in ipairs(edges) do
			edge.BackgroundTransparency = 1
		end
	end
	if quiz.frame.Visible and quiz.data then
		quiz.timer.Text = string.format("%ds", math.max(0, math.ceil((quiz.data.endsAt or now) - now)))
		quiz.warning.Visible = player:GetAttribute("PA_PhoneUp") == true
	end
	-- Smooth Clout counter
	local profile = ClientState.profile
	local target = profile and profile.clout or 0
	shownCloutValue += (target - shownCloutValue) * 0.15
	if math.abs(target - shownCloutValue) < 1 then
		shownCloutValue = target
	end
	wallet.clout.Text = Format.number(shownCloutValue)
	wallet.pending.Text = if inClass and ClientState.pending > 0 then string.format("+%s this class (banked at the bell)", Format.number(ClientState.pending)) else ""
end

function HudController.init()
	gui = Ui.screen("PA_HUD", player:WaitForChild("PlayerGui"), 2)
	buildTop()
	buildWallet()
	buildMeter()
	buildChat()
	buildToasts()
	buildQuiz()
	buildDetention()
	buildActions()

	ClientState.ProfileChanged:Connect(HudController.renderProfile)
	ClientState.SuspicionChanged:Connect(updateMeter)
	ClientState.Chat:Connect(HudController.addChat)
	ClientState.Notified:Connect(HudController.toast)
	ClientState.Announced:Connect(HudController.banner)
	ClientState.QuizChanged:Connect(HudController.showQuiz)
	ClientState.QuizResult:Connect(function(data)
		if data.correct then
			HudController.toast(string.format("Correct! +%d Clout", math.floor(data.reward)), "good")
		elseif data.distracted then
			HudController.toast("Wrong! You were on your phone. (Answer: " .. tostring(data.answer) .. ")", "bad")
		else
			HudController.toast("Wrong! The answer was " .. tostring(data.answer), "warn")
		end
	end)
	ClientState.Results:Connect(HudController.showResults)
	ClientState.PhaseChanged:Connect(function(data)
		if data and data.endsAt then
			phaseLength = math.max(1, data.endsAt - Clock.now())
		end
		if data and data.label then
			HudController.toast(string.format("%s - %s", data.label, data.risk), if data.risk == "SAFE" then "good" elseif data.risk == "RISKY" then "warn" else "bad")
		end
	end)
	ClientState.RoundChanged:Connect(function()
		refreshActions()
		refreshDetention()
		if ClientState.roundState ~= "Class" then
			HudController.showQuiz(nil)
		end
	end)
	player:GetAttributeChangedSignal("PA_Status"):Connect(function()
		refreshActions()
		refreshDetention()
	end)
	player:GetAttributeChangedSignal("PA_Pet"):Connect(refreshActions)
	RunService.RenderStepped:Connect(HudController.step)
	refreshActions()
	refreshDetention()
	updateMeter(0, "")
end

HudController._openChart = openChart
HudController._closeChart = closeChart

return HudController
