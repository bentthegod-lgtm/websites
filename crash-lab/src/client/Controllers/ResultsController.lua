--[[
	ResultsController - the post-run results card.

	Shows the server's breakdown (distance, height, impacts by tier, bonuses, featured
	objective, total score, coins), personal-record badges, a grade stamp (S-D vs your
	personal best, Grades), the change vs your last run and the next recommended upgrade.
	Every line counts up in turn, then the total, then the stamp lands. It never blocks
	play: RETRY (R) launches again with the same settings, BACK TO SETUP closes it, and
	charging a new launch closes it. On short screens it switches to a compact card at
	the top-centre, clear of the touch thumbstick and Jump button.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local CourseConfig = require(Shared.Config.CourseConfig)
local Format = require(Shared.Format)
local Grades = require(Shared.Grades)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local ResultsController = {}

local C = Ui.Colors
local gui, card, body
local refs = {}
local shownAt = 0
ResultsController.last = nil

local BONUS_NAMES = {
	Target = function(id)
		local t = CourseConfig.TargetById[id]
		return "Target: " .. (t and t.Name or id)
	end,
	Prop = function(id)
		local kind = string.match(tostring(id), "^(%a+)")
		local def = kind and CourseConfig.DestructibleKinds[kind]
		return "Smashed: " .. (def and def.Name or "prop")
	end,
	Ring = function(id)
		local r = CourseConfig.RingById[id]
		return "Ring: " .. (r and r.Name or id)
	end,
	Zone = function(id)
		local z = CourseConfig.ZoneById[id]
		return "Landed: " .. (z and z.Name or id)
	end,
	Objective = function(id)
		local o = CourseConfig.ObjectiveById[id]
		return "Objective: " .. (o and o.Name or id)
	end,
}

-- A breakdown row. The value counts up when the row's turn comes (see show()).
local function row(text, value, color, order)
	local r = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = order, Parent = body })
	Ui.label(text, { Size = UDim2.new(0.72, 0, 1, 0), TextSize = 14, TextColor3 = color or C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = r })
	local label = Ui.label(if value then "+0" else "", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.28, 0, 1, 0), TextSize = 14, Font = Ui.Fonts.Bold, TextColor3 = color or C.Text, TextXAlignment = Enum.TextXAlignment.Right, Parent = r })
	return { label = label, value = value }
end

-- Card layout. Short screens (phones in landscape: viewport under 500 px tall) get a
-- compact 380x300 card pinned to the TOP-centre, clear of the touch thumbstick and the
-- Jump button at the bottom corners. Exposed for tests.
ResultsController.CompactHeight = 500
function ResultsController.layout(viewport)
	local compact = viewport.Y < ResultsController.CompactHeight
	if compact then
		-- Top-centre and short: clear of the mobile thumbstick (bottom-left) and the Jump button (bottom-right).
		return { compact = true, anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 8), size = Vector2.new(380, 300), body = 104 }
	end
	return { compact = false, anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -24, 0.45, 0), size = Vector2.new(400, 480), body = 220 }
end

local function applyLayout()
	local l = ResultsController.layout(Ui.viewportSize())
	card.AnchorPoint = l.anchor
	card.Position = l.position
	card.Size = UDim2.fromOffset(l.size.X, l.size.Y)
	body.Size = UDim2.new(1, -86, 0, l.body)
	local y = 36 + l.body + 6
	refs.scoreCaption.Position = UDim2.fromOffset(0, y)
	refs.score.Position = UDim2.fromOffset(0, y + 14)
	refs.coins.Position = UDim2.fromOffset(0, y + 54)
	refs.delta.Position = UDim2.fromOffset(170, y + 58)
	refs.recommend.Position = UDim2.fromOffset(0, y + 80)
	refs.recommend.Visible = not l.compact
	return l
end
ResultsController.applyLayout = applyLayout

function ResultsController.close()
	if card then
		card.Visible = false
	end
end

function ResultsController.isOpen()
	return card ~= nil and card.Visible
end

-- Builds the breakdown rows (exposed for tests).
function ResultsController.show(r)
	ResultsController.last = r
	Ui.clear(body)
	applyLayout()
	local rows = {}
	local order = 0
	local function add(text, value, color)
		order += 1
		table.insert(rows, row(text, value, color, order))
	end
	refs.title.Text = if r.voided then "TEST VOIDED" elseif r.records and r.records.BestScore then "NEW PERSONAL BEST!" else "TEST RESULTS"
	refs.title.TextColor3 = if r.voided then C.Red elseif r.records and r.records.BestScore then C.Green else C.Accent
	if r.voided then
		add("The run's data didn't add up, so it wasn't scored.", nil, C.Red)
	end
	add(string.format("Distance  %s studs%s", Format.stat(r.distance), if r.records and r.records.BestDistance then "  (RECORD)" else ""), r.distancePoints, if r.records and r.records.BestDistance then C.Green else nil)
	add(string.format("Max height  %s studs%s", Format.stat(r.height), if r.records and r.records.BestHeight then "  (RECORD)" else ""), r.heightPoints, if r.records and r.records.BestHeight then C.Green else nil)
	local tiers = {}
	for _, name in ipairs({ "Massive", "Heavy", "Medium", "Light" }) do
		if r.impactTiers and r.impactTiers[name] then
			table.insert(tiers, r.impactTiers[name] .. " " .. string.lower(name))
		end
	end
	add(string.format("Impacts  %d%s", r.impacts, if #tiers > 0 then "  (" .. table.concat(tiers, ", ") .. ")" else ""), r.impactPoints)
	for _, b in ipairs(r.bonuses or {}) do
		if b.points > 0 then
			local namer = BONUS_NAMES[b.kind]
			add(if namer then namer(b.id) else b.kind, b.points, C.Blue)
		end
	end
	if r.featuredPoints and r.featuredPoints > 0 then
		add("FEATURED OBJECTIVE BONUS", r.featuredPoints, C.Accent)
	elseif r.featuredId then
		local o = CourseConfig.ObjectiveById[r.featuredId]
		add("Featured objective missed: " .. (o and o.Name or r.featuredId), nil, C.Dim)
	end
	refs.score.Text = "0"
	refs.coins.Text = "+0 coins"
	refs.delta.Text = Grades.deltaText(r.delta)
	refs.delta.TextColor3 = if r.delta == nil then C.Dim elseif r.delta >= 0 then C.Green else C.Red
	local grade = r.grade or Grades.grade(r.score, r.previousBest)
	refs.stamp.Text = grade
	refs.stamp.TextColor3 = Ui.rgb(Grades.Colors[grade] or Grades.Colors.C)
	refs.stampFrame.Visible = false
	refs.recommend.Text = if r.recommend then string.format("Next upgrade: %s  (%s coins)%s", r.recommend.name, Format.short(r.recommend.price), if r.recommend.affordable then "  -  you can afford it!" else "") else ""
	card.Visible = true
	shownAt = os.clock()
	local scale = card:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = card })
	scale.Scale = 0.9
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	-- Count-up: each line in turn (~0.2 s each, capped at ~1.6 s overall), then the total,
	-- coins and the grade stamp.
	local reducedFx = ClientState.setting("ReducedEffects") == true
	task.spawn(function()
		local per = math.clamp(1.4 / math.max(1, #rows), 0.08, 0.2)
		for _, line in ipairs(rows) do
			if line.value then
				local steps = 5
				for i = 1, steps do
					if ResultsController.last ~= r then
						return
					end
					line.label.Text = "+" .. Format.exact(math.floor(line.value * i / steps))
					task.wait(per / steps)
				end
				AudioController.play("ResultsTally")
			end
		end
		local steps = 12
		for i = 1, steps do
			if ResultsController.last ~= r then
				return
			end
			refs.score.Text = Format.exact(math.floor(r.score * i / steps))
			refs.coins.Text = "+" .. Format.exact(math.floor(r.coins * i / steps)) .. " coins"
			task.wait(0.03)
		end
		AudioController.play("Coins", nil, true)
		refs.stampFrame.Visible = true
		local stampScale = refs.stampFrame:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = refs.stampFrame })
		stampScale.Scale = if reducedFx then 1 else 2.2
		TweenService:Create(stampScale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		if r.records and next(r.records) then
			AudioController.play("NewRecord", nil, true)
		end
		if r.featuredDone then
			AudioController.play("ObjectiveDone", nil, true)
		end
	end)
end

function ResultsController.retry()
	if not ResultsController.isOpen() then
		return false
	end
	ResultsController.close()
	require(script.Parent.LaunchController).launch()
	return true
end

function ResultsController.build()
	gui = Ui.screen("CrashResults", 6)
	card = Ui.panel({ Visible = false, Parent = gui }, 14)
	Ui.padding(card, 16, 12)
	refs.title = Ui.title("TEST RESULTS", { Size = UDim2.new(1, -90, 0, 30), TextSize = 24, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	body = Ui.scroll(card, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, -86, 0, 220) })
	Ui.list(body, 2)
	-- Grade stamp (top-right, rotated like a rubber stamp).
	refs.stampFrame = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 30), Size = UDim2.fromOffset(78, 78), BackgroundTransparency = 1, Rotation = -12, Visible = false, Parent = card })
	Ui.stroke(refs.stampFrame, C.Accent, 3, 0)
	Ui.corner(refs.stampFrame, 10)
	refs.stamp = Ui.title("S", { Size = UDim2.fromScale(1, 1), TextSize = 58, Parent = refs.stampFrame })
	Ui.label("GRADE", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(78, 12), TextSize = 10, TextColor3 = C.Dim, Parent = refs.stampFrame })
	refs.scoreCaption = Ui.label("TOTAL SCORE", { Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	refs.score = Ui.title("0", { Size = UDim2.new(1, 0, 0, 40), TextSize = 40, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	refs.coins = Ui.title("+0 coins", { Size = UDim2.new(0, 170, 0, 24), TextSize = 20, TextColor3 = C.Green, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	refs.delta = Ui.label("", { Size = UDim2.new(1, -170, 0, 18), TextSize = 13, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	refs.recommend = Ui.label("", { Size = UDim2.new(1, 0, 0, 30), TextSize = 13, TextWrapped = true, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	local retry = Ui.button("RETRY  (R)", { Position = UDim2.new(0, 0, 1, -42), Size = UDim2.new(0.5, -6, 0, 42), TextSize = 17 }, C.Accent)
	retry.Parent = card
	local back = Ui.button("BACK TO SETUP", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 1, -42), Size = UDim2.new(0.5, -6, 0, 42), TextSize = 15 }, C.PanelLighter)
	back.Parent = card
	retry.Activated:Connect(ResultsController.retry)
	back.Activated:Connect(ResultsController.close)
	applyLayout()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
end

function ResultsController.init()
	ResultsController.build()
	ClientState.Results:Connect(ResultsController.show)
	-- Launching again closes the card.
	ClientState.MachineFx:Connect(function(padIndex, _machineId, phase)
		local pad = ClientState.myPad()
		if phase == "Charge" and pad and pad.index == padIndex and os.clock() - shownAt > 0.3 then
			ResultsController.close()
		end
	end)
end

return ResultsController
