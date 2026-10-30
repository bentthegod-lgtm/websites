--[[
	Headless harness for LAST LIFEBOAT.

	Loads the Rojo-built place in Lune and runs the REAL game modules against Lune's Roblox
	instance implementation. Engine services Lune does not simulate (players, data stores,
	marketplace, tweens, input, physics, terrain voxels, raycasts, rendering) are stubbed,
	and time is a fake clock the tests advance. Lune has no physics, so characters are moved
	by the tests; Terrain:FillBlock is recorded, and "underwater" is the world Y < 0 test the
	game itself uses.

	Usage (from last-lifeboat/):
	  rojo build -o build/LastLifeboat.rbxlx && lune run tests/harness build/LastLifeboat.rbxlx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local placePath = process.args[1] or "build/LastLifeboat.rbxlx"
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
		CanSendGameInviteAsync = function()
			return true
		end,
	}),
	UserInputService = stubObject("UserInputService", { TouchEnabled = true, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false }),
	GuiService = stubObject("GuiService"),
	StarterGui = stubObject("StarterGui"),
	TextChatService = stubObject("TextChatService"),
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
-- Raycasts: tests install a hook (default: nothing is hit).
local raycastHook = nil
roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction)
	if raycastHook then
		return raycastHook(origin, direction)
	end
	return nil
end)
-- Terrain: Lune has no voxel engine; FillBlock calls are recorded.
local fills = {}
roblox.implementMethod("Terrain", "FillBlock", function(_, cf, size, material)
	table.insert(fills, { cf = cf, size = size, material = material })
end)
roblox.implementMethod("Terrain", "ReadVoxels", function()
	return {}, {}
end)
local terrain = roblox.Instance.new("Terrain")
terrain.Parent = workspaceService
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
	Rect = roblox.Rect,
	TweenInfo = stubCtor("TweenInfo"),
	RaycastParams = stubCtor("RaycastParams"),
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
local Shared = RS:FindFirstChild("LastLifeboat")
local ServerRoot = SSS:FindFirstChild("LastLifeboatServer")
local Services = ServerRoot:FindFirstChild("Services")

local GameConfig = requireModule(Shared.Config.GameConfig)
local ShopConfig = requireModule(Shared.Config.ShopConfig)
local ShipGen = requireModule(Shared.ShipGen)
local LurchMath = requireModule(Shared.LurchMath)
local LootMath = requireModule(Shared.LootMath)
local V3, CF = roblox.Vector3, roblox.CFrame

-- Real product ids so ProcessReceipt can be exercised (config tables are plain tables).
ShopConfig.Products[1].ProductId = 7101 -- Life Jacket
ShopConfig.Products[3].ProductId = 7103 -- 500 coins

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
	for _, m in ipairs(ServerRoot.World:GetChildren()) do
		requireModule(m)
	end
end)

local world
local buildReport = {}
check("startup is fast: the harbour builds in one go, the sea and every ship in small chunks (timed)", function()
	local LobbyBuilder = requireModule(ServerRoot.World.LobbyBuilder)
	local t0 = os.clock()
	world = LobbyBuilder.build(workspaceService)
	local lobbyTime = os.clock() - t0
	syncPositions(world.folder)
	assert(world.spawn:IsA("SpawnLocation") and world.kiosk and world.dailyChest and world.codesBox, "harbour features")
	assert(world.votePads.Gull and world.votePads.Aurora and world.votePads.Leviathan, "vote pads")
	assert(#world.boardRows.Escapes == GameConfig.Leaderboard.Rows and #world.boardRows.Banked == GameConfig.Leaderboard.Rows, "board rows")
	assert(#world.lanterns >= 10, "lanterns")
	assert(lobbyTime < 0.5, string.format("harbour took %.2fs", lobbyTime))
	table.insert(buildReport, string.format("harbour %d parts in %.3fs", world.partCount, lobbyTime))
	-- the sea: many small FillBlocks, never one giant one
	local OceanBuilder = requireModule(ServerRoot.World.OceanBuilder)
	local job = OceanBuilder.new(terrain)
	local frames = 0
	local before = #fills
	repeat
		frames += 1
	until job:step(2)
	local made = #fills - before
	assert(made == #OceanBuilder.blocks() and frames >= 10, "ocean blocks " .. made)
	local water, biggest = 0, 0
	for i = before + 1, #fills do
		local f = fills[i]
		biggest = math.max(biggest, f.size.X * f.size.Y * f.size.Z / 64)
		if f.material == roblox.Enum.Material.Water then
			water += 1
			assert(f.cf.Position.Y + f.size.Y / 2 <= GameConfig.World.SeaLevel + 1e-6, "water above sea level")
		end
	end
	assert(water > 0 and biggest <= 400000, string.format("a single FillBlock of %d voxels", biggest))
	table.insert(buildReport, string.format("sea %d blocks over %d frames (largest %dk voxels)", made, frames, math.floor(biggest / 1000)))
	-- every ship, stepped like the server does (PartsPerStep per frame)
	local ShipBuilder = requireModule(ServerRoot.World.ShipBuilder)
	for _, key in ipairs(GameConfig.ShipOrder) do
		local plan = ShipGen.plan(key, 99)
		local folder = roblox.Instance.new("Folder")
		local shipJob = ShipBuilder.new(plan, folder, LobbyBuilder.shipBase(key))
		local n, worst, total = 0, 0, 0
		repeat
			local t1 = os.clock()
			local done = shipJob:step(GameConfig.Ship.PartsPerStep)
			local dt = os.clock() - t1
			worst = math.max(worst, dt)
			total += dt
			n += 1
		until done
		local record = shipJob.record
		local parts = partsIn(folder)
		assert(record.parts == parts or math.abs(record.parts - parts) <= 2, "part count bookkeeping " .. record.parts .. " vs " .. parts)
		assert(parts <= plan.def.PartBudget, key .. " parts " .. parts .. " > budget " .. plan.def.PartBudget)
		assert(math.abs(plan.partEstimate - parts) / parts <= 0.3, string.format("%s estimate %d vs real %d", key, plan.partEstimate, parts))
		assert(n >= math.floor(parts / GameConfig.Ship.PartsPerStep), key .. " built in too few frames: " .. n)
		assert(worst < 0.05, string.format("%s worst build frame %.1f ms", key, worst * 1000))
		assert(total < 2, string.format("%s took %.2fs", key, total))
		assert(#record.loose <= GameConfig.Ship.MaxLooseProps and #record.loose >= 5, key .. " loose props " .. #record.loose)
		assert(#record.bulkheads == #plan.bulkheads and #record.valves == #plan.valves and #record.hazards == #plan.hazards, key .. " obstacle records")
		assert(record.lifeboat and record.lifeboat.zone and record.lifeboat.model.PrimaryPart, key .. " lifeboat")
		if key == "Leviathan" then
			assert(parts >= 1500 and parts <= 5000, "Leviathan parts " .. parts)
		end
		table.insert(buildReport, string.format("%s %d parts / %d frames / worst %.1fms", key, parts, n, worst * 1000))
		folder:Destroy()
	end
	print("        " .. table.concat(buildReport, "; "))
end)

check("the ships look like ships: tapered bow, portholes, funnels, davits, railings, lifeboat, names", function()
	local ShipBuilder = requireModule(ServerRoot.World.ShipBuilder)
	local LobbyBuilder = requireModule(ServerRoot.World.LobbyBuilder)
	for _, key in ipairs(GameConfig.ShipOrder) do
		local folder = roblox.Instance.new("Folder")
		local plan = ShipGen.plan(key, 5)
		local record = ShipBuilder.buildAll(plan, folder, LobbyBuilder.shipBase(key))
		local counts = {}
		local hullAngles = 0
		for _, d in ipairs(record.model:GetDescendants()) do
			if d:IsA("BasePart") then
				counts[d.Name] = (counts[d.Name] or 0) + 1
				if d.Name == "Hull" then
					local look = d.CFrame.LookVector
					if math.abs(look.X) > 0.05 then
						hullAngles += 1
					end
				end
			end
		end
		assert(hullAngles >= 8, key .. ": the hull doesn't taper")
		assert((counts.Porthole or 0) >= plan.cellCount * 4, key .. " portholes " .. tostring(counts.Porthole))
		assert(counts.Funnel == plan.def.Funnels and counts.FunnelTop == plan.def.Funnels, key .. " funnels")
		assert((counts.DavitPost or 0) >= 4 and (counts.CapRail or 0) >= plan.cellCount * 2, key .. " davits / rails")
		assert(counts.ShipsWheel == 1 and counts.Bridge == 1 and (counts.Mast or 0) == 2, key .. " bridge / helm / masts")
		assert((counts.Lamp or 0) + (counts.Bulb or 0) >= #plan.decks * 3, key .. " lamps")
		local boatParts = partsIn(record.lifeboat.model)
		assert(boatParts >= 20, key .. " lifeboat parts " .. boatParts)
		assert(record.model:FindFirstChild("BowName", true):FindFirstChildOfClass("SurfaceGui"), "no ship name")
		-- every deck theme placed its signature props
		local themeProps = { EngineRoom = "Boiler", CargoHold = "Crate", CrewQuarters = "Bunk", Cabins = "CabinWall", DiningHall = "TableTop", Promenade = "Railing", TopDeck = "LampPost" }
		for _, deck in ipairs(plan.decks) do
			local want = themeProps[deck.theme]
			assert((counts[want] or 0) + #record.loose >= 1, key .. " " .. deck.theme .. " has no " .. want)
		end
		folder:Destroy()
	end
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
		if list[i].player == player or (player == nil and list[i].all) then
			return list[i]
		end
	end
	return nil
end

local registry
local ORDER = { "DataService", "ShopService", "UpgradeService", "RewardService", "PlayerService", "ShipService", "SurvivalService", "LootService", "ObstacleService", "LifeboatService", "AbilityService", "RoundService", "LeaderboardService" }
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
	for _, name in ipairs(registry.DataService.LEAVE_HOOKS) do
		assert(registry[name] and registry[name].onPlayerRemoving, name .. " in LEAVE_HOOKS has no onPlayerRemoving")
	end
	-- every service holding per-player state is in LEAVE_HOOKS
	for _, name in ipairs(ORDER) do
		if registry[name].onPlayerRemoving then
			assert(table.find(registry.DataService.LEAVE_HOOKS, name), name .. " missing from LEAVE_HOOKS")
		end
	end
end)

local nextUserId = 5000
local newCharacter
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
	local character, root = newCharacter(name, position)
	player.Character = character
	table.insert(playerList, player)
	fakePlayers.PlayerAdded:Fire(player)
	player.CharacterAdded:Fire(character)
	flushDeferred()
	return player, root
end
function newCharacter(name, position)
	local character = roblox.Instance.new("Model")
	character.Name = name
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V3.new(2, 2, 1)
	setPos(root, position or world.spawnCFrame.Position)
	root.AssemblyLinearVelocity = V3.new()
	root.Anchored = false
	root.Parent = character
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Size = V3.new(2, 1, 1)
	setPos(head, root.CFrame.Position + V3.new(0, 1.5, 0))
	head.Parent = character
	local torso = roblox.Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = V3.new(2, 2, 1)
	setPos(torso, root.CFrame.Position)
	torso.Parent = character
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.PlatformStand = false
	humanoid.CameraOffset = V3.new()
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = workspaceService
	return character, root
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

local DS, RSv, ShipS, SS, LS, OS, LB, AS, SH, RW, US
local DT = 1 / 30
-- Advances the fake clock in 1/30 s steps, running the same Heartbeat work as Main.server.
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
local function rootOf(player)
	return player.Character.HumanoidRootPart
end
-- Moves a character (root + head) to a world position, feet ~3 below the root.
-- Stands in for walking there: the anti-teleport tracker forgets the old spot.
local function putAt(player, position)
	if LB then
		LB.forgetTrack(player)
	end
	local root = rootOf(player)
	root.Anchored = false
	setPos(root, position)
	setPos(player.Character.Head, position + V3.new(0, 1.5, 0))
end
local DOCK = function(i)
	return V3.new(-30, GameConfig.World.DockTop + 3, -20 + (i or 0) * 6)
end
local function shipPoint(localCF)
	return ShipS.toWorld(localCF).Position
end
local function deckPoint(deck, x, z)
	local plan = ShipS.record().plan
	return shipPoint(CF.new(x, plan.decks[deck].y + 3, z))
end
local function underwater(player)
	putAt(player, V3.new(GameConfig.World.ShipX + 90, -8, 40 + player.UserId % 7 * 6))
end
check("startup: the sea fills and the Gull is moored at the dock over many frames", function()
	DS, RSv, ShipS, SS, LS, OS, LB, AS, SH, RW, US = registry.DataService, registry.RoundService, registry.ShipService, registry.SurvivalService, registry.LootService, registry.ObstacleService, registry.LifeboatService, registry.AbilityService, registry.ShopService, registry.RewardService, registry.UpgradeService
	assert(ShipS.building() and ShipS.key() == "Gull", "no ship being built at startup")
	local frames = 0
	while not ShipS.ready("Gull") do
		tick(DT)
		frames += 1
		assert(frames < 400, "the Gull never finished")
	end
	assert(ShipS.ocean().done, "sea not filled")
	assert(frames >= 3, "the ship was built in one frame (" .. frames .. ")")
	local model = ShipS.record().model
	assert(model.Parent and model.Parent.Name == "LastLifeboatShips" and model:GetAttribute("Ship") == "Gull")
	-- moored broadside, clear of the dock, above the sea
	local pivot = model:GetPivot()
	assert(math.abs(pivot.Position.X - GameConfig.World.ShipX) < 1e-6 and pivot.Position.Y == 0)
	assert(GameConfig.World.ShipX - GameConfig.Ships.Leviathan.Beam / 2 > GameConfig.World.DockX[2] + 8, "the biggest ship overlaps the dock")
	print(string.format("        Gull moored after %d frames", frames))
end)

local alice, bob, carl
check("player joins: default profile, attributes, name tag, leaderstats, told saving is off", function()
	alice = makePlayer("Alice")
	local p = DS.getProfile(alice)
	assert(p and p.Coins == 0 and p.Upgrades.Lungs == 0 and p.Boosts.LifeJacket == 0 and p.Tutorial.Done == false, "bad default profile")
	assert(not DS.isPersistent(alice))
	assert(count("Notify", "saving is unavailable", alice) >= 1, "not told that saving is off")
	assert(alice:GetAttribute("LL_VIP") == false and alice:GetAttribute("LL_Slots") == 3 and alice:GetAttribute("LL_OxygenMax") == 12, "attributes")
	local tag = alice.Character.Head:FindFirstChild("LL_NameTag")
	assert(tag and tag.Label.Text == "Alice", "name tag")
	assert(alice:FindFirstChild("leaderstats") and alice.leaderstats.Escapes.Value == 0)
	assert(count("RoundState", nil, alice) > 0, "round state not sent")
	assert(registry.PlayerService.prompts.Shop and registry.PlayerService.prompts.Daily and registry.PlayerService.prompts.Codes, "harbour prompts")
	registry.PlayerService.prompts.Shop.Triggered:Fire(alice)
	assert(lastFor("OpenMenu", alice).args[1] == "Shop", "ticket booth doesn't open the shop")
end)

-- An Aurora plan with at least two bulkheads, steam, wires and chandeliers.
local auroraSeed
for seed = 1, 200 do
	local plan = ShipGen.plan("Aurora", seed)
	local kinds = {}
	for _, h in ipairs(plan.hazards) do
		kinds[h.kind] = true
	end
	if #plan.bulkheads >= 2 and kinds.Steam and kinds.Wires and kinds.Chandelier then
		auroraSeed = seed
		break
	end
end

local run
check("vote + ready: locked ships don't count, ties go easier, pads vote, 25 s auto-start, Aurora built over frames", function()
	bob = makePlayer("Bob")
	carl = makePlayer("Carl")
	remotes.Vote.OnServerEvent:Fire(alice, "Aurora")
	assert(RSv.tally() == "Gull", "a locked vote counted")
	assert(count("Notify", "unlocks after 3 escapes", alice) >= 1, "not told the ship is locked")
	DS.getProfile(alice).Stats.Escapes = 3
	DS.getProfile(bob).Stats.Escapes = 4
	remotes.Vote.OnServerEvent:Fire(alice, "Aurora")
	remotes.Vote.OnServerEvent:Fire(bob, "Gull")
	assert(RSv.tally() == "Gull", "tie did not go to the easier ship")
	remotes.Vote.OnServerEvent:Fire(bob, "Leviathan")
	local leading, counts = RSv.tally()
	assert(leading == "Gull" and counts.Leviathan == 0, "locked Leviathan vote counted: " .. leading)
	-- standing on the Aurora pad votes too
	putAt(bob, world.votePads.Aurora.position + V3.new(1, 3, 0))
	tick(DT * 2)
	assert(RSv.tally() == "Aurora" and RSv.state().votes.Aurora == 2, "pad vote")
	remotes.Vote.OnServerEvent:Fire(carl, "Junk")
	remotes.Vote.OnServerEvent:Fire(carl, { "Gull" })
	-- a fresh Aurora is waiting at the dock (so the round reuses it)
	ShipS.request("Aurora", auroraSeed)
	local frames = 0
	while not ShipS.ready("Aurora") do
		tick(DT)
		frames += 1
		assert(frames < 600, "Aurora never finished")
	end
	assert(frames >= 6, "Aurora built in " .. frames .. " frames")
	RSv.setReady(alice, true)
	tick(1)
	assert(RSv.phase() == "Lobby", "started with only one of three ready")
	assert(RSv.state().autoStartIn and RSv.state().ready == 1, "auto-start timer not shown")
	tick(GameConfig.Round.ReadyTimeout)
	assert(RSv.phase() == "Countdown", "no countdown 25 s after the first ready: " .. RSv.phase())
	tick(GameConfig.Round.Countdown + DT)
	local guard = 0
	while RSv.phase() == "Preparing" do
		tick(DT)
		guard += 1
		assert(guard < 700, "never finished preparing")
	end
	assert(RSv.phase() == "Running", "not running: " .. RSv.phase())
	run = RSv.run()
	assert(run.shipKey == "Aurora" and run.players[alice] and run.players[bob] and run.players[carl], "participants")
	assert(ShipS.record().plan.seed == auroraSeed, "the waiting Aurora was not reused")
	print(string.format("        Aurora (seed %d) built over %d frames", auroraSeed, frames))
end)

check("round start: crew at the bow of the lowest deck, full oxygen, loot on every spot, timers up", function()
	local plan = ShipS.record().plan
	for _, p in ipairs({ alice, bob, carl }) do
		local rel = ShipS.toLocal(rootOf(p).CFrame.Position)
		assert(math.abs(rel.Y - (plan.decks[1].y + 3)) < 0.5, p.Name .. " not on the lowest deck: " .. rel.Y)
		assert(rel.Z > plan.length - GameConfig.Ship.CellLength * (GameConfig.Ship.BowCells + 1), p.Name .. " not at the bow: " .. rel.Z)
		assert(p:GetAttribute("LL_State") == "Alive" and p:GetAttribute("LL_Oxygen") == 12 and p:GetAttribute("LL_InRound"), "attributes")
		assert(ShipS.aboard(rootOf(p).CFrame.Position), p.Name .. " not aboard")
	end
	assert(#LS.items() == #plan.loot, "loot spawned " .. #LS.items() .. "/" .. #plan.loot)
	for _, entry in ipairs(LS.items()) do
		assert(entry.model:IsDescendantOf(ShipS.record().model), "loot not on the ship")
		assert(math.abs(entry.prompt.HoldDuration - GameConfig.LootRules.PickupHold) < 1e-4, "pickup hold")
	end
	local launchAt = workspaceService:GetAttribute("LL_LaunchAt")
	assert(launchAt and math.abs(launchAt - workspaceService:GetServerTimeNow() - plan.def.RoundTime) < 1, "lifeboat timer")
	assert(workspaceService:GetAttribute("LL_NextLurch") and workspaceService:GetAttribute("LL_Tilt") == 0, "lurch timer")
	assert(count("Announce", "One boat") >= 1)
	assert(count("Notify", "Climb UP", alice) >= 1, "first-round tutorial hint")
end)

local function itemNear(pred)
	for _, entry in ipairs(LS.items()) do
		if entry.model.Parent and pred(entry) then
			return entry
		end
	end
	return nil
end
local function standAt(player, entry)
	putAt(player, entry.model:GetPivot().Position + V3.new(0, 3, 0))
end

check("loot: hold E to grab, 3 slots, weight slows you, too far refused, drop, legendary announced", function()
	local list = {}
	for _, entry in ipairs(LS.items()) do
		if #list < 4 and entry.model.Parent then
			table.insert(list, entry)
		end
	end
	putAt(alice, list[1].model:GetPivot().Position + V3.new(30, 3, 0))
	list[1].prompt.Triggered:Fire(alice)
	assert(#LS.carried(alice) == 0, "picked up from 30 studs")
	for i = 1, 3 do
		standAt(alice, list[i])
		list[i].prompt.Triggered:Fire(alice)
	end
	assert(#LS.carried(alice) == 3 and alice:GetAttribute("LL_Carried") ~= "", "3 items")
	standAt(alice, list[4])
	list[4].prompt.Triggered:Fire(alice)
	assert(#LS.carried(alice) == 3 and list[4].model.Parent, "4th item taken with 3 slots")
	assert(count("Notify", "hands are full", alice) >= 1)
	-- drop one, then grab a gold bar: heavy
	local before = #LS.items()
	remotes.DropLoot.OnServerEvent:Fire(alice, 1)
	assert(#LS.carried(alice) == 2 and #LS.items() == before + 1, "drop")
	remotes.DropLoot.OnServerEvent:Fire(alice, 0 / 0)
	remotes.DropLoot.OnServerEvent:Fire(alice, "x")
	local plan = ShipS.record().plan
	local gold = LS.spawnAt("GoldBar", CF.new(6, plan.decks[2].y, 60))
	standAt(alice, gold)
	gold.prompt.Triggered:Fire(alice)
	local speed = alice.Character.Humanoid.WalkSpeed
	assert(table.find(LS.carried(alice), "GoldBar") and speed < GameConfig.Move.Walk and math.abs(speed - LootMath.walkSpeed(LS.carried(alice))) < 1e-4, "gold bar didn't slow: " .. speed)
	-- a legendary find is announced server-wide
	local tiara = LS.spawnAt("RubyTiara", CF.new(-6, plan.decks[2].y, 70))
	standAt(bob, tiara)
	tiara.prompt.Triggered:Fire(bob)
	assert(count("Announce", "found the Ruby Tiara") >= 1 and DS.getProfile(bob).Stats.Legendaries == 1, "legendary not announced")
	-- drop it and grab it again: not a new find (no announcement spam, no stat farming)
	local announced = count("Announce", "found the Ruby Tiara")
	remotes.DropLoot.OnServerEvent:Fire(bob, table.find(LS.carried(bob), "RubyTiara"))
	local again = itemNear(function(e)
		return e.key == "RubyTiara"
	end)
	standAt(bob, again)
	again.prompt.Triggered:Fire(bob)
	assert(table.find(LS.carried(bob), "RubyTiara") and count("Announce", "found the Ruby Tiara") == announced and DS.getProfile(bob).Stats.Legendaries == 1, "re-grabbing a dropped legendary announced again")
	putAt(alice, DOCK(1))
	putAt(bob, DOCK(2))
	putAt(carl, DOCK(3))
end)

check("lurches: BRACE 2 s early, then ONE PivotTo sinks and tilts the ship bow-down; clients get both pivots", function()
	local model = ShipS.record().model
	local base = ShipS.record().base
	local plan = ShipS.record().plan
	local braces = count("Brace")
	local lurches = count("Lurch")
	local before = model:GetPivot()
	local bowBefore = shipPoint(CF.new(0, plan.decks[1].y, plan.length)).Y
	local prop = ShipS.record().loose[1].part
	local propBefore = prop.CFrame.Position
	local guard = 0
	while count("Brace") == braces do
		tick(DT)
		guard += 1
		assert(guard < 30 * 30, "no brace warning")
	end
	local warnedAt = fakeOs.clock()
	assert(count("Lurch") == lurches, "lurched without a warning")
	guard = 0
	while count("Lurch") == lurches do
		tick(DT)
		guard += 1
		assert(guard < 30 * 4, "no lurch after the brace")
	end
	local gap = fakeOs.clock() - warnedAt
	assert(math.abs(gap - GameConfig.Sinking.BraceTime) < 0.1, "brace gap " .. gap)
	local after = model:GetPivot()
	assert((after.Position - before.Position).Magnitude > 0.1 and after.Position.Y < before.Position.Y, "the pivot didn't sink")
	local tilt = LurchMath.tiltOf(after, base)
	assert(tilt > 0.1 and tilt < 4.5, "tilt " .. tilt)
	assert(shipPoint(CF.new(0, plan.decks[1].y, plan.length)).Y < bowBefore - 0.5, "bow didn't go down")
	local entry = lastFor("Lurch", nil)
	assert(typeof(entry.args[1]) == "CFrame" and typeof(entry.args[2]) == "CFrame" and entry.args[3].tilt > 0, "lurch payload")
	assert((entry.args[2].Position - after.Position).Magnitude < 1e-3, "clients got the wrong pivot")
	assert((prop.CFrame.Position - propBefore).Magnitude > 0.05, "loose props didn't ride the lurch")
	assert(workspaceService:GetAttribute("LL_Tilt") == entry.args[3].tilt and workspaceService:GetAttribute("LL_Lurch") == 1)
	-- the next lurch is 18-25 s away
	local nextIn = workspaceService:GetAttribute("LL_NextLurch") - workspaceService:GetServerTimeNow()
	assert(nextIn >= plan.def.LurchEvery[1] - 0.1 and nextIn <= plan.def.LurchEvery[2] + 0.1, "next lurch in " .. nextIn)
end)

check("valve wheel: +6 s on the next lurch, once per valve", function()
	local v = OS.valves()[1]
	putAt(alice, v.wheel.CFrame.Position + V3.new(0, 1, 0))
	local before = workspaceService:GetAttribute("LL_NextLurch")
	v.prompt.Triggered:Fire(alice)
	local after = workspaceService:GetAttribute("LL_NextLurch")
	assert(math.abs(after - before - GameConfig.Sinking.ValveDelay) < 1e-6, "valve delay " .. (after - before))
	assert(v.used and count("Notify", "closed a valve", bob) >= 1)
	v.prompt.Triggered:Fire(bob)
	assert(workspaceService:GetAttribute("LL_NextLurch") == after, "valve used twice")
	putAt(alice, DOCK(1))
end)

check("bulkhead: two crew on two levers at once opens it; one lever alone (not solo) does not", function()
	local b = OS.bulkheads()[1]
	putAt(alice, b.levers[1].handle.CFrame.Position + V3.new(0, 0, 1.5))
	putAt(bob, b.levers[2].handle.CFrame.Position + V3.new(0, 0, 1.5))
	b.levers[1].prompt.Triggered:Fire(alice)
	assert(not b.open and count("Notify", "needs TWO crew", alice) >= 1, "one lever opened it with 3 alive")
	b.levers[1].prompt.PromptButtonHoldBegan:Fire(alice)
	tick(DT * 2)
	assert(not b.open, "opened with one lever held")
	b.levers[1].prompt.PromptButtonHoldBegan:Fire(bob) -- Bob is too far from lever 1
	tick(DT)
	assert(b.holders[1].player == alice, "a far lever hold counted")
	b.levers[2].prompt.PromptButtonHoldBegan:Fire(bob)
	tick(DT * 2)
	assert(b.open and not b.door.CanCollide, "both levers did not open the door")
	tick(1.3)
	local doorLocal = ShipS.toLocal(b.door.CFrame.Position)
	local wasLocal = b.doorLocal.Position
	assert(doorLocal.Y - wasLocal.Y > 6, "door didn't slide up")
	assert(count("Notify", "Bulkhead open", carl) >= 1)
	putAt(alice, DOCK(1))
	putAt(bob, DOCK(2))
end)

check("hazards: steam bursts on a telegraphed timer (knockback + damage)", function()
	local h
	for _, x in ipairs(OS.hazards()) do
		if x.kind == "Steam" then
			h = x
			break
		end
	end
	local point = OS.hazardPoint(h)
	bob.Character.Humanoid.Health = 100
	local knocks = count("Knockback", nil, bob)
	local warned = false
	local hissed = count("WorldSound", "SteamHiss")
	tick(GameConfig.Hazards.Steam.Period + 0.2, function()
		putAt(bob, OS.hazardPoint(h) + V3.new(1, 3, 0))
		if h.state == "Warn" then
			warned = true
		end
	end)
	assert(warned and count("WorldSound", "SteamHiss") > hissed, "no warning before the burst")
	assert(count("Knockback", nil, bob) > knocks, "no knockback")
	assert(bob.Character.Humanoid.Health < 100, "no damage")
	local _ = point
	putAt(bob, DOCK(2))
	bob.Character.Humanoid.Health = 100
end)

check("hazards: a chandelier shows its shadow on BRACE and drops on the lurch", function()
	local guard = 0
	local warnedH = nil
	local braces = count("Brace")
	while count("Brace") == braces do
		tick(DT)
		guard += 1
		assert(guard < 30 * 30, "no brace")
	end
	for _, x in ipairs(OS.hazards()) do
		if x.kind == "Chandelier" and x.warned then
			warnedH = x
		end
	end
	assert(warnedH and warnedH.src.shadow.Transparency < 0.5, "no warning shadow")
	-- a valve pushes this lurch back after its BRACE: the second BRACE warns no extra chandelier
	ShipS.delayNextLurch(GameConfig.Sinking.ValveDelay)
	braces = count("Brace")
	while count("Brace") == braces do
		tick(DT)
	end
	local warnedCount = 0
	for _, x in ipairs(OS.hazards()) do
		if x.kind == "Chandelier" and x.warned then
			warnedCount += 1
		end
	end
	assert(warnedCount == GameConfig.Hazards.Chandelier.PerLurch and warnedH.warned, "a delayed lurch warned " .. warnedCount .. " chandeliers")
	carl.Character.Humanoid.Health = 100
	local ringY = warnedH.src.model:GetPivot().Position.Y
	local lurches = count("Lurch")
	tick(GameConfig.Sinking.BraceTime + 0.2, function()
		putAt(carl, OS.hazardPoint(warnedH) + V3.new(0.5, 3, 0))
	end)
	assert(count("Lurch") > lurches and warnedH.dropped, "it didn't drop")
	assert(warnedH.src.model:GetPivot().Position.Y < ringY - 5, "it didn't fall")
	assert(carl.Character.Humanoid.Health <= 100 - GameConfig.Hazards.Chandelier.Damage + 1e-6 or SS.record(carl).state == "Downed", "no damage underneath")
	assert(count("WorldSound", "ChandelierFall") >= 1 and warnedH.src.shadow.Transparency == 1)
	putAt(carl, DOCK(3))
	carl.Character.Humanoid.Health = 100
end)

check("hazards: sparking wires only zap once flooded, and only players underwater", function()
	local h
	for _, x in ipairs(OS.hazards()) do
		if x.kind == "Wires" then
			h = x
		end
	end
	local guard = 0
	while h.src.spark.CFrame.Position.Y >= -4 and guard < 14 do
		ShipS.lurchNow()
		guard += 1
	end
	assert(h.src.spark.CFrame.Position.Y < -4, "wires never flooded deep")
	local rec = SS.record(bob)
	rec.oxygen = rec.max
	local sparkPos = h.src.spark.CFrame.Position
	tick(GameConfig.Hazards.Wires.Period + 0.1, function()
		putAt(bob, sparkPos + V3.new(1, 0, 0))
	end)
	local expected = rec.max - (GameConfig.Hazards.Wires.Period + 0.1)
	assert(rec.oxygen <= expected - GameConfig.Oxygen.ZapLoss + 0.2, string.format("no zap: %.2f vs %.2f", rec.oxygen, expected))
	assert(count("Notify", "ZAP", bob) >= 1)
	putAt(bob, DOCK(2))
	tick(4)
	assert(rec.oxygen == rec.max, "oxygen didn't refill above water")
end)

check("drowning: oxygen drains underwater -> DOWNED (floats, can't move); revive by holding E with 50% oxygen", function()
	local rec = SS.record(carl)
	carl:SetAttribute("LL_Oxygen", rec.max)
	underwater(carl)
	tick(GameConfig.Oxygen.Base - 1)
	assert(rec.state == "Alive" and rec.oxygen > 0 and rec.oxygen < 2, "oxygen " .. rec.oxygen)
	tick(1.2, function()
		if rec.state == "Alive" then
			underwater(carl)
		end
	end)
	assert(rec.state == "Downed" and carl:GetAttribute("LL_State") == "Downed", "not downed")
	local root = rootOf(carl)
	assert(root.Anchored and root.CFrame.Position.Y >= 0.4, "not floating at the surface: " .. root.CFrame.Position.Y)
	assert(carl.Character.Humanoid.WalkSpeed == 0 and carl.Character.Humanoid.PlatformStand, "downed player can move")
	assert(rec.prompt and rec.prompt.HoldDuration == GameConfig.Downed.ReviveHold, "no revive prompt")
	assert(carl:GetAttribute("LL_BleedEnds"), "no bleed-out timer")
	assert(count("Notify", "Carl is down", alice) >= 1, "team not told")
	-- revive attempts
	putAt(bob, root.CFrame.Position + V3.new(30, 0, 0))
	rec.prompt.Triggered:Fire(bob)
	assert(rec.state == "Downed", "revived from 30 studs")
	rec.prompt.Triggered:Fire(carl)
	assert(rec.state == "Downed", "revived himself")
	putAt(bob, root.CFrame.Position + V3.new(3, 0, 0))
	rec.prompt.PromptButtonHoldBegan:Fire(bob)
	assert(carl:GetAttribute("LL_ReviveStart"), "revive progress not shown")
	tick(1)
	rec.prompt.Triggered:Fire(bob)
	assert(rec.state == "Alive" and math.abs(rec.oxygen - rec.max * 0.5) < 1e-6, "not revived with 50% oxygen")
	assert(not root.Anchored and carl.Character.Humanoid.WalkSpeed > 0, "still stuck")
	assert(SS.record(bob).revives == 1 and DS.getProfile(bob).Stats.Revives == 1, "revive not counted")
	assert(count("Notify", "Goal complete: Revive a teammate", bob) >= 1, "session goal")
	putAt(bob, DOCK(2))
	putAt(carl, DOCK(3))
end)

check("bleed-out: 20 s downed with nobody coming = OUT (spectate from the dock, carried loot lost)", function()
	local rec = SS.record(carl)
	local plan = ShipS.record().plan
	local item = LS.spawnAt("PocketWatch", CF.new(6, plan.decks[#plan.decks].y, 30))
	standAt(carl, item)
	item.prompt.Triggered:Fire(carl)
	assert(#LS.carried(carl) == 1)
	rec.oxygen = 0.05
	underwater(carl)
	tick(DT * 3)
	assert(rec.state == "Downed")
	tick(GameConfig.Downed.BleedOut - 1)
	assert(rec.state == "Downed", "bled out early")
	tick(1.2)
	assert(rec.state == "Out" and carl:GetAttribute("LL_State") == "Out", "never bled out")
	assert(#LS.carried(carl) == 0 and carl:GetAttribute("LL_Carried") == "", "carried loot kept")
	assert(not ShipS.aboard(rootOf(carl).CFrame.Position) and rootOf(carl).CFrame.Position.X < GameConfig.World.DockX[2], "not sent to the dock")
	assert(count("Notify", "lost at sea", carl) >= 1)
end)

check("life jacket: auto-revives you once per round (the MAYDAY code gives one)", function()
	local ok = RW.redeem(bob, "mayday")
	assert(ok and DS.getProfile(bob).Boosts.LifeJacket == 1, "MAYDAY")
	assert(not RW.redeem(bob, "MAYDAY"), "code used twice")
	local rec = SS.record(bob)
	rec.oxygen = 0.05
	underwater(bob)
	tick(DT * 3)
	assert(rec.state == "Downed")
	tick(GameConfig.Downed.LifeJacketDelay + 0.2)
	assert(rec.state == "Alive" and DS.getProfile(bob).Boosts.LifeJacket == 0 and rec.jacketsUsed == 1, "jacket didn't save him")
	DS.getProfile(bob).Boosts.LifeJacket = 3
	rec.oxygen = 0.05
	underwater(bob)
	tick(DT * 3)
	tick(GameConfig.Downed.LifeJacketDelay + 0.5)
	assert(rec.state == "Downed" and DS.getProfile(bob).Boosts.LifeJacket == 3, "a second jacket used in the same round")
end)

check("rescue flare: revives downed teammates nearby and points everyone at the lifeboat", function()
	SH.buy(alice, "Flare")
	assert(DS.getProfile(alice).Boosts.Flare == 1, "Studio flare grant")
	local bobRoot = rootOf(bob)
	putAt(alice, bobRoot.CFrame.Position + V3.new(10, 0, 0))
	remotes.UseFlare.OnServerEvent:Fire(alice)
	assert(SS.record(bob).state == "Alive", "flare didn't revive bob")
	assert(DS.getProfile(alice).Boosts.Flare == 0 and count("FlareArrow", nil, bob) >= 1 and count("FlareArrow", nil, alice) >= 1, "no route arrow")
	remotes.UseFlare.OnServerEvent:Fire(alice)
	assert(count("Notify", "No Rescue Flares", alice) >= 1, "used a flare it didn't have")
	putAt(alice, DOCK(1))
	putAt(bob, DOCK(2))
end)

check("solo bulkhead: when you're the only one up, holding one lever for 4 s opens it", function()
	local rec = SS.record(bob)
	DS.getProfile(bob).Boosts.LifeJacket = 0
	rec.oxygen = 0.05
	underwater(bob)
	tick(DT * 3)
	assert(rec.state == "Downed" and SS.record(carl).state == "Out", "setup: only Alice up")
	local b = OS.bulkheads()[2]
	assert(b.levers[1].prompt.HoldDuration == GameConfig.Obstacles.SoloHold, "solo hold time")
	putAt(alice, b.levers[2].handle.CFrame.Position + V3.new(0, 0, 1.5))
	b.levers[2].prompt.Triggered:Fire(alice)
	assert(b.open, "solo lever didn't open the door")
	-- Alice revives Bob
	putAt(alice, rootOf(bob).CFrame.Position + V3.new(2, 0, 0))
	rec.prompt.Triggered:Fire(alice)
	assert(rec.state == "Alive", "revive")
	putAt(alice, DOCK(1))
	putAt(bob, DOCK(2))
end)

check("grapple hook: pass required, server-validated range / surface / cooldown", function()
	local root = rootOf(alice)
	local target = root.CFrame.Position + V3.new(0, 10, 20)
	raycastHook = function()
		return { Position = target, Instance = world.spawn }
	end
	remotes.Grapple.OnServerEvent:Fire(alice, target)
	assert(count("GrappleOk", nil, alice) == 0, "grappled without the pass")
	SH.buy(alice, "Grapple")
	assert(alice:GetAttribute("LL_Grapple") == true, "pass attribute")
	tick(1)
	assert(AS.grapple(alice, target), "valid grapple refused")
	assert(count("GrappleOk", nil, alice) == 1 and alice:GetAttribute("LL_GrappleReady"))
	assert(not AS.grapple(alice, target), "cooldown ignored")
	tick(GameConfig.Grapple.Cooldown + 0.1)
	assert(not AS.grapple(alice, root.CFrame.Position + V3.new(0, 0, 80)), "beyond 40 studs")
	assert(not AS.grapple(alice, V3.new(0 / 0, 0, 0)), "NaN target")
	assert(not AS.grapple(alice, "x"), "junk target")
	raycastHook = function()
		return nil
	end
	assert(not AS.grapple(alice, target), "grappled into thin air")
	raycastHook = function()
		return { Position = target, Instance = world.spawn }
	end
	assert(AS.grapple(alice, target), "grapple after cooldown")
	raycastHook = nil
end)

check("guard: a late joiner waits on the dock and is sent back if they get aboard", function()
	local dan = makePlayer("Dan")
	assert(not RSv.run().players[dan], "late joiner pulled into the round")
	putAt(dan, deckPoint(#ShipS.record().plan.decks, -6, 40))
	tick(DT * 2)
	assert(not ShipS.aboard(rootOf(dan).CFrame.Position), "spectator stayed on the ship")
	assert(count("Notify", "underway", dan) >= 1)
	leave(dan)
end)

local function seat(player, i)
	local zone = ShipS.record().lifeboat.zone
	putAt(player, zone.CFrame.Position + V3.new((i - 1.5) * 2, 0.5, 0))
end

check("anti-teleport: jumping into the lifeboat from across the ship is refused for the round", function()
	LB.setLaunchAt(fakeOs.clock() + 120)
	local far = deckPoint(#ShipS.record().plan.decks, 0, ShipS.record().plan.length - 30)
	putAt(alice, far)
	tick(1.2)
	assert(not SS.record(alice).flagged, "walking flagged")
	-- a raw teleport (what an exploit client does): no forgetTrack
	local zone = ShipS.record().lifeboat.zone
	local root = rootOf(alice)
	setPos(root, zone.CFrame.Position + V3.new(0, 0.5, 0))
	setPos(alice.Character.Head, zone.CFrame.Position + V3.new(0, 2, 0))
	tick(0.5)
	assert(SS.record(alice).flagged and not SS.record(alice).aboard, "teleporter boarded")
	assert(count("Notify", "Movement check", alice) >= 1)
	-- reset for the rest of the run
	SS.record(alice).flagged = nil
	putAt(alice, far)
	tick(0.3)
end)

local aliceCoinsBefore, aliceItems, bobCoinsBefore
check("lifeboat: FULL CREW aboard launches early -> cinematic -> ESCAPED with loot x ship x 1.25 x2 pass", function()
	SH.buy(alice, "DoubleLoot")
	LB.setLaunchAt(fakeOs.clock() + 120)
	aliceItems = table.clone(LS.carried(alice))
	assert(#aliceItems >= 2, "alice carries " .. #aliceItems)
	aliceCoinsBefore = DS.getProfile(alice).Coins
	bobCoinsBefore = DS.getProfile(bob).Coins
	local carlCoins = DS.getProfile(carl).Coins
	seat(alice, 1)
	tick(1)
	assert(SS.record(alice).aboard and alice:GetAttribute("LL_Aboard") and not LB.launched(), "aboard alone launched (Bob is still up)")
	seat(bob, 2)
	tick(1)
	assert(count("Announce", "FULL CREW aboard") >= 1, "no full-crew countdown")
	assert(not LB.launched(), "launched before the hold")
	tick(GameConfig.Lifeboat.FullCrewHold, function()
		if not LB.launched() then
			seat(alice, 1)
			seat(bob, 2)
		end
	end)
	assert(LB.launched() and RSv.phase() == "Launching", "no early launch: " .. RSv.phase())
	assert(RSv.run().fullCrew and count("Cinematic", "Launch") >= 1, "cinematic")
	assert(SS.record(alice).state == "Escaped" and SS.record(bob).state == "Escaped")
	local boat = ShipS.record().lifeboat.model
	local boatStart = boat:GetPivot().Position
	local shipBefore = ShipS.record().model:GetPivot().Position.Y
	tick(GameConfig.Lifeboat.CinematicTime * 0.8)
	assert(boat:GetPivot().Position.Y < boatStart.Y - 5 and math.abs(boat:GetPivot().Position.Y - 0.9) < 1, "the boat didn't lower to the sea")
	assert((rootOf(alice).CFrame.Position - boat:GetPivot().Position).Magnitude < 8, "Alice isn't in the boat")
	assert(ShipS.record().model:GetPivot().Position.Y < shipBefore, "no final plunge")
	tick(GameConfig.Lifeboat.CinematicTime * 0.3)
	assert(RSv.phase() == "Results", "no results: " .. RSv.phase())
	local summary = RSv.lastSummary
	local a, b, c = summary.players[alice], summary.players[bob], summary.players[carl]
	assert(a.outcome == "Escaped" and b.outcome == "Escaped" and c.outcome == "Lost", "outcomes")
	local expectA = LootMath.payout({ escaped = true, items = aliceItems, shipKey = "Aurora", fullCrew = true, double = true, revives = SS.record(alice).revives })
	assert(a.coins == expectA.coins and DS.getProfile(alice).Coins - aliceCoinsBefore >= expectA.coins, string.format("alice paid %d, expected %d", a.coins, expectA.coins))
	assert(a.double and a.fullCrew and a.banked == LootMath.value(aliceItems))
	assert(b.coins > 0 and not b.double, "bob")
	assert(c.coins == GameConfig.Rewards.Participation and DS.getProfile(carl).Coins - carlCoins == c.coins, "lost-at-sea participation reward")
	assert(DS.getProfile(alice).Stats.Escapes == 4 and DS.getProfile(alice).Stats.LootBanked == LootMath.value(aliceItems), "stats")
	assert(DS.getProfile(alice).Tutorial.Done, "tutorial not marked done")
	assert(#a.escapedNames == 2 and #a.goals == 3, "results card data")
	assert(lastFor("Results", alice) and lastFor("Results", carl), "results not sent")
	print(string.format("        Alice banked %d -> %d coins (x%.2f Aurora, Full Crew, x2)", a.banked, a.coins, GameConfig.Ships.Aurora.LootMult))
end)

check("after the round: everyone back on the dock, the sunk ship scrapped, a fresh Gull moored", function()
	tick(GameConfig.Round.ResultsTime + 0.2)
	assert(RSv.phase() == "Lobby", RSv.phase())
	for _, p in ipairs({ alice, bob, carl }) do
		assert(not rootOf(p).Anchored and rootOf(p).CFrame.Position.X < GameConfig.World.DockX[2], p.Name .. " not on the dock")
		assert(p:GetAttribute("LL_State") == "Lobby" and p:GetAttribute("LL_Carried") == "", p.Name .. " state")
	end
	assert((ShipS.building() or ShipS.ready("Gull")) and ShipS.key() == "Gull", "no fresh Gull")
	local frames = 0
	while not ShipS.ready("Gull") do
		tick(DT)
		frames += 1
		assert(frames < 400)
	end
	assert(#workspaceService.LastLifeboatShips:GetChildren() <= 2, "old ships left behind")
end)
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
		assert(frames < 700, "ship never finished building")
	end
	assert(RSv.phase() == "Running", "not running: " .. RSv.phase())
	return RSv.run(), frames
end

local dan
check("timed launch + leaving mid-round: the boat leaves on time with whoever is aboard; the rest are LOST AT SEA", function()
	dan = makePlayer("Dan")
	local round = startRound("Gull")
	assert(round.shipKey == "Gull" and round.players[dan], "Gull round")
	-- Dan grabs loot and holds a lever, then leaves
	local item = LS.items()[1]
	standAt(dan, item)
	item.prompt.Triggered:Fire(dan)
	assert(#LS.carried(dan) == 1)
	local b = OS.bulkheads()[1]
	if b then
		putAt(dan, b.levers[1].handle.CFrame.Position + V3.new(0, 0, 1.5))
		b.levers[1].prompt.PromptButtonHoldBegan:Fire(dan)
		assert(b.holders[1] and b.holders[1].player == dan)
	end
	leave(dan)
	assert(#LS.carried(dan) == 0, "a leaver kept loot")
	assert(not b or b.holders[1] == nil, "a leaver still holds the lever")
	assert(SS.record(dan).state == "Left")
	-- Bob stays off the boat, Alice boards; the timer runs out
	putAt(bob, DOCK(2))
	putAt(carl, DOCK(3))
	LB.setLaunchAt(fakeOs.clock() + 2)
	tick(2.2, function()
		seat(alice, 1)
	end)
	assert(LB.launched() and not RSv.run().fullCrew, "timed launch didn't happen / counted as full crew")
	tick(GameConfig.Lifeboat.CinematicTime + 0.2)
	assert(RSv.phase() == "Results")
	local s = RSv.lastSummary
	assert(s.players[alice].outcome == "Escaped" and s.players[bob].outcome == "Lost" and s.players[dan] == nil, "outcomes")
	assert(s.players[bob].coins == GameConfig.Rewards.Participation, "lost player paid " .. s.players[bob].coins)
	assert(s.players[alice].coins >= GameConfig.Rewards.EscapeBase and not s.players[alice].fullCrew)
	tick(GameConfig.Round.ResultsTime + 0.2)
	assert(RSv.phase() == "Lobby")
end)

check("a round always ends: everyone leaving aborts it; nobody left alive launches the boat empty", function()
	-- Carl died on the dock during the countdown: he boards when he respawns (not counted out)
	carl.Character.Humanoid.Health = 0
	local round = startRound("Gull")
	assert(SS.record(carl).state == "Alive" and not ShipS.aboard(rootOf(carl).CFrame.Position), "corpse moved aboard / counted out")
	local fresh = newCharacter("Carl", world.spawnCFrame.Position)
	carl.Character = fresh
	carl.CharacterAdded:Fire(fresh)
	flushDeferred()
	assert(SS.record(carl).state == "Alive" and ShipS.aboard(rootOf(carl).CFrame.Position), "respawned crew member not boarded")
	-- everyone down and out -> the boat launches empty
	for _, p in ipairs({ alice, bob, carl }) do
		DS.getProfile(p).Boosts.LifeJacket = 0
		SS.record(p).oxygen = 0.05
		underwater(p)
	end
	tick(DT * 3)
	tick(GameConfig.Downed.BleedOut + 0.5)
	assert(LB.launched() or RSv.phase() ~= "Running", "the round didn't end with everyone out")
	tick(GameConfig.Lifeboat.CinematicTime + 0.5)
	assert(RSv.phase() == "Results" and RSv.lastSummary.escaped == 0, "results")
	assert(count("Announce", "launched... empty") >= 1)
	tick(GameConfig.Round.ResultsTime + 0.2)
	local _ = round
	-- a solo round where the only player leaves -> back to the lobby, no results
	local eve = makePlayer("Eve")
	for _, p in ipairs({ alice, bob, carl }) do
		RSv.setReady(p, false)
	end
	RSv.setReady(eve, true)
	tick(GameConfig.Round.ReadyTimeout + GameConfig.Round.Countdown + 1)
	local guard = 0
	while RSv.phase() ~= "Running" and guard < 900 do
		tick(DT)
		guard += 1
	end
	assert(RSv.phase() == "Running", "solo round didn't start")
	for p in pairs(RSv.run().players) do
		if p ~= eve then
			leave(p)
		end
	end
	leave(eve)
	tick(DT * 2)
	assert(RSv.phase() == "Lobby" and RSv.run() == nil, "not aborted: " .. RSv.phase())
	alice, bob, carl = makePlayer("Alice2"), makePlayer("Bob2"), makePlayer("Carl2")
end)

check("upgrades: coins buy levels (atomic), effects reach the attributes, maxed refused", function()
	local p = DS.getProfile(alice)
	p.Coins = 149
	assert(not US.buy(alice, "Lungs"), "bought without enough coins")
	assert(p.Coins == 149 and p.Upgrades.Lungs == 0)
	p.Coins = 100000
	for level = 1, 5 do
		assert(US.buy(alice, "Lungs"), "level " .. level)
	end
	assert(not US.buy(alice, "Lungs") and p.Upgrades.Lungs == 5, "bought past max")
	assert(alice:GetAttribute("LL_OxygenMax") == 25, "lungs attribute")
	US.buy(alice, "Slots")
	assert(alice:GetAttribute("LL_Slots") == 4, "slots attribute")
	remotes.BuyUpgrade.OnServerEvent:Fire(alice, "Grip")
	assert(p.Upgrades.Grip == 1 and alice:GetAttribute("LL_GripMult") == 0.85)
	remotes.BuyUpgrade.OnServerEvent:Fire(alice, { "Swim" })
	remotes.BuyUpgrade.OnServerEvent:Fire(alice, "Wings")
	assert(p.Upgrades.Swim == 0 and p.Upgrades.Wings == nil, "junk upgrade")
	SH.buy(alice, "VIP")
	assert(alice:GetAttribute("LL_Slots") == 5 and alice.Character.Head.LL_NameTag.Label.Text == "[VIP] Alice2", "VIP slot / gold name")
	assert(alice:GetAttribute("LL_VIP") == true)
	SH.buy(alice, "Captain")
	assert(alice.Character:FindFirstChild("LL_Outfit") and alice.Character.LL_Outfit:FindFirstChild("CapCrown"), "captain's outfit")
	for _, d in ipairs(alice.Character.LL_Outfit:GetChildren()) do
		assert(not d.CanCollide and d.Massless and d:FindFirstChildOfClass("WeldConstraint"), d.Name .. " not inert")
	end
end)

check("daily streak once a day, codes once, session goals once", function()
	local p = DS.getProfile(bob)
	local coins = p.Coins
	assert(RW.claimDaily(bob) and p.Coins == coins + GameConfig.DailyRewards[1])
	assert(not RW.claimDaily(bob), "claimed twice in a day")
	advance(86400)
	assert(RW.claimDaily(bob) and p.Daily.Streak == 2, "streak")
	assert(RW.redeem(bob, "release") and not RW.redeem(bob, "RELEASE"), "RELEASE")
	assert(RW.redeem(bob, "ABANDONSHIP") and not RW.redeem(bob, "nope"))
	local goals = RW.goalsView(bob)
	assert(#goals == 3 and goals[1].text == "Escape 2 times")
end)

local function receipt(player, id, productId)
	return stubServices.MarketplaceService.ProcessReceipt({ PlayerId = player.UserId, ProductId = productId or 7101, PurchaseId = id })
end
check("receipts: granted exactly once when sent twice; refused when the profile can't persist live or is leaving", function()
	local gus = makePlayer("Gus")
	local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
	local notYet = roblox.Enum.ProductPurchaseDecision.NotProcessedYet
	local p = DS.getProfile(gus)
	assert(receipt(gus, "r-1") == granted and p.Boosts.LifeJacket == 1 and p.Receipts["r-1"])
	assert(receipt(gus, "r-1") == granted, "retry not acknowledged")
	assert(p.Boosts.LifeJacket == 1, "life jacket granted twice")
	assert(receipt(gus, "c-1", 7103) == granted and p.Coins == 500)
	assert(receipt(gus, "c-1", 7103) == granted and p.Coins == 500, "coins granted twice")
	assert(gus:GetAttribute("LL_Jackets") == 1, "attribute not refreshed")
	isStudio = false
	local hal = makePlayer("Hal")
	local decision = receipt(hal, "r-live")
	isStudio = true
	assert(decision == notYet and DS.getProfile(hal).Boosts.LifeJacket == 0, "live purchase granted on a non-persistent profile")
	assert(stubServices.MarketplaceService.ProcessReceipt({ PlayerId = 999999, ProductId = 7101, PurchaseId = "x" }) == notYet, "unknown player")
	assert(stubServices.MarketplaceService.ProcessReceipt({ PlayerId = gus.UserId, ProductId = 4242, PurchaseId = "y" }) == notYet, "unknown product")
	leave(hal)
	-- buying with an id of 0 in a live game says "not available"
	isStudio = false
	SH.buy(gus, "Flare")
	isStudio = true
	assert(count("Notify", "isn't available yet", gus) >= 1 and DS.getProfile(gus).Boosts.Flare == 0)
end)

check("settings: only known keys with legal values are saved", function()
	local p = DS.getProfile(bob)
	registry.PlayerService.saveSettings(bob, { Music = 0.3, Master = 7, Effects = 0 / 0, CameraShake = "no", ReducedEffects = true, Hack = true })
	assert(p.Settings.Music == 0.3 and p.Settings.Master == 1, "numbers not clamped")
	assert(p.Settings.Effects == 1, "NaN accepted")
	assert(p.Settings.CameraShake == true and p.Settings.ReducedEffects == true and p.Settings.Hack == nil)
end)

check("remote spam and junk arguments are rejected", function()
	for _ = 1, 30 do
		remotes.SetReady.OnServerEvent:Fire(carl, true)
		remotes.Vote.OnServerEvent:Fire(carl, { "Gull" })
	end
	remotes.Vote.OnServerEvent:Fire(carl, nil)
	remotes.Grapple.OnServerEvent:Fire(carl, nil)
	remotes.UseFlare.OnServerEvent:Fire(carl, "lots")
	remotes.DropLoot.OnServerEvent:Fire(carl, math.huge)
	remotes.RedeemCode.OnServerEvent:Fire(carl, string.rep("A", 5000))
	remotes.BuyUpgrade.OnServerEvent:Fire(carl, nil)
	remotes.ShopBuy.OnServerEvent:Fire(carl, string.rep("x", 100))
	remotes.SaveSettings.OnServerEvent:Fire(carl, "loud")
	remotes.RequestState.OnServerEvent:Fire(carl)
	remotes.ClaimDaily.OnServerEvent:Fire(carl, 1, 2, 3)
	local p = DS.getProfile(carl)
	assert(p.Coins >= 0 and p.Upgrades.Lungs == 0, "junk changed the profile")
	for _, pl in ipairs(playerList) do
		RSv.setReady(pl, false)
	end
	tick(DT)
end)

check("session lock: load locks, migration runs before defaults, a taken-over profile stops saving, leaving unlocks", function()
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
	local holdNext = false
	local fakeStore = {
		UpdateAsync = function(_, k, fn)
			if holdNext then
				holdNext = false
				coroutine.yield() -- a slow DataStore call: the test resumes it later
			end
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
		-- an old profile with no Version: migration must see it as version 1, not "current"
		stored["player_" .. (nextUserId + 1)] = { Coins = 777, Upgrades = { Lungs = 9, Wings = 2 }, Boosts = { LifeJacket = 0 / 0 }, Stats = { Escapes = 5, Bad = "x" } }
		local ivy = makePlayer("Ivy")
		local key = "player_" .. ivy.UserId
		local p = DS.getProfile(ivy)
		assert(DS.isPersistent(ivy) and p.Coins == 777, "saved profile not loaded")
		assert(p.Version == GameConfig.SchemaVersion, "not migrated")
		assert(p.Upgrades.Lungs == 5 and p.Upgrades.Wings == nil and p.Boosts.LifeJacket == 0 and p.Stats.Bad == nil and p.Stats.Escapes == 5, "saved data not validated")
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
		-- a purchase on a persistent profile is saved before it's granted
		assert(receipt(jo, "p-1") == roblox.Enum.ProductPurchaseDecision.PurchaseGranted and stored[joKey].Receipts["p-1"], "receipt not saved before granting")
		-- Roblox retries a receipt while the first call is still saving: not acknowledged early
		local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
		local jackets = DS.getProfile(jo).Boosts.LifeJacket
		holdNext = true
		local slow = coroutine.create(function()
			return receipt(jo, "p-2")
		end)
		assert(coroutine.resume(slow) and coroutine.status(slow) == "suspended", "save didn't yield")
		assert(receipt(jo, "p-2") == roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "acknowledged a receipt whose save is still in flight")
		local resumed, first = coroutine.resume(slow)
		assert(resumed and first == granted and stored[joKey].Receipts["p-2"], "slow save not granted")
		assert(receipt(jo, "p-2") == granted and DS.getProfile(jo).Boosts.LifeJacket == jackets + 1, "granted twice")
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

check("client controllers initialise and render real server data (lobby, round HUD, lurch, downed, results, every menu tab)", function()
	local kim = makePlayer("Kim")
	local snapshot = DS.sendProfileNow(kim)
	assert(snapshot and snapshot.daily and snapshot.goals and snapshot.effects and snapshot.passes, "snapshot incomplete")
	requireModule(Shared.Net).setup()
	local playerGui = roblox.Instance.new("PlayerGui")
	playerGui.Parent = kim
	fakePlayers.LocalPlayer = kim
	stubServices.RunService.IsServer = function()
		return false
	end
	local camera = roblox.Instance.new("Camera")
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	camera.CFrame = CF.new(-40, 12, -20)
	camera.Parent = workspaceService
	workspaceService.CurrentCamera = camera
	local folder = place:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("LastLifeboatClient"):FindFirstChild("Controllers")
	local names = { "ClientState", "AudioController", "InputController", "MovementController", "HudController", "MenuController", "EffectsController", "SocialController" }
	local controllers = {}
	for _, name in ipairs(names) do
		controllers[name] = requireModule(folder[name])
		controllers[name].init()
	end
	local ClientState = controllers.ClientState
	ClientState.profile = snapshot
	ClientState.settings = table.clone(snapshot.settings)
	ClientState.ProfileChanged:Fire(snapshot)
	for _, name in ipairs({ "LifeboatHUD", "LifeboatMenu", "LifeboatFx" }) do
		assert(playerGui:FindFirstChild(name), name .. " missing")
		assert(playerGui[name]:FindFirstChildOfClass("UIScale"), name .. " has no UIScale")
	end
	local Hud = controllers.HudController
	local hud = playerGui.LifeboatHUD
	-- lobby panel with live counts, locked ships marked
	ClientState.round = RSv.state()
	ClientState.RoundChanged:Fire(ClientState.round)
	Hud.tick()
	assert(hud.Lobby.Visible and string.find(hud.Lobby.Status.Text, "ready", 1, true), "lobby panel")
	assert(hud.Lobby.Cards.Leviathan.Vote.Text == "LOCKED" and hud.Lobby.Cards.Gull.Vote.Text == "VOTE", "lock state on the cards")
	assert(Hud.lobbyText({ phase = "Lobby", players = 3, ready = 1, autoStartIn = 20 }) == "1/3 ready - starting in 20s")
	assert(Hud.timerText(133) == "LIFEBOAT LAUNCHES IN 2:13")
	hud.Lobby.Cards.Gull.Vote.Activated:Fire()
	assert(clientSent[#clientSent].name == "Vote" and clientSent[#clientSent].args[1] == "Gull", "vote button")
	hud.Lobby.Ready.Activated:Fire()
	assert(clientSent[#clientSent].name == "SetReady" and clientSent[#clientSent].args[1] == true, "ready button")
	-- a real round through the client
	local run2 = startRound("Gull")
	ClientState.round = RSv.state()
	ClientState.RoundChanged:Fire(ClientState.round)
	assert(ClientState.inRound() and run2.players[kim], "client doesn't know it's in the round")
	ClientState.team = RSv.team()
	ClientState.TeamChanged:Fire(ClientState.team)
	Hud.tick()
	assert(not hud.Lobby.Visible, "lobby panel during the round")
	assert(hud.TopBar.Visible and string.find(hud.TopBar.Timer.Text, "LIFEBOAT LAUNCHES IN", 1, true), "timer: " .. hud.TopBar.Timer.Text)
	assert(hud.Oxygen.Visible and string.find(hud.Oxygen.Bar.Label.Text, "OXYGEN", 1, true), "oxygen bar")
	assert(hud.Tilt.Visible and hud.Tilt.TiltText.Text == "TILT 0°", "tilt indicator")
	local slots = 0
	for _, c in ipairs(hud.Slots:GetChildren()) do
		if c:IsA("TextButton") then
			slots += 1
		end
	end
	assert(slots == 3, "loot slots " .. slots)
	local rows = 0
	for _, c in ipairs(hud.Team:GetChildren()) do
		if c:IsA("Frame") then
			rows += 1
		end
	end
	assert(rows == #ClientState.team and rows >= 2, "team rows " .. rows)
	-- pick up a valuable: the slot shows it in its rarity colour
	local entry = LS.items()[1]
	standAt(kim, entry)
	entry.prompt.Triggered:Fire(kim)
	Hud.tick()
	local slot1 = hud.Slots:FindFirstChild("Slot1")
	assert(slot1 and slot1:FindFirstChildOfClass("ViewportFrame") and slot1.Name and slot1:FindFirstChild("Name"), "slot doesn't show the item")
	assert(slot1.UIStroke.Color == requireModule(Shared.Models).rarityColor(GameConfig.Loot[entry.key].Rarity), "rarity colour")
	slot1.Activated:Fire()
	assert(clientSent[#clientSent].name == "DropLoot" and clientSent[#clientSent].args[1] == 1, "tap to drop")
	-- BRACE + LURCH: the client moves its own character with the ship, upright
	local Move = controllers.MovementController
	local kimRoot = rootOf(kim)
	local plan = ShipS.record().plan
	putAt(kim, deckPoint(2, -5, 60))
	kimRoot.CFrame = CF.lookAt(kimRoot.CFrame.Position, kimRoot.CFrame.Position + V3.new(1, 0, 0))
	local relBefore = ShipS.toLocal(kimRoot.CFrame.Position)
	local braces = count("Brace")
	while count("Brace") == braces do
		tick(DT)
	end
	ClientState.Braced:Fire(2)
	Hud.tick()
	assert(hud.Brace.Visible, "no BRACE! on screen")
	local Fx = controllers.EffectsController
	assert(Fx.step(1 / 60) == true and playerGui.LifeboatFx.BraceFlash.Visible, "no red flash")
	local lurches = count("Lurch")
	while count("Lurch") == lurches do
		tick(DT)
	end
	local entryL = lastFor("Lurch", nil)
	local moved = Move.onLurch(entryL.args[1], entryL.args[2], entryL.args[3])
	assert(moved, "the client didn't move the character on the lurch")
	local relAfter = ShipS.toLocal(kimRoot.CFrame.Position)
	assert((relAfter - relBefore).Magnitude < 0.3, string.format("character slid off its spot: %.2f", (relAfter - relBefore).Magnitude))
	assert(math.abs(kimRoot.CFrame.UpVector.Y - 1) < 1e-4, "character tilted with the ship")
	assert(entryL.args[3].seq and entryL.args[3].length == plan.length and entryL.args[3].height, "lurch remote lacks seq / ship box")
	-- the same lurch delivered twice moves you once
	local spot = kimRoot.CFrame.Position
	assert(Move.onLurch(entryL.args[1], entryL.args[2], entryL.args[3]) == nil and (kimRoot.CFrame.Position - spot).Magnitude < 1e-6, "lurch applied twice")
	-- the remote arrives BEFORE the ship's new CFrame: wait for the ship, then move by the remote's delta
	local shipModel = ShipS.record().model
	local p0 = shipModel:GetPivot()
	local p1 = p0 * CF.new(0, -3, 0) * CF.Angles(math.rad(1), 0, 0)
	local early = table.clone(entryL.args[3])
	early.seq += 1
	relBefore = p0:PointToObjectSpace(kimRoot.CFrame.Position)
	assert(Move.onLurch(p0, p1, early) == nil and (kimRoot.CFrame.Position - spot).Magnitude < 1e-6, "moved before the ship did")
	shipModel:PivotTo(p1)
	Move.step(1 / 60)
	assert((p1:PointToObjectSpace(kimRoot.CFrame.Position) - relBefore).Magnitude < 0.3, "not moved once the ship arrived")
	shipModel:PivotTo(p0)
	-- off the ship: a lurch doesn't touch you
	putAt(kim, DOCK(4))
	local again = table.clone(entryL.args[3])
	again.seq += 2
	assert(Move.onLurch(entryL.args[1], entryL.args[2], again) == nil, "dock character moved by a lurch")
	-- slide force on a steep deck, reduced by Grip
	workspaceService:SetAttribute("LL_Tilt", 22)
	local steep = LurchMath.pivot(ShipS.record().base, 0, 22)
	ShipS.record().model:PivotTo(steep)
	putAt(kim, deckPoint(#plan.decks, -6, 40))
	local slide = Move.slideNow()
	assert(slide.Magnitude > 0 and slide.Y == 0, "no slide on a 22 degree deck")
	kim:SetAttribute("LL_GripMult", 0.3)
	assert(math.abs(Move.slideNow().Magnitude - slide.Magnitude * 0.3) < 1e-3, "grip")
	Move.step(1 / 60)
	assert(kimRoot:FindFirstChild("LL_SlideForce"), "no slide force")
	-- speed: heavy loot slows, downed stops
	kim:SetAttribute("LL_Carried", "GoldBar,Painting")
	assert(Move.speedNow() == LootMath.walkSpeed({ "GoldBar", "Painting" }) and Move.speedNow() < 16)
	kim:SetAttribute("LL_Carried", "")
	-- knockback and grapple pull
	Move.knockback(V3.new(10, 5, 0))
	assert(Move.startGrapple(kimRoot.CFrame.Position + V3.new(0, 0, 20)) and Move.grappling(), "grapple pull")
	Move.step(1 / 30)
	assert(kimRoot:FindFirstChildOfClass("Beam") or kimRoot:FindFirstChild("Attachment"), "no grapple rope")
	-- underwater grade
	camera.CFrame = CF.new(GameConfig.World.ShipX + 90, -10, 0)
	for _ = 1, 30 do
		Fx.step(1 / 30)
	end
	assert(place:GetService("Lighting").LL_Blur.Size > 3, "no underwater blur")
	camera.CFrame = CF.new(-40, 12, -20)
	-- downed overlay with a revive progress bar
	local krec = SS.record(kim)
	krec.oxygen = 0.05
	underwater(kim)
	tick(DT * 3)
	assert(krec.state == "Downed")
	Hud.tick()
	assert(hud.Downed.Visible and string.find(hud.Downed.Timer.Text, "Bleeding out in", 1, true), "downed overlay")
	assert(not hud.Downed.Revive.Visible, "revive bar without a reviver")
	local helper = nil
	for p in pairs(RSv.run().players) do
		if p ~= kim and SS.record(p) and SS.record(p).state == "Alive" then
			helper = p
		end
	end
	putAt(helper, rootOf(kim).CFrame.Position + V3.new(2, 0, 0))
	krec.prompt.PromptButtonHoldBegan:Fire(helper)
	advance(1)
	Hud.tick()
	assert(hud.Downed.Revive.Visible and hud.Downed.Revive:FindFirstChildWhichIsA("Frame").Fill.Size.X.Scale > 0.3, "revive progress")
	krec.prompt.Triggered:Fire(helper)
	assert(krec.state == "Alive")
	-- input: M toggles the menu, F flare (none), Q grapple without pass is refused locally
	local UiModule = requireModule(folder.Ui)
	local Input = controllers.InputController
	UiModule.closeAll()
	assert(Input.handle(roblox.Enum.KeyCode.M, true) and UiModule.isOpen("Menu"), "M did not open the menu")
	Input.handle(roblox.Enum.KeyCode.ButtonSelect, true)
	assert(not UiModule.isOpen("Menu"), "Select did not close the menu")
	assert(Input.handle(roblox.Enum.KeyCode.Q, true), "Q")
	assert(Input.handle(roblox.Enum.KeyCode.F, true) and clientSent[#clientSent].name == "UseFlare", "F flare")
	-- every menu tab renders
	local Menu = controllers.MenuController
	ClientState.leaderboard = { Escapes = { { userId = kim.UserId, name = "Kim", value = 3 } }, Banked = {} }
	for _, tab in ipairs(Menu.TABS) do
		Menu.open(tab)
		local n = 0
		for _, d in ipairs(Menu.content():GetDescendants()) do
			if d:IsA("TextButton") or d:IsA("TextLabel") then
				n += 1
			end
		end
		assert(n >= 3, tab .. " tab is empty")
	end
	Menu.open("Shop")
	local prices = {}
	for _, d in ipairs(Menu.content():GetDescendants()) do
		if d:IsA("TextButton") and d.Name == "Buy" then
			table.insert(prices, d.Text)
		end
	end
	assert(#prices == #ShopConfig.Products + #ShopConfig.Passes and table.find(prices, "R$ 25") and table.find(prices, "R$ 299"), "shop prices: " .. table.concat(prices, ", "))
	Menu.open("Upgrades")
	local buys = 0
	for _, d in ipairs(Menu.content():GetDescendants()) do
		if d:IsA("TextButton") and d.Name == "Buy" then
			buys += 1
		end
	end
	assert(buys == 5, "upgrade cards " .. buys)
	ClientState.MenuRequested:Fire("Daily")
	assert(UiModule.isOpen("Menu"), "kiosk prompt didn't open the menu")
	UiModule.closeAll()
	-- audio
	local Audio = controllers.AudioController
	assert(Audio.musicFor(false) == "LobbyMusic" and Audio.musicFor(true, 300) == "RoundMusic" and Audio.musicFor(true, 30) == "FinalMinute")
	local cue = Audio.step(1 / 60)
	assert(cue.music == "RoundMusic" and Audio.playing("Music") and Audio.playing("Hum"), "round audio")
	assert(Audio.onWorldSound("Waves") == nil, "an empty slot played")
	assert(Audio.onWorldSound("Lever", V3.new()) ~= nil, "a filled slot didn't play")
	-- chat tag
	kim:SetAttribute("LL_VIP", true)
	assert(controllers.SocialController.prefixFor(kim), "no VIP chat tag")
	-- the launch: letterbox and results card
	for p in pairs(RSv.run().players) do
		if SS.record(p) and SS.record(p).state == "Alive" then
			seat(p, 1)
		end
	end
	tick(GameConfig.Lifeboat.FullCrewHold + 0.5, function()
		for p in pairs(RSv.run() and RSv.run().players or {}) do
			if not LB.launched() and SS.record(p) and SS.record(p).state == "Alive" then
				seat(p, 1)
			end
		end
	end)
	assert(LB.launched(), "no launch")
	local cine = lastFor("Cinematic", nil)
	ClientState.Cinematic:Fire(cine.args[1], cine.args[2])
	Hud.tick()
	assert(hud.Letterbox.Visible, "no letterbox")
	Fx.step(1 / 60)
	assert(camera.CameraType == roblox.Enum.CameraType.Scriptable, "cinematic camera")
	tick(GameConfig.Lifeboat.CinematicTime + 0.3)
	assert(RSv.phase() == "Results", RSv.phase())
	local result = lastFor("Results", kim).args[1]
	Hud.showResults(result)
	assert(Hud.resultsShown() and hud.Results.Visible and hud.Results.Title.Text == "ESCAPED!", "results card")
	local lines = 0
	for _, d in ipairs(hud.Results.Body:GetDescendants()) do
		if d.Name == "Line" then
			lines += 1
		end
	end
	assert(lines >= 6, "results lines " .. lines)
	tick(GameConfig.Round.ResultsTime + 0.2)
	assert(RSv.phase() == "Lobby")
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
