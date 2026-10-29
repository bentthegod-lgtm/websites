--[[
	Exports parts for a browser preview: the whole vault (every depth) with loot placed on
	a share of its spawn points, two mannequins carrying stacks at different sizes per depth,
	plus a catalog sheet of every loot model, every stack style and the carry crate.
	Usage (from vault/):
	  rojo build -o build/Vault.rbxlx
	  lune run tools/export_preview build/Vault.rbxlx build/preview.json
	  node tools/render_preview.mjs build/preview.json build/
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1] or "build/Vault.rbxlx"))
local outPath = process.args[2] or "build/preview.json"
local workspaceService = place:GetService("Workspace")

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
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
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	PhysicalProperties = roblox.PhysicalProperties,
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

local V3, CF = roblox.Vector3, roblox.CFrame
local Shared = place:GetService("ReplicatedStorage"):FindFirstChild("Vault")
local Server = place:GetService("ServerScriptService"):FindFirstChild("VaultServer")
local LootConfig = requireModule(Shared.Config.LootConfig)
local LootTable = requireModule(Shared.LootTable)
local LootModels = requireModule(Shared.LootModels)
local GameConfig = requireModule(Shared.Config.GameConfig)
local StackLayout = requireModule(Shared.StackLayout)
local world = requireModule(Server.World.VaultBuilder).build()

-- Loot on ~55% of every depth's spawn points, rolled like the server would.
local rng = Rng.new(7)
local loot = roblox.Instance.new("Folder")
for depth, record in pairs(world.depths) do
	local active = {}
	for _, point in ipairs(record.points) do
		if rng:NextNumber() < 0.55 then
			local def = LootTable.roll(depth, active, 1, rng, point.size)
			if def then
				active[def.Id] = (active[def.Id] or 0) + 1
				LootModels.build(def.Id, point.cframe, GameConfig.LootScale).Parent = loot
			end
		end
	end
end

-- A simple blocky mannequin (R6 proportions) carrying a stack laid out by StackLayout.
local function mannequin(parent, rootCF, counts, theme)
	local m = roblox.Instance.new("Model")
	local function block(size, cf, color)
		local p = roblox.Instance.new("Part")
		p.Size = size
		p.CFrame = rootCF * cf
		p.Color = color
		p.Parent = m
	end
	local skin, shirt, pants = roblox.Color3.fromRGB(234, 184, 146), roblox.Color3.fromRGB(40, 70, 130), roblox.Color3.fromRGB(40, 40, 46)
	block(V3.new(2, 2, 1), CF.new(0, 0, 0), shirt)
	block(V3.new(1.2, 1.2, 1.2), CF.new(0, 1.6, 0), skin)
	block(V3.new(1, 2, 1), CF.new(-1.5, 0, -0.4) * CF.Angles(math.rad(70), 0, 0), shirt)
	block(V3.new(1, 2, 1), CF.new(1.5, 0, -0.4) * CF.Angles(math.rad(70), 0, 0), shirt)
	block(V3.new(1, 2, 1), CF.new(-0.5, -2, 0), pants)
	block(V3.new(1, 2, 1), CF.new(0.5, -2, 0), pants)
	local layout = StackLayout.layout(counts, 24)
	for _, piece in ipairs(layout.pieces) do
		local cf = rootCF * CF.new(piece.x, piece.y, piece.z) * CF.Angles(0, piece.yaw, 0)
		local model = LootModels.piece(piece.category, theme, cf)
		if piece.scale and piece.scale ~= 1 then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Size *= piece.scale
				end
			end
		end
		model.Parent = m
	end
	if layout.crate then
		LootModels.crate(theme, rootCF * CF.new(0, StackLayout.CrateY, 0)).Parent = m
	end
	m.Parent = parent
end

local action = roblox.Instance.new("Folder")
local carry = {
	{ Cash = 2 },
	{ Cash = 10 },
	{ Gold = 24 },
	{ Diamond = 30, Cash = 4 },
	{ Emerald = 70 },
	{ Platinum = 80, Gold = 8 },
	{ Artifact = 60, Legendary = 60 },
}
for depth, record in pairs(world.depths) do
	mannequin(action, CF.new(-10, record.y0 + 3, -30) * CF.Angles(0, math.rad(200), 0), carry[depth], "Classic")
	mannequin(action, CF.new(10, record.y0 + 3, -30) * CF.Angles(0, math.rad(160), 0), { Cash = 140 }, if depth % 2 == 0 then "Gilded" else "NeonVault")
end

-- Catalog sheet far away: every loot model in rows by depth, then stack styles.
local sheet = roblox.Instance.new("Folder")
local col = {}
for _, def in ipairs(LootConfig.List) do
	col[def.Depth] = (col[def.Depth] or 0) + 1
	LootModels.build(def.Id, CF.new(3000 + (col[def.Depth] - 3) * 5, 0, (def.Depth - 4) * 6), 1.5).Parent = sheet
end
local modes = { { Cash = 2 }, { Cash = 9 }, { Gold = 30 }, { Diamond = 20, Emerald = 16 }, { Platinum = 60, Gold = 20 }, { Cash = 200 } }
for i, counts in ipairs(modes) do
	mannequin(sheet, CF.new(3000 + (i - 3.5) * 7, 3, 34) * CF.Angles(0, math.rad(180), 0), counts, "Classic")
end

local function r(n)
	return math.floor(n * 100 + 0.5) / 100
end
local function dump(container, list)
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
		end
	end
end

local out = { world = {}, loot = {}, action = {}, sheet = {} }
dump(world.folder, out.world)
dump(loot, out.loot)
dump(action, out.action)
dump(sheet, out.sheet)
fs.writeFile(outPath, serde.encode("json", out))
local counts = {}
for d, rec in pairs(world.depths) do
	table.insert(counts, string.format("B%d %d parts / %d points", d, rec.parts, #rec.points))
end
table.sort(counts)
print(string.format("exported %d world, %d loot, %d action, %d sheet parts (world total %d)", #out.world, #out.loot, #out.action, #out.sheet, world.partCount))
print(table.concat(counts, "\n"))
