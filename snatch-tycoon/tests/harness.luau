--[[
	Headless smoke harness for Snatch a Blobby.

	Loads the Rojo-built place file in Lune and executes the REAL game modules against
	Lune's Roblox instance implementation (class and property names are checked against
	the Roblox reflection database). Engine services Lune does not simulate (players,
	physics, tweens, data stores, marketplace) are stubbed; the data stores are in-memory
	fakes so the save / receipt paths really run.

	It builds the world, builds every Blobby species with every mutation, initialises and
	starts every service, then simulates server flows with two/three fake players:
	join -> buy from the carpet -> walk home -> earn -> collect -> steal -> slap -> return ->
	steal + deliver -> lock / eject -> receipts (twice, failed save rollback, crate, lock
	token, server luck) -> passes -> rebirth -> daily -> codes -> events / cash rain ->
	leaderboard -> offline earnings -> leaving -> bad remote arguments.
	Finally it initialises every client controller and feeds it real server snapshots.

	It does NOT simulate physics, real networking or rendering (no Studio playtest).

	Usage (from snatch-tycoon/):
	  rojo build -o build/SnatchTycoon.rbxlx && lune run tests/harness build/SnatchTycoon.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/SnatchTycoon.rbxlx"
local place = roblox.deserializePlace(fs.readFile(placePath))
local V3, CF = roblox.Vector3, roblox.CFrame

---------------------------------------------------------------------------------------------
-- Stubs
---------------------------------------------------------------------------------------------

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		local handlers = self.handlers
		return {
			Disconnect = function()
				local i = table.find(handlers, fn)
				if i then
					table.remove(handlers, i)
				end
			end,
		}
	end
	function s:Fire(...)
		for _, fn in ipairs(table.clone(self.handlers)) do
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
			if string.match(key, "^%u%w*Added$") or string.match(key, "^%u%w*Removing$") or string.match(key, "Finished$") or key == "Heartbeat" or key == "Stepped" or key == "RenderStepped" then
				local s = signal()
				rawset(obj, key, s)
				return s
			end
			return function()
				return nil
			end
		end,
		__tostring = function()
			return name
		end,
	})
end

local playerList = {}
local characterOwner = {}
local playersService = place:GetService("Players")
local fakePlayers = stubObject("Players", {
	LocalPlayer = nil,
	GetPlayers = function()
		local out = {}
		for _, p in ipairs(playerList) do
			if p.Parent then
				table.insert(out, p)
			end
		end
		return out
	end,
	GetPlayerByUserId = function(_, id)
		for _, p in ipairs(playerList) do
			if p.UserId == id and p.Parent then
				return p
			end
		end
		return nil
	end,
	GetPlayerFromCharacter = function(_, character)
		return characterOwner[character]
	end,
	GetNameFromUserIdAsync = function(_, id)
		return "User" .. tostring(id)
	end,
})

-- In-memory DataStores.
local storeData = {}
local storeFailSaves = false
local function fakeStore()
	return {
		GetAsync = function(_, key)
			return storeData[key]
		end,
		UpdateAsync = function(_, key, fn)
			if storeFailSaves then
				error("simulated DataStore outage")
			end
			storeData[key] = fn(storeData[key])
		end,
	}
end
local ordered = {}
local fakeOrdered = {
	SetAsync = function(_, key, value)
		ordered[key] = value
	end,
	GetSortedAsync = function(_, ascending, size)
		local items = {}
		for k, v in pairs(ordered) do
			table.insert(items, { key = k, value = v })
		end
		table.sort(items, function(a, b)
			return if ascending then a.value < b.value else a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(size, #items) do
			page[i] = items[i]
		end
		return {
			GetCurrentPage = function()
				return page
			end,
		}
	end,
}

local prompted = {}
local fakeMarket = stubObject("MarketplaceService", {
	PromptProductPurchase = function(_, player, id)
		table.insert(prompted, { player = player, id = id, kind = "product" })
	end,
	PromptGamePassPurchase = function(_, player, id)
		table.insert(prompted, { player = player, id = id, kind = "pass" })
	end,
	UserOwnsGamePassAsync = function()
		return false
	end,
	PromptGamePassPurchaseFinished = signal(),
})

local tagged = {}
local fakeRun = stubObject("RunService", {
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
	IsStudio = function()
		return true
	end,
	Heartbeat = signal(),
	RenderStepped = signal(),
})

local stubServices = {
	CollectionService = stubObject("CollectionService", {
		AddTag = function(_, inst, tag)
			inst:AddTag(tag)
			tagged[tag] = tagged[tag] or {}
			table.insert(tagged[tag], inst)
		end,
		GetTagged = function(_, tag)
			local out = {}
			for _, inst in ipairs(place:GetService("Workspace"):GetDescendants()) do
				if inst:HasTag(tag) then
					table.insert(out, inst)
				end
			end
			return out
		end,
		GetInstanceAddedSignal = function()
			return signal()
		end,
		GetInstanceRemovedSignal = function()
			return signal()
		end,
	}),
	TweenService = stubObject("TweenService", {
		Create = function(_, instance, _info, goals)
			local completed = signal()
			return {
				Play = function()
					for k, v in pairs(goals) do
						instance[k] = v
					end
					completed:Fire()
				end,
				Cancel = function() end,
				Completed = completed,
				Instance = instance,
			}
		end,
	}),
	RunService = fakeRun,
	Players = fakePlayers,
	DataStoreService = stubObject("DataStoreService", {
		GetDataStore = function()
			return fakeStore()
		end,
		GetOrderedDataStore = function()
			return fakeOrdered
		end,
	}),
	MarketplaceService = fakeMarket,
	Debris = stubObject("Debris"),
	UserInputService = stubObject("UserInputService", { TouchEnabled = false, KeyboardEnabled = true, GamepadEnabled = false }),
	ContextActionService = stubObject("ContextActionService"),
	GuiService = stubObject("GuiService"),
	StarterGui = stubObject("StarterGui"),
	SocialService = stubObject("SocialService"),
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

-- Engine methods / events Lune's instance implementation does not provide.
roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local child = self:FindFirstChild(name)
	assert(child, "WaitForChild would hang: " .. self:GetFullName() .. "." .. tostring(name))
	return child
end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	if self.PrimaryPart then
		self.PrimaryPart.CFrame = cf
	end
	self:SetAttribute("HarnessPivot", cf.Position)
end)
roblox.implementMethod("BasePart", "SetNetworkOwner", function() end)
roblox.implementMethod("Humanoid", "ChangeState", function() end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("Player", "IsFriendsWith", function(self, otherId)
	-- Players 1 and 2 are friends in the harness.
	return (self.UserId == 1 and otherId == 2) or (self.UserId == 2 and otherId == 1)
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
fakeEvent("Humanoid", "Died")
fakeEvent("BasePart", "Touched")
fakeEvent("Player", "CharacterAdded")
fakeEvent("RemoteEvent", "OnClientEvent")
fakeEvent("RemoteEvent", "OnServerEvent")
for _, e in ipairs({ "Activated", "MouseButton1Down", "MouseButton1Up", "MouseButton1Click" }) do
	fakeEvent("GuiButton", e)
end
for _, e in ipairs({ "MouseEnter", "MouseLeave" }) do
	fakeEvent("GuiObject", e)
end
roblox.implementMethod("RemoteEvent", "FireServer", function() end)
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
-- Module loader (Roblox-style require on ModuleScript instances)
---------------------------------------------------------------------------------------------

local cache = {}
local env
local threads = {}
local trackedTask = setmetatable({}, { __index = task })
-- Background loops are parked forever on their first wait: the harness drives the step
-- functions itself.
trackedTask.wait = function()
	coroutine.yield()
end
for _, name in ipairs({ "spawn", "delay", "defer" }) do
	trackedTask[name] = function(...)
		local thread = task[name](...)
		table.insert(threads, thread)
		return thread
	end
end
local handlerErrors = 0
local warnings = {}

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

local function randomStub()
	return {
		new = function()
			return {
				NextNumber = function(_, a, b)
					local r = math.random()
					if a and b then
						return a + (b - a) * r
					end
					return r
				end,
				NextInteger = function(_, a, b)
					return math.random(a, b)
				end,
			}
		end,
	}
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

env = {
	game = game,
	workspace = workspaceService,
	require = requireModule,
	Instance = {
		new = function(className, parent)
			local instance = roblox.Instance.new(className)
			if instance:IsA("BasePart") then
				instance.Position = V3.zero
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
	Random = randomStub(),
	TweenInfo = stubCtor("TweenInfo"),
	task = trackedTask,
	typeof = typeof,
	warn = function(...)
		local message = table.concat({ ... }, " ")
		print("[warn]", message)
		table.insert(warnings, message)
		if string.find(message, "handler error", 1, true) or string.find(message, "Failed to start", 1, true) then
			handlerErrors += 1
		end
	end,
}

---------------------------------------------------------------------------------------------
-- Test helpers
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
local function settle()
	task.wait(0)
	task.wait(0)
end

-- Records every server -> client message.
local sent = {}
local function stubRemote(name)
	return {
		FireClient = function(_, player, ...)
			table.insert(sent, { name = name, player = player, args = { ... } })
		end,
		FireAllClients = function(_, ...)
			table.insert(sent, { name = name, all = true, args = { ... } })
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
local function sentTo(player, name, firstArg)
	for i = #sent, 1, -1 do
		local m = sent[i]
		if m.name == name and (m.player == player or m.all) and (firstArg == nil or m.args[1] == firstArg) then
			return m
		end
	end
	return nil
end
local function clearSent()
	table.clear(sent)
end

local function makePlayer(userId, name)
	local player = roblox.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = playersService
	table.insert(playerList, player)
	return player
end

local function makeCharacter(player)
	local character = roblox.Instance.new("Model")
	character.Name = player.Name
	local hrp = roblox.Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Position = V3.zero
	hrp.Size = V3.new(2, 2, 1)
	hrp.CFrame = CF.new(0, 3, 0)
	hrp.Parent = character
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Position = V3.zero
	head.Size = V3.new(2, 1, 1)
	head.CFrame = CF.new(0, 4.5, 0)
	head.Parent = character
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = 16
	humanoid.Parent = character
	character.PrimaryPart = hrp
	character.Parent = workspaceService
	characterOwner[character] = player
	player.Character = character
	return character, hrp, humanoid
end

local function moveTo(player, position)
	player.Character.HumanoidRootPart.CFrame = CF.new(position)
end

---------------------------------------------------------------------------------------------
-- Load modules
---------------------------------------------------------------------------------------------

local RS = place:GetService("ReplicatedStorage")
local SSS = place:GetService("ServerScriptService")
local Shared = RS:FindFirstChild("SnatchTycoon")
local Services = SSS:FindFirstChild("SnatchTycoonServer"):FindFirstChild("Services")

local GameConfig = requireModule(Shared.Config.GameConfig)
local BlobbyConfig = requireModule(Shared.Config.BlobbyConfig)
local RarityConfig = requireModule(Shared.Config.RarityConfig)
local MutationConfig = requireModule(Shared.Config.MutationConfig)
local ShopConfig = requireModule(Shared.Config.ShopConfig)
local EventConfig = requireModule(Shared.Config.EventConfig)
local Economy = requireModule(Shared.Economy)

-- Give four products fake ids so the ProcessReceipt path can be exercised.
local FAKE_IDS = { CashSmall = 1001, MythicCrate = 1002, LockNow = 1003, ServerLuck = 1004 }
for _, product in ipairs(ShopConfig.Products) do
	if FAKE_IDS[product.Key] then
		product.ProductId = FAKE_IDS[product.Key]
	end
end

local registry = { Remotes = remotes }
local order = { "DataService", "FeedService", "PlayerService", "ShopService", "PlotService", "BlobbyService", "StealService", "CarpetService", "EventService", "RewardService", "LeaderboardService" }
local world, WorldBuilder, BlobbyModels, Mover

check("server modules load", function()
	for _, name in ipairs(order) do
		registry[name] = requireModule(Services[name])
	end
	WorldBuilder = requireModule(Services.WorldBuilder)
	Mover = requireModule(Services.Mover)
	BlobbyModels = requireModule(Shared.BlobbyModels)
	for _, m in ipairs(Services:GetChildren()) do
		requireModule(m)
	end
end)

check("world builds: 8 bases x 20 pedestals, carpet, portal, boards", function()
	world = WorldBuilder.build()
	assert(#world.plots == GameConfig.MaxPlayers, "plot count")
	local parts = 0
	for _, d in ipairs(world.folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	assert(parts > 500 and parts < 2500, "unexpected part count " .. parts)
	for _, plot in ipairs(world.plots) do
		assert(#plot.pedestals == GameConfig.MaxPedestals, "pedestals")
		assert(plot.laser.blocker and #plot.laser.bars == 6 and plot.lockPrompt and plot.signLabel)
		for _, pedestal in ipairs(plot.pedestals) do
			assert(pedestal.pad and pedestal.cashLabel and pedestal.standCFrame)
		end
	end
	assert(#world.leaderboard.rows == 10 and #world.eventBoard.rows == 6, "boards")
	print(string.format("        world: %d parts", parts))
end)

check("every species builds with every mutation: welded, massless, non-colliding", function()
	local maxParts, minParts = 0, math.huge
	for _, species in ipairs(BlobbyConfig.List) do
		for _, mutation in ipairs({ false, "Gold", "Diamond", "Rainbow" }) do
			local built = BlobbyModels.build(species, CF.new(5, 1, 5), {
				rarity = RarityConfig.Tiers[species.Rarity],
				mutation = mutation or nil,
				mutationDef = mutation and MutationConfig.Types[mutation] or nil,
			})
			local model = built.model
			assert(model.PrimaryPart == built.root and built.root.Anchored, species.Id .. ": root")
			assert(built.motor.Part0 == built.root and built.motor.Part1 == built.main, species.Id .. ": bob motor")
			local count = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					count += 1
					assert(not d.CanCollide and not d.CanTouch and d.Massless, species.Id .. "." .. d.Name .. " affects physics")
					if d ~= built.root and d ~= built.main then
						local joint = d:FindFirstChildOfClass("WeldConstraint")
						local isHub = d.Name == "SpinnerHub"
						assert(joint or isHub, species.Id .. "." .. d.Name .. " is not welded")
					end
				end
			end
			if mutation == "Rainbow" then
				local rainbow = 0
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d:GetAttribute("Rainbow") then
						rainbow += 1
					end
				end
				assert(rainbow > 0, species.Id .. " rainbow parts")
			end
			maxParts = math.max(maxParts, count)
			minParts = math.min(minParts, count)
			local labels = BlobbyModels.nameplate(built, { name = species.Name, rarity = species.Rarity, rarityColor = RarityConfig.Tiers[species.Rarity].Color, mutation = mutation or nil, value = "$1/s" })
			assert(labels.name.Text == species.Name)
			assert(model:GetAttribute("Bob") == species.Bob and model:HasTag("Blobby"))
			model:Destroy()
		end
	end
	assert(maxParts <= 70, "a Blobby is too heavy: " .. maxParts .. " parts")
	assert(minParts >= 8, "a Blobby is too plain: " .. minParts .. " parts")
	print(string.format("        blobby parts: %d..%d", minParts, maxParts))
end)

---------------------------------------------------------------------------------------------
-- Services
---------------------------------------------------------------------------------------------

local S = registry
local A, B, Cp

check("services init + start in Main's order", function()
	for _, name in ipairs(order) do
		registry[name].init(registry)
	end
	S.PlotService.setWorld(world)
	S.BlobbyService.setWorld(world)
	S.CarpetService.setWorld(world)
	S.EventService.setWorld(world)
	S.LeaderboardService.setWorld(world)
	for _, name in ipairs({ "FeedService", "PlayerService", "ShopService", "BlobbyService", "RewardService", "StealService", "PlotService", "EventService", "CarpetService", "LeaderboardService", "DataService" }) do
		registry[name].start()
	end
	settle()
	assert(#S.CarpetService.walkers() == 12, "carpet should be seeded with 12 Blobbies")
	assert(fakeMarket.ProcessReceipt == S.ShopService.processReceipt, "ProcessReceipt not bound")
end)

check("two players join: plots, leaderstats, welcome, friends boost", function()
	A = makePlayer(1, "Alice")
	B = makePlayer(2, "Bob")
	for _, p in ipairs({ A, B }) do
		makeCharacter(p)
		fakePlayers.PlayerAdded:Fire(p)
		p.CharacterAdded:Fire(p.Character)
	end
	settle()
	assert(S.PlotService.plotIndexOf(A) == 1 and S.PlotService.plotIndexOf(B) == 2, "plot assignment")
	assert(A:FindFirstChild("leaderstats") and A.leaderstats.Cash.Value == "$100", "leaderstats")
	assert(S.DataService.isPersistent(A), "fake DataStore should make profiles persistent")
	assert(sentTo(A, "Popup", "Welcome"), "first join should show the welcome card")
	assert(sentTo(A, "Profile"), "profile snapshot sent")
	assert(S.PlayerService.session(A).friends == 1, "Alice and Bob are friends")
	assert(math.abs(S.PlayerService.multiplier(A) - 1.1) < 1e-6, "friend boost +10%")
	assert(world.plots[1].signLabel.Text == "ALICE'S BASE")
	assert(A.Character.HumanoidRootPart.CFrame.Position.Y > 2, "spawned at the base")
end)

local profileA, profileB
local bought

check("buy a Blobby on the carpet: price, distance, full checks; it walks home", function()
	profileA = S.DataService.getProfile(A)
	profileB = S.DataService.getProfile(B)
	profileA.Cash = 100000
	local walker = S.CarpetService.spawn({ rarity = "Rare", mutation = "Gold", z = -40 })
	-- too far away
	moveTo(A, V3.new(60, 3, 60))
	walker.prompt.Triggered:Fire(A)
	assert(not walker.sold, "bought from too far away")
	moveTo(A, walker.built.root.CFrame.Position + V3.new(3, 2, 0))
	walker.prompt.Triggered:Fire(A)
	assert(walker.sold, "purchase failed")
	-- (the "buy a Blobby" session goal pays its minimum reward on top)
	local goalReward = requireModule(Shared.Config.RewardConfig).Goals[1].Reward.Minimum
	assert(profileA.Cash == 100000 - walker.price + goalReward, "price not charged: " .. profileA.Cash)
	assert(walker.price == walker.species.Price * 2, "gold price multiplier")
	local uid, entry = next(profileA.Blobbies)
	assert(uid and entry.Species == walker.species.Id and entry.Mutation == "Gold" and entry.Slot == 1, "profile entry")
	bought = S.BlobbyService.get(uid)
	assert(bought.state == "Walking" and Mover.isMoving(bought.built.root), "should walk home")
	assert(not S.CarpetService.buy(A, walker), "bought the same Blobby twice")
	assert(profileA.Cash == 100000 - walker.price + goalReward, "double buy")
	for _ = 1, 200 do
		Mover.step(0.25)
	end
	assert(bought.state == "Placed", "never arrived: " .. bought.state)
	local stand = world.plots[1].pedestals[1].standCFrame.Position
	assert((bought.built.root.CFrame.Position - stand).Magnitude < 0.01, "not on its pedestal")
	assert(profileA.Discovered[walker.species.Id], "discovered")
	assert(sentTo(A, "Popup", "Discovered") and sentTo(A, "Popup", "Bought"))
end)

check("income ticks onto the pedestal and the pad collects it", function()
	S.PlayerService.tick(10)
	local expected = bought.income * S.PlayerService.multiplier(A) * 10
	assert(math.abs(bought.pending - expected) < 1e-6, "pending " .. bought.pending .. " vs " .. expected)
	assert(world.plots[1].pedestals[1].cashLabel.Text ~= "", "cash label empty")
	local before = profileA.Cash
	world.plots[1].pedestals[1].pad.Touched:Fire(B.Character.HumanoidRootPart)
	assert(profileA.Cash == before, "Bob collected Alice's cash")
	world.plots[1].pedestals[1].pad.Touched:Fire(A.Character.HumanoidRootPart)
	-- (+ the "collect $250" session goal reward, which scales with income)
	assert(profileA.Cash >= before + math.floor(expected), string.format("collect amount: %d -> %d (pending %.1f)", before, profileA.Cash, expected))
	assert(sentTo(A, "Popup", "Cash") and sentTo(A, "Tick"))
	assert(A.leaderstats["Per Sec"].Value ~= "$0/s")
end)

check("steal: hold alarms the owner, grab carries it, slap drops it, it runs home", function()
	clearSent()
	local rec = bought
	moveTo(B, rec.built.root.CFrame.Position + V3.new(2, 2, 0))
	rec.stealPrompt.PromptButtonHoldBegan:Fire(B)
	assert(sentTo(A, "Alarm"), "owner not alarmed")
	rec.stealPrompt.Triggered:Fire(A)
	assert(rec.state == "Placed", "owner stole own Blobby")
	rec.stealPrompt.Triggered:Fire(B)
	assert(rec.state == "Carried", "grab failed")
	assert(S.StealService.isCarrying(B) and rec.built.root:FindFirstChild("CarryWeld"), "carry weld")
	assert(B.Character.Humanoid.WalkSpeed < GameConfig.WalkSpeed, "carrier should be slow")
	assert(sentTo(B, "Carry") and sentTo(nil, "Feed"), "carry / feed messages")
	assert(S.BlobbyService.baseIncome(A) == 0, "a carried Blobby must not earn")
	-- Alice slaps Bob
	moveTo(A, B.Character.HumanoidRootPart.CFrame.Position + V3.new(3, 0, 0))
	local ok, target = S.StealService.slap(A)
	assert(ok and target == B, "slap missed")
	assert(not S.StealService.isCarrying(B) and rec.state == "Returning", "drop failed")
	assert(sentTo(B, "Knockback") and sentTo(nil, "SlapFx"))
	assert(B.Character.Humanoid.WalkSpeed == GameConfig.WalkSpeed, "speed restored")
	assert(profileA.Stats.Defended == 1)
	for _ = 1, 200 do
		Mover.step(0.25)
	end
	assert(rec.state == "Placed", "did not run home")
	-- stunned right after a slap
	rec.stealPrompt.Triggered:Fire(B)
	assert(rec.state == "Placed", "stunned thief grabbed")
end)

check("steal + deliver: ownership moves to the thief's base", function()
	task.wait(GameConfig.Steal.StunAfterSlap + 0.1)
	local rec = bought
	moveTo(B, rec.built.root.CFrame.Position + V3.new(2, 2, 0))
	rec.stealPrompt.Triggered:Fire(B)
	assert(rec.state == "Carried", "second grab failed")
	S.StealService.step()
	assert(S.StealService.isCarrying(B), "delivered too early")
	moveTo(B, world.plots[2].spawnCFrame.Position)
	S.StealService.step()
	assert(not S.StealService.isCarrying(B), "not delivered")
	assert(next(profileA.Blobbies) == nil, "Alice still owns it")
	local uid, entry = next(profileB.Blobbies)
	assert(uid and entry.Mutation == "Gold", "Bob didn't get it")
	assert(profileB.Stats.Stolen == 1 and profileA.Stats.Robbed == 1)
	assert(sentTo(B, "Popup", "Stolen"))
	for _ = 1, 200 do
		Mover.step(0.25)
	end
	assert(S.BlobbyService.get(uid).state == "Placed")
end)

check("lock: blocks steals, ejects intruders, cooldown, laser visuals", function()
	local uid = S.BlobbyService.add(A, "Gigachonk", nil)
	local rec = S.BlobbyService.get(uid)
	assert(rec and rec.state == "Placed")
	moveTo(B, rec.built.root.CFrame.Position + V3.new(2, 2, 0))
	assert(S.PlotService.insidePlot(1, B.Character.HumanoidRootPart.CFrame.Position), "Bob should be inside")
	assert(S.PlotService.lock(A, false), "lock failed")
	assert(world.plots[1].laser.blocker.CanCollide, "laser not solid")
	assert(not S.PlotService.insidePlot(1, B.Character.HumanoidRootPart.CFrame.Position), "intruder not ejected")
	moveTo(B, rec.built.root.CFrame.Position + V3.new(2, 2, 0))
	rec.stealPrompt.Triggered:Fire(B)
	assert(rec.state == "Placed", "stole through a locked door")
	assert(not S.PlotService.lock(A, false), "double lock")
	S.PlotService.step()
	assert(string.find(world.plots[1].statusLabel.Text, "LOCKED"), "status label")
	-- Lock Base Now can't be bought while locked
	clearSent()
	S.ShopService.requestProduct(A, "LockNow")
	assert(#prompted == 0, "prompted LockNow while locked")
	assert(sentTo(A, "Notify"))
end)

check("receipts: granted once, rollback on failed save, crate, server luck, lock token", function()
	local function receipt(id, productId, player)
		return S.ShopService.processReceipt({ PlayerId = (player or A).UserId, ProductId = productId, PurchaseId = id })
	end
	local Granted, NotYet = roblox.Enum.ProductPurchaseDecision.PurchaseGranted, roblox.Enum.ProductPurchaseDecision.NotProcessedYet
	local before = profileA.Cash
	assert(receipt("r1", 1001) == Granted)
	local afterFirst = profileA.Cash
	assert(afterFirst > before, "cash pack not granted")
	assert(receipt("r1", 1001) == Granted, "duplicate should still say granted")
	assert(profileA.Cash == afterFirst, "duplicate receipt granted twice")
	assert(storeData["player_1"] and storeData["player_1"].Receipts.r1, "receipt saved before granting")
	-- DataStore outage: nothing granted, Roblox retries later
	storeFailSaves = true
	assert(receipt("r2", 1001) == NotYet, "should not grant without saving")
	assert(profileA.Cash == afterFirst and not profileA.Receipts.r2, "rollback failed")
	storeFailSaves = false
	assert(receipt("r2", 1001) == Granted and profileA.Cash > afterFirst, "retry")
	-- unknown player / product
	assert(S.ShopService.processReceipt({ PlayerId = 999, ProductId = 1001, PurchaseId = "x" }) == NotYet)
	assert(receipt("r3", 4242) == NotYet)
	-- Mythic crate: a Mythic or Secret lands in the base
	local count = 0
	for _ in pairs(profileA.Blobbies) do
		count += 1
	end
	assert(receipt("r4", 1002) == Granted)
	local count2, crateRec = 0, nil
	for uid, e in pairs(profileA.Blobbies) do
		count2 += 1
		local sp = BlobbyConfig.ById[e.Species]
		if sp.Rarity == "Mythic" or sp.Rarity == "Secret" then
			crateRec = S.BlobbyService.get(uid)
		end
	end
	assert(count2 == count + 1 and crateRec, "crate Blobby missing")
	assert(sentTo(A, "Popup", "Reveal"))
	for _ = 1, 200 do
		Mover.step(0.25)
	end
	assert(crateRec.state == "Placed", "crate Blobby did not walk in")
	-- Server luck for everyone
	local luckBefore = S.EventService.luck()
	assert(receipt("r5", 1004) == Granted)
	assert(S.EventService.luck() == luckBefore * 2, "server luck not applied")
	assert(S.EventService.serverLuckRemaining() > 800)
	-- Lock token while the door is locked is kept for later
	assert(receipt("r6", 1003) == Granted)
	assert(profileA.LockTokens == 1, "lock token")
end)

check("passes: Studio grants, 2x cash doubles income, VIP adds a slot, auto-collect", function()
	local m1 = S.PlayerService.multiplier(B)
	S.ShopService.requestPass(B, "DoubleCash")
	assert(S.ShopService.owns(B, "DoubleCash"), "pass not granted in Studio")
	assert(math.abs(S.PlayerService.multiplier(B) - m1 * 2) < 1e-6, "2x cash")
	local slots = S.PlayerService.slots(B)
	task.wait(1.05)
	S.ShopService.requestPass(B, "VIP")
	assert(S.PlayerService.slots(B) == slots + 1, "VIP slot")
	assert(B:GetAttribute("VIP") == true, "VIP attribute for chat tag")
	task.wait(1.05)
	S.ShopService.requestPass(B, "AutoCollect")
	local before = profileB.Cash
	S.PlayerService.tick(5)
	assert(profileB.Cash > before, "auto-collect did not pay out")
	task.wait(1.05)
	S.ShopService.requestPass(B, "FastCarry")
	assert(S.ShopService.owns(B, "FastCarry"))
	-- pass with a real id prompts instead
	ShopConfig.Passes[5].PassId = 777
	S.ShopService.init(registry)
	task.wait(1.05)
	S.ShopService.requestPass(B, "ExtraSlots")
	assert(prompted[#prompted] and prompted[#prompted].id == 777, "real pass id should prompt")
	fakeMarket.PromptGamePassPurchaseFinished:Fire(B, 777, true)
	assert(S.ShopService.owns(B, "ExtraSlots") and S.PlayerService.slots(B) == slots + 4)
	ShopConfig.Passes[5].PassId = 0
	S.ShopService.init(registry)
end)

check("sell a Blobby for half price", function()
	local uid, entry = next(profileA.Blobbies)
	local value = Economy.sellValue(S.BlobbyService.priceOf(entry.Species, entry.Mutation), GameConfig.SellRefund)
	local rec = S.BlobbyService.get(uid)
	local before = profileA.Cash
	rec.sellPrompt.Triggered:Fire(B)
	assert(profileA.Blobbies[uid], "Bob sold Alice's Blobby")
	rec.sellPrompt.Triggered:Fire(A)
	assert(not profileA.Blobbies[uid], "not sold")
	assert(profileA.Cash >= before + value, "sell value")
end)

check("base full: queue, then flush when a slot frees", function()
	local slots = S.PlayerService.slots(A)
	local n = 0
	for _ in pairs(profileA.Blobbies) do
		n += 1
	end
	for _ = n + 1, slots do
		S.BlobbyService.add(A, "Wobbleton", nil)
	end
	assert(S.BlobbyService.freeSlot(A) == nil, "should be full")
	local queued = #profileA.Queued
	S.BlobbyService.add(A, "Snorkpuff", nil)
	assert(#profileA.Queued == queued + 1, "not queued")
	local walker = S.CarpetService.spawn({ rarity = "Common", mutation = false, z = 0 })
	moveTo(A, walker.built.root.CFrame.Position + V3.new(2, 2, 0))
	walker.prompt.Triggered:Fire(A)
	assert(not walker.sold, "bought into a full base")
	local uid = next(profileA.Blobbies)
	S.BlobbyService.sell(A, uid)
	assert(#profileA.Queued == queued and S.BlobbyService.freeSlot(A) == nil, "queue not flushed")
end)

check("rebirth: costs cash, resets, multiplier and slot up", function()
	profileA.Cash = 10
	assert(not S.PlayerService.rebirth(A), "rebirth without cash")
	local cost = Economy.rebirthCost(profileA.Rebirths, GameConfig.Rebirth)
	local slots = S.PlayerService.slots(A)
	profileA.Cash = cost
	assert(S.PlayerService.rebirth(A), "rebirth failed")
	assert(profileA.Rebirths == 1 and profileA.Cash == GameConfig.StartCash, "reset")
	assert(next(profileA.Blobbies) == nil, "blobbies kept")
	assert(S.PlayerService.slots(A) == slots + 1, "slot")
	assert(#S.BlobbyService.records(A) == 0)
	assert(sentTo(A, "Popup", "Rebirth"))
end)

check("daily reward claims once per day, codes once per player", function()
	assert(S.RewardService.claimDaily(A), "daily")
	assert(not S.RewardService.claimDaily(A), "daily twice")
	assert(profileA.Daily.Streak == 1)
	local before = profileA.Cash
	assert(S.RewardService.redeem(A, " release "), "RELEASE code")
	assert(profileA.Cash == before + 1000)
	assert(not S.RewardService.redeem(A, "RELEASE"), "code twice")
	assert(not S.RewardService.redeem(A, "NOPE"))
	assert(not S.RewardService.redeem(A, 42))
	assert(S.RewardService.redeem(A, "snatch"), "Blobby code")
end)

check("goals progress and pay out", function()
	local state = S.RewardService.goalState(A)
	assert(state and #state.active == 3)
	local before = profileA.Cash
	for _ = 1, 30 do
		S.RewardService.recordGoal(A, "Lock", 1)
		S.RewardService.recordGoal(A, "Buy", 5)
	end
	assert(profileA.Cash > before, "no goal rewards")
	assert(sentTo(A, "Popup", "Goal"))
end)

check("admin events rotate; cash rain coins pay the collector", function()
	clearSent()
	local seen = {}
	for cycle = 0, #EventConfig.Admin - 1 do
		S.EventService.setElapsed(GameConfig.Events.FirstAdminDelay + cycle * GameConfig.Events.AdminInterval + 1)
		S.EventService.step(0.25)
		local ev = S.EventService.currentAdmin()
		assert(ev, "no event in cycle " .. cycle)
		seen[ev.Id] = true
		if ev.CashRain then
			local coin = S.EventService.spawnCoin()
			local before = profileA.Cash
			coin.Touched:Fire(A.Character.HumanoidRootPart)
			assert(profileA.Cash > before and not coin.Parent, "coin")
		elseif ev.MythicBoost then
			assert(S.EventService.mythicBoost() > 1)
		elseif ev.IncomeMult then
			assert(S.EventService.incomeMult() == 2)
		end
	end
	for _, ev in ipairs(EventConfig.Admin) do
		assert(seen[ev.Id], "event never ran: " .. ev.Id)
	end
	S.EventService.setElapsed(GameConfig.Events.FirstAdminDelay + GameConfig.Events.AdminDuration + 5)
	S.EventService.step(0.25)
	assert(S.EventService.currentAdmin() == nil)
	local snap = S.EventService.snapshot()
	assert(snap.nextIn > 0 and snap.nextName, "countdown")
	assert(sentTo(nil, "Events") and sentTo(nil, "Feed"))
end)

check("carpet: Blobbies walk the whole carpet and despawn at the end", function()
	for _ = 1, 400 do
		S.CarpetService.step(0.5)
	end
	local walkers = S.CarpetService.walkers()
	assert(#walkers > 0 and #walkers <= GameConfig.Carpet.MaxOnCarpet, "walker count " .. #walkers)
	for _, w in ipairs(walkers) do
		assert(w.z < GameConfig.Carpet.EndZ)
	end
end)

check("leaderboard posts best income and renders the board", function()
	S.LeaderboardService.refresh()
	assert(ordered["1"] or ordered["2"], "nothing posted")
	assert(world.leaderboard.rows[1].Text ~= "", "board empty")
end)

check("offline earnings: returning player gets capped income", function()
	storeData["player_3"] = {
		Version = 1,
		Cash = 50,
		LastSeen = os.time() - 7200,
		Blobbies = { b1 = { Species = "CaptainSquish", Slot = 1 } },
		NextUid = 2,
	}
	Cp = makePlayer(3, "Carol")
	makeCharacter(Cp)
	clearSent()
	fakePlayers.PlayerAdded:Fire(Cp)
	settle()
	local msg = sentTo(Cp, "Popup", "Offline")
	assert(msg, "no offline popup")
	local ips = BlobbyConfig.ById.CaptainSquish.Income
	local expected = Economy.offlineEarnings(ips, 7200, GameConfig.OfflineCapHours * 3600, GameConfig.OfflineRate)
	assert(math.abs(msg.args[2].amount - expected) <= ips * 2, "offline amount " .. msg.args[2].amount .. " vs " .. expected)
	assert(S.DataService.getProfile(Cp).Daily, "reconciled missing fields")
	assert(S.PlotService.plotIndexOf(Cp) == 3)
end)

check("leaving saves the profile and frees the plot", function()
	local uidCount = 0
	for _ in pairs(profileB.Blobbies) do
		uidCount += 1
	end
	B.Parent = nil
	fakePlayers.PlayerRemoving:Fire(B)
	assert(S.DataService.getProfile(B) == nil, "profile kept")
	assert(world.plots[2].signLabel.Text == "EMPTY PLOT", "plot not freed")
	local saved = storeData["player_2"]
	local savedCount = 0
	for _ in pairs(saved.Blobbies) do
		savedCount += 1
	end
	assert(savedCount == uidCount, "saved Blobbies")
	assert(#S.BlobbyService.records(B) == 0)
end)

check("remotes reject bad arguments", function()
	for _, bad in ipairs({ 0 / 0, math.huge, {}, "", string.rep("x", 200), nil, true }) do
		remotes.RedeemCode.OnServerEvent:Fire(A, bad)
		remotes.ShopBuy.OnServerEvent:Fire(A, bad)
		remotes.PassBuy.OnServerEvent:Fire(A, bad)
		remotes.SaveSettings.OnServerEvent:Fire(A, bad)
	end
	remotes.SaveSettings.OnServerEvent:Fire(A, { Music = "yes", Sfx = 5 })
	assert(profileA.Settings.Music == true and profileA.Settings.Sfx == true, "settings accepted junk")
	for _ = 1, 20 do
		remotes.Slap.OnServerEvent:Fire(A)
		remotes.LockBase.OnServerEvent:Fire(A)
		remotes.DropCarried.OnServerEvent:Fire(A)
		remotes.Rebirth.OnServerEvent:Fire(A)
		remotes.ClaimDaily.OnServerEvent:Fire(A)
		remotes.RequestState.OnServerEvent:Fire(A)
	end
	assert(profileA.Cash == profileA.Cash and profileA.Cash >= 0)
end)

---------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------

check("client controllers initialise and render real server snapshots", function()
	requireModule(Shared.Net).setup()
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = A
	fakePlayers.LocalPlayer = A
	fakeRun.IsServer = function()
		return false
	end
	local Net = requireModule(Shared.Net)
	local folder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("SnatchTycoonClient"):FindFirstChild("Controllers")
	local controllers = {}
	for _, name in ipairs({ "ClientState", "AudioController", "HudController", "MenuController", "EffectsController", "WorldController", "InputController", "ChatController" }) do
		controllers[name] = requireModule(folder[name])
		controllers[name].init()
	end
	-- Feed the client the real server snapshot for Alice
	settle()
	local snap = S.PlayerService.snapshot(A)
	Net.event("Profile").OnClientEvent:Fire(snap)
	Net.event("Tick").OnClientEvent:Fire({ cash = 1234, ips = 56, lock = { status = "Cooldown", remaining = 30 }, lockTokens = 1 })
	Net.event("Events").OnClientEvent:Fire(S.EventService.snapshot())
	Net.event("Carry").OnClientEvent:Fire({ name = "Gold Gigachonk", rarity = "Legendary", timeout = 45, victim = "Bob" })
	Net.event("Feed").OnClientEvent:Fire("Bob STOLE Alice's MYTHIC Cosmo Blorbo!", { 255, 64, 112 }, true)
	Net.event("Notify").OnClientEvent:Fire("Hello", "warn")
	Net.event("Alarm").OnClientEvent:Fire("Bob", "Gigachonk")
	Net.event("Sfx").OnClientEvent:Fire("CollectCash", V3.new(1, 2, 3))
	Net.event("SlapFx").OnClientEvent:Fire(V3.new(0, 3, 0), V3.new(3, 3, 0), true)
	Net.event("Knockback").OnClientEvent:Fire(V3.new(40, 30, 0))
	local popups = {
		{ "Cash", { amount = 123, position = V3.new(0, 3, 0) } },
		{ "Cash", { amount = 80000, big = true } },
		{ "AutoCash", { amount = 12 } },
		{ "Bought", { name = "Gigachonk", rarity = "Legendary", mutation = "Gold", price = 130000, position = V3.new(0, 1, 0) } },
		{ "Bought", { name = "Wobbleton", rarity = "Common", price = 25, position = V3.new(0, 1, 0) } },
		{ "Discovered", { species = "Wobbleton" } },
		{ "Reveal", { species = "CosmoBlorbo", mutation = "Rainbow", rarity = "Mythic", source = "crate" } },
		{ "Stolen", { name = "MYTHIC Cosmo Blorbo", rarity = "Mythic", species = "CosmoBlorbo" } },
		{ "Rebirth", { rebirths = 2, mult = 2 } },
		{ "Goal", { text = "Buy a Blobby", reward = 100 } },
		{ "Daily", { day = 3, streak = 3, text = "Server Luck" } },
		{ "Code", { code = "RELEASE", text = "$1K" } },
		{ "Locked", { duration = 45 } },
		{ "Offline", { amount = 5000, seconds = 7300, capped = false } },
		{ "Welcome", {} },
	}
	for _, p in ipairs(popups) do
		Net.event("Popup").OnClientEvent:Fire(p[1], p[2])
	end
	local Menu = controllers.MenuController
	for _, name in ipairs({ "Shop", "Rebirth", "Daily", "Index", "Codes", "Settings" }) do
		Menu.open(name)
		assert(Menu.isOpen(name), name .. " did not open")
	end
	Menu.open("Shop")
	-- click through the shop tabs
	local shopFrame = playerGui.SnatchMenus.Shop
	local clicked = 0
	for _, tabName in ipairs({ "BOOSTS", "PASSES", "CASH" }) do
		for _, d in ipairs(shopFrame:GetDescendants()) do
			if d:IsA("TextButton") and d.Text == tabName then
				d.Activated:Fire()
				clicked += 1
				break
			end
		end
	end
	assert(clicked == 3, "shop tabs missing")
	Menu.close()
	-- world presentation
	local World = controllers.WorldController
	local tracked = 0
	for _, model in ipairs(stubServices.CollectionService:GetTagged("Blobby")) do
		World.track(model)
		tracked += 1
	end
	assert(tracked > 5, "no Blobbies to animate")
	World.step()
	World.updateDoors()
	assert(not world.plots[1].laser.blocker.CanCollide, "own laser door should be passable locally")
	for _, style in ipairs({ "Bounce", "Wobble", "Spin", "Hop", "Sway", "Float" }) do
		World.bobTransform(style, 1.3, false)
	end
	controllers.HudController.renderEvents()
	assert(playerGui:FindFirstChild("SnatchHUD") and playerGui:FindFirstChild("SnatchMenus") and playerGui:FindFirstChild("SnatchEffects"), "GUIs missing")
	settle()
end)

if handlerErrors > 0 then
	failed += 1
	print(string.format("  FAIL  %d errors were swallowed by signal handlers / controller init", handlerErrors))
end
print(string.format("\nharness: %d passed, %d failed", passed, failed))
for _, thread in ipairs(threads) do
	pcall(task.cancel, thread)
end
process.exit(if failed > 0 then 1 else 0)
