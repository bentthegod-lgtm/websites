--[[
	EventService - server-wide luck and FOMO events.

	  * Lucky Hour: the first 10 minutes of every UTC hour, luck x2 (same moment in every
	    server, so players learn to come back for it).
	  * Admin events: every 15 minutes a random event runs for 3 minutes (Cash Rain, Mythic
	    Madness, Mutation Mayhem, Blobby Stampede, Double Cash). The HUD shows a countdown.
	  * Server Luck x2: bought with Robux (or from the day-3 daily reward) for the whole
	    server; time stacks up to GameConfig.Events.ServerLuckCap.
	Luck multiplies the spawn weights of Rare+ Blobbies (Spawner.rarityWeights).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local EventConfig = require(Shared.Config.EventConfig)
local Timers = require(Shared.Timers)
local Format = require(Shared.Format)

local EventService = {}

local services
local world
local startedAt = os.clock()
local serverLuckUntil = 0
local order = {}
local lastActiveKey = nil
local lastLucky = nil
local lastServerLuck = false
local coinTimer = 0
local coins = {}
local rng = Random.new()

local E = GameConfig.Events

function EventService.init(registry)
	services = registry
	startedAt = os.clock()
	-- Each server shuffles the admin event order so servers differ.
	order = {}
	for i = 1, #EventConfig.Admin do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
end

function EventService.setWorld(w)
	world = w
end

-- Test hook: pretend the server has been running for `seconds`.
function EventService.setElapsed(seconds)
	startedAt = os.clock() - seconds
end

function EventService.adminPhase()
	return Timers.adminPhase(os.clock() - startedAt, E)
end

function EventService.currentAdmin()
	local phase = EventService.adminPhase()
	if not phase.active then
		return nil, phase
	end
	return EventConfig.Admin[order[(phase.cycle % #order) + 1]], phase
end

function EventService.nextAdmin()
	local phase = EventService.adminPhase()
	local nextCycle = math.max(phase.cycle + 1, 0)
	return EventConfig.Admin[order[(nextCycle % #order) + 1]], phase.nextIn
end

function EventService.luckyHour()
	return Timers.luckyHour(os.time(), E.LuckyHourMinutes)
end

function EventService.serverLuckRemaining()
	return math.max(0, serverLuckUntil - os.clock())
end

function EventService.luck()
	local luck = 1
	if EventService.luckyHour() then
		luck *= EventConfig.LuckyHour.Luck
	end
	if EventService.serverLuckRemaining() > 0 then
		luck *= EventConfig.ServerLuck.Luck
	end
	return luck
end

local function adminField(field, default)
	local event = EventService.currentAdmin()
	return if event and event[field] then event[field] else default
end

function EventService.mythicBoost()
	return adminField("MythicBoost", 1)
end

function EventService.mutationBoost()
	return adminField("MutationBoost", 1)
end

function EventService.spawnRate()
	return adminField("SpawnRate", 1)
end

function EventService.speedMult()
	return adminField("SpeedMult", 1)
end

function EventService.incomeMult()
	return adminField("IncomeMult", 1)
end

function EventService.addServerLuck(seconds, fromName)
	serverLuckUntil = Timers.extendUntil(serverLuckUntil, os.clock(), seconds, E.ServerLuckCap)
	local text = if fromName
		then string.format("%s activated SERVER LUCK x2 for everyone! (%s left)", fromName, Format.time(EventService.serverLuckRemaining()))
		else string.format("SERVER LUCK x2 is active! (%s left)", Format.time(EventService.serverLuckRemaining()))
	services.FeedService.announce(text, EventConfig.ServerLuck.Color, true)
	services.Remotes.Sfx:FireAllClients("EventStart")
	EventService.broadcast()
end

function EventService.snapshot()
	local active = {}
	local admin, phase = EventService.currentAdmin()
	if admin then
		table.insert(active, { id = admin.Id, name = admin.Name, description = admin.Description, color = admin.Color, remaining = phase.remaining })
	end
	local lucky, luckyLeft = EventService.luckyHour()
	if lucky then
		local ev = EventConfig.LuckyHour
		table.insert(active, { id = ev.Id, name = ev.Name, description = ev.Description, color = ev.Color, remaining = luckyLeft })
	end
	local serverLuck = EventService.serverLuckRemaining()
	if serverLuck > 0 then
		local ev = EventConfig.ServerLuck
		table.insert(active, { id = ev.Id, name = ev.Name, description = ev.Description, color = ev.Color, remaining = serverLuck })
	end
	local nextEvent, nextIn = EventService.nextAdmin()
	return {
		active = active,
		nextName = nextEvent and nextEvent.Name,
		nextIn = nextIn,
		luckyIn = if lucky then 0 else luckyLeft,
		luck = EventService.luck(),
		mythicBoost = EventService.mythicBoost(),
		mutationBoost = EventService.mutationBoost(),
	}
end

function EventService.broadcast()
	services.Remotes.Events:FireAllClients(EventService.snapshot())
end

function EventService.sendTo(player)
	services.Remotes.Events:FireClient(player, EventService.snapshot())
end

---------------------------------------------------------------------------------------------
-- Cash Rain coins
---------------------------------------------------------------------------------------------

function EventService.coinValue(player)
	local ips = services.PlayerService.incomePerSecond(player)
	return math.max(E.CoinMinimum, math.floor(ips * E.CoinIncomeSeconds))
end

function EventService.collectCoin(player, coin)
	if not coins[coin] then
		return 0
	end
	coins[coin] = nil
	local position = coin.Position
	coin:Destroy()
	local amount = EventService.coinValue(player)
	services.PlayerService.addCash(player, amount)
	services.RewardService.recordGoal(player, "Coin", 1)
	services.Remotes.Popup:FireClient(player, "Cash", { amount = amount, position = position })
	services.Remotes.Sfx:FireClient(player, "Coin")
	return amount
end

function EventService.spawnCoin()
	local C = GameConfig.Carpet
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.4, 2.2, 2.2)
	coin.Color = Color3.fromRGB(255, 206, 50)
	coin.Material = Enum.Material.Neon
	coin.CanCollide = true
	coin.CanTouch = true
	coin.CanQuery = false
	coin.Anchored = false
	local x = (rng:NextNumber() - 0.5) * 2 * (C.Width / 2 + 9)
	local z = C.StartZ + 10 + rng:NextNumber() * (C.EndZ - C.StartZ - 20)
	coin.CFrame = CFrame.new(x, 45, z) * CFrame.Angles(0, rng:NextNumber() * 6, math.pi / 2)
	coins[coin] = os.clock()
	coin.Touched:Connect(function(hit)
		local player = hit.Parent and Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			EventService.collectCoin(player, coin)
		end
	end)
	coin.Parent = world and world.effects or workspace
	return coin
end

local function stepCoins(dt)
	local event = EventService.currentAdmin()
	if event and event.CashRain then
		coinTimer -= dt
		while coinTimer <= 0 do
			coinTimer += E.CoinInterval
			EventService.spawnCoin()
		end
	end
	local now = os.clock()
	for coin, born in pairs(coins) do
		if now - born > E.CoinLifetime or not coin.Parent then
			coins[coin] = nil
			coin:Destroy()
		end
	end
end

---------------------------------------------------------------------------------------------
-- Loop
---------------------------------------------------------------------------------------------

local function updateBoard()
	local board = world and world.eventBoard
	if not board then
		return
	end
	local snap = EventService.snapshot()
	local rows = board.rows
	for i = 1, #rows do
		rows[i].Text = ""
	end
	local line = 1
	for _, ev in ipairs(snap.active) do
		if line <= #rows then
			rows[line].Text = ev.name .. "  " .. Format.time(ev.remaining)
			rows[line].TextColor3 = Color3.fromRGB(ev.color[1], ev.color[2], ev.color[3])
			line += 1
		end
	end
	if line <= #rows then
		rows[line].Text = string.format("Next: %s in %s", snap.nextName or "?", Format.time(snap.nextIn))
		rows[line].TextColor3 = Color3.fromRGB(255, 255, 255)
		line += 1
	end
	if line <= #rows and snap.luckyIn > 0 then
		rows[line].Text = "Lucky Hour in " .. Format.time(snap.luckyIn)
		rows[line].TextColor3 = Color3.fromRGB(150, 255, 150)
		line += 1
	end
	if line <= #rows then
		rows[line].Text = string.format("Server luck: x%s", tostring(snap.luck))
		rows[line].TextColor3 = Color3.fromRGB(120, 220, 255)
	end
end

function EventService.step(dt)
	local admin = EventService.currentAdmin()
	local key = admin and admin.Id
	local changed = false
	if key ~= lastActiveKey then
		if admin then
			services.FeedService.announce(admin.Name .. "! " .. admin.Description, admin.Color, true)
			services.Remotes.Sfx:FireAllClients("EventStart")
			coinTimer = 0
		elseif lastActiveKey then
			services.FeedService.announce("The event is over. Next one in " .. Format.time(EventService.adminPhase().nextIn) .. "!", { 220, 220, 230 }, false)
		end
		lastActiveKey = key
		changed = true
	end
	local lucky = EventService.luckyHour()
	if lucky ~= lastLucky then
		if lucky and lastLucky ~= nil then
			services.FeedService.announce("LUCKY HOUR! Server luck x2 for 10 minutes!", EventConfig.LuckyHour.Color, true)
			services.Remotes.Sfx:FireAllClients("EventStart")
		end
		lastLucky = lucky
		changed = true
	end
	local serverLuck = EventService.serverLuckRemaining() > 0
	if serverLuck ~= lastServerLuck then
		lastServerLuck = serverLuck
		changed = true
	end
	if changed then
		EventService.broadcast()
	end
	stepCoins(dt)
end

function EventService.start()
	task.spawn(function()
		local elapsed = 0
		while true do
			local dt = task.wait(0.25) or 0.25
			EventService.step(dt)
			elapsed += dt
			if elapsed >= 1 then
				elapsed = 0
				updateBoard()
			end
		end
	end)
	-- A periodic full resync keeps client countdowns honest.
	task.spawn(function()
		while true do
			task.wait(15)
			EventService.broadcast()
		end
	end)
end

return EventService
