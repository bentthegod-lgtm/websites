--[[
	DepositService - turns carried loot into Cash at the deposit machines.

	Two ways in, one code path: the machine's ProximityPrompt (or the Deposit remote) and the
	auto-deposit zone painted in front of it (players with the AutoDeposit setting on; the
	server checks positions on a timer, not Touched, so there's no touch spam).
	A deposit validates the profile, the machine's depth, the player's distance, and that
	something is carried; then the carried stack is TAKEN FIRST (cleared) and only then is
	cash added - a duplicate request finds an empty stack and does nothing.
	Payout = carried value x deposit multiplier (Deposit Bonus upgrade, VIP pass) x the
	machine's payout factor (1 at the rim; the deep-end chute machines on B2+ keep 15%).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local LootConfig = require(Shared.Config.LootConfig)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local DepositService = {}

local services
local world
local lastDeposit = {}
local zoneClock = 0

function DepositService.init(registry)
	services = registry
end

function DepositService.setWorld(newWorld)
	world = newWorld
end

local function inZone(machine, position)
	local localPos = machine.zone.cframe:PointToObjectSpace(position)
	local half = machine.zone.size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end
DepositService.inZone = inZone

-- Returns (true, summary) or (false, reason).
function DepositService.deposit(player, machineId, viaZone)
	local data = services.DataService.getProfile(player)
	if not data or services.DataService.isLeaving(player) then
		return false, "not loaded"
	end
	local machine = type(machineId) == "string" and world.machines[machineId]
	if not machine then
		return false, "no machine"
	end
	local root = services.PlayerService.root(player)
	if not root then
		return false, "no character"
	end
	if services.PlayerService.depthOf(player) ~= machine.depth then
		return false, "other depth"
	end
	if machine.depth > data.HighestDepth then
		return false, "locked depth" -- only reachable by teleporting there
	end
	local pos = root.CFrame.Position
	if not inZone(machine, pos) and (pos - machine.cframe.Position).Magnitude > GameConfig.DepositRange then
		return false, "too far"
	end
	if data.Carried.Count <= 0 then
		if not viaZone then
			services.Remotes.Notify:FireClient(player, "Nothing to deposit yet - collect some loot first.", "info")
		end
		return false, "empty"
	end
	local stats = services.DataService.stats(player)
	local carried = services.LootService.takeCarried(player) -- cleared before any reward
	-- The deep-end chute machines pay a handling fee (machine.payoutFactor, 85%).
	local factor = machine.payoutFactor or 1
	local payout = math.floor(Economy.depositPayout(carried.Value, stats) * factor + 0.5)
	services.DataService.addCash(player, payout, true)
	services.DataService.bump(player, "Deposits", 1)
	services.DataService.bump(player, "DepositValue", payout)
	local record = payout > data.BestDeposit
	if record then
		data.BestDeposit = payout
	end
	lastDeposit[player] = os.clock()
	local summary = {
		machine = machine.id,
		count = carried.Count,
		value = carried.Value,
		payout = payout,
		multiplier = stats.DepositMult * factor,
		chute = factor < 1,
		record = record,
		items = carried.Items,
	}
	services.QuestService.tutorialEvent(player, "Deposit")
	services.Analytics.funnel(player, "FirstDeposit")
	services.Analytics.custom(player, "Deposit", payout)
	services.Remotes.Deposited:FireAllClients(player.UserId, summary)
	-- The announce bar follows the loot rescale (a full stack is worth FullPoolValue as much).
	if record and payout >= 1000000 * LootConfig.FullPoolValue then
		services.Remotes.Announce:FireAllClients(string.format("%s deposited a record $%s!", player.DisplayName, Format.short(payout)), { 120, 255, 170 })
	end
	services.LootService.sendInventory(player)
	services.DataService.sendProfile(player)
	return true, summary
end

-- Auto-deposit zones, checked a few times a second.
function DepositService.step(dt)
	zoneClock += dt
	if zoneClock < 0.25 then
		return
	end
	zoneClock = 0
	local now = os.clock()
	for _, player in ipairs(services.DataService.loadedPlayers()) do
		local data = services.DataService.getProfile(player)
		local root = services.PlayerService.root(player)
		if data and root and data.Settings.AutoDeposit and data.Carried.Count > 0 and (not lastDeposit[player] or now - lastDeposit[player] >= GameConfig.AutoDepositCooldown) then
			local pos = root.CFrame.Position
			for id, machine in pairs(world.machines) do
				if inZone(machine, pos) then
					DepositService.deposit(player, id, true)
					break
				end
			end
		end
	end
end

function DepositService.onPlayerRemoving(player)
	lastDeposit[player] = nil
end

function DepositService.start()
	local lastRequest = {}
	local function request(player, id)
		local t = os.clock()
		if lastRequest[player] and t - lastRequest[player] < 0.4 then
			return
		end
		lastRequest[player] = t
		DepositService.deposit(player, id)
	end
	for id, machine in pairs(world.machines) do
		machine.prompt.Triggered:Connect(function(player)
			request(player, id)
		end)
	end
	services.Remotes.Deposit.OnServerEvent:Connect(request)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return DepositService
