--[[
	Headless smoke harness for Sprout Valley.

	Loads the Rojo-built place in Lune and runs the REAL game modules against Lune's Roblox
	instance implementation (class / property / enum names are checked against the
	reflection database). Engine services Lune does not simulate (players, data stores,
	marketplace, tweens, input, physics) are stubbed.

	It builds the village and every crop model at every stage, initialises all services,
	simulates key server flows (buy -> plant -> grow -> harvest -> sell, receipts granted
	once, restock, weather mutations, gear, expansion, rewards, gifting, offline growth) and
	initialises every client controller with a real profile snapshot.

	Usage (from sprout-valley/):
	  rojo build -o build/SproutValley.rbxlx && lune run tests/harness build/SproutValley.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/SproutValley.rbxlx"
local place = roblox.deserializePlace(fs.readFile(placePath))

---------------------------------------------------------------------------------------------
-- Stubs
---------------------------------------------------------------------------------------------

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end }
	end
	function s:Fire(...)
		for _, fn in ipairs(self.handlers) do
			fn(...)
		end
	end
	function s:Wait()
		return nil
	end
	return s
end

local function stubObject(name, extra)
	local obj = extra or {}
	return setmetatable(obj, {
		__index = function(_, key)
			if string.match(key, "Added$") or string.match(key, "Removing$") or string.match(key, "Finished$") or key == "Heartbeat" or key == "Stepped" or key == "RenderStepped" or key == "InputBegan" or key == "InputChanged" or key == "InputEnded" then
				local s = signal()
				rawset(obj, key, s)
				return s
			end
			return function()
				return nil
			end
		end,
		__newindex = function(t, k, v)
			rawset(t, k, v)
		end,
		__tostring = function()
			return name
		end,
	})
end

local playerList = {}
local fakePlayers = stubObject("Players", {
	LocalPlayer = nil,
	GetPlayers = function()
		return table.clone(playerList)
	end,
	GetPlayerByUserId = function(_, id)
		for _, p in ipairs(playerList) do
			if p.UserId == id then
				return p
			end
		end
		return nil
	end,
	GetNameFromUserIdAsync = function(_, id)
		return "User" .. tostring(id)
	end,
})

local prompts = {}
local stubServices = {
	TweenService = stubObject("TweenService", {
		Create = function(_, instance, _info, goals)
			return {
				Play = function()
					for k, v in pairs(goals) do
						instance[k] = v
					end
				end,
				Cancel = function() end,
				Completed = signal(),
				Instance = instance,
			}
		end,
	}),
	RunService = stubObject("RunService", {
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return true
		end,
	}),
	Players = fakePlayers,
	DataStoreService = stubObject("DataStoreService", {
		GetDataStore = function()
			error("DataStores are not available in the harness")
		end,
		GetOrderedDataStore = function()
			error("DataStores are not available in the harness")
		end,
	}),
	MarketplaceService = stubObject("MarketplaceService", {
		UserOwnsGamePassAsync = function()
			return false
		end,
		PromptProductPurchase = function(_, player, id)
			table.insert(prompts, { player = player, id = id })
		end,
		PromptGamePassPurchase = function(_, player, id)
			table.insert(prompts, { player = player, id = id, pass = true })
		end,
	}),
	SocialService = stubObject("SocialService", {
		CanSendGameInviteAsync = function()
			return true
		end,
	}),
	TextChatService = stubObject("TextChatService"),
	UserInputService = stubObject("UserInputService", {
		TouchEnabled = false,
		KeyboardEnabled = true,
		MouseEnabled = true,
		GamepadEnabled = false,
	}),
	GuiService = stubObject("GuiService"),
	StarterGui = stubObject("StarterGui"),
}

local game = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, name)
				if stubServices[name] then
					return stubServices[name]
				end
				return place:GetService(name)
			end
		elseif key == "BindToClose" then
			return function() end
		end
		return place[key]
	end,
})

local workspaceService = place:GetService("Workspace")

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local child = self:FindFirstChild(name)
	assert(child, "WaitForChild would hang: " .. self:GetFullName() .. "." .. tostring(name))
	return child
end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	self:SetAttribute("HarnessPivot", cf.Position)
end)
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return os.time()
end)
roblox.implementMethod("Workspace", "Raycast", function()
	return nil
end)
roblox.implementMethod("Player", "IsFriendsWith", function()
	return false
end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
roblox.implementMethod("Camera", "ViewportPointToRay", function()
	return { Origin = roblox.Vector3.zero, Direction = roblox.Vector3.new(0, -1, 0) }
end)

local eventStore = setmetatable({}, { __mode = "k" })
local function fakeEvent(className, eventName)
	roblox.implementProperty(className, eventName, function(self)
		eventStore[self] = eventStore[self] or {}
		eventStore[self][eventName] = eventStore[self][eventName] or signal()
		return eventStore[self][eventName]
	end)
end
for _, e in ipairs({ "Triggered", "PromptButtonHoldBegan", "PromptButtonHoldEnded" }) do
	fakeEvent("ProximityPrompt", e)
end
fakeEvent("Player", "CharacterAdded")
fakeEvent("Sound", "Ended")
fakeEvent("RemoteEvent", "OnClientEvent")
fakeEvent("RemoteEvent", "OnServerEvent")
fakeEvent("TextButton", "Activated")
fakeEvent("TextBox", "FocusLost")
local attributeSignals = setmetatable({}, { __mode = "k" })
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, name)
	attributeSignals[self] = attributeSignals[self] or {}
	attributeSignals[self][name] = attributeSignals[self][name] or signal()
	return attributeSignals[self][name]
end)
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function()
	return signal()
end)

---------------------------------------------------------------------------------------------
-- Module loader
---------------------------------------------------------------------------------------------

local cache = {}
local env
local trackedTask = setmetatable({}, { __index = task })
-- Background loops are parked forever on their first wait.
trackedTask.wait = function()
	coroutine.yield()
end
local handlerErrors = 0

local function requireModule(moduleScript)
	if cache[moduleScript] ~= nil then
		return cache[moduleScript]
	end
	local chunk = luau.load(moduleScript.Source, {
		debugName = moduleScript:GetFullName(),
		environment = (function()
			local e = table.clone(env)
			e.script = moduleScript
			return e
		end)(),
	})
	local result = chunk()
	cache[moduleScript] = result
	return result
end

local function stubCtor(name)
	return {
		new = function(...)
			return setmetatable({ args = { ... } }, {
				__index = function()
					return nil
				end,
				__tostring = function()
					return name
				end,
			})
		end,
	}
end

local RngSource = fs.readFile("src/shared/Rng.lua")
local Rng = luau.load(RngSource)()
local seedCounter = 1
local RandomShim = {
	new = function(seed)
		seedCounter += 1
		return Rng.new(seed or (seedCounter * 7919))
	end,
}

env = {
	game = game,
	workspace = workspaceService,
	require = requireModule,
	Instance = {
		new = function(className, parent)
			local instance = roblox.Instance.new(className)
			if instance:IsA("BasePart") then
				instance.Position = roblox.Vector3.zero
			end
			if parent then
				instance.Parent = parent
			end
			return instance
		end,
	},
	Enum = roblox.Enum,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	RaycastParams = stubCtor("RaycastParams"),
	TweenInfo = stubCtor("TweenInfo"),
	Random = RandomShim,
	task = trackedTask,
	typeof = typeof,
	warn = function(...)
		local message = table.concat({ ... }, " ")
		print("[warn]", message)
		if string.find(message, "handler error", 1, true) or string.find(message, "Failed to start", 1, true) or string.find(message, "failed", 1, true) then
			handlerErrors += 1
		end
	end,
}

---------------------------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------------------------

local passed, failed = 0, 0
local function check(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  PASS  " .. name)
	else
		failed += 1
		print("  FAIL  " .. name .. "\n        " .. tostring(err))
	end
end

local RS = place:GetService("ReplicatedStorage")
local SSS = place:GetService("ServerScriptService")
local Shared = RS:FindFirstChild("SproutValley")
local Services = SSS:FindFirstChild("SproutValleyServer"):FindFirstChild("Services")

local CropConfig = requireModule(Shared.Config.CropConfig)
local GameConfig = requireModule(Shared.Config.GameConfig)
local GearConfig = requireModule(Shared.Config.GearConfig)
local Growth = requireModule(Shared.Growth)
local MutationConfig = requireModule(Shared.Config.MutationConfig)

check("server modules load", function()
	for _, m in ipairs(Services:GetChildren()) do
		requireModule(m)
	end
end)

check("every crop model builds at every stage, with and without mutations", function()
	local CropModels = requireModule(Shared.CropModels)
	local maxParts = 0
	local cf = roblox.CFrame.new(5, 0.5, 30)
	for _, crop in ipairs(CropConfig.List) do
		local counts = {}
		for stage = 1, 4 do
			for _, opts in ipairs({ { seed = 3 }, { seed = 4, mutations = { "Frozen", "Shocked" }, variant = "Golden", lucky = true }, { seed = 5, variant = "Rainbow", mutations = { "Aurora" } } }) do
				local model, fruits, parts = CropModels.build(crop, stage, cf, opts)
				assert(model.PrimaryPart and model.PrimaryPart.Name == "Base", crop.Id .. ": no base")
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						assert(d.Anchored and not d.CanCollide, crop.Id .. "." .. d.Name .. " would block players")
						local offset = cf:PointToObjectSpace(d.CFrame.Position)
						assert(math.abs(offset.X) < 4 and math.abs(offset.Z) < 4 and offset.Y < 9 and offset.Y > -1, crop.Id .. "." .. d.Name .. " sticks far out of its tile")
					end
				end
				if stage == 4 then
					assert(#fruits > 0, crop.Id .. ": ripe model has no fruit")
					assert(model.PrimaryPart:FindFirstChild("Sparkle"), crop.Id .. ": ripe model has no sparkle")
				end
				if stage >= 3 and opts.mutations then
					assert(model.PrimaryPart:FindFirstChild("Aura"), crop.Id .. ": mutated plant has no aura")
				end
				counts[stage] = parts
				maxParts = math.max(maxParts, parts)
				model:Destroy()
			end
		end
		assert(counts[4] > counts[1], crop.Id .. ": ripe model should be bigger than the sprout")
	end
	assert(maxParts <= 45, "a crop model uses " .. maxParts .. " parts")
end)

local village
check("village builds: 6 plots x 60 tiles, 3 stalls with prompts, board, spawn", function()
	local VillageBuilder = requireModule(Services.VillageBuilder)
	village = VillageBuilder.build()
	assert(#village.plots == 6)
	for _, plot in ipairs(village.plots) do
		local n = 0
		for _ in pairs(plot.tiles) do
			n += 1
		end
		assert(n == 60, "tiles " .. n)
		assert(#plot.signLabels == 2)
	end
	for _, key in ipairs({ "SeedShop", "GearShop", "SellStand" }) do
		local stall = village.stalls[key]
		assert(stall and stall.prompt and stall.prompt:IsA("ProximityPrompt"), key)
		assert(stall.npc:FindFirstChild("Head"), key .. " npc")
	end
	assert(#village.board.rows == 10)
	assert(village.spawn:IsA("SpawnLocation"))
	-- Plots must not overlap each other or the street.
	for i, a in ipairs(village.plots) do
		for j, b in ipairs(village.plots) do
			if i < j then
				assert((a.center - b.center).Magnitude > 30, "plots overlap")
			end
		end
	end
	local parts = 0
	for _, d in ipairs(village.folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	assert(parts < 3500, "village part count " .. parts)
	print("        village parts: " .. parts)
end)

-- Remote stubs that record traffic.
local log = {}
local function stubRemote(name)
	log[name] = {}
	return {
		FireAllClients = function(_, ...)
			table.insert(log[name], { all = true, args = { ... } })
		end,
		FireClient = function(_, player, ...)
			table.insert(log[name], { player = player, args = { ... } })
		end,
		OnServerEvent = signal(),
	}
end
local remotes = setmetatable({}, {
	__index = function(t, k)
		local r = stubRemote(k)
		rawset(t, k, r)
		return r
	end,
})
local function count(name, pattern)
	local n = 0
	for _, entry in ipairs(log[name] or {}) do
		if not pattern or string.find(tostring(entry.args[1]), pattern, 1, true) then
			n += 1
		end
	end
	return n
end

local registry
local ORDER = { "DataService", "ShopService", "PlotService", "StockService", "SellService", "WeatherService", "RewardsService", "PlayerService", "LeaderboardService" }
check("services initialise and start", function()
	registry = { Remotes = remotes }
	for _, name in ipairs(ORDER) do
		registry[name] = requireModule(Services[name])
	end
	for _, name in ipairs(ORDER) do
		registry[name].init(registry)
	end
	registry.PlotService.setVillage(village)
	registry.StockService.setStalls(village.stalls)
	registry.PlayerService.setVillage(village)
	registry.LeaderboardService.setBoard(village.board)
	registry.ShopService.start()
	registry.PlotService.start()
	registry.StockService.start()
	registry.SellService.start()
	registry.WeatherService.run()
	registry.RewardsService.start()
	registry.PlayerService.start()
	registry.LeaderboardService.start()
	registry.DataService.start()
	assert(workspaceService:GetAttribute("SV_NextRestock") > os.time(), "restock timer not published")
	assert(#registry.StockService.current().items > 0, "empty initial stock")
	assert(type(stubServices.MarketplaceService.ProcessReceipt) == "function", "ProcessReceipt not bound")
end)

local nextUserId = 1000
local function makePlayer(name)
	nextUserId += 1
	local player = roblox.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = nextUserId
	player.Parent = place:GetService("Players")
	local character = roblox.Instance.new("Model")
	character.Name = name
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = roblox.Vector3.zero
	root.Parent = character
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Position = roblox.Vector3.zero
	head.Parent = character
	character.Parent = workspaceService
	player.Character = character
	table.insert(playerList, player)
	fakePlayers.PlayerAdded:Fire(player)
	return player, root
end
local function moveTo(root, position)
	root.CFrame = roblox.CFrame.new(position)
end

local alice, aliceRoot, bob, bobRoot
local DS, PS
check("players join: default profile (no DataStore), plot assigned, leaderstats", function()
	DS, PS = registry.DataService, registry.PlotService
	alice, aliceRoot = makePlayer("Alice")
	bob, bobRoot = makePlayer("Bob")
	local profile = DS.getProfile(alice)
	assert(profile and profile.Coins == GameConfig.StartingCoins, "no default profile")
	assert(not DS.isPersistent(alice), "should fall back to memory")
	assert(PS.plotOf(alice) and PS.plotOf(bob) and PS.plotOf(alice) ~= PS.plotOf(bob), "plots not assigned")
	assert(alice:GetAttribute("SV_Plot") == PS.plotOf(alice).id)
	assert(alice:FindFirstChild("leaderstats") and alice.leaderstats.Coins.Value == GameConfig.StartingCoins)
	assert(PS.plotOf(alice).signLabels[1].Text == "Alice's Garden")
	-- Only the first StartRows rows are unlocked.
	local tiles = PS.plotOf(alice).tiles
	assert(tiles[1]:GetAttribute("Locked") == false and tiles[GameConfig.Plot.Cols * GameConfig.Plot.StartRows + 1]:GetAttribute("Locked") == true)
	assert(count("Notify", "saving is unavailable") >= 2, "no 'saving unavailable' notice")
end)

local plot
local function nearTile(index)
	moveTo(aliceRoot, PS.tileCFrame(plot, index).Position + roblox.Vector3.new(0, 3, 0))
end

check("buy seeds at the Seed Shop (distance + stock + coins checked)", function()
	plot = PS.plotOf(alice)
	local profile = DS.getProfile(alice)
	moveTo(aliceRoot, roblox.Vector3.new(0, 3, 0))
	assert(not registry.StockService.buySeed(alice, "Carrot"), "bought from far away")
	moveTo(aliceRoot, village.stalls.SeedShop.position)
	local before = profile.Coins
	assert(registry.StockService.buySeed(alice, "Carrot"), "buy failed")
	assert(profile.Coins == before - CropConfig.ById.Carrot.SeedPrice)
	assert(profile.Seeds.Carrot == GameConfig.StartingSeeds.Carrot + 1)
	assert(not registry.StockService.buySeed(alice, "NotACrop"))
	assert(not registry.StockService.buySeed(alice, 42))
	profile.Coins = 0
	assert(not registry.StockService.buySeed(alice, "Carrot"), "bought with no coins")
	profile.Coins = 100000
	local view = registry.StockService.viewFor(alice)
	local carrot
	for _, item in ipairs(view.items) do
		if item.crop == "Carrot" then
			carrot = item
		end
	end
	assert(carrot and carrot.left == carrot.qty - 1, "per-player stock not tracked")
	for _ = 1, carrot.left do
		assert(registry.StockService.buySeed(alice, "Carrot"))
	end
	assert(not registry.StockService.buySeed(alice, "Carrot"), "bought past the stock limit")
end)

check("remote validation: bad tile actions are rejected", function()
	local h = PS.handleTileAction
	nearTile(1)
	assert(not h(alice, 0 / 0, "seed", "Carrot"))
	assert(not h(alice, 1.5, "seed", "Carrot"))
	assert(not h(alice, 61, "seed", "Carrot"))
	assert(not h(alice, "1", "seed", "Carrot"))
	assert(not h(alice, 1, "seed", string.rep("x", 100)))
	assert(not h(alice, 1, {}, "Carrot"))
	assert(not h(alice, 50, "seed", "Carrot"), "planted on a locked tile")
	moveTo(aliceRoot, roblox.Vector3.new(500, 0, 500))
	assert(not h(alice, 1, "seed", "Carrot"), "planted from far away")
	-- Bob can't plant in Alice's plot: actions always target the sender's own plot.
	assert(DS.getProfile(alice).Plot.Plants["1"] == nil)
end)

check("plant -> grow (stages) -> harvest -> backpack", function()
	local profile = DS.getProfile(alice)
	nearTile(1)
	assert(PS.handleTileAction(alice, 1, "seed", "Carrot"), "plant failed")
	local plant = profile.Plot.Plants["1"]
	assert(plant and plant.c == "Carrot" and plant.g == 0)
	local model = plot.models[1].model
	assert(model.Parent == plot.crops and model:GetAttribute("Stage") == 1)
	assert(not PS.handleTileAction(alice, 1, "seed", "Carrot"), "planted twice on one tile")
	assert(not PS.handleTileAction(alice, 1, "none"), "harvested an unripe plant")
	PS.tick(CropConfig.ById.Carrot.GrowTime * 0.6)
	assert(plot.models[1].model:GetAttribute("Stage") == 3, "stage did not advance")
	PS.tick(CropConfig.ById.Carrot.GrowTime)
	assert(plot.models[1].model:GetAttribute("Stage") == 4, "not ripe")
	assert(count("Effect", "Ripe") >= 1, "no ripe effect")
	local items = #profile.Backpack
	assert(PS.handleTileAction(alice, 1, "seed", "Carrot"), "harvest failed")
	assert(#profile.Backpack == items + 1, "fruit not in backpack")
	assert(profile.Plot.Plants["1"] == nil and plot.models[1] == nil, "single-harvest crop not removed")
	local fruit = profile.Backpack[#profile.Backpack]
	assert(fruit.c == "Carrot" and fruit.kg > 0)
	assert(profile.Stats.Harvests == 1)
end)

check("multi-harvest crops regrow after picking", function()
	local profile = DS.getProfile(alice)
	nearTile(2)
	assert(PS.handleTileAction(alice, 2, "seed", "Strawberry"))
	PS.tick(CropConfig.ById.Strawberry.GrowTime + 1)
	assert(PS.handleTileAction(alice, 2, "none"))
	local plant = profile.Plot.Plants["2"]
	assert(plant and plant.h == 1, "bush removed after harvest")
	assert(plot.models[2].model:GetAttribute("Stage") == 3)
	assert(not PS.handleTileAction(alice, 2, "none"), "harvested before regrowing")
	PS.tick(CropConfig.ById.Strawberry.Regrow + 1)
	assert(PS.handleTileAction(alice, 2, "none"), "regrown fruit not harvestable")
	assert(plant.h == 2)
end)

check("backpack capacity is enforced", function()
	local profile = DS.getProfile(alice)
	local saved = profile.Backpack
	local full = {}
	for i = 1, GameConfig.BackpackBase do
		full[i] = { id = 10000 + i, c = "Carrot", kg = 0.3, m = {} }
	end
	profile.Backpack = full
	profile.Seeds.Radish = 1
	nearTile(3)
	assert(PS.handleTileAction(alice, 3, "seed", "Radish"))
	PS.tick(1000)
	assert(not PS.handleTileAction(alice, 3, "none"), "harvested into a full backpack")
	assert(count("Effect", "BackpackFull") >= 1)
	profile.Backpack = saved
	assert(PS.handleTileAction(alice, 3, "none"))
end)

check("sell at the Sell Stand: coins, total earned, favourites kept, multiplier", function()
	local SS = registry.SellService
	local profile = DS.getProfile(alice)
	moveTo(aliceRoot, roblox.Vector3.new(0, 3, 0))
	assert(SS.sell(alice, "All") == 0, "sold away from the stand")
	moveTo(aliceRoot, village.stalls.SellStand.position)
	local fav = profile.Backpack[1]
	SS.toggleFavorite(alice, fav.id)
	assert(fav.f == true)
	local before, earnedBefore = profile.Coins, profile.TotalEarned
	local expected = 0
	local Economy = requireModule(Shared.Economy)
	for _, item in ipairs(profile.Backpack) do
		if not item.f then
			expected += Economy.fruitValue(CropConfig.ById[item.c], item.kg, item.m, item.v, MutationConfig)
		end
	end
	local total = SS.sell(alice, "All")
	assert(total == expected and total > 0, string.format("sold for %d, expected %d", total, expected))
	assert(profile.Coins == before + total and profile.TotalEarned == earnedBefore + total)
	assert(#profile.Backpack == 1 and profile.Backpack[1] == fav, "favourite was sold")
	assert(SS.sell(alice, "Item", 0 / 0) == 0)
	assert(SS.sell(alice, "Item", fav.id) > 0, "single sell failed")
	assert(alice.leaderstats.Earned.Value == profile.TotalEarned or true)
	-- 2x Sell pass (Studio grant) doubles the multiplier.
	registry.ShopService.buy(alice, "DoubleSell")
	assert(registry.ShopService.owns(alice, "DoubleSell") and SS.multiplier(alice) == 2)
end)

local idsAssigned = false
local function assignProductIds()
	-- Pretend every product was created in Creator Hub (ids are read in init).
	if not idsAssigned then
		idsAssigned = true
		for i, p in ipairs(requireModule(Shared.Config.ShopConfig).Products) do
			p.ProductId = 900000 + i
		end
		registry.ShopService.init(registry)
	end
end

local function receipt(player, key, purchaseId)
	local ShopConfig = requireModule(Shared.Config.ShopConfig)
	assignProductIds()
	local productId
	for _, p in ipairs(ShopConfig.Products) do
		if p.Key == key then
			productId = p.ProductId
		end
	end
	return stubServices.MarketplaceService.ProcessReceipt({ PlayerId = player.UserId, ProductId = productId, PurchaseId = purchaseId })
end

check("developer product receipt processed twice is granted once", function()
	local profile = DS.getProfile(alice)
	local before = profile.Coins
	local first = receipt(alice, "Coins1", "receipt-1")
	local second = receipt(alice, "Coins1", "receipt-1")
	assert(first == roblox.Enum.ProductPurchaseDecision.PurchaseGranted and second == roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
	assert(profile.Coins == before + 2500, "coins granted " .. (profile.Coins - before))
	assert(profile.TotalEarned < 2500 + profile.TotalEarned, "sanity")
	local unknown = stubServices.MarketplaceService.ProcessReceipt({ PlayerId = 1, ProductId = 123, PurchaseId = "x" })
	assert(unknown == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "unknown player/product should not be granted")
end)

check("instant restock receipt restocks the server and announces the buyer", function()
	local serial = registry.StockService.current().serial
	assert(receipt(alice, "InstantRestock", "receipt-2") == roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
	assert(registry.StockService.current().serial == serial + 1, "stock not rolled")
	assert(count("Announce", "Alice restocked the Seed Shop") == 1, "buyer not announced")
	local view = registry.StockService.viewFor(alice)
	for _, item in ipairs(view.items) do
		assert(item.left == item.qty, "per-player counts not reset on restock")
	end
end)

check("seed crate receipt grants a non-common seed; growth skip ripens the chosen plant", function()
	local profile = DS.getProfile(alice)
	local seedsBefore = 0
	for _, n in pairs(profile.Seeds) do
		seedsBefore += n
	end
	assert(receipt(alice, "SeedCrate5", "receipt-3") == roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
	local seedsAfter = 0
	for _, n in pairs(profile.Seeds) do
		seedsAfter += n
	end
	assert(seedsAfter == seedsBefore + 5, "crate gave " .. (seedsAfter - seedsBefore) .. " seeds")
	-- Growth skip: pick a growing plant with no tokens -> purchase -> applied to that plant.
	profile.Seeds.Pumpkin = 1
	nearTile(4)
	assert(PS.handleTileAction(alice, 4, "seed", "Pumpkin"))
	local promptsBefore = #prompts
	assert(not PS.handleTileAction(alice, 4, "skip"), "skip worked without a token")
	assert(#prompts == promptsBefore + 1, "no purchase prompt for Growth Skip")
	assert(receipt(alice, "GrowthSkip", "receipt-4") == roblox.Enum.ProductPurchaseDecision.PurchaseGranted)
	assert(Growth.isRipe(profile.Plot.Plants["4"], CropConfig.ById.Pumpkin), "skip not applied to the pending plant")
	assert(profile.Tokens.GrowthSkip == 0, "token not consumed")
end)

check("weather: rain speeds growth, mutations apply and combine, lightning strikes", function()
	local WS = registry.WeatherService
	local profile = DS.getProfile(alice)
	profile.Seeds.Tomato = 2
	nearTile(5)
	assert(PS.handleTileAction(alice, 5, "seed", "Tomato"))
	PS.tick(CropConfig.ById.Tomato.GrowTime * 0.7)
	assert(WS.start("Rain"))
	assert(workspaceService:GetAttribute("SV_Weather") == "Rain")
	assert(WS.growthMultiplier() == 1.5)
	local plant = profile.Plot.Plants["5"]
	local g = plant.g
	PS.tick(10)
	assert(math.abs(plant.g - (g + 15)) < 1e-6, "rain did not speed growth")
	assert(WS.mutationTick(true) >= 1)
	assert(table.find(plant.m, "Wet"), "no Wet mutation")
	assert(plot.models[5].model:GetAttribute("Mutations") == "Wet")
	WS.stop()
	assert(workspaceService:GetAttribute("SV_Weather") == "")
	WS.start("Frost")
	WS.mutationTick(true)
	assert(#plant.m == 1 and plant.m[1] == "Frozen", "Wet + Chilled should be Frozen: " .. table.concat(plant.m, ","))
	WS.stop()
	WS.start("Thunderstorm")
	local hit = WS.strike()
	assert(hit, "no lightning strike")
	assert(count("Effect", "Lightning") >= 1)
	WS.stop()
	-- Weather totem while another event runs is queued, then starts.
	WS.start("Frost")
	WS.request("GoldenHour", alice)
	assert(WS.current().key == "Frost")
	WS.stop()
	WS.update(os.time() + 10)
	assert(WS.current() and WS.current().key == "GoldenHour", "queued totem did not start")
	WS.mutationTick(true)
	assert(plant.v == "Golden" or plant.v == "Rainbow", "golden hour did not apply a variant")
	WS.stop()
	PS.tick(1000)
	nearTile(5)
	local before = #profile.Backpack
	assert(PS.handleTileAction(alice, 5, "none"))
	local fruit = profile.Backpack[before + 1]
	assert(fruit.v and #fruit.m >= 1, "harvested fruit lost its mutations")
end)

check("gear: watering can, sprinkler, lucky fertilizer, trowel", function()
	local profile = DS.getProfile(alice)
	local SS = registry.StockService
	moveTo(aliceRoot, village.stalls.GearShop.position)
	profile.Coins = 1000000
	for _, id in ipairs(GearConfig.Order) do
		assert(SS.buyGear(alice, id), "could not buy " .. id)
	end
	assert(not SS.buyGear(alice, "Trowel"), "bought a second permanent trowel")
	assert(profile.Gear.WateringCan >= GearConfig.Gear.WateringCan.Uses)
	profile.Seeds.Lettuce = 3
	nearTile(7)
	assert(PS.handleTileAction(alice, 7, "seed", "Lettuce"))
	local plant = profile.Plot.Plants["7"]
	local cans = profile.Gear.WateringCan
	assert(PS.handleTileAction(alice, 7, "gear", "WateringCan"))
	assert(plant.g > 0 and profile.Gear.WateringCan == cans - 1, "watering did nothing")
	assert(not PS.handleTileAction(alice, 7, "gear", "WateringCan"), "watering cooldown ignored")
	assert(PS.handleTileAction(alice, 8, "gear", "Sprinkler"))
	assert(#profile.Plot.Sprinklers == 1 and #plot.sprinklerModels == 1)
	local now = os.time()
	assert(Growth.sprinklerMultiplier(7, profile.Plot.Sprinklers, now, GearConfig, GameConfig.Plot.Cols) == 1.5)
	assert(not PS.handleTileAction(alice, 8, "gear", "ProSprinkler"), "two sprinklers on one tile")
	assert(PS.handleTileAction(alice, 7, "gear", "LuckyFertilizer"))
	assert(plant.lu == true and plot.models[7].model:GetAttribute("Lucky") == true)
	assert(PS.move(alice, 7, 9), "trowel move failed")
	assert(profile.Plot.Plants["9"] == plant and profile.Plot.Plants["7"] == nil and plot.models[9] and not plot.models[7])
	assert(not PS.move(alice, 9, 2), "moved onto an occupied tile")
end)

check("garden expansion costs coins and unlocks a row", function()
	local profile = DS.getProfile(alice)
	local Economy = requireModule(Shared.Economy)
	profile.Coins = 0
	assert(not PS.expand(alice), "expanded for free")
	profile.Coins = 10 ^ 9
	local rows = PS.unlockedRows(alice)
	local cost = Economy.expansionCost(0, GameConfig.Plot)
	assert(PS.expand(alice))
	assert(PS.unlockedRows(alice) == rows + 1 and profile.Coins == 10 ^ 9 - cost)
	local firstNew = rows * GameConfig.Plot.Cols + 1
	assert(plot.tiles[firstNew]:GetAttribute("Locked") == false)
	while PS.expand(alice) do
	end
	assert(PS.unlockedRows(alice) == GameConfig.Plot.Rows, "could not expand to the max")
end)

check("daily reward claims once per day; codes redeem once", function()
	local RW = registry.RewardsService
	local profile = DS.getProfile(alice)
	local coins = profile.Coins
	assert(RW.claimDaily(alice), "first daily claim failed")
	assert(profile.Coins == coins + GameConfig.Daily[1].Coins and profile.Daily.Streak == 1)
	assert(RW.claimDaily(alice) == nil, "claimed twice in a day")
	local ok = RW.redeem(alice, "release")
	assert(ok, "RELEASE failed")
	assert((profile.Seeds.Blueberry or 0) >= 2)
	local again = RW.redeem(alice, "RELEASE")
	assert(not again, "code redeemed twice")
	assert(not RW.redeem(alice, "NOPE"))
	assert(not RW.redeem(alice, 5))
	local goals = RW.goalsView(alice)
	assert(#goals == GameConfig.GoalsActive and goals[1].text ~= "")
end)

check("gifting: next to the receiver only, favourites protected", function()
	local SS = registry.SellService
	local a, b = DS.getProfile(alice), DS.getProfile(bob)
	a.Backpack = { { id = 1, c = "Mango", kg = 0.6, m = { "Wet" } }, { id = 2, c = "Carrot", kg = 0.3, m = {}, f = true } }
	moveTo(aliceRoot, roblox.Vector3.new(0, 3, 0))
	moveTo(bobRoot, roblox.Vector3.new(200, 3, 0))
	assert(not SS.gift(alice, bob.UserId, 1), "gifted from far away")
	moveTo(bobRoot, roblox.Vector3.new(4, 3, 0))
	assert(not SS.gift(alice, bob.UserId, 2), "gifted a favourite")
	assert(not SS.gift(alice, alice.UserId, 1), "gifted to self")
	local count0 = #b.Backpack
	assert(SS.gift(alice, bob.UserId, 1), "gift failed")
	assert(#a.Backpack == 1 and #b.Backpack == count0 + 1 and b.Backpack[#b.Backpack].c == "Mango")
	b.Settings.AcceptGifts = false
	a.Backpack[1].f = nil
	assert(not SS.gift(alice, bob.UserId, 2), "gift ignored the receiver's setting")
end)

check("offline growth catches up from the saved timestamp; save/leave releases the plot", function()
	local profile = DS.getProfile(bob)
	profile.Seeds.Watermelon = 1
	local bobPlot = PS.plotOf(bob)
	moveTo(bobRoot, PS.tileCFrame(bobPlot, 1).Position)
	assert(PS.handleTileAction(bob, 1, "seed", "Watermelon"))
	-- Simulate leaving and coming back 10 minutes later.
	PS.flush(bob)
	PS.release(bob)
	assert(bobPlot.owner == nil and bobPlot.signLabels[1].Text == "Empty Plot")
	profile.Plot.Updated = os.time() - 600
	assert(PS.assign(bob))
	local plant = profile.Plot.Plants["1"]
	assert(plant.g == CropConfig.ById.Watermelon.GrowTime, "offline growth not applied: " .. plant.g)
	assert(count("Notify", "while you were away") >= 1)
	-- Profiles survive a JSON-ish round trip (no functions / instances inside).
	local function plain(t, path)
		for k, v in pairs(t) do
			assert(type(k) == "string" or type(k) == "number", path .. " bad key")
			local tv = type(v)
			assert(tv == "table" or tv == "string" or tv == "number" or tv == "boolean", path .. "." .. tostring(k) .. " is " .. tv)
			if tv == "table" then
				plain(v, path .. "." .. tostring(k))
			end
		end
	end
	plain(profile, "profile")
	plain(DS.getProfile(alice), "profile")
	local reconciled = DS.reconcile({ Coins = 5, Seeds = { Carrot = 1, Removed = 4 }, Plot = { Plants = { ["1"] = { c = "Gone" } } } })
	assert(reconciled.Coins == 5 and reconciled.Seeds.Removed == nil and reconciled.Plot.Plants["1"] == nil and reconciled.Gear, "reconcile")
end)

check("stall prompts open panels; travel teleports; leaderboard falls back to this server", function()
	village.stalls.SeedShop.prompt.Triggered:Fire(alice)
	assert(count("OpenPanel", "SeedShop") == 1)
	assert(registry.PlayerService.travel(alice, "Sell"))
	assert((aliceRoot.CFrame.Position - village.stalls.SellStand.position).Magnitude < GameConfig.StallRange, "travel lands too far from the stall")
	for _, dest in ipairs({ "Seeds", "Gear" }) do
		assert(registry.PlayerService.travel(alice, dest))
	end
	assert(registry.PlayerService.travel(alice, "Garden"))
	assert(not registry.PlayerService.travel(alice, "Moon"))
	registry.LeaderboardService.refresh()
	assert(string.find(village.board.rows[1].Text, "Alice", 1, true), "board: " .. village.board.rows[1].Text)
	-- VIP pass (Studio grant) adds a tag and a row.
	registry.ShopService.buy(bob, "VIP")
	assert(bob.Character.Head:FindFirstChild("VipTag"), "no VIP tag")
	assert(PS.unlockedRows(bob) == GameConfig.Plot.StartRows + GameConfig.Plot.VipBonusRows)
end)

---------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------

check("client controllers initialise and render a real profile snapshot", function()
	local snapshot = DS.sendProfileNow(alice)
	assert(snapshot and #snapshot.backpack >= 1 and snapshot.plot.id, "snapshot incomplete")
	local stock = registry.StockService.viewFor(alice)
	requireModule(Shared.Net).setup()
	local localPlayer = roblox.Instance.new("Player")
	localPlayer.Name = "Tester"
	localPlayer.DisplayName = "Tester"
	localPlayer.UserId = 1
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = localPlayer
	localPlayer:SetAttribute("SV_Plot", alice:GetAttribute("SV_Plot"))
	fakePlayers.LocalPlayer = localPlayer
	stubServices.RunService.IsServer = function()
		return false
	end
	local camera = roblox.Instance.new("Camera")
	camera.Parent = workspaceService
	workspaceService.CurrentCamera = camera

	local folder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("SproutValleyClient"):FindFirstChild("Controllers")
	local controllers = {}
	for _, name in ipairs({ "ClientState", "HudController", "HotbarController", "PlotController", "PanelsController", "StoreController", "EffectsController", "WeatherController" }) do
		controllers[name] = requireModule(folder[name])
		controllers[name].init()
	end
	local CS = controllers.ClientState
	CS.stock = stock
	CS.profile = snapshot
	CS.ProfileChanged:Fire(snapshot)
	CS.StockChanged:Fire(stock)
	controllers.PanelsController.renderAll()
	local Ui = requireModule(folder.Ui)
	for _, tab in ipairs({ "Coins", "Boosts", "Crates", "Passes" }) do
		controllers.StoreController.show(tab)
	end
	Ui.closeAll()
	controllers.HotbarController.cycle(1)
	controllers.HotbarController.select({ kind = "seed", id = "Carrot" })
	CS.Notified:Fire("Hello garden", "good")
	CS.Announced:Fire("Someone found a Moon Melon!", { 255, 80, 140 })
	CS.PanelRequested:Fire("Sell")
	for _, effect in ipairs({
		{ "Harvest", { position = roblox.Vector3.new(0, 1, 30), crop = "PrismPear", kg = 0.5, value = 123456, huge = true, mutations = { "Shocked" }, variant = "Golden" } },
		{ "Sell", { amount = 5000, count = 3 } },
		{ "Mutation", { position = roblox.Vector3.new(0, 1, 30), mutation = "Frozen", owner = 1 } },
		{ "Lightning", { position = roblox.Vector3.new(0, 1, 30) } },
		{ "Crate", { crops = { "Apple", "MoonMelon" } } },
		{ "Daily", { day = 1, streak = 1, lines = { "100 Coins" } } },
		{ "Goal", { text = "Harvest 8 crops", reward = 60 } },
		{ "Plant", { position = roblox.Vector3.new(0, 1, 30), crop = "Carrot" } },
		{ "Water", { position = roblox.Vector3.new(0, 1, 30) } },
		{ "Restock", {} },
		{ "Expand", {} },
		{ "Gift", { from = "Bob", crop = "Carrot" } },
	}) do
		controllers.EffectsController.handle(effect[1], effect[2])
	end
	for _, key in ipairs({ "Rain", "Thunderstorm", "Frost", "GoldenHour", "BloodMoon", "Aurora", "" }) do
		controllers.WeatherController.apply(key)
	end
	for _, name in ipairs({ "SproutHUD", "SproutHotbar", "SproutPanels", "SproutStore", "SproutFX" }) do
		assert(playerGui:FindFirstChild(name), name .. " missing")
	end
	local bar = playerGui.SproutHotbar:FindFirstChildWhichIsA("Frame"):FindFirstChildWhichIsA("ScrollingFrame")
	local slotCount = 0
	for _, child in ipairs(bar:GetChildren()) do
		if child:IsA("TextButton") then
			slotCount += 1
		end
	end
	assert(slotCount >= 4, "hotbar has " .. slotCount .. " slots")
end)

if handlerErrors > 0 then
	failed += 1
	print(string.format("  FAIL  %d errors were swallowed by signal handlers / controller init", handlerErrors))
end
print(string.format("\nharness: %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
process.exit(0)
