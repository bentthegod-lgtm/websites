--[[
	PlayerService - characters and per-player presentation state.

	* Welds the magnet rig (MagnetModel) to the HumanoidRootPart, rebuilt on tier / skin
	  changes. Every rig part is massless and non-colliding, so it never affects movement.
	* Applies movement stats (walk speed, sprint) from UpgradeService. Sprint is a request
	  the server validates; the speed itself is set here.
	* Publishes the pile as player attributes (MM_Pile = the first N piece ids, mass, count),
	  which every client uses to draw that player's pile. Stable order: the first N pieces
	  never change until a sale, so piles don't flicker.
	* Trails (cosmetic) and settings (validated, saved with the profile).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local MagnetConfig = require(Shared.Config.MagnetConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)
local MagnetModel = require(Shared.MagnetModel)

local PlayerService = {}

local services
local world
local sprinting = {}
local lastSprint = {}

function PlayerService.init(registry)
	services = registry
end

function PlayerService.setWorld(newWorld)
	world = newWorld
end

local function humanoidOf(player)
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function PlayerService.applyStats(player)
	local humanoid = humanoidOf(player)
	if not humanoid or not services.DataService.getProfile(player) then
		return
	end
	local stats = services.UpgradeService.statsFor(player)
	humanoid.WalkSpeed = if sprinting[player] then stats.WalkSpeed * stats.SprintMultiplier else stats.WalkSpeed
	player:SetAttribute("MM_Tier", stats.MagnetVisualTier)
end

local function attachTrail(player, root, trailId)
	local old = root:FindFirstChild("MM_Trail")
	if old then
		old:Destroy()
	end
	for _, name in ipairs({ "MM_TrailA", "MM_TrailB" }) do
		local a = root:FindFirstChild(name)
		if a then
			a:Destroy()
		end
	end
	local def = MagnetConfig.Trails[trailId]
	if not def or not def.Color then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "MM_TrailA"
	a0.Position = Vector3.new(0, 1, 0.6)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "MM_TrailB"
	a1.Position = Vector3.new(0, -1.6, 0.6)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "MM_Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.45
	trail.LightEmission = 0.6
	local c = Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])
	trail.Color = ColorSequence.new(c)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = root
	player:SetAttribute("MM_Trail", trailId)
end

-- (Re)builds the magnet rig on the current character.
function PlayerService.refreshMagnet(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local data = services.DataService.getProfile(player)
	if not root or not data then
		return
	end
	local old = character:FindFirstChild("MagnetRig")
	if old then
		old:Destroy()
	end
	local skin = data.Cosmetics.Skin
	if not services.ShopService.ownsCosmetic(player, "Skin", skin) then
		skin = "Default"
	end
	local rig, parts = MagnetModel.build(data.Tier, skin, root.CFrame)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = parts.mount
	weld.Parent = parts.mount
	rig.Parent = character
	player:SetAttribute("MM_Skin", skin)
	local trail = data.Cosmetics.Trail
	if not services.ShopService.ownsCosmetic(player, "Trail", trail) then
		trail = "None"
	end
	attachTrail(player, root, trail)
	PlayerService.applyStats(player)
end

function PlayerService.updatePileAttributes(player)
	local data = services.DataService.getProfile(player)
	if not data then
		return
	end
	local ids = {}
	for i = 1, math.min(#data.Carried, PerformanceConfig.PileDetailedLocal) do
		ids[i] = data.Carried[i].id
	end
	local mass = services.DataService.carriedTotals(data)
	player:SetAttribute("MM_Pile", table.concat(ids, ","))
	player:SetAttribute("MM_PileMass", mass)
	player:SetAttribute("MM_PileCount", #data.Carried)
	local stats = services.UpgradeService.statsFor(player)
	player:SetAttribute("MM_Compaction", stats.PileCompaction)
end

local function onCharacter(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	sprinting[player] = false
	PlayerService.refreshMagnet(player)
	PlayerService.updatePileAttributes(player)
	humanoid.Died:Connect(function()
		-- In-flight scrap is released (never awarded to a dead player); the pile is kept.
		services.MagnetService.cancelAll(player)
	end)
end

function PlayerService.onProfileLoaded(player)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

-- Settings: only known keys with legal values are stored.
local SETTING_RULES = {
	CameraMode = { kind = "enum", values = { Third = true, First = true } },
	Sensitivity = { kind = "number", min = 0.2, max = 3 },
	Master = { kind = "number", min = 0, max = 1 },
	Music = { kind = "number", min = 0, max = 1 },
	Effects = { kind = "number", min = 0, max = 1 },
	Ambient = { kind = "number", min = 0, max = 1 },
	UI = { kind = "number", min = 0, max = 1 },
	ReducedEffects = { kind = "boolean" },
	Particles = { kind = "enum", values = { High = true, Medium = true, Low = true } },
}

function PlayerService.saveSettings(player, incoming)
	local data = services.DataService.getProfile(player)
	if not data or type(incoming) ~= "table" then
		return false
	end
	for key, rule in pairs(SETTING_RULES) do
		local v = incoming[key]
		if rule.kind == "number" and type(v) == "number" and v == v then
			data.Settings[key] = math.clamp(v, rule.min, rule.max)
		elseif (rule.kind == "boolean" and type(v) == "boolean") or (rule.kind == "enum" and type(v) == "string" and rule.values[v]) then
			data.Settings[key] = v
		end
	end
	services.DataService.markDirty(player)
	return true
end

function PlayerService.onPlayerRemoving(player)
	sprinting[player] = nil
	lastSprint[player] = nil
end

function PlayerService.start()
	local remotes = services.Remotes
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end
	remotes.Sprint.OnServerEvent:Connect(function(player, on)
		if type(on) ~= "boolean" then
			return
		end
		local t = os.clock()
		if lastSprint[player] and t - lastSprint[player] < 0.05 then
			return
		end
		lastSprint[player] = t
		sprinting[player] = on
		PlayerService.applyStats(player)
	end)
	remotes.SaveSettings.OnServerEvent:Connect(function(player, settings)
		PlayerService.saveSettings(player, settings)
	end)
	local lastState = {}
	Players.PlayerRemoving:Connect(function(player)
		lastState[player] = nil
	end)
	remotes.RequestState.OnServerEvent:Connect(function(player)
		local t = os.clock()
		if lastState[player] and t - lastState[player] < 2 then
			return
		end
		lastState[player] = t
		if services.DataService.getProfile(player) then
			services.DataService.sendProfile(player)
		end
		services.EventService.publish(player)
		remotes.Leaderboard:FireClient(player, services.LeaderboardService.rows())
	end)
	if world and world.stationPrompt then
		world.stationPrompt.Triggered:Connect(function(player)
			remotes.Popup:FireClient(player, "OpenMenu", { tab = "Upgrades" })
		end)
	end
end

return PlayerService
