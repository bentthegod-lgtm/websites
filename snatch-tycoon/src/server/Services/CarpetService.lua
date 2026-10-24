--[[
	CarpetService - Blobbies pop out of the portal and waddle down the red carpet. Walk up
	and press Buy (price by rarity and mutation); the Blobby then walks to your base.
	Rarity and mutation rolls use the server luck from EventService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("SnatchTycoon")
local GameConfig = require(Shared.Config.GameConfig)
local BlobbyConfig = require(Shared.Config.BlobbyConfig)
local RarityConfig = require(Shared.Config.RarityConfig)
local MutationConfig = require(Shared.Config.MutationConfig)
local BlobbyModels = require(Shared.BlobbyModels)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Spawner = require(Shared.Spawner)

local CarpetService = {}

local services
local world
local walkers = {}
local nextId = 0
local spawnTimer = 0
local rng = Random.new()

local C = GameConfig.Carpet

local function rand()
	return rng:NextNumber()
end

function CarpetService.init(registry)
	services = registry
end

function CarpetService.walkers()
	return walkers
end

local function rarityIndex(rarity)
	return table.find(RarityConfig.Order, rarity) or 1
end

local function removeWalker(walker)
	local index = table.find(walkers, walker)
	if index then
		table.remove(walkers, index)
	end
	if walker.built then
		walker.built.model:Destroy()
		walker.built = nil
	end
end

--[[
	Spawns one Blobby at the portal end of the carpet (or at `z` if given).
	opts = { rarity = forced rarity, mutation = forced mutation, z = number }
]]
function CarpetService.spawn(opts)
	opts = opts or {}
	local events = services.EventService
	local rarity = opts.rarity or Spawner.rollRarity(RarityConfig, rand, events.luck(), events.mythicBoost())
	local species = Spawner.rollSpecies(BlobbyConfig, rarity, rand)
	local mutation = opts.mutation
	if mutation == nil then
		mutation = Spawner.rollMutation(MutationConfig, rand, events.mutationBoost())
	elseif mutation == false then
		mutation = nil
	end
	local mutationDef = mutation and MutationConfig.Types[mutation]
	local tier = RarityConfig.Tiers[rarity]
	nextId += 1
	local x = (rand() - 0.5) * (C.Width - 6)
	local z = opts.z or C.StartZ
	local pos = Vector3.new(x, 0.3, z)
	local built = BlobbyModels.build(species, CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1)), {
		rarity = tier,
		mutation = mutation,
		mutationDef = mutationDef,
		phase = nextId * 0.61,
	})
	local walker = {
		id = nextId,
		species = species,
		mutation = mutation,
		mutationDef = mutationDef,
		price = Economy.blobbyPrice(species, mutationDef),
		income = Economy.blobbyIncome(species, mutationDef),
		built = built,
		x = x,
		z = z,
		travelled = 0,
	}
	built.model:SetAttribute("State", "Carpet")
	BlobbyModels.nameplate(built, {
		name = species.Name,
		rarity = rarity,
		rarityColor = tier.Color,
		mutation = mutation,
		mutationColor = mutationDef and mutationDef.Color,
		value = Format.cash(walker.price) .. "  |  " .. Format.perSecond(walker.income),
		valueColor = { 255, 226, 90 },
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy " .. Format.cash(walker.price)
	prompt.ObjectText = (if mutation then mutation .. " " else "") .. species.Name .. " (" .. rarity .. ")"
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = built.promptAttachment
	prompt.Triggered:Connect(function(player)
		CarpetService.buy(player, walker)
	end)
	walker.prompt = prompt
	built.model.Parent = world.blobbies
	table.insert(walkers, walker)

	if tier.Announce or mutation then
		local label = (if mutation then string.upper(mutation) .. " " else "") .. string.upper(rarity) .. " " .. species.Name
		-- Everything rare goes to the HUD feed; only the really rare ones also go to chat.
		local toChat = rarityIndex(rarity) >= 6 or (mutation ~= nil and mutation ~= "Gold")
		services.FeedService.announce("A " .. label .. " just walked out of the portal!", if mutationDef then mutationDef.Color else tier.Color, toChat)
		services.Remotes.Sfx:FireAllClients("RareSpawn")
	end
	return walker
end

function CarpetService.buy(player, walker)
	if walker.sold or not walker.built or not table.find(walkers, walker) then
		return false
	end
	local data = services.DataService.getProfile(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not data or not hrp then
		return false
	end
	local root = walker.built.root
	if (hrp.CFrame.Position - root.CFrame.Position).Magnitude > GameConfig.BuyDistance then
		return false
	end
	if not services.BlobbyService.freeSlot(player) then
		services.Remotes.Notify:FireClient(player, "Your base is full! Sell a Blobby (hold E on it) or rebirth for more slots.", "warn")
		services.Remotes.Sfx:FireClient(player, "Error")
		return false
	end
	if not services.PlayerService.spendCash(player, walker.price) then
		services.Remotes.Notify:FireClient(player, "You need " .. Format.cash(walker.price) .. " (you have " .. Format.cash(data.Cash) .. ")", "warn")
		services.Remotes.Sfx:FireClient(player, "Error")
		return false
	end
	walker.sold = true
	local from = Vector3.new(root.CFrame.Position.X, 0.3, root.CFrame.Position.Z)
	removeWalker(walker)
	services.BlobbyService.add(player, walker.species.Id, walker.mutation, { from = from, source = "carpet" })
	data.Stats.Bought += 1
	services.RewardService.recordGoal(player, "Buy", 1)
	local rarity = walker.species.Rarity
	if rarityIndex(rarity) >= 4 then
		services.RewardService.recordGoal(player, "BuyEpic", 1)
	end
	local tier = RarityConfig.Tiers[rarity]
	if tier.Announce or walker.mutation then
		services.FeedService.announce(string.format("%s bought a %s%s %s!", player.DisplayName, if walker.mutation then string.upper(walker.mutation) .. " " else "", string.upper(rarity), walker.species.Name), tier.Color, true)
	end
	services.Remotes.Popup:FireClient(player, "Bought", { name = walker.species.Name, rarity = rarity, mutation = walker.mutation, price = walker.price, position = from })
	services.Remotes.Sfx:FireClient(player, "BuyBlobby")
	services.PlayerService.sendProfile(player)
	return true
end

function CarpetService.step(dt)
	local events = services.EventService
	spawnTimer -= dt
	if spawnTimer <= 0 then
		spawnTimer = C.SpawnInterval / events.spawnRate()
		if #walkers < C.MaxOnCarpet then
			CarpetService.spawn()
		end
	end
	local speed = C.Speed * events.speedMult()
	for i = #walkers, 1, -1 do
		local walker = walkers[i]
		walker.z += speed * dt
		walker.travelled += speed * dt
		if walker.z >= C.EndZ then
			removeWalker(walker)
		elseif walker.built then
			local hop = math.abs(math.sin(walker.travelled * 1.3)) * 0.4
			local pos = Vector3.new(walker.x, 0.3 + hop, walker.z)
			walker.built.root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
		end
	end
end

function CarpetService.setWorld(w)
	world = w
end

-- Fills the carpet so the first players don't see an empty runway.
function CarpetService.seed(count)
	for i = 1, count do
		local z = C.StartZ + (C.EndZ - C.StartZ) * (i / (count + 1))
		CarpetService.spawn({ z = z })
	end
end

function CarpetService.start()
	CarpetService.seed(12)
	RunService.Heartbeat:Connect(CarpetService.step)
end

return CarpetService
