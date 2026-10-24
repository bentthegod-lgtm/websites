--[[
	StoreController - the Robux shop (SHOP button on the HUD). Tabs: Coins, Boosts,
	Crates (with the full odds table) and Passes. Buttons send ShopBuy; the server prompts
	the real purchase (or grants for free in Studio while IDs are 0).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SproutValley")
local Net = require(Shared.Net)
local ShopConfig = require(Shared.Config.ShopConfig)
local CropConfig = require(Shared.Config.CropConfig)
local Crate = require(Shared.Crate)
local Format = require(Shared.Format)

local Ui = require(script.Parent.Ui)
local ClientState = require(script.Parent.ClientState)

local StoreController = {}

local C = Ui.Colors
local gui, list, tabs
local current = "Coins"

local TAB_COLORS = { Coins = C.Gold, Boosts = C.Green, Crates = C.Orange, Passes = C.Pink }
local TAB_NAMES = { Coins = "COINS", Boosts = "BOOSTS", Crates = "CRATES", Passes = "PASSES" }

local function card(order, color, title, description, robux, key, owned)
	local row = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 92), BackgroundColor3 = color:Lerp(C.Cream, 0.75), LayoutOrder = order, Parent = list })
	Ui.corner(row, 14)
	Ui.stroke(row, color:Lerp(Color3.new(0, 0, 0), 0.35), 2.5)
	local icon = Ui.new("Frame", { Position = UDim2.fromOffset(10, 12), Size = UDim2.fromOffset(68, 68), BackgroundColor3 = color, Parent = row })
	Ui.corner(icon, 16)
	Ui.stroke(icon, color:Lerp(Color3.new(0, 0, 0), 0.45), 2.5)
	Ui.gradient(icon, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	local letter = Ui.title(string.sub(title, 1, 1), { Size = UDim2.fromScale(1, 1), TextSize = 40, TextColor3 = C.White, Parent = icon })
	Ui.textStroke(letter, color:Lerp(Color3.new(0, 0, 0), 0.6), 2)
	Ui.title(title, { Position = UDim2.fromOffset(90, 8), Size = UDim2.new(1, -250, 0, 28), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	Ui.label(description, { Position = UDim2.fromOffset(90, 38), Size = UDim2.new(1, -250, 0, 46), TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.Brown:Lerp(C.Dim, 0.4), Parent = row })
	local buy = Ui.button(if owned then "OWNED" else "R$ " .. tostring(robux), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 54), TextSize = 22, Parent = row }, if owned then C.Dim else C.Green)
	buy.Activated:Connect(function()
		if not owned then
			Net.event("ShopBuy"):FireServer(key)
		end
	end)
	return row
end

local function oddsTable(crateKey, order)
	local crate = ShopConfig.Crates[crateKey]
	local box = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.CreamDark, LayoutOrder = order, Parent = list })
	Ui.corner(box, 12)
	Ui.stroke(box, C.BrownLight, 1.5)
	Ui.padding(box, 12, 8)
	Ui.list(box, 4)
	Ui.title(crate.Name .. " odds", { Size = UDim2.new(1, 0, 0, 24), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, Parent = box })
	for i, entry in ipairs(Crate.odds(crate, CropConfig.List)) do
		local names = {}
		for _, id in ipairs(entry.crops) do
			table.insert(names, CropConfig.ById[id].Name)
		end
		local line = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = i, Parent = box })
		local rarity = Ui.title(entry.rarity, { Size = UDim2.fromOffset(110, 22), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Ui.rarityColor(entry.rarity), Parent = line })
		Ui.textStroke(rarity, C.Shadow, 1)
		Ui.title(string.format("%.1f%%", entry.chance * 100), { Position = UDim2.fromOffset(112, 0), Size = UDim2.fromOffset(70, 22), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right, Parent = line })
		Ui.label(table.concat(names, ", "), { Position = UDim2.fromOffset(196, 0), Size = UDim2.new(1, -196, 1, 0), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Dim, Parent = line })
	end
	Ui.label("Each crop in a rarity is equally likely. Seeds go straight to your hotbar.", { Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = C.Dim, LayoutOrder = 99, Parent = box })
end

local function render()
	if not list then
		return
	end
	Ui.clear(list)
	for name, button in pairs(tabs) do
		button.BackgroundColor3 = if name == current then TAB_COLORS[name] else C.Dim
	end
	local passes = ClientState.profile and ClientState.profile.passes or {}
	local order = 0
	if current == "Passes" then
		for _, pass in ipairs(ShopConfig.Passes) do
			order += 1
			card(order, Ui.rgb(pass.Color), pass.Name, pass.Description, pass.Robux, pass.Key, passes[pass.Key] == true)
		end
		return
	end
	for _, product in ipairs(ShopConfig.Products) do
		if product.Category == current then
			order += 1
			local description = product.Description or (if product.Coins then string.format("+%s Coins straight to your wallet.", Format.coins(product.Coins)) else "")
			card(order, Ui.rgb(product.Color), product.Name, description, product.Robux, product.Key, false)
		end
	end
	if current == "Crates" then
		oddsTable("SeedCrate", order + 1)
	end
end

function StoreController.show(tab)
	current = tab or current
	Ui.openWindow("Store")
	render()
end

function StoreController.init()
	gui = Ui.screen("SproutStore", 6)
	local _, body = Ui.window(gui, "Store", "Shop", 720, 580, C.Pink)
	local tabRow = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = body })
	Ui.list(tabRow, 8, Enum.FillDirection.Horizontal)
	tabs = {}
	for i, name in ipairs(ShopConfig.CategoryOrder) do
		local b = Ui.button(TAB_NAMES[name] or name, { Size = UDim2.fromOffset(150, 42), TextSize = 18, LayoutOrder = i, Parent = tabRow }, TAB_COLORS[name] or C.Green)
		b.Activated:Connect(function()
			current = name
			render()
		end)
		tabs[name] = b
	end
	list = Ui.scroll(body, { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54) })
	Ui.list(list, 8)
	Ui.onWindowOpen("Store", render)
	ClientState.ProfileChanged:Connect(function()
		if Ui.isOpen("Store") then
			render()
		end
	end)
end

return StoreController
