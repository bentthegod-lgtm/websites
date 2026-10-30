--[[
	Headless smoke harness for THIN ICE.

	Loads the Rojo-built place in Lune and runs the REAL game modules against Lune's Roblox
	instance implementation. Engine services Lune does not simulate (players, data stores,
	marketplace, tweens, input, physics, rendering) are stubbed, and time is a fake clock the
	tests advance. Lune has no physics, so characters are moved by the tests.

	Usage (from thin-ice/):
	  rojo build -o build/ThinIce.rbxlx && lune run tests/harness build/ThinIce.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/ThinIce.rbxlx"
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
	SocialService = stubObject("SocialService", {
		PromptGameInvite = function() end,
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
			d.Position = d.CFrame.Position
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
local clientSent = {}
roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
	table.insert(clientSent, { name = self.Name, args = table.pack(...) })
end)
roblox.implementMethod("Sound", "Play", function() end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)
roblox.implementMethod("Instance", "ClearAllChildren", function(self)
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
end)

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
fakeEvent("Part", "Touched")
fakeEvent("Model", "DescendantAdded")
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
	PhysicalProperties = roblox.PhysicalProperties,
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
local Shared = RS:FindFirstChild("ThinIce")
local ServerRoot = SSS:FindFirstChild("ThinIceServer")
local Services = ServerRoot:FindFirstChild("Services")

local GameConfig = requireModule(Shared.Config.GameConfig)
local ShopConfig = requireModule(Shared.Config.ShopConfig)
local LakeGen = requireModule(Shared.LakeGen)
local Models = requireModule(Shared.Models)
local V3, CF = roblox.Vector3, roblox.CFrame
local L = GameConfig.Lake

-- Real product ids so ProcessReceipt can be exercised (config tables are plain tables).
ShopConfig.Products[3].ProductId = 5151 -- Polar outfit
ShopConfig.Products[1].ProductId = 5152 -- Flask x1

local function partsIn(root)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

check("all server modules load", function()
	for _, m in ipairs(Services:GetChildren()) do
		requireModule(m)
	end
	requireModule(ServerRoot.World.LobbyBuilder)
	requireModule(ServerRoot.World.LakeBuilder)
end)

check("models: the Antlered (antlers, long arms, no eyes), ice block, core, kid", function()
	local monster = Models.monster(CF.new(), nil)
	local antlers, eyes, claws = 0, 0, 0
	for _, d in ipairs(monster:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Antler" or d.Name == "Tine" then
				antlers += 1
			elseif string.find(d.Name, "Eye") then
				eyes += 1
			elseif d.Name == "Claw" then
				claws += 1
			end
		end
	end
	assert(antlers >= 6 and eyes == 0 and claws == 6, string.format("antlers %d eyes %d claws %d", antlers, eyes, claws))
	assert(monster.PrimaryPart and monster.PrimaryPart.Name == "Root")
	local top = 0
	for _, d in ipairs(monster:GetDescendants()) do
		if d:IsA("BasePart") then
			top = math.max(top, d.CFrame.Position.Y)
		end
	end
	assert(top > 15, "the Antlered should tower over a kid (" .. top .. ")")
	local head = monster:FindFirstChild("Head")
	assert(head and head:FindFirstChild("Skull") and #head:GetChildren() >= 12, "no separate head to animate")
	local breath, crystals = false, 0
	for _, d in ipairs(monster:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.Name == "FrostBreath" then
			breath = true
		elseif d.Name == "Crystal" then
			crystals += 1
		end
	end
	assert(breath and crystals >= 5, "no frost breath / ice growths")
	local lighthouse, lamp = Models.lighthouse(CF.new(), nil)
	assert(lamp:FindFirstChild("LighthouseLight") and partsIn(lighthouse) >= 20, "lighthouse")
	assert(partsIn(Models.spire(CF.new(), nil)) >= 4, "spire")
	local block = Models.iceBlock(CF.new(), nil)
	assert(block.Block.CanCollide and block.Block.Transparency > 0.3, "ice block")
	local core, glow = Models.frozenCore(CF.new(), nil)
	assert(glow.Material == roblox.Enum.Material.Neon and core.Shell.CanCollide)
	local kid = Models.kid(CF.new(), nil, { Jacket = roblox.Color3.new(1, 0, 0), Scarf = roblox.Color3.new(0, 1, 0), Beanie = roblox.Color3.new(0, 0, 1) })
	assert(kid:FindFirstChild("Beanie") and kid:FindFirstChild("Lantern"))
end)

local world
check("shore camp builds: spawn, campfire, beacon, sled, hut, board, cliffs, water, part budget", function()
	local LobbyBuilder = requireModule(ServerRoot.World.LobbyBuilder)
	local t0 = os.clock()
	world = LobbyBuilder.build(workspaceService)
	local took = os.clock() - t0
	syncPositions(world.folder)
	assert(world.spawn:IsA("SpawnLocation") and world.spawn.Position.Z < L.ShoreZ, "spawn")
	assert(world.spawnCFrame.Position.Z < L.ShoreZ)
	assert(world.campfire and #world.fires == 1 and world.fires[1].Z < L.ShoreZ)
	assert(world.beacon.light and world.beacon.light.Name == "BeaconLight" and world.beacon.position.Z < L.ShoreZ)
	assert(world.sled.position.Z < L.ShoreZ and world.hut)
	assert(#world.boardRows == 10, "board rows")
	assert(world.folder.Scenery:FindFirstChild("Lakebed") and world.folder.Scenery:FindFirstChild("Water"))
	assert(world.folder.Scenery:FindFirstChild("FarBank") and world.pines >= 40, "cliffs / pines")
	local auroras = 0
	for _, d in ipairs(world.folder.Scenery:GetChildren()) do
		if d.Name == "Aurora" then
			auroras += 1
		end
	end
	assert(auroras >= 10, "aurora")
	assert(world.partCount < 2500, "shore parts " .. world.partCount)
	assert(took < 1.5, string.format("lobby build took %.2fs", took))
	print(string.format("        shore camp: %d parts, built in %.3fs (Lune)", world.partCount, took))
end)

check("lake builds incrementally: <= TilesPerStep tiles a frame, every tile has a slab, timed", function()
	local LakeBuilder = requireModule(ServerRoot.World.LakeBuilder)
	local lines = {}
	for i, diff in ipairs(GameConfig.DifficultyOrder) do
		local layout = LakeGen.generate(1000 + i, diff)
		local job = LakeBuilder.new(layout, workspaceService)
		local frames, worst, total = 0, 0, 0
		repeat
			local before = job.index
			local t0 = os.clock()
			local done = job:step(L.TilesPerStep)
			local dt = os.clock() - t0
			worst = math.max(worst, dt)
			total += dt
			frames += 1
			assert(job.index - before <= L.TilesPerStep, "built too many tiles in one frame")
		until done
		assert(frames >= math.ceil(#layout.order / L.TilesPerStep), "frames " .. frames)
		for _, t in ipairs(layout.order) do
			assert(t.part, "tile without a slab")
			if t.type == "water" then
				assert(not t.part.CanCollide and t.part.Transparency == 1, "hole is solid")
			else
				assert(t.part.CanCollide, "ice not walkable")
			end
		end
		assert(job.parts < 3200, diff .. " lake parts " .. job.parts)
		assert(total < 2, string.format("%s lake took %.2fs", diff, total))
		assert(worst < 0.03, string.format("%s worst build frame %.1f ms", diff, worst * 1000))
		local lighthouses, spires = 0, 0
		for _, d in ipairs(job.folder:GetDescendants()) do
			if d:IsA("Model") and d.Name == "Lighthouse" then
				lighthouses += 1
			elseif d:IsA("Model") and d.Name == "IceSpire" then
				spires += 1
			end
		end
		assert(lighthouses == 1 and spires == #layout.spires and spires >= 6, "Deep Hollow landmark missing")
		table.insert(lines, string.format("%s %d parts / %d frames / worst frame %.1fms", diff, job.parts, frames, worst * 1000))
		job:destroy()
	end
	print("        lake: " .. table.concat(lines, "; "))
end)

-- Remote stubs that record traffic.
local log = {}
local function stubRemote(name)
	log[name] = {}
	return {
		FireAllClients = function(_, ...)
			table.insert(log[name], { all = true, args = table.pack(...) })
		end,
		FireClient = function(_, player, ...)
			table.insert(log[name], { player = player, args = table.pack(...) })
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
local ORDER = { "DataService", "NoiseService", "WeatherService", "SurvivalService", "IceService", "ObjectiveService", "MonsterService", "RewardService", "ShopService", "PlayerService", "RoundService", "LeaderboardService" }
check("services initialise and start (same order as Main.server)", function()
	registry = { Remotes = remotes }
	for _, name in ipairs(ORDER) do
		registry[name] = requireModule(Services[name])
	end
	for _, name in ipairs(ORDER) do
		registry[name].init(registry)
	end
	for _, name in ipairs(ORDER) do
		if registry[name].setWorld then
			registry[name].setWorld(world)
		end
	end
	for _, name in ipairs(ORDER) do
		if name ~= "DataService" and registry[name].start then
			registry[name].start()
		end
	end
	registry.DataService.start()
	assert(type(stubServices.MarketplaceService.ProcessReceipt) == "function", "ProcessReceipt not bound")
end)

local nextUserId = 3000
local function setPos(part, position)
	part.CFrame = CF.new(position)
	part.Position = position
end
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
	root.Size = V3.new(2, 2, 1)
	setPos(root, position or world.spawnCFrame.Position)
	root.AssemblyLinearVelocity = V3.new()
	root.Parent = character
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Size = V3.new(2, 1, 1)
	setPos(head, root.Position + V3.new(0, 1.5, 0))
	head.Parent = character
	local humanoid = roblox.Instance.new("Humanoid")
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
	flushDeferred()
end

local DS, RSv, SS, IS, OS, MS, NS, WS
local DT = 1 / 30
-- Advances the fake clock in 1/30 s steps, running the same Heartbeat work as Main.server.
-- `script(dt)` runs first each step to move characters (Lune has no physics).
local function tick(seconds, script)
	local t = 0
	while t < seconds - 1e-9 do
		advance(DT)
		t += DT
		if script then
			script(DT)
		end
		RSv.step(DT)
	end
	flushDeferred()
end
-- Moves a root at a constant velocity (flat) every step.
local function walker(root, velocity)
	return function(dt)
		setPos(root, root.Position + velocity * dt)
	end
end
local function both(a, b)
	return function(dt)
		a(dt)
		b(dt)
	end
end
local function tileAt(position)
	return IS.tileAt(position)
end
local function cellPos(c, r, y)
	local x, z = LakeGen.cellToWorld(c, r)
	return V3.new(x, y or (L.IceTop + 3), z)
end
local function putAt(player, position)
	SS.moveTo(player, CF.new(position))
end
-- Starts a round with everyone in the lobby ready; returns when it is Running.
local function startRound(votesFor)
	for _, p in ipairs(playerList) do
		if p.Parent and DS.getProfile(p) then
			if votesFor then
				remotes.Vote.OnServerEvent:Fire(p, votesFor)
			end
			RSv.setReady(p, true)
		end
	end
	tick(DT)
	assert(RSv.phase() == "Countdown", "no countdown: " .. RSv.phase())
	tick(GameConfig.Round.Countdown + DT)
	local frames = 0
	while RSv.phase() == "Preparing" do
		tick(DT)
		frames += 1
		assert(frames < 200, "lake never finished building")
	end
	assert(RSv.phase() == "Running", "not running: " .. RSv.phase())
	return RSv.run(), frames
end

local alice, aliceRoot, bob, bobRoot
check("player joins: default profile, tags, look (beanie, scarf, lantern), told saving is off", function()
	DS, RSv, SS, IS, OS, MS, NS, WS = registry.DataService, registry.RoundService, registry.SurvivalService, registry.IceService, registry.ObjectiveService, registry.MonsterService, registry.NoiseService, registry.WeatherService
	alice, aliceRoot = makePlayer("Alice")
	local p = DS.getProfile(alice)
	assert(p and p.Coins == 0 and p.Cosmetics.Outfit == "Classic" and p.Boosts.Flask == 0, "bad default profile")
	assert(not DS.isPersistent(alice))
	assert(count("Notify", "saving is unavailable", alice) >= 1, "not told that saving is off")
	assert(alice:GetAttribute("TI_Level") == 1 and alice:GetAttribute("TI_VIP") == false, "tags")
	local look = alice.Character:FindFirstChild("TI_Look")
	assert(look and look:FindFirstChild("Beanie") and look:FindFirstChild("Scarf") and look:FindFirstChild("Lantern"), "look not applied")
	for _, d in ipairs(look:GetChildren()) do
		assert(not d.CanCollide and not d.CanTouch and d.Massless and d:FindFirstChildOfClass("WeldConstraint"), d.Name .. " not inert")
	end
	assert(alice:FindFirstChild("leaderstats") and alice.leaderstats.Level.Value == 1)
	assert(lastFor("RoundState", alice) or count("RoundState") > 0, "round state not sent")
end)

local buildFrames
check("lobby: vote (ties go easier), ready, countdown, lake built over many frames, team on the dock", function()
	bob, bobRoot = makePlayer("Bob")
	remotes.Vote.OnServerEvent:Fire(alice, "Hard")
	remotes.Vote.OnServerEvent:Fire(bob, "Easy")
	assert(RSv.tally() == "Easy", "tie did not go to the easier difficulty")
	remotes.Vote.OnServerEvent:Fire(bob, "Hard")
	remotes.Vote.OnServerEvent:Fire(bob, "Impossible")
	assert(RSv.tally() == "Hard")
	remotes.Vote.OnServerEvent:Fire(bob, "Normal")
	assert(RSv.tally() == "Normal" or RSv.tally() == "Hard")
	remotes.Vote.OnServerEvent:Fire(alice, "Normal")
	assert(RSv.tally() == "Normal")
	RSv.setReady(alice, true)
	tick(1)
	assert(RSv.phase() == "Lobby", "started with only half ready")
	assert(RSv.state().autoStartIn and RSv.state().ready == 1, "auto-start timer not shown")
	-- Bob un-readies everyone? no - Bob readies: everyone is ready -> countdown.
	local run
	run, buildFrames = startRound(nil)
	assert(run.difficulty == "Normal", run.difficulty)
	assert(buildFrames >= math.ceil(#run.layout.order / L.TilesPerStep) - 1, "lake built in " .. buildFrames .. " frames")
	assert(run.players[alice] and run.players[bob], "players not in the run")
	assert(aliceRoot.Position.Z < L.ShoreZ and aliceRoot.Position.Z > L.ShoreZ - 8, "not gathered on the dock")
	assert(alice:GetAttribute("TI_Warmth") == 100 and alice:GetAttribute("TI_State") == "Active" and alice:GetAttribute("TI_Snowballs") == GameConfig.Snowball.Start)
	assert(count("Announce", "ice is forming") >= 1 and count("Announce", "frozen cores") >= 1)
	assert(#OS.cores() == GameConfig.Difficulties.Normal.Cores, "cores not placed")
	assert(MS.brain().state == "Dormant" and MS.model(), "monster not sleeping under the ice")
	assert(MS.model():GetPivot().Position.Y < 0, "monster visible before waking")
	print(string.format("        Normal lake built over %d frames (TilesPerStep %d), build %.2fs of game time", buildFrames, L.TilesPerStep, run.buildTime))
end)

check("late joiner waits on the shore; anyone off-round is kept off the ice", function()
	local carl, carlRoot = makePlayer("Carl")
	assert(not RSv.run().players[carl], "late joiner pulled into the round")
	setPos(carlRoot, cellPos(8, 3))
	tick(DT)
	assert(carlRoot.Position.Z < L.ShoreZ, "spectator walked onto the ice")
	assert(count("Notify", "underway", carl) >= 1)
	leave(carl)
end)

check("stamina: sprinting drains and exhausts; speed check snaps back a teleport", function()
	putAt(alice, cellPos(2, 0))
	tick(0.2)
	remotes.SetMoveMode.OnServerEvent:Fire(alice, "Sprint")
	local rec = SS.record(alice)
	assert(rec.mode == "Sprint")
	tick(2, walker(aliceRoot, V3.new(GameConfig.Move.Sprint, 0, 0)))
	assert(rec.effective == "Sprint" and rec.stamina < 70, "not sprinting / draining: " .. rec.stamina)
	-- back and forth along the safe rows until exhausted
	local dir = -1
	for _ = 1, 6 do
		putAt(alice, cellPos(if dir < 0 then 13 else 2, 1))
		tick(2.2, walker(aliceRoot, V3.new(dir * GameConfig.Move.Sprint, 0, 0)))
		dir = -dir
		if rec.exhausted then
			break
		end
	end
	assert(rec.exhausted and rec.effective == "Walk", "never exhausted")
	assert(alice.Character.Humanoid.WalkSpeed == GameConfig.Move.Walk, "walk speed not applied")
	remotes.SetMoveMode.OnServerEvent:Fire(alice, "Walk")
	remotes.SetMoveMode.OnServerEvent:Fire(alice, "Fly")
	assert(rec.mode == "Walk", "junk mode accepted")
	-- teleport hack
	local before = rec.violations
	local start = aliceRoot.Position
	tick(0.6)
	setPos(aliceRoot, start + V3.new(0, 0, 60))
	tick(0.6)
	assert(rec.violations > before, "teleport not caught")
	assert((aliceRoot.Position - start).Magnitude < 5, "not snapped back")
end)

check("footsteps: sprint is loud, sneak is near-silent, standing still is silent", function()
	local rec = SS.record(alice)
	rec.stamina, rec.exhausted = 100, false
	putAt(alice, cellPos(2, 1))
	tick(0.6)
	local function steps(mode, speed, seconds)
		remotes.SetMoveMode.OnServerEvent:Fire(alice, mode)
		putAt(alice, cellPos(2, 1))
		tick(0.6)
		local before = { StepSneak = NS.count("StepSneak"), StepWalk = NS.count("StepWalk"), StepSprint = NS.count("StepSprint") }
		local logBefore = #NS.log
		tick(seconds, if speed > 0 then walker(aliceRoot, V3.new(speed, 0, 0)) else nil)
		return before, logBefore
	end
	local b = steps("Sprint", GameConfig.Move.Sprint, 1.5)
	assert(NS.count("StepSprint") > b.StepSprint, "no sprint steps")
	b = steps("Sneak", GameConfig.Move.Sneak, 1.5)
	assert(NS.count("StepSneak") > b.StepSneak and NS.count("StepSprint") == b.StepSprint, "sneak made sprint noise")
	local _, logBefore = steps("Walk", 0, 2)
	for i = logBefore + 1, #NS.log do
		assert(NS.log[i].source ~= alice or not string.find(NS.log[i].category, "Step", 1, true), "standing still made footsteps")
	end
	assert(count("WorldSound", "StepSprint") == 0, "footsteps broadcast to every client")
end)

local function findTile(pred)
	for _, t in ipairs(RSv.run().layout.order) do
		if pred(t) then
			return t
		end
	end
	return nil
end

check("ice: sprinting on thin ice cracks it (loud), breaks it, you fall in, climb out, it refreezes", function()
	local tile = findTile(function(t)
		return t.type == "ice" and t.thick == 1 and not IS.solid(t)
	end)
	assert(tile, "no thin ice on this lake")
	local rec = SS.record(alice)
	rec.stamina, rec.exhausted = 100, false
	remotes.SetMoveMode.OnServerEvent:Fire(alice, "Sprint")
	local center = cellPos(tile.c, tile.r)
	putAt(alice, center + V3.new(-3, 0, 0))
	local cracks = NS.count("Crack")
	-- jog back and forth across the tile
	local t = 0
	local function jog(dt)
		t += dt
		local x = center.X + math.sin(t * 6) * 3
		setPos(aliceRoot, V3.new(x, center.Y, center.Z))
	end
	local guard = 0
	while tile.type ~= "water" and guard < 200 do
		tick(DT, jog)
		guard += 1
	end
	assert(tile.type == "water", "thin ice never broke")
	assert(NS.count("Crack") > cracks, "no crack noise")
	assert(count("WorldSound", "Break") >= 1, "no break sound")
	assert(guard * DT < 4, "thin ice took " .. guard * DT .. "s")
	tick(DT * 2, jog)
	assert(rec.inWater and alice:GetAttribute("TI_InWater") == true, "not in the water")
	assert(NS.count("Splash") >= 1, "no splash")
	local warmth = rec.warmth
	tick(GameConfig.Warmth.ClimbOutTime + 0.2)
	assert(not rec.inWater, "never climbed out")
	assert(rec.warmth < warmth - 15, "water barely chilled: " .. warmth .. " -> " .. rec.warmth)
	local now = tileAt(aliceRoot.Position)
	assert(now and LakeGen.walkable(now), "climbed out onto nothing")
	assert(now.type == "ice", "climbed out into a brazier")
	-- a stale client position (sent before it got the climb-out move) must not drop her back in
	local outAt = aliceRoot.Position
	setPos(aliceRoot, center)
	tick(DT * 2)
	assert(not rec.inWater, "stale position dropped her back in the hole")
	setPos(aliceRoot, outAt)
	tick(DT)
	putAt(alice, world.spawnCFrame.Position + V3.new(0, 0, 30)) -- warm up on the shore meanwhile
	tick(GameConfig.Ice.RefreezeAfter + 0.5)
	assert(tile.type == "ice" and tile.thick == 1 and tile.part.CanCollide, "did not refreeze as thin ice")
	remotes.SetMoveMode.OnServerEvent:Fire(alice, "Walk")
end)

check("warmth: drains on the ice, a brazier and the shore warm you up", function()
	local rec = SS.record(alice)
	local safe = findTile(function(t)
		return t.type == "ice" and t.r >= 2 and t.r <= 4 and not t.drift and not SS.fireNear(cellPos(t.c, t.r))
	end)
	putAt(alice, cellPos(safe.c, safe.r))
	rec.warmth = 80
	tick(3)
	assert(rec.warmth < 80 - 3 * GameConfig.Warmth.IceDrain * 0.9, "no drain on the ice")
	local brazier = RSv.run().layout.braziers[1]
	putAt(alice, cellPos(brazier.c, brazier.r) + V3.new(4, 0, 0))
	local w = rec.warmth
	tick(2)
	assert(rec.warmth > w + 10, "brazier did not warm")
	putAt(alice, world.spawnCFrame.Position + V3.new(0, 0, 20))
	rec.warmth = 60
	w = rec.warmth
	tick(2)
	assert(rec.warmth > w, "shore did not warm")
end)

check("snowballs: thrown lure makes a loud noise far away with no source; cooldown, empty, junk", function()
	local rec = SS.record(alice)
	putAt(alice, cellPos(8, 1))
	tick(0.2)
	local n = rec.snowballs
	local before = NS.count("Snowball")
	remotes.Throw.OnServerEvent:Fire(alice, V3.new(0, 0, 1))
	assert(rec.snowballs == n - 1 and NS.count("Snowball") == before + 1, "throw failed")
	local entry = NS.log[#NS.log]
	assert(entry.category == "Snowball" and entry.source == nil, "lure carries the thrower")
	assert(entry.position.Z > aliceRoot.Position.Z + 30, "lure landed too close")
	assert(count("WorldSound", "Throw") >= 1, "no throw arc for clients")
	remotes.Throw.OnServerEvent:Fire(alice, V3.new(0, 0, 1))
	assert(rec.snowballs == n - 1, "cooldown ignored")
	for _, junk in ipairs({ "x", V3.new(0 / 0, 0, 0), V3.new(0, 1, 0), V3.new(math.huge, 0, 0) }) do
		tick(1)
		remotes.Throw.OnServerEvent:Fire(alice, junk)
	end
	assert(rec.snowballs == n - 1, "junk direction thrown")
	-- the lure lands inside the lake even when thrown at the cliffs
	tick(1)
	remotes.Throw.OnServerEvent:Fire(alice, V3.new(1, 0, 0))
	local last = NS.log[#NS.log]
	assert(last.position.X <= L.Columns * L.TileSize / 2, "lure landed in the cliff")
	rec.snowballs = 0
	tick(1)
	remotes.Throw.OnServerEvent:Fire(alice, V3.new(0, 0, 1))
	assert(count("Notify", "No snowballs", alice) >= 1)
	-- refill at a drift
	local drift = RSv.run().layout.drifts[1]
	putAt(alice, cellPos(drift.c, drift.r) + V3.new(2, 0, 0))
	tick(0.3)
	assert(rec.snowballs == GameConfig.Snowball.Max, "drift did not refill")
end)

check("the Antlered: asleep for the grace period, wakes, hears sprinting, hunts, catches = frozen", function()
	local run = RSv.run()
	-- (it was checked asleep right after the start; the ice tests above took longer than the grace period)
	local remaining = run.wakeAt - fakeOs.clock()
	if remaining > 0 then
		tick(remaining + 0.3)
	end
	assert(MS.brain():awake(), "never woke")
	assert(count("MonsterCue", "Wake") >= 1 and count("Announce", "woke up") >= 1)
	assert(MS.model():GetPivot().Position.Y >= L.IceTop - 0.1, "still under the ice")
	WS.startRun() -- calm air for this test (a whiteout would halve its hearing)
	-- Bob sprints near it.
	local rec = SS.record(bob)
	rec.stamina, rec.exhausted = 100, false
	local spot = findTile(function(t)
		return t.type == "ice" and t.r >= 12 and t.r <= 20 and t.c >= 4 and t.c <= 11 and not IS.solid(t)
	end)
	local p = cellPos(spot.c, spot.r)
	MS.place(p + V3.new(14, 0, 0))
	putAt(bob, p)
	remotes.SetMoveMode.OnServerEvent:Fire(bob, "Sprint")
	local hunted = false
	local t = 0
	tick(1.5, function(dt)
		t += dt
		setPos(bobRoot, p + V3.new(math.sin(t * 4) * 2, 0, 0))
		if MS.brain().state == "Hunt" and MS.brain().target == bob then
			hunted = true
		end
	end)
	assert(hunted, "sprinting next to it did not start a hunt (" .. MS.brain().state .. ")")
	assert(count("MonsterCue", "Hunt") >= 1)
	remotes.SetMoveMode.OnServerEvent:Fire(bob, "Walk")
	-- it closes in and catches him
	local guard = 0
	while rec.state == "Active" and guard < 300 do
		tick(DT)
		guard += 1
	end
	assert(rec.state == "Frozen", "never caught Bob")
	assert(bob:GetAttribute("TI_State") == "Frozen" and rec.block and rec.block.Parent, "no ice block")
	assert(rec.prompt and rec.prompt.HoldDuration == GameConfig.Warmth.ThawHold, "no thaw prompt")
	assert(lastFor("MonsterCue", bob).args[1] == "Caught", "Bob got no scare cue")
	assert(MS.brain().state == "Recover", "no recovery pause after the catch")
	assert(bob.Character.HumanoidRootPart.Anchored, "frozen player can move")
	assert(count("Notify", "caught by the Antlered", alice) >= 1, "team not told")
end)

check("thaw: a friend holds E beside the block; you stand up next to them; rescue counted; too far refused", function()
	local rec = SS.record(bob)
	local blockPos = bobRoot.Position
	MS.place(blockPos + V3.new(60, 0, 60))
	putAt(alice, blockPos + V3.new(40, 0, 0))
	assert(not SS.tryThaw(alice, bob), "thawed from 40 studs")
	rec.prompt.Triggered:Fire(bob)
	assert(rec.state == "Frozen", "thawed himself")
	putAt(alice, blockPos + V3.new(4, 0, 0))
	rec.prompt.Triggered:Fire(alice)
	assert(rec.state == "Active" and math.abs(rec.warmth - GameConfig.Warmth.ThawTo) < 1e-6, "not thawed")
	assert(not bobRoot.Anchored and not rec.block, "still in the block")
	assert((bobRoot.Position - aliceRoot.Position).Magnitude < 4, "did not stand up beside the rescuer")
	assert(SS.record(alice).rescues == 1 and DS.getProfile(alice).Stats.Rescues == 1, "rescue not counted")
	assert(NS.count("Thaw") >= 1, "thawing made no noise")
end)

check("the Antlered's weight cracks the ice behind it (bounded trail); it flags who it hunts", function()
	local brain = MS.brain()
	tick(GameConfig.Monster.RecoverTime + 0.5)
	MS.place(cellPos(13, 20))
	local arec = SS.record(alice)
	if arec.state == "Frozen" then
		SS.thaw(alice, nil)
	end
	putAt(alice, cellPos(13, 44 - 4))
	brain.state = "Hunt"
	brain.target = alice
	brain.goal = cellPos(13, 40)
	brain.lastHeardAt = fakeOs.clock()
	brain.since = fakeOs.clock()
	tick(0.3)
	assert(MS.model():GetAttribute("TI_Target") == alice.UserId, "hunted player not flagged")
	tick(2.5, function()
		brain.lastHeardAt = fakeOs.clock()
	end)
	local trail = MS.trailTiles()
	assert(#trail >= 3 and #trail <= GameConfig.Monster.TrailLength, "trail " .. #trail)
	local cracked = 0
	for _, t in ipairs(trail) do
		if t.part and t.part:FindFirstChild("Cracks") then
			cracked += 1
		end
	end
	-- (older trail tiles may have healed / refrozen from earlier stress in this round)
	assert(cracked >= 3, "trail tiles without cracks: " .. cracked .. "/" .. #trail)
	-- it cracks, but doesn't stress, the ice (purely a warning sign)
	local newest = trail[#trail]
	assert(LakeGen.walkable(newest) and (newest.stress or 0) == 0, "its weight stressed the ice")
	brain:caught(fakeOs.clock())
	tick(0.3)
	assert(MS.model():GetAttribute("TI_Target") == 0, "still flagged after the catch pause")
	putAt(alice, cellPos(3, 1))
end)

check("whiteout: 15-20 s, it hears half as much but moves faster; chills you faster", function()
	local brain = MS.brain()
	tick(GameConfig.Monster.RecoverTime + 0.5)
	WS.startRun() -- calm
	local calm = registry.MonsterService
	-- How far it gets hunting a far-off sound in 1 s (calm, then in a whiteout).
	local function stride()
		local from = MS.position()
		local goal = MS.clampToLake(from + V3.new(0, 0, if from.Z > 300 then -120 else 120))
		brain.state = "Hunt"
		brain.goal = goal
		brain.target = nil
		brain.lastHeardAt = fakeOs.clock()
		brain.since = fakeOs.clock()
		tick(1)
		return (MS.position() - from).Magnitude
	end
	MS.place(cellPos(13, 20))
	local calmStride = stride()
	local mpos = MS.position()
	local lure = mpos + V3.new(22, 0, 0)
	local loudCalm = requireModule(Shared.IceMath).perceived("Snowball", 22, MS.hearing())
	assert(loudCalm >= GameConfig.Noise.HuntThreshold, "test lure too quiet " .. loudCalm)
	WS.forceGust()
	tick(DT)
	assert(WS.gusting() and workspaceService:GetAttribute("TI_Gust") == true, "no whiteout")
	assert(count("Announce", "WHITEOUT") >= 1)
	local ends = workspaceService:GetAttribute("TI_GustEnds") - workspaceService:GetServerTimeNow()
	assert(ends >= GameConfig.Weather.WhiteoutMin - 0.1 and ends <= GameConfig.Weather.WhiteoutMax + 0.1, "whiteout length " .. ends)
	assert(math.abs(MS.hearing() - RSv.run().diff.MonsterHearing * GameConfig.Noise.GustHearing) < 1e-6)
	brain.state = "Prowl"
	brain.target = nil
	calm.hear("Snowball", lure, nil)
	assert(brain.state ~= "Hunt", "hunted through a whiteout")
	MS.place(cellPos(13, 20))
	local gustStride = stride()
	assert(gustStride > calmStride * 1.15, string.format("not faster in the whiteout: %.1f vs %.1f", gustStride, calmStride))
	-- warmth drains faster out on the ice in a whiteout
	local rec = SS.record(alice)
	putAt(alice, cellPos(3, 1))
	rec.warmth = 80
	tick(1)
	local gustLoss = 80 - rec.warmth
	tick(GameConfig.Weather.WhiteoutMax + 0.5)
	assert(not WS.gusting(), "whiteout never ended")
	rec.warmth = 80
	putAt(alice, cellPos(3, 1))
	tick(1)
	assert(gustLoss > 80 - rec.warmth, "whiteout did not chill")
	brain.state = "Prowl"
	calm.hear("Snowball", MS.position() + V3.new(22, 0, 0), nil)
	assert(brain.state == "Hunt" and brain.target == nil, "calm lure did not draw a hunt at the lure")
end)

check("flask: thaws you once after a delay; frozen too long = lost, sent to the shore", function()
	local rec = SS.record(bob)
	if rec.state == "Frozen" then
		SS.thaw(bob, nil) -- (the Antlered may have come back for him)
	end
	DS.getProfile(bob).Boosts.Flask = 1
	local arec = SS.record(alice)
	if arec.state == "Frozen" then
		SS.thaw(alice, nil)
	end
	putAt(alice, world.fires[1] + V3.new(4, 3, 0)) -- Alice waits by the campfire (the shore is safe)
	putAt(bob, cellPos(12, 1))
	MS.place(cellPos(2, 30))
	MS.brain():caught(fakeOs.clock()) -- keep it busy
	rec.warmth = 0.01
	tick(DT * 2)
	assert(rec.state == "Frozen", "did not freeze from cold")
	assert(count("Notify", "Thermos Flask will", bob) >= 1, "not told about the flask")
	tick(GameConfig.Warmth.FlaskDelay + 0.2)
	assert(rec.state == "Active" and rec.flaskUsed and DS.getProfile(bob).Boosts.Flask == 0, "flask did not thaw")
	rec.warmth = 0.01
	tick(DT * 2)
	assert(rec.state == "Frozen")
	tick(GameConfig.Warmth.FlaskDelay + 1)
	assert(rec.state == "Frozen", "flask used twice")
	tick(GameConfig.Warmth.FrozenLostAfter)
	assert(rec.state == "Lost" and bob:GetAttribute("TI_State") == "Lost", "never lost")
	assert(bobRoot.Position.Z < L.ShoreZ and not bobRoot.Anchored, "lost player left on the ice")
	assert(RSv.phase() == "Running" and arec.state == "Active", "round ended while Alice waited at the fire")
end)

check("cores: chip (loud) -> carry -> fall in drops it -> pick up -> deliver at the beacon; all in -> sled", function()
	local run = RSv.run()
	local rec = SS.record(alice)
	if rec.state == "Frozen" then
		SS.thaw(alice, nil) -- (the Antlered wanders: it may have caught her meanwhile)
	end
	rec.warmth = 100
	MS.place(V3.new(0, 0, 300))
	local cores = OS.cores()
	local first = cores[1]
	local chips = NS.count("Chip")
	putAt(alice, first.position + V3.new(30, 3, 0))
	first.prompt.Triggered:Fire(alice)
	assert(first.state == "Sealed", "chipped from far away")
	putAt(alice, first.position + V3.new(3, 3, 0))
	first.prompt.PromptButtonHoldBegan:Fire(alice)
	assert(NS.count("Chip") == chips + 1, "chipping is silent")
	first.prompt.Triggered:Fire(alice)
	assert(first.state == "Carried" and rec.carrying == first and alice:GetAttribute("TI_Carrying") ~= nil)
	assert(first.shard and first.shard:FindFirstChild("Shard"):FindFirstChildOfClass("WeldConstraint"), "shard not welded to the carrier")
	assert(count("Notify", "chipped out a core", bob) >= 1, "team not told")
	tick(DT)
	assert(alice:GetAttribute("TI_Carrying") == true, string.format("state %s water %s carrying %s core %s", rec.state, tostring(rec.inWater), tostring(rec.carrying), first.state))
	-- falling in drops it
	local hole = findTile(function(t)
		return t.type == "water" and t.r >= 2
	end)
	if not hole then
		hole = findTile(function(t)
			return t.type == "ice" and not IS.solid(t) and t.r >= 3
		end)
		IS.forceBreak(hole)
	end
	putAt(alice, cellPos(hole.c, hole.r))
	tick(DT * 2)
	assert(first.state == "Dropped" and rec.carrying == nil, "fell in still holding the core")
	assert(LakeGen.walkable(tileAt(first.position)), "core dropped into the water")
	tick(GameConfig.Warmth.ClimbOutTime + 0.3)
	rec.warmth = 100
	putAt(alice, first.position + V3.new(2, 3, 0))
	first.prompt.Triggered:Fire(alice)
	assert(first.state == "Carried", "could not pick it back up")
	-- deliver
	putAt(alice, world.beacon.position + V3.new(6, 3, 0))
	tick(DT * 2)
	assert(first.state == "Delivered" and run.delivered == 1 and rec.cores == 1, "not delivered")
	assert(world.beacon.light.Brightness > 0.2, "beacon did not light up")
	local beam = world.beacon.model.BeaconBeam
	assert(beam.Transparency < 1 and beam.Transparency > 0.5, "no faint beam after one core")
	assert(DS.getProfile(alice).Stats.Cores == 1 and count("Announce", "Core delivered") >= 1)
	-- the rest
	for i = 2, #cores do
		local core = cores[i]
		putAt(alice, core.position + V3.new(2, 3, 0))
		core.prompt.Triggered:Fire(alice)
		assert(core.state == "Carried", "core " .. i)
		putAt(alice, world.beacon.position + V3.new(4, 3, 0))
		tick(DT * 2)
		assert(core.state == "Delivered", "core " .. i .. " not delivered")
	end
	assert(RSv.phase() == "Sled", "sled not ready: " .. RSv.phase())
	assert(count("Announce", "ALL CORES IN! Get to the sled") >= 1, "no all-cores announcement")
	assert(world.beacon.light.Brightness >= 3, "beacon not fully lit")
	assert(math.abs(world.beacon.model.BeaconBeam.Transparency - 0.35) < 1e-6, "beam not blazing when all cores are in")
	-- the sled horn sounds 10 s before it leaves (Alice waits at the beacon)
	local horns = count("WorldSound", "Horn")
	tick(GameConfig.Round.SledWait - GameConfig.Round.SledHornAt + 0.3)
	assert(RSv.phase() == "Sled" and count("WorldSound", "Horn") == horns + 1, "no horn at 10 s")
	assert(count("Announce", "The sled leaves in 10 seconds") >= 1)
end)

check("escape: reach the sled -> results (escaped, paid, stat), lake cleared, back to camp", function()
	local run = RSv.run()
	putAt(alice, world.sled.position + V3.new(3, 3, 0))
	tick(DT * 2)
	assert(SS.record(alice).state == "Escaped", "not escaped")
	-- Bob is lost, Alice escaped: nobody active -> the sled leaves.
	tick(DT)
	assert(RSv.phase() == "Results", "round did not end: " .. RSv.phase())
	local result = lastFor("Results", alice).args[1]
	assert(result.outcome == "Escaped" and result.coins > 0 and result.delivered == run.total, "bad result")
	assert(DS.getProfile(alice).Stats.Escapes == 1 and DS.getProfile(alice).Coins >= result.coins)
	assert(count("WorldSound", "Horn") >= 2, "no horn as the sled pulls away")
	local mine
	for _, row in ipairs(result.team) do
		if row.userId == alice.UserId then
			mine = row
		end
	end
	assert(mine and mine.cores == run.total and mine.rescues == 1 and mine.state == "Escaped" and mine.freezes ~= nil, "per-player stats missing from results")
	local bobResult = lastFor("Results", bob).args[1]
	assert(bobResult.outcome == "LeftBehind" and bobResult.coins > 0 and bobResult.coins < result.coins, "lost player paid like an escapee")
	assert(DS.getProfile(alice).Xp > 0)
	tick(GameConfig.Round.ResultsTime + 0.1)
	assert(RSv.phase() == "Lobby" and RSv.run() == nil, "not back in the lobby")
	assert(not run.folder.Parent, "lake not cleared")
	assert(aliceRoot.Position.Z < L.ShoreZ and bobRoot.Position.Z < L.ShoreZ, "not sent back to camp")
	assert(alice:GetAttribute("TI_Warmth") == nil, "round attributes left behind")
	assert(MS.brain() == nil and not WS.gusting())
end)

check("a round always ends: everyone frozen", function()
	local run = startRound("Easy")
	assert(run.difficulty == "Easy")
	SS.freeze(alice, "cold")
	SS.freeze(bob, "cold")
	tick(DT)
	assert(RSv.phase() == "Results", "did not end with everyone frozen")
	assert(count("Announce", "Everyone froze on the ice.") >= 1)
	local result = lastFor("Results", alice).args[1]
	assert(result.outcome == "Failed" and result.coins == GameConfig.Rewards.Played, "fail reward " .. tostring(result.coins))
	tick(GameConfig.Round.ResultsTime + 0.1)
	assert(RSv.phase() == "Lobby")
end)

check("a round always ends: time limit", function()
	local run = startRound("Nightmare")
	run.endsAt = fakeOs.clock() + 1
	tick(1.2)
	assert(RSv.phase() == "Results", "time limit ignored")
	assert(lastFor("Results", bob).args[1].outcome == "Failed")
	tick(GameConfig.Round.ResultsTime + 0.1)
end)

check("the Antlered walks the ice: around holes and rocks (never over them), and never stays stuck", function()
	local run = startRound("Hard")
	local tiles = run.layout.tiles
	-- A wall of open water across row 15 with one gap at column 6.
	for c = 0, L.Columns - 1 do
		local t = tiles[LakeGen.key(c, 15)]
		if c == 6 then
			t.type, t.thick = "ice", 2
		elseif t.type ~= "water" then
			IS.forceBreak(t)
		end
		for _, r in ipairs({ 14, 16 }) do
			local u = tiles[LakeGen.key(c, r)]
			if u.type ~= "ice" and u.type ~= "brazier" then
				u.type, u.thick = "ice", 2 -- keep the approach open
			end
		end
	end
	local goal = cellPos(2, 18, L.IceTop)
	tiles[LakeGen.key(2, 12)].type = "ice"
	tiles[LakeGen.key(2, 18)].type = "ice"
	MS.place(cellPos(2, 12))
	local brain = MS.brain()
	brain.opts.wakeAt = 0
	tick(0.2)
	brain:_enter("Prowl", fakeOs.clock(), "test")
	brain.goal = goal
	local sawGap, maxStep, last = false, 0, MS.position()
	local guard = 0
	while brain.state == "Prowl" and guard < 30 * 40 do
		tick(DT, function()
			brain.goal = goal -- (keep the test's goal; prowl picks its own otherwise)
		end)
		guard += 1
		local p = MS.position()
		local c, r = LakeGen.worldToCell(p.X, p.Z)
		assert(c and LakeGen.walkable(tiles[LakeGen.key(c, r)]), string.format("walked onto %s at %d,%d", tostring(c and tiles[LakeGen.key(c, r)].type), c or -1, r or -1))
		if r == 15 then
			sawGap = sawGap or c == 6
		end
		maxStep = math.max(maxStep, (p - last).Magnitude)
		last = p
	end
	assert(brain.state == "Listen", "never got round the wall: " .. brain.state .. " at " .. tostring(MS.position()))
	assert(sawGap, "did not go through the gap")
	assert(maxStep < 2, "it teleported " .. maxStep)
	local path = MS.path()
	assert(type(path) == "table")
	-- Sealed on an island: it dives and resurfaces on shore-connected ice.
	local island = { c = 10, r = 25 }
	for dc = -1, 1 do
		for dr = -1, 1 do
			local t = tiles[LakeGen.key(island.c + dc, island.r + dr)]
			if dc == 0 and dr == 0 then
				t.type, t.thick = "ice", 2
			elseif t.type ~= "water" then
				IS.forceBreak(t)
			end
		end
	end
	MS.place(cellPos(island.c, island.r))
	brain:_enter("Prowl", fakeOs.clock(), "test")
	brain.goal = cellPos(2, 4, L.IceTop)
	tick(GameConfig.Monster.StuckTime + 3)
	local p = MS.position()
	local c, r = LakeGen.worldToCell(p.X, p.Z)
	assert(not (c == island.c and r == island.r), "stuck on the island forever")
	assert(LakeGen.walkable(tiles[LakeGen.key(c, r)]), "resurfaced on " .. tiles[LakeGen.key(c, r)].type)
	SS.freeze(alice, "cold")
	SS.freeze(bob, "cold")
	tick(DT)
	assert(RSv.phase() == "Results")
	tick(GameConfig.Round.ResultsTime + 0.1)
end)

check("leaving mid-round drops the core; character reset = lost; everyone leaving aborts", function()
	local dana = makePlayer("Dana")
	local run = startRound("Normal")
	assert(run.players[dana])
	local core = OS.cores()[1]
	putAt(dana, core.position + V3.new(2, 3, 0))
	core.prompt.Triggered:Fire(dana)
	assert(core.state == "Carried")
	leave(dana)
	assert(core.state == "Dropped" and core.model and core.model.Parent, "core vanished with the leaver")
	tick(DT)
	assert(RSv.phase() == "Running", "round ended when one player left")
	-- Bob carries a core out on the ice and dies (reset): it drops where he fell, not at spawn
	local second = OS.cores()[2]
	putAt(bob, second.position + V3.new(2, 3, 0))
	second.prompt.Triggered:Fire(bob)
	assert(second.state == "Carried", "bob could not take the core")
	local fellAt = second.position + V3.new(0, 3, 6)
	putAt(bob, fellAt)
	bob.Character.Humanoid.Died:Fire()
	assert(second.state == "Dropped" and second.model and second.model.Parent, "core vanished with the dead carrier")
	assert(second.position.Z >= L.ShoreZ and (second.position - fellAt).Magnitude < 12, "core dropped away from where he died: " .. tostring(second.position))
	assert(SS.record(bob).state == "Lost", "death did not count as lost")
	-- Bob resets his character
	local newChar = roblox.Instance.new("Model")
	local newRoot = roblox.Instance.new("Part")
	newRoot.Name = "HumanoidRootPart"
	setPos(newRoot, world.spawnCFrame.Position)
	newRoot.Parent = newChar
	roblox.Instance.new("Humanoid").Parent = newChar
	newChar.PrimaryPart = newRoot
	newChar.Parent = workspaceService
	bob.Character = newChar
	bob.CharacterAdded:Fire(newChar)
	flushDeferred()
	assert(SS.record(bob).state == "Lost", "reset did not count as lost")
	bobRoot = newRoot
	local resultsBefore = count("Results")
	leave(alice)
	leave(bob)
	tick(DT)
	assert(RSv.phase() == "Lobby" and RSv.run() == nil, "empty round not aborted: " .. RSv.phase())
	assert(count("Results") == resultsBefore, "results sent to nobody")
end)

check("rewards: daily once, codes once (with flask), goals pay once, level up", function()
	local erin = makePlayer("Erin")
	local p = DS.getProfile(erin)
	remotes.ClaimDaily.OnServerEvent:Fire(erin)
	assert(p.Coins == GameConfig.DailyRewards[1] and p.Daily.Streak == 1, "daily not paid")
	tick(2)
	remotes.ClaimDaily.OnServerEvent:Fire(erin)
	assert(p.Coins == GameConfig.DailyRewards[1], "daily paid twice")
	tick(2)
	remotes.RedeemCode.OnServerEvent:Fire(erin, " antlers ")
	assert(p.Coins == GameConfig.DailyRewards[1] + 100 and p.Boosts.Flask == 1, "code not applied")
	tick(2)
	remotes.RedeemCode.OnServerEvent:Fire(erin, "ANTLERS")
	assert(p.Boosts.Flask == 1, "code used twice")
	tick(2)
	remotes.RedeemCode.OnServerEvent:Fire(erin, "NOPE")
	assert(count("Notify", "doesn't exist", erin) >= 1)
	local coins = p.Coins
	for _ = 1, 5 do
		DS.bump(erin, "Snowballs", 1)
	end
	DS.bump(erin, "Snowballs", 1)
	assert(p.Goals.Done.Lure and p.Coins == coins + 25, "goal not paid exactly once")
	local view = registry.RewardService.goalsView(erin)
	assert(#view == #GameConfig.Goals and view[3].done)
	local reward, leveled = registry.RewardService.grantRound(erin, { escaped = true, cores = 3, rescues = 2, difficulty = "Nightmare" })
	assert(reward.coins > 500 and leveled and leveled > 1 and erin:GetAttribute("TI_Level") == leveled, "no level up")
	assert(count("Notify", "LEVEL UP", erin) >= 1)
	leave(erin)
end)

check("wardrobe: coins buy (atomic), level unlocks, equip only owned, look rebuilt", function()
	local fay = makePlayer("Fay")
	local p = DS.getProfile(fay)
	local Shop = registry.ShopService
	local ok = Shop.buyWithCoins(fay, "Outfit", "Mint")
	assert(not ok and p.Coins == 0, "bought without coins")
	p.Coins = 1000
	ok = Shop.buyWithCoins(fay, "Outfit", "Mint")
	assert(ok and p.Coins == 600 and p.Cosmetics.Outfit == "Mint", "coin purchase")
	assert(not Shop.buyWithCoins(fay, "Outfit", "Mint") and p.Coins == 600, "bought twice")
	assert(not Shop.buyWithCoins(fay, "Outfit", "Polar"), "Robux item sold for coins")
	assert(not Shop.equip(fay, "Outfit", "Ranger"), "level-5 outfit equipped at level 1")
	p.Xp = requireModule(Shared.Progress).xpFor(5)
	assert(Shop.equip(fay, "Outfit", "Ranger"), "level unlock")
	assert(not Shop.equip(fay, "Lantern", "Aurora"), "unowned lantern")
	assert(not Shop.equip(fay, "Hat", "x") and not Shop.equip(fay, "Outfit", 5))
	local look = fay.Character.TI_Look
	assert(look and look.Beanie.Color == roblox.Color3.fromRGB(60, 90, 70), "look not rebuilt with the Ranger beanie")
	-- Studio: Robux items and VIP granted free for testing
	Shop.buy(fay, "Aurora")
	assert(p.Cosmetics.Owned["Lantern:Aurora"] and Shop.equip(fay, "Lantern", "Aurora"), "studio product grant")
	Shop.buy(fay, "Polar") -- has a (test) product id: prompts instead
	assert(not p.Cosmetics.Owned["Outfit:Polar"], "granted without paying")
	Shop.buy(fay, "VIP")
	assert(Shop.owns(fay, "Outfit", "Golden") and fay:GetAttribute("TI_VIP") == true, "VIP")
	Shop.buy(fay, "Flask5")
	assert(p.Boosts.Flask == 5, "flask x5")
	local snap = DS.snapshot(fay)
	assert(snap.owned["Outfit:Golden"] and snap.vip and snap.level == 5 and snap.daily and #snap.goals == 4, "snapshot")
	leave(fay)
end)

local function receipt(player, id, productId)
	return stubServices.MarketplaceService.ProcessReceipt({ PlayerId = player.UserId, ProductId = productId or 5151, PurchaseId = id })
end
local gus
check("receipts: granted exactly once; flask product once; refused when the profile can't persist live", function()
	gus = makePlayer("Gus")
	local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
	local notYet = roblox.Enum.ProductPurchaseDecision.NotProcessedYet
	local p = DS.getProfile(gus)
	assert(receipt(gus, "r-1") == granted and p.Cosmetics.Owned["Outfit:Polar"] and p.Receipts["r-1"])
	assert(receipt(gus, "r-1") == granted, "retry not acknowledged")
	assert(receipt(gus, "f-1", 5152) == granted and p.Boosts.Flask == 1)
	assert(receipt(gus, "f-1", 5152) == granted and p.Boosts.Flask == 1, "flask granted twice")
	isStudio = false
	local hal = makePlayer("Hal")
	local decision = receipt(hal, "r-live", 5152)
	isStudio = true
	assert(decision == notYet and DS.getProfile(hal).Boosts.Flask == 0, "live purchase granted on a non-persistent profile")
	assert(stubServices.MarketplaceService.ProcessReceipt({ PlayerId = 999999, ProductId = 5151, PurchaseId = "x" }) == notYet)
	leave(hal)
end)

check("settings: only known keys with legal values are saved", function()
	local p = DS.getProfile(gus)
	registry.PlayerService.saveSettings(gus, { Music = 0.3, Master = 7, Effects = 0 / 0, ScareEffects = "no", CameraShake = false, Hack = true })
	assert(p.Settings.Music == 0.3 and p.Settings.Master == 1, "numbers not clamped")
	assert(p.Settings.Effects == 1, "NaN accepted")
	assert(p.Settings.ScareEffects == true and p.Settings.CameraShake == false and p.Settings.Hack == nil)
end)

check("remote spam and junk arguments are rejected", function()
	for _ = 1, 30 do
		remotes.SetReady.OnServerEvent:Fire(gus, true)
		remotes.Vote.OnServerEvent:Fire(gus, { "Easy" })
	end
	remotes.Vote.OnServerEvent:Fire(gus, nil)
	remotes.SetMoveMode.OnServerEvent:Fire(gus, 42)
	remotes.Throw.OnServerEvent:Fire(gus, nil)
	remotes.RedeemCode.OnServerEvent:Fire(gus, string.rep("A", 5000))
	remotes.Equip.OnServerEvent:Fire(gus, "Outfit", { "Golden" })
	remotes.BuyCosmetic.OnServerEvent:Fire(gus, nil, nil)
	remotes.ShopBuy.OnServerEvent:Fire(gus, string.rep("x", 100))
	remotes.SaveSettings.OnServerEvent:Fire(gus, "loud")
	remotes.RequestState.OnServerEvent:Fire(gus)
	local p = DS.getProfile(gus)
	assert(p.Coins >= 0 and p.Cosmetics.Outfit == "Classic", "junk changed the profile")
	RSv.setReady(gus, false)
	tick(DT)
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
		stored["player_" .. (nextUserId + 1)] = { Coins = 777, Xp = -5, Boosts = { Flask = 0 / 0 }, Cosmetics = { Owned = { ["Outfit:Mint"] = true, ["Bogus:Thing"] = true }, Outfit = "Nope" } }
		local ivy = makePlayer("Ivy")
		local key = "player_" .. ivy.UserId
		local p = DS.getProfile(ivy)
		assert(DS.isPersistent(ivy) and p.Coins == 777, "saved profile not loaded")
		assert(p.Xp == 0 and p.Boosts.Flask == 0 and p.Cosmetics.Owned["Outfit:Mint"] and p.Cosmetics.Owned["Bogus:Thing"] == nil and p.Cosmetics.Outfit == "Classic", "saved data not validated")
		assert(type(stored[key].Lock) == "table", "profile not locked on load")
		p.Coins = 800
		assert(DS.save(ivy) and stored[key].Coins == 800, "save failed")
		stored[key].Lock = { Session = "other-server", At = fakeOs.time() }
		p.Coins = 1
		assert(not DS.save(ivy), "saved over another server's lock")
		assert(stored[key].Coins == 800 and not DS.isPersistent(ivy))
		isStudio = false
		local decision = receipt(ivy, "lock-1")
		isStudio = true
		assert(decision == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "granted after losing the lock")
		leave(ivy)
		assert(stored[key].Coins == 800, "left player overwrote the new owner")
		stored["player_" .. (nextUserId + 1)] = { Coins = 55, Lock = { Session = "crashed", At = fakeOs.time() - 100000 } }
		local jo = makePlayer("Jo")
		local joKey = "player_" .. jo.UserId
		assert(DS.isPersistent(jo) and DS.getProfile(jo).Coins == 55, "stale lock blocked the load")
		DS.getProfile(jo).Coins = 99
		leave(jo)
		assert(stored[joKey].Coins == 99 and stored[joKey].Lock == nil, "leave save did not persist and unlock")
	end)
	stubServices.DataStoreService.GetDataStore = function()
		error("DataStores are not available in the harness")
	end
	DS.init(registry)
	assert(ok, err)
end)

---------------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------------

check("client controllers initialise and render real server data (HUD, lobby, overlays, results, every menu tab, scare)", function()
	local kim = makePlayer("Kim")
	local snapshot = DS.sendProfileNow(kim)
	assert(snapshot and snapshot.daily and snapshot.goals and snapshot.owned, "snapshot incomplete")
	requireModule(Shared.Net).setup()
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = kim
	fakePlayers.LocalPlayer = kim
	stubServices.RunService.IsServer = function()
		return false
	end
	local camera = roblox.Instance.new("Camera")
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	camera.Parent = workspaceService
	workspaceService.CurrentCamera = camera
	local folder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("ThinIceClient"):FindFirstChild("Controllers")
	local names = { "ClientState", "AudioController", "LightingController", "InputController", "HudController", "MenuController", "EffectsController" }
	local controllers = {}
	for _, name in ipairs(names) do
		controllers[name] = requireModule(folder[name])
		controllers[name].init()
	end
	local ClientState = controllers.ClientState
	ClientState.profile = snapshot
	ClientState.settings = table.clone(snapshot.settings)
	ClientState.ProfileChanged:Fire(snapshot)
	for _, name in ipairs({ "IceHUD", "IceMenu", "IceFx" }) do
		assert(playerGui:FindFirstChild(name), name .. " missing")
	end
	local Hud = controllers.HudController
	-- Lobby panel with live counts.
	local state = RSv.state()
	ClientState.round = state
	ClientState.RoundChanged:Fire(state)
	assert(playerGui.IceHUD.Lobby.Visible, "lobby panel hidden in the lobby")
	assert(string.find(playerGui.IceHUD.Lobby.Status.Text, "ready", 1, true))
	assert(Hud.lobbyText({ phase = "Lobby", players = 3, ready = 1, autoStartIn = 20 }) == "1/3 ready - starting in 20s")
	-- A real round through the client: Kim + Lee play.
	local lee = makePlayer("Lee")
	local run = startRound("Hard")
	ClientState.round = RSv.state()
	ClientState.RoundChanged:Fire(ClientState.round)
	assert(ClientState.inRound(), "client doesn't know it's in the round")
	assert(not playerGui.IceHUD.Lobby.Visible, "lobby panel during the round")
	assert(string.find(playerGui.IceHUD.TopBar.Timer.Text, "HARD", 1, true), "timer: " .. playerGui.IceHUD.TopBar.Timer.Text)
	ClientState.team = RSv.team()
	ClientState.TeamChanged:Fire(ClientState.team)
	local rows = 0
	for _, c in ipairs(playerGui.IceHUD.Team:GetChildren()) do
		if c:IsA("Frame") then
			rows += 1
		end
	end
	assert(rows == #ClientState.team and rows >= 2, "team rows " .. rows .. " for " .. #ClientState.team)
	Hud.tick()
	assert(playerGui.IceHUD.Survival.Visible, "survival bars hidden")
	SS.freeze(kim, "monster")
	Hud.tick()
	assert(playerGui.IceHUD.Frozen.Visible and string.find(playerGui.IceHUD.Frozen.Text.Text, "Lost to the ice in", 1, true), "frozen overlay")
	-- Every menu tab renders.
	local Menu = controllers.MenuController
	ClientState.leaderboard = { { userId = kim.UserId, name = "Kim", value = 3 } }
	for _, tab in ipairs(Menu.TABS) do
		Menu.open(tab)
		local n = 0
		for _, d in ipairs(Menu.content():GetDescendants()) do
			if d:IsA("TextButton") or d:IsA("TextLabel") then
				n += 1
			end
		end
		assert(n >= 2, tab .. " tab is empty")
	end
	Menu.open("Wardrobe")
	local equips, buys = 0, 0
	for _, d in ipairs(Menu.content():GetDescendants()) do
		if d:IsA("TextButton") and d.Name == "Action" then
			if d.Text == "EQUIPPED" then
				equips += 1
			elseif string.find(d.Text, "BUY", 1, true) then
				buys += 1
			end
		elseif d:IsA("ViewportFrame") then
			assert(d:FindFirstChildOfClass("Camera"), "wardrobe preview without a camera")
		end
	end
	assert(equips == 2 and buys == 4, string.format("wardrobe: %d equipped, %d buy", equips, buys))
	-- Scare (full and gentle), lighting targets, input.
	local Fx = controllers.EffectsController
	local scare = Fx.scare(true)
	assert(scare:FindFirstChild("Face") and scare.Face:FindFirstChildOfClass("Camera") and scare.Face:FindFirstChild("Antlered"), "no close-up")
	local gentle = Fx.scare(false)
	assert(not gentle:FindFirstChild("Face"), "scare shown with scare effects off")
	assert(Fx.dread(100) == 0 and Fx.dread(6) == 1 and Fx.snowRate(true, false) > Fx.snowRate(false, false) and Fx.snowRate(true, true) < Fx.snowRate(true, false))
	Fx.step(1 / 60)
	local Light = controllers.LightingController
	assert(Light.target(true, false, false, false).density > Light.target(false, false, false, false).density, "gust fog")
	assert(Light.target(false, true, false, false).saturation < -0.3, "frozen grade")
	Light.step(1 / 60)
	local Input = controllers.InputController
	assert(Input.handle(roblox.Enum.KeyCode.C, true) and ClientState.mode == "Sneak", "sneak toggle")
	assert(Input.handle(roblox.Enum.KeyCode.LeftShift, true) and ClientState.mode == "Sprint")
	Input.handle(roblox.Enum.KeyCode.LeftShift, false)
	assert(ClientState.mode == "Sneak", "sprint release forgot sneak")
	Input.handle(roblox.Enum.KeyCode.C, true)
	assert(ClientState.mode == "Walk")
	local UiModule = requireModule(folder.Ui)
	UiModule.closeAll()
	assert(Input.handle(roblox.Enum.KeyCode.M, true) and UiModule.isOpen("Menu"), "M did not open the menu")
	Input.handle(roblox.Enum.KeyCode.M, true)
	assert(not UiModule.isOpen("Menu"), "M did not close the menu")
	assert(Input.handle(roblox.Enum.KeyCode.F, true), "throw key")
	assert(clientSent[#clientSent].name == "Throw" and typeof(clientSent[#clientSent].args[1]) == "Vector3", "throw not sent")
	controllers.AudioController.step(1 / 60)
	-- Presence: put the Antlered 12 studs from Kim, awake and hunting her.
	local kimRec = SS.record(kim)
	if kimRec.state ~= "Active" then
		SS.thaw(kim, nil)
	end
	local kimRoot = kim.Character.HumanoidRootPart
	setPos(kimRoot, cellPos(10, 6))
	MS.place(kimRoot.Position + V3.new(12, 0, 0))
	local monsterModel = MS.model()
	monsterModel:SetAttribute("TI_State", "Hunt")
	monsterModel:SetAttribute("TI_Target", kim.UserId)
	tick(1.1) -- (ClientState looks the monster up at most once a second)
	monsterModel:SetAttribute("TI_State", "Hunt")
	monsterModel:SetAttribute("TI_Target", kim.UserId)
	local info = ClientState.monsterInfo()
	assert(info and info.huntingMe and info.distance and info.distance < 20, "client can't see the hunt")
	local cues = controllers.AudioController.step(1 / 60)
	assert(cues.heartbeat and cues.breath and cues.chase, "presence cues missing up close")
	local Audio = controllers.AudioController
	assert(Audio.playing("Heartbeat") and Audio.playing("Chase") and Audio.playing("Breath"), "heartbeat / chase / breath not playing")
	assert(Audio.playing("Wind") and Audio.playing("WindHum") and Audio.playing("Music"), "ambience not playing")
	for _, slot in ipairs({ "Crack", "Caught", "Deliver", "Splash" }) do
		local layers = Audio.layers(requireModule(Shared.Config.AudioAssets)[slot])
		assert(#layers >= 2, slot .. " should be layered")
		for _, layer in ipairs(layers) do
			assert(layer.volume <= 1, slot .. " too loud")
		end
	end
	local vign = Fx.step(1 / 60)
	assert(vign > 0.4 and playerGui.IceFx.Frost.BackgroundTransparency < 0.8, "no frost vignette up close")
	-- head pose: listening cocks the head
	local skull = monsterModel.Head.Skull
	monsterModel:SetAttribute("TI_State", "Listen")
	Fx.poseHead(monsterModel, 1)
	local listenCF = skull.CFrame
	monsterModel:SetAttribute("TI_State", "Prowl")
	Fx.poseHead(monsterModel, 0)
	assert((listenCF.Position - skull.CFrame.Position).Magnitude > 0.3, "head doesn't move to listen")
	-- far away: it shows through the fog now and then; then out of range nothing at all
	MS.place(kimRoot.Position + V3.new(0, 0, 80))
	monsterModel:SetAttribute("TI_State", "Prowl")
	Fx.step(1 / 60)
	local hl = monsterModel:FindFirstChild("TI_Silhouette")
	assert(hl and hl:IsA("Highlight") and hl.Enabled, "no silhouette at 80 studs")
	assert(not controllers.AudioController.step(1 / 60).heartbeat, "heartbeat at 80 studs")
	-- ambient scares (client-only)
	ClientState.applySettings({ ScareEffects = true, ReducedEffects = false })
	local prints = Fx.ambientScare("Footprints")
	assert(prints and #prints:GetChildren() == 0, "footprints should appear one by one")
	flushDeferred() -- (the harness runs every delayed task at once: the prints appear, then get cleaned up)
	assert(prints.Parent == nil, "footprints never cleaned up")
	assert(Fx.ambientScare("UnderIceShadow"):IsA("BasePart"), "no shadow under the ice")
	assert(Fx.ambientScare("IceGroan") == "groan" and Fx.ambientScare("DistantScream") == "howl")
	ClientState.applySettings({ ReducedEffects = true })
	assert(Fx.ambientScare("Footprints") == nil, "reduced effects still spawns footprints")
	ClientState.applySettings({ ReducedEffects = false })
	-- HUD: smooth bars, compass while carrying, the sled countdown
	assert(math.abs(Hud.ease(0, 1, 1 / 60) - 8 / 60) < 1e-6 and Hud.ease(nil, 0.5, 0.1) == 0.5)
	assert(math.abs(Hud.arrowAngle(V3.new(0, 0, 1), V3.new(), V3.new(0, 0, 10))) < 1e-6, "straight ahead")
	assert(math.abs(math.abs(Hud.arrowAngle(V3.new(0, 0, 1), V3.new(), V3.new(10, 0, 0))) - 90) < 1e-6, "side")
	kim:SetAttribute("TI_Carrying", true)
	Hud.tick(1 / 60)
	assert(playerGui.IceHUD.Compass.Visible and string.find(playerGui.IceHUD.Compass.Text.Text, "BEACON", 1, true), "no beacon compass")
	kim:SetAttribute("TI_Carrying", false)
	ClientState.round = { phase = "Sled", timeLeft = 8, participants = ClientState.round.participants }
	Hud.tick(1 / 60)
	assert(playerGui.IceHUD.SledCountdown.Visible and string.find(playerGui.IceHUD.SledCountdown.Text, "0:08", 1, true), "no sled countdown")
	Fx.step(1 / 60)
	assert(world.sled.model.SledLight1, "sled lights")
	ClientState.round = RSv.state()
	-- the full catch scare: a face lunging in + frost cracks; reduced = gentle
	local strong = Fx.scare(true)
	local cracks = 0
	for _, c in ipairs(strong:GetChildren()) do
		if c.Name == "Crack" then
			cracks += 1
		end
	end
	assert(cracks >= 4 and strong:FindFirstChild("Face"), "catch scare too tame")
	-- Finish the round and show the real results card.
	for _, p in ipairs(RSv.participantList()) do
		SS.freeze(p, "cold")
	end
	tick(DT)
	assert(RSv.phase() == "Results", RSv.phase())
	local result = lastFor("Results", kim).args[1]
	Hud.showResults(result)
	assert(Hud.resultsShown() and playerGui.IceHUD.Results.Visible, "results card")
	local playerRows = 0
	for _, d in ipairs(playerGui.IceHUD.Results:GetDescendants()) do
		if d.Name == "Player" then
			playerRows += 1
		end
	end
	assert(playerRows == #result.team and playerRows >= 2, "results table rows " .. playerRows)
	tick(GameConfig.Round.ResultsTime + 0.1)
	assert(run.folder.Parent == nil)
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
