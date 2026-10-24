--[[
	MatchService - lobby queue, countdown, rounds, contestants, eliminations, rewards,
	kill feed and streak announcements.

	A contestant is a player or a bot taking part in the current round:
	  { id, name, isBot, player?, userId?, model, alive, kills, streak, parries,
	    startedAt, eliminatedAt, cosmetics, loadout, shieldReady, parryMemo, skill? }

	States: "Lobby" -> "Countdown" -> "Playing" -> "Results" -> "Lobby".
	Player attribute RR_Status: "Lobby" | "Arena" | "Out" (eliminated / spectating).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local GameConfig = require(Shared.Config.GameConfig)
local ArenaConfig = require(Shared.Config.ArenaConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local Clock = require(Shared.Clock)
local ArenaBuilder = require(script.Parent.ArenaBuilder)

local MatchService = {}

local services
local lobby
local state = "Lobby"
local countdown = 0
local contestants = {}
local byId = {}
local arena
local roundStartedAt = 0
local roundNumber = 0
local ready = {}
local lastReadyToggle = {}

local L = GameConfig.Lobby

function MatchService.init(registry)
	services = registry
end

function MatchService.setLobby(l)
	lobby = l
end

function MatchService.lobby()
	return lobby
end

function MatchService.state()
	return state
end

function MatchService.arena()
	return arena
end

function MatchService.roundStartedAt()
	return roundStartedAt
end

function MatchService.contestants()
	return contestants
end

function MatchService.get(id)
	return byId[id]
end

function MatchService.forPlayer(player)
	return byId["p" .. player.UserId]
end

function MatchService.alive()
	local list = {}
	for _, c in ipairs(contestants) do
		if c.alive then
			table.insert(list, c)
		end
	end
	return list
end

function MatchService.rootOf(c)
	local model = c and c.model
	if not model or not model.Parent then
		return nil
	end
	return model:FindFirstChild("HumanoidRootPart")
end

-- Uses CFrame.Position (identical to Position in Roblox) so the Lune harness can track it.
function MatchService.positionOf(c)
	local root = MatchService.rootOf(c)
	return root and root.CFrame.Position
end

local function humanCount()
	local n = 0
	for _, c in ipairs(contestants) do
		if not c.isBot then
			n += 1
		end
	end
	return n
end

local function setStatus(player, status)
	if player and player.Parent then
		player:SetAttribute("RR_Status", status)
	end
end

local function lobbyStatus(text, color)
	if lobby then
		lobby.setStatus(text, color)
	end
end

function MatchService.isReady(player)
	return ready[player] == true
end

function MatchService.readyPlayers()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if ready[player] and services.DataService.getProfile(player) then
			table.insert(list, player)
		end
	end
	return list
end

function MatchService.roster()
	local list = {}
	for _, c in ipairs(contestants) do
		table.insert(list, {
			id = c.id,
			name = c.name,
			isBot = c.isBot,
			userId = c.userId,
			alive = c.alive,
			kills = c.kills,
			vip = c.vip,
			trail = c.cosmetics.Trail,
		})
	end
	return list
end

function MatchService.sendRoster()
	services.Remotes.Roster:FireAllClients(MatchService.roster())
end

local function aliveCount()
	return #MatchService.alive()
end

function MatchService.broadcastState(player)
	local data = {
		countdown = countdown,
		alive = aliveCount(),
		total = #contestants,
		theme = arena and arena.theme,
		arenaName = arena and arena.name,
		round = roundNumber,
		startedAt = roundStartedAt,
		readyCount = #MatchService.readyPlayers(),
	}
	if player then
		services.Remotes.MatchState:FireClient(player, state, data)
	else
		services.Remotes.MatchState:FireAllClients(state, data)
	end
end

---------------------------------------------------------------------------------------------
-- Tags (VIP / bot labels)
---------------------------------------------------------------------------------------------

local function tagFor(model, text, color)
	local head = model and model:FindFirstChild("Head")
	if not head then
		return
	end
	local existing = head:FindFirstChild("RR_Tag")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RR_Tag"
	gui.Size = UDim2.fromOffset(160, 26)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	return gui
end

function MatchService.refreshTags(player)
	local character = player.Character
	if character and services.ShopService.owns(player, "VIP") then
		tagFor(character, "VIP  " .. player.DisplayName, Color3.fromRGB(255, 210, 70))
	end
	local c = MatchService.forPlayer(player)
	if c then
		c.vip = services.ShopService.owns(player, "VIP")
	end
end

MatchService.tagFor = tagFor

function MatchService.refreshCosmetics(player)
	local c = MatchService.forPlayer(player)
	if c then
		c.cosmetics = services.CosmeticService.equippedFor(player)
	end
end

---------------------------------------------------------------------------------------------
-- Round flow
---------------------------------------------------------------------------------------------

-- Fills contestant defaults into `c` (bots keep their BotService table) and registers it.
local function newContestant(c)
	local defaults = {
		alive = true,
		kills = 0,
		streak = 0,
		parries = 0,
		startedAt = Clock.now(),
		parryMemo = {},
		loadout = {},
		cosmetics = {},
		shieldReady = false,
	}
	for k, v in pairs(defaults) do
		if c[k] == nil then
			c[k] = v
		end
	end
	table.insert(contestants, c)
	byId[c.id] = c
	return c
end

local function pickTheme(opts)
	if opts and opts.theme then
		return opts.theme
	end
	local index = (roundNumber % #ArenaConfig.Order) + 1
	return ArenaConfig.Order[index]
end

--[[
	Starts a round with every ready player (plus bots to fill a near-empty server).
	opts = { theme?, seed?, bots? (override count) }. Returns true when a round started.
]]
function MatchService.startMatch(opts)
	if state == "Playing" or state == "Results" then
		return false
	end
	local humans = {}
	for _, player in ipairs(MatchService.readyPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and character:FindFirstChild("HumanoidRootPart") then
			table.insert(humans, player)
		end
		if #humans >= L.MaxContestants then
			break
		end
	end
	if #humans == 0 or (#humans < L.MinHumans and not L.AllowSoloWithBots) then
		state = "Lobby"
		return false
	end

	local theme = pickTheme(opts)
	roundNumber += 1
	arena = ArenaBuilder.build(theme, (opts and opts.seed) or (os.time() + roundNumber), workspace)
	workspace:SetAttribute("RR_Theme", theme)
	table.clear(contestants)
	table.clear(byId)
	roundStartedAt = Clock.now()

	for i, player in ipairs(humans) do
		local profile = services.DataService.getProfile(player)
		local loadout = table.clone(profile.Loadout)
		local maxSlots = if services.ShopService.owns(player, "ExtraSlot") then AbilityConfig.MaxSlotsWithPass else AbilityConfig.MaxSlots
		while #loadout > maxSlots do
			table.remove(loadout)
		end
		local c = newContestant({
			id = "p" .. player.UserId,
			name = player.DisplayName,
			isBot = false,
			player = player,
			userId = player.UserId,
			model = player.Character,
			loadout = loadout,
			cosmetics = services.CosmeticService.equippedFor(player),
			vip = services.ShopService.owns(player, "VIP"),
		})
		c.shieldReady = table.find(loadout, "Shield") ~= nil
		local spawnCf = arena.spawns[((i - 1) % #arena.spawns) + 1]
		player.Character:PivotTo(spawnCf)
		setStatus(player, "Arena")
	end

	local botCount = if opts and opts.bots then opts.bots else math.max(0, L.FillToContestants - #humans)
	if #humans >= L.FillToContestants then
		botCount = 0
	end
	for i, bot in ipairs(services.BotService.spawn(botCount, arena, #humans)) do
		local c = newContestant(bot)
		local spawnCf = arena.spawns[((#humans + i - 1) % #arena.spawns) + 1]
		c.model:PivotTo(spawnCf)
	end

	state = "Playing"
	countdown = 0
	lobbyStatus(string.format("ROUND %d - %s", roundNumber, string.upper(arena.name)), Color3.fromRGB(255, 120, 200))
	MatchService.sendRoster()
	MatchService.broadcastState()
	services.Remotes.Announce:FireAllClients(string.format("ROUND %d: %s! %d contestants", roundNumber, string.upper(arena.name), #contestants), "round")
	services.BallService.begin(arena)
	return true
end

local function explosionColorFor(killer)
	local id = killer and killer.cosmetics and killer.cosmetics.Explosion
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Id == id then
			return item
		end
	end
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Category == "Explosion" and item.Default then
			return item
		end
	end
	return nil
end

function MatchService.partyActive()
	return (workspace:GetAttribute("RR_PartyUntil") or 0) > Clock.now()
end

--[[
	Eliminates a contestant. killerId may be nil (environment / no deflect yet).
	cause: "ball" | "fell" | "left" | "reset"
]]
function MatchService.eliminate(c, killerId, cause, data)
	if not c or not c.alive or state ~= "Playing" then
		return false
	end
	c.alive = false
	c.eliminatedAt = Clock.now()
	local killer = killerId and byId[killerId]
	if killer == c then
		killer = nil
	end
	local position = MatchService.positionOf(c)
	if killer then
		killer.kills += 1
		killer.streak += 1
		if killer.player then
			services.RewardService.track(killer.player, "Kills", 1)
		end
		local streakName = GameConfig.KillStreakNames[math.min(killer.streak, 6)]
		if killer.streak >= 2 and streakName then
			services.Remotes.Announce:FireAllClients(string.format("%s - %s!", killer.name, streakName), "streak")
		end
	end
	local explosion = explosionColorFor(killer)
	if position and cause ~= "left" then
		services.Remotes.Fx:FireAllClients("Explode", {
			pos = position,
			victim = c.id,
			color = explosion and explosion.Color,
			rainbow = explosion and explosion.Rainbow,
			confetti = MatchService.partyActive(),
		})
	end
	services.Remotes.KillFeed:FireAllClients({
		killer = killer and killer.name,
		killerBot = killer and killer.isBot,
		victim = c.name,
		victimBot = c.isBot,
		cause = cause,
		speed = data and data.speed and math.floor(data.speed),
	})

	if c.isBot then
		services.BotService.kill(c)
	elseif c.player then
		setStatus(c.player, "Out")
		local humanoid = c.model and c.model:FindFirstChildOfClass("Humanoid")
		if humanoid and cause ~= "left" then
			humanoid.Health = 0
		end
	end
	MatchService.sendRoster()
	MatchService.broadcastState()
	MatchService.checkEnd()
	return true
end

function MatchService.checkEnd()
	if state ~= "Playing" then
		return
	end
	local alive = MatchService.alive()
	if #alive <= 1 then
		MatchService.endRound(alive[1])
	end
end

function MatchService.endRound(winner)
	if state ~= "Playing" then
		return
	end
	state = "Results"
	services.BallService.stop()
	local now = Clock.now()
	local ranked = humanCount() >= 2
	local standings = {}
	for _, c in ipairs(contestants) do
		table.insert(standings, { name = c.name, isBot = c.isBot, kills = c.kills, won = c == winner, survived = math.floor((c.eliminatedAt or now) - c.startedAt) })
	end
	table.sort(standings, function(a, b)
		if a.won ~= b.won then
			return a.won
		end
		return a.survived > b.survived
	end)
	for _, c in ipairs(contestants) do
		if c.player and c.player.Parent then
			local won = c == winner
			local reward = services.RewardService.payRound(c.player, {
				kills = c.kills,
				won = won,
				survivedSeconds = (c.eliminatedAt or now) - c.startedAt,
				parries = c.parries,
				ranked = ranked,
			})
			local profile = services.DataService.getProfile(c.player)
			services.Remotes.Results:FireClient(c.player, {
				won = won,
				winner = winner and winner.name,
				winnerBot = winner and winner.isBot,
				ranked = ranked,
				reward = reward,
				streak = profile and profile.WinStreak or 0,
				standings = standings,
			})
			services.DataService.sendProfile(c.player)
			if won and ranked and profile and profile.WinStreak >= GameConfig.WinStreakAnnounceFrom then
				services.Remotes.Announce:FireAllClients(string.format("%s is on a %d WIN STREAK!", c.name, profile.WinStreak), "streak")
			end
		end
	end
	if winner then
		services.Remotes.Announce:FireAllClients(string.format("%s%s WINS ROUND %d!", winner.name, if winner.isBot then " [BOT]" else "", roundNumber), "win")
		services.Remotes.Fx:FireAllClients("Win", { id = winner.id, pos = MatchService.positionOf(winner) })
	end
	lobbyStatus(if winner then string.upper(winner.name) .. " WINS!" else "ROUND OVER", Color3.fromRGB(255, 210, 70))
	MatchService.broadcastState()
	task.delay(L.ResultsSeconds, MatchService.returnToLobby)
end

function MatchService.returnToLobby()
	if state ~= "Results" then
		return
	end
	for _, c in ipairs(contestants) do
		if c.player and c.player.Parent then
			local character = c.player.Character
			if c.alive and character and lobby then
				character:PivotTo(lobby.spawnCFrame)
			end
			setStatus(c.player, "Lobby")
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("RR_Status") ~= "Lobby" then
			setStatus(player, "Lobby")
		end
	end
	services.BotService.clear()
	if arena then
		arena.destroy()
		arena = nil
	end
	workspace:SetAttribute("RR_Theme", nil)
	table.clear(contestants)
	table.clear(byId)
	state = "Lobby"
	MatchService.sendRoster()
	MatchService.broadcastState()
end

---------------------------------------------------------------------------------------------
-- Lobby loop
---------------------------------------------------------------------------------------------

function MatchService.tickLobby()
	if state == "Lobby" or state == "Countdown" then
		local readyList = MatchService.readyPlayers()
		local enough = #readyList >= L.MinHumans or (#readyList >= 1 and L.AllowSoloWithBots)
		if not enough then
			if state == "Countdown" then
				state = "Lobby"
				MatchService.broadcastState()
			end
			lobbyStatus(string.format("WAITING FOR PLAYERS  (%d ready)", #readyList))
			return
		end
		if state == "Lobby" then
			state = "Countdown"
			countdown = if #readyList >= L.MinHumans then L.CountdownFull else L.Countdown
		else
			countdown -= 1
			if #readyList >= L.MinHumans then
				countdown = math.min(countdown, L.CountdownFull)
			end
		end
		if countdown <= 0 then
			MatchService.startMatch()
		else
			lobbyStatus(string.format("NEXT ROUND IN %d", countdown), Color3.fromRGB(120, 230, 255))
			MatchService.broadcastState()
		end
	elseif state == "Playing" then
		-- Falling off the arena.
		for _, c in ipairs(MatchService.alive()) do
			local pos = MatchService.positionOf(c)
			if not pos or (arena and pos.Y < arena.killY) then
				MatchService.eliminate(c, nil, if pos then "fell" else "left")
			end
		end
		lobbyStatus(string.format("ROUND %d - %d ALIVE", roundNumber, aliveCount()), Color3.fromRGB(255, 120, 200))
	end
end

local function onCharacter(player, character)
	local status = player:GetAttribute("RR_Status")
	if state == "Playing" and status == "Arena" then
		-- A respawn while still listed alive (e.g. reset): count it as an elimination.
		MatchService.eliminate(MatchService.forPlayer(player), nil, "reset")
	end
	if player:GetAttribute("RR_Status") ~= "Lobby" and state ~= "Playing" then
		setStatus(player, "Lobby")
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			local c = MatchService.forPlayer(player)
			if c and c.alive and c.model == character then
				MatchService.eliminate(c, nil, "reset")
			end
		end)
	end
	task.defer(MatchService.refreshTags, player)
end

function MatchService.playerAdded(player)
	setStatus(player, if state == "Playing" then "Out" else "Lobby")
	ready[player] = true
	player:SetAttribute("RR_Ready", true)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

function MatchService.setReady(player, value)
	ready[player] = value == true
	player:SetAttribute("RR_Ready", ready[player])
	MatchService.broadcastState()
end

function MatchService.start()
	local remotes = services.Remotes
	remotes.SetReady.OnServerEvent:Connect(function(player, value)
		local now = os.clock()
		if type(value) ~= "boolean" or (lastReadyToggle[player] and now - lastReadyToggle[player] < 0.4) then
			return
		end
		lastReadyToggle[player] = now
		MatchService.setReady(player, value)
	end)
	remotes.RequestState.OnServerEvent:Connect(function(player)
		MatchService.broadcastState(player)
		remotes.Roster:FireClient(player, MatchService.roster())
		services.DataService.sendProfile(player)
		services.RewardService.sendGoals(player)
		services.BallService.syncTo(player)
	end)
	Players.PlayerAdded:Connect(MatchService.playerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		MatchService.playerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local c = MatchService.forPlayer(player)
		if c then
			MatchService.eliminate(c, nil, "left")
		end
		ready[player] = nil
		lastReadyToggle[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			MatchService.tickLobby()
		end
	end)
end

return MatchService
