--[[
	ElevatorController - the floor panel and the ride.

	Panel: the cabin's "Select Floor" prompt opens a vertical list of all seven depths,
	deepest at the bottom. Unlocked floors have a GO button (the current floor is marked
	YOU ARE HERE); the next locked floor shows its price and an UNLOCK button that turns
	gold when you can afford it; deeper floors are shown locked with their name and code,
	so there is always something visible to work towards. Below them: the Ancient Vault
	complex, sealed ("coming soon").

	Ride (server-validated; the server moves the character at the end):
	  Depart -> doors slide shut, motor hum, the screen dims to a shaft view with passing
	  light bars and a floor counter rolling from the start to the target code, a little
	  camera sway. Arrive -> chime, the destination cabin's doors slide open, the overlay
	  fades and a title card names the depth. Cancel (died, rebirth) -> overlay off.
	The character can't walk during the ride (local WalkSpeed / JumpHeight 0, restored).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local Net = require(Shared.Net)
local DepthConfig = require(Shared.Config.DepthConfig)
local Format = require(Shared.Format)

local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)
local Ui = require(script.Parent.Ui)

local C = Ui.Colors
local ElevatorController = {}

local gui
local list
local overlay, counter, subtitle, bars
local card, cardTitle, cardText
local motor
local rideConn
local saved
local doorsOpen = {} -- [code] = bool (local door state)

-- Doors ------------------------------------------------------------------------------------

local function cabin(code)
	local vault = Workspace:FindFirstChild("Vault")
	local folder = vault and vault:FindFirstChild(code)
	return folder and folder:FindFirstChild("Elevator_" .. code, true)
end

local function setDoors(code, open, instant)
	local model = cabin(code)
	if not model then
		return
	end
	if (doorsOpen[code] ~= false) == open then
		return
	end
	doorsOpen[code] = open
	local offset = model:GetAttribute("DoorClosedOffset") or 6
	for name, sign in pairs({ DoorL = 1, DoorR = -1 }) do
		local door = model:FindFirstChild(name)
		if door and door.PrimaryPart then
			local base = door:GetAttribute("OpenPivot")
			if not base then
				base = door:GetPivot()
				door:SetAttribute("OpenPivot", base)
			end
			-- Slide along the cabin's own X axis.
			local goal = if open then base else base * CFrame.new(sign * offset, 0, 0)
			if instant then
				door:PivotTo(goal)
			else
				local value = Instance.new("CFrameValue")
				value.Value = door:GetPivot()
				value.Changed:Connect(function(cf)
					door:PivotTo(cf)
				end)
				local tween = TweenService:Create(value, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = goal })
				tween.Completed:Connect(function()
					value:Destroy()
				end)
				tween:Play()
			end
		end
	end
end
ElevatorController.setDoors = setDoors

-- Panel ------------------------------------------------------------------------------------

local function row(def, profile, list, canTravel)
	local unlocked = def.Depth <= profile.highestDepth
	local here = def.Depth == ClientState.depth()
	local isNext = def.Depth == profile.highestDepth + 1
	local accent = Ui.rgb(def.Palette.Accent)
	local frame = Ui.panel({ Size = UDim2.new(1, -8, 0, 58), LayoutOrder = def.Depth, BackgroundColor3 = if unlocked then C.PanelLight else C.Panel, Parent = list }, 10)
	local chip = Ui.new("Frame", { Size = UDim2.fromOffset(56, 42), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = if unlocked then accent else C.PanelLighter, Parent = frame })
	Ui.corner(chip, 8)
	Ui.title(def.Code, { Size = UDim2.fromScale(1, 1), TextSize = 20, TextColor3 = if unlocked then C.Black else C.Dim, Parent = chip })
	Ui.label(string.upper(def.Name), { Position = UDim2.fromOffset(74, 8), Size = UDim2.new(1, -230, 0, 22), Font = Ui.Fonts.Bold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if unlocked then C.Text else C.Dim, Parent = frame })
	local info
	if unlocked then
		info = if here then "YOU ARE HERE" else def.Tagline
	elseif isNext then
		info = "Unlock: $" .. Format.short(def.UnlockCash) .. (if def.UnlockTokens > 0 then "  +  " .. def.UnlockTokens .. " Tokens" else "")
	else
		info = "LOCKED  -  clearance required"
	end
	Ui.label(info, { Position = UDim2.fromOffset(74, 30), Size = UDim2.new(1, -230, 0, 20), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if here then C.Accent else C.Dim, TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame })
	local button
	if unlocked and not here and not canTravel then
		Ui.label("VIA ELEVATOR", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 38), Font = Ui.Fonts.Bold, TextSize = 13, TextColor3 = C.Green, Parent = frame })
	elseif unlocked and not here then
		button = Ui.button("GO", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 38), TextSize = 18 }, C.Green)
		button.Activated:Connect(function()
			Net.event("Travel"):FireServer(def.Depth)
		end)
	elseif isNext then
		local affordable = profile.cash >= def.UnlockCash and profile.tokens >= def.UnlockTokens
		button = Ui.button("UNLOCK", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 38), TextSize = 16 }, if affordable then C.Accent else C.PanelLighter)
		button.Activated:Connect(function()
			if affordable then
				Net.event("UnlockDepth"):FireServer(def.Depth)
			else
				AudioController.play("NoFunds")
				ClientState.Notified:Fire(string.format("%s needs $%s%s.", def.Name, Format.short(def.UnlockCash), if def.UnlockTokens > 0 then " and " .. def.UnlockTokens .. " Vault Tokens" else ""), "error")
			end
		end)
	elseif not unlocked then
		Ui.label("LOCKED", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 38), Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = C.Dim, Parent = frame })
	end
	if button then
		button.Parent = frame
	end
end

-- Fills a list with every depth (also used by the Depths menu, where canTravel is false).
function ElevatorController.fillDepthList(list, canTravel)
	Ui.clear(list)
	local profile = ClientState.profile
	if not profile then
		return
	end
	for d = 1, DepthConfig.Count do
		row(DepthConfig.get(d), profile, list, canTravel)
	end
	local nc = DepthConfig.NextComplex
	local sealed = Ui.panel({ Size = UDim2.new(1, -8, 0, 52), LayoutOrder = 99, BackgroundColor3 = C.Black, Parent = list }, 10)
	Ui.label(string.upper(nc.Name) .. " COMPLEX", { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 22), Font = Ui.Fonts.Bold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 160, 110), Parent = sealed })
	Ui.label("SEALED  -  coming soon. Reach " .. DepthConfig.get(nc.RequiresDepth).Code .. " to see what waits behind the last door.", { Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -28, 0, 20), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, Parent = sealed })
end

function ElevatorController.refreshPanel()
	if list then
		ElevatorController.fillDepthList(list, true)
	end
end

-- Ride -------------------------------------------------------------------------------------

local function freeze(on)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if on then
		saved = saved or { walk = humanoid.WalkSpeed, jump = humanoid.JumpHeight }
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
	elseif saved then
		humanoid.WalkSpeed = math.max(saved.walk, ClientState.stats().WalkSpeed)
		humanoid.JumpHeight = saved.jump
		saved = nil
	end
end

local function stopRide()
	if rideConn then
		rideConn:Disconnect()
		rideConn = nil
	end
	if motor then
		motor:Destroy()
		motor = nil
	end
	freeze(false)
	TweenService:Create(overlay, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(counter, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	task.delay(0.5, function()
		if not ClientState.riding then
			overlay.Visible = false
		end
	end)
end

local function depart(data)
	Ui.closeWindow("Elevator")
	local from = DepthConfig.get(data.from or ClientState.depth())
	local to = DepthConfig.get(data.to)
	if not to then
		return
	end
	freeze(true)
	setDoors(from.Code, false)
	setDoors(to.Code, false, true) -- the destination cabin waits closed
	AudioController.play("ElevatorDoorClose")
	task.delay(0.5, function()
		if ClientState.riding then
			motor = AudioController.loop("ElevatorMotor")
		end
	end)
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	TweenService:Create(overlay, TweenInfo.new(0.6), { BackgroundTransparency = 0.25 }):Play()
	counter.TextTransparency = 1
	subtitle.TextTransparency = 1
	TweenService:Create(counter, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	subtitle.Text = (if data.to > from.Depth then "DESCENDING TO " else "ASCENDING TO ") .. to.Code .. "  " .. string.upper(to.Name)
	local duration = data.duration or 2
	local t0 = os.clock()
	local down = data.to > from.Depth
	local camera = Workspace.CurrentCamera
	rideConn = RunService.RenderStepped:Connect(function(dt)
		local t = math.clamp((os.clock() - t0) / duration, 0, 1)
		local eased = t * t * (3 - 2 * t)
		local level = from.Depth + (to.Depth - from.Depth) * eased
		local shown = DepthConfig.get(math.clamp(math.floor(level + 0.5), 1, DepthConfig.Count))
		counter.Text = shown.Code
		for i, bar in ipairs(bars) do
			local speed = 2.2 * math.sin(t * math.pi) + 0.2
			local y = (bar:GetAttribute("Y") + dt * speed * (if down then -1 else 1)) % 1
			bar:SetAttribute("Y", y)
			bar.Position = UDim2.new(0, 0, y, 0)
			bar.BackgroundTransparency = 0.55 + 0.35 * (1 - math.sin(t * math.pi)) + (i % 2) * 0.05
		end
		if camera and ClientState.setting("CameraShake") ~= false and not ClientState.setting("ReducedEffects") then
			local sway = math.sin(os.clock() * 23) * 0.004 * math.sin(t * math.pi)
			camera.CFrame = camera.CFrame * CFrame.Angles(sway, 0, sway * 0.5)
		end
	end)
end

local function arrive(data)
	stopRide()
	local def = DepthConfig.get(data.depth)
	if not def then
		return
	end
	AudioController.play("ElevatorArrive")
	task.delay(0.25, function()
		setDoors(def.Code, true)
		AudioController.play("ElevatorDoor")
	end)
	cardTitle.Text = def.Code .. "  |  " .. string.upper(def.Name)
	cardText.Text = def.Tagline
	cardTitle.TextColor3 = Ui.rgb(def.Palette.Accent)
	card.Visible = true
	card.GroupTransparency = 1
	TweenService:Create(card, TweenInfo.new(0.4), { GroupTransparency = 0 }):Play()
	task.delay(2.6, function()
		TweenService:Create(card, TweenInfo.new(0.6), { GroupTransparency = 1 }):Play()
		task.delay(0.6, function()
			card.Visible = false
		end)
	end)
end

function ElevatorController.init()
	gui = Ui.screen("VaultElevator", 20)
	local _, body = Ui.window(gui, "Elevator", "ELEVATOR - SELECT FLOOR", 520, 590)
	list = Ui.scroll(body, { Size = UDim2.fromScale(1, 1) })
	Ui.list(list, 6)
	Ui.onWindowOpen("Elevator", ElevatorController.refreshPanel)
	ClientState.ProfileChanged:Connect(function()
		if Ui.isOpen("Elevator") then
			ElevatorController.refreshPanel()
		end
	end)

	overlay = Ui.new("Frame", { Name = "RideOverlay", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Black, BackgroundTransparency = 1, Visible = false, ZIndex = 5, Parent = gui })
	bars = {}
	for i = 1, 6 do
		local bar = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = Color3.fromRGB(255, 226, 170), BackgroundTransparency = 0.7, ZIndex = 5, Parent = overlay })
		bar:SetAttribute("Y", (i - 1) / 6)
		table.insert(bars, bar)
	end
	counter = Ui.title("B1", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(300, 110), TextSize = 96, TextColor3 = Color3.fromRGB(255, 170, 60), ZIndex = 6, Parent = overlay })
	subtitle = Ui.label("", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(600, 30), Font = Ui.Fonts.Bold, TextSize = 20, ZIndex = 6, Parent = overlay })

	card = Ui.new("CanvasGroup", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.16), Size = UDim2.fromOffset(620, 92), BackgroundColor3 = C.Black, BackgroundTransparency = 0.3, Visible = false, Parent = gui })
	Ui.corner(card, 12)
	cardTitle = Ui.title("", { Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 8), TextSize = 34, Parent = card })
	cardText = Ui.label("", { Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 58), TextSize = 16, TextColor3 = C.Dim, Parent = card })

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.ActionText == "Select Floor" and not ClientState.riding then
			Ui.openWindow("Elevator")
		end
	end)
	ClientState.ElevatorEvent:Connect(function(phase, data)
		if phase == "Depart" then
			depart(data)
		elseif phase == "Arrive" then
			arrive(data)
		else
			stopRide()
			for d = 1, DepthConfig.Count do
				setDoors(DepthConfig.get(d).Code, true, true)
			end
		end
	end)
end

return ElevatorController
