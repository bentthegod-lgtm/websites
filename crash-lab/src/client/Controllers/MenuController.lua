--[[
	MenuController - the main window with tabs:
	  Upgrades    four categories of upgrade cards (level, price, current -> next effect)
	  Machines    the three launchers: owned / unlock requirement + price / select
	  LabLog      personal records, daily challenges (UTC reset timer), achievements,
	              Lab Certification (prestige, with a confirmation listing what resets),
	              duel challenges and codes
	  Locker      dummy designs, trails and launch effects (coins / achievements / optional
	              Robux cosmetics)
	  Facilities  the facility progression (only the Industrial Crash Lab is built yet)
	  Settings    volumes, sensitivity, camera shake, follow cam, reduced effects, tutorial
	  Help        controls for PC, gamepad and touch
	Buttons only send requests; the server validates and replies with a new profile.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local Economy = require(Shared.Economy)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local MachineConfig = require(Shared.Config.MachineConfig)
local CourseConfig = require(Shared.Config.CourseConfig)
local QuestConfig = require(Shared.Config.QuestConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local ScoringConfig = require(Shared.Config.ScoringConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)

local MenuController = {}

local C = Ui.Colors
local TABS = { "Upgrades", "Machines", "LabLog", "Locker", "Facilities", "Settings", "Help" }
local TAB_NAMES = { LabLog = "LAB LOG" }
local gui, content, tabButtons = nil, nil, {}
local currentTab = "Upgrades"
local category = UpgradeConfig.Categories[1]
local renderers = {}
local confirmFrame

local function fire(name, ...)
	Net.event(name):FireServer(...)
end

local function profileLike(p, upgrades)
	return { Upgrades = upgrades or p.upgrades, Prestige = p.prestige }
end

-- Upgrades ------------------------------------------------------------------------------

local EFFECT = {
	Power = function(s)
		return string.format("x%s launch speed", Format.stat(s.SpeedMultiplier))
	end,
	Payload = function(s)
		return s.Dummy.Name
	end,
	Cooldown = function(s)
		return string.format("-%ds cooldown", s.CooldownReduction)
	end,
	Angles = function(s)
		return if s.AngleMin == s.AngleMax then string.format("fixed %d°", s.AngleMin) else string.format("%d° - %d°", s.AngleMin, s.AngleMax)
	end,
	Precision = function(s)
		return string.format("charge x%s, spread %s°", Format.stat(s.ChargeMultiplier), Format.stat(math.floor(s.SpreadDegrees * 10) / 10))
	end,
	Durability = function(s)
		return string.format("%d impacts, x%s pts", s.ImpactCap, Format.stat(s.ImpactMultiplier))
	end,
	Spin = function(s)
		return #s.SpinModes - 1 .. " spin modes"
	end,
	Bonus = function(s)
		return string.format("x%s bonuses", Format.stat(s.BonusMultiplier))
	end,
	Challenge = function(s)
		return string.format("featured x%s", Format.stat(s.FeaturedMultiplier))
	end,
	Analyst = function(s)
		return string.format("x%s coins", Format.stat(math.floor(s.CoinMultiplier * 100) / 100))
	end,
}
MenuController.Effect = EFFECT

local function upgradeCard(parent, def, p, order)
	local level = p.upgrades[def.Key] or 0
	local price = Economy.cost(def.Key, level)
	local now = Economy.stats(profileLike(p))
	local nextLevels = table.clone(p.upgrades)
	nextLevels[def.Key] = level + 1
	local after = Economy.stats(profileLike(p, nextLevels))
	local card = Ui.panel({ BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = parent }, 10)
	local icon = Ui.new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = C.PanelLighter, Parent = card })
	Ui.corner(icon, 8)
	Ui.title(def.Icon, { Size = UDim2.fromScale(1, 1), TextSize = 13, TextColor3 = C.Accent, Parent = icon })
	Ui.title(def.Name, { Position = UDim2.fromOffset(62, 8), Size = UDim2.new(1, -70, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 15, Parent = card })
	Ui.label(if price then string.format("Level %d / %d  ->  %d", level, def.Max, level + 1) else string.format("Level %d / %d  (MAX)", level, def.Max), { Position = UDim2.fromOffset(62, 28), Size = UDim2.new(1, -70, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = C.Dim, Parent = card })
	local view = EFFECT[def.Key]
	Ui.label(if price then string.format("%s  ->  %s", view(now), view(after)) else view(now), { Position = UDim2.fromOffset(10, 60), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, Font = Ui.Fonts.Bold, TextColor3 = C.Green, Parent = card })
	Ui.label(def.Text, { Position = UDim2.fromOffset(10, 78), Size = UDim2.new(1, -124, 0, 34), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextSize = 11, TextColor3 = C.Dim, Parent = card })
	local affordable = price ~= nil and p.coins >= price
	local buy = Ui.button(if price then Format.short(price) else "MAX", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10), Size = UDim2.fromOffset(100, 32), TextSize = 14 }, if affordable then C.Accent else C.PanelLighter)
	if price and not affordable then
		buy.TextColor3 = C.Red
		buy.Text = Format.short(price) .. " (need more)"
		buy.TextSize = 10
	end
	buy.Parent = card
	buy.Activated:Connect(function()
		if price then
			fire("BuyUpgrade", def.Key)
		end
	end)
	return card
end

renderers.Upgrades = function(p)
	local side = Ui.new("Frame", { Size = UDim2.new(0, 170, 1, 0), BackgroundTransparency = 1, Parent = content })
	Ui.list(side, 6)
	for i, cat in ipairs(UpgradeConfig.Categories) do
		local b = Ui.button(string.upper(cat), { Size = UDim2.new(1, 0, 0, 36), TextSize = 12, LayoutOrder = i }, if cat == category then C.Accent else C.PanelLight)
		b.Parent = side
		b.Activated:Connect(function()
			category = cat
			MenuController.render()
		end)
	end
	Ui.label(string.format("Coins: %s", Format.exact(p.coins)), { Size = UDim2.new(1, 0, 0, 24), TextSize = 14, Font = Ui.Fonts.Bold, TextColor3 = C.Accent, LayoutOrder = 10, Parent = side })
	local scroll = Ui.scroll(content, { Position = UDim2.fromOffset(182, 0), Size = UDim2.new(1, -182, 1, 0) })
	local grid = Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(310, 122), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	grid.FillDirectionMaxCells = 2
	for i, def in ipairs(UpgradeConfig.List) do
		if def.Category == category then
			upgradeCard(scroll, def, p, i)
		end
	end
end

-- Machines ------------------------------------------------------------------------------

renderers.Machines = function(p)
	local list = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = content })
	Ui.list(list, 10, Enum.FillDirection.Horizontal)
	local stats = Economy.stats(profileLike(p))
	for i, id in ipairs(MachineConfig.Order) do
		local def = MachineConfig.ById[id]
		local owned = p.machines[id] == true
		local card = Ui.panel({ Size = UDim2.fromOffset(262, 420), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Parent = list }, 12)
		if id == p.selected then
			Ui.stroke(card, C.Accent, 2, 0)
		end
		Ui.machineIcon(card, id, 180, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6) })
		Ui.title(def.Name, { Position = UDim2.fromOffset(10, 190), Size = UDim2.new(1, -20, 0, 22), TextSize = 16, TextColor3 = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3]), Parent = card })
		Ui.label(def.Description, { Position = UDim2.fromOffset(10, 214), Size = UDim2.new(1, -20, 0, 48), TextWrapped = true, TextSize = 12, TextColor3 = C.Dim, Parent = card })
		local reach = Economy.reach(def, stats)
		local facts = string.format("Speed %d st/s  -  charge %ss\nCooldown %ds  -  max reach ~%d studs", math.floor(Economy.speed(def, stats, 1)), Format.stat(math.floor(Economy.chargeTime(def, stats) * 10) / 10), Economy.cooldown(def, stats), math.floor(reach))
		Ui.label(facts, { Position = UDim2.fromOffset(10, 266), Size = UDim2.new(1, -20, 0, 36), TextWrapped = true, TextSize = 12, Font = Ui.Fonts.Bold, Parent = card })
		local action
		if owned then
			action = Ui.button(if id == p.selected then "SELECTED" else "SELECT", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -24, 0, 40), TextSize = 15 }, if id == p.selected then C.Green else C.Accent)
			action.Activated:Connect(function()
				fire("SelectMachine", id)
			end)
		else
			local req = def.Requirement
			local values = table.clone(p.stats)
			for k, v in pairs(p.upgrades) do
				values[k] = v
			end
			local met = Economy.meets(req, values)
			local reqText = req and (req.Text .. (if req.AndText then " " .. req.AndText else "")) or ""
			local progress = req and string.format("(%s / %s)", Format.short(values[req.Stat] or 0), Format.short(req.Value)) or ""
			Ui.label("REQUIRES: " .. reqText .. "  " .. progress, { Position = UDim2.fromOffset(10, 306), Size = UDim2.new(1, -20, 0, 50), TextWrapped = true, TextSize = 12, TextColor3 = if met then C.Green else C.Red, Parent = card })
			action = Ui.button(string.format("UNLOCK  %s", Format.short(def.Cost)), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -24, 0, 40), TextSize = 15 }, if met and p.coins >= def.Cost then C.Accent else C.PanelLighter)
			action.Activated:Connect(function()
				fire("UnlockMachine", id)
			end)
		end
		action.Parent = card
	end
end

-- Lab log -------------------------------------------------------------------------------

-- Friend checks yield, so they're cached and filled in the background (then re-render).
local friendCache = {}
function MenuController.isFriend(userId)
	if type(userId) ~= "number" or userId <= 0 or userId == Players.LocalPlayer.UserId then
		return false
	end
	if friendCache[userId] == nil then
		friendCache[userId] = false
		task.spawn(function()
			local ok, result = pcall(function()
				return Players.LocalPlayer:IsFriendsWith(userId)
			end)
			if ok and result then
				friendCache[userId] = true
				if Ui.isOpen("Menu") and currentTab == "LabLog" then
					MenuController.render()
				end
			end
		end)
	end
	return friendCache[userId]
end

local function row(parent, text, sub, progress, order, color)
	local frame = Ui.panel({ Size = UDim2.new(1, -8, 0, 50), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = parent }, 8)
	Ui.label(text, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, Font = Ui.Fonts.Bold, TextColor3 = color or C.Text, Parent = frame })
	Ui.label(sub, { Position = UDim2.fromOffset(10, 24), Size = UDim2.new(0.62, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = C.Dim, Parent = frame })
	if progress then
		local _, fill = Ui.bar(frame, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 28), Size = UDim2.new(0.33, 0, 0, 12) }, C.Green)
		fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	end
	return frame
end

local function showConfirm(p)
	if confirmFrame then
		confirmFrame:Destroy()
	end
	local preview = p.prestigePreview
	confirmFrame = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(480, 340), ZIndex = 50, Parent = gui }, 14)
	Ui.title("EARN LAB CERTIFICATION?", { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 30), TextSize = 22, TextColor3 = C.Accent, ZIndex = 51, Parent = confirmFrame })
	local text = string.format("You gain %d Lab Credit%s (+%d%% coins each, up to +%d%%).\n\nRESETS: %s\n\nKEEPS: %s", preview.credits, if preview.credits == 1 then "" else "s", ScoringConfig.CreditBonus * 100, ScoringConfig.MaxCreditBonus * 100, table.concat(preview.resets, ", "), table.concat(preview.keeps, ", "))
	Ui.label(text, { Position = UDim2.fromOffset(20, 48), Size = UDim2.new(1, -40, 0, 210), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, ZIndex = 51, Parent = confirmFrame })
	local yes = Ui.button("YES, CERTIFY", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -16), Size = UDim2.fromOffset(200, 40), TextSize = 15, ZIndex = 51 }, C.Accent)
	yes.Parent = confirmFrame
	local no = Ui.button("CANCEL", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -16), Size = UDim2.fromOffset(180, 40), TextSize = 15, ZIndex = 51 }, C.PanelLighter)
	no.Parent = confirmFrame
	yes.Activated:Connect(function()
		fire("Prestige", "CERTIFY")
		confirmFrame:Destroy()
		confirmFrame = nil
	end)
	no.Activated:Connect(function()
		confirmFrame:Destroy()
		confirmFrame = nil
	end)
end
MenuController.showConfirm = showConfirm

renderers.LabLog = function(p)
	local scroll = Ui.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Ui.list(scroll, 6)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local function header(text)
		Ui.title(text, { Size = UDim2.new(1, -8, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, TextColor3 = C.Accent, LayoutOrder = nextOrder(), Parent = scroll })
	end
	header("PERSONAL RECORDS")
	local s = p.stats
	row(scroll, string.format("Best score %s   -   Farthest %s studs   -   Highest %s studs   -   Most impacts %d", Format.exact(s.BestScore or 0), Format.exact(s.BestDistance or 0), Format.exact(s.BestHeight or 0), s.BestImpacts or 0), string.format("%d launches, %d props smashed, %d rings, %d objectives", s.Launches or 0, s.Destroyed or 0, s.Rings or 0, s.Objectives or 0), nil, nextOrder())
	local daily = p.daily
	if daily then
		header(string.format("DAILY CHALLENGES  (reset in %s)", Format.clock(daily.resetsIn)))
		for _, c in ipairs(daily.list) do
			row(scroll, c.text .. (if c.done then "  - DONE" else ""), string.format("%s / %s   -   reward %s coins", Format.short(c.progress), Format.short(c.target), Format.short(c.reward)), c.progress / math.max(1, c.target), nextOrder(), if c.done then C.Green else nil)
		end
	end
	header("LAB CERTIFICATION (PRESTIGE)")
	local preview = p.prestigePreview
	local cert = Ui.panel({ Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = C.PanelLight, LayoutOrder = nextOrder(), Parent = scroll }, 8)
	Ui.label(if preview.eligible then string.format("Ready! Earn %d Lab Credit%s.", preview.credits, if preview.credits == 1 then "" else "s") else string.format("Needs the Air Cannon and a best score of %s.", Format.short(preview.needScore)), { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -200, 1, 0), TextWrapped = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = cert })
	local certify = Ui.button("CERTIFY...", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(160, 38), TextSize = 14 }, if preview.eligible then C.Accent else C.PanelLighter)
	certify.Parent = cert
	certify.Activated:Connect(function()
		if preview.eligible then
			showConfirm(p)
		end
	end)
	header("LEADERBOARDS  (global - friends marked)")
	local boards = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 230), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = scroll })
	Ui.list(boards, 10, Enum.FillDirection.Horizontal)
	for i, info in ipairs({ { "score", "TOP SCORES" }, { "distance", "FARTHEST FLIGHTS" } }) do
		local panel = Ui.panel({ Size = UDim2.new(0.5, -6, 1, 0), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Parent = boards }, 8)
		Ui.padding(panel, 10, 6)
		Ui.list(panel, 2)
		Ui.title(info[2], { Size = UDim2.new(1, 0, 0, 20), TextSize = 14, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
		local rows = (ClientState.leaderboard and ClientState.leaderboard[info[1]]) or {}
		if #rows == 0 then
			Ui.label("No entries yet (boards need published DataStores).", { Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
		end
		for rank, entry in ipairs(rows) do
			local me = entry.userId == Players.LocalPlayer.UserId
			local friend = MenuController.isFriend(entry.userId)
			Ui.label(string.format("%d. %s%s  -  %s", rank, entry.name, if me then "  (you)" elseif friend then "  (friend)" else "", Format.short(entry.value)), { Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = if me then C.Accent elseif friend then C.Green else C.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
		end
	end
	header("CRASH DUELS")
	local duelLine = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 36), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = scroll })
	Ui.list(duelLine, 6, Enum.FillDirection.Horizontal)
	local others = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= Players.LocalPlayer then
			others += 1
			local b = Ui.button("CHALLENGE " .. string.upper(other.DisplayName), { Size = UDim2.fromOffset(190, 34), TextSize = 11, LayoutOrder = others }, C.PanelLighter)
			b.Parent = duelLine
			b.Activated:Connect(function()
				fire("Duel", "Invite", other.UserId)
			end)
		end
	end
	if others == 0 then
		Ui.label("No other testers in this server yet. Invite a friend!", { Size = UDim2.fromOffset(500, 34), TextSize = 13, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = duelLine })
	end
	header("ACHIEVEMENTS")
	for _, def in ipairs(QuestConfig.Achievements) do
		local done = p.achievements[def.Id] ~= nil
		local value = p.stats[def.Stat] or 0
		row(scroll, def.Name .. (if done then "  - DONE" else ""), def.Text .. (if def.Reward > 0 then string.format("  (+%s coins)", Format.short(def.Reward)) else ""), if done then 1 else value / def.Target, nextOrder(), if done then C.Green else nil)
	end
	header("CODES")
	local codeLine = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 36), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = scroll })
	Ui.list(codeLine, 8, Enum.FillDirection.Horizontal)
	local box = Ui.new("TextBox", { Size = UDim2.fromOffset(200, 34), PlaceholderText = "Enter code", Text = "", TextSize = 14, BackgroundTransparency = 0, BackgroundColor3 = C.PanelLight, ClearTextOnFocus = false, LayoutOrder = 1, Parent = codeLine })
	Ui.corner(box, 8)
	local redeem = Ui.button("REDEEM", { Size = UDim2.fromOffset(100, 34), TextSize = 12, LayoutOrder = 2 }, C.Accent)
	redeem.Parent = codeLine
	redeem.Activated:Connect(function()
		fire("RedeemCode", box.Text)
		box.Text = ""
	end)
end

-- Locker --------------------------------------------------------------------------------

renderers.Locker = function(p)
	local scroll = Ui.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Ui.list(scroll, 8)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local robuxFor = {}
	for _, item in ipairs(ShopConfig.Products) do
		robuxFor[item.Kind .. ":" .. item.Item] = item
	end
	for _, item in ipairs(ShopConfig.Passes) do
		robuxFor[item.Kind .. ":" .. item.Item] = item
	end
	local sections = {
		{ kind = "Skin", title = "DUMMY DESIGNS", order = CosmeticConfig.SkinOrder, catalog = CosmeticConfig.Skins },
		{ kind = "Trail", title = "TRAILS", order = CosmeticConfig.TrailOrder, catalog = CosmeticConfig.Trails },
		{ kind = "LaunchFx", title = "LAUNCH EFFECTS", order = CosmeticConfig.LaunchFxOrder, catalog = CosmeticConfig.LaunchFx },
	}
	Ui.label("Cosmetic only: nothing here changes physics, scores or rewards.", { Size = UDim2.new(1, -8, 0, 18), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = nextOrder(), Parent = scroll })
	for _, section in ipairs(sections) do
		Ui.title(section.title, { Size = UDim2.new(1, -8, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, TextColor3 = C.Accent, LayoutOrder = nextOrder(), Parent = scroll })
		local grid = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = scroll })
		Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, if section.kind == "Skin" then 180 else 86), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for i, id in ipairs(section.order) do
			local def = section.catalog[id]
			local key = section.kind .. ":" .. id
			local owned = p.owned[key] == true
			local equipped = p.cosmetics[section.kind] == id
			local card = Ui.panel({ BackgroundColor3 = C.PanelLight, LayoutOrder = i, Parent = grid }, 10)
			if equipped then
				Ui.stroke(card, C.Accent, 2, 0)
			end
			local top = 4
			if section.kind == "Skin" then
				Ui.dummyIcon(card, id, 96, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2) })
				top = 98
			end
			Ui.title(def.Name, { Position = UDim2.fromOffset(4, top), Size = UDim2.new(1, -8, 0, 18), TextScaled = true, TextSize = 13, Parent = card })
			local label, color, action
			if equipped then
				label, color = "EQUIPPED", C.Green
			elseif owned then
				label, color = "EQUIP", C.Accent
				action = function()
					fire("Equip", section.kind, id)
				end
			elseif def.Source == "Coins" then
				label, color = Format.short(def.Cost) .. " coins", if p.coins >= def.Cost then C.Accent else C.PanelLighter
				action = function()
					fire("BuyCosmetic", section.kind, id)
				end
			elseif def.Source == "Achievement" then
				local a = QuestConfig.AchievementById[def.Achievement]
				label, color = "Achievement: " .. (a and a.Name or "?"), C.PanelLighter
			elseif def.Source == "Robux" and robuxFor[key] then
				label, color = "R$ " .. robuxFor[key].Robux, C.Blue
				action = function()
					fire("ShopBuy", robuxFor[key].Key)
				end
			else
				label, color = "Locked", C.PanelLighter
			end
			local b = Ui.button(label, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -12, 0, 30), TextSize = 11, TextWrapped = true }, color)
			b.Parent = card
			if action then
				b.Activated:Connect(action)
			end
		end
	end
end

-- Facilities ----------------------------------------------------------------------------

renderers.Facilities = function(p)
	local scroll = Ui.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Ui.list(scroll, 8)
	for i, f in ipairs(CourseConfig.Facilities) do
		local unlocked = p.facilities[f.Id] == true
		local status = if f.Built then "OPEN" elseif unlocked then "ACCESS GRANTED - under construction (coming in a future update)" else "LOCKED"
		row(scroll, f.Name, if unlocked then status else ("Requires: " .. f.Text), nil, i, if f.Built then C.Green elseif unlocked then C.Accent else nil)
	end
end

-- Settings ------------------------------------------------------------------------------

local saveQueued = false
local function setSetting(key, value)
	ClientState.applySettings({ [key] = value })
	if not saveQueued then
		saveQueued = true
		task.delay(1, function()
			saveQueued = false
			ClientState.saveSettings()
		end)
	end
	MenuController.render()
end
MenuController.setSetting = setSetting

local function settingRow(parent, order, label, valueText, onMinus, onPlus, onToggle)
	local frame = Ui.panel({ Size = UDim2.new(1, -8, 0, 40), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = parent }, 8)
	Ui.label(label, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, Font = Ui.Fonts.Bold, Parent = frame })
	Ui.label(valueText, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -90, 0, 0), Size = UDim2.fromOffset(140, 40), TextSize = 14, TextColor3 = C.Accent, Parent = frame })
	if onToggle then
		local b = Ui.button("CHANGE", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(76, 28), TextSize = 12 }, C.PanelLighter)
		b.Parent = frame
		b.Activated:Connect(onToggle)
	else
		local minus = Ui.button("-", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -46, 0.5, 0), Size = UDim2.fromOffset(32, 28), TextSize = 16 }, C.PanelLighter)
		minus.Parent = frame
		minus.Activated:Connect(onMinus)
		local plus = Ui.button("+", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(32, 28), TextSize = 16 }, C.PanelLighter)
		plus.Parent = frame
		plus.Activated:Connect(onPlus)
	end
end

renderers.Settings = function(_p)
	local scroll = Ui.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Ui.list(scroll, 6)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local function s(key, default)
		local v = ClientState.setting(key)
		if v == nil then
			return default
		end
		return v
	end
	for _, key in ipairs({ "Master", "Music", "Effects", "Ambient", "UI" }) do
		local v = s(key, 1)
		settingRow(scroll, nextOrder(), (if key == "Effects" then "Sound effects" else key) .. " volume", string.format("%d%%", math.floor(v * 100 + 0.5)), function()
			setSetting(key, math.max(0, math.floor((v - 0.1) * 10 + 0.5) / 10))
		end, function()
			setSetting(key, math.min(1, math.floor((v + 0.1) * 10 + 0.5) / 10))
		end)
	end
	settingRow(scroll, nextOrder(), "Camera sensitivity", Format.stat(s("Sensitivity", 1)), function()
		setSetting("Sensitivity", math.max(0.2, math.floor((s("Sensitivity", 1) - 0.1) * 10 + 0.5) / 10))
	end, function()
		setSetting("Sensitivity", math.min(3, math.floor((s("Sensitivity", 1) + 0.1) * 10 + 0.5) / 10))
	end)
	for _, info in ipairs({ { "CameraShake", "Camera shake", true }, { "FollowCam", "Follow camera during launches", true }, { "ReducedEffects", "Reduced effects mode", false } }) do
		local value = s(info[1], info[3])
		settingRow(scroll, nextOrder(), info[2], if value then "On" else "Off", nil, nil, function()
			setSetting(info[1], not value)
		end)
	end
	local more = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 36), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = scroll })
	Ui.list(more, 8, Enum.FillDirection.Horizontal)
	local replay = Ui.button("REPLAY TUTORIAL", { Size = UDim2.fromOffset(170, 34), TextSize = 12, LayoutOrder = 1 }, C.PanelLighter)
	replay.Parent = more
	replay.Activated:Connect(function()
		fire("Tutorial", "Replay")
	end)
	local help = Ui.button("CONTROLS / HELP", { Size = UDim2.fromOffset(170, 34), TextSize = 12, LayoutOrder = 2 }, C.PanelLighter)
	help.Parent = more
	help.Activated:Connect(function()
		currentTab = "Help"
		MenuController.render()
	end)
end

-- Help ----------------------------------------------------------------------------------

MenuController.HelpText = [[HOW TO PLAY
1. Walk onto a glowing green launch pad and press E (tap the prompt on mobile).
2. Pick your power, angle, aim and spin in the launch panel.
3. Press LAUNCH (F / R2). Your dummy flies down the course - the camera follows it (Space skips).
4. Distance, height, impacts, targets, rings, landings and objectives all score. Coins = score.
5. Spend coins on upgrades and new machines. Try the FEATURED OBJECTIVE for a big bonus.

PC        E use pad / stations   F launch   1/2 power   3/4 angle   5/6 aim   7 spin
          U upgrades   M menu   H help   Space skip camera   R retry (results)   WASD move, Space jump
GAMEPAD   X use   R2 launch   D-pad up/down power   D-pad left/right angle   L1/R1 aim
          Y spin   L2 menu   B skip camera / close
TOUCH     tap prompts, drag the POWER bar, use - / + buttons, LAUNCH, SKIP and the menu buttons]]

renderers.Help = function(_p)
	local scroll = Ui.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Ui.label(MenuController.HelpText, { Size = UDim2.new(1, -8, 0, 360), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 14, Font = Ui.Fonts.Body, Parent = scroll })
end

-- Window --------------------------------------------------------------------------------

function MenuController.render()
	local p = ClientState.profile
	if not content or not p then
		return
	end
	for name, b in pairs(tabButtons) do
		Ui.setButtonColor(b, if name == currentTab then C.Accent else C.PanelLight)
	end
	Ui.clear(content)
	local ok, err = pcall(renderers[currentTab], p)
	if not ok then
		warn("[CrashLab] menu render failed: " .. tostring(err))
	end
end

function MenuController.open(tab)
	currentTab = tab or currentTab
	Ui.openWindow("Menu")
	MenuController.render()
end

function MenuController.toggle(tab)
	if Ui.isOpen("Menu") and (tab == nil or tab == currentTab) then
		Ui.closeWindow("Menu")
	else
		MenuController.open(tab)
	end
end

function MenuController.init()
	gui = Ui.screen("CrashMenu", 10)
	local _, body = Ui.window(gui, "Menu", "CRASH LAB", 900, 580)
	local bar = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = body })
	Ui.list(bar, 6, Enum.FillDirection.Horizontal)
	for i, tab in ipairs(TABS) do
		local b = Ui.button(TAB_NAMES[tab] or string.upper(tab), { Size = UDim2.fromOffset(116, 32), TextSize = 12, LayoutOrder = i }, C.PanelLight)
		b.Parent = bar
		b.Activated:Connect(function()
			currentTab = tab
			MenuController.render()
		end)
		tabButtons[tab] = b
	end
	content = Ui.new("Frame", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1, Parent = body })
	InputController.MenuRequested:Connect(MenuController.toggle)
	ClientState.ProfileChanged:Connect(function()
		if Ui.isOpen("Menu") then
			MenuController.render()
		end
	end)
	ClientState.LeaderboardChanged:Connect(function()
		if Ui.isOpen("Menu") and currentTab == "LabLog" then
			MenuController.render()
		end
	end)
end

MenuController.renderers = renderers
MenuController.TABS = TABS
MenuController.setTab = function(tab)
	currentTab = tab
end
MenuController.setCategory = function(name)
	category = name
end

return MenuController
