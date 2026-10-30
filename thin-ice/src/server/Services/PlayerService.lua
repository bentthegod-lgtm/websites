--[[
	PlayerService - characters and per-player odds and ends:
	  * the outfit (beanie, pompom, scarf, jacket tint) and lantern built from parts on the
	    player's own avatar (CosmeticConfig; purely visual)
	  * tags: TI_Level and TI_VIP attributes (shown in the team list)
	  * settings: only known keys with legal values are saved
	  * RequestState: a client that just loaded gets the profile, round and board
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Progress = require(Shared.Progress)
local RateLimit = require(script.Parent.RateLimit)

local PlayerService = {}

local services
local settingsLimit = RateLimit.new(1, 4)
local stateLimit = RateLimit.new(0.5, 3)

local rgb = Color3.fromRGB

function PlayerService.init(registry)
	services = registry
end

local function color(t)
	return rgb(t[1], t[2], t[3])
end

local function accessory(folder, anchor, name, size, offset, col, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = col
	p.Material = material or Enum.Material.Fabric
	if shape then
		p.Shape = shape
	end
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = anchor.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = p
	weld.Part1 = anchor
	weld.Parent = p
	p.Parent = folder
	return p
end

-- Rebuilds the player's outfit + lantern on their current character.
function PlayerService.applyLook(player)
	local data = services.DataService.getProfile(player)
	local character = player.Character
	if not data or not character then
		return false
	end
	local old = character:FindFirstChild("TI_Look")
	if old then
		old:Destroy()
	end
	local outfit = CosmeticConfig.Outfits[data.Cosmetics.Outfit] or CosmeticConfig.Outfits.Classic
	local lantern = CosmeticConfig.Lanterns[data.Cosmetics.Lantern] or CosmeticConfig.Lanterns.Warm
	local folder = Instance.new("Folder")
	folder.Name = "TI_Look"
	local head = character:FindFirstChild("Head")
	local root = character:FindFirstChild("HumanoidRootPart")
	if head and head:IsA("BasePart") then
		accessory(folder, head, "Beanie", Vector3.new(1.3, 0.6, 1.3), CFrame.new(0, 0.55, 0), color(outfit.Beanie))
		accessory(folder, head, "Pompom", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.98, 0), rgb(250, 250, 252), Enum.Material.Fabric, Enum.PartType.Ball)
		accessory(folder, head, "Scarf", Vector3.new(1.5, 0.35, 1.25), CFrame.new(0, -0.62, 0), color(outfit.Scarf))
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local colors = character:FindFirstChildOfClass("BodyColors")
	if colors then
		colors.TorsoColor3 = color(outfit.Jacket)
		colors.LeftArmColor3 = color(outfit.Jacket)
		colors.RightArmColor3 = color(outfit.Jacket)
	elseif torso and torso:IsA("BasePart") then
		torso.Color = color(outfit.Jacket)
	end
	if root then
		local lamp = accessory(folder, root, "Lantern", Vector3.new(0.5, 0.7, 0.5), CFrame.new(1.4, -0.9, -0.4), color(lantern.Color), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = color(lantern.Color)
		light.Range = 14
		light.Brightness = 1.1
		light.Shadows = false
		light.Parent = lamp
	end
	folder.Parent = character
	return true
end

function PlayerService.refreshTags(player)
	local data = services.DataService.getProfile(player)
	if not data or not player.Parent then
		return
	end
	player:SetAttribute("TI_Level", Progress.levelFor(data.Xp))
	player:SetAttribute("TI_VIP", services.ShopService.ownsPass(player, "VIP"))
end

function PlayerService.saveSettings(player, incoming)
	local data = services.DataService.getProfile(player)
	if not data or type(incoming) ~= "table" then
		return false
	end
	local defaults = services.DataService.defaultSettings()
	for key, default in pairs(defaults) do
		local v = incoming[key]
		if type(default) == "number" and type(v) == "number" and v == v then
			data.Settings[key] = math.clamp(v, 0, 1)
		elseif type(default) == "boolean" and type(v) == "boolean" then
			data.Settings[key] = v
		end
	end
	services.DataService.markDirty(player)
	return true
end

local function onCharacter(player, character)
	task.defer(function()
		if character.Parent then
			PlayerService.applyLook(player)
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = GameConfig.Move.Walk
			end
		end
	end)
	if services.RoundService then
		services.RoundService.onCharacterAdded(player)
	end
end

function PlayerService.onProfileLoaded(player)
	PlayerService.refreshTags(player)
	PlayerService.applyLook(player)
end

function PlayerService.onPlayerRemoving(player)
	settingsLimit:forget(player)
	stateLimit:forget(player)
end

function PlayerService.start()
	local remotes = services.Remotes
	local function hook(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	remotes.SaveSettings.OnServerEvent:Connect(function(player, incoming)
		if settingsLimit:allow(player) then
			PlayerService.saveSettings(player, incoming)
		end
	end)
	remotes.RequestState.OnServerEvent:Connect(function(player)
		if not stateLimit:allow(player) then
			return
		end
		services.DataService.sendProfile(player)
		services.RoundService.sendState(player)
		remotes.Leaderboard:FireClient(player, services.LeaderboardService.rows())
	end)
end

return PlayerService
