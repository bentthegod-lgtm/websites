--[[
	PanelsController - the coin-economy windows: Seed Shop, Gear Shop, Sell Stand,
	Backpack (favourites + gifting) and Rewards (daily streak, codes, goals, settings).
	Stall windows open from the NPC ProximityPrompts (server sends OpenPanel).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local Net = require(Shared.Net)
local CropConfig = require(Shared.Config.CropConfig)
local GearConfig = require(Shared.Config.GearConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local PanelsController = {}

local player = Players.LocalPlayer
local C = Ui.Colors

local gui
local seedList, seedTimer
local gearList
local sellSummary, sellList
local bagList, bagHeader, bagFill, giftPicker
local rewardsBody
local codeBox

local restockProduct
for _, p in ipairs(ShopConfig.Products) do
	if p.Key == "InstantRestock" then
		restockProduct = p
	end
end

function PanelsController.itemName(item)
	local parts = {}
	if item.variant then
		table.insert(parts, item.variant)
	end
	for _, m in ipairs(item.mutations or {}) do
		table.insert(parts, m)
	end
	local crop = CropConfig.ById[item.crop]
	table.insert(parts, crop and crop.Name or item.crop)
	return table.concat(parts, " ")
end

local function priceTag(parent, amount, props)
	local holder = Ui.new("Frame", props)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	Ui.coinIcon(holder, 18, { Position = UDim2.new(0, 0, 0.5, -9) })
	Ui.title(Format.coins(amount), { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 1, 0), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 140, 20), Parent = holder })
	return holder
end

local function rowFrame(parent, order, height)
	local row = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, height or 72), BackgroundColor3 = C.CreamDark, LayoutOrder = order, Parent = parent })
	Ui.corner(row, 12)
	Ui.stroke(row, C.BrownLight, 1.5)
	return row
end

local function mutationChips(parent, item)
	local holder = Ui.new("Frame", { BackgroundTransparency = 1, Parent = parent })
	Ui.list(holder, 3, Enum.FillDirection.Horizontal)
	if item.variant and MutationConfig.Variants[item.variant] then
		Ui.chip(holder, item.variant, Ui.rgb(MutationConfig.Variants[item.variant].Color), 0)
	end
	for i, m in ipairs(item.mutations or {}) do
		local def = MutationConfig.Mutations[m]
		if def then
			Ui.chip(holder, m, Ui.rgb(def.Color), i)
		end
	end
	return holder
end

local function rarityLabel(parent, rarity, props)
	local label = Ui.title(string.upper(rarity), props)
	label.TextColor3 = Ui.rarityColor(rarity)
	label.Parent = parent
	Ui.textStroke(label, C.Shadow, 1.2)
	if rarity == "Prismatic" then
		label.TextColor3 = C.White
		Ui.prismatic(label)
	end
	return label
end

---------------------------------------------------------------------------------------------
-- Seed Shop
---------------------------------------------------------------------------------------------

local function renderSeeds()
	if not seedList or not Ui.isOpen("SeedShop") then
		return
	end
	Ui.clear(seedList)
	local stock = ClientState.stock or { items = {} }
	local profile = ClientState.profile or { coins = 0, seeds = {} }
	local inStock = {}
	for _, item in ipairs(stock.items or {}) do
		inStock[item.crop] = item
	end
	for i, crop in ipairs(CropConfig.List) do
		local item = inStock[crop.Id]
		local row = rowFrame(seedList, if item then i else 100 + i)
		if not item then
			row.BackgroundTransparency = 0.45
		end
		Ui.cropIcon(row, crop.Id, 60, { Position = UDim2.fromOffset(6, 6) })
		Ui.title(crop.Name, { Position = UDim2.fromOffset(74, 6), Size = UDim2.fromOffset(220, 26), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		rarityLabel(row, crop.Rarity, { Position = UDim2.fromOffset(74, 32), Size = UDim2.fromOffset(110, 18), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left })
		local detail = if crop.Regrow then string.format("Grows %s, regrows every %s", Format.duration(crop.GrowTime), Format.duration(crop.Regrow)) else "Grows in " .. Format.duration(crop.GrowTime)
		Ui.label(detail, { Position = UDim2.fromOffset(74, 50), Size = UDim2.fromOffset(300, 16), TextSize = 12, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		priceTag(row, crop.SeedPrice, { Position = UDim2.new(1, -250, 0, 10), Size = UDim2.fromOffset(110, 24) })
		local owned = profile.seeds[crop.Id] or 0
		Ui.label(if owned > 0 then string.format("You have %d", owned) else "", { Position = UDim2.new(1, -250, 0, 38), Size = UDim2.fromOffset(110, 18), TextSize = 13, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		if item then
			local soldOut = item.left <= 0
			local affordable = profile.coins >= crop.SeedPrice
			local buy = Ui.button(if soldOut then "SOLD OUT" else string.format("BUY  x%d", item.left), {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(128, 46),
				TextSize = 18,
				Parent = row,
			}, if soldOut then C.Dim elseif affordable then C.Green else C.Orange)
			buy.Activated:Connect(function()
				if not soldOut then
					Net.event("BuySeed"):FireServer(crop.Id)
				end
			end)
		else
			Ui.title("Not in stock", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(128, 30), TextSize = 16, TextColor3 = C.Dim, Parent = row })
		end
	end
end

local function buildSeedShop()
	local _, body = Ui.window(gui, "SeedShop", "Seed Shop", 700, 560, C.Green)
	local top = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = body })
	seedTimer = Ui.title("Restock in 5:00", { Size = UDim2.new(1, -230, 1, 0), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.GreenDark, Parent = top })
	local restock = Ui.button(string.format("RESTOCK FOR ALL  R$ %d", restockProduct and restockProduct.Robux or 0), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(225, 44), TextSize = 16, Parent = top }, C.Pink)
	restock.Activated:Connect(function()
		Net.event("ShopBuy"):FireServer("InstantRestock")
	end)
	seedList = Ui.scroll(body, { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 1, -56) })
	Ui.list(seedList, 6)
	Ui.onWindowOpen("SeedShop", renderSeeds)
end

---------------------------------------------------------------------------------------------
-- Gear Shop
---------------------------------------------------------------------------------------------

local function renderGear()
	if not gearList or not Ui.isOpen("GearShop") then
		return
	end
	Ui.clear(gearList)
	local profile = ClientState.profile or { coins = 0, gear = {} }
	for i, id in ipairs(GearConfig.Order) do
		local def = GearConfig.Gear[id]
		local row = rowFrame(gearList, i, 84)
		local icon = Ui.new("Frame", { Position = UDim2.fromOffset(8, 10), Size = UDim2.fromOffset(62, 62), BackgroundColor3 = Ui.rgb(def.Color), Parent = row })
		Ui.corner(icon, 14)
		Ui.stroke(icon, Ui.rgb(def.Color):Lerp(Color3.new(0, 0, 0), 0.4), 2)
		Ui.title(string.sub(def.Name, 1, 1), { Size = UDim2.fromScale(1, 1), TextSize = 34, TextColor3 = C.White, Parent = icon })
		Ui.title(def.Name, { Position = UDim2.fromOffset(80, 6), Size = UDim2.fromOffset(260, 26), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Ui.label(def.Description, { Position = UDim2.fromOffset(80, 32), Size = UDim2.new(1, -330, 0, 44), TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.Dim, Parent = row })
		priceTag(row, def.Price, { Position = UDim2.new(1, -240, 0, 12), Size = UDim2.fromOffset(100, 24) })
		local owned = profile.gear[id] or 0
		Ui.label(if def.Permanent then (if owned > 0 then "Owned" else "") else string.format("Have: %d", owned), { Position = UDim2.new(1, -240, 0, 42), Size = UDim2.fromOffset(100, 18), TextSize = 13, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local done = def.Permanent and owned > 0
		local buy = Ui.button(if done then "OWNED" else "BUY", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 46), Parent = row }, if done then C.Dim elseif profile.coins >= def.Price then C.Sky else C.Orange)
		buy.Activated:Connect(function()
			if not done then
				Net.event("BuyGear"):FireServer(id)
			end
		end)
	end
end

local function buildGearShop()
	local _, body = Ui.window(gui, "GearShop", "Gear Shop", 700, 520, C.Sky)
	gearList = Ui.scroll(body, { Size = UDim2.fromScale(1, 1) })
	Ui.list(gearList, 6)
	Ui.onWindowOpen("GearShop", renderGear)
end

---------------------------------------------------------------------------------------------
-- Sell Stand
---------------------------------------------------------------------------------------------

local function itemRow(parent, order, item, options)
	local crop = CropConfig.ById[item.crop]
	local row = rowFrame(parent, order, 58)
	local dot = Ui.new("Frame", { Position = UDim2.fromOffset(10, 13), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = if crop then Ui.rgb(crop.Model.Fruit) else C.Dim, Parent = row })
	Ui.corner(dot, 16)
	Ui.stroke(dot, C.Brown, 2)
	local name = Ui.title(PanelsController.itemName(item), { Position = UDim2.fromOffset(52, 4), Size = UDim2.new(1, -330, 0, 24), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
	if crop then
		name.TextColor3 = Ui.rarityColor(crop.Rarity):Lerp(C.Brown, 0.4)
	end
	local chips = mutationChips(row, item)
	chips.Position = UDim2.fromOffset(52, 30)
	chips.Size = UDim2.new(1, -330, 0, 20)
	Ui.label(Format.kg(item.kg), { Position = UDim2.new(1, -270, 0, 0), Size = UDim2.fromOffset(70, 58), TextSize = 15, Font = Ui.Fonts.Bold, Parent = row })
	priceTag(row, item.value, { Position = UDim2.new(1, -200, 0, 17), Size = UDim2.fromOffset(90, 24) })
	local star = Ui.button(if item.favorite then "FAV" else "fav", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -60, 0.5, 0), Size = UDim2.fromOffset(46, 38), TextSize = 14, Parent = row }, if item.favorite then C.Gold else C.Dim)
	star.Activated:Connect(function()
		Net.event("Favorite"):FireServer(item.id)
	end)
	local action = Ui.button(options.actionText, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(48, 38), TextSize = 14, Parent = row }, options.actionColor)
	action.Activated:Connect(function()
		options.onAction(item)
	end)
	return row
end

local function sortedItems(profile)
	local items = table.clone(profile.backpack or {})
	table.sort(items, function(a, b)
		return a.value > b.value
	end)
	return items
end

local function renderSell()
	if not sellList or not Ui.isOpen("Sell") then
		return
	end
	local profile = ClientState.profile
	Ui.clear(sellList)
	Ui.clear(sellSummary)
	if not profile then
		return
	end
	local total, count = 0, 0
	for _, item in ipairs(profile.backpack) do
		if not item.favorite then
			total += item.value
			count += 1
		end
	end
	local mult = profile.sellMultiplier or 1
	Ui.title(string.format("%d fruit to sell", count), { Size = UDim2.new(0.5, 0, 0, 30), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Parent = sellSummary })
	local bonus = {}
	if profile.passes and profile.passes.DoubleSell then
		table.insert(bonus, "2x Sell pass")
	end
	if (profile.friends or 0) > 0 then
		table.insert(bonus, string.format("+%d%% friends", math.floor(math.min(profile.friends * GameConfig.FriendBoostPer, GameConfig.FriendBoostMax) * 100)))
	end
	Ui.label(if #bonus > 0 then "Bonus: " .. table.concat(bonus, ", ") else "Tip: friends in the server give +10% each!", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(0.6, 0, 0, 20), TextSize = 14, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Left, Parent = sellSummary })
	priceTag(sellSummary, math.floor(total * mult + 0.5), { Position = UDim2.fromOffset(0, 54), Size = UDim2.fromOffset(200, 30) })
	local sellAll = Ui.button("SELL ALL", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(200, 64), TextSize = 26, Parent = sellSummary }, if count > 0 then C.Orange else C.Dim)
	sellAll.Activated:Connect(function()
		Net.event("Sell"):FireServer("All")
	end)
	for i, item in ipairs(sortedItems(profile)) do
		itemRow(sellList, i, item, {
			actionText = "SELL",
			actionColor = C.Orange,
			onAction = function(it)
				Net.event("Sell"):FireServer("Item", it.id)
			end,
		})
	end
end

local function buildSell()
	local _, body = Ui.window(gui, "Sell", "Sell Stand", 680, 560, C.Orange)
	sellSummary = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 90), BackgroundTransparency = 1, Parent = body })
	sellList = Ui.scroll(body, { Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 1, -96) })
	Ui.list(sellList, 5)
	Ui.onWindowOpen("Sell", renderSell)
end

---------------------------------------------------------------------------------------------
-- Backpack + gifting
---------------------------------------------------------------------------------------------

local function nearbyPlayers()
	local list = {}
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local oc = other.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart")
			if root and oroot and (root.Position - oroot.Position).Magnitude <= GameConfig.GiftRange then
				table.insert(list, other)
			end
		end
	end
	return list
end

local function openGiftPicker(item)
	Ui.clear(giftPicker)
	giftPicker.Visible = true
	Ui.title("Gift " .. PanelsController.itemName(item) .. " to:", { Size = UDim2.new(1, 0, 0, 26), TextSize = 18, LayoutOrder = 0, Parent = giftPicker })
	local others = nearbyPlayers()
	if #others == 0 then
		Ui.label("Nobody is close enough. Stand next to a friend!", { Size = UDim2.new(1, 0, 0, 22), TextSize = 14, LayoutOrder = 1, Parent = giftPicker })
	end
	for i, other in ipairs(others) do
		local b = Ui.button(other.DisplayName, { Size = UDim2.new(1, 0, 0, 38), LayoutOrder = i + 1, Parent = giftPicker }, C.Pink)
		b.Activated:Connect(function()
			Net.event("Gift"):FireServer(other.UserId, item.id)
			giftPicker.Visible = false
		end)
	end
	local cancel = Ui.button("Cancel", { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 99, Parent = giftPicker }, C.Dim)
	cancel.Activated:Connect(function()
		giftPicker.Visible = false
	end)
end

local function renderBag()
	if not bagList or not Ui.isOpen("Backpack") then
		return
	end
	local profile = ClientState.profile
	Ui.clear(bagList)
	if not profile then
		return
	end
	local total = 0
	for _, item in ipairs(profile.backpack) do
		total += item.value
	end
	bagHeader.Text = string.format("%d / %d fruit  -  worth %s Coins", #profile.backpack, profile.capacity, Format.coins(total))
	bagFill.Size = UDim2.fromScale(math.clamp(#profile.backpack / math.max(profile.capacity, 1), 0, 1), 1)
	bagFill.BackgroundColor3 = if #profile.backpack >= profile.capacity then C.Red else C.Green
	if #profile.backpack == 0 then
		Ui.label("Your backpack is empty. Harvest ripe crops in your garden!", { Size = UDim2.new(1, 0, 0, 40), TextSize = 16, Parent = bagList })
	end
	for i, item in ipairs(sortedItems(profile)) do
		itemRow(bagList, i, item, { actionText = "GIFT", actionColor = C.Pink, onAction = openGiftPicker })
	end
end

local function buildBag()
	local frame, body = Ui.window(gui, "Backpack", "Backpack", 680, 560, C.BrownLight)
	bagHeader = Ui.title("", { Size = UDim2.new(1, 0, 0, 26), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
	local _, fill = Ui.bar(body, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 14) }, C.Green)
	bagFill = fill
	bagList = Ui.scroll(body, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52) })
	Ui.list(bagList, 5)
	giftPicker = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(320, 60), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 40, Parent = frame })
	Ui.padding(giftPicker, 12, 10)
	Ui.list(giftPicker, 6)
	Ui.onWindowOpen("Backpack", renderBag)
end

---------------------------------------------------------------------------------------------
-- Rewards (daily, codes, goals, settings)
---------------------------------------------------------------------------------------------

local function bundleText(bundle)
	local parts = {}
	if bundle.Coins then
		table.insert(parts, Format.coins(bundle.Coins) .. " Coins")
	end
	for crop, n in pairs(bundle.Seeds or {}) do
		table.insert(parts, string.format("%dx %s", n, CropConfig.ById[crop] and CropConfig.ById[crop].Name or crop))
	end
	for gear, n in pairs(bundle.Gear or {}) do
		table.insert(parts, string.format("%dx %s", n, GearConfig.Gear[gear] and GearConfig.Gear[gear].Name or gear))
	end
	return table.concat(parts, "\n")
end

local function section(text, order)
	return Ui.title(text, { Size = UDim2.new(1, -10, 0, 30), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Purple:Lerp(C.Brown, 0.3), LayoutOrder = order, Parent = rewardsBody })
end

local function renderRewards()
	if not rewardsBody or not Ui.isOpen("Rewards") then
		return
	end
	local keepText = codeBox and codeBox.Text or ""
	Ui.clear(rewardsBody)
	local profile = ClientState.profile
	if not profile then
		return
	end
	local daily = profile.daily or { canClaim = false, day = 1, streak = 1, secondsLeft = 0 }
	section(string.format("Daily Reward  -  streak: %d day%s", daily.lastStreak or 0, if (daily.lastStreak or 0) == 1 then "" else "s"), 10)
	local days = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 130), BackgroundTransparency = 1, LayoutOrder = 20, Parent = rewardsBody })
	Ui.list(days, 6, Enum.FillDirection.Horizontal)
	for i, bundle in ipairs(GameConfig.Daily) do
		local isNext = i == daily.day
		local claimed = (not daily.canClaim and i <= daily.day) or (daily.canClaim and i < daily.day)
		local card = Ui.panel({ Size = UDim2.fromOffset(84, 124), BackgroundColor3 = if isNext and daily.canClaim then Color3.fromRGB(255, 240, 180) elseif claimed then Color3.fromRGB(220, 240, 210) else C.CreamDark, LayoutOrder = i, Parent = days }, 12)
		Ui.title("Day " .. i, { Size = UDim2.new(1, 0, 0, 24), TextSize = 18, Parent = card })
		Ui.label(bundleText(bundle), { Position = UDim2.fromOffset(4, 26), Size = UDim2.new(1, -8, 1, -52), TextSize = 11, TextWrapped = true, Font = Ui.Fonts.Bold, Parent = card })
		Ui.label(if claimed then "CLAIMED" elseif isNext then "NEXT" else "", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 18), TextSize = 12, Font = Ui.Fonts.Bold, TextColor3 = if claimed then C.GreenDark else C.Orange, Parent = card })
	end
	local claim = Ui.button(if daily.canClaim then "CLAIM DAY " .. daily.day .. " REWARD" else "NEXT REWARD IN " .. Format.duration(daily.secondsLeft), { Size = UDim2.new(1, -10, 0, 48), TextSize = 20, LayoutOrder = 30, Parent = rewardsBody }, if daily.canClaim then C.Green else C.Dim)
	claim.Activated:Connect(function()
		Net.event("ClaimDaily"):FireServer()
	end)

	section("Goals", 40)
	for i, goal in ipairs(profile.goals or {}) do
		local row = rowFrame(rewardsBody, 40 + i, 52)
		Ui.label(goal.text, { Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -140, 0, 22), TextSize = 16, Font = Ui.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local _, fill = Ui.bar(row, { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -140, 0, 14) }, C.Green)
		fill.Size = UDim2.fromScale(math.clamp(goal.progress / math.max(goal.target, 1), 0, 1), 1)
		priceTag(row, goal.reward, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(110, 24) })
	end

	section("Codes", 50)
	local codeRow = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 46), BackgroundTransparency = 1, LayoutOrder = 51, Parent = rewardsBody })
	codeBox = Ui.new("TextBox", { Size = UDim2.new(1, -140, 1, 0), BackgroundTransparency = 0, BackgroundColor3 = C.White, PlaceholderText = "Enter code (try RELEASE)", Text = keepText, TextSize = 18, Font = Ui.Fonts.Bold, ClearTextOnFocus = false, Parent = codeRow })
	Ui.corner(codeBox, 10)
	Ui.stroke(codeBox, C.BrownLight, 2)
	local redeem = Ui.button("REDEEM", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(130, 46), Parent = codeRow }, C.Purple)
	redeem.Activated:Connect(function()
		if codeBox.Text ~= "" then
			Net.event("RedeemCode"):FireServer(codeBox.Text)
			codeBox.Text = ""
		end
	end)
	Ui.label(GameConfig.CodesHint, { Size = UDim2.new(1, -10, 0, 20), TextSize = 14, TextColor3 = C.Dim, LayoutOrder = 52, Parent = rewardsBody })

	section("Settings", 60)
	local settings = profile.settings or {}
	for i, entry in ipairs({ { "AcceptGifts", "Accept gifts from other players" }, { "Music", "Music" } }) do
		local on = settings[entry[1]] ~= false
		local toggle = Ui.button((if on then "ON   " else "OFF  ") .. entry[2], { Size = UDim2.new(1, -10, 0, 40), TextSize = 16, LayoutOrder = 60 + i, Parent = rewardsBody }, if on then C.Green else C.Dim)
		toggle.Activated:Connect(function()
			Net.event("SetSetting"):FireServer(entry[1], not on)
		end)
	end
	Ui.label(profile.persistent and "Your progress is saved automatically." or "Saving is unavailable on this server (Studio).", { Size = UDim2.new(1, -10, 0, 20), TextSize = 13, TextColor3 = C.Dim, LayoutOrder = 70, Parent = rewardsBody })
end

local function buildRewards()
	local _, body = Ui.window(gui, "Rewards", "Rewards", 700, 580, C.Purple)
	rewardsBody = Ui.scroll(body, { Size = UDim2.fromScale(1, 1) })
	Ui.list(rewardsBody, 8)
	Ui.onWindowOpen("Rewards", renderRewards)
end

---------------------------------------------------------------------------------------------

local PANEL_FOR = { SeedShop = "SeedShop", GearShop = "GearShop", Sell = "Sell" }

function PanelsController.init()
	gui = Ui.screen("SproutPanels", 5)
	Ui.WindowChanged = ClientState.WindowChanged
	buildSeedShop()
	buildGearShop()
	buildSell()
	buildBag()
	buildRewards()
	ClientState.PanelRequested:Connect(function(name)
		if PANEL_FOR[name] then
			Ui.openWindow(PANEL_FOR[name])
		end
	end)
	ClientState.StockChanged:Connect(renderSeeds)
	ClientState.ProfileChanged:Connect(function()
		renderSeeds()
		renderGear()
		renderSell()
		renderBag()
		renderRewards()
	end)
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then
			return
		end
		accumulator = 0
		if seedTimer and Ui.isOpen("SeedShop") then
			local nextAt = workspace:GetAttribute("SV_NextRestock") or 0
			seedTimer.Text = "Restock in " .. Format.clock(math.max(0, nextAt - ClientState.serverNow()))
		end
	end)
end

-- For the harness / debugging: render every window once.
function PanelsController.renderAll()
	for _, name in ipairs({ "SeedShop", "GearShop", "Sell", "Backpack", "Rewards" }) do
		Ui.openWindow(name)
	end
	Ui.closeAll()
end

PanelsController.RarityOrder = RarityConfig.Order

return PanelsController
