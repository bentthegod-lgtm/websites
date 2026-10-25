--[[
	EffectsController - feedback that isn't the magnet itself.

	* Collection popups: your pickups are grouped into one "+value" counter that keeps
	  adding while you pull (max PerformanceConfig.MaxPopupsPerSecond new popups).
	* Toasts (notifications), the announcement banner, achievement / quest / daily /
	  discovery / tier / zone / prestige cards.
	* Rare discovery: a short celebration card + sting, never blocking play.
	* The sell sequence: your pile flies into the shredder hopper in stages, the machine
	  reacts (rollers race, pistons pump, warning lights flash, sparks, smoke), then the
	  coins land. Bigger sales get a bigger (but bounded) show.
	* Shredder idle motion (rollers, belt slats) and the Magnetic Storm sky.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local ScrapConfig = require(Shared.Config.ScrapConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)
local MagnetController = require(script.Parent.MagnetController)

local EffectsController = {}

local C = Ui.Colors
local player = Players.LocalPlayer
local gui, toastList, banner, bannerText, cardHolder
local group = { value = 0, count = 0, label = nil, last = 0 }
local machine = { processingUntil = 0, parts = nil }
local popupBudget = { t = 0, n = 0 }

local function reduced()
	return ClientState.setting("ReducedEffects") == true
end

-- Toasts --------------------------------------------------------------------------------

function EffectsController.toast(text, kind)
	if not toastList or not text or text == "" then
		return
	end
	local color = if kind == "good" then C.Green elseif kind == "error" then C.Red elseif kind == "warn" then C.Accent else C.Text
	local toast = Ui.panel({ Size = UDim2.fromOffset(380, 34), BackgroundTransparency = 0.1, LayoutOrder = -math.floor(os.clock() * 100) }, 8)
	Ui.label(text, { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextSize = 14, TextColor3 = color, TextWrapped = true, Font = Ui.Fonts.Bold, Parent = toast })
	toast.Parent = toastList
	if kind == "error" then
		AudioController.play("Denied", nil, true)
	end
	task.delay(3.2, function()
		toast:Destroy()
	end)
	local children = 0
	for _, child in ipairs(toastList:GetChildren()) do
		if child:IsA("Frame") then
			children += 1
			if children > 4 then
				child:Destroy()
			end
		end
	end
end

function EffectsController.announce(text, color)
	if not banner then
		return
	end
	bannerText.Text = text
	bannerText.TextColor3 = if type(color) == "table" then Ui.rgb(color) else C.Accent
	banner.Visible = true
	banner.BackgroundTransparency = 0.15
	task.delay(4, function()
		if bannerText.Text == text then
			banner.Visible = false
		end
	end)
end

-- Cards (achievement / quest / discovery / tier / zone / prestige) ----------------------

function EffectsController.card(title, body, color, sound)
	if not cardHolder then
		return
	end
	local card = Ui.panel({ Size = UDim2.fromOffset(320, 70), BackgroundTransparency = 0.05 }, 10)
	Ui.new("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = color or C.Accent, Parent = card })
	Ui.title(title, { Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -24, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 17, TextColor3 = color or C.Accent, Parent = card })
	Ui.label(body, { Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -24, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 13, TextWrapped = true, TextColor3 = C.Text, Parent = card })
	card.Parent = cardHolder
	if sound then
		AudioController.play(sound, nil, true)
	end
	task.delay(4.2, function()
		card:Destroy()
	end)
	return card
end

local function onPopup(kind, data)
	data = data or {}
	if kind == "Achievement" then
		EffectsController.card("ACHIEVEMENT: " .. string.upper(data.name or ""), data.text or "", C.Accent, "QuestDone")
	elseif kind == "Quest" then
		EffectsController.card("QUEST COMPLETE", string.format("%s  (+%s coins)", data.text or "", Format.short(data.reward or 0)), C.Green, "QuestDone")
	elseif kind == "Daily" then
		EffectsController.card("DAILY OBJECTIVE DONE", string.format("%s  (+%s coins)", data.text or "", Format.short(data.reward or 0)), C.Green, "QuestDone")
	elseif kind == "Discovery" then
		local def = ScrapConfig.ById[data.id]
		local rank = def and ScrapConfig.rank(def) or 1
		if rank >= 3 then
			EffectsController.card(ScrapConfig.Rarities[def.Rarity].Label .. " DISCOVERY!", string.format("%s added to your Codex (%d/%d)", data.name, data.count, data.total), Ui.rarityColor(def.Rarity), "RareSting")
		else
			EffectsController.card("NEW CODEX ENTRY", string.format("%s  (%d/%d)", data.name or "", data.count or 0, data.total or 0), Ui.rarityColor(data.rarity), nil)
		end
	elseif kind == "Upgrade" then
		AudioController.play("Purchase", nil, true)
		EffectsController.flashStation(Color3.fromRGB(90, 230, 120))
	elseif kind == "Tier" then
		EffectsController.flashStation(Color3.fromRGB(255, 220, 90))
		EffectsController.card("NEW MAGNET", string.format("%s (tier %d) - stronger pull, more range, bigger pile!", data.name, data.tier), C.Accent, "LevelUp")
		AudioController.play("Purchase", nil, true)
	elseif kind == "Zone" then
		EffectsController.card("ZONE UNLOCKED", (data.name or "") .. " - walk through the gate!", C.Blue, "ZoneUnlock")
	elseif kind == "Prestige" then
		EffectsController.card("PRESTIGE!", string.format("+%d Magnet Cores (%d total). Everything you sell is worth more.", data.cores or 0, data.total or 0), C.Accent, "LevelUp")
	elseif kind == "StormReward" then
		EffectsController.card("STORM BONUS", string.format("You pulled %d pieces in the storm: +%s coins", data.count or 0, Format.short(data.reward or 0)), C.Purple, "QuestDone")
	elseif kind == "TutorialDone" then
		EffectsController.card("TUTORIAL COMPLETE", "You're a scrapper now. Keep upgrading and unlock Metro Wreck!", C.Green, "QuestDone")
	end
end

-- The upgrade station's neon trims flash after a purchase, then settle on the colour of
-- your current magnet tier.
function EffectsController.flashStation(color)
	local world = workspace:FindFirstChild("MagnetMayhemWorld")
	local yard = world and world:FindFirstChild("Rustyard")
	local station = yard and yard:FindFirstChild("UpgradeStation")
	if not station then
		return
	end
	for _, d in ipairs(station:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("StationTrim") then
			d.Color = Color3.new(1, 1, 1)
			TweenService:Create(d, TweenInfo.new(0.8), { Color = color }):Play()
		end
	end
end

-- Collection popups (grouped) -------------------------------------------------------------

local function collectPopup(value, lucky, def)
	local now = os.clock()
	if group.label and now - group.last < 1.1 then
		group.value += value
		group.count += 1
		group.last = now
		group.label.Text = string.format("+%s scrap value  (x%d)", Format.short(group.value), group.count)
		return
	end
	if now - popupBudget.t > 1 then
		popupBudget.t, popupBudget.n = now, 0
	end
	if popupBudget.n >= PerformanceConfig.MaxPopupsPerSecond then
		return
	end
	popupBudget.n += 1
	group.value, group.count, group.last = value, 1, now
	local label = Ui.title(string.format("+%s scrap value", Format.short(value)), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(420, 30),
		TextSize = 22,
		TextColor3 = C.Accent,
		Parent = gui,
	})
	Ui.new("UIStroke", { Thickness = 2, Color = C.Black, Transparency = 0.3, Parent = label })
	group.label = label
	TweenService:Create(label, TweenInfo.new(1.4), { Position = UDim2.fromScale(0.5, 0.56) }):Play()
	task.delay(1.6, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.delay(0.45, function()
			label:Destroy()
			if group.label == label then
				group.label = nil
			end
		end)
	end)
	if lucky then
		EffectsController.toast("LUCKY FIND! +50% value", "good")
	end
	if def and ScrapConfig.weightClass(def) == "Heavy" then
		EffectsController.toast("HEAVY OBJECT: " .. def.Name, "warn")
	end
end

-- Shredder machine -----------------------------------------------------------------------

local function machineParts()
	if machine.parts then
		return machine.parts
	end
	local world = workspace:FindFirstChild("MagnetMayhemWorld")
	local yard = world and world:FindFirstChild("Rustyard")
	local shred = yard and yard:FindFirstChild("Shredder")
	if not shred then
		return nil
	end
	local p = { rollers = {}, pistons = {}, warnings = {}, slats = {}, indicators = {}, mouth = shred:FindFirstChild("Mouth") }
	for _, d in ipairs(shred:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("Roller") then
				table.insert(p.rollers, { part = d, base = d.CFrame, dir = d:GetAttribute("Roller") })
			elseif d:GetAttribute("Piston") then
				table.insert(p.pistons, { part = d, base = d.CFrame })
			elseif d:GetAttribute("WarningLight") then
				table.insert(p.warnings, d)
			elseif d:GetAttribute("Slat") then
				table.insert(p.slats, { part = d, base = d.CFrame, index = d:GetAttribute("Slat") })
			elseif d:GetAttribute("Indicator") then
				table.insert(p.indicators, { part = d, index = d:GetAttribute("Indicator") })
			end
		end
	end
	if p.mouth then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparks"
		sparks.Rate = 0
		sparks.Lifetime = NumberRange.new(0.3, 0.7)
		sparks.Speed = NumberRange.new(12, 24)
		sparks.SpreadAngle = Vector2.new(60, 60)
		sparks.Size = NumberSequence.new(0.18, 0)
		sparks.LightEmission = 1
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
		sparks.Acceleration = Vector3.new(0, -40, 0)
		sparks.Parent = p.mouth
		p.sparks = sparks
	end
	machine.parts = p
	return p
end

local machineTime = 0
local function stepMachine(dt)
	local p = machineParts()
	if not p then
		return
	end
	local now = os.clock()
	local busy = now < machine.processingUntil
	machineTime += dt * (if busy then 6 else 0.6)
	for _, r in ipairs(p.rollers) do
		r.part.CFrame = r.base * CFrame.Angles(machineTime * r.dir, 0, 0)
	end
	for i, s in ipairs(p.pistons) do
		local y = if busy then math.abs(math.sin(now * 10 + i)) * 1.6 else 0
		s.part.CFrame = s.base * CFrame.new(0, -y, 0)
	end
	local beltSpeed = if busy then 8 else 1.2
	for _, s in ipairs(p.slats) do
		local offset = ((now * beltSpeed + s.index * 2) % 18) - (s.index * 2)
		s.part.CFrame = s.base * CFrame.new(offset, 0, 0)
	end
	for i, w in ipairs(p.warnings) do
		local on = busy and math.floor(now * 6 + i) % 2 == 0
		w.Color = if on then Color3.fromRGB(255, 80, 30) else Color3.fromRGB(150, 70, 30)
		local light = w:FindFirstChildOfClass("PointLight")
		if light then
			light.Brightness = if on then 2.5 else 0.3
		end
	end
	for _, ind in ipairs(p.indicators) do
		local on = if busy then math.floor(now * 10) % 5 == ind.index else true
		ind.part.Color = if on then Color3.fromRGB(80, 230, 110) else Color3.fromRGB(30, 80, 40)
	end
end

function EffectsController.sell(userId, amount, count, big)
	local owner = Players:GetPlayerByUserId(userId)
	local p = machineParts()
	local isLocal = owner == player
	local duration = math.clamp(0.8 + count * 0.04, 1, if big then 3 else 2)
	machine.processingUntil = math.max(machine.processingUntil, os.clock() + duration + 0.6)
	local pieces = if owner then MagnetController.takePieces(owner) else {}
	local hopper = if p and p.mouth then p.mouth.Position + Vector3.new(0, 1, 0) else Vector3.new(0, 16, -48)
	-- Staged unload: pieces leave the pile in waves, arc up and drop into the hopper.
	for i, piece in ipairs(pieces) do
		local model = piece.model
		if model then
			local delay = math.min(1.2, (i - 1) * 0.035)
			task.delay(delay, function()
				if not model.Parent then
					return
				end
				local startCF = if model:IsA("Model") then model:GetPivot() else model.CFrame
				local t0 = os.clock()
				local flightTime = 0.45
				local conn
				conn = RunService.RenderStepped:Connect(function()
					local u = math.clamp((os.clock() - t0) / flightTime, 0, 1)
					local pos = startCF.Position:Lerp(hopper, u * u) + Vector3.new(0, math.sin(u * math.pi) * 6, 0)
					local cf = CFrame.new(pos) * CFrame.Angles(u * 6, u * 4, 0)
					if model:IsA("Model") then
						model:PivotTo(cf)
					else
						model.CFrame = cf
					end
					if u >= 1 then
						conn:Disconnect()
						model:Destroy()
					end
				end)
			end)
		end
	end
	if p and p.sparks and not reduced() then
		local q = PerformanceConfig.Particles[ClientState.setting("Particles") or "High"] or 1
		p.sparks:Emit(math.floor((if big then 60 else 25) * q))
	end
	local near = isLocal
	local myRoot = ClientState.root()
	if not near and myRoot and (myRoot.Position - hopper).Magnitude < 80 then
		near = true
	end
	if near then
		local at = if isLocal then nil else hopper
		AudioController.play("ShredderStart", at, true)
		local loop = p and p.mouth and AudioController.loop("ShredderLoop", p.mouth)
		for k = 1, math.min(6, count) do
			task.delay(0.25 + k * (duration / 7), function()
				AudioController.play("ShredderCrunch", at)
			end)
		end
		task.delay(duration, function()
			if loop then
				loop:Destroy()
			end
			if big then
				AudioController.play("ShredderSlam", at, true)
			end
		end)
	end
	if isLocal then
		task.delay(duration * 0.8, function()
			AudioController.play("SaleDing", nil, true)
			local label = Ui.title(string.format("+%s COINS", Format.short(amount)), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.45),
				Size = UDim2.fromOffset(500, 60),
				TextSize = if big then 52 else 40,
				TextColor3 = C.Green,
				Parent = gui,
			})
			Ui.new("UIStroke", { Thickness = 3, Color = C.Black, Transparency = 0.2, Parent = label })
			TweenService:Create(label, TweenInfo.new(1.2), { Position = UDim2.fromScale(0.5, 0.38) }):Play()
			task.delay(1.4, function()
				TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				task.delay(0.5, function()
					label:Destroy()
				end)
			end)
			if big then
				require(script.Parent.CameraController).punch(1)
			end
		end)
	end
end

-- Magnetic Storm sky ---------------------------------------------------------------------

local storm = { grade = nil }
local function onEvent(view)
	local active = view and view.kind == "MagneticStorm"
	local grade = Lighting:FindFirstChild("MM_StormGrade")
	if active and not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "MM_StormGrade"
		grade.TintColor = Color3.fromRGB(255, 255, 255)
		grade.Parent = Lighting
		TweenService:Create(grade, TweenInfo.new(3), { TintColor = Color3.fromRGB(205, 195, 255), Contrast = 0.1 }):Play()
		AudioController.play("StormSiren", nil, true)
	elseif not active and grade then
		TweenService:Create(grade, TweenInfo.new(3), { TintColor = Color3.fromRGB(255, 255, 255), Contrast = 0 }):Play()
		task.delay(3.1, function()
			grade:Destroy()
		end)
	end
	storm.active = active
end

local lightningAt = 0
local function stepStorm()
	if not storm.active or reduced() then
		return
	end
	local now = os.clock()
	if now > lightningAt then
		lightningAt = now + Random.new():NextNumber(4, 9)
		local root = ClientState.root()
		if root then
			local spot = root.Position + Vector3.new(Random.new():NextNumber(-60, 60), 0, Random.new():NextNumber(-60, 60))
			local bolt = Instance.new("Part")
			bolt.Name = "StormBolt"
			bolt.Anchored = true
			bolt.CanCollide = false
			bolt.CanQuery = false
			bolt.CanTouch = false
			bolt.Material = Enum.Material.Neon
			bolt.Color = Color3.fromRGB(190, 160, 255)
			bolt.Size = Vector3.new(0.6, 90, 0.6)
			bolt.CFrame = CFrame.new(spot + Vector3.new(0, 45, 0)) * CFrame.Angles(0.05, 0, 0.08)
			bolt.Parent = workspace
			MagnetController.burst(spot, Color3.fromRGB(190, 160, 255), 14)
			task.delay(0.15, function()
				bolt:Destroy()
			end)
		end
	end
end

function EffectsController.init()
	gui = Ui.screen("MagnetFX", 20)
	toastList = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -130), Size = UDim2.fromOffset(380, 170), BackgroundTransparency = 1, Parent = gui })
	Ui.list(toastList, 4, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	banner = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 124), Size = UDim2.fromOffset(640, 34), Visible = false, Parent = gui }, 8)
	bannerText = Ui.title("", { Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), TextSize = 15, TextWrapped = true, Parent = banner })
	cardHolder = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -120), Size = UDim2.fromOffset(320, 300), BackgroundTransparency = 1, Parent = gui })
	Ui.list(cardHolder, 6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)

	ClientState.Notified:Connect(EffectsController.toast)
	ClientState.Announced:Connect(EffectsController.announce)
	ClientState.PopupRequested:Connect(onPopup)
	ClientState.Sold:Connect(EffectsController.sell)
	ClientState.EventChanged:Connect(onEvent)
	ClientState.Collected:Connect(function(batch)
		for _, entry in ipairs(batch) do
			if entry[2] == player.UserId then
				collectPopup(entry[4], entry[5], ScrapConfig.ById[entry[3]])
			end
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		stepMachine(dt)
		stepStorm()
	end)
end

EffectsController.onPopup = onPopup
EffectsController.stepMachine = stepMachine

return EffectsController
