--[[
	Themes - per-depth materials, the shared building helpers (ambient emitters, lights,
	decorative loot) and the preview rooms that show the next depth's loot behind glass.
	Ambient sound emitters are invisible parts tagged with an AmbientSound attribute; the
	client attaches the 3D sounds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Vault")
local LootModels = require(Shared.LootModels)

local Themes = {}

local M = Enum.Material
local rgb = Color3.fromRGB

local STYLES = {
	{ WallMaterial = M.Concrete, FloorMaterial = M.Concrete, LightBrightness = 2.4 },
	{ WallMaterial = M.Concrete, FloorMaterial = M.DiamondPlate, LightBrightness = 2.3, PipeColor = rgb(150, 110, 60) },
	{ WallMaterial = M.Marble, FloorMaterial = M.Marble, FloorReflect = 0.12, LightBrightness = 2.3 },
	{ WallMaterial = M.Slate, FloorMaterial = M.Slate, LightBrightness = 2.2 },
	{ WallMaterial = M.Metal, FloorMaterial = M.Concrete, LightBrightness = 2.5, PipeColor = rgb(170, 200, 230) }, -- concrete slab: a full metal floor blew out under the strip lights
	{ WallMaterial = M.Sandstone, FloorMaterial = M.Sandstone, LightBrightness = 2.2, PipeColor = rgb(140, 110, 70) },
	{ WallMaterial = M.Marble, FloorMaterial = M.Marble, FloorReflect = 0.15, LightBrightness = 2.3, PipeColor = rgb(200, 160, 60) },
}

function Themes.style(depth)
	return STYLES[depth] or STYLES[1]
end

-- Helpers -----------------------------------------------------------------------------------

local function emitter(ctx, pos, sound)
	local p = ctx.b.deco({ Name = "AmbientEmitter", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos), Transparency = 1 })
	p:SetAttribute("AmbientSound", sound)
	ctx.ambience = ctx.ambience or {}
	table.insert(ctx.ambience, p)
end

local function light(part, kind, color, brightness, range, shadows)
	local l = Instance.new(kind or "PointLight")
	l.Color = color
	l.Brightness = brightness or 1
	l.Range = range or 14
	l.Shadows = shadows == true
	if l:IsA("SpotLight") then
		l.Face = Enum.NormalId.Bottom
		l.Angle = 70
	end
	l.Parent = part
	return l
end

-- Static decorative loot (behind glass / in cages / on the landmark): no hitbox, no
-- sparkle, no light - never mistaken for a pickup, never adds a light.
local function decoLoot(ctx, itemId, cf, scale)
	local model = LootModels.build(itemId, cf, scale)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	if model.PrimaryPart then
		model.PrimaryPart:Destroy()
	end
	model.Name = "Display_" .. itemId
	model.Parent = ctx.folder
	ctx.b.count += #model:GetChildren()
	return model
end

Themes.helpers = { emitter = emitter, light = light, decoLoot = decoLoot }

function Themes.build(ctx)
	-- The preview chamber shows the next depth's loot on its plinths (decor).
	local LootConfig = require(Shared.Config.LootConfig)
	local nextPool = ctx.preview and ctx.preview.nextDepth and LootConfig.ByDepth[ctx.preview.nextDepth]
	if ctx.preview then
		for i, cf in ipairs(ctx.preview.cframes) do
			if nextPool then
				local def = nextPool[math.min(#nextPool, i + 1)]
				decoLoot(ctx, def.Id, cf)
			else
				-- Beyond B7: the sealed Ancient Vault, shown as stone silhouettes.
				local idol = decoLoot(ctx, "AncientIdol", cf)
				for _, p in ipairs(idol:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Color = rgb(110, 104, 96)
						p.Material = M.Slate
					end
				end
			end
		end
	end
end

return Themes
