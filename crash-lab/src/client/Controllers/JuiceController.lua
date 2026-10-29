--[[
	JuiceController - moment-to-moment feedback during YOUR run. All client-side and
	purely visual; the numbers that pay out always come from the server's results.

	* Live readout: distance and height (current + peak) while your dummy flies.
	* Combo counter: impacts within ComboWindow of each other chain into "x3 COMBO!" with
	  a pop in the tier's colour.
	* Floating score popups at the impact point (tier base points; at most MaxPopups).
	* Speed lines at the screen edges above SpeedLineMin studs/s (capped count).
	* NEW RECORD banner + falling confetti when the results contain a record.
	Reduced effects turns off the speed lines and confetti and calms the popups.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local ScoringConfig = require(Shared.Config.ScoringConfig)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local JuiceController = {}

local C = Ui.Colors
local player = Players.LocalPlayer
JuiceController.ComboWindow = 1.2
JuiceController.SpeedLineMin = 120
JuiceController.MaxSpeedLines = 12
JuiceController.MaxPopups = 10

JuiceController.TierColor = {
	Light = Color3.fromRGB(230, 230, 230),
	Medium = Color3.fromRGB(110, 190, 255),
	Heavy = Color3.fromRGB(255, 190, 50),
	Massive = Color3.fromRGB(255, 80, 60),
}
local TIER_POINTS = {}
for _, tier in ipairs(ScoringConfig.Impact.Tiers) do
	TIER_POINTS[tier.Name] = tier.Points
end

local gui, live, liveDistance, liveHeight, comboLabel, banner
local speedLines = {}
local popups = 0
local combo = { count = 0, last = -math.huge }
local peak = 0
local lastRootPos, lastRootT = nil, nil

local function reduced()
	return ClientState.setting("ReducedEffects") == true
end

-- Pure: advances a combo state for a hit at time t. Returns the new count.
function JuiceController.comboStep(state, t, window)
	if t - state.last <= (window or JuiceController.ComboWindow) then
		state.count += 1
	else
		state.count = 1
	end
	state.last = t
	return state.count
end

-- Pure: how many speed lines to show at a given speed (0 below the threshold, capped).
function JuiceController.speedLineCount(speed)
	if type(speed) ~= "number" or speed ~= speed or speed < JuiceController.SpeedLineMin then
		return 0
	end
	return math.min(JuiceController.MaxSpeedLines, math.floor((speed - JuiceController.SpeedLineMin) / 15) + 1)
end

function JuiceController.showCombo(count, tier)
	if count < 2 or not comboLabel then
		return
	end
	comboLabel.Text = string.format("x%d COMBO!", count)
	comboLabel.TextColor3 = JuiceController.TierColor[tier] or C.Accent
	comboLabel.Visible = true
	local scale = comboLabel:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = comboLabel })
	scale.Scale = if reduced() then 1 else 1.45
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local stamp = combo.last
	task.delay(JuiceController.ComboWindow + 0.3, function()
		if combo.last == stamp then
			comboLabel.Visible = false
		end
	end)
end

-- A "+16" that floats up from the impact point and fades.
function JuiceController.popup(position, text, color)
	if not position or popups >= JuiceController.MaxPopups then
		return false
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return false
	end
	popups += 1
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = terrain
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(180, 50)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local label = Ui.title(text, { Size = UDim2.fromScale(1, 1), TextSize = 30, TextColor3 = color or C.Accent, TextStrokeTransparency = 0.2, Parent = billboard })
	TweenService:Create(billboard, TweenInfo.new(1, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, if reduced() then 3 else 7, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.05, function()
		anchor:Destroy()
		popups -= 1
	end)
	return true
end

local function myRunRoot()
	local run = ClientState.myRun
	return run and run.model and run.model:FindFirstChild("Root")
end

function JuiceController.step(dt)
	local root = myRunRoot()
	live.Visible = root ~= nil
	if not root then
		peak = 0
		lastRootPos = nil
		for _, line in ipairs(speedLines) do
			line.Visible = false
		end
		return
	end
	local pos = root.Position
	peak = math.max(peak, pos.Y)
	liveDistance.Text = Format.exact(math.max(0, math.floor(pos.Z)))
	liveHeight.Text = string.format("%d  (peak %d)", math.max(0, math.floor(pos.Y)), math.floor(peak))
	local now = os.clock()
	local speed = 0
	if lastRootPos and lastRootT and now > lastRootT then
		speed = (pos - lastRootPos).Magnitude / (now - lastRootT)
	end
	lastRootPos, lastRootT = pos, now
	local count = if reduced() then 0 else JuiceController.speedLineCount(speed)
	for i, line in ipairs(speedLines) do
		line.Visible = i <= count
		if line.Visible then
			-- Streaks race from the centre toward the screen edge.
			local p = line:GetAttribute("P") or math.random()
			p = (p + dt * (2 + speed / 120)) % 1
			line:SetAttribute("P", p)
			local angle = line:GetAttribute("A")
			local r = 0.25 + p * 0.45
			line.Position = UDim2.fromScale(0.5 + math.cos(angle) * r * 0.9, 0.5 + math.sin(angle) * r)
			line.Rotation = math.deg(angle)
			line.BackgroundTransparency = 0.35 + p * 0.6
		end
	end
end

function JuiceController.celebrate(result)
	local records = result.records or {}
	if not next(records) then
		return false
	end
	local which = if records.BestScore then "SCORE" elseif records.BestDistance then "DISTANCE" elseif records.BestHeight then "HEIGHT" else "IMPACTS"
	banner.Text = "NEW " .. which .. " RECORD!"
	banner.Visible = true
	banner.TextTransparency = 0
	local scale = banner:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = banner })
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(2.4, function()
		TweenService:Create(banner, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.delay(0.55, function()
			banner.Visible = false
		end)
	end)
	if not reduced() then
		local colors = { C.Accent, C.Green, C.Blue, C.Red, C.Purple }
		for i = 1, 28 do
			local piece = Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(math.random(), -0.05),
				Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22)),
				BackgroundColor3 = colors[(i % #colors) + 1],
				Rotation = math.random(0, 360),
				Parent = gui,
			})
			TweenService:Create(piece, TweenInfo.new(1.6 + math.random() * 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 1.1), Rotation = piece.Rotation + math.random(-360, 360) }):Play()
			task.delay(3, function()
				piece:Destroy()
			end)
		end
	end
	return true
end

function JuiceController.build()
	gui = Ui.screen("CrashJuice", 7)
	live = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(420, 64), BackgroundTransparency = 0.25, Visible = false, Parent = gui }, 12)
	Ui.label("DISTANCE", { Position = UDim2.fromOffset(14, 4), Size = UDim2.fromOffset(180, 14), TextSize = 11, TextColor3 = C.Dim, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, Parent = live })
	liveDistance = Ui.title("0", { Position = UDim2.fromOffset(14, 18), Size = UDim2.fromOffset(180, 40), TextSize = 34, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = live })
	Ui.label("HEIGHT", { Position = UDim2.fromOffset(214, 4), Size = UDim2.fromOffset(190, 14), TextSize = 11, TextColor3 = C.Dim, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, Parent = live })
	liveHeight = Ui.title("0", { Position = UDim2.fromOffset(214, 18), Size = UDim2.fromOffset(190, 40), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Parent = live })
	Ui.label("live estimate", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -4), Size = UDim2.fromOffset(100, 12), TextSize = 10, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Right, Parent = live })
	comboLabel = Ui.title("", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.27), Size = UDim2.fromOffset(420, 56), TextSize = 46, TextStrokeTransparency = 0.25, Visible = false, Parent = gui })
	banner = Ui.title("", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromOffset(760, 70), TextSize = 56, TextColor3 = C.Accent, TextStrokeTransparency = 0.1, Visible = false, Parent = gui })
	for i = 1, JuiceController.MaxSpeedLines do
		local line = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(140, 3), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.5, Visible = false, Parent = gui })
		line:SetAttribute("A", (i / JuiceController.MaxSpeedLines) * math.pi * 2 + 0.3)
		table.insert(speedLines, line)
	end
end

function JuiceController.init()
	JuiceController.build()
	ClientState.RunEvent:Connect(function(userId, kind, data)
		if userId ~= player.UserId then
			return
		end
		if kind == "Impact" then
			local n = JuiceController.comboStep(combo, os.clock())
			JuiceController.showCombo(n, data.tier)
			JuiceController.popup(data.position, "+" .. (TIER_POINTS[data.tier] or 0), JuiceController.TierColor[data.tier])
			if n >= 3 then
				AudioController.play("Countdown", nil, true)
			end
		elseif kind == "Target" then
			JuiceController.popup(data.position, "TARGET!", C.Red)
		elseif kind == "Ring" then
			JuiceController.popup(data.position, "RING!", C.Green)
		end
	end)
	ClientState.RunStarted:Connect(function(userId)
		if userId == player.UserId then
			combo.count, combo.last = 0, -math.huge
			peak = 0
		end
	end)
	ClientState.Results:Connect(JuiceController.celebrate)
	RunService.RenderStepped:Connect(JuiceController.step)
end

return JuiceController
