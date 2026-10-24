--[[
	MenuController - main menu / lobby (party, ready, difficulty), settings, profile &
	cosmetics, lore reader and the results screen. Works with mouse, touch and gamepad
	(buttons are selectable; GuiService selection is set when a gamepad is in use).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local Net = require(Shared.Net)
local DifficultyConfig = require(Shared.Config.DifficultyConfig)
local ShopConfig = require(Shared.Config.ShopConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local Settings = require(script.Parent.Settings)
local InputController = require(script.Parent.InputController)

local MenuController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui, lobbyFrame, partyList, readyButton, difficultyButton, countdownLabel, persistLabel, levelLabel
local settingsFrame, profileFrame, profileBody, resultsFrame, resultsBody, loreFrame, loreTitle, loreBody
local shopFrame, shopBody
local modalButton
local isReady = false

local function gamepadActive()
	return UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function focus(button)
	if button and gamepadActive() then
		GuiService.SelectedObject = button
	end
end

-- While any panel is open in first person, a Modal button frees the mouse cursor.
local function updateModal()
	local open = settingsFrame.Visible or profileFrame.Visible or resultsFrame.Visible or loreFrame.Visible or (shopFrame ~= nil and shopFrame.Visible)
	modalButton.Modal = open
	modalButton.Visible = open
end

local function heading(text, parent, order)
	return Ui.scalable(Ui.new("TextLabel", {
		Text = text,
		Font = Ui.Fonts.Title,
		TextSize = 22,
		TextColor3 = C.Accent,
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order or 0,
		Parent = parent,
	}))
end

local function modalPanel(name, width, height)
	local frame = Ui.panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, width, 0, height),
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	Ui.new("UISizeConstraint", { MaxSize = Vector2.new(width, height), Parent = frame })
	Ui.stroke(frame, C.Accent, 0.5)
	Ui.padding(frame, 16)
	-- Shrink on small (phone) screens.
	frame.Size = UDim2.new(0.92, 0, 0.86, 0)
	return frame
end

local function closeButton(frame, onClose)
	local button = Ui.button("Close", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0, 110, 0, 36),
		ZIndex = 11,
		Parent = frame,
	})
	button.Activated:Connect(onClose)
	return button
end

---------------------------------------------------------------------------------------------
-- Lobby
---------------------------------------------------------------------------------------------

local function buildLobby()
	lobbyFrame = Ui.new("Frame", {
		Name = "Lobby",
		Size = UDim2.new(0, 400, 1, 0),
		BackgroundColor3 = Color3.fromRGB(8, 8, 6),
		BackgroundTransparency = 0.2,
		Parent = gui,
	})
	Ui.new("UISizeConstraint", { MaxSize = Vector2.new(400, math.huge), Parent = lobbyFrame })
	lobbyFrame.Size = UDim2.new(0.9, 0, 1, 0)
	Ui.padding(lobbyFrame, 22)
	Ui.list(lobbyFrame, 10)

	Ui.scalable(Ui.new("TextLabel", {
		Text = "DEAD AIR",
		Font = Ui.Fonts.Title,
		TextSize = 52,
		TextColor3 = C.Text,
		Size = UDim2.new(1, 0, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = lobbyFrame,
	}))
	Ui.scalable(Ui.new("TextLabel", {
		Text = "It cannot see you. It can hear everything.",
		TextSize = 15,
		TextColor3 = C.Dim,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = lobbyFrame,
	}))
	levelLabel = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		TextSize = 14,
		TextColor3 = C.Accent,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		Parent = lobbyFrame,
	}))

	heading("PARTY", lobbyFrame, 4)
	partyList = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = lobbyFrame,
	})
	Ui.list(partyList, 4)

	countdownLabel = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		Font = Ui.Fonts.Title,
		TextSize = 20,
		TextColor3 = C.Danger,
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 6,
		Parent = lobbyFrame,
	}))

	readyButton = Ui.button("READY", { Size = UDim2.new(1, 0, 0, 48), TextSize = 20, LayoutOrder = 7, Parent = lobbyFrame })
	readyButton.Activated:Connect(function()
		if not MenuController.myBay then
			return
		end
		isReady = not isReady
		Net.event("SetReady"):FireServer(isReady)
	end)

	difficultyButton = Ui.button("DIFFICULTY: NORMAL", { Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 8, Parent = lobbyFrame })
	difficultyButton.Activated:Connect(function()
		local bay = MenuController.myBay
		if not bay or bay.leaderUserId ~= player.UserId then
			return
		end
		local current = table.find(DifficultyConfig.Order, bay.difficulty) or 2
		local nextName = DifficultyConfig.Order[(current % #DifficultyConfig.Order) + 1]
		Net.event("SetDifficulty"):FireServer(nextName)
	end)

	local row = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = 9, Parent = lobbyFrame })
	local settingsButton = Ui.button("SETTINGS", { Size = UDim2.new(1 / 3, -4, 1, 0), Parent = row })
	local profileButton = Ui.button("RECORD", { Position = UDim2.new(1 / 3, 2, 0, 0), Size = UDim2.new(1 / 3, -4, 1, 0), Parent = row })
	local shopButton = Ui.button("SHOP", { Position = UDim2.new(2 / 3, 4, 0, 0), Size = UDim2.new(1 / 3, -4, 1, 0), Parent = row })
	shopButton.TextColor3 = C.Accent
	shopButton.Activated:Connect(function()
		MenuController.toggleShop(true)
	end)
	settingsButton.Activated:Connect(function()
		MenuController.toggleSettings(true)
	end)
	profileButton.Activated:Connect(function()
		MenuController.toggleProfile(true)
	end)

	Ui.scalable(Ui.new("TextLabel", {
		Text = "Walk into an elevator with your friends: SOLO, DUO, TRIO or SQUAD. It leaves when it's full or when "
			.. "everyone inside presses READY. Freeze and it can't sense you. Crouch to stay quiet (except on metal).",
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = C.Dim,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 10,
		Parent = lobbyFrame,
	}))
	persistLabel = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		TextSize = 12,
		TextColor3 = C.Danger,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 11,
		Parent = lobbyFrame,
	}))
end

local countdownToken
local function renderParty(party)
	for _, child in ipairs(partyList:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local myBay
	for i, bay in ipairs(party.bays or {}) do
		local names = {}
		for _, m in ipairs(bay.members) do
			if m.userId == player.UserId then
				myBay = bay
			end
			table.insert(names, (if m.userId == bay.leaderUserId then "★" else "") .. m.name .. (if m.ready then " ✓" else ""))
		end
		local line = string.format("%s (%d)   %d/%d", string.upper(bay.id), bay.size, #bay.members, bay.size)
		if bay.locked then
			line ..= "   IN USE"
		elseif bay.countdown then
			line ..= string.format("   leaving in %d", math.ceil(bay.countdown))
		end
		if #names > 0 then
			line ..= "\n   " .. table.concat(names, ", ") .. "  -  " .. string.upper(bay.difficulty)
		end
		Ui.scalable(Ui.new("TextLabel", {
			Text = line,
			TextSize = 14,
			TextWrapped = true,
			TextColor3 = if myBay == bay then C.Accent elseif #bay.members > 0 then C.Text else C.Dim,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
			Parent = partyList,
		}))
	end
	local me
	for _, m in ipairs(myBay and myBay.members or {}) do
		if m.userId == player.UserId then
			me = m
		end
	end
	isReady = me ~= nil and me.ready
	readyButton.AutoButtonColor = myBay ~= nil
	readyButton.TextTransparency = if myBay then 0 else 0.45
	if not myBay then
		readyButton.Text = "WALK INTO AN ELEVATOR TO JOIN A PARTY"
	elseif isReady then
		readyButton.Text = "READY  (click to cancel)"
	else
		readyButton.Text = string.format("READY  -  go with %d", #myBay.members)
	end
	readyButton.BackgroundColor3 = if isReady then Color3.fromRGB(40, 70, 44) else C.PanelLight
	local leader = myBay ~= nil and myBay.leaderUserId == player.UserId
	local pressure = party.pressure or 0
	difficultyButton.Text = "DIFFICULTY: " .. string.upper(myBay and myBay.difficulty or "-") .. (if pressure > 0 then string.format("  (+%d pressure)", pressure) else "")
	difficultyButton.AutoButtonColor = leader
	difficultyButton.TextTransparency = if leader then 0 else 0.45
	MenuController.myBay = myBay
	countdownToken = {}
	local token = countdownToken
	if myBay and myBay.countdown then
		local endsAt = os.clock() + myBay.countdown
		task.spawn(function()
			while os.clock() < endsAt and countdownToken == token do
				countdownLabel.Text = string.format("DOORS CLOSING IN %d", math.ceil(endsAt - os.clock()))
				task.wait(0.2)
			end
		end)
	elseif myBay and myBay.locked then
		countdownLabel.Text = "Another party is in the facility. Please wait..."
	else
		countdownLabel.Text = ""
	end
end

---------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------

local function buildSettings()
	settingsFrame = modalPanel("Settings", 520, 560)
	local scroll = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ZIndex = 11,
		Parent = settingsFrame,
	})
	Ui.list(scroll, 8)
	heading("SETTINGS", scroll, 0)
	local first
	for i, def in ipairs(Settings.Definitions) do
		local row = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 36), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 11, Parent = scroll })
		Ui.scalable(Ui.new("TextLabel", {
			Text = def.label,
			TextSize = 15,
			Size = UDim2.new(0.55, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 11,
			Parent = row,
		}))
		if def.kind == "toggle" then
			local button = Ui.button("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.new(0, 110, 0, 32), ZIndex = 11, Parent = row })
			local function render()
				button.Text = if Settings.get(def.key) then "ON" else "OFF"
				button.TextColor3 = if Settings.get(def.key) then C.Good else C.Dim
			end
			button.Activated:Connect(function()
				Settings.set(def.key, not Settings.get(def.key))
				render()
			end)
			Settings.Changed:Connect(render)
			render()
			first = first or button
		else
			local minus = Ui.button("-", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 2), Size = UDim2.new(0, 36, 0, 32), ZIndex = 11, Parent = row })
			local value = Ui.new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 2), Size = UDim2.new(0, 100, 0, 32), TextSize = 15, ZIndex = 11, Parent = row })
			local plus = Ui.button("+", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.new(0, 36, 0, 32), ZIndex = 11, Parent = row })
			local function render()
				local v = Settings.get(def.key)
				if def.max <= 1 and def.min >= 0 then
					value.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
				else
					value.Text = string.format("%.2f", v):gsub("%.?0+$", "")
				end
			end
			local function adjust(sign)
				local v = Settings.get(def.key) + sign * def.step
				v = math.clamp(math.floor(v / def.step + 0.5) * def.step, def.min, def.max)
				Settings.set(def.key, v)
				render()
			end
			minus.Activated:Connect(function()
				adjust(-1)
			end)
			plus.Activated:Connect(function()
				adjust(1)
			end)
			Settings.Changed:Connect(render)
			render()
			first = first or minus
		end
	end
	MenuController.firstSetting = first
	closeButton(settingsFrame, function()
		MenuController.toggleSettings(false)
	end)
end

function MenuController.toggleSettings(open)
	if open == nil then
		open = not settingsFrame.Visible
	end
	settingsFrame.Visible = open
	if open then
		profileFrame.Visible = false
		focus(MenuController.firstSetting)
	end
	updateModal()
end

---------------------------------------------------------------------------------------------
-- Profile / cosmetics
---------------------------------------------------------------------------------------------

local function buildProfile()
	profileFrame = modalPanel("Record", 520, 560)
	profileBody = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 4,
		ZIndex = 11,
		Parent = profileFrame,
	})
	Ui.list(profileBody, 6)
	closeButton(profileFrame, function()
		MenuController.toggleProfile(false)
	end)
end

local function renderProfile(profile)
	if not profileBody then
		return
	end
	for _, child in ipairs(profileBody:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if not profile then
		return
	end
	heading("PERSONNEL RECORD", profileBody, 0)
	local function line(text, order, color)
		Ui.scalable(Ui.new("TextLabel", {
			Text = text,
			TextSize = 15,
			TextColor3 = color or C.Text,
			Size = UDim2.new(1, 0, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			ZIndex = 11,
			Parent = profileBody,
		}))
	end
	line(string.format("Level %d   (%d / %d XP)", profile.level, profile.xp, profile.nextLevelXp), 1, C.Accent)
	local s = profile.stats
	line(string.format("Runs %d    Escapes %d    Deaths %d", s.Runs, s.Escapes, s.Deaths), 2)
	line(string.format("Items %d    Revives %d    Evidence %d    Black boxes %d", s.ItemsCollected, s.Revives, s.LoreFound, s.BlackBoxes), 3)
	heading("FLASHLIGHT BEAMS", profileBody, 4)
	for i, cosmetic in ipairs(profile.cosmetics) do
		local unlocked = profile.unlocked[cosmetic.Id] == true
		local equipped = profile.equipped == cosmetic.Id
		local requirement = if cosmetic.Level then "Level " .. cosmetic.Level else cosmetic.Stat .. " " .. cosmetic.Threshold
		local button = Ui.button(
			string.format("%s   %s", cosmetic.Name, if equipped then "(equipped)" elseif unlocked then "" else "[" .. requirement .. "]"),
			{ Size = UDim2.new(1, -8, 0, 34), LayoutOrder = 4 + i, ZIndex = 11, Parent = profileBody }
		)
		button.TextColor3 = Color3.fromRGB(cosmetic.Color[1], cosmetic.Color[2], cosmetic.Color[3])
		button.TextTransparency = if unlocked then 0 else 0.5
		button.Activated:Connect(function()
			if unlocked then
				Net.event("EquipCosmetic"):FireServer(cosmetic.Id)
			end
		end)
	end
	if not profile.persistent then
		line("Progress is not being saved on this server.", 40, C.Danger)
	end
end

function MenuController.toggleProfile(open)
	profileFrame.Visible = open
	if open then
		settingsFrame.Visible = false
		renderProfile(ClientState.profile)
	end
	updateModal()
end

---------------------------------------------------------------------------------------------
-- Shop (Robux boosts)
---------------------------------------------------------------------------------------------

local function buildShop()
	shopFrame = modalPanel("Shop", 560, 600)
	shopBody = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 4,
		ZIndex = 11,
		Parent = shopFrame,
	})
	Ui.list(shopBody, 8)
	closeButton(shopFrame, function()
		MenuController.toggleShop(false)
	end)
end

local function renderShop(profile)
	if not shopBody then
		return
	end
	for _, child in ipairs(shopBody:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	heading("SUPPLY SHOP", shopBody, 0)
	Ui.scalable(Ui.new("TextLabel", {
		Text = "One-run boosts. Switch one ON and it is used up when your next descent starts.",
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = C.Dim,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		ZIndex = 11,
		Parent = shopBody,
	}))
	local boosts = profile and profile.boosts or {}
	local armed = profile and profile.armed or {}
	for i, key in ipairs(ShopConfig.BoostOrder) do
		local def = ShopConfig.Boosts[key]
		local owned = boosts[key] or 0
		local row = Ui.panel({ Size = UDim2.new(1, -8, 0, 84), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.3, LayoutOrder = 1 + i, ZIndex = 11, Parent = shopBody })
		Ui.padding(row, 8)
		Ui.scalable(Ui.new("TextLabel", {
			Text = string.format("%s   x%d", def.Name, owned),
			Font = Ui.Fonts.Bold,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3]),
			Size = UDim2.new(1, -130, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 12,
			Parent = row,
		}))
		Ui.scalable(Ui.new("TextLabel", {
			Text = def.Description,
			TextSize = 13,
			TextWrapped = true,
			TextColor3 = C.Dim,
			Position = UDim2.new(0, 0, 0, 22),
			Size = UDim2.new(1, -130, 0, 44),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 12,
			Parent = row,
		}))
		local on = armed[key] == true
		local toggle = Ui.button(if on then "NEXT RUN: ON" else "NEXT RUN: OFF", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 124, 0, 30),
			TextSize = 12,
			ZIndex = 12,
			Parent = row,
		})
		toggle.TextColor3 = if on then C.Good elseif owned > 0 then C.Text else C.Dim
		toggle.Activated:Connect(function()
			if owned > 0 or on then
				Net.event("ShopArm"):FireServer(key, not on)
			end
		end)
		-- Buy button for the single-boost product.
		for _, product in ipairs(ShopConfig.Products) do
			if product.Grants[key] and next(product.Grants, next(product.Grants)) == nil then
				local buy = Ui.button(string.format("BUY  R$ %d", product.Robux), {
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, 0, 1, 0),
					Size = UDim2.new(0, 124, 0, 30),
					TextSize = 12,
					ZIndex = 12,
					Parent = row,
				})
				buy.TextColor3 = C.Accent
				buy.Activated:Connect(function()
					Net.event("ShopBuy"):FireServer(product.Key)
				end)
			end
		end
	end
	-- Bundles (products that grant more than one boost).
	for i, product in ipairs(ShopConfig.Products) do
		local kinds = 0
		for _ in pairs(product.Grants) do
			kinds += 1
		end
		if kinds > 1 then
			local buy = Ui.button(string.format("%s   -   R$ %d", product.Name, product.Robux), {
				Size = UDim2.new(1, -8, 0, 40),
				TextSize = 14,
				LayoutOrder = 20 + i,
				ZIndex = 11,
				Parent = shopBody,
			})
			buy.TextColor3 = C.Accent
			buy.Activated:Connect(function()
				Net.event("ShopBuy"):FireServer(product.Key)
			end)
		end
	end
end

function MenuController.toggleShop(open)
	shopFrame.Visible = open
	if open then
		settingsFrame.Visible = false
		profileFrame.Visible = false
		renderShop(ClientState.profile)
	end
	updateModal()
end

---------------------------------------------------------------------------------------------
-- Lore reader
---------------------------------------------------------------------------------------------

local function buildLore()
	loreFrame = modalPanel("Lore", 480, 380)
	loreFrame.BackgroundColor3 = Color3.fromRGB(226, 218, 192)
	loreTitle = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		Font = Ui.Fonts.Title,
		TextSize = 22,
		TextColor3 = Color3.fromRGB(40, 32, 22),
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = loreFrame,
	}))
	loreBody = Ui.scalable(Ui.new("TextLabel", {
		Text = "",
		Font = Ui.Fonts.Title,
		TextSize = 17,
		TextColor3 = Color3.fromRGB(50, 42, 30),
		TextWrapped = true,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(1, 0, 1, -90),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 11,
		Parent = loreFrame,
	}))
	local close = closeButton(loreFrame, function()
		loreFrame.Visible = false
		updateModal()
	end)
	MenuController.loreClose = close
end

---------------------------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------------------------

local function buildResults()
	resultsFrame = modalPanel("Results", 560, 520)
	resultsBody = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 4,
		ZIndex = 11,
		Parent = resultsFrame,
	})
	Ui.list(resultsBody, 6)
	closeButton(resultsFrame, function()
		resultsFrame.Visible = false
		updateModal()
	end)
end

local STATUS_TEXT = { Escaped = "ESCAPED", Dead = "KILLED", Downed = "LEFT BEHIND", Alive = "ALIVE" }

local function renderResults(results)
	for _, child in ipairs(resultsBody:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local escaped = results.outcome == "Escaped"
	Ui.scalable(Ui.new("TextLabel", {
		Text = if escaped then "EXTRACTION CONFIRMED" else "SIGNAL LOST",
		Font = Ui.Fonts.Title,
		TextSize = 34,
		TextColor3 = if escaped then C.Good else C.Danger,
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
		LayoutOrder = 0,
		Parent = resultsBody,
	}))
	local function line(text, order, color, size)
		Ui.scalable(Ui.new("TextLabel", {
			Text = text,
			TextSize = size or 15,
			TextColor3 = color or C.Text,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 11,
			LayoutOrder = order,
			Parent = resultsBody,
		}))
	end
	line(string.format("%s  -  %s  -  objectives %d/%d", results.title, results.difficulty, math.min(results.stepsCompleted, results.totalSteps), results.totalSteps), 1, C.Dim)
	if results.mvp then
		line("MVP: " .. results.mvp, 1, C.Accent, 18)
	end
	for i, p in ipairs(results.players) do
		line(string.format("#%d  %s   %s   score %d   items %d   revives %d", i, p.name, STATUS_TEXT[p.status] or p.status, p.score or 0, p.items, p.revives), 1 + i, if p.status == "Escaped" then C.Good else C.Text)
	end
	local xp = results.xp
	if xp then
		line(" ", 20)
		for i, entry in ipairs(xp.lines) do
			line(string.format("%s   +%d", entry.label, entry.amount), 20 + i, C.Dim)
		end
		line(string.format("TOTAL  +%d XP  (x%.2f)", xp.total, xp.multiplier), 40, C.Accent, 18)
		if xp.levelAfter > xp.levelBefore then
			line("LEVEL UP: " .. xp.levelAfter, 41, C.Good, 18)
		end
		for i, name in ipairs(xp.unlocks) do
			line("Unlocked: " .. name, 41 + i, C.Good)
		end
	end
	if (results.pressureNext or 0) > 0 and escaped then
		line(string.format("The facility is learning. Pressure %d next run.", results.pressureNext), 60, C.Danger)
	end
	line("Returning to the lobby...", 61, C.Dim)
end

---------------------------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------------------------

local function refreshLobby()
	lobbyFrame.Visible = not ClientState.inRun()
	if lobbyFrame.Visible then
		focus(readyButton)
	end
end

function MenuController.init()
	gui = Ui.screen("DeadAirMenu", player:WaitForChild("PlayerGui"), 20)
	modalButton = Ui.new("TextButton", {
		Name = "MouseUnlock",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 0),
		Visible = false,
		Parent = gui,
	})
	buildLobby()
	buildSettings()
	buildProfile()
	buildLore()
	buildResults()
	buildShop()

	ClientState.PartyChanged:Connect(renderParty)
	ClientState.RoundChanged:Connect(function(state, data)
		if state == "Lobby" then
			resultsFrame.Visible = false
			updateModal()
			if data and data.error then
				countdownLabel.Text = data.error
			end
		end
		refreshLobby()
	end)
	player:GetAttributeChangedSignal("DA_Status"):Connect(refreshLobby)
	ClientState.ProfileChanged:Connect(function(profile)
		levelLabel.Text = string.format("LEVEL %d", profile.level)
		persistLabel.Text = if profile.persistent then "" else "Progress saving unavailable on this server."
		if profileFrame.Visible then
			renderProfile(profile)
		end
		if shopFrame.Visible then
			renderShop(profile)
		end
	end)
	ClientState.ResultsReceived:Connect(function(results)
		renderResults(results)
		resultsFrame.Visible = true
		updateModal()
	end)
	ClientState.LoreReceived:Connect(function(note)
		loreTitle.Text = note.title
		loreBody.Text = note.body
		loreFrame.Visible = true
		updateModal()
		focus(MenuController.loreClose)
	end)
	InputController.SettingsToggled:Connect(function()
		MenuController.toggleSettings()
	end)
	refreshLobby()
end

return MenuController
