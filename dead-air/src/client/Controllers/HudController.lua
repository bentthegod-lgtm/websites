--[[
	HudController - the minimal in-run HUD: objective, teammates, inventory, stamina,
	battery, a noise meter (how loud YOU just were), notifications and state overlays
	(hiding, downed, dead / escaped + spectating).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local ItemConfig = require(Shared.Config.ItemConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)

local HudController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui, objectiveTitle, objectiveText, objectiveExtra, teamList, inventoryFrame
local staminaFill, batteryLabel, noiseFill, notifyStack
local hiddenOverlay, downedOverlay, downedTimer, deadOverlay, deadTitle, spectateLabel
local noiseLevel = 0

local STATUS_COLORS = {
	Alive = C.Good,
	Downed = C.Accent,
	Dead = C.Danger,
	Escaped = Color3.fromRGB(140, 190, 255),
	Lobby = C.Dim,
	Spectating = C.Dim,
}

local function flashlightKey()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Light button"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Y"
	end
	return "F"
end

local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	gui = Ui.screen("DeadAirHUD", playerGui, 5)
	gui.Enabled = false

	-- Objective (top-left)
	local objective = Ui.panel({
		Name = "Objective",
		Position = UDim2.new(0, 16, 0, 16),
		Size = UDim2.new(0, 340, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.45,
		Parent = gui,
	})
	Ui.padding(objective, 10)
	Ui.list(objective, 4)
	objectiveTitle = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		Font = Ui.Fonts.Title,
		TextSize = 14,
		TextColor3 = C.Accent,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = objective,
	}))
	objectiveText = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		TextSize = 18,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = objective,
	}))
	objectiveExtra = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		TextSize = 14,
		TextColor3 = C.Danger,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		Parent = objective,
	}))

	-- Teammates (top-right)
	teamList = Ui.new("Frame", {
		Name = "Team",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 60),
		Size = UDim2.new(0, 200, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.list(teamList, 4, nil, Enum.HorizontalAlignment.Right)

	local menuButton = Ui.button("≡", {
		Name = "MenuButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.new(0, 36, 0, 36),
		TextSize = 22,
		Parent = gui,
	})
	menuButton.Activated:Connect(function()
		InputController.SettingsToggled:Fire()
	end)

	-- Inventory (bottom-centre)
	inventoryFrame = Ui.new("Frame", {
		Name = "Inventory",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(0, 0, 0, 58),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.list(inventoryFrame, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)

	-- Vitals (bottom-left)
	local vitals = Ui.new("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -20),
		Size = UDim2.new(0, 280, 0, 70),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local function bar(y, label, color)
		Ui.new("TextLabel", {
			Text = label,
			TextSize = 11,
			Font = Ui.Fonts.Bold,
			TextColor3 = C.Dim,
			Position = UDim2.new(0, 0, 0, y),
			Size = UDim2.new(0, 60, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = vitals,
		})
		local track = Ui.new("Frame", {
			Position = UDim2.new(0, 62, 0, y + 3),
			Size = UDim2.new(1, -62, 0, 6),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			Parent = vitals,
		})
		Ui.corner(track, 3)
		local fill = Ui.new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = color, Parent = track })
		Ui.corner(fill, 3)
		return fill
	end
	staminaFill = bar(0, "STAMINA", C.Text)
	noiseFill = bar(20, "NOISE", C.Accent)
	noiseFill.Size = UDim2.new(0, 0, 1, 0)
	batteryLabel = Ui.scalable(Ui.new("TextLabel", {
		Text = "LIGHT 100%",
		TextSize = 12,
		Font = Ui.Fonts.Bold,
		TextColor3 = C.Dim,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = vitals,
	}))

	-- Crosshair
	Ui.new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 3, 0, 3),
		BackgroundColor3 = C.Text,
		BackgroundTransparency = 0.5,
		Parent = gui,
	})

	-- Notifications
	notifyStack = Ui.new("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.new(0, 520, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Ui.list(notifyStack, 4, nil, Enum.HorizontalAlignment.Center)

	-- Hiding overlay: dark slats framing the view
	hiddenOverlay = Ui.new("Frame", { Name = "Hidden", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })
	for _, spec in ipairs({ { 0, 0.36 }, { 0.64, 0.36 } }) do
		Ui.new("Frame", {
			Position = UDim2.fromScale(0, spec[1]),
			Size = UDim2.fromScale(1, spec[2]),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.12,
			Parent = hiddenOverlay,
		})
	end
	local leaveHint = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Tap the locker prompt to leave" else "HIDING  -  E / Space to leave"
	Ui.scalable(Ui.new("TextLabel", {
		Text = leaveHint,
		TextSize = 15,
		Font = Ui.Fonts.Title,
		TextColor3 = C.Dim,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.new(0, 400, 0, 20),
		Parent = hiddenOverlay,
	}))

	-- Downed overlay
	downedOverlay = Ui.new("Frame", {
		Name = "Downed",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(90, 0, 0),
		BackgroundTransparency = 0.6,
		Visible = false,
		Parent = gui,
	})
	Ui.scalable(Ui.new("TextLabel", {
		Text = "YOU'RE DOWN",
		Font = Ui.Fonts.Title,
		TextSize = 38,
		TextColor3 = C.Text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(0, 500, 0, 44),
		Parent = downedOverlay,
	}))
	downedTimer = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 500, 0, 24),
		Parent = downedOverlay,
	}))

	-- Dead / escaped overlay
	deadOverlay = Ui.new("Frame", { Name = "Spectate", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = gui })
	deadTitle = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		Font = Ui.Fonts.Title,
		TextSize = 34,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.new(0, 600, 0, 40),
		Parent = deadOverlay,
	}))
	spectateLabel = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		TextSize = 16,
		TextColor3 = C.Dim,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.new(0, 400, 0, 20),
		Parent = deadOverlay,
	}))
	local prev = Ui.button("<", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, -240, 1, -92), Size = UDim2.new(0, 44, 0, 36), Parent = deadOverlay })
	local nextButton = Ui.button(">", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 240, 1, -92), Size = UDim2.new(0, 44, 0, 36), Parent = deadOverlay })
	prev.Activated:Connect(function()
		CameraController.cycleSpectate(-1)
	end)
	nextButton.Activated:Connect(function()
		CameraController.cycleSpectate(1)
	end)
end

---------------------------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------------------------

local function renderObjective(snapshot)
	if not snapshot then
		objectiveTitle.Text = ""
		objectiveText.Text = ""
		objectiveExtra.Text = ""
		return
	end
	objectiveTitle.Text = string.upper(snapshot.title or "") .. string.format("   %d/%d", math.min(snapshot.index, snapshot.total), snapshot.total)
	local current
	for _, step in ipairs(snapshot.steps) do
		if step.current then
			current = step
		end
	end
	objectiveText.Text = current and current.text or "Escape"
	objectiveExtra.Text = ""
end

local function renderTeam(party)
	for _, child in ipairs(teamList:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if not party or not party.members then
		return
	end
	for i, member in ipairs(party.members) do
		if member.userId ~= player.UserId then
			local color = STATUS_COLORS[member.status] or C.Dim
			Ui.scalable(Ui.new("TextLabel", {
				Text = member.name .. "  ●",
				RichText = false,
				TextSize = 14,
				TextColor3 = color,
				Size = UDim2.new(1, 0, 0, 16),
				TextXAlignment = Enum.TextXAlignment.Right,
				LayoutOrder = i,
				Parent = teamList,
			}))
		end
	end
end

local function renderInventory()
	for _, child in ipairs(inventoryFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local items = ClientState.inventory
	for i = 1, PlayerConfig.Inventory.Capacity do
		local kind = items[i]
		local def = kind and ItemConfig[kind]
		local selected = kind ~= nil and i == ClientState.selectedSlot
		local slot = Ui.new("TextButton", {
			Name = "Slot" .. i,
			Text = "",
			Size = UDim2.new(0, 58, 0, 58),
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = if kind then 0.25 else 0.65,
			AutoButtonColor = false,
			LayoutOrder = i,
			Parent = inventoryFrame,
		})
		Ui.corner(slot, 6)
		Ui.stroke(slot, if selected then C.Accent else C.Dim, if selected then 0.1 else 0.75)
		if def then
			local swatch = Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 8),
				Size = UDim2.new(0, 18, 0, 18),
				BackgroundColor3 = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3]),
				Parent = slot,
			})
			Ui.corner(swatch, 4)
			Ui.new("TextLabel", {
				Text = def.DisplayName,
				TextSize = 10,
				TextWrapped = true,
				Position = UDim2.new(0, 2, 0, 28),
				Size = UDim2.new(1, -4, 0, 26),
				Parent = slot,
			})
		end
		Ui.new("TextLabel", {
			Text = tostring(i),
			TextSize = 10,
			TextColor3 = C.Dim,
			Position = UDim2.new(0, 4, 0, 2),
			Size = UDim2.new(0, 10, 0, 10),
			Parent = slot,
		})
		slot.Activated:Connect(function()
			if kind then
				ClientState.setSlot(i)
			end
		end)
	end
end

function HudController.notify(text, kind)
	if not gui then
		return
	end
	local color = C.Text
	if kind == "danger" then
		color = C.Danger
	elseif kind == "warn" or kind == "objective" then
		color = C.Accent
	end
	local label = Ui.scalable(Ui.new("TextLabel", {
		Text = text,
		Font = if kind == "danger" or kind == "objective" then Ui.Fonts.Title else Ui.Fonts.Body,
		TextSize = if kind == "danger" then 20 else 16,
		TextColor3 = color,
		TextStrokeTransparency = 0.6,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Parent = notifyStack,
	}))
	task.delay(4.5, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.9)
			label:Destroy()
		end
	end)
	local labels = {}
	for _, child in ipairs(notifyStack:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	if #labels > 4 then
		labels[1]:Destroy()
	end
end

local function refreshVisibility()
	local status = ClientState.status()
	gui.Enabled = ClientState.inRun() and (ClientState.roundState == "Playing" or ClientState.roundState == "Starting")
	hiddenOverlay.Visible = player:GetAttribute("DA_Hidden") == true and status == "Alive"
	downedOverlay.Visible = status == "Downed"
	deadOverlay.Visible = status == "Dead" or status == "Escaped"
	if status == "Dead" then
		deadTitle.Text = "YOU WERE HEARD"
		deadTitle.TextColor3 = C.Danger
	elseif status == "Escaped" then
		deadTitle.Text = "YOU ESCAPED"
		deadTitle.TextColor3 = Color3.fromRGB(160, 200, 255)
	end
end

function HudController.init()
	build()
	ClientState.ObjectiveChanged:Connect(renderObjective)
	ClientState.PartyChanged:Connect(renderTeam)
	ClientState.InventoryChanged:Connect(renderInventory)
	ClientState.SlotChanged:Connect(renderInventory)
	ClientState.Notified:Connect(HudController.notify)
	ClientState.NoiseFeedback:Connect(function(level)
		noiseLevel = math.max(noiseLevel, math.clamp(level, 0, 1))
	end)
	ClientState.RoundChanged:Connect(function(state)
		refreshVisibility()
		if state == "Playing" then
			task.delay(4, function()
				HudController.notify("Press " .. flashlightKey() .. " for your flashlight. Its light makes you easier to spot.", "info")
			end)
		end
	end)
	CameraController.SpectateChanged:Connect(function(target)
		spectateLabel.Text = if target then "Watching " .. target.DisplayName else "No one left to watch"
	end)
	for _, attr in ipairs({ "DA_Status", "DA_Hidden" }) do
		player:GetAttributeChangedSignal(attr):Connect(refreshVisibility)
	end
	renderInventory()
	refreshVisibility()

	RunService.Heartbeat:Connect(function(dt)
		if not gui.Enabled then
			return
		end
		local stamina = (player:GetAttribute("DA_Stamina") or 100) / (player:GetAttribute("DA_StaminaMax") or PlayerConfig.Stamina.Max)
		staminaFill.Size = UDim2.new(math.clamp(stamina, 0, 1), 0, 1, 0)
		staminaFill.BackgroundColor3 = if player:GetAttribute("DA_Exhausted") then C.Danger else C.Text
		local battery = player:GetAttribute("DA_Battery") or 100
		local on = player:GetAttribute("DA_Flashlight") == true
		batteryLabel.Text = string.format("FLASHLIGHT %d%%  %s", battery, if on then "ON" else "OFF  [" .. flashlightKey() .. "]")
		batteryLabel.TextColor3 = if battery < 20 then C.Danger elseif on then C.Accent else C.Dim
		noiseLevel = math.max(0, noiseLevel - dt * 0.9)
		noiseFill.Size = UDim2.new(noiseLevel, 0, 1, 0)
		noiseFill.BackgroundColor3 = if noiseLevel > 0.6 then C.Danger else C.Accent

		local snapshot = ClientState.objective
		if snapshot and snapshot.extraction and snapshot.extraction.localEndsAt then
			local remaining = math.max(0, snapshot.extraction.localEndsAt - os.clock())
			objectiveExtra.Text = if snapshot.extraction.phase == "Calling"
				then string.format("ELEVATOR ARRIVING  %ds  - the alarm is drawing it in", math.ceil(remaining))
				else string.format("DOORS OPEN  %ds  - GET INSIDE", math.ceil(remaining))
		elseif objectiveExtra.Text ~= "" and not (snapshot and snapshot.extraction) then
			objectiveExtra.Text = ""
		end
		if downedOverlay.Visible then
			local t = player:GetAttribute("DA_BleedOut")
			downedTimer.Text = if t then string.format("A teammate can revive you  -  %ds", t) else "Hold on..."
		end
	end)
end

return HudController
