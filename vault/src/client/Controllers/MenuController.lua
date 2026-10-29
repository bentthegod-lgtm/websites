--[[
	MenuController - every menu window. Values shown come from the server's snapshot;
	buttons only send requests (the server validates and answers with a toast).

	Upgrades      category tabs (Collection / Capacity / Movement / Earnings / Token Perks)
	              with cards: name, level x / max, effect now -> next, price, BUY. Locked
	              upgrades say which depth opens them. Opened by the Upgrade Terminal prompt.
	Depths        the vertical depth panel (same list as the elevator, travel disabled) and
	              the sealed Ancient Vault complex.
	Book          the Collection Book: every item grouped by depth, undiscovered entries as
	              dark silhouettes with "???"; found entries show rarity and count.
	Achievements  progress bars and rewards.
	Daily         three UTC daily challenges with a reset countdown.
	Stats         lifetime numbers and the Rebirth panel (resets / keeps, type REBIRTH).
	Leaderboards  the four global boards.
	Shop          Robux items (optional, cosmetics / modest convenience) and Token
	              cosmetics; equip what you own.
	Settings      volumes, effects, camera shake, show others, auto-deposit, replay
	              tutorial, redeem a code.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local Net = require(Shared.Net)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local DepthConfig = require(Shared.Config.DepthConfig)
local LootConfig = require(Shared.Config.LootConfig)
local QuestConfig = require(Shared.Config.QuestConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)
local Format = require(Shared.Format)

local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)
local InputController = require(script.Parent.InputController)
local ElevatorController = require(script.Parent.ElevatorController)
local Ui = require(script.Parent.Ui)

local C = Ui.Colors
local MenuController = {}

local gui
local refreshers = {} -- [window] = fn

local function profile()
	return ClientState.profile
end

local function economyState(p)
	return { Upgrades = p.upgrades, Perks = p.perks, Rebirths = p.rebirths, BoostUntil = p.boostUntil, Vip = p.vip }
end

local function register(name, title, w, h, build)
	local _, body = Ui.window(gui, name, title, w, h)
	local refresh = build(body)
	refreshers[name] = refresh
	Ui.onWindowOpen(name, refresh)
end

local function tabs(body, names, onSelect)
	local bar = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Parent = body })
	Ui.list(bar, 6, Enum.FillDirection.Horizontal)
	local buttons = {}
	local current = names[1]
	local function choose(name)
		current = name
		for n, b in pairs(buttons) do
			Ui.setButtonColor(b, if n == name then C.Accent else C.PanelLight)
		end
		onSelect(name)
	end
	for i, name in ipairs(names) do
		local b = Ui.button(string.upper(name), { Size = UDim2.fromOffset(math.floor(640 / #names) - 6, 32), TextSize = 13, LayoutOrder = i }, C.PanelLight)
		b.Parent = bar
		buttons[name] = b
		b.Activated:Connect(function()
			choose(name)
		end)
	end
	return function()
		return current
	end, choose
end

-- Upgrades ---------------------------------------------------------------------------------

local function upgradeCard(parent, def, p, order)
	local level = p.upgrades[def.Key] or 0
	local locked = p.highestDepth < def.UnlockDepth
	local cost = Economy.upgradeCost(def.Key, level)
	local card = Ui.panel({ Size = UDim2.new(1, -10, 0, 84), LayoutOrder = order, BackgroundColor3 = if locked then C.Panel else C.PanelLight, Parent = parent }, 10)
	Ui.label(def.Name, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -200, 0, 22), Font = Ui.Fonts.Bold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if locked then C.Dim else C.Text, Parent = card })
	Ui.label(string.format("LV %d / %d", level, def.Max), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 10), Size = UDim2.fromOffset(80, 20), TextSize = 13, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Right, Parent = card })
	Ui.label(def.Description, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -170, 0, 18), TextSize = 13, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
	local now, nxt = Economy.effectText(def.Key, economyState(p))
	local effect = if cost then now .. "  ->  " .. nxt else now .. "  (max)"
	Ui.label(effect, { Position = UDim2.fromOffset(14, 52), Size = UDim2.new(1, -170, 0, 20), Font = Ui.Fonts.Bold, TextSize = 14, TextColor3 = C.Green, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	local _, fill = Ui.bar(card, { Position = UDim2.new(0, 14, 1, -8), Size = UDim2.new(1, -170, 0, 4) }, C.Accent)
	fill.Size = UDim2.fromScale(level / def.Max, 1)
	local button
	if locked then
		local d = DepthConfig.get(def.UnlockDepth)
		Ui.label("UNLOCKS AT\n" .. d.Code .. " " .. string.upper(d.Name), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 50), Font = Ui.Fonts.Bold, TextSize = 12, TextColor3 = C.Dim, Parent = card })
	elseif not cost then
		Ui.label("MAXED", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 44), Font = Ui.Fonts.Title, TextSize = 18, TextColor3 = C.Accent, Parent = card })
	else
		local affordable = p.cash >= cost
		button = Ui.button("$" .. Format.short(cost), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 44), TextSize = 18 }, if affordable then C.Green else C.PanelLighter)
		button.Parent = card
		button.Activated:Connect(function()
			if p.cash >= cost then
				Net.event("BuyUpgrade"):FireServer(def.Key)
				AudioController.play("UpgradeBuy")
			else
				AudioController.play("NoFunds")
				ClientState.Notified:Fire(string.format("%s costs $%s - you have $%s.", def.Name, Format.short(cost), Format.short(p.cash)), "error")
			end
		end)
	end
end

local function perkCard(parent, def, p, order)
	local level = p.perks[def.Key] or 0
	local cost = Economy.perkCost(def.Key, level)
	local card = Ui.panel({ Size = UDim2.new(1, -10, 0, 70), LayoutOrder = order, BackgroundColor3 = C.PanelLight, Parent = parent }, 10)
	Ui.label(def.Name .. string.format("   LV %d / %d", level, def.Max), { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -170, 0, 22), Font = Ui.Fonts.Bold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	Ui.label(def.Description, { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -170, 0, 28), TextSize = 13, TextWrapped = true, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	if cost then
		local b = Ui.button(cost .. " TOKENS", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 42), TextSize = 15 }, if p.tokens >= cost then C.Accent else C.PanelLighter)
		b.Parent = card
		b.Activated:Connect(function()
			Net.event("BuyPerk"):FireServer(def.Key)
		end)
	else
		Ui.label("MAXED", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 42), Font = Ui.Fonts.Title, TextSize = 18, TextColor3 = C.Accent, Parent = card })
	end
end

local function buildUpgrades(body)
	local list
	local current
	local function fill(category)
		local p = profile()
		Ui.clear(list)
		if not p then
			return
		end
		if category == "Token Perks" then
			Ui.label("Vault Tokens come from achievements, daily challenges, rare finds and rebirths. Perks are kept through rebirth.", { Size = UDim2.new(1, -10, 0, 34), TextSize = 13, TextWrapped = true, TextColor3 = C.Dim, LayoutOrder = 0, Parent = list })
			for i, def in ipairs(UpgradeConfig.Perks) do
				perkCard(list, def, p, i)
			end
			return
		end
		local order = 0
		for _, def in ipairs(UpgradeConfig.List) do
			if def.Category == category then
				order += 1
				upgradeCard(list, def, p, order)
			end
		end
	end
	local names = table.clone(UpgradeConfig.Categories)
	table.insert(names, "Token Perks")
	local get
	get, current = tabs(body, names, function(name)
		fill(name)
	end)
	list = Ui.scroll(body, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })
	Ui.list(list, 8)
	ClientState.ProfileChanged:Connect(function()
		if Ui.isOpen("Upgrades") then
			fill(get())
		end
	end)
	current(names[1])
	return function()
		fill(get())
	end
end

-- Depths -----------------------------------------------------------------------------------

local function buildDepths(body)
	Ui.label("Unlock depths here or at any elevator panel; ride the elevator to travel. Each depth's loot is worth far more than the last.", { Size = UDim2.new(1, 0, 0, 34), TextSize = 13, TextWrapped = true, TextColor3 = C.Dim, Parent = body })
	local list = Ui.scroll(body, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40) })
	Ui.list(list, 6)
	local function refresh()
		ElevatorController.fillDepthList(list, false)
	end
	ClientState.ProfileChanged:Connect(function()
		if Ui.isOpen("Depths") then
			refresh()
		end
	end)
	return refresh
end

-- Collection Book --------------------------------------------------------------------------

local function buildBook(body)
	local header = Ui.label("", { Size = UDim2.new(1, 0, 0, 22), Font = Ui.Fonts.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Accent, Parent = body })
	local list = Ui.scroll(body, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -28) })
	Ui.list(list, 10)
	local built = false
	local cells = {}
	local function build()
		built = true
		for d = 1, DepthConfig.Count do
			local def = DepthConfig.get(d)
			local section = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = d, Parent = list })
			Ui.label(def.Code .. "  " .. string.upper(def.Name), { Size = UDim2.new(1, 0, 0, 22), Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = Ui.rgb(def.Palette.Accent), TextXAlignment = Enum.TextXAlignment.Left, Parent = section })
			local grid = Ui.new("Frame", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = section })
			Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(118, 132), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
			for _, item in ipairs(LootConfig.List) do
				if item.Depth == d then
					local cell = Ui.panel({ BackgroundColor3 = C.PanelLight, LayoutOrder = item.Order, Parent = grid }, 8)
					cells[item.Id] = { cell = cell, def = item }
				end
			end
		end
	end
	local function refresh()
		local p = profile()
		if not p then
			return
		end
		if not built then
			build()
		end
		local found = 0
		for id, entry in pairs(cells) do
			local book = p.book[id]
			local known = book ~= nil
			if known then
				found += 1
			end
			if entry.known ~= known or (known and entry.n ~= book.n) then
				entry.known = known
				entry.n = known and book.n or 0
				Ui.clear(entry.cell)
				local def = entry.def
				local rarity = LootConfig.Rarities[def.Rarity]
				Ui.lootIcon(entry.cell, def.Id, 80, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), silhouette = not known })
				Ui.label(if known then def.Name else "???", { Position = UDim2.fromOffset(4, 84), Size = UDim2.new(1, -8, 0, 18), Font = Ui.Fonts.Bold, TextSize = 12, TextWrapped = true, TextColor3 = if known then C.Text else C.Dim, Parent = entry.cell })
				Ui.label(if known then string.format("%s  x%s", def.Rarity, Format.short(book.n)) else (if def.Special then "Rare event" else def.Rarity), { Position = UDim2.fromOffset(4, 104), Size = UDim2.new(1, -8, 0, 16), TextSize = 11, TextColor3 = if known then Ui.rgb(rarity.Color) else C.Dim, Parent = entry.cell })
				if known then
					Ui.stroke(entry.cell, Ui.rgb(rarity.Color), 1, 0.3)
				end
			end
		end
		header.Text = string.format("DISCOVERED %d / %d", found, Progress.bookSize())
	end
	ClientState.ProfileChanged:Connect(function()
		if Ui.isOpen("Book") then
			refresh()
		end
	end)
	return refresh
end

-- Achievements -----------------------------------------------------------------------------

local function buildAchievements(body)
	local list = Ui.scroll(body, { Size = UDim2.fromScale(1, 1) })
	Ui.list(list, 6)
	return function()
		local p = profile()
		Ui.clear(list)
		if not p then
			return
		end
		for i, def in ipairs(QuestConfig.Achievements) do
			local done = p.achievements[def.Id] ~= nil
			local target = Progress.achievementTarget(def)
			local value = p.stats[def.Stat] or 0
			local card = Ui.panel({ Size = UDim2.new(1, -10, 0, 58), LayoutOrder = (if done then 1000 else 0) + i, BackgroundColor3 = if done then C.PanelLighter else C.PanelLight, Parent = list }, 8)
			Ui.label((if done then "[DONE]  " else "") .. def.Name, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -150, 0, 20), Font = Ui.Fonts.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if done then C.Green else C.Text, Parent = card })
			Ui.label(def.Text, { Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -150, 0, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, Parent = card })
			local reward = "+" .. def.Tokens .. " Tokens" .. (if def.Cosmetic then "  + theme" else "")
			Ui.label(reward, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(130, 18), TextSize = 13, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Right, Parent = card })
			local progressText = if target >= 1000 then Format.short(math.min(value, target)) .. " / " .. Format.short(target) else math.min(value, target) .. " / " .. target
			Ui.label(progressText, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 28), Size = UDim2.fromOffset(130, 16), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Right, Parent = card })
			local _, fill = Ui.bar(card, { Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 5) }, if done then C.Green else C.Accent)
			fill.Size = UDim2.fromScale(math.clamp(value / math.max(1, target), 0, 1), 1)
		end
	end
end

-- Daily ------------------------------------------------------------------------------------

local function buildDaily(body)
	local reset = Ui.label("", { Size = UDim2.new(1, 0, 0, 22), TextSize = 14, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
	local list = Ui.new("Frame", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), BackgroundTransparency = 1, Parent = body })
	Ui.list(list, 8)
	local openedAt, resetIn = 0, 0
	RunService.Heartbeat:Connect(function()
		if Ui.isOpen("Daily") then
			reset.Text = "New challenges in " .. Format.clock(math.max(0, resetIn - (os.clock() - openedAt))) .. "  (UTC midnight)"
		end
	end)
	return function()
		local p = profile()
		Ui.clear(list)
		if not p or not p.daily then
			return
		end
		openedAt, resetIn = os.clock(), p.daily.resetIn or 0
		for i, c in ipairs(p.daily.list or {}) do
			local card = Ui.panel({ Size = UDim2.new(1, 0, 0, 70), LayoutOrder = i, BackgroundColor3 = if c.Done then C.PanelLighter else C.PanelLight, Parent = list }, 10)
			Ui.label((if c.Done then "[DONE]  " else "") .. c.Text, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 22), Font = Ui.Fonts.Bold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if c.Done then C.Green else C.Text, Parent = card })
			Ui.label(string.format("Reward: $%s + %d Tokens      %s / %s", Format.short(c.Cash), c.Tokens, Format.short(math.min(c.Progress, c.Target)), Format.short(c.Target)), { Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -28, 0, 18), TextSize = 13, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
			local _, fill = Ui.bar(card, { Position = UDim2.new(0, 14, 1, -12), Size = UDim2.new(1, -28, 0, 6) }, if c.Done then C.Green else C.Blue)
			fill.Size = UDim2.fromScale(math.clamp(c.Progress / math.max(1, c.Target), 0, 1), 1)
		end
	end
end

-- Stats + Rebirth --------------------------------------------------------------------------

local function buildStats(body)
	local left = Ui.scroll(body, { Size = UDim2.new(0.5, -8, 1, 0) })
	Ui.list(left, 4)
	local right = Ui.panel({ Position = UDim2.new(0.5, 8, 0, 0), Size = UDim2.new(0.5, -8, 1, 0), BackgroundColor3 = C.PanelLight }, 10)
	right.Parent = body
	Ui.padding(right, 12, 10)
	local rebirthText = Ui.label("", { Size = UDim2.new(1, 0, 1, -110), TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, RichText = true, Parent = right })
	local box = Ui.new("TextBox", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -54), Size = UDim2.new(1, 0, 0, 40), PlaceholderText = "Type REBIRTH to confirm", Text = "", ClearTextOnFocus = false, BackgroundTransparency = 0, BackgroundColor3 = C.Black, Font = Ui.Fonts.Bold, TextSize = 16, Parent = right })
	Ui.corner(box, 8)
	local button = Ui.button("REBIRTH", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 46), TextSize = 18 }, C.PanelLighter)
	button.Parent = right
	button.Activated:Connect(function()
		local r = profile() and profile().rebirth
		if not r or not r.eligible then
			AudioController.play("NoFunds")
			ClientState.Notified:Fire("Rebirth isn't available yet - see the requirements.", "error")
			return
		end
		if string.upper(box.Text) ~= UpgradeConfig.Rebirth.Confirm then
			ClientState.Notified:Fire("Type REBIRTH in the box to confirm. This resets your Cash, upgrades and depths.", "warn")
			return
		end
		Net.event("Rebirth"):FireServer(UpgradeConfig.Rebirth.Confirm)
		box.Text = ""
	end)
	local function stat(name, value, order)
		local row = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 24), BackgroundTransparency = 1, LayoutOrder = order, Parent = left })
		Ui.label(name, { Size = UDim2.new(0.6, 0, 1, 0), TextSize = 14, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Ui.label(value, { Position = UDim2.fromScale(0.6, 0), Size = UDim2.new(0.4, 0, 1, 0), Font = Ui.Fonts.Bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
	end
	return function()
		local p = profile()
		Ui.clear(left)
		if not p then
			return
		end
		local s = p.stats
		local st = ClientState.stats()
		local found = 0
		for _ in pairs(p.book) do
			found += 1
		end
		local rows = {
			{ "Total earned", "$" .. Format.short(p.totalEarned) },
			{ "Best deposit", "$" .. Format.short(p.bestDeposit) },
			{ "Items collected", Format.exact(s.Collect or 0) },
			{ "Deposits", Format.exact(s.Deposits or 0) },
			{ "Full stacks", Format.exact(s.FullStacks or 0) },
			{ "Rare finds", Format.exact(s.RareFinds or 0) },
			{ "Upgrades bought", Format.exact(s.Upgrades or 0) },
			{ "Deepest unlocked", DepthConfig.get(p.highestDepth).Code .. " " .. DepthConfig.get(p.highestDepth).Name },
			{ "Collection Book", found .. " / " .. Progress.bookSize() },
			{ "Rebirths", tostring(p.rebirths) },
			{ "Capacity", st.Capacity .. " slots" },
			{ "Pickup delay", Format.stat(st.PickupInterval) .. "s" },
			{ "Reach", Format.stat(st.Radius) .. " studs" },
			{ "Loot value", "x" .. Format.stat(st.ValueMult) },
			{ "Deposit payout", "x" .. Format.stat(st.DepositMult) },
			{ "Walk speed", Format.stat(st.WalkSpeed) },
		}
		for i, r in ipairs(rows) do
			stat(r[1], r[2], i)
		end
		local r = p.rebirth
		if r then
			local lines = {
				string.format("<b><font color=\"#B478FF\">REBIRTH %d</font></b>", r.count + 1),
				string.format("Loot value x%s -> <b>x%s</b> forever, +%d Vault Tokens.", Format.stat(r.bonusNow), Format.stat(r.bonusNext), r.tokens),
				string.format("Needs: reach %s and earn $%s since your last rebirth ($%s so far).", DepthConfig.get(r.minDepth).Code, Format.short(r.requirement), Format.short(r.progress)),
				"",
				"<b>Resets:</b> " .. table.concat(r.resets, ", ") .. ".",
				"<b>Keeps:</b> " .. table.concat(r.keeps, ", ") .. ".",
			}
			rebirthText.Text = table.concat(lines, "\n")
			Ui.setButtonColor(button, if r.eligible then C.Purple else C.PanelLighter)
		end
	end
end

-- Leaderboards -----------------------------------------------------------------------------

local function formatBoard(key, value)
	if key == "Depth" then
		local def = DepthConfig.get(math.clamp(math.floor(value), 1, DepthConfig.Count))
		return def.Code .. " " .. def.Name
	end
	for _, lb in ipairs(GameConfig.Leaderboards) do
		if lb.Key == key and not lb.Money then
			return Format.short(value)
		end
	end
	return "$" .. Format.short(value)
end

local function buildLeaderboards(body)
	local current = GameConfig.Leaderboards[1].Key
	local list
	local function fill()
		Ui.clear(list)
		local rows = ClientState.leaderboard[current] or {}
		if #rows == 0 then
			Ui.label("No entries yet (boards refresh every minute; Studio without API access stays empty).", { Size = UDim2.new(1, 0, 0, 40), TextSize = 14, TextWrapped = true, TextColor3 = C.Dim, Parent = list })
		end
		for i, entry in ipairs(rows) do
			local row = Ui.panel({ Size = UDim2.new(1, -10, 0, 34), LayoutOrder = i, BackgroundColor3 = if i <= 3 then C.PanelLighter else C.PanelLight, Parent = list }, 8)
			Ui.label(string.format("%d.  %s", i, entry.name), { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.6, 0, 1, 0), Font = Ui.Fonts.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if i == 1 then C.Accent else C.Text, Parent = row })
			Ui.label(formatBoard(current, entry.value), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0.4, 0, 1, 0), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
		end
	end
	local names, byTitle = {}, {}
	for _, lb in ipairs(GameConfig.Leaderboards) do
		table.insert(names, lb.Title)
		byTitle[lb.Title] = lb.Key
	end
	local _, choose = tabs(body, names, function(title)
		current = byTitle[title]
		if list then
			fill()
		end
	end)
	list = Ui.scroll(body, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })
	Ui.list(list, 4)
	choose(names[1])
	ClientState.LeaderboardChanged:Connect(function()
		if Ui.isOpen("Leaderboards") then
			fill()
		end
	end)
	return fill
end

-- Shop -------------------------------------------------------------------------------------

local function buildShop(body)
	local list = Ui.scroll(body, { Size = UDim2.fromScale(1, 1) })
	Ui.list(list, 8)
	local function section(text, order)
		Ui.label(text, { Size = UDim2.new(1, -10, 0, 24), Font = Ui.Fonts.Bold, TextSize = 15, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, Parent = list })
	end
	local function card(order, title, text, buttonText, color, onClick)
		local c = Ui.panel({ Size = UDim2.new(1, -10, 0, 60), LayoutOrder = order, BackgroundColor3 = C.PanelLight, Parent = list }, 8)
		Ui.label(title, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -170, 0, 22), Font = Ui.Fonts.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Parent = c })
		Ui.label(text, { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -170, 0, 22), TextSize = 12, TextWrapped = true, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = c })
		if buttonText then
			local b = Ui.button(buttonText, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(140, 40), TextSize = 14 }, color)
			b.Parent = c
			b.Activated:Connect(onClick)
		end
	end
	return function()
		local p = profile()
		Ui.clear(list)
		if not p then
			return
		end
		Ui.label("Everything here is optional. The whole game - every depth, upgrade and item - is playable without Robux.", { Size = UDim2.new(1, -10, 0, 34), TextSize = 13, TextWrapped = true, TextColor3 = C.Dim, LayoutOrder = 0, Parent = list })
		local order = 1
		section("ROBUX (OPTIONAL)", order)
		for _, pass in ipairs(ShopConfig.Passes) do
			order += 1
			local owned = (pass.Key == "VIP" and p.vip) or (pass.Kind and p.owned[pass.Kind .. ":" .. pass.Item])
			card(order, pass.Name .. " (Pass)", pass.Description, if owned then "OWNED" else "R$ " .. pass.Robux, if owned then C.PanelLighter else C.Green, function()
				if not owned then
					Net.event("ShopBuy"):FireServer(pass.Key)
				end
			end)
		end
		for _, product in ipairs(ShopConfig.Products) do
			order += 1
			local owned = product.Kind and p.owned[product.Kind .. ":" .. product.Item]
			card(order, product.Name, product.Description, if owned then "OWNED" else "R$ " .. product.Robux, if owned then C.PanelLighter else C.Green, function()
				if not owned then
					Net.event("ShopBuy"):FireServer(product.Key)
				end
			end)
		end
		for _, kind in ipairs(CosmeticConfig.KindOrder) do
			order += 1
			section(string.upper(if kind == "DepositFx" then "Deposit effects" elseif kind == "Theme" then "Stack themes" else "Trails"), order)
			local items = {}
			for id, def in pairs(CosmeticConfig.Kinds[kind]) do
				table.insert(items, { id = id, def = def })
			end
			table.sort(items, function(a, b)
				return a.def.Order < b.def.Order
			end)
			for _, item in ipairs(items) do
				order += 1
				local key = kind .. ":" .. item.id
				local owned = p.owned[key] == true
				local equipped = p.cosmetics[kind] == item.id
				local label, color, action
				if equipped then
					label, color = "EQUIPPED", C.PanelLighter
				elseif owned then
					label, color = "EQUIP", C.Accent
					action = function()
						Net.event("Equip"):FireServer(kind, item.id)
					end
				elseif item.def.Source == "Tokens" then
					label, color = item.def.Cost .. " TOKENS", if p.tokens >= item.def.Cost then C.Accent else C.PanelLighter
					action = function()
						Net.event("BuyCosmetic"):FireServer(kind, item.id)
					end
				elseif item.def.Source == "Achievement" then
					label, color = "ACHIEVEMENT", C.PanelLighter
				else
					label, color = "SEE ROBUX", C.PanelLighter
				end
				card(order, item.def.Name, item.def.Description, label, color, function()
					if action then
						action()
					end
				end)
			end
		end
	end
end

-- Settings ---------------------------------------------------------------------------------

local function buildSettings(body)
	local list = Ui.scroll(body, { Size = UDim2.fromScale(1, 1) })
	Ui.list(list, 6)
	local function slider(key, title, order)
		local row = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 40), BackgroundTransparency = 1, LayoutOrder = order, Parent = list })
		Ui.label(title, { Size = UDim2.new(0.35, 0, 1, 0), Font = Ui.Fonts.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local track, fill = Ui.bar(row, { Position = UDim2.new(0.38, 0, 0.5, -6), Size = UDim2.new(0.5, 0, 0, 12) }, C.Accent)
		local valueLabel = Ui.label("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(50, 40), TextSize = 14, Parent = row })
		local function show()
			local v = ClientState.setting(key) or 1
			fill.Size = UDim2.fromScale(v, 1)
			valueLabel.Text = math.floor(v * 100 + 0.5) .. "%"
		end
		local dragging = false
		local function set(x)
			local v = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
			v = math.floor(v * 20 + 0.5) / 20
			ClientState.applySettings({ [key] = v })
			show()
		end
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				set(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				set(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				dragging = false
				ClientState.saveSettings()
			end
		end)
		return show
	end
	local function toggle(key, title, text, order)
		local row = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 44), BackgroundTransparency = 1, LayoutOrder = order, Parent = list })
		Ui.label(title, { Size = UDim2.new(1, -120, 0, 22), Font = Ui.Fonts.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Ui.label(text, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -120, 0, 18), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local b = Ui.button("", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(100, 34), TextSize = 14 }, C.PanelLighter)
		b.Parent = row
		local function show()
			local on = ClientState.setting(key) == true
			b.Text = if on then "ON" else "OFF"
			Ui.setButtonColor(b, if on then C.Green else C.PanelLighter)
		end
		b.Activated:Connect(function()
			ClientState.applySettings({ [key] = not (ClientState.setting(key) == true) })
			ClientState.saveSettings()
			show()
		end)
		return show
	end
	local shows = {
		slider("Master", "Master volume", 1),
		slider("Effects", "Effects", 2),
		slider("Ambient", "Ambience", 3),
		slider("Music", "Music", 4),
		slider("UI", "Interface", 5),
		toggle("AutoDeposit", "Auto-deposit zone", "Walk into the painted zone in front of a machine to deposit.", 6),
		toggle("ShowOthers", "Show other players' stacks", "Turn off to save performance in busy servers.", 7),
		toggle("ReducedEffects", "Reduced effects", "Fewer particles, fly-ins and stack pieces.", 8),
		toggle("CameraShake", "Camera sway", "Gentle sway during elevator rides.", 9),
	}
	local replay = Ui.button("REPLAY TUTORIAL", { Size = UDim2.new(1, -10, 0, 38), TextSize = 14, LayoutOrder = 10 }, C.PanelLight)
	replay.Parent = list
	replay.Activated:Connect(function()
		Net.event("Tutorial"):FireServer("Replay")
		Ui.closeAll()
	end)
	local codeRow = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 40), BackgroundTransparency = 1, LayoutOrder = 11, Parent = list })
	local box = Ui.new("TextBox", { Size = UDim2.new(1, -130, 1, 0), PlaceholderText = "Enter a code", Text = "", BackgroundTransparency = 0, BackgroundColor3 = C.Black, Font = Ui.Fonts.Bold, TextSize = 15, ClearTextOnFocus = false, Parent = codeRow })
	Ui.corner(box, 8)
	local redeem = Ui.button("REDEEM", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 120, 1, 0), TextSize = 14 }, C.Accent)
	redeem.Parent = codeRow
	redeem.Activated:Connect(function()
		if #box.Text > 0 then
			Net.event("RedeemCode"):FireServer(box.Text)
			box.Text = ""
		end
	end)
	return function()
		for _, show in ipairs(shows) do
			show()
		end
	end
end

-- Init -------------------------------------------------------------------------------------

function MenuController.refresh(name)
	if refreshers[name] then
		refreshers[name]()
	end
end

function MenuController.init()
	gui = Ui.screen("VaultMenus", 10)
	register("Upgrades", "UPGRADES", 680, 560, buildUpgrades)
	register("Depths", "DEPTHS", 540, 590, buildDepths)
	register("Book", "COLLECTION BOOK", 700, 580, buildBook)
	register("Achievements", "ACHIEVEMENTS", 620, 560, buildAchievements)
	register("Daily", "DAILY CHALLENGES", 560, 330, buildDaily)
	register("Stats", "STATS & REBIRTH", 700, 520, buildStats)
	register("Leaderboards", "LEADERBOARDS", 640, 520, buildLeaderboards)
	register("Shop", "SHOP", 620, 580, buildShop)
	register("Settings", "SETTINGS", 560, 600, buildSettings)
	Ui.clickHandler = function()
		AudioController.play("UiClick")
	end
	InputController.setMenuOpener(Ui.toggleWindow)
	for _, name in ipairs({ "Achievements", "Daily", "Stats", "Shop" }) do
		ClientState.ProfileChanged:Connect(function()
			if Ui.isOpen(name) then
				refreshers[name]()
			end
		end)
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.ActionText == "Upgrades" then
			Ui.openWindow("Upgrades")
		end
	end)
end

return MenuController
