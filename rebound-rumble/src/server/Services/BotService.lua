--[[
	BotService - clearly labelled "[BOT]" contestants so the game is playable solo and in
	near-empty servers. Bots obey the same server rules as players: they press parry at a
	distance chosen by BotBrain and BallService/ParryJudge decides like for anyone else.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ReboundRumble")
local GameConfig = require(Shared.Config.GameConfig)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local BotBrain = require(Shared.BotBrain)
local Clock = require(Shared.Clock)
local Rng = require(Shared.Rng)

local BotService = {}

local services
local rng
local bots = {}
local nextId = 0

local BODY_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(130, 255, 130),
	Color3.fromRGB(255, 200, 80),
	Color3.fromRGB(200, 120, 255),
	Color3.fromRGB(255, 140, 210),
}

function BotService.init(registry)
	services = registry
	rng = Rng.new(os.time() + 17)
end

function BotService.setSeed(seed)
	rng = Rng.new(seed)
end

local function limb(model, root, name, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.Massless = true
	p.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

-- Blocky robot rig (welded parts + Humanoid, moves with Humanoid:MoveTo).
function BotService.buildModel(name, color, cframe)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = cframe or CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	local dark = Color3.fromRGB(35, 38, 52)
	limb(model, root, "Torso", Vector3.new(2, 2, 1), CFrame.new(), color)
	local head = limb(model, root, "Head", Vector3.new(1.6, 1.2, 1.2), CFrame.new(0, 1.65, 0), dark, Enum.Material.Metal)
	limb(model, root, "Visor", Vector3.new(1.3, 0.35, 0.1), CFrame.new(0, 1.7, -0.62), Color3.fromRGB(120, 255, 255), Enum.Material.Neon)
	limb(model, root, "Antenna", Vector3.new(0.15, 0.7, 0.15), CFrame.new(0.5, 2.55, 0), dark, Enum.Material.Metal)
	limb(model, root, "AntennaTip", Vector3.new(0.35, 0.35, 0.35), CFrame.new(0.5, 2.95, 0), color, Enum.Material.Neon)
	limb(model, root, "Left Arm", Vector3.new(0.9, 2, 0.9), CFrame.new(-1.5, 0, 0), dark, Enum.Material.Metal)
	limb(model, root, "Right Arm", Vector3.new(0.9, 2, 0.9), CFrame.new(1.5, 0, 0), dark, Enum.Material.Metal)
	limb(model, root, "Left Leg", Vector3.new(0.95, 2, 0.95), CFrame.new(-0.5, -2, 0), dark, Enum.Material.Metal)
	limb(model, root, "Right Leg", Vector3.new(0.95, 2, 0.95), CFrame.new(0.5, -2, 0), dark, Enum.Material.Metal)
	limb(model, root, "ChestLight", Vector3.new(0.6, 0.6, 0.1), CFrame.new(0, 0.3, -0.52), color, Enum.Material.Neon)
	local humanoid = Instance.new("Humanoid")
	-- R15 so HipHeight (root bottom to the ground) is honoured (R6 ignores it); there is no
	-- Neck Motor6D in this welded rig, so don't let the neck check kill the bot.
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.RequiresNeck = false
	humanoid.HipHeight = 2
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = GameConfig.Bots.WalkSpeed
	humanoid.DisplayName = GameConfig.Bots.Label .. " " .. name
	-- The coloured "[BOT] name" billboard replaces the default name display.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	return model, root, humanoid, head
end

local function randomCosmetic(category)
	local options = {}
	for _, item in ipairs(CosmeticConfig.Items) do
		if item.Category == category and not item.Pass and (item.Rarity == "Common" or item.Rarity == "Rare") then
			table.insert(options, item.Id)
		end
	end
	return rng:pick(options)
end

--[[
	Creates `count` bots inside the arena. Returns contestant field tables for
	MatchService (which owns the contestant records).
]]
function BotService.spawn(count, arena, offset)
	local list = {}
	local names = table.clone(GameConfig.Bots.Names)
	rng:shuffle(names)
	for i = 1, count do
		nextId += 1
		local name = names[((i - 1) % #names) + 1]
		local cf = arena.spawns[(((offset or 0) + i - 1) % #arena.spawns) + 1]
		local model, root, humanoid = BotService.buildModel(name, BODY_COLORS[(i - 1) % #BODY_COLORS + 1], cf)
		model:SetAttribute("ContestantId", "b" .. nextId)
		model.Parent = arena.bots
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		services.MatchService.tagFor(model, GameConfig.Bots.Label .. " " .. name, Color3.fromRGB(180, 220, 255))
		local entry = {
			id = "b" .. nextId,
			name = name,
			isBot = true,
			model = model,
			skill = rng:range(GameConfig.Bots.SkillMin, GameConfig.Bots.SkillMax),
			cosmetics = { ParryFx = randomCosmetic("ParryFx"), Trail = randomCosmetic("Trail"), Explosion = randomCosmetic("Explosion") },
			humanoid = humanoid,
			wanderAt = 0,
			arena = arena,
		}
		table.insert(bots, entry)
		table.insert(list, entry)
	end
	return list
end

function BotService.onTargeted(c, speed)
	c.plan = BotBrain.plan(c.skill, speed, rng, GameConfig)
end

function BotService.kill(c)
	local humanoid = c.model and c.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
	if c.model then
		for _, d in ipairs(c.model:GetDescendants()) do
			if d:IsA("WeldConstraint") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.CanCollide = true
				d.Massless = false
			end
		end
		Debris:AddItem(c.model, 3)
	end
	local index = table.find(bots, c)
	if index then
		table.remove(bots, index)
	end
end

function BotService.clear()
	for _, c in ipairs(bots) do
		if c.model then
			c.model:Destroy()
		end
	end
	table.clear(bots)
end

function BotService.count()
	return #bots
end

local function think(c, now)
	local pos = services.MatchService.positionOf(c)
	if not pos then
		return
	end
	local ball = services.BallService.current()
	local targeted = ball and ball.targetId == c.id
	-- Parry decision.
	if targeted and c.plan and (ball.phase == "chasing" or ball.phase == "pending") then
		local distance = (ball.state.pos - pos).Magnitude
		if BotBrain.shouldPress(c.plan, distance) then
			c.plan.pressed = true
			local candidates = {}
			for _, other in ipairs(services.MatchService.alive()) do
				local p = services.MatchService.positionOf(other)
				if p and other ~= c then
					table.insert(candidates, { id = other.id, pos = p })
				end
			end
			local aimAt = BotBrain.chooseAim(c.id, candidates, ball.lastDeflector, rng)
			local aim = if aimAt then (aimAt.pos - pos) else Vector3.new(0, 0, -1)
			if aim.Magnitude < 0.1 then
				aim = Vector3.new(0, 0, -1)
			end
			services.BallService.tryParry(c, now, aim.Unit)
		end
	end
	-- Movement: wander, and back away from the ball while it hunts us.
	if now >= c.wanderAt and c.humanoid then
		c.wanderAt = now + rng:range(1.5, 3.5)
		local arena = c.arena
		local goal
		if targeted and ball then
			local away = pos - ball.state.pos
			away = Vector3.new(away.X, 0, away.Z)
			goal = pos + (if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)) * 14
		else
			local a = rng:range(0, math.pi * 2)
			local d = rng:range(0, arena.radius * 0.75)
			goal = arena.center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		end
		local flat = goal - arena.center
		flat = Vector3.new(flat.X, 0, flat.Z)
		if flat.Magnitude > arena.radius * 0.8 then
			flat = flat.Unit * arena.radius * 0.8
		end
		c.humanoid:MoveTo(arena.center + flat + Vector3.new(0, 3, 0))
		if rng:chance(0.15) then
			c.humanoid.Jump = true
		end
	end
end

function BotService.step()
	local now = Clock.now()
	for _, c in ipairs(table.clone(bots)) do
		if c.alive then
			think(c, now)
		end
	end
end

return BotService
