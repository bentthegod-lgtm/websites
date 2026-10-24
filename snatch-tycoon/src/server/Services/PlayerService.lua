--[[
	PlayerService - the hub for per-player session state:
	  * cash helpers (addCash / spendCash), income multiplier and income per second
	  * leaderstats (Cash, Per Sec, Rebirths) and the overhead nameplate (gold for VIP)
	  * character spawning at the player's base, walk speed
	  * the full profile snapshot sent to the client, and the 1-second economy tick
	  * rebirth
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local ShopConfig = require(Shared.Config.ShopConfig)
local RewardConfig = require(Shared.Config.RewardConfig)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Timers = require(Shared.Timers)
local Goals = require(Shared.Goals)

local PlayerService = {}

local services
local sessions = {} -- [player] = { friends, joinedAt, sendQueued, lastRebirth }

function PlayerService.init(registry)
	services = registry
end

function PlayerService.session(player)
	return sessions[player]
end

---------------------------------------------------------------------------------------------
-- Economy helpers
---------------------------------------------------------------------------------------------

function PlayerService.multiplier(player)
	local data = services.DataService.getProfile(player)
	local session = sessions[player]
	if not data then
		return 1
	end
	return Economy.playerMultiplier({
		rebirths = data.Rebirths,
		rebirthCfg = GameConfig.Rebirth,
		doubleCash = services.ShopService.owns(player, "DoubleCash"),
		friends = if session then session.friends else 0,
		friendPer = GameConfig.FriendBoostPer,
		friendMax = GameConfig.FriendBoostMax,
		eventMult = services.EventService.incomeMult(),
	})
end

function PlayerService.incomePerSecond(player)
	return services.BlobbyService.baseIncome(player) * PlayerService.multiplier(player)
end

function PlayerService.slots(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return GameConfig.BaseSlots
	end
	return Economy.slotCount(data.Rebirths, services.ShopService.owns(player, "VIP"), services.ShopService.owns(player, "ExtraSlots"), GameConfig)
end

function PlayerService.addCash(player, amount)
	local data = services.DataService.getProfile(player)
	if not data or not Economy.finite(amount) or amount <= 0 then
		return false
	end
	data.Cash += amount
	data.TotalEarned += amount
	services.DataService.markDirty(player)
	return true
end

function PlayerService.spendCash(player, amount)
	local data = services.DataService.getProfile(player)
	if not data or not Economy.finite(amount) or amount < 0 or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	services.DataService.markDirty(player)
	return true
end

---------------------------------------------------------------------------------------------
-- leaderstats + nameplate
---------------------------------------------------------------------------------------------

local function ensureLeaderstats(player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		local cash = Instance.new("StringValue")
		cash.Name = "Cash"
		cash.Parent = stats
		local ips = Instance.new("StringValue")
		ips.Name = "Per Sec"
		ips.Parent = stats
		local rebirths = Instance.new("IntValue")
		rebirths.Name = "Rebirths"
		rebirths.Parent = stats
		stats.Parent = player
	end
	return stats
end

function PlayerService.updateLeaderstats(player, ips)
	local data = services.DataService.getProfile(player)
	if not data or not player.Parent then
		return
	end
	local stats = ensureLeaderstats(player)
	stats.Cash.Value = Format.cash(data.Cash)
	stats["Per Sec"].Value = Format.perSecond(ips or PlayerService.incomePerSecond(player))
	stats.Rebirths.Value = data.Rebirths
end

function PlayerService.updateNameplate(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local data = services.DataService.getProfile(player)
	if not head or not data then
		return
	end
	local vip = services.ShopService.owns(player, "VIP")
	player:SetAttribute("VIP", vip)
	local gui = head:FindFirstChild("SnatchNameplate")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "SnatchNameplate"
		gui.Size = UDim2.new(6, 0, 1.8, 0)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 100
		gui.LightInfluence = 0
		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.BackgroundTransparency = 1
		name.Size = UDim2.fromScale(1, 0.6)
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextStrokeTransparency = 0.2
		name.Parent = gui
		local sub = Instance.new("TextLabel")
		sub.Name = "SubLine"
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromScale(0, 0.6)
		sub.Size = UDim2.fromScale(1, 0.4)
		sub.Font = Enum.Font.FredokaOne
		sub.TextScaled = true
		sub.TextStrokeTransparency = 0.3
		sub.TextColor3 = Color3.fromRGB(140, 255, 150)
		sub.Parent = gui
		gui.Parent = head
	end
	gui.PlayerName.Text = (if vip then "[VIP] " else "") .. player.DisplayName
	gui.PlayerName.TextColor3 = if vip then Color3.fromRGB(255, 210, 60) else Color3.fromRGB(255, 255, 255)
	local rebirthText = if data.Rebirths > 0 then ("Rebirth " .. data.Rebirths .. "  ") else ""
	gui.SubLine.Text = rebirthText .. Format.perSecond(PlayerService.incomePerSecond(player))
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

---------------------------------------------------------------------------------------------
-- Snapshot sent to the client
---------------------------------------------------------------------------------------------

function PlayerService.snapshot(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return nil
	end
	local ips = PlayerService.incomePerSecond(player)
	local mult = PlayerService.multiplier(player)
	local blobbies = {}
	for uid, b in pairs(data.Blobbies) do
		table.insert(blobbies, {
			uid = uid,
			species = b.Species,
			mutation = b.Mutation,
			slot = b.Slot,
			income = services.BlobbyService.incomeOf(b) * mult,
			state = services.BlobbyService.stateOf(player, uid),
		})
	end
	table.sort(blobbies, function(a, b)
		return a.slot < b.slot
	end)
	local passes = {}
	for _, pass in ipairs(ShopConfig.Passes) do
		passes[pass.Key] = services.ShopService.owns(player, pass.Key)
	end
	local packs = {}
	for _, product in ipairs(ShopConfig.Products) do
		if product.Pack then
			packs[product.Key] = Economy.cashPackAmount(product.Pack, ips)
		end
	end
	local now = os.time()
	local canClaim, streak, rewardIndex = Timers.dailyStatus(data.Daily, Timers.dayIndex(now), #RewardConfig.Daily)
	local dailyRewards = {}
	for i, reward in ipairs(RewardConfig.Daily) do
		dailyRewards[i] = {
			text = reward.Text,
			amount = if reward.Kind == "Cash" then Economy.scaledReward(reward, ips) else nil,
			kind = reward.Kind,
			rarity = reward.Rarity,
		}
	end
	local discoveredCount = 0
	for _ in pairs(data.Discovered) do
		discoveredCount += 1
	end
	local goals = {}
	local goalState = services.RewardService.goalState(player)
	if goalState then
		for _, entry in ipairs(goalState.active) do
			local goal = RewardConfig.Goals[entry.pool]
			table.insert(goals, {
				text = Goals.describe(goal, entry, if goal.Stat == "Collect" then Format.short else nil),
				progress = math.min(entry.progress, entry.target),
				target = entry.target,
				reward = Economy.scaledReward(goal.Reward, ips),
			})
		end
	end
	local slots = PlayerService.slots(player)
	local used = 0
	for _ in pairs(data.Blobbies) do
		used += 1
	end
	return {
		cash = data.Cash,
		ips = ips,
		mult = mult,
		rebirths = data.Rebirths,
		slots = slots,
		usedSlots = used,
		queued = #data.Queued,
		blobbies = blobbies,
		passes = passes,
		packs = packs,
		daily = { canClaim = canClaim, streak = if canClaim then streak - 1 else streak, rewardIndex = rewardIndex, nextIn = Timers.secondsUntilNextDay(now), rewards = dailyRewards },
		discovered = data.Discovered,
		discoveredCount = discoveredCount,
		goals = goals,
		rebirth = {
			cost = Economy.rebirthCost(data.Rebirths, GameConfig.Rebirth),
			multNow = Economy.rebirthMultiplier(data.Rebirths, GameConfig.Rebirth),
			multNext = Economy.rebirthMultiplier(data.Rebirths + 1, GameConfig.Rebirth),
			slotsNext = Economy.slotCount(data.Rebirths + 1, passes.VIP, passes.ExtraSlots, GameConfig),
		},
		stats = data.Stats,
		settings = data.Settings,
		persistent = services.DataService.isPersistent(player),
		lockTokens = data.LockTokens or 0,
		friends = if sessions[player] then sessions[player].friends else 0,
		plotIndex = services.PlotService.plotIndexOf(player),
		codesUsed = data.Codes,
		randomItemsAllowed = services.ShopService.randomItemsAllowed(player),
	}
end

-- Coalesces several changes in one frame into a single Profile message.
function PlayerService.sendProfile(player)
	local session = sessions[player]
	if not session or session.sendQueued then
		return
	end
	session.sendQueued = true
	task.defer(function()
		session.sendQueued = false
		if player.Parent then
			local snap = PlayerService.snapshot(player)
			if snap then
				services.Remotes.Profile:FireClient(player, snap)
			end
		end
	end)
end

function PlayerService.sendTick(player, ips)
	local data = services.DataService.getProfile(player)
	if not data then
		return
	end
	local status, remaining = services.PlotService.lockStatus(player)
	services.Remotes.Tick:FireClient(player, {
		cash = data.Cash,
		ips = ips,
		lock = { status = status, remaining = remaining },
		lockTokens = data.LockTokens or 0,
	})
end

---------------------------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------------------------

function PlayerService.resetMovement(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = GameConfig.WalkSpeed
		humanoid.UseJumpPower = true
		humanoid.JumpPower = GameConfig.JumpPower
	end
end

local function onCharacter(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not root or not humanoid then
		return
	end
	PlayerService.resetMovement(player)
	local spawnCf = services.PlotService.spawnCFrame(player)
	if spawnCf then
		task.defer(function()
			if character.Parent then
				character:PivotTo(spawnCf)
			end
		end)
	end
	humanoid.Died:Connect(function()
		services.StealService.onCarrierLost(player, "died")
	end)
	PlayerService.updateNameplate(player)
end

---------------------------------------------------------------------------------------------
-- Rebirth
---------------------------------------------------------------------------------------------

function PlayerService.rebirth(player)
	local data = services.DataService.getProfile(player)
	local session = sessions[player]
	if not data or not session then
		return false
	end
	local cost = Economy.rebirthCost(data.Rebirths, GameConfig.Rebirth)
	if data.Cash < cost then
		services.Remotes.Notify:FireClient(player, "You need " .. Format.cash(cost) .. " to rebirth.", "warn")
		return false
	end
	if services.StealService.isCarrying(player) or services.StealService.isBeingRobbed(player) then
		services.Remotes.Notify:FireClient(player, "Can't rebirth during a heist!", "warn")
		return false
	end
	services.BlobbyService.clearAll(player)
	data.Rebirths += 1
	data.Cash = GameConfig.StartCash
	services.DataService.markDirty(player)
	services.PlotService.applySlots(player)
	services.FeedService.announce(string.format("%s REBIRTHED! (Rebirth %d, x%s cash)", player.DisplayName, data.Rebirths, tostring(Economy.rebirthMultiplier(data.Rebirths, GameConfig.Rebirth))), { 255, 200, 60 })
	services.Remotes.Popup:FireClient(player, "Rebirth", { rebirths = data.Rebirths, mult = Economy.rebirthMultiplier(data.Rebirths, GameConfig.Rebirth) })
	services.Remotes.Sfx:FireClient(player, "Rebirth")
	PlayerService.updateLeaderstats(player)
	PlayerService.updateNameplate(player)
	PlayerService.sendProfile(player)
	task.spawn(services.DataService.save, player)
	return true
end

---------------------------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------------------------

function PlayerService.tick(dt)
	services.BlobbyService.tick(dt)
	for player in pairs(sessions) do
		local data = services.DataService.getProfile(player)
		if data and player.Parent then
			local ips = PlayerService.incomePerSecond(player)
			if ips > data.BestIncome then
				data.BestIncome = math.floor(ips)
			end
			PlayerService.sendTick(player, ips)
			PlayerService.updateLeaderstats(player, ips)
			PlayerService.updateNameplate(player)
		end
	end
end

function PlayerService.start()
	local DataService = services.DataService
	DataService.ProfileLoaded:Connect(function(player)
		sessions[player] = { friends = 0, joinedAt = os.clock(), sendQueued = false }
		ensureLeaderstats(player)
		services.PlotService.assign(player)
		PlayerService.updateLeaderstats(player)
		services.EventService.sendTo(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end)
	DataService.Releasing:Connect(function(player)
		sessions[player] = nil
	end)

	local remotes = services.Remotes
	remotes.RequestState.OnServerEvent:Connect(function(player)
		if sessions[player] then
			PlayerService.sendProfile(player)
			services.EventService.sendTo(player)
		end
	end)
	local lastRebirth = {}
	remotes.Rebirth.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if lastRebirth[player] and now - lastRebirth[player] < 2 then
			return
		end
		lastRebirth[player] = now
		PlayerService.rebirth(player)
	end)
	local lastSettings = {}
	remotes.SaveSettings.OnServerEvent:Connect(function(player, settings)
		local data = DataService.getProfile(player)
		local now = os.clock()
		if not data or type(settings) ~= "table" or (lastSettings[player] and now - lastSettings[player] < 0.5) then
			return
		end
		lastSettings[player] = now
		for _, key in ipairs({ "Music", "Sfx" }) do
			if type(settings[key]) == "boolean" then
				data.Settings[key] = settings[key]
			end
		end
		DataService.markDirty(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRebirth[player] = nil
		lastSettings[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			PlayerService.tick(1)
		end
	end)
end

-- Rarity colour helper for announcements.
function PlayerService.rarityColor(rarity)
	local tier = RarityConfig.Tiers[rarity]
	return if tier then tier.Color else { 255, 255, 255 }
end

return PlayerService
