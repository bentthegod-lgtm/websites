--[[
	Exports parts (and lights) for a browser preview: the shore camp and a generated Normal
	lake with its cores, braziers and the Antlered, a staged scene for the store art, and a
	character sheet (kids in every outfit, a frozen kid, the Antlered).
	Usage (from thin-ice/):
	  lune run tools/export_preview build/ThinIce.rbxlx build/preview.json
	  node tools/render_preview.mjs build/preview.json build/
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1] or "build/ThinIce.rbxlx"))
local outPath = process.args[2] or "build/preview.json"
local workspaceService = place:GetService("Workspace")

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
end)
roblox.implementMethod("Model", "GetPivot", function(self)
	return self.PrimaryPart.CFrame
end)
roblox.implementMethod("Model", "PivotTo", function(self, cf)
	local delta = cf * self.PrimaryPart.CFrame:Inverse()
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
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

local Shared = place:GetService("ReplicatedStorage"):FindFirstChild("ThinIce")
local Server = place:GetService("ServerScriptService"):FindFirstChild("ThinIceServer")
local GameConfig = requireModule(Shared.Config.GameConfig)
local CosmeticConfig = requireModule(Shared.Config.CosmeticConfig)
local LakeGen = requireModule(Shared.LakeGen)
local Models = requireModule(Shared.Models)
local LakeBuilder = requireModule(Server.World.LakeBuilder)
local world = requireModule(Server.World.LobbyBuilder).build(workspaceService)
local CF, V3 = roblox.CFrame, roblox.Vector3
local L = GameConfig.Lake

local seed = tonumber(process.args[3]) or 4242
local layout = LakeGen.generate(seed, "Normal")
local job = LakeBuilder.buildAll(layout, world.lakeFolder)
local function at(c, r)
	local x, z = LakeGen.cellToWorld(c, r)
	return V3.new(x, L.IceTop, z)
end
for _, core in ipairs(layout.cores) do
	Models.frozenCore(CF.new(at(core.c, core.r)), world.lakeFolder)
end
-- the beacon half lit, like mid-round
world.beacon.flame.Transparency = 0.35
world.beacon.light.Brightness = 1.6

local function rgb(t)
	return roblox.Color3.fromRGB(t[1], t[2], t[3])
end
local function kid(cf, parent, outfitId, lanternId)
	local o = CosmeticConfig.Outfits[outfitId]
	local lantern = CosmeticConfig.Lanterns[lanternId or "Warm"]
	return Models.kid(cf, parent, { Jacket = rgb(o.Jacket), Scarf = rgb(o.Scarf), Beanie = rgb(o.Beanie), Lantern = rgb(lantern.Color) })
end

-- Staged action on the lake: a team crossing the Thin Flats, one kid frozen, a cracked
-- tile, and the Antlered listening in the Boulder Isles.
local action = roblox.Instance.new("Folder")
local function stand(c, r)
	local p = at(c, r)
	return CF.new(p.X, L.IceTop, p.Z)
end
kid(stand(7, 9) * CF.Angles(0, math.rad(170), 0), action, "Classic")
kid(stand(9, 10) * CF.Angles(0, math.rad(200), 0), action, "Berry", "Frost")
kid(stand(5, 11) * CF.Angles(0, math.rad(150), 0), action, "Mint")
local frozen = kid(stand(10, 12) * CF.Angles(0, math.rad(210), 0), action, "Midnight", "Aurora")
Models.iceBlock(stand(10, 12), action)
local cracked = layout.tiles[LakeGen.key(8, 10)]
if cracked.part then
	LakeBuilder.addCracks(cracked, Rng.new(3))
end
local monster = Models.monster(stand(8, 15) * CF.Angles(0, math.rad(10), 0), action)
local carried = Models.carriedShard(stand(9, 10) * CF.new(0, 7.4, 0), action)
local _ = frozen and carried and monster

-- Poster staging for the store art: out in The Deep Hollow, a kid with a lantern, the
-- half-sunken lighthouse behind, and the Antlered stepping out of the fog toward them.
local poster = roblox.Instance.new("Folder")
kid(CF.new(-12, L.IceTop, 346) * CF.Angles(0, math.rad(212), 0), poster, "Berry", "Warm")
Models.monster(CF.new(4, L.IceTop, 372) * CF.Angles(0, math.rad(31), 0), poster)
kid(CF.new(-30, L.IceTop, 366) * CF.Angles(0, math.rad(150), 0), poster, "Mint", "Frost")
Models.iceBlock(CF.new(-30, L.IceTop, 366), poster)

-- Character sheet far away (x = 2000).
local sheet = roblox.Instance.new("Folder")
for i, id in ipairs(CosmeticConfig.OutfitOrder) do
	kid(CF.new(2000 + (i - 4) * 4.2, 0, 0) * CF.Angles(0, math.rad(-12), 0), sheet, id, CosmeticConfig.LanternOrder[(i - 1) % 4 + 1])
end
kid(CF.new(2000 - 22, 0, 4) * CF.Angles(0, math.rad(-12), 0), sheet, "Polar")
Models.iceBlock(CF.new(2000 - 22, 0, 4), sheet)
Models.monster(CF.new(2000 + 26, 0, 8) * CF.Angles(0, math.rad(15), 0), sheet)

local function r(n)
	return math.floor(n * 100 + 0.5) / 100
end
local function dump(container, list, lights)
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local cf = d.CFrame
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
		elseif d:IsA("PointLight") and d.Parent and d.Parent:IsA("BasePart") then
			local p = d.Parent.CFrame.Position
			local c = d.Color
			table.insert(lights, { p = { r(p.X), r(p.Y), r(p.Z) }, c = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }, range = d.Range, b = d.Brightness })
		end
	end
end

local out = { world = {}, action = {}, sheet = {}, poster = {}, lights = {}, sheetLights = {}, posterLights = {} }
dump(world.folder, out.world, out.lights)
dump(action, out.action, out.lights)
dump(sheet, out.sheet, out.sheetLights)
dump(poster, out.poster, out.posterLights)
for _, l in ipairs(out.lights) do
	table.insert(out.posterLights, l)
end
out.lake = { parts = job.parts, seed = seed }
out.shoreParts = world.partCount
fs.writeFile(outPath, serde.encode("json", out))
print(string.format("exported %d world (shore %d + lake %d), %d action, %d sheet parts, %d lights", #out.world, world.partCount, job.parts, #out.action, #out.sheet, #out.lights))
