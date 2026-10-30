--[[
	LakeBuilder - turns a LakeGen layout into parts, a few tiles at a time.

	A round's lake is 1,300 tiles (26 x 50) plus rocks, spires, braziers, drifts, the wreck
	and the lighthouse. Building it in one go would stall the server for a noticeable
	moment, so RoundService creates a job and calls job:step(GameConfig.Lake.TilesPerStep)
	once per Heartbeat while the round "prepares" (about 20 frames). Previews and tests can call LakeBuilder.buildAll.

	Every tile gets one ice part (except open water). IceService recolours / hides / restores
	that part as the ice cracks, breaks and refreezes (LakeBuilder.applyTile).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local LakeGen = require(Shared.LakeGen)
local Models = require(Shared.Models)
local Rng = require(Shared.Rng)

local LakeBuilder = {}
LakeBuilder.__index = LakeBuilder

local rgb = Color3.fromRGB
local M = Enum.Material
local P = Models.Palette
local L = GameConfig.Lake

local THICK_COLOR = {
	[1] = rgb(96, 150, 196), -- thin: dark and see-through (the water shows)
	[2] = P.Ice,
	[3] = P.IceLight,
}

local function zoneTint(tile)
	local t = GameConfig.Zones[tile.zone].Tint
	return rgb(t[1], t[2], t[3])
end

-- Sets a tile part's look from the tile's state (type, thickness, damage 0..1).
function LakeBuilder.applyTile(tile, damage)
	local p = tile.part
	if not p then
		return
	end
	if tile.type == "water" then
		p.Transparency = 1
		p.CanCollide = false
		p.CanQuery = false
		local cracks = p:FindFirstChild("Cracks")
		if cracks then
			cracks:Destroy()
		end
		return
	end
	p.CanCollide = true
	p.CanQuery = true
	local base = THICK_COLOR[tile.thick] or P.Ice
	if tile.thick >= 2 then
		base = base:Lerp(zoneTint(tile), 0.35)
	end
	if GameConfig.Zones[tile.zone].Dark then
		-- The Deep Hollow: black, glassy ice over deep water
		base = base:Lerp(rgb(30, 46, 78), 0.62)
	end
	damage = damage or 0
	p.Color = base:Lerp(rgb(70, 110, 150), damage * 0.6)
	p.Material = if tile.thick == 1 then M.Glass else M.Ice
	p.Transparency = if tile.thick == 1 then 0.3 else 0
	p.Reflectance = if tile.thick == 1 then 0.1 else 0.04
end

-- Cracks: a few dark lines on the top face (added once, when the tile first cracks).
function LakeBuilder.addCracks(tile, rng)
	local p = tile.part
	if not p or p:FindFirstChild("Cracks") then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Cracks"
	local top = p.CFrame * CFrame.new(0, p.Size.Y / 2 + 0.02, 0)
	for i = 1, 4 do
		local len = 2.5 + (if rng then rng:NextNumber() else 0.5) * 4
		local a = i * 0.8 + (if rng then rng:NextNumber() else 0)
		Models.part({ Name = "Crack", Size = Vector3.new(0.18, 0.05, len), CFrame = top * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, len * 0.3), Color = rgb(40, 70, 100), Material = M.SmoothPlastic, Parent = model, CastShadow = false })
	end
	model.Parent = p
end

function LakeBuilder.removeCracks(tile)
	local cracks = tile.part and tile.part:FindFirstChild("Cracks")
	if cracks then
		cracks:Destroy()
	end
end

function LakeBuilder.new(layout, parent)
	local folder = Instance.new("Folder")
	folder.Name = "Ice_" .. tostring(layout.seed)
	folder.Parent = parent
	local self = setmetatable({
		layout = layout,
		folder = folder,
		index = 1,
		done = false,
		parts = 0,
		rng = Rng.new(layout.seed + 17),
		wreckBuilt = false,
		features = Instance.new("Folder"),
	}, LakeBuilder)
	self.features.Name = "Features"
	self.features.Parent = folder
	return self
end

function LakeBuilder:_tile(tile)
	local x, z = LakeGen.cellToWorld(tile.c, tile.r)
	local top = L.IceTop
	local ground = CFrame.new(x, top, z)
	-- Holes are open water from the start: no ice part (the water plane shows through).
	-- Every other tile is a slab of ice; features sit on top of it.
	local slab = Models.part({ Name = "Ice", Size = Vector3.new(L.TileSize - 0.1, 1.2, L.TileSize - 0.1), CFrame = CFrame.new(x, top - 0.6, z), Material = M.Ice, Parent = self.folder, CanCollide = true })
	slab:SetAttribute("TI_Cell", LakeGen.key(tile.c, tile.r))
	tile.part = slab
	self.parts += 1
	LakeBuilder.applyTile(tile, 0)
	if tile.type == "water" then
		return
	end
	local rng = self.rng
	if tile.type == "rock" then
		if tile.style == "spire" then
			Models.spire(ground * CFrame.Angles(0, rng:NextNumber() * 6, 0), self.features, rng)
		elseif tile.style == "crystal" then
			Models.crystals(ground * CFrame.Angles(0, rng:NextNumber() * 6, 0), self.features, rng)
		else
			Models.boulder(ground * CFrame.Angles(0, rng:NextNumber() * 6, 0), self.features, rng)
		end
	elseif tile.type == "brazier" then
		Models.brazier(ground, self.features)
	elseif tile.type == "landmark" and not self.landmarkBuilt then
		self.landmarkBuilt = true
		local lc, lr = self.layout.landmarkCell[1], self.layout.landmarkCell[2]
		local x1, z1 = LakeGen.cellToWorld(lc, lr)
		local x2, z2 = LakeGen.cellToWorld(lc + 1, lr + 1)
		Models.lighthouse(CFrame.new((x1 + x2) / 2, top, (z1 + z2) / 2), self.features)
	elseif tile.type == "wreck" and not self.wreckBuilt then
		self.wreckBuilt = true
		local wc, wr = self.layout.wreckCell[1], self.layout.wreckCell[2]
		local x1, z1 = LakeGen.cellToWorld(wc, wr)
		local x2, z2 = LakeGen.cellToWorld(wc + 1, wr + 2)
		Models.wreck(CFrame.new((x1 + x2) / 2, top, (z1 + z2) / 2), self.features)
	elseif tile.thick == 3 and rng:NextNumber() < 0.3 then
		-- a dusting of snow on thick ice (thick ice looks safe; thin ice never gets snow)
		Models.part({ Name = "SnowPatch", Size = Vector3.new(rng:NextNumber(2, 5), 0.12, rng:NextNumber(2, 5)), CFrame = ground * CFrame.new(rng:NextNumber(-1.5, 1.5), 0.06, rng:NextNumber(-1.5, 1.5)) * CFrame.Angles(0, rng:NextNumber() * 3, 0), Color = P.Snow, Material = M.Snow, Parent = self.features, CastShadow = false })
	end
	if tile.drift then
		local drift = Models.drift(ground * CFrame.new(0, -0.8, 0), self.features)
		drift:SetAttribute("TI_Drift", LakeGen.key(tile.c, tile.r))
	end
end

-- Builds up to `budget` more tiles. Returns true once the whole lake exists.
function LakeBuilder:step(budget)
	if self.done then
		return true
	end
	local order = self.layout.order
	local last = math.min(#order, self.index + budget - 1)
	for i = self.index, last do
		self:_tile(order[i])
	end
	self.index = last + 1
	if self.index > #order then
		self.done = true
		local n = 0
		for _, d in ipairs(self.folder:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		self.parts = n
	end
	return self.done
end

function LakeBuilder:destroy()
	self.folder:Destroy()
end

function LakeBuilder.buildAll(layout, parent)
	local job = LakeBuilder.new(layout, parent)
	job:step(math.huge)
	return job
end

return LakeBuilder
