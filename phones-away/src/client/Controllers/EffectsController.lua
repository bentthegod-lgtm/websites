--[[
	EffectsController - juicy feedback: "CONFISCATED!" stamp + camera shake, selfie flash,
	Clout popups, level-ups, goals, pizza party confetti, fire drill alarm lights, paper
	airplanes flying across the room, notes, bells and door sounds.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)
local Props = require(Shared.Props)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local EffectsController = {}

local player = Players.LocalPlayer
local C = Ui.Colors
local gui, flashFrame, alarmFrame
local shakeUntil, shakePower = 0, 0
local alarmSound
local camera

local function deskPosition(index)
	local school = workspace:FindFirstChild("School")
	local room = school and school:FindFirstChild("Classroom")
	local desks = room and room:FindFirstChild("Desks")
	local desk = desks and desks:FindFirstChild("Desk" .. tostring(index))
	local top = desk and desk:FindFirstChild("Top")
	return top and top.Position or nil
end

local function stamp(text, color, size)
	local label = Ui.label(text, {
		Font = Ui.Fonts.Title,
		TextSize = size or 80,
		TextColor3 = color,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(900, 120),
		Rotation = -8,
		ZIndex = 60,
		Parent = gui,
	})
	local scale = Ui.new("UIScale", { Scale = 2.4, Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.6, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(0.6, function()
			label:Destroy()
		end)
	end)
	return label
end

local function shake(power, seconds)
	shakePower = math.max(shakePower, power)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

local function flash(color, from)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = from or 0.1
	TweenService:Create(flashFrame, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
end

local function confetti(count)
	for _ = 1, count do
		local piece = Ui.new("Frame", {
			Position = UDim2.new(math.random(), 0, -0.05, 0),
			Size = UDim2.fromOffset(math.random(8, 16), math.random(10, 20)),
			BackgroundColor3 = Color3.fromHSV(math.random(), 0.7, 1),
			Rotation = math.random(0, 360),
			ZIndex = 55,
			Parent = gui,
		})
		local fall = TweenInfo.new(1.6 + math.random() * 1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(piece, fall, { Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.05, 0), Rotation = piece.Rotation + math.random(-360, 360) }):Play()
		task.delay(3.2, function()
			piece:Destroy()
		end)
	end
end

local function pizzaRain()
	for i = 1, 14 do
		local slice = Ui.label("PIZZA", {
			Font = Ui.Fonts.Title,
			TextSize = 22,
			TextColor3 = Color3.fromRGB(255, 170, 60),
			TextStrokeTransparency = 0.2,
			Position = UDim2.new(i / 15, 0, -0.08, 0),
			Size = UDim2.fromOffset(90, 30),
			Rotation = math.random(-30, 30),
			ZIndex = 56,
			Parent = gui,
		})
		TweenService:Create(slice, TweenInfo.new(2 + math.random(), Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Position = UDim2.new(i / 15, 0, 1.1, 0), Rotation = slice.Rotation + 180 }):Play()
		task.delay(3.4, function()
			slice:Destroy()
		end)
	end
end

local function flyPlane(fromIndex, toIndex)
	local a, b = deskPosition(fromIndex), deskPosition(toIndex)
	if not a or not b then
		return
	end
	local school = workspace:FindFirstChild("School")
	local plane = Props.plane(CFrame.lookAt(a + Vector3.new(0, 2, 0), b + Vector3.new(0, 2, 0)))
	plane.Parent = school or workspace
	local steps = 16
	for i = 1, steps do
		task.delay(i * 0.05, function()
			if not plane.Parent then
				return
			end
			local t = i / steps
			local pos = a:Lerp(b, t) + Vector3.new(0, 2 + math.sin(t * math.pi) * 4, 0)
			local nextPos = a:Lerp(b, math.min(1, t + 0.05)) + Vector3.new(0, 2 + math.sin(math.min(1, t + 0.05) * math.pi) * 4, 0)
			if (nextPos - pos).Magnitude > 0.01 then
				plane:PivotTo(CFrame.lookAt(pos, nextPos))
			end
		end)
	end
	task.delay(3, function()
		plane:Destroy()
	end)
end

function EffectsController.handle(kind, data)
	data = data or {}
	local me = data.userId == player.UserId
	if kind == "Clout" then
		AudioUtil.play(AudioAssets.CloutGain)
		stamp("+" .. Format.number(data.amount or 0) .. " CLOUT", C.Gold, if data.big then 64 else 40)
		confetti(if data.big then 40 else 10)
	elseif kind == "Purchase" then
		AudioUtil.play(AudioAssets.Purchase)
	elseif kind == "Upgrade" then
		AudioUtil.play(AudioAssets.Purchase)
		stamp("UPGRADED!", C.Accent2, 54)
	elseif kind == "LevelUp" then
		AudioUtil.play(AudioAssets.LevelUp)
		stamp(string.format("LEVEL %d - %s", data.level or 0, string.upper(data.rank or "")), if data.color then Ui.rgb(data.color) else C.Gold, 56)
		confetti(50)
	elseif kind == "Goal" then
		AudioUtil.play(AudioAssets.CloutGain)
		ClientState.Notified:Fire(string.format("Goal complete: %s  +%d Clout", data.text or "", data.clout or 0), "good")
		confetti(20)
	elseif kind == "Daily" then
		stamp(string.format("DAY %d STREAK! +%d", data.streak or 1, data.clout or 0), C.Good, 50)
		confetti(30)
	elseif kind == "SelfFlash" then
		flash(Color3.new(1, 1, 1), 0)
		AudioUtil.play(AudioAssets.SelfieShutter)
	elseif kind == "Flash" then
		if not me then
			flash(Color3.new(1, 1, 1), 0.75)
		end
	elseif kind == "Caught" then
		AudioUtil.play(AudioAssets.Caught)
		if me then
			stamp("CONFISCATED!", C.Danger, 96)
			flash(Color3.fromRGB(255, 40, 40), 0.2)
			shake(1.2, 0.6)
			ClientState.Notified:Fire(string.format("Caught! -%s Clout and off to detention.", Format.number(data.lost or 0)), "bad")
		else
			ClientState.Notified:Fire(string.format("%s got CAUGHT! Phones down...", data.name or "Someone"), "warn")
			shake(0.3, 0.3)
		end
	elseif kind == "Forgiven" then
		if me then
			stamp("HALL PASS!", C.Accent2, 80)
		end
	elseif kind == "Released" then
		if me then
			stamp("FREEDOM!", C.Good, 80)
		end
	elseif kind == "Pizza" then
		AudioUtil.play(AudioAssets.PizzaFanfare)
		stamp("PIZZA PARTY!", Color3.fromRGB(255, 160, 60), 84)
		pizzaRain()
		confetti(60)
	elseif kind == "FireDrill" then
		alarmFrame.Visible = true
		if not alarmSound then
			alarmSound = AudioUtil.make(AudioAssets.FireAlarm)
			if alarmSound then
				alarmSound:Play()
			end
		end
		stamp("FIRE DRILL!", Color3.fromRGB(255, 120, 40), 80)
	elseif kind == "FireDrillEnd" then
		alarmFrame.Visible = false
		if alarmSound then
			alarmSound:Destroy()
			alarmSound = nil
		end
	elseif kind == "Bell" then
		AudioUtil.play(AudioAssets.SchoolBell)
		if data.early then
			stamp("RIIIING?!", C.Accent2, 64)
		elseif data.final then
			stamp("BELL!", C.Gold, 80)
		end
	elseif kind == "Plane" then
		flyPlane(data.from, data.to)
	elseif kind == "PlaneLand" then
		local pos = deskPosition(data.desk)
		if pos then
			local s = AudioUtil.make(AudioAssets.PlaneLand)
			if s then
				s:Play()
				task.delay(3, function()
					s:Destroy()
				end)
			end
		end
	elseif kind == "Note" then
		AudioUtil.play(AudioAssets.PhoneTap)
	elseif kind == "Principal" then
		if data.on then
			stamp("PRINCIPAL!", C.Danger, 80)
			shake(0.5, 0.4)
		end
	elseif kind == "Door" then
		AudioUtil.play(AudioAssets.DoorOpen)
	end
end

function EffectsController.init()
	camera = workspace.CurrentCamera
	gui = Ui.screen("PA_FX", player:WaitForChild("PlayerGui"), 8, true)
	flashFrame = Ui.new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 50, Parent = gui })
	alarmFrame = Ui.new("Frame", { Name = "Alarm", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 40, 20), BackgroundTransparency = 0.85, Visible = false, ZIndex = 2, Parent = gui })
	ClientState.Effect:Connect(EffectsController.handle)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if alarmFrame.Visible then
			alarmFrame.BackgroundTransparency = 0.78 + math.abs(math.sin(now * 5)) * 0.18
		end
		if camera and now < shakeUntil then
			local p = shakePower * (shakeUntil - now)
			camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * p * 4), math.rad((math.random() - 0.5) * p * 4), 0)
		else
			shakePower = 0
		end
	end)
	ClientState.RoundChanged:Connect(function(state)
		if state ~= "Class" then
			EffectsController.handle("FireDrillEnd", {})
		end
	end)
end

return EffectsController
