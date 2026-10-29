--[[
	CollectController - manual pickup on the client side.

	* A few times a second it finds the nearest loose item on the character's depth inside
	  the collection radius and marks it: an outline (one shared Highlight) and a small
	  billboard "[E] Gold Bar  $1.2K". Nothing is highlighted when the stack is full; the
	  billboard says "STACK FULL - DEPOSIT" instead.
	* tryCollect() (E / ButtonX / the PICKUP button, held to repeat) asks the server for that
	  item, at most once per pickup interval. The server decides everything: distance,
	  cooldown, capacity, whether someone else got it first.
	* When the server confirms a pickup (Collected, also sent for magnet and auto-collect
	  pickups), the item flies into the stack with a short scale-down, a floating "+$X"
	  rises and the category's pickup sound plays. Other players' pickups play a quiet 3D
	  sound only. Effects are pooled and capped (PerformanceConfig).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local Net = require(Shared.Net)
local LootConfig = require(Shared.Config.LootConfig)
local PerformanceConfig = require(Shared.Config.PerformanceConfig)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local LootModels = require(Shared.LootModels)
local SpatialHash = require(Shared.SpatialHash)

local ClientState = require(script.Parent.ClientState)
local AudioController = require(script.Parent.AudioController)
local Ui = require(script.Parent.Ui)

local CollectController = {}

local lootFolder
local target -- { model, id, def }
local highlight
local billboard, billboardText
local lastRequest = 0
local scanClock = 0
local flying = 0
local floating = 0

CollectController.TargetChanged = nil -- optional callback(target)

local function myDepth()
	return ClientState.depth()
end

function CollectController.target()
	return target
end

local function rarityColor(def)
	local r = LootConfig.Rarities[def.Rarity]
	return if r then Ui.rgb(r.Color) else Ui.Colors.Text
end

-- The part that stands for a pickup: single-part pickups are the part itself, detailed
-- models use their Hitbox.
local function partOf(obj)
	return if obj:IsA("BasePart") then obj else obj.PrimaryPart
end
CollectController.partOf = partOf

-- Client spatial hash of the pickups, per depth (thousands fill a pool; no full scans).
local hashes = {}
local function hashFor(depth)
	hashes[depth] = hashes[depth] or SpatialHash.new(8)
	return hashes[depth]
end
local function onAdded(obj)
	local depth = obj:GetAttribute("Depth")
	local part = partOf(obj)
	if depth and part then
		hashFor(depth):insert(obj, part.CFrame.Position)
	end
end
local function onRemoved(obj)
	for _, h in pairs(hashes) do
		h:remove(obj)
	end
end
CollectController.indexed = function(depth)
	return hashes[depth] and hashes[depth].size or 0
end

local function scan()
	local root = ClientState.root()
	if not root or not lootFolder then
		return nil
	end
	local stats = ClientState.stats()
	local pos = root.CFrame.Position
	local best, bestDist = nil, stats.Radius
	-- A little extra search radius: magnet-pulled items drift from where they were indexed.
	for _, obj in ipairs(hashFor(myDepth()):query(pos, stats.Radius + 8)) do
		local hit = obj.Parent and partOf(obj)
		if hit then
			local d = (hit.CFrame.Position - pos).Magnitude
			if d < bestDist then
				best, bestDist = obj, d
			end
		end
	end
	if not best then
		return nil
	end
	local def = LootConfig.ById[best:GetAttribute("Item")]
	if not def then
		return nil
	end
	return { model = best, id = best:GetAttribute("LootId"), def = def }
end

local function showTarget(t)
	local full = ClientState.isFull()
	if not t then
		highlight.Enabled = false
		billboard.Enabled = false
		return
	end
	highlight.Adornee = t.model
	highlight.Enabled = not full
	highlight.OutlineColor = rarityColor(t.def)
	billboard.Adornee = partOf(t.model)
	billboard.Enabled = true
	if full then
		billboardText.Text = "STACK FULL - DEPOSIT"
		billboardText.TextColor3 = Ui.Colors.Red
	else
		local value = Economy.itemValue(t.def, ClientState.stats())
		local key = if Ui.touch then "TAP PICKUP" else "[E]"
		billboardText.Text = string.format("%s  %s  $%s", key, t.def.Name, Format.short(value))
		billboardText.TextColor3 = rarityColor(t.def)
	end
end

function CollectController.refresh()
	local t = scan()
	local changed = (t and t.model) ~= (target and target.model)
	target = t
	showTarget(t)
	if changed and CollectController.TargetChanged then
		CollectController.TargetChanged(t)
	end
end

-- Ask for the targeted item. Returns true if a request was sent.
function CollectController.tryCollect()
	if ClientState.riding then
		return false
	end
	local now = os.clock()
	local interval = ClientState.stats().PickupInterval
	if now - lastRequest < interval then
		return false
	end
	CollectController.refresh()
	if not target or not target.id then
		return false
	end
	if ClientState.isFull() then
		lastRequest = now
		AudioController.play("StackFull")
		ClientState.PopupRequested:Fire("StackFull", { capacity = ClientState.inventory.capacity, localOnly = true })
		return false
	end
	lastRequest = now
	Net.event("Collect"):FireServer(target.id)
	return true
end

-- Effects ----------------------------------------------------------------------------------

local function reduced()
	return ClientState.setting("ReducedEffects") == true
end

local function floatText(position, text, color)
	if floating >= PerformanceConfig.FloatingTexts then
		return
	end
	floating += 1
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0))
	anchor.Parent = Workspace.CurrentCamera
	local gui = Ui.new("BillboardGui", { Size = UDim2.fromOffset(180, 40), AlwaysOnTop = true, LightInfluence = 0, Adornee = anchor, Parent = anchor })
	local label = Ui.label(text, { Size = UDim2.fromScale(1, 1), Font = Ui.Fonts.Title, TextSize = 24, TextColor3 = color, TextStrokeTransparency = 0.4, Parent = gui })
	TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = anchor.CFrame + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.95, function()
		anchor:Destroy()
		floating -= 1
	end)
end
CollectController.floatText = floatText

local function flyIn(itemId, from)
	local root = ClientState.root()
	if not root or flying >= PerformanceConfig.FlyingPickups or reduced() then
		return
	end
	flying += 1
	local model = LootModels.build(itemId, CFrame.new(from), 1)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	model.Parent = Workspace.CurrentCamera
	local start = os.clock()
	local duration = 0.28
	local startPivot = model:GetPivot()
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, { part = p, offset = startPivot:ToObjectSpace(p.CFrame), size = p.Size })
		end
	end
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - start) / duration)
		local goal = root.Parent and (root.CFrame * CFrame.new(0, 1.2, -1.2)).Position or from
		local eased = t * t * (3 - 2 * t)
		local arc = Vector3.new(0, math.sin(t * math.pi) * 2.2, 0)
		local pos = from:Lerp(goal, eased) + arc
		local s = 1 - 0.7 * eased
		local pivot = CFrame.new(pos) * startPivot.Rotation * CFrame.Angles(0, t * 4, 0)
		for _, entry in ipairs(parts) do
			entry.part.Size = entry.size * s
			entry.part.CFrame = pivot * CFrame.new(entry.offset.Position * s) * entry.offset.Rotation
		end
		if t >= 1 then
			connection:Disconnect()
			model:Destroy()
			flying -= 1
		end
	end)
end

local function onCollected(userId, _lootId, itemId, position, value)
	local def = LootConfig.ById[itemId]
	if not def then
		return
	end
	local category = LootConfig.Categories[def.Category]
	local sound = category and category.Sound or "CashPickup"
	local me = Players.LocalPlayer
	if userId == me.UserId then
		flyIn(itemId, position)
		AudioController.play(sound, { pitch = 1 + math.min(0.25, (ClientState.inventory.count or 0) * 0.004) })
		floatText(position, "+$" .. Format.short(value), if LootConfig.rank(def) >= 4 then rarityColor(def) else Ui.Colors.Green)
		if LootConfig.rank(def) >= 4 then
			AudioController.play("RareDiscovery", { volume = 0.6 })
		end
	else
		AudioController.play(sound, { position = position, volume = 0.45, maxStack = 2, maxDistance = 60 })
	end
	if target and target.id == _lootId then
		target = nil
		showTarget(nil)
	end
end

function CollectController.init()
	lootFolder = Workspace:WaitForChild("Vault"):WaitForChild("Loot")
	for _, obj in ipairs(lootFolder:GetChildren()) do
		onAdded(obj)
	end
	lootFolder.ChildAdded:Connect(onAdded)
	lootFolder.ChildRemoved:Connect(onRemoved)
	Ui.touch = game:GetService("UserInputService").TouchEnabled and not game:GetService("UserInputService").KeyboardEnabled
	highlight = Instance.new("Highlight")
	highlight.Name = "LootTarget"
	highlight.FillTransparency = 0.85
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = Workspace.CurrentCamera
	billboard = Ui.new("BillboardGui", { Name = "LootPrompt", Size = UDim2.fromOffset(260, 34), StudsOffset = Vector3.new(0, 2.4, 0), AlwaysOnTop = true, LightInfluence = 0, Enabled = false, Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
	local back = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Ui.Colors.Black, BackgroundTransparency = 0.35, Parent = billboard })
	Ui.corner(back, 8)
	billboardText = Ui.label("", { Size = UDim2.fromScale(1, 1), Font = Ui.Fonts.Bold, TextSize = 15, Parent = back })
	ClientState.Collected:Connect(onCollected)
	ClientState.InventoryChanged:Connect(function()
		showTarget(target)
	end)
	RunService.Heartbeat:Connect(function(dt)
		scanClock += dt
		if scanClock >= 1 / PerformanceConfig.TargetScanRate then
			scanClock = 0
			CollectController.refresh()
		end
	end)
end

return CollectController
