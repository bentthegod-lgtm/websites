--[[
	LaunchController - the launch panel shown while you own a pad.

	Shows the featured objective, the machine choice (owned / locked), power (drag the bar
	or use -/+), launch angle and aim (within what your upgrades unlock), spin mode, the
	machine's state (READY / CHARGING / COOLDOWN / IN FLIGHT) and a big LAUNCH button.
	Values are clamped locally for display with the same Economy.sanitise the server uses;
	the server re-validates everything.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local Net = require(Shared.Net)
local Economy = require(Shared.Economy)
local MachineConfig = require(Shared.Config.MachineConfig)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local LaunchController = {}

local C = Ui.Colors
local gui, panel
local refs = {}
local request = { Power = 1, Angle = 45, Aim = 0, Spin = "None" }
local loadedFromProfile = false
local chargingUntil, cooldownUntil = nil, nil
local dragging = false

LaunchController.request = request

local function profileLike()
	local p = ClientState.profile
	return { Upgrades = p and p.upgrades or {}, Prestige = p and p.prestige or { Credits = 0 } }
end

function LaunchController.stats()
	return Economy.stats(profileLike())
end

function LaunchController.machine()
	local p = ClientState.profile
	return MachineConfig.ById[p and p.selected or "Standard"] or MachineConfig.ById.Standard
end

local function clampRequest()
	local clean = Economy.sanitise(LaunchController.machine(), LaunchController.stats(), request)
	for k, v in pairs(clean) do
		request[k] = v
	end
end

function LaunchController.status()
	local now = os.clock()
	if ClientState.myRun then
		return "Flight"
	end
	if chargingUntil and now < chargingUntil then
		return "Charging"
	end
	if cooldownUntil and now < cooldownUntil then
		return "Cooldown"
	end
	return "Ready"
end

function LaunchController.adjust(field, delta)
	local stats = LaunchController.stats()
	if field == "Power" then
		request.Power += delta * 0.05
	elseif field == "Angle" then
		request.Angle += delta * stats.AngleStep
	elseif field == "Aim" then
		request.Aim += delta * 2
	elseif field == "Spin" then
		local modes = stats.SpinModes
		local i = table.find(modes, request.Spin) or 1
		request.Spin = modes[(i % #modes) + 1]
	end
	clampRequest()
	LaunchController.render()
end

function LaunchController.launch()
	if not ClientState.myPad() then
		ClientState.Notified:Fire("Claim a launch pad first: walk onto a glowing pad and press E.", "info")
		return
	end
	if LaunchController.status() ~= "Ready" then
		return
	end
	clampRequest()
	Net.event("Launch"):FireServer({ Power = request.Power, Angle = request.Angle, Aim = request.Aim, Spin = request.Spin })
end

local function setPowerFromX(x)
	local bar = refs.powerBar
	local rel = (x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X)
	local machine = LaunchController.machine()
	request.Power = machine.MinPower + math.clamp(rel, 0, 1) * (1 - machine.MinPower)
	clampRequest()
	LaunchController.render()
end

local function stepper(parent, title, order, field)
	local row = Ui.new("Frame", { Size = UDim2.new(0, 150, 0, 54), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	Ui.label(title, { Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = C.Dim, Font = Ui.Fonts.Bold, Parent = row })
	local minus = Ui.button("-", { Position = UDim2.fromOffset(0, 18), Size = UDim2.fromOffset(36, 34), TextSize = 20 }, C.PanelLighter)
	minus.Parent = row
	local value = Ui.label("", { Position = UDim2.fromOffset(38, 18), Size = UDim2.new(1, -76, 0, 34), TextSize = 18, Font = Ui.Fonts.Bold, Parent = row })
	local plus = Ui.button("+", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 18), Size = UDim2.fromOffset(36, 34), TextSize = 20 }, C.PanelLighter)
	plus.Parent = row
	minus.Activated:Connect(function()
		LaunchController.adjust(field, -1)
	end)
	plus.Activated:Connect(function()
		LaunchController.adjust(field, 1)
	end)
	return value
end

function LaunchController.build()
	gui = Ui.screen("CrashLaunch", 5)
	panel = Ui.panel({ Name = "LaunchPanel", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(780, 210), Visible = false, Parent = gui }, 14)
	Ui.padding(panel, 14, 10)
	-- Featured objective banner.
	local banner = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.PanelLight, Parent = panel })
	Ui.corner(banner, 8)
	refs.featured = Ui.label("", { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 15, Font = Ui.Fonts.Bold, TextColor3 = C.Accent, Parent = banner })
	-- Machine choice.
	local machines = Ui.new("Frame", { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(0, 540, 0, 40), BackgroundTransparency = 1, Parent = panel })
	Ui.list(machines, 8, Enum.FillDirection.Horizontal)
	refs.machineButtons = {}
	for i, id in ipairs(MachineConfig.Order) do
		local def = MachineConfig.ById[id]
		local b = Ui.button(def.Short, { Size = UDim2.fromOffset(170, 38), TextSize = 15, LayoutOrder = i }, C.PanelLighter)
		b.Parent = machines
		b.Activated:Connect(function()
			local p = ClientState.profile
			if p and p.machines[id] then
				Net.event("SelectMachine"):FireServer(id)
			else
				ClientState.PopupRequested:Fire("OpenMenu", { tab = "Machines" })
			end
		end)
		refs.machineButtons[id] = b
	end
	-- Controls.
	local controls = Ui.new("Frame", { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(0, 560, 0, 100), BackgroundTransparency = 1, Parent = panel })
	Ui.label("POWER", { Size = UDim2.new(0, 200, 0, 16), TextSize = 12, TextColor3 = C.Dim, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, Parent = controls })
	local back, fill = Ui.bar(controls, { Size = UDim2.new(0, 400, 0, 26), Position = UDim2.fromOffset(0, 20) }, C.Accent)
	refs.powerBar, refs.powerFill = back, fill
	refs.powerText = Ui.label("", { Position = UDim2.fromOffset(410, 20), Size = UDim2.fromOffset(140, 26), TextSize = 18, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, Parent = controls })
	local hit = Ui.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = back })
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setPowerFromX(input.Position.X)
		end
	end)
	-- Released anywhere (not just over the bar): GuiObject.InputEnded doesn't fire when the
	-- mouse / finger lets go outside the bar, which would leave the drag stuck on.
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setPowerFromX(input.Position.X)
		end
	end)
	local steppers = Ui.new("Frame", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, Parent = controls })
	Ui.list(steppers, 12, Enum.FillDirection.Horizontal)
	refs.angle = stepper(steppers, "LAUNCH ANGLE", 1, "Angle")
	refs.aim = stepper(steppers, "AIM  (LEFT / RIGHT)", 2, "Aim")
	local spinRow = Ui.new("Frame", { Size = UDim2.new(0, 150, 0, 54), BackgroundTransparency = 1, LayoutOrder = 3, Parent = steppers })
	Ui.label("SPIN", { Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = C.Dim, Font = Ui.Fonts.Bold, Parent = spinRow })
	refs.spin = Ui.button("", { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 34), TextSize = 15 }, C.PanelLighter)
	refs.spin.Parent = spinRow
	refs.spin.Activated:Connect(function()
		LaunchController.adjust("Spin", 1)
	end)
	-- Launch button + status.
	refs.launch = Ui.button("LAUNCH", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 40), Size = UDim2.fromOffset(190, 100), TextSize = 30, Font = Ui.Fonts.Title }, C.Accent)
	refs.launch.Parent = panel
	refs.launch.Activated:Connect(LaunchController.launch)
	refs.status = Ui.label("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 146), Size = UDim2.fromOffset(190, 20), TextSize = 13, TextColor3 = C.Dim, Parent = panel })
	refs.leave = Ui.button("LEAVE PAD", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 168), Size = UDim2.fromOffset(190, 22), TextSize = 12 }, C.PanelLighter)
	refs.leave.Parent = panel
	refs.leave.Activated:Connect(function()
		Net.event("LeavePad"):FireServer()
	end)
	-- Charge overlay: machine-specific wind-up label, a charge ramp and a 3-2-1 countdown.
	refs.charge = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(420, 150), BackgroundTransparency = 1, Visible = false, Parent = gui })
	refs.chargeCount = Ui.title("3", { Size = UDim2.new(1, 0, 0, 90), TextSize = 86, TextColor3 = C.Accent, TextStrokeTransparency = 0.2, Parent = refs.charge })
	refs.chargeLabel = Ui.title("", { Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 24), TextSize = 20, TextStrokeTransparency = 0.4, Parent = refs.charge })
	local back, fill = Ui.bar(refs.charge, { Position = UDim2.fromOffset(40, 122), Size = UDim2.new(1, -80, 0, 14) }, C.Red)
	refs.chargeBack, refs.chargeFill = back, fill
	refs.skip = Ui.button("SKIP CAMERA  (SPACE)", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -236), Size = UDim2.fromOffset(220, 34), TextSize = 14, Visible = false }, C.PanelLighter)
	refs.skip.Parent = gui
	refs.skip.Activated:Connect(function()
		require(script.Parent.CameraController).stopFollow()
	end)
end

-- Wind-up text per machine (matches its animation and sound).
LaunchController.WindUp = {
	Standard = "COCKING THE ARM",
	Spring = "COMPRESSING THE SPRING",
	AirCannon = "PRESSURISING - STAND CLEAR",
}

-- Pure: the countdown number (3, 2, 1) shown at `elapsed` seconds into a charge.
function LaunchController.countdownStep(elapsed, duration)
	if duration <= 0 then
		return 1
	end
	local f = math.clamp(elapsed / duration, 0, 0.9999)
	return 3 - math.floor(f * 3)
end

local charge = nil -- { start, duration, machineId, shown }
local function stepCharge()
	if not refs.charge then
		return
	end
	if not charge then
		refs.charge.Visible = false
		return
	end
	local elapsed = os.clock() - charge.start
	if charge.fired then
		refs.charge.Visible = elapsed < charge.duration + 0.6
		return
	end
	refs.charge.Visible = true
	local n = LaunchController.countdownStep(elapsed, charge.duration)
	if n ~= charge.shown then
		charge.shown = n
		refs.chargeCount.Text = tostring(n)
		require(script.Parent.AudioController).play("Countdown", nil, true)
		local scale = refs.chargeCount:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = refs.chargeCount })
		scale.Scale = if ClientState.setting("ReducedEffects") then 1 else 1.5
		game:GetService("TweenService"):Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	local f = math.clamp(elapsed / charge.duration, 0, 1)
	-- Ramp eases in: slow start, fast finish - it should feel like pressure building.
	refs.chargeFill.Size = UDim2.fromScale(f * f, 1)
	refs.chargeFill.BackgroundColor3 = C.Accent:Lerp(C.Red, f)
end
LaunchController.stepCharge = stepCharge

function LaunchController.render()
	if not panel then
		return
	end
	local p = ClientState.profile
	local pad = ClientState.myPad()
	panel.Visible = pad ~= nil and p ~= nil
	if not panel.Visible then
		return
	end
	if not loadedFromProfile and p.lastLaunch then
		loadedFromProfile = true
		for k, v in pairs(p.lastLaunch) do
			request[k] = v
		end
	end
	clampRequest()
	local stats = LaunchController.stats()
	local machine = LaunchController.machine()
	local featured = p.featured
	refs.featured.Text = if featured then string.format("FEATURED OBJECTIVE:  %s   (+%d, x%s)", featured.name, featured.points, Format.stat(featured.multiplier)) else "Launch freely - no objective required"
	for id, b in pairs(refs.machineButtons) do
		local owned = p.machines[id] == true
		local def = MachineConfig.ById[id]
		b.Text = if owned then def.Short else (def.Short .. "  (LOCKED)")
		Ui.setButtonColor(b, if id == p.selected then C.Accent elseif owned then C.PanelLighter else C.PanelLight)
	end
	refs.powerFill.Size = UDim2.fromScale((request.Power - machine.MinPower) / math.max(0.01, 1 - machine.MinPower), 1)
	local speed = Economy.speed(machine, stats, request.Power)
	refs.powerText.Text = string.format("%d%%  (%d st/s)", math.floor(request.Power * 100 + 0.5), math.floor(speed))
	refs.angle.Text = if stats.AngleMin == stats.AngleMax then string.format("%d°  (fixed)", request.Angle) else string.format("%d°", request.Angle)
	refs.aim.Text = if request.Aim == 0 then "CENTER" elseif request.Aim < 0 then string.format("%d° L", -request.Aim) else string.format("%d° R", request.Aim)
	local spinCount = #stats.SpinModes
	refs.spin.Text = (MachineConfig.SpinById[request.Spin] and MachineConfig.SpinById[request.Spin].Name or "No spin") .. (if spinCount <= 1 then "  (locked)" else "")
	local status = LaunchController.status()
	if status == "Ready" then
		refs.launch.Text = "LAUNCH"
		Ui.setButtonColor(refs.launch, C.Accent)
		refs.status.Text = machine.Name .. " ready  -  F / R2"
	elseif status == "Charging" then
		refs.launch.Text = "CHARGING"
		Ui.setButtonColor(refs.launch, C.Red)
		refs.status.Text = "Stand clear!"
	elseif status == "Cooldown" then
		refs.launch.Text = string.format("%.1fs", math.max(0, cooldownUntil - os.clock()))
		Ui.setButtonColor(refs.launch, C.PanelLighter)
		refs.status.Text = "Launcher resetting..."
	else
		refs.launch.Text = "IN FLIGHT"
		Ui.setButtonColor(refs.launch, C.PanelLighter)
		refs.status.Text = "Watch it go!"
	end
	refs.skip.Visible = status == "Flight" and require(script.Parent.CameraController).following()
end

function LaunchController.init()
	LaunchController.build()
	ClientState.ProfileChanged:Connect(LaunchController.render)
	ClientState.PadsChanged:Connect(LaunchController.render)
	ClientState.MachineFx:Connect(function(padIndex, machineId, phase, data)
		local pad = ClientState.myPad()
		if not pad or pad.index ~= padIndex then
			return
		end
		if phase == "Charge" then
			chargingUntil = os.clock() + (data.time or 1)
			charge = { start = os.clock(), duration = data.time or 1, machineId = machineId }
			refs.chargeLabel.Text = LaunchController.WindUp[machineId] or "CHARGING"
		elseif phase == "Fire" then
			chargingUntil = nil
			cooldownUntil = os.clock() + Economy.cooldown(MachineConfig.ById[machineId], LaunchController.stats())
			if charge then
				charge.fired = true
				charge.duration = os.clock() - charge.start
				refs.chargeCount.Text = "LAUNCH!"
				refs.chargeLabel.Text = ""
				refs.chargeFill.Size = UDim2.fromScale(1, 1)
			end
		elseif phase == "Rest" then
			chargingUntil = nil
			charge = nil
		end
		LaunchController.render()
	end)
	game:GetService("RunService").RenderStepped:Connect(stepCharge)
	task.spawn(function()
		while gui and gui.Parent do
			LaunchController.render()
			task.wait(0.1)
		end
	end)
end

return LaunchController
