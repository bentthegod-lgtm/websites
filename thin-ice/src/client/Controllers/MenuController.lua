--[[
	MenuController - one window with tabs:
	  Wardrobe  outfits and lanterns (coins / level / Robux / VIP), with 3D previews
	  Shop      the optional Robux items (Thermos Flask, cosmetics, VIP)
	  Daily     login streak reward and today's goals
	  Codes     promo codes
	  Board     most escapes
	  Settings  volumes, scare effects, camera shake, sneak toggle
	  Invite    invite friends (SocialService)
	Every button only sends a request; the server validates and answers with a Notify.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local InputController = require(script.Parent.InputController)

local MenuController = {}

MenuController.TABS = { "Wardrobe", "Shop", "Daily", "Codes", "Board", "Settings", "Invite" }

local C = Ui.Colors
local gui, body, tabBar, content
local current = "Wardrobe"
local tabButtons = {}

local function owned(kind, id)
	local p = ClientState.profile
	return p ~= nil and p.owned ~= nil and p.owned[kind .. ":" .. id] == true
end

local function sourceText(def)
	if def.Source == "Coins" then
		return Format.short(def.Cost) .. " coins"
	elseif def.Source == "Level" then
		return "Reach level " .. def.Level
	elseif def.Source == "Product" then
		return "Robux (Shop)"
	elseif def.Source == "Pass" then
		return "VIP pass"
	end
	return "Free"
end

local function card(parent, order, height)
	local f = Ui.panel({ LayoutOrder = order, Size = UDim2.new(1, -8, 0, height or 96), BackgroundColor3 = C.PanelLight, Parent = parent }, 10)
	Ui.padding(f, 10, 8)
	return f
end

local function cosmeticCard(parent, order, kind, id, def)
	local f = card(parent, order, 110)
	local p = ClientState.profile
	local equipped = p and p.cosmetics and p.cosmetics[kind] == id
	if kind == "Outfit" then
		Ui.kidIcon(f, def, nil, 90, { Position = UDim2.fromOffset(0, 0) })
	else
		local outfit = CosmeticConfig.Outfits[p and p.cosmetics and p.cosmetics.Outfit or "Classic"] or CosmeticConfig.Outfits.Classic
		Ui.kidIcon(f, outfit, def.Color, 90, { Position = UDim2.fromOffset(0, 0) })
	end
	Ui.title(def.Name, { Position = UDim2.fromOffset(100, 4), Size = UDim2.new(1, -250, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, Parent = f })
	Ui.label(sourceText(def), { Position = UDim2.fromOffset(100, 34), Size = UDim2.new(1, -250, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, TextSize = 14, Parent = f })
	local button
	if equipped then
		button = Ui.button("EQUIPPED", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 38) }, C.PanelLighter)
	elseif owned(kind, id) then
		button = Ui.button("EQUIP", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 38) }, C.Accent)
		button.Activated:Connect(function()
			Net.event("Equip"):FireServer(kind, id)
		end)
	elseif def.Source == "Coins" then
		button = Ui.button("BUY " .. Format.short(def.Cost), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 38) }, C.Warm)
		button.Activated:Connect(function()
			Net.event("BuyCosmetic"):FireServer(kind, id)
		end)
	else
		button = Ui.button("LOCKED", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 38) }, C.PanelLighter)
	end
	button.Name = "Action"
	button.Parent = f
	return f
end

local RENDER = {}

function RENDER.Wardrobe(list)
	Ui.title("OUTFITS", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = list })
	for i, id in ipairs(CosmeticConfig.OutfitOrder) do
		cosmeticCard(list, i, "Outfit", id, CosmeticConfig.Outfits[id])
	end
	Ui.title("LANTERNS", { LayoutOrder = 100, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = list })
	for i, id in ipairs(CosmeticConfig.LanternOrder) do
		cosmeticCard(list, 100 + i, "Lantern", id, CosmeticConfig.Lanterns[id])
	end
end

function RENDER.Shop(list)
	Ui.label("Everything here is optional. Friends can always thaw you for free.", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Dim, TextSize = 14, Parent = list })
	local items = {}
	for _, product in ipairs(ShopConfig.Products) do
		table.insert(items, product)
	end
	for _, pass in ipairs(ShopConfig.Passes) do
		table.insert(items, pass)
	end
	for i, item in ipairs(items) do
		local f = card(list, i, 84)
		Ui.title(item.Name, { Size = UDim2.new(1, -150, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, Parent = f })
		Ui.label(item.Description, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -150, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = f })
		local isVip = item.PassId ~= nil
		local ownedVip = isVip and ClientState.profile and ClientState.profile.vip
		local b = Ui.button(if ownedVip then "OWNED" else ("R$ " .. item.Robux), { Name = "Buy", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 40) }, if ownedVip then C.PanelLighter else C.Green)
		b.Parent = f
		if not ownedVip then
			b.Activated:Connect(function()
				Net.event("ShopBuy"):FireServer(item.Key)
			end)
		end
	end
	local flasks = ClientState.profile and ClientState.profile.boosts and ClientState.profile.boosts.Flask or 0
	Ui.label("Thermos Flasks: " .. flasks, { LayoutOrder = 99, Size = UDim2.new(1, 0, 0, 24), Font = Ui.Fonts.Bold, TextColor3 = C.Warm, Parent = list })
end

function RENDER.Daily(list)
	local daily = ClientState.profile and ClientState.profile.daily
	local f = card(list, 1, 110)
	Ui.title("DAILY REWARD", { Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = f })
	if daily then
		Ui.label(string.format("Streak: %d day%s", daily.streak or 0, if daily.streak == 1 then "" else "s"), { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -150, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = f })
		local b = Ui.button(if daily.canClaim then ("CLAIM " .. tostring(daily.reward)) else "CLAIMED", { Name = "Claim", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(140, 42) }, if daily.canClaim then C.Warm else C.PanelLighter)
		b.Parent = f
		if daily.canClaim then
			b.Activated:Connect(function()
				Net.event("ClaimDaily"):FireServer()
			end)
		end
	end
	Ui.title("TODAY'S GOALS", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = list })
	for i, goal in ipairs(ClientState.profile and ClientState.profile.goals or {}) do
		local g = card(list, 2 + i, 56)
		Ui.label(goal.text, { Size = UDim2.new(1, -170, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, Parent = g })
		Ui.label(if goal.done then "DONE" else string.format("%d / %d  (+%d)", goal.progress, goal.target, goal.coins), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 160, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = if goal.done then C.Green else C.Warm, Font = Ui.Fonts.Bold, Parent = g })
	end
end

function RENDER.Codes(list)
	local f = card(list, 1, 120)
	Ui.title("ENTER A CODE", { Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = f })
	local box = Ui.new("TextBox", { Name = "CodeBox", Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, -150, 0, 42), BackgroundTransparency = 0, BackgroundColor3 = C.Panel, PlaceholderText = "code", Text = "", ClearTextOnFocus = false, TextSize = 18, Parent = f })
	Ui.corner(box, 8)
	local b = Ui.button("REDEEM", { Name = "Redeem", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 36), Size = UDim2.fromOffset(130, 42) }, C.Accent)
	b.Parent = f
	b.Activated:Connect(function()
		Net.event("RedeemCode"):FireServer(box.Text)
	end)
	Ui.label("Codes are announced in the group and on the game page.", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Dim, TextSize = 14, Parent = list })
end

function RENDER.Board(list)
	Ui.title("MOST ESCAPES", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = list })
	local rows = ClientState.leaderboard or {}
	if #rows == 0 then
		Ui.label("No escapes recorded yet (or the board is offline). Be the first!", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), TextColor3 = C.Dim, Parent = list })
	end
	for i, row in ipairs(rows) do
		local f = card(list, i, 40)
		local mine = row.userId == Players.LocalPlayer.UserId
		Ui.label(string.format("%d. %s", i, row.name), { Size = UDim2.new(1, -100, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, TextColor3 = if mine then C.Warm else C.Text, Parent = f })
		Ui.label(Format.short(row.value), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 90, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = f })
	end
end

local SLIDERS = { { "Master", "Master volume" }, { "Music", "Music" }, { "Effects", "Effects" }, { "Ambient", "Wind & ambience" } }
local TOGGLES = {
	{ "ScareEffects", "Scare effects (flash + close-up when caught)" },
	{ "CameraShake", "Camera shake" },
	{ "ReducedEffects", "Reduced effects (less snow and fog)" },
	{ "ToggleSneak", "C toggles sneak (off = hold C)" },
}

function RENDER.Settings(list)
	for i, s in ipairs(SLIDERS) do
		local key = s[1]
		local f = card(list, i, 50)
		Ui.label(s[2], { Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, Parent = f })
		local value = ClientState.setting(key) or 1
		local minus = Ui.button("-", { Name = "Minus", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -110, 0.5, 0), Size = UDim2.fromOffset(36, 32) }, C.PanelLighter)
		minus.Parent = f
		local label = Ui.label(string.format("%d%%", math.floor(value * 100 + 0.5)), { Name = "Value", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -48, 0.5, 0), Size = UDim2.fromOffset(60, 32), Parent = f })
		local plus = Ui.button("+", { Name = "Plus", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(36, 32) }, C.PanelLighter)
		plus.Parent = f
		local function change(delta)
			local v = math.clamp((ClientState.setting(key) or 1) + delta, 0, 1)
			ClientState.applySettings({ [key] = v })
			label.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
			ClientState.saveSettings()
		end
		minus.Activated:Connect(function()
			change(-0.1)
		end)
		plus.Activated:Connect(function()
			change(0.1)
		end)
	end
	for i, t in ipairs(TOGGLES) do
		local key = t[1]
		local f = card(list, 10 + i, 50)
		Ui.label(t[2], { Size = UDim2.new(1, -120, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Font = Ui.Fonts.Bold, Parent = f })
		local on = ClientState.setting(key) == true
		local b = Ui.button(if on then "ON" else "OFF", { Name = "Toggle", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(90, 34) }, if on then C.Green else C.PanelLighter)
		b.Parent = f
		b.Activated:Connect(function()
			local v = not (ClientState.setting(key) == true)
			ClientState.applySettings({ [key] = v })
			ClientState.saveSettings()
			MenuController.render()
		end)
	end
end

function RENDER.Invite(list)
	local f = card(list, 1, 120)
	Ui.title("BRING FRIENDS", { Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = f })
	Ui.label(string.format("Thin Ice is better with friends: they thaw you, you thaw them. Up to %d per server.", GameConfig.MaxPlayers), { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -150, 0, 50), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = f })
	local b = Ui.button("INVITE", { Name = "Invite", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 42) }, C.Green)
	b.Parent = f
	b.Activated:Connect(function()
		pcall(function()
			SocialService:PromptGameInvite(Players.LocalPlayer)
		end)
	end)
	Ui.label("Share the code THINICE with friends for free coins.", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Dim, TextSize = 14, Parent = list })
end

function MenuController.render()
	if not content then
		return
	end
	Ui.clear(content)
	local list = Ui.list(content, 8)
	list.Name = "Layout"
	RENDER[current](content)
	for name, b in pairs(tabButtons) do
		Ui.setButtonColor(b, if name == current then C.Accent else C.PanelLighter)
	end
end

function MenuController.setTab(name)
	if RENDER[name] then
		current = name
	end
end

function MenuController.open(tab)
	if tab then
		MenuController.setTab(tab)
	end
	Ui.openWindow("Menu")
	MenuController.render()
end

function MenuController.toggle()
	if Ui.isOpen("Menu") then
		Ui.closeWindow("Menu")
	else
		MenuController.open()
	end
end

function MenuController.content()
	return content
end

function MenuController.init()
	gui = Ui.screen("IceMenu", 10)
	local _, b = Ui.window(gui, "Menu", "THIN ICE", 760, 540)
	body = b
	tabBar = Ui.new("Frame", { Name = "Tabs", Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, Parent = body })
	Ui.list(tabBar, 6, Enum.FillDirection.Horizontal)
	for i, name in ipairs(MenuController.TABS) do
		local t = Ui.button(name, { Name = name, LayoutOrder = i, Size = UDim2.fromOffset(98, 34), TextSize = 14 }, C.PanelLighter)
		t.Parent = tabBar
		t.Activated:Connect(function()
			MenuController.setTab(name)
			MenuController.render()
		end)
		tabButtons[name] = t
	end
	content = Ui.scroll(body, { Name = "Content", Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46) })
	InputController.menuToggle = MenuController.toggle
	ClientState.ProfileChanged:Connect(function()
		if Ui.isOpen("Menu") then
			MenuController.render()
		end
	end)
	ClientState.LeaderboardChanged:Connect(function()
		if Ui.isOpen("Menu") and current == "Board" then
			MenuController.render()
		end
	end)
end

return MenuController
