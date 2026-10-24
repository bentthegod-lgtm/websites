--[[
	Exports every Blobby species (plain + Gold/Diamond/Rainbow) as JSON part lists, built by
	the real BlobbyModels module, for a browser 3D preview (tools/render_preview.mjs).
	Usage (from snatch-tycoon/):
	  rojo build -o build/SnatchTycoon.rbxlx
	  lune run tools/export_blobbies build/SnatchTycoon.rbxlx build/blobbies.json
	  lune run tools/export_blobbies build/SnatchTycoon.rbxlx build/world.json world
	The "world" mode exports the whole map (WorldBuilder) with a few Blobbies on plot 1.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1] or "build/SnatchTycoon.rbxlx"))
local outPath = process.args[2] or "build/blobbies.json"
local mode = process.args[3] or "blobbies"

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
end)

local fakeCollection = {
	AddTag = function(_, inst, tag)
		inst:AddTag(tag)
	end,
}
local game = {
	GetService = function(_, name)
		if name == "CollectionService" then
			return fakeCollection
		end
		return place:GetService(name)
	end,
}
local cache = {}
local env
local function requireModule(m)
	if cache[m] == nil then
		local e = table.clone(env)
		e.script = m
		cache[m] = luau.load(m.Source, { debugName = m:GetFullName(), environment = e })()
	end
	return cache[m]
end
env = {
	game = game,
	require = requireModule,
	Instance = {
		new = function(className)
			local i = roblox.Instance.new(className)
			if i:IsA("BasePart") then
				i.Position = roblox.Vector3.zero
			end
			return i
		end,
	},
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
	workspace = place:GetService("Workspace"),
}

local Shared = place:GetService("ReplicatedStorage"):FindFirstChild("SnatchTycoon")
local BlobbyModels = requireModule(Shared.BlobbyModels)
local BlobbyConfig = requireModule(Shared.Config.BlobbyConfig)
local RarityConfig = requireModule(Shared.Config.RarityConfig)
local MutationConfig = requireModule(Shared.Config.MutationConfig)

local function exportParts(root, list)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			table.insert(list, {
				shape = if mesh then "Ellipsoid" elseif d:IsA("SpawnLocation") then "Block" else d.Shape.Name,
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				cf = { d.CFrame:GetComponents() },
				color = { d.Color.R, d.Color.G, d.Color.B },
				material = d.Material.Name,
				transparency = d.Transparency,
				rainbow = d:GetAttribute("Rainbow") == true,
			})
		end
	end
	return list
end

if mode == "world" then
	local WorldBuilder = requireModule(place:GetService("ServerScriptService"):FindFirstChild("SnatchTycoonServer").Services.WorldBuilder)
	local world = WorldBuilder.build()
	local parts = exportParts(world.folder, {})
	-- a few Blobbies on plot 1 and the carpet, plus a locked laser door on plot 2
	for slot = 1, 9 do
		local species = BlobbyConfig.List[(slot * 2) % #BlobbyConfig.List + 1]
		local built = BlobbyModels.build(species, world.plots[1].pedestals[slot].standCFrame, { rarity = RarityConfig.Tiers[species.Rarity] })
		exportParts(built.model, parts)
	end
	for i = 1, 6 do
		local species = BlobbyConfig.List[i * 3 % #BlobbyConfig.List + 1]
		local pos = roblox.Vector3.new((i % 3 - 1) * 3, 0.3, -120 + i * 14)
		local built = BlobbyModels.build(species, roblox.CFrame.lookAt(pos, pos + roblox.Vector3.new(0, 0, 1)), { rarity = RarityConfig.Tiers[species.Rarity] })
		exportParts(built.model, parts)
	end
	for _, bar in ipairs(world.plots[2].laser.bars) do
		bar.Transparency = 0.05
	end
	exportParts(world.plots[2].model, {})
	local plot1 = world.plots[1].cframe
	fs.writeFile(outPath, serde.encode("json", { parts = parts, plot1 = { plot1:GetComponents() } }))
	print(string.format("exported world with %d visible parts to %s", #parts, outPath))
	return
end

local out = {}
for _, species in ipairs(BlobbyConfig.List) do
	for _, mutation in ipairs({ "", "Gold", "Diamond", "Rainbow" }) do
		local built = BlobbyModels.build(species, roblox.CFrame.new(), {
			rarity = RarityConfig.Tiers[species.Rarity],
			mutation = if mutation ~= "" then mutation else nil,
			mutationDef = if mutation ~= "" then MutationConfig.Types[mutation] else nil,
		})
		table.insert(out, {
			id = species.Id,
			name = species.Name,
			rarity = species.Rarity,
			rarityColor = RarityConfig.Tiers[species.Rarity].Color,
			mutation = mutation,
			height = built.height,
			parts = exportParts(built.model, {}),
		})
	end
end
fs.writeFile(outPath, serde.encode("json", out))
print(string.format("exported %d models to %s", #out, outPath))
