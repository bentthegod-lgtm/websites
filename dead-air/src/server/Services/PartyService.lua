--[[
	PartyService - lobby party elevators (Solo 1 / Duo 2 / Trio 3 / Squad 4).

	* Walk onto an elevator pad to join that party; the first one in is the leader and picks
	  the difficulty. Extra players beyond the elevator's size are not let in.
	* The elevator goes down when it is full, or when everyone on it presses READY
	  (so two friends can take a Squad elevator without waiting for strangers).
	* Live game: the party is teleported to its own reserved server, where RoundService runs
	  the descent and teleports everyone back to a lobby afterwards. Several parties can play
	  at the same time.
	* Studio / unpublished place / teleport failure: the run happens on this server instead,
	  and the elevators show "IN USE" until it finishes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("DeadAir")
local DifficultyConfig = require(Shared.Config.DifficultyConfig)

local PartyService = {}

local services
local lobby
local bays = {}
local readyPlayers = {}
local departingUntil = {} -- players mid-teleport: ignored by the pads so they are not sent twice
local enabled = true
local COUNTDOWN = 5

function PartyService.init(registry)
	services = registry
end

-- True on a reserved server created for one party's run.
function PartyService.isRunServer()
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local function canTeleport()
	return not RunService:IsStudio() and game.PlaceId ~= 0
end

function PartyService.bayOf(player)
	for _, bay in ipairs(bays) do
		if table.find(bay.members, player) then
			return bay
		end
	end
	return nil
end

local function displayName(player)
	return player.DisplayName
end

---------------------------------------------------------------------------------------------
-- Broadcast
---------------------------------------------------------------------------------------------

function PartyService.broadcast()
	local runParty = services.RoundService.currentParty()
	local members = {}
	for _, player in ipairs(runParty or Players:GetPlayers()) do
		if player.Parent then
			local profile = services.DataService.getProfile(player)
			local bay = PartyService.bayOf(player)
			table.insert(members, {
				userId = player.UserId,
				name = player.DisplayName,
				ready = readyPlayers[player] == true,
				status = player:GetAttribute("DA_Status") or "Lobby",
				level = profile and services.DataService.levelFor(profile.Xp) or 1,
				bay = bay and bay.id,
				host = bay ~= nil and bay.members[1] == player,
			})
		end
	end
	local bayList = {}
	for _, bay in ipairs(bays) do
		local names = {}
		for _, p in ipairs(bay.members) do
			table.insert(names, { name = displayName(p), userId = p.UserId, ready = readyPlayers[p] == true })
		end
		table.insert(bayList, {
			id = bay.id,
			size = bay.size,
			members = names,
			leaderUserId = bay.members[1] and bay.members[1].UserId,
			difficulty = bay.difficulty,
			countdown = bay.countdownEndsAt and math.max(0, bay.countdownEndsAt - os.clock()) or nil,
			locked = not enabled or services.RoundService.isBusy(),
		})
	end
	services.Remotes.Party:FireAllClients({
		members = members,
		bays = bayList,
		state = services.RoundService.state(),
		pressure = services.RoundService.pressure(),
	})
end

local function updateBoards()
	if not lobby then
		return
	end
	local busy = services.RoundService.isBusy()
	for _, bay in ipairs(bays) do
		local text
		if not enabled then
			text = "PRIVATE RUN"
		elseif busy then
			text = "IN USE - PLEASE WAIT"
		elseif bay.countdownEndsAt then
			text = string.format("DOORS CLOSING  %d", math.ceil(math.max(0, bay.countdownEndsAt - os.clock())))
		elseif #bay.members == 0 then
			text = "EMPTY"
		else
			text = string.format("%d / %d  -  %s", #bay.members, bay.size, string.upper(bay.difficulty))
		end
		lobby:setBayStatus(bay.record, text, bay.countdownEndsAt ~= nil)
	end
end

---------------------------------------------------------------------------------------------
-- Launch
---------------------------------------------------------------------------------------------

local function teleportParty(party, difficulty)
	local ok, err = pcall(function()
		local code = TeleportService:ReserveServer(game.PlaceId)
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		local userIds = {}
		for _, p in ipairs(party) do
			table.insert(userIds, p.UserId)
		end
		options:SetTeleportData({ party = userIds, difficulty = difficulty })
		TeleportService:TeleportAsync(game.PlaceId, party, options)
	end)
	if not ok then
		warn("[DeadAir] Party teleport failed: " .. tostring(err))
	end
	return ok
end

local function launch(bay)
	local party = table.clone(bay.members)
	local difficulty = bay.difficulty
	table.clear(bay.members)
	bay.countdownEndsAt = nil
	for _, p in ipairs(party) do
		readyPlayers[p] = nil
	end
	if #party == 0 then
		return
	end
	if canTeleport() and teleportParty(party, difficulty) then
		for _, p in ipairs(party) do
			departingUntil[p] = os.clock() + 30
			services.Remotes.Notify:FireClient(p, "Descending...", "info")
		end
		return
	end
	services.RoundService.startRun(party, difficulty)
end

---------------------------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------------------------

local function tick()
	local changed = false
	local busy = services.RoundService.isBusy()
	-- Membership from who is standing on which pad.
	for _, player in ipairs(Players:GetPlayers()) do
		local state = services.PlayerService.get(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local departing = departingUntil[player] and os.clock() < departingUntil[player]
		local record = enabled and not departing and root and state and not state.inRound and lobby:bayAt(root.Position)
		local current = PartyService.bayOf(player)
		local target
		for _, bay in ipairs(bays) do
			if record and bay.record == record then
				target = bay
			end
		end
		if current ~= target then
			if current then
				table.remove(current.members, table.find(current.members, player))
				readyPlayers[player] = nil
				changed = true
			end
			if target and #target.members < target.size then
				table.insert(target.members, player)
				changed = true
			end
		end
	end
	-- Start conditions.
	for _, bay in ipairs(bays) do
		local full = #bay.members >= bay.size
		local allReady = #bay.members > 0
		for _, p in ipairs(bay.members) do
			if not readyPlayers[p] then
				allReady = false
			end
		end
		local go = not busy and (full or allReady)
		if go and not bay.countdownEndsAt then
			bay.countdownEndsAt = os.clock() + COUNTDOWN
			changed = true
		elseif not go and bay.countdownEndsAt then
			bay.countdownEndsAt = nil
			changed = true
		elseif go and os.clock() >= bay.countdownEndsAt then
			launch(bay)
			changed = true
			busy = services.RoundService.isBusy()
		end
	end
	updateBoards()
	return changed
end

function PartyService.start(lobbyObject)
	lobby = lobbyObject
	for _, record in ipairs(lobby.bays) do
		table.insert(bays, {
			id = record.id,
			size = record.size,
			record = record,
			members = {},
			difficulty = DifficultyConfig.Default,
		})
	end
	enabled = not PartyService.isRunServer()

	local remotes = services.Remotes
	remotes.SetReady.OnServerEvent:Connect(function(player, value)
		if type(value) ~= "boolean" or not PartyService.bayOf(player) then
			return
		end
		readyPlayers[player] = value or nil
		PartyService.broadcast()
	end)
	remotes.SetDifficulty.OnServerEvent:Connect(function(player, name)
		local bay = PartyService.bayOf(player)
		if not bay or bay.members[1] ~= player or type(name) ~= "string" or not DifficultyConfig.Presets[name] then
			return
		end
		bay.difficulty = name
		PartyService.broadcast()
	end)
	Players.PlayerRemoving:Connect(function(player)
		local bay = PartyService.bayOf(player)
		if bay then
			table.remove(bay.members, table.find(bay.members, player))
		end
		readyPlayers[player] = nil
		departingUntil[player] = nil
		task.defer(PartyService.broadcast)
	end)

	task.spawn(function()
		local sinceBroadcast = 0
		while true do
			task.wait(0.25)
			sinceBroadcast += 0.25
			local ok, changed = pcall(tick)
			if not ok then
				warn("[DeadAir] Party tick error: " .. tostring(changed))
			elseif changed or sinceBroadcast >= 1 then
				sinceBroadcast = 0
				PartyService.broadcast()
			end
		end
	end)
end

-- Teleport a finished run's players back to a public lobby server.
function PartyService.returnToLobby(players)
	if not canTeleport() or #players == 0 then
		return false
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, players)
	end)
	if not ok then
		warn("[DeadAir] Return teleport failed: " .. tostring(err))
	end
	return ok
end

return PartyService
