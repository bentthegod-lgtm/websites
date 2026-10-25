--[[
	Exports parts for a browser preview: the built world, a sample of scrap, a player with
	the magnet rig and a pile, and a catalog sheet of every scrap model + magnet tier.
	Usage (from magnet-mayhem/):
	  lune run tools/export_preview build/MagnetMayhem.rbxlx build/preview.json
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1] or "build/MagnetMayhem.rbxlx"))
local outPath = process.args[2] or "build/preview.json"
local workspaceService = place:GetService("Workspace")

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
end)
roblox.implementMethod("Model", "GetPivot", function(self)
	return self.PrimaryPart.CFrame
end)

local Rng = luau.load(fs.readFile("src/shared/Rng.lua"))()
local cache, env = {}, nil
local function requireModule(m)
	if cache[m] then
		return cache[m]
	end
	local e = table.clone(env)
	e.script = m
	cache[m] = luau.load(m.Source, { debugName = m:GetFullName(), environment = e })()
	return cache[m]
end
local game = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_, name)
				return place:GetService(name)
			end
		end
		return place[key]
	end,
})
env = {
	game = game,
	workspace = workspaceService,
	require = requireModule,
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	Random = {
		new = function(seed)
			return Rng.new(seed or 1)
		end,
	},
	typeof = typeof,
	print = print,
	warn = print,
}

local Shared = place:GetService("ReplicatedStorage"):FindFirstChild("MagnetMayhem")
local Server = place:GetService("ServerScriptService"):FindFirstChild("MagnetMayhemServer")
local ScrapConfig = requireModule(Shared.Config.ScrapConfig)
local MagnetConfig = requireModule(Shared.Config.MagnetConfig)
local ScrapModels = requireModule(Shared.ScrapModels)
local MagnetModel = requireModule(Shared.MagnetModel)
local PileLayout = requireModule(Shared.PileLayout)
local world = requireModule(Server.World.WorldBuilder).build()

local function r(n)
	return math.floor(n * 100 + 0.5) / 100
end
local function dump(container, list, transform)
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local cf = if transform then transform * d.CFrame else d.CFrame
			local rx, ry, rz = cf:ToOrientation()
			local c = d.Color
			table.insert(list, {
				p = { r(cf.Position.X), r(cf.Position.Y), r(cf.Position.Z) },
				o = { r(rx), r(ry), r(rz) },
				s = { r(d.Size.X), r(d.Size.Y), r(d.Size.Z) },
				c = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
				t = r(d.Transparency),
				m = d.Material.Name,
				sh = if d:IsA("WedgePart") then "Wedge" elseif d:IsA("Part") then d.Shape.Name else "Block",
			})
		end
	end
end

-- World + scattered scrap (deterministic sample from the real spawn regions).
local rng = Rng.new(5)
local scrap = roblox.Instance.new("Folder")
local function pick(zone, maxRank)
	local list = {}
	for _, def in ipairs(ScrapConfig.List) do
		if def.Zone == zone and (not maxRank or ScrapConfig.rank(def) <= maxRank) then
			table.insert(list, def)
		end
	end
	return list[rng:NextInteger(1, #list)]
end
for zoneId, regions in pairs(world.regions) do
	for _, region in ipairs(regions) do
		for _ = 1, math.floor(region.weight * 14) do
			local x = region.cx + (rng:NextNumber() - 0.5) * region.w
			local z = region.cz + (rng:NextNumber() - 0.5) * region.h
			local blocked = false
			for _, b in ipairs(world.blockers) do
				if (x - b.x) ^ 2 + (z - b.z) ^ 2 < b.r * b.r then
					blocked = true
				end
			end
			if not blocked then
				local def = pick(zoneId, if rng:NextNumber() < 0.85 then 1 else nil)
				ScrapModels.build(def.Id, roblox.CFrame.new(x, def.Size * 0.32, z) * roblox.CFrame.Angles(0, rng:NextNumber(0, 6), 0)).Parent = scrap
			end
		end
	end
end

-- A player near the shredder with a tier-3 magnet and a pile of 34 pieces.
local hero = roblox.Instance.new("Folder")
local rootCF = roblox.CFrame.new(6, 3, -6) * roblox.CFrame.Angles(0, math.rad(200), 0)
local function body(name, size, offset, color)
	local p = roblox.Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = rootCF * offset
	p.Color = color
	p.Parent = hero
end
body("Torso", roblox.Vector3.new(2, 2, 1), roblox.CFrame.new(0, 0, 0), roblox.Color3.fromRGB(60, 110, 190))
body("Head", roblox.Vector3.new(1.2, 1.2, 1.2), roblox.CFrame.new(0, 1.6, 0), roblox.Color3.fromRGB(240, 200, 160))
body("LegL", roblox.Vector3.new(0.9, 2, 0.9), roblox.CFrame.new(-0.5, -2, 0), roblox.Color3.fromRGB(50, 50, 60))
body("LegR", roblox.Vector3.new(0.9, 2, 0.9), roblox.CFrame.new(0.5, -2, 0), roblox.Color3.fromRGB(50, 50, 60))
body("ArmL", roblox.Vector3.new(0.8, 2, 0.8), roblox.CFrame.new(-1.45, 0, 0), roblox.Color3.fromRGB(240, 200, 160))
body("ArmR", roblox.Vector3.new(0.8, 2, 0.8), roblox.CFrame.new(1.45, 0, 0), roblox.Color3.fromRGB(240, 200, 160))
MagnetModel.build(3, "Default", rootCF).Parent = hero
local pileIds = { "Bolt", "SodaCan", "Gear", "Washer", "RustyPipe", "MetalSign", "Toolbox", "Bolt", "HeavyChain", "Gear", "SodaCan", "IndustrialFan", "Washer", "EngineComponent", "Bolt", "RustyPipe", "Gear", "SodaCan", "MotorcycleEngine", "Washer", "Bolt", "MetalSign", "Gear", "Toolbox", "SodaCan", "Bolt", "Washer", "Gear", "RustyPipe", "HeavyChain", "Bolt", "SodaCan", "Gear", "PowerCore" }
for i, id in ipairs(pileIds) do
	local def = ScrapConfig.ById[id]
	local scale = math.clamp(1.7 / def.Size, 0.22, 0.62)
	local x, y, z, yaw = PileLayout.slot(i, 0.8, def.Size * scale, 1)
	local base = roblox.CFrame.new(rootCF.Position) * roblox.CFrame.Angles(0, select(2, rootCF:ToOrientation()), 0)
	ScrapModels.build(id, base * roblox.CFrame.new(x, y, z) * roblox.CFrame.Angles(0.3 * math.sin(i), yaw, 0.2 * math.cos(i * 1.7)), scale).Parent = hero
end
-- Three objects mid-flight toward the player.
for i, id in ipairs({ "Toolbox", "Gear", "IndustrialFan" }) do
	local from = rootCF.Position + roblox.Vector3.new(-6 - i * 3, 1 + i, 6 + i * 2)
	ScrapModels.build(id, roblox.CFrame.new(from) * roblox.CFrame.Angles(i, i * 2, 0)).Parent = hero
end

-- Catalog sheet: every scrap model and every magnet tier in a row, far away.
local sheet = roblox.Instance.new("Folder")
for i, def in ipairs(ScrapConfig.List) do
	local col, row = (i - 1) % 9, math.floor((i - 1) / 9)
	ScrapModels.build(def.Id, roblox.CFrame.new(2000 + col * 9, def.Size * 0.5, row * 10) * roblox.CFrame.Angles(0, math.rad(200), 0)).Parent = sheet
end
for t = 1, #MagnetConfig.Tiers do
	MagnetModel.build(t, "Default", roblox.CFrame.new(2000 + (t - 1) * 7, 0, 36) * roblox.CFrame.Angles(0, math.rad(160), 0)).Parent = sheet
end

local out = { world = {}, scrap = {}, hero = {}, sheet = {}, scrapNames = {} }
dump(world.folder, out.world)
dump(scrap, out.scrap)
dump(hero, out.hero)
dump(sheet, out.sheet)
for _, def in ipairs(ScrapConfig.List) do
	table.insert(out.scrapNames, def.Name)
end
fs.writeFile(outPath, serde.encode("json", out))
print(string.format("exported %d world, %d scrap, %d hero, %d sheet parts", #out.world, #out.scrap, #out.hero, #out.sheet))
