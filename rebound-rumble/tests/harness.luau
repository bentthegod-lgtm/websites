--[[
	Headless smoke harness for REBOUND RUMBLE.

	Loads the Rojo-built place file in Lune and executes the REAL game modules against
	Lune's Roblox instance implementation (which validates class, property and enum names
	against the Roblox reflection database). Engine services Lune does not simulate
	(players, data stores, marketplace, tweens, physics) are stubbed, and time is driven
	by the harness through Shared.Clock so whole rounds can be simulated deterministically.

	It catches wrong property/class/enum names, nil errors and broken server flows. It does
	NOT simulate physics or networking (bots and players don't actually walk here).

	Usage (from rebound-rumble/):
	  rojo build -o build/ReboundRumble.rbxlx && lune run tests/harness build/ReboundRumble.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/ReboundRumble.rbxlx"
local place = roblox.deserializePlace(fs.readFile(placePath))
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

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
			if string.match(key, "^%u%w*Added$") or string.match(key, "^%u%w*Removing$") or string.match(key, "Finished$") or string.match(key, "Began$") or string.match(key, "Ended$") or key == "Heartbeat" or key == "Stepped" or key == "RenderStepped" then
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
local realPlayers = place:GetService("Players")
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
		return "User" .. id
	end,
})

local prompts = {}
local marketplace = stubObject("MarketplaceService", {
	UserOwnsGamePassAsync = function()
		return false
	end,
	PromptProductPurchase = function(_, player, id)
		table.insert(prompts, { kind = "product", player = player, id = id })
	end,
	PromptGamePassPurchase = function(_, player, id)
		table.insert(prompts, { kind = "pass", player = player, id = id })
	end,
})

-- Toggled by tests that simulate a live (non-Studio) server.
local harnessIsStudio = true

local stubServices = {
	TweenService = stubObject("TweenService", {
		Create = function(_, instance, _info, goals)
			return {
				Play = function()
					for k, v in pairs(goals) do
						instance[k] = v
					end
				end,
				Completed = signal(),
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
			return harnessIsStudio
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
	MarketplaceService = marketplace,
	Debris = stubObject("Debris"),
	UserInputService = stubObject("UserInputService", { TouchEnabled = true, KeyboardEnabled = true, GamepadEnabled = false }),
	ContextActionService = stubObject("ContextActionService"),
	GuiService = stubObject("GuiService"),
	StarterGui = stubObject("StarterGui"),
	SocialService = stubObject("SocialService", {
		CanSendGameInviteAsync = function()
			return true
		end,
	}),
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
	local root = self.PrimaryPart or self:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = cf
	end
end)
roblox.implementMethod("Model", "GetPivot", function(self)
	local root = self.PrimaryPart or self:FindFirstChild("HumanoidRootPart")
	return if root then root.CFrame else CFrame.new()
end)
roblox.implementMethod("BasePart", "SetNetworkOwner", function() end)
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return os.clock()
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
fakeEvent("Player", "CharacterAdded")
fakeEvent("TextButton", "Activated")
fakeEvent("RemoteEvent", "OnClientEvent")
fakeEvent("RemoteEvent", "OnServerEvent")
roblox.implementMethod("Humanoid", "MoveTo", function() end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
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
local delayed = {}
local trackedTask = setmetatable({}, { __index = task })
-- Background loops park forever on their first wait: the harness drives time itself.
trackedTask.wait = function()
	coroutine.yield()
end
-- Delayed callbacks are recorded; the harness runs the ones it cares about explicitly.
trackedTask.delay = function(_, fn, ...)
	table.insert(delayed, { fn = fn, args = { ... } })
end
trackedTask.defer = function(fn, ...)
	return task.spawn(fn, ...)
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

env = {
	game = game,
	workspace = workspaceService,
	require = requireModule,
	Instance = {
		new = function(className, parent)
			local instance = roblox.Instance.new(className)
			if instance:IsA("BasePart") then
				instance.Position = Vector3.zero
			end
			if parent then
				instance.Parent = parent
			end
			return instance
		end,
	},
	Enum = roblox.Enum,
	Vector3 = Vector3,
	Vector2 = roblox.Vector2,
	CFrame = CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	TweenInfo = stubCtor("TweenInfo"),
	task = trackedTask,
	typeof = typeof,
	warn = function(...)
		local message = table.concat({ ... }, " ")
		print("[warn]", message)
		if string.find(message, "handler error", 1, true) or string.find(message, "Failed to start", 1, true) then
			handlerErrors += 1
		end
	end,
}
-- task.delay is called as task.delay(seconds, fn): adapt the recorder's signature.
trackedTask.delay = function(_seconds, fn, ...)
	table.insert(delayed, { fn = fn, args = { ... } })
end

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
local Shared = RS:FindFirstChild("ReboundRumble")
local Services = SSS:FindFirstChild("ReboundRumbleServer"):FindFirstChild("Services")

local simTime = 1000
local Clock = requireModule(Shared.Clock)
Clock.set(function()
	return simTime
end)

local function countParts(root)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

check("server modules load", function()
	for _, m in ipairs(Services:GetChildren()) do
		requireModule(m)
	end
end)

local lobby
check("lobby builds: spawn, leaderboard, status board, crate prompt", function()
	lobby = requireModule(Services.LobbyBuilder).build(workspaceService)
	assert(lobby.spawn:IsA("SpawnLocation") and lobby.spawnCFrame, "spawn")
	assert(lobby.cratePrompt:IsA("ProximityPrompt"), "crate prompt")
	lobby.board.setRows({ { rank = 1, name = "Ace", wins = 12 } }, nil)
	lobby.board.setRows({}, "offline")
	lobby.setStatus("TEST", nil)
	local parts = countParts(lobby.folder)
	assert(parts > 60 and parts < 900, "lobby part count " .. parts)
	print(string.format("        lobby parts: %d", parts))
end)

check("every arena theme builds with spawns inside the barrier", function()
	local ArenaBuilder = requireModule(Services.ArenaBuilder)
	local ArenaConfig = requireModule(Shared.Config.ArenaConfig)
	for _, theme in ipairs(ArenaConfig.Order) do
		for seed = 1, 3 do
			local arena = ArenaBuilder.build(theme, seed, workspaceService)
			assert(#arena.spawns == 16, "spawns")
			for _, cf in ipairs(arena.spawns) do
				local flat = cf.Position - arena.center
				assert(Vector3.new(flat.X, 0, flat.Z).Magnitude < arena.radius - 5, "spawn outside play area")
			end
			assert(arena.folder:FindFirstChild("Barrier") and arena.folder:FindFirstChild("BallPad") and arena.bots, theme .. " incomplete")
			local parts = countParts(arena.folder)
			assert(parts > 40 and parts < 1500, theme .. " part count " .. parts)
			if seed == 1 then
				print(string.format("        %s parts: %d", theme, parts))
			end
			arena.destroy()
		end
	end
end)

check("every parry weapon style builds a non-colliding model", function()
	local WeaponModels = requireModule(Shared.WeaponModels)
	local CosmeticConfig = requireModule(Shared.Config.CosmeticConfig)
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Category == "ParryFx" then
			local model = WeaponModels.build(item)
			assert(model.PrimaryPart, item.Id .. " no primary")
			local parts = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					parts += 1
					assert(d.Anchored and not d.CanCollide and not d.CanQuery, item.Id .. "." .. d.Name .. " collides")
				end
			end
			assert(parts >= 5, item.Id .. " only " .. parts .. " parts")
		end
	end
	assert(#WeaponModels.styles() == 5)
end)

---------------------------------------------------------------------------------------------
-- Server wiring with recording remotes
---------------------------------------------------------------------------------------------

local log = {}
local function record(name, target, ...)
	table.insert(log, { name = name, target = target, args = { ... } })
end
local remotes = setmetatable({}, {
	__index = function(t, k)
		local r = {
			FireAllClients = function(_, ...)
				record(k, "all", ...)
			end,
			FireClient = function(_, p, ...)
				record(k, p, ...)
			end,
			OnServerEvent = signal(),
		}
		rawset(t, k, r)
		return r
	end,
})
local function sent(name, target, predicate)
	local list = {}
	for _, e in ipairs(log) do
		if e.name == name and (target == nil or e.target == target) and (predicate == nil or predicate(table.unpack(e.args))) then
			table.insert(list, e)
		end
	end
	return list
end
local function lastSent(name, target)
	local list = sent(name, target)
	return list[#list]
end

-- Give one product a real-looking id so ProcessReceipt can be exercised.
local ShopConfig = requireModule(Shared.Config.ShopConfig)
for _, product in ipairs(ShopConfig.Products) do
	if product.Key == "Coins500" then
		product.ProductId = 111
	elseif product.Key == "ExplosionParty" then
		product.ProductId = 222
	end
end

local registry = { Remotes = remotes }
local order = { "DataService", "ShopService", "LeaderboardService", "RewardService", "CosmeticService", "AbilityService", "BotService", "BallService", "MatchService" }
check("services initialise and start", function()
	for _, name in ipairs(order) do
		registry[name] = requireModule(Services[name])
	end
	for _, name in ipairs(order) do
		registry[name].init(registry)
	end
	registry.MatchService.setLobby(lobby)
	registry.LeaderboardService.setBoard(lobby.board)
	registry.BotService.setSeed(42)
	registry.CosmeticService.setSeed(7)
	for _, name in ipairs(order) do
		if registry[name].start then
			registry[name].start()
		end
	end
end)

local function makePlayer(userId, name)
	local player = roblox.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = realPlayers
	local character = registry.BotService.buildModel(name, roblox.Color3.new(1, 1, 1), CFrame.new(0, 3, 18))
	character.Parent = workspaceService
	player.Character = character
	table.insert(playerList, player)
	fakePlayers.PlayerAdded:Fire(player)
	return player
end

local function removePlayer(player)
	fakePlayers.PlayerRemoving:Fire(player)
	table.remove(playerList, table.find(playerList, player))
end

local function fire(remoteName, player, ...)
	remotes[remoteName].OnServerEvent:Fire(player, ...)
end

local alice, bob
local DS
check("player joins: profile, leaderstats, lobby status, ready", function()
	DS = registry.DataService
	alice = makePlayer(101, "Alice")
	local profile = DS.getProfile(alice)
	assert(profile and profile.Coins == 150, "starting coins")
	local stats = alice:FindFirstChild("leaderstats")
	assert(stats and stats.Wins and stats.Coins.Value == 150 and stats.Streak, "leaderstats")
	assert(alice:GetAttribute("RR_Status") == "Lobby" and registry.MatchService.isReady(alice))
	assert(lastSent("Profile", alice), "profile not sent")
	assert(lastSent("Notify", alice), "should warn that saving is unavailable")
end)

check("profile migration v1 -> current keeps data and fills defaults", function()
	local old = { Version = 1, Coins = 999, Equipped = "Slugger", Abilities = { "Dash", "Swap" }, Loadout = { "Swap", "Bogus" }, Stats = { Wins = 4 } }
	local data = DS.reconcile(old)
	assert(data.Coins == 999 and data.Stats.Wins == 4 and data.Stats.Kills == 0)
	assert(data.Equipped.ParryFx == "Slugger" and data.Equipped.Trail == "Basic", "equipped migration")
	assert(data.Abilities.Swap and data.Abilities.Dash, "abilities migration")
	assert(#data.Loadout == 1 and data.Loadout[1] == "Swap", "loadout not cleaned")
	assert(data.Owned.ParryFx.Blade and data.Version == 2)
end)

check("Robux receipt processed twice is granted once; unknown player retried", function()
	local profile = DS.getProfile(alice)
	local before = profile.Coins
	local receipt = { PlayerId = 101, ProductId = 111, PurchaseId = "abc-1" }
	local Enum = roblox.Enum
	assert(registry.ShopService.processReceipt(receipt) == Enum.ProductPurchaseDecision.PurchaseGranted)
	assert(registry.ShopService.processReceipt(receipt) == Enum.ProductPurchaseDecision.PurchaseGranted)
	assert(profile.Coins == before + 500, "granted " .. (profile.Coins - before))
	assert(registry.ShopService.processReceipt({ PlayerId = 999, ProductId = 111, PurchaseId = "x" }) == Enum.ProductPurchaseDecision.NotProcessedYet)
	assert(registry.ShopService.processReceipt({ PlayerId = 101, ProductId = 5555, PurchaseId = "y" }) == Enum.ProductPurchaseDecision.NotProcessedYet)
	-- Server Explosion Party.
	assert(registry.ShopService.processReceipt({ PlayerId = 101, ProductId = 222, PurchaseId = "party-1" }) == Enum.ProductPurchaseDecision.PurchaseGranted)
	assert((workspaceService:GetAttribute("RR_PartyUntil") or 0) > simTime + 500, "party not started")
	assert(#sent("Announce", "all") >= 1, "party not announced")
	-- Product with a real id prompts instead of granting.
	fire("ShopBuy", alice, "Coins500")
	assert(prompts[#prompts] and prompts[#prompts].id == 111, "should prompt purchase")
end)

check("live game without DataStores: receipts are retried, not granted", function()
	local profile = DS.getProfile(alice)
	local before = profile.Coins
	local Enum = roblox.Enum
	harnessIsStudio = false
	local ok, decision = pcall(registry.ShopService.processReceipt, { PlayerId = 101, ProductId = 111, PurchaseId = "live-1" })
	harnessIsStudio = true
	assert(ok, decision)
	assert(decision == Enum.ProductPurchaseDecision.NotProcessedYet, "granted a purchase that cannot be saved")
	assert(profile.Coins == before and profile.Receipts["live-1"] == nil, "profile changed")
end)

check("Studio: id-0 products and passes are granted for free", function()
	local profile = DS.getProfile(alice)
	simTime += 2
	task.wait(1.05) -- the shop rate limit uses real os.clock time
	fire("ShopBuy", alice, "Spin1")
	assert(profile.PremiumSpins == 1, "spin not granted")
	for _, key in ipairs({ "VIP", "DoubleCoins", "ExtraSlot", "PrismTrail" }) do
		registry.ShopService._grantPass(alice, key)
	end
	assert(registry.ShopService.coinMultiplier(alice) == 2.5, "multiplier")
	assert(profile.Owned.Trail.Prism, "prism not unlocked by pass")
	assert(registry.AbilityService.maxSlots(alice) == 2)
	fire("ShopBuy", alice, 12345)
	fire("ShopBuy", alice, "NotAProduct")
	fire("BuyPass", alice, { "bad" })
end)

check("abilities: buy with coins, equip two slots, lobby-only", function()
	local profile = DS.getProfile(alice)
	profile.Coins = 100
	local ok = registry.AbilityService.buy(alice, "Freeze")
	assert(not ok, "bought without coins")
	profile.Coins = 10000
	assert(registry.AbilityService.buy(alice, "Freeze"))
	assert(registry.AbilityService.buy(alice, "Swap"))
	assert(not registry.AbilityService.buy(alice, "Freeze"), "bought twice")
	assert(registry.AbilityService.equip(alice, 1, "Swap"))
	assert(registry.AbilityService.equip(alice, 2, "Freeze"))
	assert(profile.Loadout[1] == "Swap" and profile.Loadout[2] == "Freeze", "loadout " .. table.concat(profile.Loadout, ","))
	assert(registry.AbilityService.equip(alice, 1, "Freeze"))
	assert(profile.Loadout[1] == "Freeze" and profile.Loadout[2] == "Swap", "swap slots " .. table.concat(profile.Loadout, ","))
	assert(not registry.AbilityService.equip(alice, 3, "Dash"), "slot 3")
	assert(not registry.AbilityService.equip(alice, 0 / 0, "Dash"), "NaN slot")
	assert(not registry.AbilityService.buy(alice, "Nope"))
	fire("EquipAbility", alice, "1", {})
	fire("UseAbility", alice, 0 / 0, Vector3.new(0 / 0, 0, 0))
	fire("UseAbility", alice, 1, "x")
end)

check("crates: coin crate, premium spin, pity, duplicates refund, equip", function()
	local profile = DS.getProfile(alice)
	profile.Coins = 5000
	local result = registry.CosmeticService.open(alice, "Basic")
	assert(result and result.itemId and #result.reel == 25 and result.reel[25] == result.itemId, "basic crate")
	assert(profile.Coins == 5000 - 400 + result.refund, "crate price")
	local spin = registry.CosmeticService.open(alice, "Premium")
	assert(spin and spin.rarity ~= "Common", "premium spin")
	assert(profile.PremiumSpins == 0)
	assert(not registry.CosmeticService.open(alice, "Premium"), "spin without spins")
	assert(not registry.CosmeticService.open(alice, "Nope"))
	profile.Coins = 0
	assert(not registry.CosmeticService.open(alice, "Elite"), "opened without coins")
	-- Duplicates refund.
	profile.Coins = 100000
	local refunds = 0
	for _ = 1, 30 do
		local r = registry.CosmeticService.open(alice, "Basic")
		if r.duplicate then
			refunds += 1
			assert(r.refund > 0)
		end
	end
	assert(refunds > 0, "30 crates and no duplicate?")
	assert(profile.Stats.CratesOpened == 32)
	assert(registry.CosmeticService.equip(alice, "Trail", "Prism"), "equip prism")
	assert(not registry.CosmeticService.equip(alice, "Trail", "Galaxy") or profile.Owned.Trail.Galaxy, "equipped unowned")
	assert(not registry.CosmeticService.equip(alice, "ParryFx", "Prism"), "wrong category")
	fire("OpenCrate", alice, nil)
	fire("EquipCosmetic", alice, 5, 6)
end)

check("codes, daily reward and invite bonus are one-time", function()
	local profile = DS.getProfile(alice)
	local coins = profile.Coins
	local ok, msg = registry.RewardService.redeem(alice, " release ")
	assert(ok, msg)
	assert(profile.Coins == coins + 300)
	assert(not registry.RewardService.redeem(alice, "RELEASE"), "redeemed twice")
	assert(not registry.RewardService.redeem(alice, nil))
	local ok2, amount = registry.RewardService.claimDaily(alice)
	assert(ok2 and amount == 100, "daily")
	assert(not registry.RewardService.claimDaily(alice), "daily twice")
	local before = profile.Coins
	fire("InviteSent", alice)
	fire("InviteSent", alice)
	assert(profile.Coins == before + 50, "invite bonus not bounded")
	fire("SaveSettings", alice, { Music = 0 / 0, Sfx = 5, Shake = "yes", AutoReady = false })
	assert(profile.Settings.Music == 0.5 and profile.Settings.Sfx == 1 and profile.Settings.Shake == true and profile.Settings.AutoReady == false, "settings sanitising")
end)

check("junk parry arguments are ignored", function()
	fire("Parry", alice, "now", Vector3.new(1, 0, 0))
	fire("Parry", alice, 0 / 0, Vector3.new(0 / 0, 0, 0))
	fire("Parry", alice, math.huge, Vector3.new(1e9, 0, 0))
	fire("Parry", alice, 1, nil)
	fire("Parry", alice, 1, Vector3.zero)
	fire("SetReady", alice, "maybe")
end)

local function step(seconds, onStep)
	local dt = 1 / 30
	for _ = 1, math.floor(seconds / dt) do
		simTime += dt
		registry.BallService.step(dt)
		registry.BotService.step(dt)
		if onStep and onStep() then
			return true
		end
		if registry.MatchService.state() ~= "Playing" then
			return false
		end
	end
	return false
end

local function runDelayed()
	local list = table.clone(delayed)
	table.clear(delayed)
	for _, d in ipairs(list) do
		d.fn(table.unpack(d.args))
	end
	-- Time passed (results screen > Players.RespawnTime): dead characters have respawned.
	for _, p in ipairs(playerList) do
		local humanoid = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then
			humanoid.Health = humanoid.MaxHealth
		end
	end
end

check("lobby countdown starts with one ready player (solo vs bots)", function()
	local MS = registry.MatchService
	assert(MS.state() == "Lobby")
	MS.tickLobby()
	assert(MS.state() == "Countdown", "countdown did not start: " .. MS.state())
	MS.setReady(alice, false)
	MS.tickLobby()
	assert(MS.state() == "Lobby", "countdown should cancel when nobody is ready")
	MS.setReady(alice, true)
	MS.tickLobby()
	for _ = 1, 20 do
		if MS.state() ~= "Countdown" then
			break
		end
		MS.tickLobby()
	end
	assert(MS.state() == "Playing", "round did not start: " .. MS.state())
	MS.endRound(nil)
	runDelayed()
	assert(MS.state() == "Lobby" and not workspaceService:FindFirstChild("Arena"), "did not return to lobby")
end)

check("solo round vs bots: parry, whiff, freeze, swap, eliminations, winner, rewards", function()
	local MS, BS = registry.MatchService, registry.BallService
	local profile = DS.getProfile(alice)
	local coinsBefore = profile.Coins
	local roundsBefore = profile.Stats.Rounds
	table.clear(log)
	assert(MS.startMatch({ theme = "Volcano", seed = 3 }), "match did not start")
	assert(#MS.contestants() == 5, "expected 1 human + 4 bots, got " .. #MS.contestants())
	local botCount = 0
	for _, c in ipairs(MS.contestants()) do
		if c.isBot then
			botCount += 1
			assert(c.model.Parent and c.model.Humanoid.DisplayName:sub(1, 5) == "[BOT]", "bot not labelled")
		end
	end
	assert(botCount == 4)
	assert(alice:GetAttribute("RR_Status") == "Arena")
	assert(workspaceService:FindFirstChild("Arena"), "arena missing")
	local me = MS.forPlayer(alice)

	-- An early press while not targeted is a whiff with the long cooldown.
	fire("Parry", alice, simTime, Vector3.new(1, 0, 0))
	local res = lastSent("ParryResult", alice)
	assert(res and res.args[1] == false, "expected whiff")

	local parried, froze, swapped = false, false, false
	local function onStep()
		local ball = BS.current()
		if not ball then
			return false
		end
		if ball.targetId == me.id and ball.phase == "chasing" and me.alive then
			local d = BS.distanceTo(me)
			if not froze and d and d < 60 and (me.parryMemo.readyAt or 0) < simTime then
				-- Freeze (slot 1) slows the ball while it hunts me.
				froze = registry.AbilityService.use(alice, 1, nil)
				assert(froze, "freeze failed while targeted")
				assert(BS.current().slowUntil > simTime, "ball not slowed")
			end
			local range = requireModule(Shared.BallMath).parryRange(ball.state.speed, requireModule(Shared.Config.GameConfig).Parry)
			if not parried and d and d <= range * 0.6 and (me.parryMemo.readyAt or 0) < simTime then
				-- Aim at a bot.
				local target
				for _, c in ipairs(MS.alive()) do
					if c.isBot then
						target = MS.positionOf(c)
						break
					end
				end
				local aim = (target - MS.positionOf(me)).Unit
				fire("Parry", alice, simTime - 0.05, aim)
				local r = lastSent("ParryResult", alice)
				assert(r.args[1] == true, "timed parry failed: " .. tostring(r.args[2]))
				parried = true
				assert(BS.current().lastDeflector == me.id and BS.current().targetId ~= me.id, "ball not deflected")
			end
		end
		if not swapped and me.alive and BS.current().targetId ~= me.id then
			local before = MS.positionOf(me)
			if registry.AbilityService.use(alice, 2, nil) then
				swapped = true
				assert((MS.positionOf(me) - before).Magnitude > 1, "swap did not move me")
			end
		end
		return false
	end
	local finished = not step(900, onStep) and MS.state() == "Results"
	assert(finished, "round never ended: " .. MS.state())
	assert(parried, "never got a chance to parry")
	assert(swapped, "swap never used")
	local feed = sent("KillFeed", "all")
	assert(#feed >= 4, "expected >=4 kill feed entries, got " .. #feed)
	assert(#sent("Fx", "all", function(kind)
		return kind == "Explode"
	end) >= 4, "no explosions")
	-- The Explosion Party is active: explosions are confetti.
	local explode = sent("Fx", "all", function(kind)
		return kind == "Explode"
	end)[1]
	assert(explode.args[2].confetti == true, "party explosions should be confetti")
	assert(#sent("Fx", "all", function(kind)
		return kind == "Freeze"
	end) == 1, "freeze fx")
	local results = lastSent("Results", alice)
	assert(results and results.args[1].reward and results.args[1].ranked == false, "results")
	assert(profile.Stats.Rounds == roundsBefore + 1, "rounds stat")
	assert(profile.Stats.Wins == 0, "practice wins must not count for the leaderboard")
	assert(profile.Coins > coinsBefore, "no coins earned")
	assert(profile.Stats.Parries >= 1)
	print(string.format("        round: %d feed entries, winner %s, coins +%d", #feed, tostring(results.args[1].winner), profile.Coins - coinsBefore))
	runDelayed()
	assert(MS.state() == "Lobby" and alice:GetAttribute("RR_Status") == "Lobby" and registry.BotService.count() == 0, "cleanup")
	assert(not workspaceService:FindFirstChild("Arena"), "arena not destroyed")
end)

check("ranked 2-player round: shield save, leaver, streak bookkeeping", function()
	local MS, BS = registry.MatchService, registry.BallService
	workspaceService:SetAttribute("RR_PartyUntil", nil)
	bob = makePlayer(202, "Bob")
	local bobProfile = DS.getProfile(bob)
	bobProfile.Abilities.Shield = true
	bobProfile.Loadout = { "Shield" }
	table.clear(log)
	assert(MS.startMatch({ theme = "NeonGrid", seed = 9, bots = 1 }), "match did not start")
	assert(#MS.contestants() == 3)
	local bobC = MS.forPlayer(bob)
	assert(bobC.shieldReady, "shield not armed")
	-- Wait for the ball to launch, then force it onto Bob.
	step(1.7)
	local ball = BS.current()
	assert(ball and ball.phase == "chasing", "ball not chasing")
	ball.targetId = bobC.id
	local popped = step(30, function()
		return #sent("Fx", "all", function(kind)
			return kind == "ShieldPop"
		end) > 0
	end)
	assert(popped, "shield never popped")
	assert(bobC.alive and not bobC.shieldReady, "shield should save Bob once")
	-- Bob leaves mid-round.
	removePlayer(bob)
	assert(not bobC.alive, "leaver still alive")
	local finished = not step(900) and MS.state() == "Results"
	assert(finished, "round never ended")
	local results = lastSent("Results", alice)
	assert(results.args[1].ranked == true, "2 humans should be ranked")
	local profile = DS.getProfile(alice)
	if results.args[1].won then
		assert(profile.Stats.Wins == 1 and profile.WinStreak == 1, "win bookkeeping")
	else
		assert(profile.WinStreak == 0, "streak should reset on a ranked loss")
	end
	runDelayed()
	assert(MS.state() == "Lobby")
end)

check("bot rig: welded R15 humanoid that honours HipHeight and has a root part", function()
	local model, root, humanoid = registry.BotService.buildModel("Rig", roblox.Color3.new(1, 1, 1), CFrame.new(0, 3, 0))
	assert(root.Name == "HumanoidRootPart" and model.PrimaryPart == root and not root.Anchored)
	assert(humanoid.RigType == roblox.Enum.HumanoidRigType.R15 and humanoid.HipHeight == 2, "HipHeight ignored by R6")
	assert(humanoid.RequiresNeck == false, "welded rig has no Neck joint")
	model:Destroy()
end)

check("a dead (respawning) player is not put into the next round", function()
	local MS = registry.MatchService
	local humanoid = alice.Character:FindFirstChildOfClass("Humanoid")
	humanoid.Health = 0
	assert(MS.startMatch({ theme = "FrostRing", seed = 4 }) == false, "dead character joined the round")
	assert(MS.state() == "Lobby" and alice:GetAttribute("RR_Status") == "Lobby")
	humanoid.Health = 100
end)

check("eliminated players respawn into the lobby as spectators until the round ends", function()
	local MS = registry.MatchService
	assert(MS.startMatch({ theme = "FrostRing", seed = 5 }))
	local me = MS.forPlayer(alice)
	MS.eliminate(me, nil, "reset")
	assert(alice:GetAttribute("RR_Status") == "Out", "eliminated player should be Out")
	assert(MS.state() == "Playing", "bots should keep playing")
	step(900)
	assert(MS.state() == "Results")
	runDelayed()
	assert(alice:GetAttribute("RR_Status") == "Lobby")
end)

---------------------------------------------------------------------------------------------
-- Client UI
---------------------------------------------------------------------------------------------

check("client controllers initialise and render real server payloads", function()
	local profilePayload = lastSent("Profile", alice).args[1]
	local resultsPayload = lastSent("Results", alice).args[1]
	local crate = registry.CosmeticService.open(alice, "Basic")

	requireModule(Shared.Net).setup()
	local localPlayer = roblox.Instance.new("Player")
	localPlayer.Name = "Tester"
	localPlayer.DisplayName = "Tester"
	localPlayer.UserId = 101
	roblox.Instance.new("PlayerGui").Parent = localPlayer
	localPlayer:SetAttribute("RR_Status", "Lobby")
	local character = registry.BotService.buildModel("Tester", roblox.Color3.new(1, 1, 1), CFrame.new(0, 3, 0))
	character.Parent = workspaceService
	localPlayer.Character = character
	table.clear(playerList)
	table.insert(playerList, localPlayer)
	fakePlayers.LocalPlayer = localPlayer
	stubServices.RunService.IsServer = function()
		return false
	end
	local camera = roblox.Instance.new("Camera")
	camera.CFrame = CFrame.new(0, 10, 20)
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	camera.Parent = workspaceService
	workspaceService.CurrentCamera = camera

	local folder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("ReboundRumbleClient"):FindFirstChild("Controllers")
	local controllers = {}
	for _, name in ipairs({ "ClientState", "InputController", "BallController", "EffectsController", "HudController", "MenuController", "SpectateController", "LightingController" }) do
		controllers[name] = requireModule(folder[name])
		controllers[name].init()
	end
	local CS = controllers.ClientState
	local roster = {
		{ id = "p101", name = "Tester", isBot = false, userId = 101, alive = true, kills = 1, vip = true, trail = "Prism" },
		{ id = "b1", name = "Volt", isBot = true, alive = true, kills = 0 },
	}
	CS.roster = roster
	CS.RosterChanged:Fire(roster)
	CS.profile = profilePayload
	CS.ProfileChanged:Fire(profilePayload)
	CS.GoalsChanged:Fire(registry.RewardService.goalsSnapshot(alice))
	CS.MatchChanged:Fire("Countdown", { countdown = 3, readyCount = 1 })
	localPlayer:SetAttribute("RR_Status", "Arena")
	CS.matchState = "Playing"
	CS.MatchChanged:Fire("Playing", { alive = 2, total = 2, round = 1, arenaName = "Neon Grid", theme = "NeonGrid" })
	workspaceService:SetAttribute("RR_Theme", "NeonGrid")
	controllers.LightingController.update()
	CS.ball = { active = true, p = Vector3.new(0, 20, 0), d = Vector3.new(0, -1, 0), s = 120, c = 0, t = "p101", ph = "chasing", st = simTime, slow = 1, trail = "Prism" }
	CS.BallSynced:Fire(CS.ball)
	CS.BallEvent:Fire("target", { id = "p101", speed = 120 })
	for _ = 1, 5 do
		stubServices.RunService.RenderStepped:Fire(1 / 60)
	end
	assert(controllers.BallController.active(), "ball not rendered")
	assert(workspaceService:FindFirstChild("RR_BallVisual"), "ball visual missing")
	controllers.InputController.parry()
	CS.ParryResult:Fire(true, "parry", 0.25)
	CS.ParryResult:Fire(false, "early", 0.9)
	CS.BallEvent:Fire("deflect", { by = "p101", to = "b1", speed = 130, trail = "Galaxy", pos = Vector3.new(0, 5, 0) })
	CS.AbilityFx:Fire("Cooldown", { slot = 1, id = "Freeze", cooldown = 30 })
	CS.AbilityFx:Fire("Dash", { dir = Vector3.new(1, 0, 0), power = 95, duration = 0.18 })
	CS.AbilityFx:Fire("SuperJump", { power = 115 })
	CS.Fx:Fire("Swing", { id = "b1", ok = true, item = "Reaper" })
	CS.Fx:Fire("Swing", { id = "p101", ok = true, item = "Solar" })
	for _, item in ipairs({ "Blade", "Slugger", "Moonlit", "Thunder" }) do
		controllers.EffectsController.swing("p101", item, false)
	end
	CS.Fx:Fire("Explode", { pos = Vector3.new(1, 2, 3), victim = "b1", color = { 255, 0, 0 }, rainbow = true })
	CS.Fx:Fire("Explode", { pos = Vector3.new(1, 2, 3), victim = "p101", confetti = true })
	CS.Fx:Fire("Freeze", { id = "p101", duration = 1 })
	CS.Fx:Fire("ShieldPop", { id = "p101", pos = Vector3.new(0, 3, 0) })
	CS.Fx:Fire("Swap", { a = Vector3.new(0, 3, 0), b = Vector3.new(10, 3, 0) })
	CS.Fx:Fire("Dash", { userId = 101 })
	CS.Fx:Fire("Win", { id = "p101", pos = Vector3.new(0, 3, 0) })
	for _ = 1, 5 do
		stubServices.RunService.RenderStepped:Fire(1 / 60)
	end
	CS.KillFeed:Fire({ killer = "Tester", victim = "Volt", victimBot = true, cause = "ball", speed = 140 })
	CS.KillFeed:Fire({ victim = "Volt", cause = "shield" })
	CS.KillFeed:Fire({ victim = "Volt", cause = "fell" })
	CS.Announce:Fire("Tester - DOUBLE DEFLECT!", "streak")
	CS.Announce:Fire("Tester unboxed MYTHIC Solar Edge!", "Mythic")
	CS.Notified:Fire("Hello", "good")
	CS.Results:Fire(resultsPayload)
	-- Spectating after elimination.
	localPlayer:SetAttribute("RR_Status", "Out")
	controllers.SpectateController.setActive(true)
	controllers.SpectateController.cycle(1)
	assert(controllers.SpectateController.active, "spectate should be active while Out during a round")
	-- Every menu panel renders.
	localPlayer:SetAttribute("RR_Status", "Lobby")
	for _, key in ipairs({ "Shop", "Crates", "Abilities", "Locker", "Daily", "Codes", "Settings" }) do
		controllers.MenuController.open(key)
		assert(controllers.MenuController.isOpen(key))
	end
	controllers.MenuController.open("Locker")
	controllers.MenuController.close()
	CS.CrateResult:Fire(crate)
	CS.CodeResult:Fire(true, "Code redeemed")
	CS.matchState = "Lobby"
	CS.MatchChanged:Fire("Lobby", {})
	controllers.SpectateController.refresh()
	assert(not controllers.SpectateController.active, "spectate should stop after the round")
	local pg = localPlayer:FindFirstChild("PlayerGui")
	assert(pg:FindFirstChild("RR_HUD") and pg:FindFirstChild("RR_Menu") and pg:FindFirstChild("RR_Spectate"), "GUIs missing")
end)

if handlerErrors > 0 then
	failed += 1
	print(string.format("  FAIL  %d errors were swallowed by signal handlers / controller init", handlerErrors))
end
print(string.format("\nharness: %d passed, %d failed", passed, failed))
process.exit(if failed > 0 then 1 else 0)
