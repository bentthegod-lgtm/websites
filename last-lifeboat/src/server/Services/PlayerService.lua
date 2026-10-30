--[[
	PlayerService - characters and per-player odds and ends:
	  * name tags over every head (gold with [VIP] for VIP owners); the default name is hidden
	  * the Captain's Outfit (cap and navy coat built from parts, welded to the avatar)
	  * attributes the client reads: LL_VIP, LL_Captain, LL_Grapple, LL_DoubleLoot,
	    LL_Jackets, LL_Flares (+ the upgrade attributes from UpgradeService)
	  * walk speed: heavy loot slows you, downed players can't move
	  * the harbour's prompts: ticket booth (shop), daily chest, codes box
	  * settings: only known keys with legal values are saved
	  * RequestState: a client that just loaded gets the profile, round and boards
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local Models = require(Shared.Models)
local Parts = require(Shared.Parts)
local LootMath = require(Shared.LootMath)
local RateLimit = require(script.Parent.RateLimit)

local PlayerService = {}

local services
local world
local settingsLimit = RateLimit.new(1, 4)
local stateLimit = RateLimit.new(0.5, 3)

function PlayerService.init(registry)
	services = registry
end

function PlayerService.setWorld(newWorld)
	world = newWorld
end

local function weld(part, anchor)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part
	w.Part1 = anchor
	w.Parent = part
end

function PlayerService.applyOutfit(player)
	local character = player.Character
	if not character then
		return false
	end
	local old = character:FindFirstChild("LL_Outfit")
	if old then
		old:Destroy()
	end
	if not services.ShopService.ownsPass(player, "Captain") then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "LL_Outfit"
	local head = character:FindFirstChild("Head")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
	for _, item in ipairs(Models.CaptainOutfit) do
		local anchor = if item[2] == "Head" then head else torso
		if anchor and anchor:IsA("BasePart") then
			local p = Parts.new({ Name = item[1], Size = item[3], CFrame = anchor.CFrame * item[4], Color = item[5], Material = item[6], Shape = if item[7] then Enum.PartType[item[7]] else nil, Anchored = false, CanCollide = false, CastShadow = false })
			p.Massless = true
			p.CanQuery = false
			weld(p, anchor)
			p.Parent = folder
		end
	end
	folder.Parent = character
	return true
end

function PlayerService.applyNameTag(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local tag = head:FindFirstChild("LL_NameTag")
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "LL_NameTag"
		tag.Size = UDim2.fromOffset(200, 30)
		tag.StudsOffset = Vector3.new(0, 2.4, 0)
		tag.MaxDistance = 90
		tag.AlwaysOnTop = false
		tag.Parent = head
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextStrokeTransparency = 0.4
		label.Parent = tag
	end
	local vip = services.ShopService.ownsPass(player, "VIP")
	local label = tag:FindFirstChild("Label")
	label.Text = if vip then "[VIP] " .. player.DisplayName else player.DisplayName
	label.TextColor3 = if vip then Color3.fromRGB(255, 205, 70) else Color3.fromRGB(240, 236, 224)
	return tag
end

-- Recomputes everything derived from passes / upgrades / boosts.
function PlayerService.refresh(player)
	local data = services.DataService.getProfile(player)
	if not data or not player.Parent then
		return
	end
	local shop = services.ShopService
	player:SetAttribute("LL_VIP", shop.ownsPass(player, "VIP"))
	player:SetAttribute("LL_Captain", shop.ownsPass(player, "Captain"))
	player:SetAttribute("LL_Grapple", shop.ownsPass(player, "Grapple"))
	player:SetAttribute("LL_DoubleLoot", shop.ownsPass(player, "DoubleLoot"))
	player:SetAttribute("LL_Jackets", data.Boosts.LifeJacket)
	player:SetAttribute("LL_Flares", data.Boosts.Flare)
	if services.UpgradeService then
		services.UpgradeService.applyAttributes(player)
	end
	PlayerService.applyNameTag(player)
	PlayerService.applyOutfit(player)
	PlayerService.applySpeed(player)
end

function PlayerService.applySpeed(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local rec = services.SurvivalService and services.SurvivalService.record(player)
	if rec and rec.state == "Downed" then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		return
	end
	local carried = services.LootService and services.LootService.carried(player) or {}
	humanoid.WalkSpeed = LootMath.walkSpeed(carried)
	humanoid.JumpPower = 46
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
			PlayerService.refresh(player)
		end
	end)
	if services.RoundService then
		services.RoundService.onCharacterAdded(player, character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				services.RoundService.onCharacterDied(player, character)
			end)
		end
	end
end

function PlayerService.onProfileLoaded(player)
	PlayerService.refresh(player)
end

function PlayerService.onPlayerRemoving(player)
	settingsLimit:forget(player)
	stateLimit:forget(player)
end

local function prompt(part, action, object, tab)
	if not part then
		return nil
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "LL_" .. tab
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(function(player)
		services.Remotes.OpenMenu:FireClient(player, tab)
	end)
	return p
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
	if world then
		PlayerService.prompts = {
			Shop = prompt(world.kiosk, "Open shop", "Ticket Booth", "Shop"),
			Daily = prompt(world.dailyChest, "Daily reward", "Sea Chest", "Daily"),
			Codes = prompt(world.codesBox, "Enter a code", "Codes", "Codes"),
		}
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
