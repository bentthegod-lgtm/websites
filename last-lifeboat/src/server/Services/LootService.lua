--[[
	LootService - valuables on the ship and what each player carries.

	* At round start every ShipGen loot spot gets an item rolled by depth (the lowest decks,
	  which flood first, roll rarer loot) and ship tier. Items sit inside the ship model, so
	  they ride every lurch.
	* Hold E (ProximityPrompt; validated server-side: in the round, alive, within range, a
	  free slot) to pick one up. Slots: 3 base, Loot Slots upgrade, +1 VIP. Heavy items (gold
	  bars, paintings) lower your WalkSpeed.
	* Carried loot only pays out if you ESCAPE (RewardService / LootMath.payout). Going OUT
	  loses it. You can drop an item (DropLoot) to free a slot; it lands at your feet.
	* Legendary finds are announced to the whole server.
	The carried list reaches the client as the LL_Carried attribute ("GoldBar,PocketWatch").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)
local LootMath = require(Shared.LootMath)
local Models = require(Shared.Models)
local RateLimit = require(script.Parent.RateLimit)

local LootService = {}

local services
local run = nil
local carried = {}
local items = {}
local dropLimit = RateLimit.new(2, 3)
local rng = Random.new()

local R = GameConfig.LootRules

function LootService.init(registry)
	services = registry
end

local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

function LootService.carried(player)
	return carried[player] or {}
end

local function sync(player)
	if player.Parent then
		player:SetAttribute("LL_Carried", LootMath.encode(carried[player] or {}))
	end
	services.PlayerService.applySpeed(player)
end

-- Places an item model at a ship-local CFrame (inside the ship so it rides the lurches).
local function spawnItem(key, localCF, record)
	local model = Models.loot(key, record.model:GetPivot() * localCF, record.lootFolder)
	local def = GameConfig.Loot[key]
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LL_Grab"
	prompt.ActionText = "Grab"
	prompt.ObjectText = string.format("%s (%s)", def.Name, def.Rarity)
	prompt.HoldDuration = R.PickupHold
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = R.PickupRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	local entry = { key = key, model = model, prompt = prompt }
	prompt.Triggered:Connect(function(player)
		LootService.pickup(player, entry)
	end)
	table.insert(items, entry)
	return entry
end

-- Puts an item on the current ship at a ship-local CFrame (drops; also used by tests).
function LootService.spawnAt(key, localCF)
	local ship = services.ShipService.record()
	if not ship or not GameConfig.Loot[key] then
		return nil
	end
	return spawnItem(key, localCF, ship)
end

function LootService.startRun(newRun, record)
	run = newRun
	items = {}
	local plan = record.plan
	local n = #plan.decks
	for _, spot in ipairs(plan.loot) do
		local depth = 1 - (spot.deck - 1) / math.max(1, n - 1)
		local key = LootMath.roll(rng, depth, plan.def.Tier)
		local entry = spawnItem(key, CFrame.new(spot.x, plan.decks[spot.deck].y, spot.z), record)
		entry.spot = spot
	end
	for player in pairs(run.players) do
		carried[player] = {}
		sync(player)
	end
end

function LootService.items()
	return items
end

function LootService.pickup(player, entry)
	-- Slots first: the pass lookup can yield, and nothing may yield between the checks below
	-- and taking the item (two players grabbing one item would both get it).
	local slots = services.UpgradeService.slots(player)
	local rec = services.SurvivalService.record(player)
	if not rec or rec.state ~= "Alive" or not entry.model.Parent then
		return false, "gone"
	end
	local root = rootOf(player)
	if not root or (root.CFrame.Position - entry.model:GetPivot().Position).Magnitude > R.PickupRange + 2 then
		return false, "too far"
	end
	local list = carried[player] or {}
	carried[player] = list
	if #list >= slots then
		services.Remotes.Notify:FireClient(player, string.format("Your hands are full (%d/%d). Drop something or upgrade Loot Slots.", #list, slots), "error")
		return false, "full"
	end
	entry.model:Destroy()
	table.insert(list, entry.key)
	sync(player)
	local def = GameConfig.Loot[entry.key]
	services.Remotes.WorldSound:FireClient(player, if LootMath.rank(def.Rarity) >= 2 then "PickupRare" else "Pickup", nil)
	services.Remotes.Notify:FireClient(player, string.format("+ %s (%s, %d)%s", def.Name, def.Rarity, def.Value, if def.Weight >= 2 then " - heavy!" else ""), "loot:" .. def.Rarity)
	if def.Rarity == "Legendary" and not entry.dropped then -- a re-grab isn't a new find
		services.DataService.bump(player, "Legendaries", 1)
		services.Remotes.Announce:FireAllClients(string.format("%s found the %s!", player.DisplayName, def.Name), GameConfig.Rarities.Legendary.Color)
		services.Remotes.WorldSound:FireAllClients("Legendary", nil)
	end
	return true
end

function LootService.drop(player, index)
	local rec = services.SurvivalService.record(player)
	local list = carried[player]
	if not rec or rec.state ~= "Alive" or not list or type(index) ~= "number" or index ~= index then
		return false
	end
	index = math.floor(index)
	local key = list[index]
	local root = rootOf(player)
	local ship = services.ShipService.record()
	if not key or not root or not ship then
		return false
	end
	table.remove(list, index)
	sync(player)
	local localCF = ship.model:GetPivot():ToObjectSpace(CFrame.new(root.CFrame.Position - Vector3.new(0, 2.8, 0)))
	spawnItem(key, CFrame.new(localCF.Position), ship).dropped = true
	services.Remotes.WorldSound:FireClient(player, "Drop", nil)
	return true
end

-- Hands over what a player carries (for the payout) and empties their hands.
function LootService.take(player)
	local list = carried[player] or {}
	carried[player] = {}
	sync(player)
	return list
end

function LootService.clear(player)
	carried[player] = {}
	if player.Parent then
		sync(player)
	end
end

function LootService.stopRun()
	for player in pairs(carried) do
		if player.Parent then
			player:SetAttribute("LL_Carried", "")
		end
	end
	carried = {}
	items = {}
	run = nil
end

function LootService.onPlayerRemoving(player)
	carried[player] = nil
	dropLimit:forget(player)
end

function LootService.start()
	services.Remotes.DropLoot.OnServerEvent:Connect(function(player, index)
		if dropLimit:allow(player) then
			LootService.drop(player, index)
		end
	end)
end

return LootService
