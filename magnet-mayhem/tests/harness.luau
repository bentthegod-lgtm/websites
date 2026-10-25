--[[
	Headless smoke harness for MAGNET MAYHEM.

	Loads the Rojo-built place in Lune and runs the REAL game modules against Lune's Roblox
	instance implementation (class / property / enum names are checked against the
	reflection database). Engine services Lune does not simulate (players, data stores,
	marketplace, tweens, input, physics, rendering) are stubbed, and time is a fake clock
	the tests advance.

	Covers: spawn -> magnet on -> server claim -> flight -> award once -> pile grows ->
	sell once (duplicate prompt / touch pays nothing) -> upgrade (price + stats) -> tier ->
	zone unlock + enforcement -> codex / achievement / quest once-only -> pulse cooldown ->
	two players racing for one object -> leave mid-flight -> prestige -> daily reset ->
	storm reward -> receipt idempotency -> session lock -> every client controller.

	Usage (from magnet-mayhem/):
	  rojo build -o build/MagnetMayhem.rbxlx && lune run tests/harness build/MagnetMayhem.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/MagnetMayhem.rbxlx"
local place = roblox.deserializePlace(fs.readFile(placePath))

---------------------------------------------------------------------------------------------
-- Fake clock
---------------------------------------------------------------------------------------------

local clock = 1000
local unixOffset = 1800000000
local function advance(seconds)
	clock += seconds
end
local fakeOs = {
	clock = function()
		return clock
	end,
	time = function()
		return math.floor(unixOffset + clock)
	end,
	date = os.date,
}

---------------------------------------------------------------------------------------------
-- Stubs
---------------------------------------------------------------------------------------------

local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return {
			Disconnect = function()
				local i = table.find(self.handlers, fn)
				if i then
					table.remove(self.handlers, i)
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

local SIGNAL_SUFFIXES = { "Added$", "Removing$", "Finished$", "Began$", "Ended$", "Changed$", "Released$", "Focused$", "^Heartbeat$", "^Stepped$", "^RenderStepped$" }
local function stubObject(name, extra)
	local obj = extra or {}
	return setmetatable(obj, {
		__index = function(_, key)
			for _, pattern in ipairs(SIGNAL_SUFFIXES) do
				if string.match(key, pattern) then
					local s = signal()
					rawset(obj, key, s)
					return s
				end
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
local analytics = {}
local isStudio = true
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
			return isStudio
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
	AnalyticsService = stubObject("AnalyticsService", {
		LogOnboardingFunnelStepEvent = function(_, player, step, name)
			table.insert(analytics, { player = player, step = step, name = name })
		end,
		LogCustomEvent = function() end,
	}),
	UserInputService = stubObject("UserInputService", { TouchEnabled = true, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false }),
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
		elseif key == "JobId" then
			return "harness-job"
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
roblox.implementMethod("Model", "GetPivot", function(self)
	if self.PrimaryPart then
		return self.PrimaryPart.CFrame
	end
	local first = self:FindFirstChildWhichIsA("BasePart", true)
	return if first then first.CFrame else roblox.CFrame.new()
end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	local pivot = if self.PrimaryPart then self.PrimaryPart.CFrame else roblox.CFrame.new()
	local delta = cf * pivot:Inverse()
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)
-- Lune keeps Position and CFrame separate; in Roblox Position is derived from CFrame.
-- syncPositions() copies CFrame.Position into Position for everything under a root.
local function syncPositions(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Position = d.CFrame.Position
		end
	end
end
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return unixOffset + clock
end)
local bulkMoves = 0
roblox.implementMethod("Workspace", "BulkMoveTo", function(_, parts, cframes)
	assert(#parts == #cframes, "BulkMoveTo size mismatch")
	for i, part in ipairs(parts) do
		part.CFrame = cframes[i]
	end
	bulkMoves += #parts
end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)

local eventStore = {}
local function keyOf(instance)
	local id = instance:GetAttribute("__harnessId")
	if not id then
		id = tostring(math.random(1, 2 ^ 30)) .. tostring(clock)
		instance:SetAttribute("__harnessId", id)
	end
	return id
end
local function fakeEvent(className, eventName)
	roblox.implementProperty(className, eventName, function(self)
		local k = keyOf(self)
		eventStore[k] = eventStore[k] or {}
		eventStore[k][eventName] = eventStore[k][eventName] or signal()
		return eventStore[k][eventName]
	end)
end
for _, e in ipairs({ "Triggered", "PromptButtonHoldBegan", "PromptButtonHoldEnded" }) do
	fakeEvent("ProximityPrompt", e)
end
fakeEvent("Player", "CharacterAdded")
fakeEvent("Humanoid", "Died")
fakeEvent("RemoteEvent", "OnClientEvent")
fakeEvent("RemoteEvent", "OnServerEvent")
for _, cls in ipairs({ "TextButton", "Frame", "TextLabel", "ImageButton", "TextBox" }) do
	for _, e in ipairs({ "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" }) do
		fakeEvent(cls, e)
	end
end
fakeEvent("TextButton", "Activated")
fakeEvent("TextBox", "FocusLost")
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function()
	return signal()
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
local deferred = {}
-- Background loops park on their first wait; deferred work runs when the test flushes.
trackedTask.wait = function()
	coroutine.yield()
end
trackedTask.defer = function(fn, ...)
	table.insert(deferred, { fn = fn, args = table.pack(...) })
end
trackedTask.delay = function(_seconds, fn, ...)
	table.insert(deferred, { fn = fn, args = table.pack(...) })
end
local function flushDeferred()
	for _ = 1, 5 do
		local list = deferred
		deferred = {}
		for _, d in ipairs(list) do
			local co = coroutine.create(d.fn)
			local ok, err = coroutine.resume(co, table.unpack(d.args, 1, d.args.n))
			if not ok then
				error("deferred task failed: " .. tostring(err))
			end
		end
		if #deferred == 0 then
			return
		end
	end
end

local handlerErrors = 0
local warnings = {}

local function requireModule(moduleScript)
	if cache[moduleScript] ~= nil then
		return cache[moduleScript]
	end
	local e = table.clone(env)
	e.script = moduleScript
	local chunk = luau.load(moduleScript.Source, { debugName = moduleScript:GetFullName(), environment = e })
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

local Rng = luau.load(fs.readFile("src/shared/Rng.lua"))()
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
	TweenInfo = stubCtor("TweenInfo"),
	Random = RandomShim,
	task = trackedTask,
	os = fakeOs,
	typeof = typeof,
	print = function() end,
	warn = function(...)
		local message = table.concat({ ... }, " ")
		table.insert(warnings, message)
		if string.find(message, "error", 1, true) or string.find(message, "Failed to start", 1, true) or string.find(message, "failed", 1, true) then
			handlerErrors += 1
			print("[warn]", message)
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
local Shared = RS:FindFirstChild("MagnetMayhem")
local ServerRoot = SSS:FindFirstChild("MagnetMayhemServer")
local Services = ServerRoot:FindFirstChild("Services")

local ScrapConfig = requireModule(Shared.Config.ScrapConfig)
local ShopConfig = requireModule(Shared.Config.ShopConfig)
local EconomyConfig = requireModule(Shared.Config.EconomyConfig)
local MagnetConfig = requireModule(Shared.Config.MagnetConfig)
local ZoneConfig = requireModule(Shared.Config.ZoneConfig)
local QuestConfig = requireModule(Shared.Config.QuestConfig)
local EventConfig = requireModule(Shared.Config.EventConfig)
local Economy = requireModule(Shared.Economy)

-- A real product id so ProcessReceipt can be exercised (config tables are plain tables).
ShopConfig.Products[1].ProductId = 4242

check("all server modules load", function()
	for _, m in ipairs(Services:GetChildren()) do
		requireModule(m)
	end
	requireModule(ServerRoot.World.WorldBuilder)
end)

check("every scrap model builds (world and pile scale) without blocking anything", function()
	local ScrapModels = requireModule(Shared.ScrapModels)
	local maxParts = 0
	for _, def in ipairs(ScrapConfig.List) do
		for _, scale in ipairs({ 1, 0.4 }) do
			local cf = roblox.CFrame.new(10, 2, 10)
			local model = ScrapModels.build(def.Id, cf, scale)
			assert(model.PrimaryPart and model.PrimaryPart.Name == "Root", def.Id .. " root")
			local parts = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					parts += 1
					assert(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, def.Id .. "." .. d.Name .. " would block players or raycasts")
					local offset = cf:PointToObjectSpace(d.CFrame.Position)
					assert(offset.Magnitude <= def.Size * scale * 1.6 + 0.5, def.Id .. "." .. d.Name .. " sticks far out")
				end
			end
			assert(parts >= 4, def.Id .. " only has " .. parts .. " parts")
			maxParts = math.max(maxParts, parts)
			local list, offsets = ScrapModels.partsAndOffsets(model)
			assert(#list == parts and #offsets == parts)
		end
	end
	assert(maxParts <= 30, "a scrap model uses " .. maxParts .. " parts")
end)

check("magnet rig builds for every tier and skin, welded, massless and non-colliding", function()
	local MagnetModel = requireModule(Shared.MagnetModel)
	local lastCoils = 0
	for tier = 1, #MagnetConfig.Tiers do
		for _, skin in ipairs(MagnetConfig.SkinOrder) do
			local rig, parts = MagnetModel.build(tier, skin, roblox.CFrame.new())
			assert(parts.mount and parts.core and parts.emitter and parts.glow, "rig parts missing")
			for _, d in ipairs(rig:GetDescendants()) do
				if d:IsA("BasePart") then
					assert(d.Massless and not d.CanCollide and not d.Anchored, d.Name .. " would affect movement")
					if d ~= parts.mount then
						local weld = d:FindFirstChildOfClass("WeldConstraint")
						assert(weld and weld.Part0 == parts.mount, d.Name .. " not welded")
					end
				end
			end
			if skin == "Default" then
				assert(#parts.coils >= lastCoils, "higher tiers should not lose coils")
				lastCoils = #parts.coils
			end
		end
	end
end)

local world
check("world builds: Rustyard + gate + Metro Wreck, regions inside zones, part budget", function()
	local WorldBuilder = requireModule(ServerRoot.World.WorldBuilder)
	world = WorldBuilder.build()
	syncPositions(world.folder)
	assert(world.spawn:IsA("SpawnLocation"), "no spawn")
	assert(world.sellPad and world.sellPrompt:IsA("ProximityPrompt"), "no sell pad / prompt")
	assert(world.stationPrompt:IsA("ProximityPrompt"), "no upgrade station prompt")
	assert(world.gate.barrier and world.gate.prompt and world.gate.zoneId == "MetroWreck")
	assert(#world.boards.value.rows == 10 and #world.boards.rare.rows == 10)
	assert(#world.blockers > 20, "too few spawn blockers")
	assert(world.partCount < 5000, "world part count " .. world.partCount)
	for zoneId, regions in pairs(world.regions) do
		local zone = ZoneConfig.ById[zoneId]
		for _, r in ipairs(regions) do
			for _, corner in ipairs({ { -1, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 } }) do
				local x, z = r.cx + corner[1] * r.w / 2, r.cz + corner[2] * r.h / 2
				assert(ZoneConfig.zoneAt(x, z) == zone.Id, zoneId .. " region leaks out of its zone at " .. x .. "," .. z)
			end
		end
	end
	-- The spawn is in Rustyard and next to commons.
	assert(ZoneConfig.zoneAt(world.spawn.Position.X, world.spawn.Position.Z) == "Rustyard")
	print("        world parts: " .. world.partCount)
end)

-- Remote stubs that record traffic.
local log = {}
local logSeq = 0 -- global send order across remotes
local function stubRemote(name)
	log[name] = {}
	return {
		FireAllClients = function(_, ...)
			logSeq += 1
			table.insert(log[name], { all = true, args = table.pack(...), seq = logSeq })
		end,
		FireClient = function(_, player, ...)
			logSeq += 1
			table.insert(log[name], { player = player, args = table.pack(...), seq = logSeq })
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
local function count(name, pattern, player)
	local n = 0
	for _, entry in ipairs(log[name] or {}) do
		if (not player or entry.player == player or entry.all) and (not pattern or string.find(tostring(entry.args[1]), pattern, 1, true)) then
			n += 1
		end
	end
	return n
end
local function lastFor(name, player)
	local list = log[name] or {}
	for i = #list, 1, -1 do
		if list[i].player == player then
			return list[i]
		end
	end
	return nil
end

local registry
local ORDER = { "Analytics", "DataService", "UpgradeService", "ScrapService", "MagnetService", "EconomyService", "ZoneService", "QuestService", "EventService", "ShopService", "PlayerService", "LeaderboardService" }
check("services initialise and start (same order as Main.server)", function()
	registry = { Remotes = remotes }
	for _, name in ipairs(ORDER) do
		registry[name] = requireModule(Services[name])
	end
	for _, name in ipairs(ORDER) do
		registry[name].init(registry)
	end
	for _, name in ipairs({ "ScrapService", "EconomyService", "ZoneService", "PlayerService", "LeaderboardService" }) do
		registry[name].setWorld(world)
	end
	for _, name in ipairs({ "ScrapService", "MagnetService", "EconomyService", "ZoneService", "QuestService", "EventService", "ShopService", "UpgradeService", "PlayerService", "LeaderboardService" }) do
		registry[name].start()
	end
	registry.DataService.start()
	assert(type(stubServices.MarketplaceService.ProcessReceipt) == "function", "ProcessReceipt not bound")
	local rusty = registry.ScrapService.count("Rustyard")
	assert(rusty >= ZoneConfig.ById.Rustyard.MaxScrap * 0.9, "Rustyard only has " .. rusty .. " scrap at start")
	assert(registry.ScrapService.count("MetroWreck") > 50, "Metro Wreck not stocked")
	-- Nothing spawned inside a blocker.
	for _, item in pairs(registry.ScrapService.all()) do
		for _, b in ipairs(world.blockers) do
			local dx, dz = item.position.X - b.x, item.position.Z - b.z
			assert(dx * dx + dz * dz >= b.r * b.r, item.def.Id .. " spawned inside a blocker")
		end
		assert(not item.def.StormOnly, "storm shard outside a storm")
	end
	-- Commons right by the spawn so the first pull is instant.
	local near = registry.ScrapService.query(world.spawn.Position, 40)
	assert(#near >= 5, "only " .. #near .. " scrap within 40 studs of spawn")
end)

local nextUserId = 1000
local function makePlayer(name, position)
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
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.CFrame = roblox.CFrame.new(position or roblox.Vector3.new(0, 3, 40))
	root.Position = root.CFrame.Position
	root.Parent = character
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = workspaceService
	player.Character = character
	table.insert(playerList, player)
	fakePlayers.PlayerAdded:Fire(player)
	player.CharacterAdded:Fire(character)
	flushDeferred()
	return player, root
end
local function leave(player)
	local i = table.find(playerList, player)
	if i then
		table.remove(playerList, i)
	end
	fakePlayers.PlayerRemoving:Fire(player)
	player.Parent = nil
end
local function moveTo(root, position)
	root.CFrame = roblox.CFrame.new(position)
	root.Position = position
end
local function tick(seconds)
	local step = 0.1
	local t = 0
	while t < seconds - 1e-9 do
		advance(step)
		registry.MagnetService.tick(step)
		t += step
	end
	flushDeferred()
end
local function clearNear(position, radius)
	for _, item in pairs(registry.ScrapService.all()) do
		if (item.position - position).Magnitude < radius and not item.claimedBy then
			registry.ScrapService.consume(item)
		end
	end
end
local function spawnAt(id, position)
	return registry.ScrapService.spawn("Rustyard", { def = ScrapConfig.ById[id], position = position, quiet = true })
end

local alice, aliceRoot, bob, bobRoot
local DS, MS, SS
check("player joins: default profile, magnet rig on the character, pile attributes, leaderstats", function()
	DS, MS, SS = registry.DataService, registry.MagnetService, registry.ScrapService
	alice, aliceRoot = makePlayer("Alice", roblox.Vector3.new(0, 3, 40))
	local p = DS.getProfile(alice)
	assert(p and p.Coins == 0 and p.Tier == 1 and p.Zones.Rustyard and not p.Zones.MetroWreck, "bad default profile")
	assert(not DS.isPersistent(alice), "should fall back to memory without DataStores")
	assert(alice.Character:FindFirstChild("MagnetRig"), "no magnet rig")
	assert(alice:GetAttribute("MM_Pile") == "" and alice:GetAttribute("MM_PileCount") == 0)
	assert(alice:FindFirstChild("leaderstats"), "no leaderstats")
	assert(count("Notify", "saving is unavailable", alice) >= 1, "player not told saving is off")
	assert(p.Tutorial.Step == 1 and not p.Tutorial.Done)
end)

local function pileCount(player)
	return #DS.getProfile(player).Carried
end

check("magnet: claim -> flight -> award exactly once -> pile grows (first collection)", function()
	clearNear(aliceRoot.Position, 60)
	local item = spawnAt("Bolt", aliceRoot.Position + roblox.Vector3.new(6, -2, 0))
	remotes.Magnet.OnServerEvent:Fire(alice, true)
	assert(alice:GetAttribute("MM_Active") == true, "magnet not active")
	tick(0.1)
	local st = MS.stateOf(alice)
	assert(item.claimedBy == alice, string.format("nearby bolt not claimed (active=%s tokens=%s inFlight=%s query=%d dist=%.1f claimedBy=%s)", tostring(st.active), tostring(st.tokens), tostring(st.inFlight), #SS.query(aliceRoot.Position, 16), (item.position - aliceRoot.Position).Magnitude, tostring(item.claimedBy)))
	local attract = log.Attract[#log.Attract]
	assert(attract and attract.all and attract.args[1][1][1] == item.id, "Attract batch not broadcast")
	assert(pileCount(alice) == 0, "awarded before the flight finished")
	tick(1.5)
	assert(SS.get(item.id) == nil, "object not consumed")
	assert(pileCount(alice) == 1 and DS.getProfile(alice).Carried[1].id == "Bolt", "bolt not in the pile")
	assert(alice:GetAttribute("MM_Pile") == "Bolt" and alice:GetAttribute("MM_PileCount") == 1, "pile attributes not updated")
	assert(count("Collected") >= 1, "Collected not broadcast")
	assert(DS.getProfile(alice).Codex.Bolt.n == 1, "codex not updated")
	assert(DS.getProfile(alice).Achievements.FirstCollect, "first-collect achievement missing")
	-- Awarding again is impossible: the object is gone.
	assert(SS.consume(item) == false)
	tick(1)
	assert(pileCount(alice) == 1, "awarded twice")
	assert(DS.getProfile(alice).Tutorial.Step == 2, "tutorial did not advance past 'activate'")
end)

check("magnet: out-of-range and too-heavy objects are not claimed; player is told why", function()
	clearNear(aliceRoot.Position, 60)
	local far = spawnAt("Bolt", aliceRoot.Position + roblox.Vector3.new(45, -2, 0))
	local safe = spawnAt("SteelSafe", aliceRoot.Position + roblox.Vector3.new(5, -2, 3))
	tick(0.5)
	assert(not far.claimedBy, "claimed an object out of range")
	assert(not safe.claimedBy, "pulled a safe with strength 1")
	assert(count("Notify", "too heavy", alice) >= 1, "no too-heavy notice")
	SS.consume(far)
	SS.consume(safe)
end)

check("magnet: flight is released (not awarded) if the player walks away mid-pull", function()
	clearNear(aliceRoot.Position, 60)
	local pipe = spawnAt("RustyPipe", aliceRoot.Position + roblox.Vector3.new(10, -2, 0))
	tick(0.1)
	assert(pipe.claimedBy == alice, "pipe not claimed")
	local before = pileCount(alice)
	moveTo(aliceRoot, roblox.Vector3.new(-120, 3, 120))
	remotes.Magnet.OnServerEvent:Fire(alice, false)
	tick(2)
	assert(pileCount(alice) == before, "awarded after walking away")
	assert(SS.get(pipe.id) == pipe and not pipe.claimedBy, "pipe not released back")
	assert(count("Released") >= 1, "Released not broadcast")
	moveTo(aliceRoot, roblox.Vector3.new(0, 3, 40))
end)

check("magnet: two players racing for one object -> exactly one gets it", function()
	bob, bobRoot = makePlayer("Bob", roblox.Vector3.new(4, 3, 40))
	clearNear(aliceRoot.Position, 60)
	local gear = spawnAt("Gear", roblox.Vector3.new(2, 1, 44))
	remotes.Magnet.OnServerEvent:Fire(alice, true)
	remotes.Magnet.OnServerEvent:Fire(bob, true)
	local beforeA, beforeB = pileCount(alice), pileCount(bob)
	tick(2)
	local gotA, gotB = pileCount(alice) - beforeA, pileCount(bob) - beforeB
	assert(gotA + gotB == 1, string.format("gear awarded %d times", gotA + gotB))
	remotes.Magnet.OnServerEvent:Fire(bob, false)
end)

check("magnet: tutorial and capacity - collecting stops when the pile is full", function()
	clearNear(aliceRoot.Position, 60)
	local stats = registry.UpgradeService.statsFor(alice)
	for i = 1, 40 do
		spawnAt("Bolt", aliceRoot.Position + roblox.Vector3.new(math.cos(i) * 6, -2, math.sin(i) * 6))
	end
	remotes.Magnet.OnServerEvent:Fire(alice, true)
	tick(8)
	local mass = DS.carriedTotals(DS.getProfile(alice))
	assert(mass <= stats.MaximumScrapCapacity, "pile over capacity: " .. mass)
	assert(mass >= stats.MaximumScrapCapacity - 2, "pile not filled: " .. mass)
	assert(count("Notify", "FULL", alice) >= 1, "player not told the pile is full")
	assert(DS.getProfile(alice).Tutorial.Step == 3, "tutorial should now point at the shredder (step " .. DS.getProfile(alice).Tutorial.Step .. ")")
	remotes.Magnet.OnServerEvent:Fire(alice, false)
	tick(2)
end)

check("sell: only at the shredder, pays once, duplicate prompt / pad touches pay nothing", function()
	local p = DS.getProfile(alice)
	local _, pileValue = DS.carriedTotals(p)
	local expected = Economy.saleValue(pileValue, registry.UpgradeService.statsFor(alice).ScrapValueMultiplier)
	local start = p.Coins -- starter-quest rewards may already have paid out
	remotes.Sell.OnServerEvent:Fire(alice)
	assert(p.Coins == start and #p.Carried > 0, "sold away from the shredder")
	moveTo(aliceRoot, world.sellPad.Position + roblox.Vector3.new(0, 3, 0))
	world.sellPrompt.Triggered:Fire(alice)
	local paid = p.Coins - start
	assert(paid >= expected, string.format("paid %d, expected %d", paid, expected))
	local saleCoins = p.TotalScrapValue
	assert(saleCoins == expected, string.format("sale paid %d, expected %d", saleCoins, expected))
	local afterSale = p.Coins
	assert(#p.Carried == 0 and alice:GetAttribute("MM_PileCount") == 0, "pile not cleared")
	world.sellPrompt.Triggered:Fire(alice)
	remotes.Sell.OnServerEvent:Fire(alice)
	advance(5)
	world.sellPrompt.Triggered:Fire(alice)
	assert(p.Coins == afterSale, "a duplicate sell paid again")
	assert(p.TotalScrapValue == expected and p.Stats.SellCount == 1)
	assert(count("SellFx") == 1, "sell effect fired " .. count("SellFx") .. " times")
	assert(p.Achievements.FirstSale and p.Tutorial.Step == 4, "first sale did not advance tutorial / achievement")
	assert(expected >= Economy.upgradePrice("Range", 0), "first sale can't afford the first upgrade")
	moveTo(aliceRoot, roblox.Vector3.new(0, 3, 40))
end)

check("upgrades: validated server-side, exact price, stats change, max level", function()
	local p = DS.getProfile(alice)
	local coins = p.Coins
	local before = registry.UpgradeService.statsFor(alice).AttractionRange
	remotes.BuyUpgrade.OnServerEvent:Fire(alice, "NotAnUpgrade")
	remotes.BuyUpgrade.OnServerEvent:Fire(alice, 12345)
	assert(p.Coins == coins, "forged request spent coins")
	local price = Economy.upgradePrice("Range", 0)
	local ok = registry.UpgradeService.buyUpgrade(alice, "Range")
	assert(ok and p.Upgrades.Range == 1 and p.Coins == coins - price, "range upgrade did not apply / wrong price")
	assert(registry.UpgradeService.statsFor(alice).AttractionRange > before, "range did not grow")
	assert(p.Tutorial.Step == 5, "tutorial did not advance after the first upgrade")
	-- Unaffordable: nothing changes.
	p.Coins = 0
	local ok2, msg = registry.UpgradeService.buyUpgrade(alice, "Heavy")
	assert(not ok2 and string.find(msg, "Need", 1, true) and (p.Upgrades.Heavy or 0) == 0, "bought without coins")
	-- Max level.
	p.Coins = 1e12
	for _ = 1, EconomyConfig.ByKey.Move.Max + 3 do
		registry.UpgradeService.buyUpgrade(alice, "Move")
	end
	assert(p.Upgrades.Move == EconomyConfig.ByKey.Move.Max, "went past max level")
	assert(alice.Character:FindFirstChildOfClass("Humanoid").WalkSpeed == registry.UpgradeService.statsFor(alice).WalkSpeed, "walk speed not applied")
	remotes.Sprint.OnServerEvent:Fire(alice, true)
	assert(alice.Character:FindFirstChildOfClass("Humanoid").WalkSpeed > registry.UpgradeService.statsFor(alice).WalkSpeed, "sprint not applied")
	remotes.Sprint.OnServerEvent:Fire(alice, false)
end)

check("magnet tier: rig rebuilt, strength jumps, heavy objects now pullable", function()
	local p = DS.getProfile(alice)
	p.Coins = 1e12
	assert(registry.UpgradeService.buyTier(alice))
	assert(registry.UpgradeService.buyTier(alice))
	assert(p.Tier == 3 and alice.Character.MagnetRig:GetAttribute("Tier") == 3, "rig not rebuilt for tier 3")
	assert(#alice.Character:GetChildren() > 0)
	local rigs = 0
	for _, child in ipairs(alice.Character:GetChildren()) do
		if child.Name == "MagnetRig" then
			rigs += 1
		end
	end
	assert(rigs == 1, "old rig not removed")
	clearNear(aliceRoot.Position, 60)
	local engine = spawnAt("MotorcycleEngine", aliceRoot.Position + roblox.Vector3.new(8, -2, 0))
	remotes.Magnet.OnServerEvent:Fire(alice, true)
	tick(4)
	assert(SS.get(engine.id) == nil and p.Carried[#p.Carried].id == "MotorcycleEngine", "tier 3 can't pull a motorcycle engine")
	assert(p.Achievements.FirstRare and p.Achievements.FirstHeavy, "rare / heavy achievements missing")
	assert(count("Announce", "RARE", nil) >= 1, "rare find not announced")
	remotes.Magnet.OnServerEvent:Fire(alice, false)
end)

check("pulse: big radius grab with a server cooldown", function()
	clearNear(aliceRoot.Position, 80)
	local stats = registry.UpgradeService.statsFor(alice)
	local items = {}
	for i = 1, 6 do
		table.insert(items, spawnAt("Washer", aliceRoot.Position + roblox.Vector3.new(stats.AttractionRange + 4, -2, i * 2 - 6)))
	end
	DS.getProfile(alice).Carried = {}
	local ok = registry.MagnetService.pulse(alice)
	assert(ok, "pulse refused")
	local claimed = 0
	for _, it in ipairs(items) do
		if it.claimedBy == alice then
			claimed += 1
		end
	end
	assert(claimed >= 4, "pulse only claimed " .. claimed)
	assert(registry.MagnetService.pulse(alice) == false, "pulse ignored its cooldown")
	assert(DS.getProfile(alice).Stats.Pulse == 1)
	advance(stats.PulseCooldown + 0.1)
	assert(registry.MagnetService.pulse(alice), "pulse not ready after cooldown")
	tick(4)
end)

check("zones: requirements enforced, unlock saved once, locked players pushed back", function()
	local p = DS.getProfile(bob)
	p.Coins = 1e9
	local ok, msg = registry.ZoneService.unlock(bob, "MetroWreck")
	assert(not ok and string.find(msg, "strength", 1, true), "unlocked without strength")
	moveTo(bobRoot, roblox.Vector3.new(300, 3, 0))
	registry.ZoneService.enforce(bob)
	assert(bobRoot.CFrame.Position.X < 157, "locked player stayed in Metro Wreck")
	bobRoot.Position = bobRoot.CFrame.Position
	-- Scrap in a locked zone is never claimed.
	local metroScrap = registry.ScrapService.spawn("MetroWreck", { def = ScrapConfig.ById.Hubcap, position = roblox.Vector3.new(300, 0, 0), quiet = true })
	moveTo(bobRoot, roblox.Vector3.new(300, 3, 2))
	remotes.Magnet.OnServerEvent:Fire(bob, true)
	tick(0.3)
	assert(not metroScrap.claimedBy, "claimed scrap in a locked zone")
	remotes.Magnet.OnServerEvent:Fire(bob, false)
	moveTo(bobRoot, roblox.Vector3.new(4, 3, 40))
	local a = DS.getProfile(alice)
	a.Coins = 20000
	assert(registry.ZoneService.unlock(alice, "MetroWreck"), "alice could not unlock")
	assert(a.Zones.MetroWreck and a.Coins == 20000 - ZoneConfig.ById.MetroWreck.Unlock.Coins)
	assert(not registry.ZoneService.unlock(alice, "MetroWreck"), "unlocked twice")
	assert(not registry.ZoneService.unlock(alice, "IndustrialCore"), "unlocked an unbuilt zone")
	assert(a.Achievements.FirstZone, "zone achievement missing")
end)

check("quests / achievements / codex reward exactly once", function()
	local p = DS.getProfile(alice)
	local index = p.Quest.Index
	local quest = QuestConfig.Starter[index]
	assert(quest, "starter quests already finished")
	p.Stats[quest.Stat] = (p.Stats[quest.Stat] or 0)
	local coins = p.Coins
	DS.bump(alice, quest.Stat, quest.Target)
	local afterQuest = p.Quest.Index
	assert(afterQuest > index, "quest did not complete")
	local gained = p.Coins - coins
	assert(gained >= quest.Reward, "quest reward missing")
	DS.bump(alice, quest.Stat, 0)
	registry.QuestService.onStat(alice, quest.Stat, 0)
	assert(p.Coins - coins == gained, "quest rewarded twice")
	local achievementCards = count("Popup", "Achievement", alice)
	registry.QuestService.onStat(alice, "Collect", 0)
	registry.QuestService.onStat(alice, "SellCount", 0)
	assert(count("Popup", "Achievement", alice) == achievementCards, "achievement fired twice")
	local discoveries = count("Popup", "Discovery", alice)
	registry.QuestService.discover(alice, ScrapConfig.ById.Bolt, 3)
	assert(count("Popup", "Discovery", alice) == discoveries, "codex re-announced a known entry")
	assert(p.Codex.Bolt.n >= 2)
end)

check("daily objectives: progress, one reward, reroll on a new UTC day", function()
	local p = DS.getProfile(alice)
	registry.QuestService.ensureDaily(alice)
	local day = p.Daily.Day
	local first = p.Daily.List[1]
	local coins = p.Coins
	DS.bump(alice, first.Stat, first.Target + 5)
	assert(first.Done and first.Progress == first.Target, "daily not completed")
	local gained = p.Coins - coins
	assert(gained >= first.Reward)
	DS.bump(alice, first.Stat, 10)
	-- (other quests may pay for the same stat; the daily itself must not pay again)
	assert(first.Done and first.Progress == first.Target)
	advance(86400)
	registry.QuestService.ensureDaily(alice)
	assert(p.Daily.Day == day + 1 and not p.Daily.List[1].Done, "daily did not reset on a new day")
end)

check("codes: valid once per player, unknown rejected", function()
	local p = DS.getProfile(bob)
	local coins = p.Coins
	assert(registry.QuestService.redeem(bob, " magnet "))
	assert(p.Coins == coins + 150)
	assert(not registry.QuestService.redeem(bob, "MAGNET"), "code used twice")
	assert(not registry.QuestService.redeem(bob, "FREEMONEY"))
	assert(not registry.QuestService.redeem(bob, 5))
end)

check("magnetic storm: more scrap, higher value, reward only for real participation", function()
	local ES = registry.EventService
	ES.startStorm()
	assert(workspaceService:GetAttribute("MM_Event") == "MagneticStorm")
	assert(SS.stormMultiplier > 1 and ES.valueMultiplier() == EventConfig.MagneticStorm.ValueMultiplier)
	for _ = 1, EventConfig.MagneticStorm.ParticipationTarget do
		ES.onCollect(alice, 10)
	end
	ES.onCollect(bob, 10) -- below the target
	local a, b = DS.getProfile(alice).Coins, DS.getProfile(bob).Coins
	ES.endStorm()
	assert(DS.getProfile(alice).Coins > a, "participant got no storm reward")
	assert(DS.getProfile(bob).Coins == b, "non-participant got a storm reward")
	assert(SS.stormMultiplier == 1 and ES.valueMultiplier() == nil)
	assert(workspaceService:GetAttribute("MM_Event") == nil)
end)

check("player leaving mid-pull: in-flight scrap is released, never awarded", function()
	local carol, carolRoot = makePlayer("Carol", roblox.Vector3.new(-60, 3, 30))
	clearNear(carolRoot.Position, 40)
	local item = spawnAt("Gear", carolRoot.Position + roblox.Vector3.new(5, -2, 0))
	remotes.Magnet.OnServerEvent:Fire(carol, true)
	tick(0.1)
	assert(item.claimedBy == carol, "not claimed")
	leave(carol)
	tick(2)
	assert(SS.get(item.id) == item and not item.claimedBy, "left player's object not released")
end)

local function hasId(list, id, userId)
	for _, entry in ipairs(list or {}) do
		if (type(entry) == "table" and entry[1] == id and (not userId or entry[2] == userId)) or entry == id then
			return true
		end
	end
	return false
end

check("magnet: released by one player and re-grabbed by another in one tick -> Released is sent before Attract", function()
	remotes.Magnet.OnServerEvent:Fire(alice, false)
	remotes.Magnet.OnServerEvent:Fire(bob, false)
	moveTo(aliceRoot, roblox.Vector3.new(-60, 3, 60))
	moveTo(bobRoot, roblox.Vector3.new(-52, 3, 60))
	DS.getProfile(alice).Carried = {}
	DS.getProfile(bob).Carried = {}
	clearNear(aliceRoot.Position, 60)
	local item = spawnAt("Bolt", roblox.Vector3.new(-56, 1, 62))
	MS.setActive(alice, true)
	tick(0.1)
	assert(item.claimedBy == alice, "alice did not claim")
	MS.cancelAll(alice) -- e.g. died: release queued for the next batch
	MS.setActive(bob, true)
	tick(0.1)
	assert(item.claimedBy == bob, "bob did not re-claim the released object")
	local rel, att = log.Released[#log.Released], log.Attract[#log.Attract]
	assert(hasId(rel.args[1], item.id) and hasId(att.args[1], item.id, bob.UserId), "release / re-claim not broadcast")
	assert(rel.seq < att.seq, "Released sent after Attract: clients would drop bob's flight")
	MS.cancelAll(bob)
	tick(0.1)
	-- A claim that is released before it was ever broadcast is dropped, not sent twice.
	local attracts, releases = #log.Attract, #log.Released
	MS.stateOf(alice).lastPulse = -math.huge
	assert(MS.pulse(alice), "pulse refused")
	assert(item.claimedBy == alice, "pulse did not claim")
	MS.cancelAll(alice)
	MS.flush()
	for i = attracts + 1, #log.Attract do
		assert(not hasId(log.Attract[i].args[1], item.id), "cancelled claim still broadcast as Attract")
	end
	for i = releases + 1, #log.Released do
		assert(not hasId(log.Released[i].args[1], item.id), "never-broadcast claim sent as Released")
	end
	assert(not item.claimedBy, "object stuck claimed")
	moveTo(aliceRoot, roblox.Vector3.new(0, 3, 40))
	moveTo(bobRoot, roblox.Vector3.new(4, 3, 40))
end)

check("prestige: needs confirmation + eligibility, resets exactly what it says", function()
	local p = DS.getProfile(alice)
	assert(not registry.UpgradeService.prestige(alice, "yes"), "prestiged without CONFIRM")
	p.RunEarned = 0
	assert(not registry.UpgradeService.prestige(alice, "CONFIRM"), "prestiged while not eligible")
	p.RunEarned = EconomyConfig.Prestige.MinRunEarned * 4
	local codex, achievements = p.Codex, p.Achievements
	local cosmetics = p.Cosmetics
	local preview = registry.UpgradeService.prestigePreview(alice)
	assert(preview.eligible and preview.cores == EconomyConfig.Prestige.CoresBase * 2)
	assert(registry.UpgradeService.prestige(alice, "CONFIRM"))
	assert(p.Coins == 0 and p.Tier == 1 and next(p.Upgrades) == nil and not p.Zones.MetroWreck and #p.Carried == 0, "did not reset")
	assert(p.Prestige.Cores == preview.cores and p.Prestige.Count == 1)
	assert(p.Codex == codex and p.Achievements == achievements and p.Cosmetics == cosmetics, "wiped permanent data")
	assert(p.Achievements.FirstPrestige and p.Cosmetics.Owned.Hazard, "prestige achievement / Hazard skin not unlocked")
	assert(registry.UpgradeService.statsFor(alice).ScrapValueMultiplier > 1, "cores give no bonus")
	assert(alice.Character.MagnetRig:GetAttribute("Tier") == 1, "rig not reset")
end)

check("cosmetics: equip only what you own (achievement, pass, product)", function()
	assert(not registry.ShopService.equip(alice, "Skin", "GoldRush"), "equipped an unowned pass skin")
	assert(registry.ShopService.equip(alice, "Skin", "Hazard"), "could not equip the achievement skin")
	assert(alice:GetAttribute("MM_Skin") == "Hazard")
	assert(not registry.ShopService.equip(alice, "Skin", "DoesNotExist"))
	assert(not registry.ShopService.equip(alice, "Hat", "Hazard"))
	registry.ShopService.buy(alice, "GoldSkin") -- PassId 0 in Studio: granted for this session
	assert(registry.ShopService.equip(alice, "Skin", "GoldRush"), "studio pass grant did not work")
	registry.ShopService.buy(alice, "NeonSkin") -- ProductId set: prompts instead of granting
	assert(#prompts == 1 and prompts[1].id == 4242, "product purchase not prompted")
	assert(not registry.ShopService.ownsCosmetic(alice, "Skin", "NeonPulse"), "granted before the receipt")
end)

local function receipt(player, purchaseId)
	return stubServices.MarketplaceService.ProcessReceipt({ PlayerId = player.UserId, ProductId = 4242, PurchaseId = purchaseId })
end

check("receipts: granted exactly once, refused when the profile can't persist live", function()
	local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
	local notYet = roblox.Enum.ProductPurchaseDecision.NotProcessedYet
	assert(receipt(alice, "r-1") == granted)
	assert(DS.getProfile(alice).Cosmetics.Owned.NeonPulse and DS.getProfile(alice).Receipts["r-1"])
	assert(receipt(alice, "r-1") == granted, "retry not acknowledged")
	local owned = 0
	for _ in pairs(DS.getProfile(alice).Receipts) do
		owned += 1
	end
	assert(owned == 1, "receipt stored twice")
	isStudio = false
	local decision = receipt(bob, "r-live")
	isStudio = true
	assert(decision == notYet and not DS.getProfile(bob).Cosmetics.Owned.NeonPulse, "live purchase granted on a non-persistent profile")
	assert(stubServices.MarketplaceService.ProcessReceipt({ PlayerId = 999999, ProductId = 4242, PurchaseId = "x" }) == notYet)
end)

check("settings: only known keys with legal values are saved", function()
	local p = DS.getProfile(bob)
	registry.PlayerService.saveSettings(bob, { Music = 0.3, Master = 7, Effects = 0 / 0, CameraMode = "Upside", Particles = "Low", Hack = true, ReducedEffects = "yes" })
	assert(p.Settings.Music == 0.3 and p.Settings.Master == 1, "numbers not clamped")
	assert(p.Settings.Effects == 1, "NaN accepted")
	assert(p.Settings.CameraMode == "Third" and p.Settings.Particles == "Low")
	assert(p.Settings.Hack == nil and p.Settings.ReducedEffects == false)
end)

check("session lock: load locks, a taken-over profile stops saving, leaving unlocks", function()
	local stored = {}
	local function copy(v)
		if type(v) ~= "table" then
			return v
		end
		local t = {}
		for k, x in pairs(v) do
			t[k] = copy(x)
		end
		return t
	end
	local fakeStore = {
		UpdateAsync = function(_, k, fn)
			local new = fn(copy(stored[k]))
			if new ~= nil then
				stored[k] = copy(new)
			end
			return copy(new)
		end,
	}
	stubServices.DataStoreService.GetDataStore = function()
		return fakeStore
	end
	DS.init(registry)
	local ok, err = pcall(function()
		stored["player_" .. (nextUserId + 1)] = { Coins = 777, Upgrades = { Range = 999, Bogus = 3 }, Tier = 42 }
		local dave = makePlayer("Dave")
		local key = "player_" .. dave.UserId
		local p = DS.getProfile(dave)
		assert(DS.isPersistent(dave) and p.Coins == 777, "saved profile not loaded")
		assert(p.Upgrades.Range == EconomyConfig.ByKey.Range.Max and p.Upgrades.Bogus == nil and p.Tier == #MagnetConfig.Tiers, "saved data not validated")
		assert(type(stored[key].Lock) == "table", "profile not locked on load")
		p.Coins = 800
		assert(DS.save(dave) and stored[key].Coins == 800, "save failed")
		stored[key].Lock = { Session = "other-server", At = fakeOs.time() }
		p.Coins = 1
		assert(not DS.save(dave), "saved over another server's lock")
		assert(stored[key].Coins == 800 and not DS.isPersistent(dave))
		isStudio = false
		local decision = receipt(dave, "lock-1")
		isStudio = true
		assert(decision == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "granted after losing the lock")
		leave(dave)
		assert(stored[key].Coins == 800, "left player overwrote the new owner")
		stored["player_" .. (nextUserId + 1)] = { Coins = 55, Lock = { Session = "crashed", At = fakeOs.time() - 100000 } }
		local erin = makePlayer("Erin")
		local erinKey = "player_" .. erin.UserId
		assert(DS.isPersistent(erin) and DS.getProfile(erin).Coins == 55, "stale lock blocked the load")
		DS.getProfile(erin).Coins = 99
		-- A receipt arriving after the final save (leave / BindToClose) must not be granted:
		-- that save already ran and released the lock, so the grant would never be stored.
		local realRelease, lateDecision = DS.release, nil
		DS.release = function(player)
			if player == erin then
				-- (in Roblox the player is still in Players here, and during BindToClose)
				table.insert(playerList, erin)
				lateDecision = receipt(erin, "late-1")
				table.remove(playerList, table.find(playerList, erin))
			end
			return realRelease(player)
		end
		leave(erin)
		DS.release = realRelease
		assert(lateDecision == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "receipt granted after the final save")
		assert(stored[erinKey].Receipts == nil or stored[erinKey].Receipts["late-1"] == nil)
		assert(stored[erinKey].Coins == 99 and stored[erinKey].Lock == nil, "leave save did not persist and unlock")
	end)
	isStudio = true
	stubServices.DataStoreService.GetDataStore = function()
		error("DataStores are not available in the harness")
	end
	DS.init(registry)
	assert(ok, err)
end)

check("analytics: onboarding funnel steps logged once each", function()
	local seen = {}
	for _, a in ipairs(analytics) do
		if a.player == alice then
			assert(not seen[a.name], a.name .. " logged twice")
			seen[a.name] = true
		end
	end
	for _, name in ipairs({ "FirstCollect", "FirstSale", "FirstUpgrade", "FirstRare", "FirstZone", "FirstPrestige" }) do
		assert(seen[name], name .. " not logged")
	end
end)

---------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------

check("client controllers initialise, render a real snapshot and animate flights / piles / sales", function()
	local snapshot = DS.sendProfileNow(bob)
	assert(snapshot and snapshot.stats and snapshot.daily and snapshot.quest and snapshot.prestigePreview, "snapshot incomplete")
	requireModule(Shared.Net).setup()
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = bob
	fakePlayers.LocalPlayer = bob
	stubServices.RunService.IsServer = function()
		return false
	end
	local camera = roblox.Instance.new("Camera")
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	camera.Parent = workspaceService
	workspaceService.CurrentCamera = camera
	local folder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("MagnetMayhemClient"):FindFirstChild("Controllers")
	local names = { "ClientState", "AudioController", "CameraController", "InputController", "MagnetController", "HudController", "EffectsController", "LightingController", "TutorialController", "MenuController" }
	local controllers = {}
	for _, name in ipairs(names) do
		controllers[name] = requireModule(folder[name])
		controllers[name].init()
	end
	local CS = controllers.ClientState
	CS.profile = snapshot
	CS.settings = table.clone(snapshot.settings)
	CS.ProfileChanged:Fire(snapshot)
	for _, name in ipairs({ "MagnetHUD", "MagnetFX", "MagnetMenu", "MagnetTutorial" }) do
		assert(playerGui:FindFirstChild(name), name .. " missing")
	end
	-- Every menu tab renders.
	local Menu = controllers.MenuController
	for _, tab in ipairs({ "Upgrades", "Codex", "Quests", "Zones", "Shop", "Settings" }) do
		Menu.open(tab)
	end
	for _, category in ipairs(EconomyConfig.Categories) do
		Menu.setTab("Upgrades")
		Menu.setCategory(category)
		Menu.render()
		local cards = 0
		for _, d in ipairs(playerGui.MagnetMenu:GetDescendants()) do
			if d:IsA("TextLabel") and string.find(d.Text, "Level ", 1, true) then
				cards += 1
			end
		end
		assert(cards >= 2, category .. " shows " .. cards .. " upgrade cards")
	end
	registry.QuestService.discover(bob, ScrapConfig.ById.SodaCan, 2)
	CS.profile = DS.snapshot(bob)
	Menu.setTab("Codex")
	Menu.render()
	local unknown = 0
	for _, d in ipairs(playerGui.MagnetMenu:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text == "???" then
			unknown += 1
		end
	end
	assert(unknown > 0 and unknown < #ScrapConfig.List, "codex should show discovered and ??? entries (" .. unknown .. ")")
	-- A real flight: server claims for Bob, client animates the world model.
	clearNear(bobRoot.Position, 60)
	local item = spawnAt("Toolbox", bobRoot.Position + roblox.Vector3.new(6, -2, 0))
	DS.getProfile(bob).Tier = 2
	registry.UpgradeService.invalidate(bob)
	stubServices.RunService.IsServer = function()
		return true
	end
	remotes.Magnet.OnServerEvent:Fire(bob, true)
	tick(0.1)
	local attract = log.Attract[#log.Attract].args
	CS.Attracted:Fire(attract[1], attract[2])
	assert(controllers.MagnetController.flights[item.id], "client did not start the flight")
	local function clientStep()
		syncPositions(workspaceService)
		controllers.MagnetController.step(1 / 60)
	end
	local startPos = item.model:GetPivot().Position
	local entry = attract[1][#attract[1]]
	local duration, anticipation = entry[3], entry[4]
	advance(anticipation * 0.5)
	clientStep()
	assert(item.model.Parent and (item.model:GetPivot().Position - startPos).Magnitude < 1.5, "wind-up should only shake / lift a little")
	advance(anticipation * 0.5 + (duration - anticipation) * 0.5)
	clientStep()
	local mid = item.model:GetPivot().Position
	assert((mid - startPos).Magnitude > 0.5, "flight did not move the model")
	assert((mid - bobRoot.Position).Magnitude < (startPos - bobRoot.Position).Magnitude, "flight is not heading to the player")
	advance(duration)
	clientStep()
	assert(item.model.Parent == nil, "arrived object should be hidden until the server confirms")
	tick(3)
	local collected = log.Collected[#log.Collected].args
	CS.Collected:Fire(collected[1])
	assert(not controllers.MagnetController.flights[item.id], "flight not finished on Collected")
	clientStep()
	local pile = controllers.MagnetController.piles[bob]
	assert(pile and #pile.pieces == #DS.getProfile(bob).Carried, string.format("pile shows %d pieces, server has %d", pile and #pile.pieces or -1, #DS.getProfile(bob).Carried))
	assert(bulkMoves > 0, "BulkMoveTo never used")
	-- Sale animation takes the pieces.
	controllers.EffectsController.sell(bob.UserId, 500, #pile.pieces, false)
	assert(#pile.pieces == 0, "sell animation did not take the pile")
	flushDeferred()
	-- Arrived (hidden) but then released by the server (walked away at the last moment):
	-- the object must come back on this client, even several frames later.
	clearNear(bobRoot.Position, 60)
	local late = spawnAt("Toolbox", bobRoot.Position + roblox.Vector3.new(6, -2, 0))
	tick(0.1)
	assert(late.claimedBy == bob, "second toolbox not claimed")
	local lateAttract = log.Attract[#log.Attract].args
	CS.Attracted:Fire(lateAttract[1], lateAttract[2])
	local lateEntry = lateAttract[1][#lateAttract[1]]
	advance(lateEntry[3] + 0.05)
	clientStep()
	assert(late.model.Parent == nil, "arrived object should be hidden")
	clientStep()
	clientStep()
	assert(controllers.MagnetController.flights[late.id], "hidden flight dropped before the server answered")
	remotes.Magnet.OnServerEvent:Fire(bob, false)
	local home = bobRoot.Position
	moveTo(bobRoot, home + roblox.Vector3.new(0, 0, 200))
	tick(1)
	assert(SS.get(late.id) == late and not late.claimedBy, "server did not release the toolbox")
	CS.Released:Fire(log.Released[#log.Released].args[1])
	assert(late.model.Parent == world.scrapFolder, "released object stays invisible on this client")
	assert(not controllers.MagnetController.flights[late.id], "released flight not ended")
	moveTo(bobRoot, home)
	-- Popups, events, settings, zone change.
	for _, kind in ipairs({ "Achievement", "Quest", "Daily", "Discovery", "Upgrade", "Tier", "Zone", "Prestige", "StormReward", "TutorialDone", "OpenMenu", "GateMenu" }) do
		CS.PopupRequested:Fire(kind, { id = "SteelSafe", name = "Large Steel Safe", rarity = "Rare", count = 3, total = 26, text = "x", reward = 10, tier = 2, cores = 3, total2 = 3, tab = "Codex" })
	end
	CS.Notified:Fire("Hello", "good")
	CS.Notified:Fire("Nope", "error")
	CS.Announced:Fire("Somebody pulled a LEGENDARY!", { 255, 190, 60 })
	CS.EventChanged:Fire({ kind = "MagneticStorm", name = "MAGNETIC STORM", endsAt = unixOffset + clock + 60 })
	controllers.HudController.tick()
	CS.EventChanged:Fire({ kind = nil })
	CS.applySettings({ CameraMode = "First", ReducedEffects = true, Particles = "Low" })
	controllers.CameraController.apply()
	clientStep()
	CS.applySettings({ CameraMode = "Third" })
	CS.ZoneChanged:Fire("MetroWreck")
	controllers.LightingController.apply("MetroWreck", true)
	controllers.LightingController.updateBarrier(snapshot)
	controllers.EffectsController.stepMachine(0.1)
	assert(controllers.HudController.nextGoal(snapshot), "no next goal")
	stubServices.RunService.IsServer = function()
		return true
	end
end)

if handlerErrors > 0 then
	failed += 1
	print(string.format("  FAIL  %d errors were reported through warn()", handlerErrors))
end
print(string.format("\nharness: %d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
process.exit(0)
