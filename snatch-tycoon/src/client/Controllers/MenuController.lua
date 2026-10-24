--[[
	MenuController - modal panels: SHOP (tabs: Cash / Boosts / Passes), REBIRTH, DAILY,
	INDEX (the Blobbydex, with 3D previews), CODES and SETTINGS.
	Only one panel is open at a time. Gamepad: opening a panel selects its first button.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local ShopConfig = require(Shared.Config.ShopConfig)
local BlobbyConfig = require(Shared.Config.BlobbyConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local RewardConfig = require(Shared.Config.RewardConfig)
local BlobbyModels = require(Shared.BlobbyModels)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)
local HudController = require(script.Parent.HudController)

local MenuController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui
local panels = {} -- [name] = { frame, body, render, firstButton }
local openName = nil
local shopTab = "Cash"

local function gamepadActive()
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	return ok and last ~= nil and string.sub(last.Name, 1, 7) == "Gamepad"
end

local function clear(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function makePanel(name, title, color, width, height)
	local frame = Ui.panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0, width, 0, height),
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	Ui.gradient(frame, Color3.fromRGB(58, 42, 100), Color3.fromRGB(34, 24, 62))
	local header = Ui.new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = color, Parent = frame })
	Ui.corner(header, 14)
	Ui.gradient(header, Ui.lighten(color, 0.2), Ui.darken(color, 0.2))
	Ui.label(title, { Font = Ui.Fonts.Title, Size = UDim2.new(1, -120, 1, -10), Position = UDim2.new(0, 16, 0, 5), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, StrokeThickness = 3, Parent = header })
	local close = Ui.button("X", C.Danger, { Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 44, 0, 44), TextSize = 26, Parent = header })
	close.Activated:Connect(function()
		MenuController.close()
	end)
	local body = Ui.new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.new(0, 12, 0, 66),
		Size = UDim2.new(1, -24, 1, -78),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = frame,
	})
	-- Fit small screens: never wider/taller than the viewport.
	Ui.new("UISizeConstraint", { MaxSize = Vector2.new(width, height), Parent = frame })
	frame.Size = UDim2.new(0.94, 0, 0.84, 0)
	local panel = { frame = frame, body = body, close = close }
	panels[name] = panel
	return panel
end

function MenuController.open(name)
	local panel = panels[name]
	if not panel then
		return
	end
	if openName and openName ~= name and panels[openName] then
		panels[openName].frame.Visible = false
	end
	openName = name
	panel.frame.Visible = true
	Ui.pop(panel.frame, 0.85)
	if panel.render then
		panel.render(ClientState.profile)
	end
	if gamepadActive() then
		GuiService.SelectedObject = panel.firstButton or panel.close
	end
end

function MenuController.close()
	if openName and panels[openName] then
		panels[openName].frame.Visible = false
	end
	openName = nil
	if gamepadActive() then
		GuiService.SelectedObject = nil
	end
end

function MenuController.toggle(name)
	if openName == name then
		MenuController.close()
	else
		MenuController.open(name)
	end
end

function MenuController.isOpen(name)
	return openName == name
end

---------------------------------------------------------------------------------------------
-- Shop
---------------------------------------------------------------------------------------------

local function shopCard(parent, order, color, title, description, priceText, owned, onBuy, extra)
	local card = Ui.panel({ Size = UDim2.new(0, 196, 0, 214), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = parent })
	local stripe = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = color, Parent = card })
	Ui.corner(stripe, 12)
	Ui.label(title, { Font = Ui.Fonts.Title, Size = UDim2.new(1, -12, 1, -8), Position = UDim2.new(0, 6, 0, 4), TextScaled = true, Parent = stripe })
	if extra then
		Ui.label(extra, { Position = UDim2.new(0, 8, 0, 44), Size = UDim2.new(1, -16, 0, 30), TextScaled = true, TextColor3 = C.Good, StrokeThickness = 2, Parent = card })
	end
	Ui.new("TextLabel", {
		Text = description,
		Font = Ui.Fonts.Body,
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.Dim,
		Position = UDim2.new(0, 8, 0, if extra then 76 else 48),
		Size = UDim2.new(1, -16, 0, if extra then 76 else 104),
		Parent = card,
	})
	local button = Ui.button(if owned then "OWNED" else priceText, if owned then C.Grey else C.Good, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, 42),
		TextSize = 22,
		Parent = card,
	})
	if not owned then
		button.Activated:Connect(function()
			AudioController.play("Click")
			onBuy()
		end)
	end
	return button
end

local function renderShop(profile)
	local panel = panels.Shop
	local body = panel.body
	clear(body)
	local tabs = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, LayoutOrder = 0, Parent = body })
	Ui.list(tabs, 8, Enum.FillDirection.Horizontal)
	local first
	for i, tab in ipairs({ { "Cash", C.Good }, { "Boosts", C.Blue }, { "Passes", C.Accent } }) do
		local button = Ui.button(string.upper(tab[1]), if shopTab == tab[1] then tab[2] else C.Grey, { Size = UDim2.new(0, 150, 0, 42), LayoutOrder = i, Parent = tabs })
		button.Activated:Connect(function()
			shopTab = tab[1]
			AudioController.play("Click")
			renderShop(ClientState.profile)
		end)
		first = first or button
	end
	panel.firstButton = first
	local grid = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = body })
	Ui.new("UIGridLayout", {
		CellSize = UDim2.new(0, 196, 0, 214),
		CellPadding = UDim2.new(0, 10, 0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local passes = profile and profile.passes or {}
	local order = 0
	if shopTab == "Passes" then
		for _, pass in ipairs(ShopConfig.Passes) do
			order += 1
			shopCard(grid, order, Ui.rgb(pass.Color), pass.Name, pass.Description, "R$ " .. pass.Robux, passes[pass.Key], function()
				Net.event("PassBuy"):FireServer(pass.Key)
			end)
		end
	else
		for _, product in ipairs(ShopConfig.Products) do
			local isCash = product.Kind == "Cash"
			local hidden = product.Kind == "Crate" and profile ~= nil and profile.randomItemsAllowed == false
			if (shopTab == "Cash") == isCash and not hidden then
				order += 1
				local extra
				if isCash then
					extra = "+" .. Format.cash(profile and profile.packs and profile.packs[product.Key] or product.Pack.Minimum)
				elseif product.Kind == "Crate" then
					local parts = {}
					for _, o in ipairs(product.Odds) do
						table.insert(parts, string.format("%s %d%%", o.Rarity, math.floor(o.Chance * 100 + 0.5)))
					end
					extra = table.concat(parts, "  ")
				elseif product.Kind == "ServerLuck" then
					extra = "EVERYONE GETS IT!"
				elseif product.Kind == "LockNow" and profile and (profile.lockTokens or 0) > 0 then
					extra = "Tokens: " .. profile.lockTokens
				end
				shopCard(grid, order, Ui.rgb(product.Color), product.Name, product.Description, "R$ " .. product.Robux, false, function()
					Net.event("ShopBuy"):FireServer(product.Key)
				end, extra)
			end
		end
	end
	Ui.label("Purchases support the game. Prices in Robux (R$).", { Size = UDim2.new(1, 0, 0, 20), TextScaled = true, TextColor3 = C.Dim, LayoutOrder = 2, Parent = body })
end

---------------------------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------------------------

local function renderRebirth(profile)
	local panel = panels.Rebirth
	local body = panel.body
	clear(body)
	if not profile then
		return
	end
	local r = profile.rebirth
	local function line(text, color, order, height)
		return Ui.label(text, { Size = UDim2.new(1, 0, 0, height or 30), TextScaled = true, TextColor3 = color or C.Text, LayoutOrder = order, Parent = body })
	end
	line("Rebirths: " .. profile.rebirths, C.Accent, 1, 40)
	line(string.format("Cash multiplier: x%s  ->  x%s", tostring(r.multNow), tostring(r.multNext)), C.Good, 2)
	line(string.format("Pedestal slots: %d  ->  %d", profile.slots, r.slotsNext), C.Blue, 3)
	line("Cost: " .. Format.cash(r.cost), C.Text, 4)
	local back, fill = Ui.progressBar(body, { Size = UDim2.new(0.9, 0, 0, 26), LayoutOrder = 5, FillColor = C.Accent })
	fill.Size = UDim2.fromScale(math.clamp(profile.cash / math.max(r.cost, 1), 0, 1), 1)
	Ui.label(Format.cash(profile.cash) .. " / " .. Format.cash(r.cost), { Size = UDim2.fromScale(1, 1), TextScaled = true, ZIndex = back.ZIndex + 2, Parent = back })
	Ui.new("TextLabel", {
		Text = "Rebirthing resets your cash and Blobbies, but the multiplier and slots are forever. Blobbies waiting for a pedestal (crates, gifts) are kept.",
		Font = Ui.Fonts.Body,
		TextSize = 15,
		TextWrapped = true,
		TextColor3 = C.Dim,
		Size = UDim2.new(1, 0, 0, 54),
		LayoutOrder = 6,
		Parent = body,
	})
	local can = profile.cash >= r.cost
	local button = Ui.button(if can then "REBIRTH!" else "NOT ENOUGH CASH", if can then C.Accent else C.Grey, { Size = UDim2.new(0, 280, 0, 56), TextSize = 28, LayoutOrder = 7, Parent = body })
	button.Activated:Connect(function()
		if can then
			Net.event("Rebirth"):FireServer()
			MenuController.close()
		end
	end)
	panel.firstButton = button
end

---------------------------------------------------------------------------------------------
-- Daily
---------------------------------------------------------------------------------------------

local function renderDaily(profile)
	local panel = panels.Daily
	local body = panel.body
	clear(body)
	if not profile or not profile.daily then
		return
	end
	local daily = profile.daily
	Ui.label("Streak: " .. daily.streak .. " day" .. (if daily.streak == 1 then "" else "s"), { Size = UDim2.new(1, 0, 0, 32), TextScaled = true, TextColor3 = C.Accent, LayoutOrder = 1, Parent = body })
	local row = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Parent = body })
	Ui.new("UIGridLayout", { CellSize = UDim2.new(0, 116, 0, 120), CellPadding = UDim2.new(0, 8, 0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	for i, reward in ipairs(daily.rewards) do
		local isToday = i == daily.rewardIndex
		local claimed = i < daily.rewardIndex or (isToday and not daily.canClaim)
		local color = if isToday then C.Accent elseif claimed then C.Good else C.PanelLight
		local tile = Ui.panel({ BackgroundColor3 = Ui.darken(color, 0.35), LayoutOrder = i, Parent = row })
		Ui.label("DAY " .. i, { Font = Ui.Fonts.Title, Size = UDim2.new(1, 0, 0, 28), TextScaled = true, TextColor3 = color, Parent = tile })
		local text = if reward.amount then Format.cash(reward.amount) else reward.text
		Ui.new("TextLabel", { Text = text, Font = Ui.Fonts.Bold, TextSize = 15, TextWrapped = true, TextColor3 = C.Text, Position = UDim2.new(0, 4, 0, 30), Size = UDim2.new(1, -8, 0, 60), Parent = tile })
		if claimed then
			Ui.label("CLAIMED", { Position = UDim2.new(0, 0, 1, -26), Size = UDim2.new(1, 0, 0, 22), TextScaled = true, TextColor3 = C.Good, Parent = tile })
		end
	end
	local button = Ui.button(if daily.canClaim then "CLAIM DAY " .. daily.rewardIndex else ("NEXT IN " .. Format.time(daily.nextIn)), if daily.canClaim then C.Good else C.Grey, { Size = UDim2.new(0, 300, 0, 54), TextSize = 26, LayoutOrder = 3, Parent = body })
	button.Activated:Connect(function()
		if daily.canClaim then
			Net.event("ClaimDaily"):FireServer()
		end
	end)
	panel.firstButton = button
	Ui.label("Come back every day! Missing a day resets the streak.", { Size = UDim2.new(1, 0, 0, 20), TextScaled = true, TextColor3 = C.Dim, LayoutOrder = 4, Parent = body })
end

---------------------------------------------------------------------------------------------
-- Index (Blobbydex)
---------------------------------------------------------------------------------------------

local function preview(parent, species, discovered)
	local viewport = Ui.new("ViewportFrame", {
		Size = UDim2.new(1, -8, 0, 96),
		Position = UDim2.new(0, 4, 0, 4),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -1),
		ImageColor3 = if discovered then Color3.new(1, 1, 1) else Color3.new(0, 0, 0),
		Parent = parent,
	})
	local built = BlobbyModels.build(species, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi + 0.5, 0), { rarity = RarityConfig.Tiers[species.Rarity] })
	built.model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local h = built.height
	camera.CFrame = CFrame.lookAt(Vector3.new(0, h * 0.55, h * 1.9 + 4), Vector3.new(0, h * 0.45, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

local function renderIndex(profile)
	local panel = panels.Index
	local body = panel.body
	clear(body)
	local discovered = profile and profile.discovered or {}
	Ui.label(string.format("BLOBBYDEX  %d / %d discovered", profile and profile.discoveredCount or 0, #BlobbyConfig.List), { Size = UDim2.new(1, 0, 0, 30), TextScaled = true, TextColor3 = C.Accent, LayoutOrder = 0, Parent = body })
	local grid = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = body })
	Ui.new("UIGridLayout", { CellSize = UDim2.new(0, 136, 0, 168), CellPadding = UDim2.new(0, 8, 0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, species in ipairs(BlobbyConfig.List) do
		local tier = RarityConfig.Tiers[species.Rarity]
		local color = Ui.rgb(tier.Color)
		local found = discovered[species.Id] == true
		local card = Ui.panel({ BackgroundColor3 = Ui.darken(color, 0.65), LayoutOrder = i, Parent = grid })
		local ok = pcall(preview, card, species, found)
		if not ok then
			Ui.label("?", { Size = UDim2.new(1, 0, 0, 96), TextScaled = true, Parent = card })
		end
		Ui.label(if found then species.Name else "???", { Position = UDim2.new(0, 4, 0, 102), Size = UDim2.new(1, -8, 0, 22), TextScaled = true, Parent = card })
		Ui.label(species.Rarity, { Position = UDim2.new(0, 4, 0, 124), Size = UDim2.new(1, -8, 0, 18), TextScaled = true, TextColor3 = color, Parent = card })
		Ui.label(if found then Format.perSecond(species.Income) else Format.cash(species.Price), { Position = UDim2.new(0, 4, 0, 144), Size = UDim2.new(1, -8, 0, 18), TextScaled = true, TextColor3 = C.Good, Parent = card })
	end
end

---------------------------------------------------------------------------------------------
-- Codes
---------------------------------------------------------------------------------------------

local codeBox

local function buildCodes()
	local panel = makePanel("Codes", "CODES", C.Pink, 520, 360)
	local body = panel.body
	Ui.list(body, 10)
	Ui.label(RewardConfig.LikeMessage, { Size = UDim2.new(1, 0, 0, 44), TextScaled = true, TextColor3 = C.Accent, LayoutOrder = 1, Parent = body })
	codeBox = Ui.new("TextBox", {
		PlaceholderText = "Enter code...",
		Text = "",
		ClearTextOnFocus = false,
		Font = Ui.Fonts.Bold,
		TextSize = 24,
		TextColor3 = C.Text,
		BackgroundColor3 = C.Outline,
		BackgroundTransparency = 0.2,
		Size = UDim2.new(0.9, 0, 0, 52),
		LayoutOrder = 2,
		Parent = body,
	})
	Ui.corner(codeBox, 10)
	Ui.stroke(codeBox, C.Pink, 2)
	local redeem = Ui.button("REDEEM", C.Good, { Size = UDim2.new(0, 220, 0, 52), TextSize = 26, LayoutOrder = 3, Parent = body })
	redeem.Activated:Connect(function()
		local text = codeBox.Text
		if #text > 0 and #text <= 32 then
			Net.event("RedeemCode"):FireServer(text)
			codeBox.Text = ""
		end
	end)
	panel.firstButton = redeem
	Ui.label("New codes drop at like and visit milestones!", { Size = UDim2.new(1, 0, 0, 22), TextScaled = true, TextColor3 = C.Dim, LayoutOrder = 4, Parent = body })
end

---------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------

local function renderSettings(profile)
	local panel = panels.Settings
	local body = panel.body
	clear(body)
	local settings = profile and profile.settings or { Music = true, Sfx = true }
	local first
	for i, key in ipairs({ "Music", "Sfx" }) do
		local on = settings[key] ~= false
		local button = Ui.button((if key == "Sfx" then "SOUND EFFECTS" else "MUSIC") .. ": " .. (if on then "ON" else "OFF"), if on then C.Good else C.Grey, { Size = UDim2.new(0.9, 0, 0, 52), TextSize = 22, LayoutOrder = i, Parent = body })
		button.Activated:Connect(function()
			settings[key] = not on
			AudioController.applySettings(settings)
			Net.event("SaveSettings"):FireServer({ Music = settings.Music ~= false, Sfx = settings.Sfx ~= false })
			renderSettings(profile)
		end)
		first = first or button
	end
	panel.firstButton = first
	local saved = profile and profile.persistent
	Ui.label(if saved then "Your progress saves automatically." else "Saving is OFF on this server (Studio / DataStore offline).", { Size = UDim2.new(1, 0, 0, 24), TextScaled = true, TextColor3 = if saved then C.Good else C.Orange, LayoutOrder = 5, Parent = body })
	Ui.label("Controls: E buy/steal/sell  |  F slap  |  L lock  |  G drop  |  B shop", { Size = UDim2.new(1, 0, 0, 22), TextScaled = true, TextColor3 = C.Dim, LayoutOrder = 6, Parent = body })
end

---------------------------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------------------------

function MenuController.init()
	gui = Ui.screen("SnatchMenus", player:WaitForChild("PlayerGui"), 5)
	Ui.autoScale(gui)

	local shop = makePanel("Shop", "SHOP", C.Good, 680, 560)
	Ui.list(shop.body, 10)
	shop.render = renderShop
	local rebirth = makePanel("Rebirth", "REBIRTH", C.Accent, 520, 460)
	Ui.list(rebirth.body, 10)
	rebirth.render = renderRebirth
	local daily = makePanel("Daily", "DAILY REWARDS", C.Blue, 560, 460)
	Ui.list(daily.body, 10)
	daily.render = renderDaily
	local index = makePanel("Index", "INDEX", C.Purple, 680, 560)
	Ui.list(index.body, 10)
	index.render = renderIndex
	buildCodes()
	local settings = makePanel("Settings", "SETTINGS", C.Grey, 480, 340)
	Ui.list(settings.body, 10)
	settings.render = renderSettings

	HudController.openPanel = MenuController.open

	ClientState.ProfileChanged:Connect(function(profile)
		local panel = openName and panels[openName]
		-- The Index rebuilds 3D previews, so only refresh it when it is opened.
		if panel and panel.render and openName ~= "Index" and openName ~= "Settings" then
			panel.render(profile)
		end
	end)
end

return MenuController
