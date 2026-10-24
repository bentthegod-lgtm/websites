--[[
	MenuController - lobby side bar and panels: Robux SHOP, CRATES (with visible odds and a
	spin reel), ABILITIES (coins only, lobby-only loadout), LOCKER (cosmetics), DAILY
	reward, CODES, SETTINGS, READY toggle and friend INVITE.

	Works with mouse, touch and gamepad (buttons are selectable; the Select button focuses
	the side bar).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local Net = require(Shared.Net)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local AudioUtil = require(Shared.AudioUtil)
local CrateRoll = require(Shared.CrateRoll)
local Clock = require(Shared.Clock)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local MenuController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui, sidebar, readyButton
local panels = {}
local current
local lockerCategory = "ParryFx"
local codeResultLabel
local reelFrame

local function gamepadActive()
	return UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function rarityColor(rarity)
	local r = CosmeticConfig.Rarities[rarity]
	return if r then Ui.rgb(r.Color) else C.Text
end

local function clear(body)
	for _, child in ipairs(body:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function section(body, text, order)
	return Ui.label(text, { Font = Ui.Fonts.Title, TextSize = 20, TextColor3 = C.Accent2, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, ZIndex = 11, Parent = body })
end

local function row(body, order, height)
	local frame = Ui.panel({ Size = UDim2.new(1, -8, 0, height or 64), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.2, LayoutOrder = order, ZIndex = 11, Parent = body })
	Ui.padding(frame, 8)
	return frame
end

local function rowText(frame, title, description, titleColor)
	Ui.label(title, { Font = Ui.Fonts.Title, TextSize = 18, TextColor3 = titleColor or C.Text, Size = UDim2.new(1, -150, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = frame })
	Ui.label(description or "", { TextSize = 13, TextColor3 = C.Dim, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -150, 1, -22), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 12, Parent = frame })
end

local function rowButton(frame, text, color, onClick, widthOffset)
	local button = Ui.button(text, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, widthOffset or 0, 0.5, 0), Size = UDim2.fromOffset(130, 38), TextSize = 16, ZIndex = 12, Parent = frame }, color)
	if onClick then
		button.Activated:Connect(function()
			AudioUtil.play(AudioAssets.Click)
			onClick()
		end)
	else
		button.AutoButtonColor = false
		button.BackgroundTransparency = 0.5
	end
	return button
end

---------------------------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------------------------

local function makePanel(key, title, width, height)
	local frame = Ui.panel({ Name = key, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(width or 620, height or 560), Visible = false, ZIndex = 10, Parent = gui })
	Ui.stroke(frame, C.Accent, 0.2, 3)
	Ui.label(title, { Font = Ui.Fonts.Title, TextSize = 30, TextColor3 = C.Accent, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -140, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Parent = frame })
	local close = Ui.button("CLOSE", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(100, 36), ZIndex = 12, Parent = frame }, C.Danger)
	close.Activated:Connect(function()
		MenuController.close()
	end)
	local body = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 1, -68),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 11,
		Parent = frame,
	})
	Ui.list(body, 8)
	panels[key] = { frame = frame, body = body, close = close }
	return panels[key]
end

local renderers = {}

function renderers.Shop(body, profile)
	section(body, "COINS & PREMIUM SPINS", 1)
	local order = 2
	local passes = profile and profile.passes or {}
	for _, product in ipairs(ShopConfig.Products) do
		if product.Key ~= "ExplosionParty" then
			local r = row(body, order)
			rowText(r, product.Name, product.Description, C.Gold)
			rowButton(r, "R$ " .. product.Robux, C.Good, function()
				Net.event("ShopBuy"):FireServer(product.Key)
			end)
			order += 1
		end
	end
	section(body, "SOCIAL", order)
	order += 1
	for _, product in ipairs(ShopConfig.Products) do
		if product.Key == "ExplosionParty" then
			local r = row(body, order, 74)
			local untilTime = workspace:GetAttribute("RR_PartyUntil") or 0
			local left = untilTime - Clock.now()
			local desc = product.Description
			if left > 0 then
				desc ..= string.format("  [ACTIVE: %d:%02d left, started by %s]", math.floor(left / 60), math.floor(left % 60), tostring(workspace:GetAttribute("RR_PartyBy") or "?"))
			end
			rowText(r, product.Name, desc, C.Accent)
			rowButton(r, "R$ " .. product.Robux, C.Accent, function()
				Net.event("ShopBuy"):FireServer(product.Key)
			end)
			order += 1
		end
	end
	section(body, "GAME PASSES", order)
	order += 1
	for _, pass in ipairs(ShopConfig.Passes) do
		local r = row(body, order)
		rowText(r, pass.Name, pass.Description, C.Accent2)
		if passes[pass.Key] then
			rowButton(r, "OWNED", C.PanelLight)
		else
			rowButton(r, "R$ " .. pass.Robux, C.Good, function()
				Net.event("BuyPass"):FireServer(pass.Key)
			end)
		end
		order += 1
	end
	Ui.label("Fair play: nothing sold here changes parry timing, ball speed or ability power. Abilities are coins-only.", { TextSize = 12, TextColor3 = C.Dim, TextWrapped = true, Size = UDim2.new(1, -8, 0, 32), LayoutOrder = order, ZIndex = 11, Parent = body })
end

function renderers.Crates(body, profile)
	local pity = profile and profile.pity or 0
	Ui.label(string.format("Pity: a Legendary or better is guaranteed within %d opens (%d to go).  Duplicates refund coins.", CosmeticConfig.PityEvery, CosmeticConfig.PityEvery - pity), { TextSize = 13, TextColor3 = C.Dim, TextWrapped = true, Size = UDim2.new(1, -8, 0, 32), LayoutOrder = 0, ZIndex = 11, Parent = body })
	for i, key in ipairs(CosmeticConfig.CrateOrder) do
		local crate = CosmeticConfig.Crates[key]
		local odds = CrateRoll.odds(crate, CosmeticConfig)
		local r = row(body, i, 60 + #odds * 18)
		Ui.label(crate.Name, { Font = Ui.Fonts.Title, TextSize = 22, TextColor3 = Ui.rgb(crate.Color), Size = UDim2.new(1, -150, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = r })
		for j, o in ipairs(odds) do
			Ui.label(string.format("%s  %.1f%%", o.rarity, o.percent), { Font = Ui.Fonts.Bold, TextSize = 14, TextColor3 = rarityColor(o.rarity), Position = UDim2.fromOffset(6, 26 + (j - 1) * 18), Size = UDim2.new(1, -150, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = r })
		end
		local label
		if crate.SpinCurrency then
			label = string.format("SPIN (%d)", profile and profile.premiumSpins or 0)
		else
			label = Ui.formatNumber(crate.CoinPrice) .. " coins"
		end
		rowButton(r, label, Ui.rgb(crate.Color):Lerp(Color3.new(0, 0, 0), 0.3), function()
			Net.event("OpenCrate"):FireServer(key)
		end)
		if crate.SpinCurrency then
			local buy = rowButton(r, "Get spins", C.Good, function()
				MenuController.open("Shop")
			end)
			buy.Position = UDim2.new(1, 0, 1, -20)
		end
	end
end

function renderers.Abilities(body, profile)
	local maxSlots = profile and profile.maxSlots or 1
	Ui.label(string.format("Slots: %d%s.  Loadout can only be changed in the lobby.", maxSlots, if maxSlots < AbilityConfig.MaxSlotsWithPass then " (Extra Slot pass: 2)" else ""), { TextSize = 13, TextColor3 = C.Dim, Size = UDim2.new(1, -8, 0, 20), LayoutOrder = 0, ZIndex = 11, Parent = body })
	for i, id in ipairs(AbilityConfig.Order) do
		local def = AbilityConfig.Abilities[id]
		local r = row(body, i, 78)
		local cd = if def.Passive then "passive, once per round" else string.format("%ds cooldown", def.Cooldown)
		rowText(r, string.format("%s  [%s]", def.Name, def.Rarity), def.Description .. "  (" .. cd .. ")", rarityColor(def.Rarity))
		local owned = profile and profile.abilities and profile.abilities[id]
		if not owned then
			rowButton(r, if def.Price > 0 then Ui.formatNumber(def.Price) .. " coins" else "FREE", C.Gold, function()
				Net.event("BuyAbility"):FireServer(id)
			end)
		else
			local slotIndex = profile.loadout and table.find(profile.loadout, id)
			for slot = 1, maxSlots do
				local text = if slotIndex == slot then "SLOT " .. slot .. " ON" else "EQUIP " .. slot
				local b = rowButton(r, text, if slotIndex == slot then C.Good else C.PanelLight, function()
					Net.event("EquipAbility"):FireServer(slot, id)
				end, -(maxSlots - slot) * 136)
				if maxSlots > 1 then
					b.Size = UDim2.fromOffset(130, 34)
				end
			end
		end
	end
end

function renderers.Locker(body, profile)
	local tabs = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 40), BackgroundTransparency = 1, LayoutOrder = 0, ZIndex = 11, Parent = body })
	for i, category in ipairs(CosmeticConfig.Categories) do
		local b = Ui.button(CosmeticConfig.CategoryNames[category], { Position = UDim2.new((i - 1) / 3, 2, 0, 0), Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 15, ZIndex = 12, Parent = tabs }, if category == lockerCategory then C.Accent else C.PanelLight)
		b.Activated:Connect(function()
			lockerCategory = category
			MenuController.refresh()
		end)
	end
	local order = 1
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Category == lockerCategory then
			local owned = profile and profile.owned and profile.owned[item.Category] and profile.owned[item.Category][item.Id]
			local equipped = profile and profile.equipped and profile.equipped[item.Category] == item.Id
			local r = row(body, order, 56)
			local desc = item.Rarity .. (if item.Pass then " - Game Pass exclusive" else "") .. (if item.Style then " - " .. item.Style else "")
			rowText(r, if owned then item.Name else item.Name .. " (locked)", desc, rarityColor(item.Rarity))
			if equipped then
				rowButton(r, "EQUIPPED", C.Good)
			elseif owned then
				rowButton(r, "EQUIP", C.PanelLight, function()
					Net.event("EquipCosmetic"):FireServer(item.Category, item.Id)
				end)
			elseif item.Pass then
				rowButton(r, "GET PASS", C.Accent2, function()
					MenuController.open("Shop")
				end)
			else
				rowButton(r, "CRATES", C.PanelLight, function()
					MenuController.open("Crates")
				end)
			end
			order += 1
		end
	end
	Ui.label("Cosmetics are visual only: no stat advantage.", { TextSize = 12, TextColor3 = C.Dim, Size = UDim2.new(1, -8, 0, 18), LayoutOrder = order, ZIndex = 11, Parent = body })
end

function renderers.Daily(body, profile)
	local daily = profile and profile.daily or {}
	Ui.label("Log in every day to grow your streak. Miss a day and it resets.", { TextSize = 14, TextColor3 = C.Dim, Size = UDim2.new(1, -8, 0, 20), LayoutOrder = 0, ZIndex = 11, Parent = body })
	local strip = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 90), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 11, Parent = body })
	local n = #ProgressionConfig.DailyRewards
	local streak = daily.streak or 0
	local currentIndex = ((math.max(streak, 1) - 1) % n) + 1
	for i, amount in ipairs(ProgressionConfig.DailyRewards) do
		local highlight = (daily.claimable and i == currentIndex) or (not daily.claimable and i == currentIndex and streak > 0)
		local box = Ui.panel({ Position = UDim2.new((i - 1) / n, 2, 0, 0), Size = UDim2.new(1 / n, -4, 1, 0), BackgroundColor3 = if highlight then C.Accent else C.PanelLight, ZIndex = 12, Parent = strip })
		Ui.label("DAY " .. i, { Font = Ui.Fonts.Title, TextSize = 14, Size = UDim2.new(1, 0, 0, 24), ZIndex = 13, Parent = box })
		Ui.label(tostring(amount), { Font = Ui.Fonts.Title, TextSize = 22, TextColor3 = C.Gold, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 26), ZIndex = 13, Parent = box })
	end
	local r = row(body, 2, 60)
	if daily.claimable then
		rowText(r, string.format("Day %d reward ready!", daily.streak or 1), string.format("+%d coins", daily.amount or 0), C.Gold)
		rowButton(r, "CLAIM", C.Good, function()
			Net.event("ClaimDaily"):FireServer()
		end)
	else
		local hours = math.floor((daily.nextIn or 0) / 3600)
		local minutes = math.floor(((daily.nextIn or 0) % 3600) / 60)
		rowText(r, string.format("Streak: %d day(s)", streak), string.format("Next reward in %dh %dm", hours, minutes))
		rowButton(r, "CLAIMED", C.PanelLight)
	end
end

function renderers.Codes(body)
	Ui.label("Enter a code (hint: like the game for one!).", { TextSize = 14, TextColor3 = C.Dim, Size = UDim2.new(1, -8, 0, 20), LayoutOrder = 0, ZIndex = 11, Parent = body })
	local r = row(body, 1, 60)
	local box = Ui.new("TextBox", {
		PlaceholderText = "CODE",
		Text = "",
		ClearTextOnFocus = false,
		Font = Ui.Fonts.Title,
		TextSize = 20,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0,
		Size = UDim2.new(1, -150, 1, 0),
		ZIndex = 12,
		Parent = r,
	})
	Ui.corner(box, 8)
	rowButton(r, "REDEEM", C.Good, function()
		Net.event("RedeemCode"):FireServer(box.Text)
	end)
	codeResultLabel = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 15, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = 2, ZIndex = 11, Parent = body })
end

local function settingRow(body, order, title, valueText, onMinus, onPlus)
	local r = row(body, order, 50)
	rowText(r, title, valueText)
	if onPlus then
		rowButton(r, "+", C.PanelLight, onPlus).Size = UDim2.fromOffset(60, 34)
		rowButton(r, "-", C.PanelLight, onMinus, -66).Size = UDim2.fromOffset(60, 34)
	else
		rowButton(r, "TOGGLE", C.PanelLight, onMinus)
	end
end

function renderers.Settings(body, profile)
	local s = table.clone(profile and profile.settings or { Music = 0.5, Sfx = 1, Shake = true, AutoReady = true })
	local function save()
		Net.event("SaveSettings"):FireServer(s)
		if profile then
			profile.settings = s
		end
		MenuController.applySettings(s)
		MenuController.refresh()
	end
	settingRow(body, 1, "Music volume", string.format("%d%%", math.floor(s.Music * 100 + 0.5)), function()
		s.Music = math.clamp(s.Music - 0.1, 0, 1)
		save()
	end, function()
		s.Music = math.clamp(s.Music + 0.1, 0, 1)
		save()
	end)
	settingRow(body, 2, "Sound effects", string.format("%d%%", math.floor(s.Sfx * 100 + 0.5)), function()
		s.Sfx = math.clamp(s.Sfx - 0.1, 0, 1)
		save()
	end, function()
		s.Sfx = math.clamp(s.Sfx + 0.1, 0, 1)
		save()
	end)
	settingRow(body, 3, "Camera shake", if s.Shake then "On" else "Off", function()
		s.Shake = not s.Shake
		save()
	end)
	settingRow(body, 4, "Auto-ready for rounds", if s.AutoReady then "On" else "Off", function()
		s.AutoReady = not s.AutoReady
		Net.event("SetReady"):FireServer(s.AutoReady)
		save()
	end)
	Ui.label("Controls: F / Left Click / R1 / PARRY button to parry. Q/E (X/Y on gamepad) for abilities. Aim with the camera.", { TextSize = 13, TextColor3 = C.Dim, TextWrapped = true, Size = UDim2.new(1, -8, 0, 36), LayoutOrder = 5, ZIndex = 11, Parent = body })
end

function MenuController.applySettings(s)
	AudioUtil.volumeScale = s.Sfx or 1
end

---------------------------------------------------------------------------------------------
-- Crate reel
---------------------------------------------------------------------------------------------

local function playReel(result)
	if reelFrame then
		reelFrame:Destroy()
	end
	reelFrame = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 230), BackgroundColor3 = C.Panel, ZIndex = 30, Parent = gui })
	Ui.stroke(reelFrame, C.Gold, 0.1, 3)
	local window = Ui.new("Frame", { Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 0, 90), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 31, Parent = reelFrame })
	local strip = Ui.new("Frame", { Size = UDim2.new(0, #result.reel * 130, 1, 0), BackgroundTransparency = 1, ZIndex = 31, Parent = window })
	for i, id in ipairs(result.reel) do
		local item = CrateRoll.find(CosmeticConfig, id)
		local card = Ui.panel({ Position = UDim2.fromOffset((i - 1) * 130 + 4, 4), Size = UDim2.fromOffset(122, 82), BackgroundColor3 = rarityColor(item and item.Rarity or "Common"):Lerp(Color3.new(0, 0, 0), 0.55), ZIndex = 32, Parent = strip })
		Ui.stroke(card, rarityColor(item and item.Rarity or "Common"), 0, 2)
		Ui.label(item and item.Name or id, { Font = Ui.Fonts.Bold, TextSize = 14, TextWrapped = true, Size = UDim2.fromScale(1, 1), ZIndex = 33, Parent = card })
	end
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(4, 102), BackgroundColor3 = C.Gold, ZIndex = 34, Parent = reelFrame })
	local resultLabel = Ui.label("", { Font = Ui.Fonts.Title, TextSize = 26, Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 34), ZIndex = 31, Parent = reelFrame })
	local sub = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = C.Dim, Position = UDim2.fromOffset(0, 176), Size = UDim2.new(1, 0, 0, 22), ZIndex = 31, Parent = reelFrame })
	-- Center the last card under the marker.
	local finalX = -((#result.reel - 1) * 130 + 65) + 310
	local spin = TweenService:Create(strip, TweenInfo.new(3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(finalX, 0) })
	spin:Play()
	for i = 1, 12 do
		task.delay(i * i * 0.02, function()
			AudioUtil.play(AudioAssets.CrateTick)
		end)
	end
	task.delay(3.1, function()
		local item = CrateRoll.find(CosmeticConfig, result.itemId)
		resultLabel.Text = string.format("%s %s!", string.upper(result.rarity), item and item.Name or result.itemId)
		resultLabel.TextColor3 = rarityColor(result.rarity)
		sub.Text = if result.duplicate then string.format("Duplicate - refunded %d coins", result.refund) else "NEW! Equip it in the LOCKER."
		AudioUtil.play(AudioAssets.CrateReveal)
		task.delay(2.5, function()
			if reelFrame then
				reelFrame:Destroy()
				reelFrame = nil
			end
		end)
	end)
end

---------------------------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------------------------

function MenuController.refresh()
	if not current then
		return
	end
	local p = panels[current]
	clear(p.body)
	renderers[current](p.body, ClientState.profile)
end

function MenuController.open(key)
	if current and panels[current] then
		panels[current].frame.Visible = false
	end
	current = key
	local p = panels[key]
	p.frame.Visible = true
	MenuController.refresh()
	if gamepadActive() then
		GuiService.SelectedObject = p.close
	end
end

function MenuController.close()
	if current and panels[current] then
		panels[current].frame.Visible = false
	end
	current = nil
	if gamepadActive() then
		GuiService.SelectedObject = nil
	end
end

function MenuController.isOpen(key)
	return current == key
end

local function invite()
	local okCan, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if okCan and can then
		local ok = pcall(function()
			SocialService:PromptGameInvite(player)
		end)
		if ok then
			Net.event("InviteSent"):FireServer()
		end
	else
		ClientState.Notified:Fire("Invites aren't available right now.", "warn")
	end
end

local function updateReady()
	local isReady = player:GetAttribute("RR_Ready") ~= false
	readyButton.Text = if isReady then "READY: ON" else "READY: OFF"
	readyButton.BackgroundColor3 = if isReady then C.Good:Lerp(Color3.new(0, 0, 0), 0.3) else C.PanelLight
end

local function updateVisibility()
	sidebar.Visible = ClientState.status() ~= "Arena"
	if ClientState.status() == "Arena" then
		MenuController.close()
	end
end

function MenuController.init()
	gui = Ui.screen("RR_Menu", player:WaitForChild("PlayerGui"), 5)
	sidebar = Ui.new("Frame", { Name = "Sidebar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.56, 0), Size = UDim2.fromOffset(150, 430), BackgroundTransparency = 1, Parent = gui })
	Ui.list(sidebar, 6)
	local buttons = {
		{ "SHOP", "Shop", C.Gold },
		{ "CRATES", "Crates", Color3.fromRGB(150, 90, 255) },
		{ "ABILITIES", "Abilities", C.Accent2 },
		{ "LOCKER", "Locker", C.Accent },
		{ "DAILY", "Daily", C.Good },
		{ "CODES", "Codes", C.PanelLight },
		{ "SETTINGS", "Settings", C.PanelLight },
	}
	for i, spec in ipairs(buttons) do
		local b = Ui.button(spec[1], { Size = UDim2.new(1, 0, 0, 42), TextSize = 18, LayoutOrder = i, Parent = sidebar }, spec[3]:Lerp(Color3.new(0, 0, 0), 0.25))
		b.Activated:Connect(function()
			AudioUtil.play(AudioAssets.Click)
			if current == spec[2] then
				MenuController.close()
			else
				MenuController.open(spec[2])
			end
		end)
	end
	local inviteButton = Ui.button("INVITE (+coins)", { Size = UDim2.new(1, 0, 0, 36), TextSize = 15, LayoutOrder = 20, Parent = sidebar }, C.Accent2:Lerp(Color3.new(0, 0, 0), 0.4))
	inviteButton.Activated:Connect(invite)
	readyButton = Ui.button("READY: ON", { Size = UDim2.new(1, 0, 0, 40), TextSize = 16, LayoutOrder = 21, Parent = sidebar }, C.Good)
	readyButton.Activated:Connect(function()
		Net.event("SetReady"):FireServer(player:GetAttribute("RR_Ready") == false)
	end)

	makePanel("Shop", "SHOP")
	makePanel("Crates", "CRATES")
	makePanel("Abilities", "ABILITIES")
	makePanel("Locker", "LOCKER")
	makePanel("Daily", "DAILY REWARD", 620, 340)
	makePanel("Codes", "CODES", 520, 260)
	makePanel("Settings", "SETTINGS", 560, 420)

	local shownDaily = false
	ClientState.ProfileChanged:Connect(function(profile)
		if profile and profile.settings then
			MenuController.applySettings(profile.settings)
		end
		if current then
			MenuController.refresh()
		end
		if profile and profile.daily and profile.daily.claimable and not shownDaily and ClientState.status() ~= "Arena" then
			shownDaily = true
			MenuController.open("Daily")
		end
	end)
	ClientState.CrateResult:Connect(playReel)
	ClientState.CodeResult:Connect(function(ok, message)
		if codeResultLabel and codeResultLabel.Parent then
			codeResultLabel.Text = message
			codeResultLabel.TextColor3 = if ok then C.Good else C.Danger
		end
		ClientState.Notified:Fire(message, if ok then "good" else "warn")
	end)
	player:GetAttributeChangedSignal("RR_Ready"):Connect(updateReady)
	player:GetAttributeChangedSignal("RR_Status"):Connect(updateVisibility)
	updateReady()
	updateVisibility()

	-- Crate pedestal in the lobby opens the crate panel.
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby", 30)
		local pedestal = lobby and lobby:WaitForChild("CratePedestal", 10)
		local crate = pedestal and pedestal:WaitForChild("Crate", 10)
		local prompt = crate and crate:WaitForChild("CratePrompt", 10)
		if prompt then
			prompt.Triggered:Connect(function()
				MenuController.open("Crates")
			end)
		end
	end)

	-- Gamepad: Select focuses the side bar.
	ContextActionService:BindAction("RR_Menu", function(_, state)
		if state == Enum.UserInputState.Begin and sidebar.Visible then
			local first = sidebar:FindFirstChildWhichIsA("TextButton")
			GuiService.SelectedObject = if GuiService.SelectedObject then nil else first
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonSelect)
end

-- For the harness.
MenuController._playReel = playReel

return MenuController
