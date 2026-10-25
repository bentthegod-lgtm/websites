--[[
	MagnetService - the server side of the magnet. The client only says "magnet on/off" and
	"pulse"; everything else is decided here.

	One central tick (GameConfig.MagnetTick) for all players:
	  1. Active magnets claim nearby eligible scrap (ScrapService.query + atomic claim),
	     limited by a claims-per-second budget, objects-in-flight, heavy-object slots and
	     remaining capacity. Each claim gets a duration from Attraction.duration().
	  2. Flights whose time is up are validated (player still here, alive, close enough,
	     zone unlocked) and then awarded exactly once: ScrapService.consume() only succeeds
	     the first time. Invalid flights are released and float back.
	  3. Claims / awards / releases are broadcast in one batch per tick, so every client
	     animates the same flights (vibrate, lift, fly, join the pile).

	Values come from ScrapConfig + Economy on the server; the client never reports a value,
	rarity or distance.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local GameConfig = require(Shared.Config.GameConfig)
local ScrapConfig = require(Shared.Config.ScrapConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Attraction = require(Shared.Attraction)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)

local MagnetService = {}

local services
local states = {} -- [player] = state
local pendingAttract, pendingCollect, pendingRelease, pendingPulse = {}, {}, {}, {}
local rng = Random.new()

local function now()
	return os.clock()
end

local function stateOf(player)
	local s = states[player]
	if not s then
		s = { active = false, lastPulse = -math.huge, flights = {}, inFlight = 0, heavyInFlight = 0, massInFlight = 0, tokens = 0, lastNotice = {} }
		states[player] = s
	end
	return s
end
MagnetService.stateOf = stateOf

function MagnetService.init(registry)
	services = registry
end

local function rootOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or (humanoid and humanoid.Health <= 0) then
		return nil
	end
	return root
end

local function notice(player, s, key, text, kind)
	local t = now()
	if s.lastNotice[key] and t - s.lastNotice[key] < 4 then
		return
	end
	s.lastNotice[key] = t
	services.Remotes.Notify:FireClient(player, text, kind or "warn")
end

-- Starts one flight. Returns true if the object was claimed.
local function startFlight(player, s, item, stats, rootPos, pulse)
	local def = item.def
	if not services.ScrapService.claim(item, player) then
		return false
	end
	local dist = (item.position - rootPos).Magnitude
	local duration = Attraction.duration(def, dist, stats)
	local anticipation = Attraction.anticipation(def, stats)
	local flight = { item = item, def = def, start = now(), finish = now() + duration, pulse = pulse }
	s.flights[item.id] = flight
	s.inFlight += 1
	s.massInFlight += def.Mass
	if ScrapConfig.weightClass(def) == "Heavy" then
		s.heavyInFlight += 1
	end
	table.insert(pendingAttract, { item.id, player.UserId, duration, anticipation, pulse == true })
	return true
end

local function endFlight(s, flight)
	s.flights[flight.item.id] = nil
	s.inFlight = math.max(0, s.inFlight - 1)
	s.massInFlight = math.max(0, s.massInFlight - flight.def.Mass)
	if ScrapConfig.weightClass(flight.def) == "Heavy" then
		s.heavyInFlight = math.max(0, s.heavyInFlight - 1)
	end
end

-- Releases every flight of a player (died, left, prestiged). Nothing is awarded.
function MagnetService.cancelAll(player)
	local s = states[player]
	if not s then
		return
	end
	for _, flight in pairs(s.flights) do
		services.ScrapService.release(flight.item)
		table.insert(pendingRelease, flight.item.id)
		endFlight(s, flight)
	end
	s.active = false
	player:SetAttribute("MM_Active", false)
end

local function capacityLeft(player, s, stats)
	local data = services.DataService.getProfile(player)
	if not data then
		return 0
	end
	local mass = services.DataService.carriedTotals(data)
	return stats.MaximumScrapCapacity - mass - s.massInFlight
end

-- Is this object one this player may pull right now? Returns ok, reason.
local function eligible(data, stats, s, item)
	if not data.Zones[item.zone] and item.zone ~= "Any" then
		return false, "Zone"
	end
	local ok, reason = Attraction.canPull(item.def, stats)
	if not ok then
		return false, reason
	end
	if ScrapConfig.weightClass(item.def) == "Heavy" and s.heavyInFlight >= stats.HeavyObjectCapability then
		return false, "HeavySlots"
	end
	return true
end

local function claimAround(player, s, stats, rootPos, radius, maxClaims, pulse)
	local data = services.DataService.getProfile(player)
	if not data then
		return 0
	end
	local left = capacityLeft(player, s, stats)
	if left <= 0 then
		notice(player, s, "Full", "Your pile is FULL - sell it at the shredder!", "warn")
		return 0
	end
	local claimed = 0
	local tooHeavy
	for _, item in ipairs(services.ScrapService.query(rootPos, radius)) do
		if claimed >= maxClaims or s.inFlight >= PerformanceConfig.MaxInFlightPerPlayer then
			break
		end
		local ok, reason = eligible(data, stats, s, item)
		if ok then
			if item.def.Mass <= left then
				if startFlight(player, s, item, stats, rootPos, pulse) then
					claimed += 1
					left -= item.def.Mass
				end
			end
		elseif reason == "TooHeavy" and not tooHeavy then
			tooHeavy = item.def
		end
	end
	if tooHeavy and claimed == 0 then
		notice(player, s, "Heavy:" .. tooHeavy.Id, string.format("%s is too heavy: needs strength %s (you have %s).", tooHeavy.Name, tostring(tooHeavy.MinStrength), tostring(stats.MagnetStrength)), "warn")
	end
	if claimed > 0 then
		services.QuestService.tutorialEvent(player, "Claim")
	end
	return claimed
end

-- Awards one finished flight. Returns the collected entry or nil.
local function award(player, s, flight, stats, rootPos)
	local item, def = flight.item, flight.def
	endFlight(s, flight)
	local data = services.DataService.getProfile(player)
	local radius = (if flight.pulse then stats.PulseRadius else stats.AttractionRange) * GameConfig.CompletionRangeSlack
	local valid = data ~= nil
		and rootPos ~= nil
		and (item.position - rootPos).Magnitude <= radius
		and (data.Zones[item.zone] or item.zone == "Any")
	if not valid then
		services.ScrapService.release(item)
		table.insert(pendingRelease, item.id)
		return nil
	end
	if not services.ScrapService.consume(item) then
		return nil -- already gone (never award twice)
	end
	local lucky = stats.LuckyChance > 0 and rng:NextNumber() < stats.LuckyChance
	local storm = services.EventService.valueMultiplier()
	local value = Economy.itemValue(def, lucky, storm)
	table.insert(data.Carried, { id = def.Id, v = value })
	if def.Bonus and def.Bonus.Kind == "Coins" then
		services.DataService.addCoins(player, def.Bonus.Amount, true)
	end
	-- Codex, counters, quests, achievements.
	services.QuestService.discover(player, def, value)
	for _, key in ipairs(Progress.collectStats(def)) do
		services.DataService.bump(player, key, 1)
	end
	local rank = ScrapConfig.rank(def)
	if rank >= 3 then
		data.RareFinds += 1
		services.Analytics.funnel(player, "FirstRare")
		services.Remotes.Announce:FireAllClients(string.format("%s pulled a %s %s!", player.DisplayName, ScrapConfig.Rarities[def.Rarity].Label, def.Name), ScrapConfig.Rarities[def.Rarity].Color)
	end
	services.QuestService.tutorialEvent(player, "Collect")
	local class = ScrapConfig.weightClass(def)
	if class ~= "Light" then
		services.QuestService.tutorialEvent(player, "CollectMedium")
	end
	services.Analytics.funnel(player, "FirstCollect")
	services.EventService.onCollect(player, value)
	return { item.id, player.UserId, def.Id, value, lucky }
end

function MagnetService.tick(dt)
	local t = now()
	for _, player in ipairs(Players:GetPlayers()) do
		local s = states[player]
		local data = services.DataService.getProfile(player)
		if s and data then
			local root = rootOf(player)
			local stats = services.UpgradeService.statsFor(player)
			-- 1. Finish flights that are due.
			local changed = false
			for _, flight in pairs(s.flights) do
				if t >= flight.finish then
					local entry = award(player, s, flight, stats, root and root.Position)
					if entry then
						table.insert(pendingCollect, entry)
						changed = true
					end
				end
			end
			if changed then
				services.PlayerService.updatePileAttributes(player)
				services.DataService.sendProfile(player)
			end
			-- 2. Claim new objects while the magnet is on.
			if root and s.active then
				s.tokens = math.min(stats.ClaimsPerSecond, s.tokens + stats.ClaimsPerSecond * dt)
				local budget = math.min(math.floor(s.tokens), PerformanceConfig.MaxClaimsPerTick, stats.CollectionEfficiency - s.inFlight)
				if budget > 0 then
					local claimed = claimAround(player, s, stats, root.Position, stats.AttractionRange, budget, false)
					s.tokens -= claimed
				end
			elseif not root and s.active then
				MagnetService.cancelAll(player)
			end
		end
	end
	MagnetService.flush()
end

-- Sends this tick's batches (one remote call each, to everyone).
function MagnetService.flush()
	local remotes = services.Remotes
	if #pendingAttract > 0 or #pendingPulse > 0 then
		remotes.Attract:FireAllClients(pendingAttract, pendingPulse)
		pendingAttract, pendingPulse = {}, {}
	end
	if #pendingCollect > 0 then
		remotes.Collected:FireAllClients(pendingCollect)
		pendingCollect = {}
	end
	if #pendingRelease > 0 then
		remotes.Released:FireAllClients(pendingRelease)
		pendingRelease = {}
	end
end

function MagnetService.setActive(player, on)
	local s = stateOf(player)
	if on and not rootOf(player) then
		on = false
	end
	if s.active ~= on then
		s.active = on
		player:SetAttribute("MM_Active", on)
		if on then
			-- The first grab happens on the very next tick (instant feedback); the claim
			-- budget then refills at ClaimsPerSecond.
			s.tokens = math.max(s.tokens, 1)
		end
	end
end

-- Magnetic pulse: one big grab in a wider radius, on a cooldown.
function MagnetService.pulse(player)
	local s = stateOf(player)
	local root = rootOf(player)
	if not root or not services.DataService.getProfile(player) then
		return false
	end
	local stats = services.UpgradeService.statsFor(player)
	local t = now()
	if t - s.lastPulse < stats.PulseCooldown then
		return false
	end
	s.lastPulse = t
	local maxClaims = math.min(PerformanceConfig.MaxInFlightPerPlayer - s.inFlight, stats.CollectionEfficiency * 2 + 4)
	local claimed = claimAround(player, s, stats, root.Position, stats.PulseRadius, maxClaims, true)
	table.insert(pendingPulse, { player.UserId, stats.PulseRadius, claimed })
	player:SetAttribute("MM_PulseReady", workspace:GetServerTimeNow() + stats.PulseCooldown)
	services.DataService.bump(player, "Pulse", 1)
	return true, claimed
end

function MagnetService.onProfileLoaded(player)
	stateOf(player)
	player:SetAttribute("MM_PulseReady", 0)
end

function MagnetService.onPlayerRemoving(player)
	MagnetService.cancelAll(player)
	states[player] = nil
end

function MagnetService.start()
	local remotes = services.Remotes
	local lastToggle = {}
	remotes.Magnet.OnServerEvent:Connect(function(player, on)
		if type(on) ~= "boolean" then
			return
		end
		local t = now()
		-- Rapid toggling is ignored (anti-spam) but turning OFF always works.
		if on and lastToggle[player] and t - lastToggle[player] < 0.08 then
			return
		end
		lastToggle[player] = t
		MagnetService.setActive(player, on)
	end)
	remotes.Pulse.OnServerEvent:Connect(function(player)
		MagnetService.pulse(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastToggle[player] = nil
	end)
	task.spawn(function()
		local last = now()
		while true do
			task.wait(GameConfig.MagnetTick)
			local t = now()
			local ok, err = pcall(MagnetService.tick, math.min(0.5, t - last))
			if not ok then
				warn("[MagnetMayhem] magnet tick error: " .. tostring(err))
			end
			last = t
		end
	end)
end

-- Zone a position is in (helper used by other services).
function MagnetService.zoneAt(position)
	return ZoneConfig.zoneAt(position.X, position.Z)
end

return MagnetService
