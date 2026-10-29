--[[
	EffectsController - per-floor presentation that only this client sees.

	* Watches which depth the character is on (height band) and, on a change, applies that
	  floor's lighting preset and fires ClientState.DepthChanged (ambience, HUD, tutorial).
	* Exit vault doors: the round door at the end of each floor's corridor swings open on
	  this client once the depth behind it is unlocked (closed and lit red before that).
	* Rare loot events: a light column over the special item while it lasts, removed when
	  it is collected or expires.
	* Trails (cosmetic) on every character from the V_Trail attribute.
	* Drives the AudioController's random ambient one-shots.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local DepthConfig = require(Shared.Config.DepthConfig)
local LootConfig = require(Shared.Config.LootConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local LightingPresets = require(Shared.LightingPresets)

local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)

local EffectsController = {}

local currentDepth
local checkClock = 0
local doors = {} -- { model, leaf, axis, next, open }
local beacon

-- Depth tracking ---------------------------------------------------------------------------

local function setDepth(depth)
	if depth == currentDepth then
		return
	end
	currentDepth = depth
	local def = DepthConfig.get(depth)
	local preset = def and LightingPresets[def.Lighting]
	if preset then
		LightingPresets.apply(Lighting, preset)
	end
	ClientState.DepthChanged:Fire(depth)
end

function EffectsController.depth()
	return currentDepth
end

-- Exit doors -------------------------------------------------------------------------------

local function indexDoors()
	local vault = Workspace:WaitForChild("Vault")
	for _, d in ipairs(vault:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("ExitDoor") then
			local leaf = d:FindFirstChild("Leaf")
			local axis = leaf and leaf:FindFirstChild("HingeAxis")
			if leaf and axis then
				table.insert(doors, { model = d, leaf = leaf, axis = axis, next = d:GetAttribute("NextDepth"), open = false, closed = leaf:GetPivot(), hinge = axis.CFrame })
			end
		end
	end
end

local function swing(door, open, instant)
	if door.open == open then
		return
	end
	door.open = open
	-- Rotate the leaf about its hinge axis (vertical), 100 degrees outward.
	local function at(alpha)
		local rot = door.hinge * CFrame.Angles(0, math.rad(-100) * alpha, 0)
		door.leaf:PivotTo(rot * door.hinge:ToObjectSpace(door.closed))
	end
	if instant then
		at(if open then 1 else 0)
		return
	end
	local value = Instance.new("NumberValue")
	value.Value = if open then 0 else 1
	value.Changed:Connect(at)
	local tween = TweenService:Create(value, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = if open then 1 else 0 })
	tween.Completed:Connect(function()
		value:Destroy()
	end)
	tween:Play()
	AudioController.play("VaultDoor", { position = door.axis.Position, maxDistance = 120 })
end

local function refreshDoors(instant)
	local p = ClientState.profile
	if not p then
		return
	end
	for _, door in ipairs(doors) do
		local unlocked = door.next and DepthConfig.get(door.next) ~= nil and p.highestDepth >= door.next
		swing(door, unlocked == true, instant)
	end
end

-- Rare event beacon ------------------------------------------------------------------------

local function clearBeacon()
	if beacon then
		beacon:Destroy()
		beacon = nil
	end
end

local function onRare(phase, data)
	if phase == "Spawn" and data.position then
		clearBeacon()
		local rarity = LootConfig.Rarities[data.rarity]
		local color = if rarity then Color3.fromRGB(rarity.Color[1], rarity.Color[2], rarity.Color[3]) else Color3.new(1, 0.8, 0.3)
		beacon = Instance.new("Part")
		beacon.Name = "RareBeacon"
		beacon.Anchored = true
		beacon.CanCollide = false
		beacon.CanQuery = false
		beacon.CanTouch = false
		beacon.CastShadow = false
		beacon.Material = Enum.Material.Neon
		beacon.Color = color
		beacon.Transparency = 0.65
		beacon.Shape = Enum.PartType.Cylinder
		beacon.Size = Vector3.new(26, 1.6, 1.6)
		beacon.CFrame = CFrame.new(data.position + Vector3.new(0, 13, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 22
		light.Brightness = 2
		light.Parent = beacon
		beacon.Parent = Workspace.CurrentCamera
		if currentDepth == data.depth then
			AudioController.play("RareDiscovery")
		end
	elseif phase == "Gone" then
		clearBeacon()
	end
end

-- Trails -----------------------------------------------------------------------------------

local function applyTrail(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local old = root:FindFirstChild("VaultTrail")
	if old then
		old:Destroy()
	end
	local id = player:GetAttribute("V_Trail") or "None"
	local def = CosmeticConfig.Kinds.Trail[id]
	if not def or not def.Color then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "VaultTrail"
	holder.Parent = root
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0.4)
	a0.Parent = root
	a0:SetAttribute("Trail", true)
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.4, 0.4)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.45
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3]))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = holder
	holder.Destroying:Connect(function()
		a0:Destroy()
		a1:Destroy()
	end)
end

local function trackTrail(player)
	player:GetAttributeChangedSignal("V_Trail"):Connect(function()
		applyTrail(player)
	end)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		applyTrail(player)
	end)
	applyTrail(player)
end

function EffectsController.init()
	indexDoors()
	for _, door in ipairs(doors) do
		door.open = true -- built closed; force the first refresh to apply
		swing(door, false, true)
	end
	local first = true
	ClientState.ProfileChanged:Connect(function()
		refreshDoors(first) -- doors already unlocked on join are simply open
		first = false
	end)
	ClientState.RareEvent:Connect(onRare)
	for _, player in ipairs(Players:GetPlayers()) do
		trackTrail(player)
	end
	Players.PlayerAdded:Connect(trackTrail)
	setDepth(ClientState.depth())
	RunService.Heartbeat:Connect(function(dt)
		checkClock += dt
		if checkClock >= 0.25 then
			checkClock = 0
			if ClientState.root() then
				setDepth(ClientState.depth())
			end
		end
		AudioController.step()
	end)
end

return EffectsController
