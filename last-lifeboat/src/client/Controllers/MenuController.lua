--[[
	MenuController - one window with tabs:
	  Shop      the optional Robux items (Life Jacket, Rescue Flare, coin packs, passes)
	  Upgrades  coin upgrades: Lung Capacity, Swim Speed, Grip, Loot Slots, Climb Speed
	  Daily     login streak reward and this session's goals
	  Codes     promo codes
	  Board     Total Escapes and Loot Banked
	  Stats     your numbers
	  Settings  volumes, camera shake, reduced effects, tutorial hints
	  Invite    invite friends (SocialService)
	Every button only sends a request; the server validates and answers with a Notify.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Upgrades = require(Shared.Upgrades)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local InputController = require(script.Parent.InputController)
local HudController = require(script.Parent.HudController)

local MenuController = {}

MenuController.TABS = { "Shop", "Upgrades", "Daily", "Codes", "Board", "Stats", "Settings", "Invite" }

local C = Ui.Colors
local gui, body, content, coinLabel
local current = "Shop"
local tabButtons = {}

local function card(parent, order, height)
	local f = Ui.panel({ LayoutOrder = order, Size = UDim2.new(1, -8, 0, height or 84), BackgroundColor3 = C.PanelLight, Parent = parent }, 10)
	Ui.padding(f, 12, 8)
	return f
end

local function header(parent, order, text)
	return Ui.title(text, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = parent })
end

local function rightButton(parent, text, color, fn, name)
	local b = Ui.button(text, { Name = name or "Action", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(136, 40) }, color)
	b.Parent = parent
	if fn then
		b.Activated:Connect(fn)
	end
	return b
end

local RENDER = {}

function RENDER.Shop(list)
	Ui.label("Everything here is optional - free crews escape just as well.", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Dim, TextSize = 14, Parent = list })
	local p = ClientState.profile
	header(list, 1, "SUPPLIES")
	for i, product in ipairs(ShopConfig.Products) do
		local f = card(list, 1 + i, 78)
		Ui.title(product.Name, { Size = UDim2.new(1, -160, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, Parent = f })
		Ui.label(product.Description, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -160, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = f })
		rightButton(f, "R$ " .. product.Robux, C.Green, function()
			Net.event("ShopBuy"):FireServer(product.Key)
		end, "Buy")
	end
	header(list, 20, "PASSES")
	for i, pass in ipairs(ShopConfig.Passes) do
		local f = card(list, 20 + i, if pass.Key == "Captain" then 96 else 78)
		local owned = p and p.passes and p.passes[pass.Key]
		local textX = if pass.Key == "Captain" then 86 else 0
		if pass.Key == "Captain" then
			Ui.crewIcon(f, true, 80, { Position = UDim2.fromOffset(0, 0) })
		end
		Ui.title(pass.Name, { Position = UDim2.fromOffset(textX, 0), Size = UDim2.new(1, -160 - textX, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = if pass.Key == "VIP" then Color3.fromRGB(255, 205, 70) else C.Text, Parent = f })
		Ui.label(pass.Description, { Position = UDim2.fromOffset(textX, 26), Size = UDim2.new(1, -160 - textX, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = f })
		rightButton(f, if owned then "OWNED" else "R$ " .. pass.Robux, if owned then C.PanelLighter else C.Green, if owned then nil else function()
			Net.event("ShopBuy"):FireServer(pass.Key)
		end, "Buy")
	end
	local boosts = p and p.boosts or {}
	Ui.label(string.format("Life Jackets: %d    Rescue Flares: %d", boosts.LifeJacket or 0, boosts.Flare or 0), { LayoutOrder = 99, Size = UDim2.new(1, 0, 0, 24), Font = Ui.Fonts.Bold, TextColor3 = C.Warm, Parent = list })
end

function RENDER.Upgrades(list)
	local p = ClientState.profile
	Ui.label("Spend coins from escapes. Every upgrade has 5 levels.", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Dim, TextSize = 14, Parent = list })
	for i, key in ipairs(GameConfig.UpgradeOrder) do
		local def = GameConfig.Upgrades[key]
		local level = p and p.upgrades and p.upgrades[key] or 0
		local f = card(list, i, 84)
		Ui.title(string.format("%s  (Lv %d/5)", def.Name, level), { Size = UDim2.new(1, -160, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, Parent = f })
		local now = Upgrades.effect(key, level)
		local nextValue = if level < Upgrades.MaxLevel then Upgrades.effect(key, level + 1) else nil
		Ui.label(string.format("%s%s%s", Format.stat(now), def.Unit, if nextValue then "  ->  " .. Format.stat(nextValue) .. def.Unit else "  (max)"), { Name = "Effect", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -160, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Cream, TextSize = 15, Parent = f })
		local pips = Ui.new("Frame", { Name = "Pips", Position = UDim2.fromOffset(0, 50), Size = UDim2.fromOffset(150, 12), BackgroundTransparency = 1, Parent = f })
		Ui.list(pips, 4, Enum.FillDirection.Horizontal)
		for j = 1, Upgrades.MaxLevel do
			local pip = Ui.new("Frame", { LayoutOrder = j, Size = UDim2.fromOffset(26, 10), BackgroundColor3 = if j <= level then C.Accent else C.Panel, Parent = pips })
			Ui.corner(pip, 4)
		end
		local cost = Upgrades.cost(key, level)
		rightButton(f, if cost then Format.short(cost) .. " coins" else "MAXED", if cost then C.Accent else C.PanelLighter, if cost then function()
			Net.event("BuyUpgrade"):FireServer(key)
		end else nil, "Buy")
	end
end

function RENDER.Daily(list)
	local p = ClientState.profile
	local daily = p and p.daily
	local f = card(list, 1, 110)
	Ui.title("DAILY REWARD", { Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = f })
	if daily then
		Ui.label(string.format("Streak: %d day%s - come back every day for bigger rewards", daily.streak or 0, if daily.streak == 1 then "" else "s"), { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -160, 0, 40), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = f })
		rightButton(f, if daily.canClaim then ("CLAIM " .. tostring(daily.reward)) else "CLAIMED", if daily.canClaim then C.Accent else C.PanelLighter, if daily.canClaim then function()
			Net.event("ClaimDaily"):FireServer()
		end else nil, "Claim")
	end
	header(list, 2, "SESSION GOALS")
	for i, goal in ipairs(p and p.goals or {}) do
		local g = card(list, 2 + i, 50)
		Ui.label(goal.text, { Size = UDim2.new(1, -170, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, Parent = g })
		Ui.label(if goal.done then "DONE" else string.format("%d / %d  (+%d)", goal.progress, goal.target, goal.coins), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 160, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = if goal.done then C.Green else C.Warm, Font = Ui.Fonts.Bold, Parent = g })
	end
end

function RENDER.Codes(list)
	local f = card(list, 1, 110)
	Ui.title("ENTER A CODE", { Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = f })
	local box = Ui.new("TextBox", { Name = "CodeBox", Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, -160, 0, 42), BackgroundTransparency = 0, BackgroundColor3 = C.Panel, PlaceholderText = "code", Text = "", ClearTextOnFocus = false, TextSize = 18, Parent = f })
	Ui.corner(box, 8)
	local b = Ui.button("REDEEM", { Name = "Redeem", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 36), Size = UDim2.fromOffset(136, 42) }, C.Accent)
	b.Parent = f
	b.Activated:Connect(function()
		Net.event("RedeemCode"):FireServer(box.Text)
	end)
	Ui.label("Codes are posted on the game page and in the group. Try RELEASE!", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Dim, TextSize = 14, Parent = list })
end

function RENDER.Board(list)
	for col, key in ipairs({ "Escapes", "Banked" }) do
		header(list, col * 100, if key == "Escapes" then "TOTAL ESCAPES" else "LOOT BANKED")
		local rows = ClientState.leaderboard and ClientState.leaderboard[key] or {}
		if #rows == 0 then
			Ui.label("No records yet (or the board is offline). Be the first!", { LayoutOrder = col * 100 + 1, Size = UDim2.new(1, 0, 0, 24), TextColor3 = C.Dim, Parent = list })
		end
		for i, row in ipairs(rows) do
			local f = card(list, col * 100 + i, 38)
			local mine = row.userId == Players.LocalPlayer.UserId
			Ui.label(string.format("%d. %s", i, row.name), { Size = UDim2.new(1, -100, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, TextColor3 = if mine then C.Accent else C.Text, Parent = f })
			Ui.label(Format.short(row.value), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 90, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = f })
		end
	end
end

local STAT_ROWS = {
	{ "Escapes", "Escapes" },
	{ "Rounds", "Rounds played" },
	{ "LootBanked", "Loot banked (value)" },
	{ "BestBank", "Best single haul" },
	{ "Revives", "Teammates revived" },
	{ "Legendaries", "Legendary finds" },
	{ "FullCrews", "Full Crew launches" },
	{ "LostAtSea", "Lost at sea" },
	{ "Earned", "Coins earned" },
}

function RENDER.Stats(list)
	local stats = ClientState.profile and ClientState.profile.stats or {}
	for i, row in ipairs(STAT_ROWS) do
		local f = card(list, i, 38)
		Ui.label(row[2], { Size = UDim2.new(1, -120, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, Parent = f })
		Ui.label(Format.exact(stats[row[1]] or 0), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 110, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Accent, Font = Ui.Fonts.Bold, Parent = f })
	end
	local unlocked = {}
	for _, key in ipairs(GameConfig.ShipOrder) do
		local def = GameConfig.Ships[key]
		table.insert(unlocked, string.format("%s: %s", def.Name, if (stats.Escapes or 0) >= def.UnlockEscapes then "unlocked" else string.format("%d/%d escapes", stats.Escapes or 0, def.UnlockEscapes)))
	end
	Ui.label(table.concat(unlocked, "   "), { LayoutOrder = 50, Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = list })
end

local SLIDERS = { { "Master", "Master volume" }, { "Music", "Music" }, { "Effects", "Effects" }, { "Ambient", "Sea & ship ambience" }, { "UI", "Menu clicks" } }
local TOGGLES = {
	{ "CameraShake", "Camera shake on lurches" },
	{ "ReducedEffects", "Reduced effects (less flashing and blur)" },
	{ "Hints", "Tutorial hints" },
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
		rightButton(f, if on then "ON" else "OFF", if on then C.Green else C.PanelLighter, function()
			ClientState.applySettings({ [key] = not (ClientState.setting(key) == true) })
			ClientState.saveSettings()
			MenuController.render()
		end, "Toggle")
	end
end

function RENDER.Invite(list)
	local f = card(list, 1, 110)
	Ui.title("BRING YOUR CREW", { Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = f })
	Ui.label(string.format("Doors need two hands, downed friends need a revive, and a Full Crew pays x1.25. Up to %d per server.", GameConfig.MaxPlayers), { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -160, 0, 54), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = f })
	rightButton(f, "INVITE", C.Green, function()
		pcall(function()
			local canInvite = SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
			if canInvite then
				SocialService:PromptGameInvite(Players.LocalPlayer)
			end
		end)
	end, "Invite")
	Ui.label("Like the game? Give it a thumbs up - new codes drop at like milestones!", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Dim, TextSize = 14, Parent = list })
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
	local p = ClientState.profile
	coinLabel.Text = string.format("%s coins", Format.short(p and p.coins or 0))
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
	gui = Ui.screen("LifeboatMenu", 10)
	local _, b = Ui.window(gui, "Menu", "LAST LIFEBOAT", 800, 560)
	body = b
	coinLabel = Ui.title("", { Name = "Coins", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 0, -38), Size = UDim2.fromOffset(200, 30), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 18, TextColor3 = C.Accent, Parent = body })
	local tabBar = Ui.new("Frame", { Name = "Tabs", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = body })
	Ui.list(tabBar, 5, Enum.FillDirection.Horizontal)
	for i, name in ipairs(MenuController.TABS) do
		local t = Ui.button(name, { Name = name, LayoutOrder = i, Size = UDim2.fromOffset(91, 32), TextSize = 13 }, C.PanelLighter)
		t.Parent = tabBar
		t.Activated:Connect(function()
			MenuController.setTab(name)
			MenuController.render()
		end)
		tabButtons[name] = t
	end
	content = Ui.scroll(body, { Name = "Content", Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44) })
	InputController.menuToggle = MenuController.toggle
	HudController.onMenu = MenuController.open
	ClientState.MenuRequested:Connect(MenuController.open)
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
