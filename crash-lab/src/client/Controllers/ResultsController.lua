--[[
	ResultsController - the post-run results card.

	Shows the server's breakdown (distance, height, impacts by tier, bonuses, featured
	objective, total score, coins), personal-record badges and the next recommended
	upgrade, with a short tally animation. It never blocks play: RETRY launches again
	with the same settings, CONFIGURE closes it, and it closes itself after a few seconds
	if you start configuring or launching.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local CourseConfig = require(Shared.Config.CourseConfig)
local Format = require(Shared.Format)

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

local function row(text, value, color, order)
	local r = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = order, Parent = body })
	Ui.label(text, { Size = UDim2.new(0.72, 0, 1, 0), TextSize = 14, TextColor3 = color or C.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = r })
	Ui.label(value, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.28, 0, 1, 0), TextSize = 14, Font = Ui.Fonts.Bold, TextColor3 = color or C.Text, TextXAlignment = Enum.TextXAlignment.Right, Parent = r })
end

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
	local order = 0
	local function add(text, value, color)
		order += 1
		row(text, value, color, order)
	end
	refs.title.Text = if r.voided then "TEST VOIDED" elseif r.records and r.records.BestScore then "NEW PERSONAL BEST!" else "TEST RESULTS"
	refs.title.TextColor3 = if r.voided then C.Red elseif r.records and r.records.BestScore then C.Green else C.Accent
	if r.voided then
		add("The run's data didn't add up, so it wasn't scored.", "", C.Red)
	end
	add(string.format("Distance  %s studs%s", Format.stat(r.distance), if r.records and r.records.BestDistance then "  (RECORD)" else ""), "+" .. r.distancePoints, if r.records and r.records.BestDistance then C.Green else nil)
	add(string.format("Max height  %s studs%s", Format.stat(r.height), if r.records and r.records.BestHeight then "  (RECORD)" else ""), "+" .. r.heightPoints, if r.records and r.records.BestHeight then C.Green else nil)
	local tiers = {}
	for _, name in ipairs({ "Massive", "Heavy", "Medium", "Light" }) do
		if r.impactTiers and r.impactTiers[name] then
			table.insert(tiers, r.impactTiers[name] .. " " .. string.lower(name))
		end
	end
	add(string.format("Impacts  %d%s", r.impacts, if #tiers > 0 then "  (" .. table.concat(tiers, ", ") .. ")" else ""), "+" .. r.impactPoints)
	for _, b in ipairs(r.bonuses or {}) do
		if b.points > 0 then
			local namer = BONUS_NAMES[b.kind]
			add(if namer then namer(b.id) else b.kind, "+" .. b.points, C.Blue)
		end
	end
	if r.featuredPoints and r.featuredPoints > 0 then
		add("FEATURED OBJECTIVE BONUS", "+" .. r.featuredPoints, C.Accent)
	elseif r.featuredId then
		local o = CourseConfig.ObjectiveById[r.featuredId]
		add("Featured objective missed: " .. (o and o.Name or r.featuredId), "", C.Dim)
	end
	refs.score.Text = "0"
	refs.coins.Text = "+0 coins"
	refs.recommend.Text = if r.recommend then string.format("Next upgrade: %s  (%s coins)%s", r.recommend.name, Format.short(r.recommend.price), if r.recommend.affordable then "  -  you can afford it!" else "") else ""
	card.Visible = true
	shownAt = os.clock()
	local scale = card:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = card })
	scale.Scale = 0.9
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	-- Tally animation (short: ~1 second).
	task.spawn(function()
		local steps = 16
		for i = 1, steps do
			if ResultsController.last ~= r then
				return
			end
			refs.score.Text = Format.exact(math.floor(r.score * i / steps))
			refs.coins.Text = "+" .. Format.exact(math.floor(r.coins * i / steps)) .. " coins"
			AudioController.play("ResultsTally")
			task.wait(0.05)
		end
		AudioController.play("Coins", nil, true)
		if r.records and next(r.records) then
			AudioController.play("NewRecord", nil, true)
		end
		if r.featuredDone then
			AudioController.play("ObjectiveDone", nil, true)
		end
	end)
end

function ResultsController.build()
	gui = Ui.screen("CrashResults", 6)
	card = Ui.panel({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.45, 0), Size = UDim2.fromOffset(400, 470), Visible = false, Parent = gui }, 14)
	Ui.padding(card, 16, 12)
	refs.title = Ui.title("TEST RESULTS", { Size = UDim2.new(1, 0, 0, 30), TextSize = 24, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	body = Ui.scroll(card, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 230) })
	Ui.list(body, 2)
	Ui.label("TOTAL SCORE", { Position = UDim2.fromOffset(0, 272), Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	refs.score = Ui.title("0", { Position = UDim2.fromOffset(0, 288), Size = UDim2.new(1, 0, 0, 44), TextSize = 42, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	refs.coins = Ui.title("+0 coins", { Position = UDim2.fromOffset(0, 332), Size = UDim2.new(1, 0, 0, 26), TextSize = 22, TextColor3 = C.Green, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	refs.recommend = Ui.label("", { Position = UDim2.fromOffset(0, 360), Size = UDim2.new(1, 0, 0, 30), TextSize = 13, TextWrapped = true, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	local retry = Ui.button("RETRY  (F)", { Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(0.5, -6, 0, 44), TextSize = 17 }, C.Accent)
	retry.Parent = card
	local configure = Ui.button("CONFIGURE", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 1, -44), Size = UDim2.new(0.5, -6, 0, 44), TextSize = 17 }, C.PanelLighter)
	configure.Parent = card
	retry.Activated:Connect(function()
		ResultsController.close()
		require(script.Parent.LaunchController).launch()
	end)
	configure.Activated:Connect(ResultsController.close)
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
