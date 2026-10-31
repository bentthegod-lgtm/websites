--[[
	MenuController - one window with tabs:
	  Garage    pick your kart (cosmetic only - every kart has identical physics)
	  Shop      the optional Robux items (Stage 1: placeholders; cosmetic shop in Stage 7)
	  Daily     login streak reward
	  Codes     promo codes (try RELEASE and CHAOS)
	  Board     Most Wins and Fastest Lap on Chaos City
	  Stats     your numbers and best laps
	  Settings  volumes, camera shake, speed lines, reduced effects, mobile stick
	  Invite    invite friends (SocialService)
	Every button only sends a request; the server validates and answers with a Notify.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("ChaosKarts")
local GameConfig = require(Shared.Config.GameConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local VehicleRegistry = require(Shared.Vehicles.Registry)
local Progress = require(Shared.Progress)

local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)
local InputController = require(script.Parent.InputController)
local HudController = require(script.Parent.HudController)

local MenuController = {}

MenuController.TABS = { "Garage", "Shop", "Daily", "Codes", "Board", "Stats", "Settings", "Invite" }

local C = Ui.Colors
local gui, body, content, coinLabel
local current = "Garage"
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

function RENDER.Garage(list)
	Ui.label("Every kart drives EXACTLY the same - pick the one you like the look of. More karts arrive in Stage 2 (25 total).", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 36), TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = list })
	local p = ClientState.profile
	for i, def in ipairs(VehicleRegistry.all()) do
		local f = card(list, i, 110)
		Ui.kartIcon(f, def.Id, 96, { Position = UDim2.fromOffset(0, -4) })
		Ui.title(def.Name, { Position = UDim2.fromOffset(104, 6), Size = UDim2.new(1, -260, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 20, Parent = f })
		Ui.label(def.Rarity .. " - cosmetic", { Position = UDim2.fromOffset(104, 36), Size = UDim2.new(1, -260, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, TextSize = 14, Parent = f })
		local selected = p and p.vehicle == def.Id
		rightButton(f, if selected then "SELECTED" else "SELECT", if selected then C.PanelLighter else C.Green, if selected then nil else function()
			Net.event("SelectVehicle"):FireServer(def.Id)
		end, "Select")
	end
	Ui.label(string.format("Coming in Stage 2: %d more karts.", #VehicleRegistry.PLANNED - #VehicleRegistry.ORDER), { LayoutOrder = 99, Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Dim, TextSize = 14, Parent = list })
end

function RENDER.Shop(list)
	Ui.label("Everything here is cosmetic or coins - nothing changes how a kart drives. The full cosmetic shop arrives in Stage 7.", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 36), TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = list })
	local p = ClientState.profile
	header(list, 1, "COINS")
	for i, product in ipairs(ShopConfig.Products) do
		local f = card(list, 1 + i, 78)
		Ui.title(product.Name, { Size = UDim2.new(1, -160, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, Parent = f })
		Ui.label(product.Description, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -160, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = f })
		rightButton(f, "R$ " .. product.Robux, C.Green, function()
			Net.event("ShopBuy"):FireServer(product.Key)
		end, "Buy")
	end
	header(list, 20, "COSMETIC PASSES")
	for i, pass in ipairs(ShopConfig.Passes) do
		local f = card(list, 20 + i, 78)
		local owned = p and p.passes and p.passes[pass.Key]
		Ui.title(pass.Name, { Size = UDim2.new(1, -160, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = if pass.Key == "VIP" then C.Accent else C.Text, Parent = f })
		Ui.label(pass.Description, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -160, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = f })
		rightButton(f, if owned then "OWNED" else "R$ " .. pass.Robux, if owned then C.PanelLighter else C.Green, if owned then nil else function()
			Net.event("ShopBuy"):FireServer(pass.Key)
		end, "Buy")
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
	Ui.label("Codes are posted on the game page and in the group. Try RELEASE and CHAOS!", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 22), TextColor3 = C.Dim, TextSize = 14, Parent = list })
end

function RENDER.Board(list)
	for col, key in ipairs({ "Wins", "BestLap" }) do
		header(list, col * 100, if key == "Wins" then "MOST WINS" else "FASTEST LAP - CHAOS CITY")
		local rows = ClientState.leaderboard and ClientState.leaderboard[key] or {}
		if #rows == 0 then
			Ui.label("No records yet (or the board is offline). Be the first!", { LayoutOrder = col * 100 + 1, Size = UDim2.new(1, 0, 0, 24), TextColor3 = C.Dim, Parent = list })
		end
		for i, row in ipairs(rows) do
			local f = card(list, col * 100 + i, 38)
			local mine = row.userId == Players.LocalPlayer.UserId
			Ui.label(string.format("%d. %s", i, row.name), { Size = UDim2.new(1, -120, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, TextColor3 = if mine then C.Accent else C.Text, Parent = f })
			Ui.label(if key == "BestLap" then Format.raceTime(row.value / 1000) else Format.short(row.value), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 110, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = f })
		end
	end
end

local STAT_ROWS = {
	{ "Races", "Races" },
	{ "Wins", "Wins" },
	{ "Podiums", "Podiums (top 3)" },
	{ "Finishes", "Finishes" },
	{ "Laps", "Laps driven" },
	{ "BestFinish", "Best finish" },
	{ "Earned", "Coins earned" },
}

function RENDER.Stats(list)
	local p = ClientState.profile
	local stats = p and p.stats or {}
	local level = p and p.level or 1
	local f0 = card(list, 0, 44)
	Ui.title(string.format("LEVEL %d", level), { Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 20, TextColor3 = C.Accent, Parent = f0 })
	Ui.label(string.format("%d / %d XP", p and p.levelXp or 0, p and p.levelNeed or Progress.xpForLevel(1)), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = f0 })
	for i, row in ipairs(STAT_ROWS) do
		local f = card(list, i, 38)
		Ui.label(row[2], { Size = UDim2.new(1, -120, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.Fonts.Bold, Parent = f })
		Ui.label(Format.exact(stats[row[1]] or 0), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 110, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Accent, Font = Ui.Fonts.Bold, Parent = f })
	end
	local best = p and p.bestLaps and p.bestLaps.ChaosCity
	Ui.label("Best lap, Chaos City: " .. Format.raceTime(best), { LayoutOrder = 50, Size = UDim2.new(1, 0, 0, 28), Font = Ui.Fonts.Bold, TextColor3 = C.Line, Parent = list })
end

local SLIDERS = { { "Master", "Master volume" }, { "Music", "Music" }, { "Effects", "Effects" }, { "Engine", "Engines" }, { "UI", "Menu clicks" } }
local TOGGLES = {
	{ "CameraShake", "Camera shake (landings, walls, events)" },
	{ "SpeedLines", "Speed lines" },
	{ "ReducedEffects", "Reduced effects (less flashing and shake)" },
	{ "MobileStick", "Mobile: slider stick instead of steer buttons" },
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
	Ui.title("BRING YOUR FRIENDS", { Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = C.Accent, Parent = f })
	Ui.label(string.format("Races are better with friends - up to %d racers per server, bots fill the rest of the grid.", GameConfig.MaxPlayers), { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -160, 0, 54), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextColor3 = C.Dim, TextSize = 14, Parent = f })
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
	gui = Ui.screen("KartMenu", 10)
	local _, b = Ui.window(gui, "Menu", "CHAOS KARTS", 800, 560)
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
