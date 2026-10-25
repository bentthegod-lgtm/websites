--[[
	MenuController - the SHOP button (always on the HUD) and the hallway side bar:
	SHOP (Robux: Clout packs, Pizza Party, escapes, crates, game passes), UPGRADES (Clout),
	LOCKER (cosmetics), CRATES (with odds), DAILY, CODES, TEACHER'S PET toggle and INVITE.

	Mouse, touch and gamepad (buttons are selectable; Select focuses the side bar).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local Net = require(Shared.Net)
local ShopConfig = require(Shared.Config.ShopConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local AudioAssets = require(Shared.Config.AudioAssets)
local AudioUtil = require(Shared.AudioUtil)
local CrateRoll = require(Shared.CrateRoll)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local MenuController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui, sidebar, shopButton
local panels = {}
local current
local shopTab = "Clout"
local lockerCategory = "Skin"
local codeResultLabel
local reelFrame

local function gamepadActive()
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	return UserInputService.GamepadEnabled and ok and last ~= nil and string.sub(last.Name, 1, 7) == "Gamepad"
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

local function row(body, order, height)
	local frame = Ui.panel({ Size = UDim2.new(1, -8, 0, height or 64), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.2, LayoutOrder = order, ZIndex = 11, Parent = body })
	Ui.padding(frame, 8)
	return frame
end

local function rowText(frame, title, description, titleColor)
	Ui.label(title, { Font = Ui.Fonts.Title, TextSize = 18, TextColor3 = titleColor or C.Text, Size = UDim2.new(1, -150, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = frame })
	Ui.label(description or "", { TextSize = 13, TextColor3 = C.Dim, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -150, 1, -22), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 12, Parent = frame })
end

local function rowButton(frame, text, color, onClick)
	local button = Ui.button(text, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 40), TextSize = 16, ZIndex = 12, Parent = frame }, color)
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

local function tabs(body, list, selected, onPick)
	local bar = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 38), BackgroundTransparency = 1, LayoutOrder = 0, ZIndex = 11, Parent = body })
	for i, entry in ipairs(list) do
		local b = Ui.button(entry.label, { Position = UDim2.new((i - 1) / #list, 2, 0, 0), Size = UDim2.new(1 / #list, -4, 1, 0), TextSize = 14, ZIndex = 12, Parent = bar }, if entry.key == selected then C.Accent else C.PanelLight)
		b.Activated:Connect(function()
			onPick(entry.key)
			MenuController.refresh()
		end)
	end
end

---------------------------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------------------------

local function makePanel(key, title, width, height)
	local frame = Ui.panel({ Name = key, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(width or 620, height or 540), Visible = false, ZIndex = 10, Parent = gui })
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
	local list = {}
	for _, key in ipairs(ShopConfig.CategoryOrder) do
		table.insert(list, { key = key, label = ShopConfig.CategoryNames[key] })
	end
	tabs(body, list, shopTab, function(key)
		shopTab = key
	end)
	local order = 1
	local passes = profile and profile.passes or {}
	if shopTab == "GamePasses" then
		for _, pass in ipairs(ShopConfig.Passes) do
			local r = row(body, order, 70)
			rowText(r, pass.Name, pass.Description, Ui.rgb(pass.Color))
			if passes[pass.Key] then
				rowButton(r, "OWNED", C.PanelLight)
			else
				rowButton(r, "R$ " .. pass.Robux, C.Good:Lerp(Color3.new(0, 0, 0), 0.2), function()
					Net.event("ShopBuy"):FireServer(pass.Key)
				end)
			end
			order += 1
		end
	else
		for _, product in ipairs(ShopConfig.Products) do
			if product.Category == shopTab then
				local hidden = product.Random and profile ~= nil and profile.randomItemsAllowed == false
				if not hidden then
					local r = row(body, order, if product.Key == "PizzaParty" then 84 else 70)
					local desc = product.Description
					if product.Key == "PizzaParty" then
						local queued = workspace:GetAttribute("PA_PizzaQueued") or 0
						if workspace:GetAttribute("PA_Pizza") then
							desc ..= "  [PIZZA CLASS RIGHT NOW!]"
						elseif queued > 0 then
							desc ..= string.format("  [%d pizza class(es) queued]", queued)
						end
					elseif product.Key == "DetentionPass" or product.Key == "HallPass" or product.Key == "AnswerPeek" then
						local tokenKey = if product.Key == "AnswerPeek" then "Peek" else product.Key
						desc ..= string.format("  (you have %d)", profile and profile.tokens and profile.tokens[tokenKey] or 0)
					end
					rowText(r, product.Name, desc, Ui.rgb(product.Color))
					rowButton(r, "R$ " .. product.Robux, Ui.rgb(product.Color):Lerp(Color3.new(0, 0, 0), 0.35), function()
						Net.event("ShopBuy"):FireServer(product.Key)
					end)
					order += 1
				end
			end
		end
		if shopTab == "Crates" then
			if profile and profile.randomItemsAllowed == false then
				Ui.label("Crates bought with Robux aren't available in your region. You can still open Locker Crates with Clout in CRATES.", { TextSize = 13, TextColor3 = C.Dim, TextWrapped = true, Size = UDim2.new(1, -8, 0, 36), LayoutOrder = order, ZIndex = 11, Parent = body })
			else
				Ui.label("See the exact odds in the CRATES panel before you buy.", { TextSize = 13, TextColor3 = C.Dim, Size = UDim2.new(1, -8, 0, 20), LayoutOrder = order, ZIndex = 11, Parent = body })
			end
			order += 1
		end
	end
	Ui.label("Fair play: every upgrade can be earned with Clout. Pass bonuses are capped (max x2.2 Clout).", { TextSize = 12, TextColor3 = C.Dim, TextWrapped = true, Size = UDim2.new(1, -8, 0, 32), LayoutOrder = 100, ZIndex = 11, Parent = body })
end

function renderers.Upgrades(body, profile)
	local upgrades = profile and profile.upgrades or {}
	local passes = profile and profile.passes or {}
	local stats = profile and profile.phone
	if stats then
		Ui.label(string.format("Your phone: %s  |  %d answers/snap  |  scan %.1fs  |  glow %d%%  |  shutter %d%%  |  hide %.2fs%s", stats.phoneName, stats.answers or 2, stats.scan or 6, stats.glow * 100, stats.noise * 100, stats.hide, if stats.watch then "  |  " .. stats.watch.name else ""), { TextSize = 13, TextColor3 = C.Gold, TextWrapped = true, Size = UDim2.new(1, -8, 0, 34), LayoutOrder = 0, ZIndex = 11, Parent = body })
	end
	for i, key in ipairs(UpgradeConfig.Order) do
		local def = UpgradeConfig[key]
		local tier = upgrades[key] or def.Start
		local cur = def.Tiers[tier]
		local price, _, nextDef = Economy.nextUpgrade(UpgradeConfig, key, tier)
		local r = row(body, i, 72)
		local note = ""
		if key == "Phone" and passes.ProPhone then
			note = " (Pro Phone pass active)"
		elseif key == "Earbuds" and passes.SilentMode then
			note = " (Silent Mode: at least tier " .. UpgradeConfig.SilentModeEarbudsTier .. ")"
		elseif key == "Hide" and passes.ExtraHide then
			note = " (+Extra Hide Speed)"
		end
		rowText(r, string.format("%s: %s", def.Name, cur and cur.Name or "?"), def.Description .. note .. (if nextDef then "  Next: " .. nextDef.Name else ""), C.Accent2)
		if price then
			local affordable = profile and profile.clout >= price
			rowButton(r, Format.short(price) .. " Clout", if affordable then C.Gold:Lerp(Color3.new(0, 0, 0), 0.3) else C.PanelLight, function()
				Net.event("BuyUpgrade"):FireServer(key)
			end)
		else
			rowButton(r, "MAXED", C.PanelLight)
		end
	end
end

function renderers.Locker(body, profile)
	local list = {}
	for _, category in ipairs(CosmeticConfig.Categories) do
		table.insert(list, { key = category, label = CosmeticConfig.CategoryNames[category] })
	end
	tabs(body, list, lockerCategory, function(key)
		lockerCategory = key
	end)
	local order = 1
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Category == lockerCategory then
			local owned = profile and profile.owned and profile.owned[item.Category] and profile.owned[item.Category][item.Id]
			local equipped = profile and profile.equipped and profile.equipped[item.Category] == item.Id
			local r = row(body, order, 56)
			if item.Colors or item.Color then
				local swatch = Ui.new("Frame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = Ui.rgb(item.Color or item.Colors[1]), ZIndex = 12, Parent = r })
				Ui.corner(swatch, 8)
				if item.Colors then
					Ui.gradient(swatch, Ui.rgb(item.Colors[1]), Ui.rgb(item.Colors[2]), 90)
				end
			end
			local title = Ui.label(item.Name .. (if owned then "" else " (locked)"), { Font = Ui.Fonts.Title, TextSize = 17, TextColor3 = rarityColor(item.Rarity), Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -190, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = r })
			title.Name = "Title"
			Ui.label(item.Rarity .. (if item.Price then "" else " - crate only"), { TextSize = 12, TextColor3 = C.Dim, Position = UDim2.fromOffset(40, 22), Size = UDim2.new(1, -190, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = r })
			if equipped then
				rowButton(r, "EQUIPPED", C.Good:Lerp(Color3.new(0, 0, 0), 0.3))
			elseif owned then
				rowButton(r, "EQUIP", C.PanelLight, function()
					Net.event("Equip"):FireServer(item.Category, item.Id)
				end)
			elseif item.Price then
				rowButton(r, Format.number(item.Price) .. " Clout", C.Gold:Lerp(Color3.new(0, 0, 0), 0.3), function()
					Net.event("BuyCosmetic"):FireServer(item.Category, item.Id)
				end)
			else
				rowButton(r, "CRATES", C.PanelLight, function()
					MenuController.open("Crates")
				end)
			end
			order += 1
		end
	end
	Ui.label("Cosmetics are visual only. Classmates see your phone skin when it's out!", { TextSize = 12, TextColor3 = C.Dim, Size = UDim2.new(1, -8, 0, 18), LayoutOrder = order, ZIndex = 11, Parent = body })
end

function renderers.Crates(body, profile)
	local pity = profile and profile.pity or 0
	Ui.label(string.format("Pity: Legendary or better guaranteed within %d opens (%d to go). Duplicates refund Clout.", CosmeticConfig.PityEvery, CosmeticConfig.PityEvery - pity), { TextSize = 13, TextColor3 = C.Dim, TextWrapped = true, Size = UDim2.new(1, -8, 0, 32), LayoutOrder = 0, ZIndex = 11, Parent = body })
	for i, key in ipairs(CosmeticConfig.CrateOrder) do
		local crate = CosmeticConfig.Crates[key]
		local restricted = crate.Product and profile ~= nil and profile.randomItemsAllowed == false
		if not restricted then
			local odds = CrateRoll.odds(crate, CosmeticConfig)
			local r = row(body, i, 60 + #odds * 18)
			Ui.label(crate.Name, { Font = Ui.Fonts.Title, TextSize = 22, TextColor3 = Ui.rgb(crate.Color), Size = UDim2.new(1, -150, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = r })
			for j, o in ipairs(odds) do
				Ui.label(string.format("%s  %.1f%%", o.rarity, o.percent), { Font = Ui.Fonts.Bold, TextSize = 14, TextColor3 = rarityColor(o.rarity), Position = UDim2.fromOffset(6, 26 + (j - 1) * 18), Size = UDim2.new(1, -150, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = r })
			end
			local label
			if crate.Product then
				local robux = 0
				for _, p in ipairs(ShopConfig.Products) do
					if p.Key == crate.Product then
						robux = p.Robux
					end
				end
				label = "R$ " .. robux
			else
				label = Format.number(crate.CloutPrice) .. " Clout"
			end
			rowButton(r, label, Ui.rgb(crate.Color):Lerp(Color3.new(0, 0, 0), 0.35), function()
				Net.event("OpenCrate"):FireServer(key)
			end)
		end
	end
end

function renderers.Daily(body, profile)
	local daily = profile and profile.daily or {}
	Ui.label("Come back every day to grow your streak. Miss a day and it resets!", { TextSize = 14, TextColor3 = C.Dim, Size = UDim2.new(1, -8, 0, 20), LayoutOrder = 0, ZIndex = 11, Parent = body })
	local strip = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 90), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 11, Parent = body })
	local n = #ProgressionConfig.DailyRewards
	local streak = daily.streak or 0
	local currentIndex = ((math.max(streak, 1) - 1) % n) + 1
	for i, amount in ipairs(ProgressionConfig.DailyRewards) do
		local highlight = i == currentIndex and (daily.claimable or streak > 0)
		local box = Ui.panel({ Position = UDim2.new((i - 1) / n, 2, 0, 0), Size = UDim2.new(1 / n, -4, 1, 0), BackgroundColor3 = if highlight then C.Accent else C.PanelLight, ZIndex = 12, Parent = strip })
		Ui.label("DAY " .. i, { Font = Ui.Fonts.Title, TextSize = 14, Size = UDim2.new(1, 0, 0, 24), ZIndex = 13, Parent = box })
		Ui.label(tostring(amount), { Font = Ui.Fonts.Title, TextSize = 22, TextColor3 = C.Gold, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 26), ZIndex = 13, Parent = box })
	end
	local r = row(body, 2, 60)
	if daily.claimable then
		rowText(r, string.format("Day %d reward ready!", daily.streak or 1), string.format("+%d Clout (VIP: +50%%)", daily.amount or 0), C.Gold)
		rowButton(r, "CLAIM", C.Good:Lerp(Color3.new(0, 0, 0), 0.2), function()
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
	Ui.label("Enter a code. Like the game for more codes!", { TextSize = 14, TextColor3 = C.Dim, Size = UDim2.new(1, -8, 0, 20), LayoutOrder = 0, ZIndex = 11, Parent = body })
	local r = row(body, 1, 60)
	local box = Ui.new("TextBox", {
		Name = "CodeBox",
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
	rowButton(r, "REDEEM", C.Good:Lerp(Color3.new(0, 0, 0), 0.2), function()
		Net.event("RedeemCode"):FireServer(box.Text)
	end)
	codeResultLabel = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 15, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = 2, ZIndex = 11, Parent = body })
end

function renderers.Pet(body, profile)
	local on = profile and profile.settings and profile.settings.Pet == true
	Ui.label("TEACHER'S PET MODE", { Font = Ui.Fonts.Title, TextSize = 22, TextColor3 = C.Warn, Size = UDim2.new(1, -8, 0, 28), LayoutOrder = 0, ZIndex = 11, Parent = body })
	Ui.label("Pets get a REPORT button in class: tell on a classmate whose phone is OUT for +6 Clout and +25% pop quiz rewards. Max 3 reports per class, 20 s cooldown. A false report (their phone was away) makes the teacher suspicious of YOU. Switching applies from the next class.", { TextSize = 14, TextWrapped = true, TextColor3 = C.Dim, Size = UDim2.new(1, -8, 0, 90), LayoutOrder = 1, ZIndex = 11, Parent = body })
	local r = row(body, 2, 60)
	rowText(r, if on then "You are a Teacher's Pet" else "You are a regular student", if on then "[PET] shows on your name tag." else "Phones out, solidarity forever.")
	rowButton(r, if on then "TURN OFF" else "TURN ON", if on then C.Danger else C.Warn:Lerp(Color3.new(0, 0, 0), 0.3), function()
		Net.event("SetPet"):FireServer(not on)
	end)
end

---------------------------------------------------------------------------------------------
-- Crate reveal
---------------------------------------------------------------------------------------------

local function playReveal(result)
	if reelFrame then
		reelFrame:Destroy()
	end
	reelFrame = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 220), BackgroundColor3 = C.Panel, ZIndex = 30, Parent = gui })
	Ui.stroke(reelFrame, rarityColor(result.rarity), 0, 4)
	local title = Ui.label("OPENING...", { Font = Ui.Fonts.Title, TextSize = 30, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 30), ZIndex = 31, Parent = reelFrame })
	local sub = Ui.label("", { Font = Ui.Fonts.Bold, TextSize = 16, TextColor3 = C.Dim, Position = UDim2.fromOffset(0, 130), Size = UDim2.new(1, 0, 0, 24), ZIndex = 31, Parent = reelFrame })
	local order = CosmeticConfig.Rarities.Order
	for i = 1, 10 do
		task.delay(i * i * 0.018, function()
			if title.Parent then
				local rarity = order[(i % #order) + 1]
				title.Text = string.upper(rarity) .. "?"
				title.TextColor3 = rarityColor(rarity)
			end
		end)
	end
	task.delay(2, function()
		if not title.Parent then
			return
		end
		title.Text = string.format("%s\n%s", string.upper(result.rarity), result.name)
		title.TextColor3 = rarityColor(result.rarity)
		sub.Text = if result.duplicate then string.format("Duplicate - refunded %d Clout", result.refund) else "NEW! Equip it in the LOCKER."
		TweenService:Create(reelFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(460, 240) }):Play()
		task.delay(2.6, function()
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
	if not panels[key] then
		return
	end
	if current and panels[current] then
		panels[current].frame.Visible = false
	end
	current = key
	panels[key].frame.Visible = true
	MenuController.refresh()
	if gamepadActive() then
		GuiService.SelectedObject = panels[key].close
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

local function updateVisibility()
	local hallway = ClientState.status() == "Hallway"
	sidebar.Visible = hallway
	if not hallway and current and current ~= "Shop" then
		MenuController.close()
	end
end

function MenuController.init()
	gui = Ui.screen("PA_Menu", player:WaitForChild("PlayerGui"), 5)
	shopButton = Ui.button("SHOP", { Name = "ShopButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 52), Size = UDim2.fromOffset(120, 46), TextSize = 22, Parent = gui }, C.Gold:Lerp(Color3.new(0, 0, 0), 0.2))
	shopButton.Activated:Connect(function()
		AudioUtil.play(AudioAssets.Click)
		if current == "Shop" then
			MenuController.close()
		else
			MenuController.open("Shop")
		end
	end)
	sidebar = Ui.new("Frame", { Name = "Sidebar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -24), Size = UDim2.fromOffset(150, 340), BackgroundTransparency = 1, Parent = gui })
	local layout = Ui.list(sidebar, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	local buttons = {
		{ "UPGRADES", "Upgrades", C.Accent2 },
		{ "LOCKER", "Locker", C.Accent },
		{ "CRATES", "Crates", Color3.fromRGB(170, 100, 255) },
		{ "DAILY", "Daily", C.Good },
		{ "CODES", "Codes", C.PanelLight },
		{ "PET MODE", "Pet", C.Warn },
	}
	for i, spec in ipairs(buttons) do
		local b = Ui.button(spec[1], { Name = spec[2] .. "Button", Size = UDim2.new(1, 0, 0, 40), TextSize = 17, LayoutOrder = i, Parent = sidebar }, spec[3]:Lerp(Color3.new(0, 0, 0), 0.25))
		b.Activated:Connect(function()
			AudioUtil.play(AudioAssets.Click)
			if current == spec[2] then
				MenuController.close()
			else
				MenuController.open(spec[2])
			end
		end)
	end
	local inviteButton = Ui.button("BRING YOUR CLASS", { Name = "InviteButton", Size = UDim2.new(1, 0, 0, 40), TextSize = 14, LayoutOrder = 20, Parent = sidebar }, C.Accent2:Lerp(Color3.new(0, 0, 0), 0.45))
	inviteButton.Activated:Connect(invite)

	makePanel("Shop", "SHOP")
	makePanel("Upgrades", "UPGRADES")
	makePanel("Locker", "LOCKER")
	makePanel("Crates", "CRATES")
	makePanel("Daily", "DAILY STREAK", 620, 330)
	makePanel("Codes", "CODES", 520, 250)
	makePanel("Pet", "TEACHER'S PET", 560, 300)

	local shownDaily = false
	ClientState.ProfileChanged:Connect(function(profile)
		if current then
			MenuController.refresh()
		end
		if profile and profile.daily and profile.daily.claimable and not shownDaily and ClientState.status() == "Hallway" then
			shownDaily = true
			MenuController.open("Daily")
		end
	end)
	ClientState.CrateResult:Connect(playReveal)
	ClientState.CodeResult:Connect(function(ok, message)
		if codeResultLabel and codeResultLabel.Parent then
			codeResultLabel.Text = message
			codeResultLabel.TextColor3 = if ok then C.Good else C.Danger
		end
		ClientState.Notified:Fire(message, if ok then "good" else "warn")
	end)
	ClientState.Effect:Connect(function(kind)
		if kind == "OpenShop" then
			MenuController.open("Shop")
		end
	end)
	player:GetAttributeChangedSignal("PA_Status"):Connect(updateVisibility)
	updateVisibility()

	ContextActionService:BindAction("PA_Menu", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			local target = if sidebar.Visible then sidebar:FindFirstChildWhichIsA("TextButton") else shopButton
			GuiService.SelectedObject = if GuiService.SelectedObject then nil else target
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonSelect)
end

MenuController._playReveal = playReveal
MenuController._renderers = renderers

return MenuController
