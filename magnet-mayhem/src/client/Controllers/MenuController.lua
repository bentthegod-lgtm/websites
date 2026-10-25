--[[
	MenuController - the main menu window with tabs:
	  Upgrades  four categories of upgrade cards (current -> next, price, buy), the next
	            magnet tier, and Prestige (with a confirmation that lists what resets)
	  Codex     every scrap object; undiscovered ones are silhouettes with "???"
	  Quests    tutorial, starter quest, daily objectives (UTC reset timer), achievements
	  Zones     unlock requirements and progress; future zones shown as coming soon
	  Shop      optional cosmetic Robux items
	  Settings  camera, sensitivity, five volume sliders, reduced effects, particle
	            quality, cosmetics, tutorial replay, codes and the controls list
	Buttons only send requests; the server validates and replies with a new profile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local Net = require(Shared.Net)
local Format = require(Shared.Format)
local Economy = require(Shared.Economy)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MagnetConfig = require(Shared.Config.MagnetConfig)
local ScrapConfig = require(Shared.Config.ScrapConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local QuestConfig = require(Shared.Config.QuestConfig)
local ShopConfig = require(Shared.Config.ShopConfig)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)
local InputController = require(script.Parent.InputController)
local HudController = require(script.Parent.HudController)

local MenuController = {}

local C = Ui.Colors
local TABS = { "Upgrades", "Codex", "Quests", "Zones", "Shop", "Settings" }
local gui, content, tabButtons = nil, nil, {}
local currentTab = "Upgrades"
local category = "Magnet"
local renderers = {}
local confirmFrame
local lastCodexCount = -1

local function profile()
	return ClientState.profile
end

local function fire(name, ...)
	Net.event(name):FireServer(...)
end

-- Upgrades ------------------------------------------------------------------------------

local STAT_VIEW = {
	Strength = function(s)
		return "Strength " .. Format.stat(s.MagnetStrength)
	end,
	Range = function(s)
		return Format.stat(s.AttractionRange) .. " studs"
	end,
	Speed = function(s)
		return "x" .. Format.stat(s.AttractionSpeed)
	end,
	Pulse = function(s)
		return string.format("%s studs, %ss", Format.stat(s.PulseRadius), Format.stat(s.PulseCooldown))
	end,
	Heavy = function(s)
		return Format.stat(s.HeavyObjectCapability) .. " heavy at once"
	end,
	Capacity = function(s)
		return Format.short(s.MaximumScrapCapacity) .. " capacity"
	end,
	Efficiency = function(s)
		return Format.stat(s.CollectionEfficiency) .. " at once"
	end,
	Organization = function(s)
		return Format.short(s.MaximumScrapCapacity) .. " capacity"
	end,
	Move = function(s)
		return Format.stat(s.WalkSpeed) .. " speed"
	end,
	Sprint = function(s)
		return "x" .. Format.stat(s.SprintMultiplier)
	end,
	Sell = function(s)
		return "x" .. Format.stat(s.ScrapValueMultiplier)
	end,
	Rare = function(s)
		return Format.stat(s.LuckyChance * 100) .. "% lucky"
	end,
}

local function upgradeCard(parent, def, p, order)
	local level = p.upgrades[def.Key] or 0
	local price = Economy.upgradePrice(def.Key, level)
	local cores = p.prestige.Cores
	local now = Economy.stats(p.upgrades, p.tier, cores)
	local nextLevels = table.clone(p.upgrades)
	nextLevels[def.Key] = level + 1
	local after = Economy.stats(nextLevels, p.tier, cores)
	local card = Ui.panel({ Size = UDim2.fromOffset(300, 120), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = parent }, 10)
	local icon = Ui.new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = C.PanelLighter, Parent = card })
	Ui.corner(icon, 8)
	Ui.title(def.Icon, { Size = UDim2.fromScale(1, 1), TextSize = 13, TextColor3 = C.Accent, Parent = icon })
	Ui.title(def.Name, { Position = UDim2.fromOffset(62, 8), Size = UDim2.new(1, -70, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 15, Parent = card })
	Ui.label(string.format("Level %d / %d", level, def.Max), { Position = UDim2.fromOffset(62, 28), Size = UDim2.new(1, -70, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = C.Dim, Parent = card })
	local view = STAT_VIEW[def.Key]
	local statText = if price then string.format("%s  ->  %s", view(now), view(after)) else view(now) .. "  (MAX)"
	Ui.label(statText, { Position = UDim2.fromOffset(10, 60), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, Font = Ui.Fonts.Bold, TextColor3 = C.Green, Parent = card })
	Ui.label(def.Description, { Position = UDim2.fromOffset(10, 76), Size = UDim2.new(1, -120, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextSize = 11, TextColor3 = C.Dim, Parent = card })
	local affordable = price ~= nil and p.coins >= price
	local label = if not price then "MAX" else Format.short(price)
	local buy = Ui.button(label, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10), Size = UDim2.fromOffset(96, 32), TextSize = 14 }, if not price then C.PanelLighter elseif affordable then C.Accent else C.PanelLighter)
	if price and not affordable then
		buy.TextColor3 = C.Red
	end
	buy.Parent = card
	buy.Activated:Connect(function()
		if not price then
			return
		end
		fire("BuyUpgrade", def.Key)
	end)
	return card
end

local function tierCard(parent, p)
	local nextDef = MagnetConfig.Tiers[p.tier + 1]
	local card = Ui.panel({ Size = UDim2.new(1, -8, 0, 64), BackgroundColor3 = Color3.fromRGB(52, 44, 30), LayoutOrder = 0, Parent = parent }, 10)
	local cur = MagnetConfig.Tiers[p.tier]
	Ui.title(string.format("MAGNET: %s (tier %d/%d)", string.upper(cur.Name), p.tier, #MagnetConfig.Tiers), { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -150, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, TextColor3 = C.Accent, Parent = card })
	if nextDef then
		Ui.label(string.format("Next: %s - base strength %d -> %d, +range, x%s capacity. New look!", nextDef.Name, cur.Strength, nextDef.Strength, Format.stat(nextDef.CapacityMult)), { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -150, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextSize = 12, TextColor3 = C.Text, Parent = card })
		local affordable = p.coins >= nextDef.Price
		local buy = Ui.button(Format.short(nextDef.Price), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(120, 38), TextSize = 16 }, if affordable then C.Accent else C.PanelLighter)
		if not affordable then
			buy.TextColor3 = C.Red
		end
		buy.Parent = card
		buy.Activated:Connect(function()
			fire("BuyTier")
		end)
	else
		Ui.label("You have the most powerful magnet. Prestige for Magnet Cores!", { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, Parent = card })
	end
end

local function showConfirm(p)
	if confirmFrame then
		confirmFrame:Destroy()
	end
	local preview = p.prestigePreview
	confirmFrame = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 330), ZIndex = 50, Parent = gui }, 14)
	Ui.title("PRESTIGE?", { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 30), TextSize = 24, TextColor3 = C.Accent, ZIndex = 51, Parent = confirmFrame })
	local text = string.format("You will gain %d Magnet Cores (+%d%% sale value and +%d%% pull speed each).\n\nRESETS: %s\n\nKEEPS: %s", preview.cores, EconomyConfig.Prestige.ValuePerCore * 100, EconomyConfig.Prestige.SpeedPerCore * 100, table.concat(preview.resets, ", "), table.concat(preview.keeps, ", "))
	Ui.label(text, { Position = UDim2.fromOffset(20, 48), Size = UDim2.new(1, -40, 0, 200), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, ZIndex = 51, Parent = confirmFrame })
	local yes = Ui.button("YES, PRESTIGE", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -16), Size = UDim2.fromOffset(200, 40), TextSize = 15, ZIndex = 51 }, C.Accent)
	yes.Parent = confirmFrame
	local no = Ui.button("CANCEL", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -16), Size = UDim2.fromOffset(180, 40), TextSize = 15, ZIndex = 51 }, C.PanelLighter)
	no.Parent = confirmFrame
	yes.Activated:Connect(function()
		fire("Prestige", "CONFIRM")
		confirmFrame:Destroy()
		confirmFrame = nil
	end)
	no.Activated:Connect(function()
		confirmFrame:Destroy()
		confirmFrame = nil
	end)
end

renderers.Upgrades = function(p)
	local side = Ui.new("Frame", { Size = UDim2.new(0, 140, 1, 0), BackgroundTransparency = 1, Parent = content })
	Ui.list(side, 6)
	for i, cat in ipairs(EconomyConfig.Categories) do
		local b = Ui.button(string.upper(cat), { Size = UDim2.new(1, 0, 0, 36), TextSize = 13, LayoutOrder = i }, if cat == category then C.Accent else C.PanelLight)
		b.Parent = side
		b.Activated:Connect(function()
			category = cat
			MenuController.render()
		end)
	end
	local preview = p.prestigePreview
	local prestige = Ui.button(if preview and preview.eligible then string.format("PRESTIGE (+%d)", preview.cores) else "PRESTIGE", { Size = UDim2.new(1, 0, 0, 36), TextSize = 13, LayoutOrder = 20 }, if preview and preview.eligible then C.Purple else C.PanelLighter)
	prestige.Parent = side
	local reason = Ui.label(if preview and not preview.eligible then table.concat(preview.reasons, "\n") else "", { Size = UDim2.new(1, 0, 0, 70), TextWrapped = true, TextSize = 11, TextColor3 = C.Dim, LayoutOrder = 21, Parent = side })
	reason.TextYAlignment = Enum.TextYAlignment.Top
	prestige.Activated:Connect(function()
		if preview and preview.eligible then
			showConfirm(p)
		end
	end)
	local top = 0
	if category == "Magnet" then
		local holder = Ui.new("Frame", { Position = UDim2.fromOffset(152, 0), Size = UDim2.new(1, -152, 0, 64), BackgroundTransparency = 1, Parent = content })
		tierCard(holder, p)
		top = 72
	end
	local scroll = Ui.scroll(content, { Position = UDim2.fromOffset(152, top), Size = UDim2.new(1, -152, 1, -top) })
	local grid = Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(300, 120), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	grid.FillDirectionMaxCells = 2
	for _, def in ipairs(EconomyConfig.Upgrades) do
		if def.Category == category then
			upgradeCard(scroll, def, p, def.Order)
		end
	end
end

-- Codex ---------------------------------------------------------------------------------

renderers.Codex = function(p)
	local found = 0
	for _ in pairs(p.codex) do
		found += 1
	end
	lastCodexCount = found
	Ui.title(string.format("SCRAP CODEX  -  %d / %d discovered", found, #ScrapConfig.List), { Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, Parent = content })
	local scroll = Ui.scroll(content, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30) })
	Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 170), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	for _, def in ipairs(ScrapConfig.List) do
		local entry = p.codex[def.Id]
		local card = Ui.panel({ BackgroundColor3 = C.PanelLight, LayoutOrder = def.Order, Parent = scroll }, 10)
		Ui.scrapIcon(card, def.Id, 96, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4) }, entry == nil)
		Ui.title(if entry then def.Name else "???", { Position = UDim2.fromOffset(4, 100), Size = UDim2.new(1, -8, 0, 18), TextScaled = true, TextSize = 14, Parent = card })
		Ui.label(ScrapConfig.Rarities[def.Rarity].Label, { Position = UDim2.fromOffset(4, 118), Size = UDim2.new(1, -8, 0, 14), TextSize = 11, Font = Ui.Fonts.Bold, TextColor3 = Ui.rarityColor(def.Rarity), Parent = card })
		local zone = ZoneConfig.ById[def.Zone]
		local info = if entry then string.format("x%d  -  best %s\n%s", entry.n, Format.short(entry.best), if zone then zone.Name else "Magnetic Storm") else (if zone then zone.Name else "Magnetic Storm")
		Ui.label(info, { Position = UDim2.fromOffset(4, 132), Size = UDim2.new(1, -8, 0, 32), TextSize = 11, TextWrapped = true, TextColor3 = C.Dim, Parent = card })
	end
end

-- Quests --------------------------------------------------------------------------------

local function row(parent, text, sub, progress, order, color)
	local frame = Ui.panel({ Size = UDim2.new(1, -8, 0, 52), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = parent }, 8)
	Ui.label(text, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, Font = Ui.Fonts.Bold, TextColor3 = color or C.Text, Parent = frame })
	Ui.label(sub, { Position = UDim2.fromOffset(10, 24), Size = UDim2.new(0.6, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, TextColor3 = C.Dim, Parent = frame })
	if progress then
		local _, fill = Ui.bar(frame, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 28), Size = UDim2.new(0.35, 0, 0, 12) }, C.Green)
		fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	end
	return frame
end

renderers.Quests = function(p)
	local scroll = Ui.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Ui.list(scroll, 6)
	local order = 0
	local function header(text)
		order += 1
		Ui.title(text, { Size = UDim2.new(1, -8, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, TextColor3 = C.Accent, LayoutOrder = order, Parent = scroll })
	end
	local tut = p.tutorial
	if tut and not tut.Done then
		header("TUTORIAL")
		local step = QuestConfig.Tutorial[tut.Step]
		order += 1
		row(scroll, step and step.Text or "", step and step.Hint or "", (tut.Step - 1) / #QuestConfig.Tutorial, order)
	end
	header("QUEST")
	local q = p.quest
	order += 1
	if q and not q.done then
		row(scroll, string.format("%d/%d  %s", q.index, q.total, q.text), string.format("%s / %s   -   reward %s coins", Format.short(q.progress), Format.short(q.target), Format.short(q.reward)), q.progress / q.target, order)
	else
		row(scroll, "All starter quests complete!", "Daily objectives keep coming every day.", 1, order, C.Green)
	end
	local daily = p.daily
	local resetIn = if daily then daily.resetIn - (os.clock() - (p.receivedAt or os.clock())) else 0
	header(string.format("DAILY OBJECTIVES  (new in %s)", Format.clock(resetIn)))
	for _, o in ipairs(daily and daily.list or {}) do
		order += 1
		row(scroll, o.Text, if o.Done then "Done!" else string.format("%s / %s   -   reward %s coins", Format.short(o.Progress), Format.short(o.Target), Format.short(o.Reward)), o.Progress / o.Target, order, if o.Done then C.Green else nil)
	end
	header("ACHIEVEMENTS")
	for _, a in ipairs(QuestConfig.Achievements) do
		order += 1
		local done = p.achievements[a.Id] ~= nil
		row(scroll, (if done then "[DONE] " else "") .. a.Name, a.Text, nil, order, if done then C.Green else C.Dim)
	end
end

-- Zones ---------------------------------------------------------------------------------

renderers.Zones = function(p)
	local scroll = Ui.scroll(content, { Size = UDim2.fromScale(1, 1) })
	Ui.list(scroll, 8)
	local strength = p.stats and p.stats.MagnetStrength or 1
	for _, zone in ipairs(ZoneConfig.List) do
		local unlocked = p.zones[zone.Id] == true
		local card = Ui.panel({ Size = UDim2.new(1, -8, 0, 92), BackgroundColor3 = if unlocked then Color3.fromRGB(34, 52, 40) else C.PanelLight, LayoutOrder = zone.Order, Parent = scroll }, 10)
		Ui.title(string.upper(zone.Name), { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -170, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 18, TextColor3 = if zone.Built then C.Text else C.Dim, Parent = card })
		Ui.label(zone.Description .. (if zone.Categories then "\nFind: " .. zone.Categories else ""), { Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -180, 0, 50), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 12, TextColor3 = C.Dim, Parent = card })
		if unlocked then
			Ui.title("UNLOCKED", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(140, 30), TextSize = 16, TextColor3 = C.Green, Parent = card })
		elseif zone.Unlock then
			local req = string.format("Strength %d  (%s)\n%s coins", zone.Unlock.Strength, Format.stat(strength), Format.short(zone.Unlock.Coins))
			Ui.label(req, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 8), Size = UDim2.fromOffset(150, 34), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = if strength >= zone.Unlock.Strength then C.Green else C.Red, Parent = card })
			if zone.Built then
				local ready = strength >= zone.Unlock.Strength and p.coins >= zone.Unlock.Coins
				local b = Ui.button("UNLOCK", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -10), Size = UDim2.fromOffset(120, 32), TextSize = 14 }, if ready then C.Accent else C.PanelLighter)
				b.Parent = card
				b.Activated:Connect(function()
					fire("UnlockZone", zone.Id)
				end)
			else
				Ui.title("COMING SOON", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -10), Size = UDim2.fromOffset(140, 30), TextSize = 14, TextColor3 = C.Dim, Parent = card })
			end
		end
	end
end

-- Shop ----------------------------------------------------------------------------------

renderers.Shop = function(p)
	Ui.label("Optional cosmetics. They never change stats or progression.", { Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = C.Dim, Parent = content })
	local scroll = Ui.scroll(content, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 1, -26) })
	Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(240, 120), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	local order = 0
	local function item(entry, owned)
		order += 1
		local card = Ui.panel({ BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = scroll }, 10)
		Ui.title(entry.Name, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 15, Parent = card })
		Ui.label(entry.Description, { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 40), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 12, TextColor3 = C.Dim, Parent = card })
		local b = Ui.button(if owned then "OWNED" else "R$ " .. entry.Robux, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -10), Size = UDim2.fromOffset(110, 32), TextSize = 14 }, if owned then C.PanelLighter else C.Green)
		b.Parent = card
		b.Activated:Connect(function()
			if not owned then
				fire("ShopBuy", entry.Key)
			end
		end)
	end
	for _, pass in ipairs(ShopConfig.Passes) do
		item(pass, p.passes[pass.Key] == true)
	end
	for _, product in ipairs(ShopConfig.Products) do
		item(product, p.cosmetics.Owned[product.Skin or product.Trail] == true)
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

renderers.Settings = function(p)
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
	settingRow(scroll, nextOrder(), "Camera", if s("CameraMode", "Third") == "First" then "First person" else "Third person", nil, nil, function()
		setSetting("CameraMode", if s("CameraMode", "Third") == "First" then "Third" else "First")
	end)
	settingRow(scroll, nextOrder(), "Camera sensitivity", Format.stat(s("Sensitivity", 1)), function()
		setSetting("Sensitivity", math.max(0.2, math.floor((s("Sensitivity", 1) - 0.1) * 10 + 0.5) / 10))
	end, function()
		setSetting("Sensitivity", math.min(3, math.floor((s("Sensitivity", 1) + 0.1) * 10 + 0.5) / 10))
	end)
	for _, key in ipairs({ "Master", "Music", "Effects", "Ambient", "UI" }) do
		local v = s(key, 1)
		settingRow(scroll, nextOrder(), key .. " volume", string.format("%d%%", math.floor(v * 100 + 0.5)), function()
			setSetting(key, math.max(0, math.floor((v - 0.1) * 10 + 0.5) / 10))
		end, function()
			setSetting(key, math.min(1, math.floor((v + 0.1) * 10 + 0.5) / 10))
		end)
	end
	settingRow(scroll, nextOrder(), "Reduced camera effects", if s("ReducedEffects", false) then "On" else "Off", nil, nil, function()
		setSetting("ReducedEffects", not s("ReducedEffects", false))
	end)
	local qualities = { High = "Medium", Medium = "Low", Low = "High" }
	settingRow(scroll, nextOrder(), "Particle quality", s("Particles", "High"), nil, nil, function()
		setSetting("Particles", qualities[s("Particles", "High")] or "High")
	end)
	-- Cosmetics.
	Ui.title("COSMETICS", { Size = UDim2.new(1, -8, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, TextColor3 = C.Accent, LayoutOrder = nextOrder(), Parent = scroll })
	local function ownsCosmetic(kind, id, def)
		if p.cosmetics.Owned[id] then
			return true
		end
		for _, pass in ipairs(ShopConfig.Passes) do
			if ((kind == "Skin" and pass.Skin == id) or (kind == "Trail" and pass.Trail == id)) and p.passes[pass.Key] then
				return true
			end
		end
		return def.Source == nil
	end
	for _, info in ipairs({ { kind = "Skin", order = MagnetConfig.SkinOrder, catalog = MagnetConfig.Skins }, { kind = "Trail", order = MagnetConfig.TrailOrder, catalog = MagnetConfig.Trails } }) do
		local line = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 34), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = scroll })
		Ui.list(line, 6, Enum.FillDirection.Horizontal)
		for i, id in ipairs(info.order) do
			local def = info.catalog[id]
			local owned = ownsCosmetic(info.kind, id, def)
			local equipped = p.cosmetics[info.kind] == id
			local b = Ui.button(def.Name, { Size = UDim2.fromOffset(120, 32), TextSize = 11, LayoutOrder = i }, if equipped then C.Accent elseif owned then C.PanelLighter else C.Panel)
			if not owned then
				b.TextColor3 = C.Dim
			end
			b.Parent = line
			b.Activated:Connect(function()
				if owned then
					fire("Equip", info.kind, id)
				end
			end)
		end
	end
	-- Tutorial, codes, controls.
	Ui.title("MORE", { Size = UDim2.new(1, -8, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, TextColor3 = C.Accent, LayoutOrder = nextOrder(), Parent = scroll })
	local more = Ui.new("Frame", { Size = UDim2.new(1, -8, 0, 36), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = scroll })
	Ui.list(more, 8, Enum.FillDirection.Horizontal)
	local replay = Ui.button("REPLAY TUTORIAL", { Size = UDim2.fromOffset(160, 34), TextSize = 12, LayoutOrder = 1 }, C.PanelLighter)
	replay.Parent = more
	replay.Activated:Connect(function()
		fire("Tutorial", "Replay")
	end)
	local box = Ui.new("TextBox", { Size = UDim2.fromOffset(180, 34), PlaceholderText = "Enter code", Text = "", TextSize = 14, BackgroundTransparency = 0, BackgroundColor3 = C.PanelLight, ClearTextOnFocus = false, LayoutOrder = 2, Parent = more })
	Ui.corner(box, 8)
	local redeem = Ui.button("REDEEM", { Size = UDim2.fromOffset(100, 34), TextSize = 12, LayoutOrder = 3 }, C.Accent)
	redeem.Parent = more
	redeem.Activated:Connect(function()
		fire("RedeemCode", box.Text)
		box.Text = ""
	end)
	local controls = "CONTROLS\nPC: WASD move - hold Left Mouse = magnet - R = magnetic pulse - Shift = sprint - E = interact - M = menu - V = camera mode - Tab = player list\nGamepad: R2 = magnet - R1 = pulse - L3 = sprint - X = interact - D-pad up = menu - D-pad down = camera\nTouch: hold MAGNET - tap PULSE - SPRINT toggles - tap prompts to interact"
	Ui.label(controls, { Size = UDim2.new(1, -8, 0, 110), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextSize = 12, TextColor3 = C.Dim, LayoutOrder = nextOrder(), Parent = scroll })
end

-- Window --------------------------------------------------------------------------------

function MenuController.render()
	local p = profile()
	if not content or not p then
		return
	end
	for name, b in pairs(tabButtons) do
		Ui.setButtonColor(b, if name == currentTab then C.Accent else C.PanelLight)
	end
	Ui.clear(content)
	local ok, err = pcall(renderers[currentTab], p)
	if not ok then
		warn("[MagnetMayhem] menu render failed: " .. tostring(err))
	end
end

function MenuController.open(tab)
	currentTab = tab or currentTab
	Ui.openWindow("Menu")
	MenuController.render()
end

function MenuController.init()
	gui = Ui.screen("MagnetMenu", 10)
	local _, body = Ui.window(gui, "Menu", "MAGNET MAYHEM", 860, 560)
	local bar = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = body })
	Ui.list(bar, 6, Enum.FillDirection.Horizontal)
	for i, tab in ipairs(TABS) do
		local b = Ui.button(string.upper(tab), { Size = UDim2.fromOffset(122, 32), TextSize = 13, LayoutOrder = i }, C.PanelLight)
		b.Parent = bar
		b.Activated:Connect(function()
			currentTab = tab
			MenuController.render()
		end)
		tabButtons[tab] = b
	end
	content = Ui.new("Frame", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1, Parent = body })
	for _, tab in ipairs(TABS) do
		local button = HudController.menuButton(tab)
		if button then
			button.Activated:Connect(function()
				if Ui.isOpen("Menu") and currentTab == tab then
					Ui.closeWindow("Menu")
				else
					MenuController.open(tab)
				end
			end)
		end
	end
	InputController.MenuRequested:Connect(function()
		if Ui.isOpen("Menu") then
			Ui.closeWindow("Menu")
		else
			MenuController.open(currentTab)
		end
	end)
	ClientState.ProfileChanged:Connect(function(p)
		if not Ui.isOpen("Menu") then
			return
		end
		if currentTab == "Codex" then
			local found = 0
			for _ in pairs(p.codex) do
				found += 1
			end
			if found == lastCodexCount then
				return -- the codex is expensive to rebuild; only when something new is found
			end
		end
		MenuController.render()
	end)
	ClientState.PopupRequested:Connect(function(kind, data)
		if kind == "OpenMenu" then
			MenuController.open(data and data.tab or "Upgrades")
		elseif kind == "GateMenu" then
			MenuController.open("Zones")
		end
	end)
	-- Daily reset countdown in the Quests tab stays fresh.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc > 5 and Ui.isOpen("Menu") and currentTab == "Quests" then
			acc = 0
			MenuController.render()
		end
	end)
end

MenuController.renderers = renderers
MenuController.setTab = function(tab)
	currentTab = tab
end
MenuController.setCategory = function(name)
	category = name
end

return MenuController
