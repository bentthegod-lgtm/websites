--[[
	AbilityService - buying (coins only), equipping (lobby only) and using abilities.

	The server validates cooldowns, slots and round state for every use. Movement
	abilities (Dash, Super Jump) are then executed by the owning client, because Roblox
	gives each client physics ownership of its own character; everything that affects
	other players (Freeze, Swap, Shield) runs entirely on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local AbilityConfig = require(Shared.Config.AbilityConfig)
local Clock = require(Shared.Clock)
local Rng = require(Shared.Rng)

local AbilityService = {}

local services
local readyAt = {} -- [player] = { [abilityId] = time }
local lastUse = {}
local rng

function AbilityService.init(registry)
	services = registry
	rng = Rng.new(os.time() + 99)
end

function AbilityService.maxSlots(player)
	return if services.ShopService.owns(player, "ExtraSlot") then AbilityConfig.MaxSlotsWithPass else AbilityConfig.MaxSlots
end

local function inRound(player)
	local c = services.MatchService.forPlayer(player)
	return c and c.alive and services.MatchService.state() == "Playing", c
end

function AbilityService.buy(player, id)
	local profile = services.DataService.getProfile(player)
	local def = type(id) == "string" and AbilityConfig.Abilities[id]
	if not profile or not def then
		return false, "Unknown ability."
	end
	if profile.Abilities[id] then
		return false, "You already own " .. def.Name .. "."
	end
	if not services.DataService.spendCoins(player, def.Price) then
		return false, "Not enough coins."
	end
	profile.Abilities[id] = true
	-- The loadout only changes in the lobby (a round uses profile.Loadout live).
	if #profile.Loadout < AbilityService.maxSlots(player) and player:GetAttribute("RR_Status") ~= "Arena" then
		table.insert(profile.Loadout, id)
	end
	services.DataService.markDirty(player)
	return true, "Unlocked " .. def.Name .. "!"
end

function AbilityService.equip(player, slot, id)
	local profile = services.DataService.getProfile(player)
	if not profile or type(id) ~= "string" or type(slot) ~= "number" or slot ~= slot then
		return false, "Invalid."
	end
	slot = math.floor(slot)
	if slot < 1 or slot > AbilityService.maxSlots(player) then
		return false, "That slot is locked."
	end
	if player:GetAttribute("RR_Status") == "Arena" then
		return false, "Change abilities in the lobby."
	end
	if not profile.Abilities[id] or not AbilityConfig.Abilities[id] then
		return false, "You don't own that ability."
	end
	local max = AbilityService.maxSlots(player)
	local slots = {}
	for i = 1, max do
		slots[i] = profile.Loadout[i]
	end
	local existing = table.find(profile.Loadout, id)
	if existing and existing <= max then
		-- Swap the two slots.
		slots[existing] = slots[slot]
	end
	slots[slot] = id
	-- Keep the list contiguous with no duplicates.
	local clean = {}
	for i = 1, max do
		local v = slots[i]
		if v and not table.find(clean, v) then
			table.insert(clean, v)
		end
	end
	profile.Loadout = clean
	services.DataService.markDirty(player)
	return true
end

-- Returns ok, message
function AbilityService.use(player, slot, moveDir)
	if type(slot) ~= "number" or slot ~= slot then
		return false
	end
	local profile = services.DataService.getProfile(player)
	if not profile then
		return false
	end
	slot = math.floor(slot)
	if slot < 1 or slot > AbilityService.maxSlots(player) then
		return false
	end
	local id = profile.Loadout[slot]
	local def = id and AbilityConfig.Abilities[id]
	if not def then
		return false
	end
	local now = Clock.now()
	readyAt[player] = readyAt[player] or {}
	if (readyAt[player][id] or 0) > now then
		return false, "cooldown"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local active, c = inRound(player)

	if def.Passive then
		return false, if c and c.shieldReady then "Shield is ready: it will save you once this round." else "Shield is passive (one save per round)."
	elseif id == "Dash" then
		local dir = Vector3.new(0, 0, -1)
		if typeof(moveDir) == "Vector3" and moveDir.Magnitude == moveDir.Magnitude and moveDir.Magnitude > 0.1 and moveDir.Magnitude < 10 then
			dir = Vector3.new(moveDir.X, 0, moveDir.Z)
			dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, -1)
		end
		services.Remotes.AbilityFx:FireClient(player, "Dash", { dir = dir, power = def.Power, duration = def.Duration })
	elseif id == "SuperJump" then
		services.Remotes.AbilityFx:FireClient(player, "SuperJump", { power = def.Power })
	elseif id == "Freeze" then
		if not active or not services.BallService.freeze(c, def.SlowFactor, def.Duration) then
			return false, "Freeze only works while the ball is chasing you."
		end
	elseif id == "Swap" then
		if not active then
			return false, "Swap only works during a round."
		end
		local pool = {}
		for _, other in ipairs(services.MatchService.alive()) do
			if other ~= c and services.MatchService.rootOf(other) then
				table.insert(pool, other)
			end
		end
		local other = rng:pick(pool)
		local myRoot = services.MatchService.rootOf(c)
		if not other or not myRoot then
			return false, "Nobody to swap with."
		end
		local a = myRoot.CFrame
		local b = services.MatchService.rootOf(other).CFrame
		c.model:PivotTo(b)
		other.model:PivotTo(a)
		services.Remotes.Fx:FireAllClients("Swap", { a = a.Position, b = b.Position, by = c.id, with = other.id })
	end
	readyAt[player][id] = now + def.Cooldown
	services.Remotes.AbilityFx:FireClient(player, "Cooldown", { slot = slot, id = id, cooldown = def.Cooldown })
	if id == "Dash" or id == "SuperJump" then
		services.Remotes.Fx:FireAllClients(id, { userId = player.UserId })
	end
	return true
end

-- Called by DataService on PlayerRemoving, before the leave save.
function AbilityService.onPlayerRemoving(player)
	readyAt[player] = nil
	lastUse[player] = nil
end

function AbilityService.start()
	local remotes = services.Remotes
	remotes.UseAbility.OnServerEvent:Connect(function(player, slot, moveDir)
		local now = os.clock()
		if lastUse[player] and now - lastUse[player] < 0.15 then
			return
		end
		lastUse[player] = now
		local ok, message = AbilityService.use(player, slot, moveDir)
		if not ok and message and message ~= "cooldown" then
			remotes.Notify:FireClient(player, message, "warn")
		end
	end)
	remotes.BuyAbility.OnServerEvent:Connect(function(player, id)
		local ok, message = AbilityService.buy(player, id)
		remotes.Notify:FireClient(player, message, if ok then "good" else "warn")
		services.DataService.sendProfile(player)
	end)
	remotes.EquipAbility.OnServerEvent:Connect(function(player, slot, id)
		local ok, message = AbilityService.equip(player, slot, id)
		if not ok then
			remotes.Notify:FireClient(player, message, "warn")
		end
		services.DataService.sendProfile(player)
	end)
end

return AbilityService
