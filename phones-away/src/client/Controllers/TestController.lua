--[[
	TestController - the test paper on screen: version badge, exam timer, a question grid
	(1-10), the current question with 4 answer buttons (A-D), PREV / NEXT.

	Answering is safe: clicks go to the server as Answer(slot, option) and are acknowledged.
	The client never has the answer key; revealed answers live on the phone screen only, so
	you have to memorise them, put the phone away and click them here.

	Keys: 1-4 answer, Left / Right (or D-pad) change question. Hidden while the phone is out.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local Net = require(Shared.Net)
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)
local Format = require(Shared.Format)
local Clock = require(Shared.Clock)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local TestController = {}

local player = Players.LocalPlayer
local C = Ui.Colors
local LETTERS = { "A", "B", "C", "D" }
local SUBJECT_COLORS = {
	Math = { 90, 170, 255 },
	Science = { 110, 220, 140 },
	History = { 230, 170, 90 },
	Geography = { 90, 210, 210 },
	English = { 220, 120, 220 },
}

local gui, frame, badge, timerLabel, countLabel, grid, questionLabel, tagLabel, rippedLabel, peekButton
local optionButtons = {}
local gridButtons = {}
local current = 1
local phoneOut = false

local function test()
	return ClientState.test
end

function TestController.render()
	local t = test()
	local active = t ~= nil and ClientState.roundState == "Class" and ClientState.status() ~= "Hallway"
	frame.Visible = active and not phoneOut
	if not t then
		return
	end
	local questions = t.questions or {}
	current = math.clamp(current, 1, math.max(1, #questions))
	badge.Text = "VERSION " .. tostring(t.version)
	badge.BackgroundColor3 = if t.version == "B" then Color3.fromRGB(255, 120, 160) else Color3.fromRGB(90, 170, 255)
	local answered = 0
	for slot = 1, #questions do
		if t.answers[slot] then
			answered += 1
		end
	end
	countLabel.Text = string.format("%d / %d answered", answered, #questions)
	for slot, b in pairs(gridButtons) do
		b.Visible = slot <= #questions
		b.BackgroundColor3 = if slot == current then C.Accent elseif t.answers[slot] then C.Ink else Color3.fromRGB(200, 200, 210)
		b.TextColor3 = if slot == current or t.answers[slot] then Color3.new(1, 1, 1) else C.Ink
	end
	local q = questions[current]
	rippedLabel.Visible = t.ripped == true
	local profile = ClientState.profile
	local peeks = profile and profile.tokens and profile.tokens.Peek or 0
	peekButton.Visible = peeks > 0 and not t.ripped
	peekButton.Text = string.format("PEEK (%d)", peeks)
	if not q then
		return
	end
	questionLabel.Text = string.format("%d. %s", current, q.text)
	local color = SUBJECT_COLORS[q.subject] or { 200, 200, 200 }
	tagLabel.Text = string.format("%s  %s", string.upper(q.subject), string.rep("*", q.tier or 1))
	tagLabel.BackgroundColor3 = Ui.rgb(color)
	for i, b in ipairs(optionButtons) do
		b.Text = string.format("%s)  %s", LETTERS[i], q.options[i] or "")
		local chosen = t.answers[current] == i
		b.BackgroundColor3 = if chosen then C.Accent2 else Color3.fromRGB(235, 235, 245)
		b.TextColor3 = if chosen then Color3.new(1, 1, 1) else C.Ink
	end
end

function TestController.select(slot)
	local t = test()
	if t and t.questions and t.questions[slot] then
		current = slot
		TestController.render()
	end
end

function TestController.answer(option)
	local t = test()
	if not t or t.ripped or not t.questions[current] then
		return
	end
	AudioUtil.play(AudioAssets.Click)
	-- Optimistic highlight; the server's "ack" confirms it.
	t.answers[current] = option
	Net.event("Answer"):FireServer(current, option)
	TestController.render()
	-- Hop to the next unanswered question.
	for step = 1, #t.questions do
		local slot = ((current - 1 + step) % #t.questions) + 1
		if not t.answers[slot] then
			current = slot
			break
		end
	end
	TestController.render()
end

local function build()
	gui = Ui.screen("PA_Test", player:WaitForChild("PlayerGui"), 3)
	frame = Ui.panel({ Name = "TestPaper", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 272, 1, -20), Size = UDim2.fromOffset(520, 300), BackgroundColor3 = C.Paper, BackgroundTransparency = 0, Visible = false, ZIndex = 5, Parent = gui })
	Ui.stroke(frame, C.Ink, 0.4, 2)
	-- Notebook margin line
	Ui.new("Frame", { Position = UDim2.fromOffset(36, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 140, 140), ZIndex = 6, Parent = frame })
	Ui.label("TEST", { Font = Ui.Fonts.Title, TextSize = 22, TextColor3 = C.Ink, Position = UDim2.fromOffset(46, 6), Size = UDim2.fromOffset(80, 28), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = frame })
	badge = Ui.label("VERSION A", { Font = Ui.Fonts.Title, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, Position = UDim2.fromOffset(112, 9), Size = UDim2.fromOffset(100, 24), ZIndex = 7, Parent = frame })
	Ui.corner(badge, 8)
	timerLabel = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = C.Danger, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(150, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7, Parent = frame })
	countLabel = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 13, TextColor3 = C.Ink, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 26), Size = UDim2.fromOffset(150, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7, Parent = frame })
	grid = Ui.new("Frame", { Position = UDim2.fromOffset(46, 42), Size = UDim2.new(1, -58, 0, 26), BackgroundTransparency = 1, ZIndex = 7, Parent = frame })
	for slot = 1, 12 do
		local b = Ui.button(tostring(slot), { Position = UDim2.fromOffset((slot - 1) * 36, 0), Size = UDim2.fromOffset(32, 26), TextSize = 14, ZIndex = 8, Parent = grid })
		b.Activated:Connect(function()
			TestController.select(slot)
		end)
		gridButtons[slot] = b
	end
	tagLabel = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 12, TextColor3 = Color3.fromRGB(20, 20, 40), BackgroundTransparency = 0, Position = UDim2.fromOffset(46, 74), Size = UDim2.fromOffset(150, 18), ZIndex = 7, Parent = frame })
	Ui.corner(tagLabel, 6)
	questionLabel = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 19, TextColor3 = C.Ink, TextWrapped = true, Position = UDim2.fromOffset(46, 94), Size = UDim2.new(1, -58, 0, 52), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7, Parent = frame })
	for i = 1, 4 do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local b = Ui.button("", { Name = "Option" .. i, Position = UDim2.new(col * 0.5, if col == 0 then 46 else 6, 0, 150 + row * 52), Size = UDim2.new(0.5, -52 + (if col == 0 then 0 else 40), 0, 46), TextSize = 15, ZIndex = 7, Parent = frame }, Color3.fromRGB(235, 235, 245))
		b.TextWrapped = true
		b.TextXAlignment = Enum.TextXAlignment.Left
		Ui.padding(b, 8)
		b.Activated:Connect(function()
			TestController.answer(i)
		end)
		optionButtons[i] = b
	end
	local prev = Ui.button("< PREV", { Position = UDim2.fromOffset(46, 258), Size = UDim2.fromOffset(100, 32), TextSize = 14, ZIndex = 7, Parent = frame }, C.PanelLight)
	prev.Activated:Connect(function()
		TestController.select(current - 1)
	end)
	local nextButton = Ui.button("NEXT >", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 258), Size = UDim2.fromOffset(100, 32), TextSize = 14, ZIndex = 7, Parent = frame }, C.PanelLight)
	nextButton.Activated:Connect(function()
		TestController.select(current + 1)
	end)
	Ui.label("Answering is safe. Using your phone is NOT.", { TextSize = 12, TextColor3 = Color3.fromRGB(110, 110, 140), Position = UDim2.fromOffset(150, 264), Size = UDim2.new(1, -270, 0, 20), ZIndex = 7, Parent = frame })
	peekButton = Ui.button("PEEK", { Name = "Peek", Position = UDim2.fromOffset(222, 9), Size = UDim2.fromOffset(90, 24), TextSize = 13, Visible = false, ZIndex = 8, Parent = frame }, C.Gold:Lerp(Color3.new(0, 0, 0), 0.2))
	peekButton.Activated:Connect(function()
		Net.event("PhoneAction"):FireServer("peek")
	end)
	rippedLabel = Ui.label("TEST RIPPED UP!\nescape detention for a fresh copy", { Font = Ui.Fonts.Title, TextSize = 30, TextColor3 = C.Danger, BackgroundTransparency = 0.15, BackgroundColor3 = C.Paper, Size = UDim2.fromScale(1, 1), Rotation = -4, Visible = false, ZIndex = 12, Parent = frame })
end

function TestController.init()
	build()
	ClientState.TestChanged:Connect(function(kind)
		if kind == "view" then
			current = 1
		end
		TestController.render()
	end)
	ClientState.RoundChanged:Connect(TestController.render)
	ClientState.ProfileChanged:Connect(TestController.render)
	ClientState.LocalPhone:Connect(function(up)
		phoneOut = up
		TestController.render()
	end)
	player:GetAttributeChangedSignal("PA_Status"):Connect(TestController.render)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not frame.Visible then
			return
		end
		local key = input.KeyCode
		local digits = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4 }
		if digits[key] then
			TestController.answer(digits[key])
		elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.DPadRight then
			TestController.select(current + 1)
		elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.DPadLeft then
			TestController.select(current - 1)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if frame.Visible then
			local ends = workspace:GetAttribute("PA_StateEnds") or Clock.now()
			timerLabel.Text = "TIME LEFT " .. Format.clock(ends - Clock.now())
		end
	end)
	TestController.render()
end

return TestController
