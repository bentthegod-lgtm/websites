--[[
	Exports part geometry for a browser 3D preview (three.js), so the procedural models can
	be eyeballed without Studio.
	Usage (from sprout-valley/):
	  lune run tools/export_preview build/SproutValley.rbxlx crops   build/crops.json
	  lune run tools/export_preview build/SproutValley.rbxlx village build/village.json
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1] or "build/SproutValley.rbxlx"))
local mode = process.args[2] or "crops"
local outPath = process.args[3] or ("build/" .. mode .. ".json")

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
end)

local Rng = luau.load(fs.readFile("src/shared/Rng.lua"))()
local cache = {}
local env
local function requireModule(ms)
	if cache[ms] then
		return cache[ms]
	end
	local e = table.clone(env)
	e.script = ms
	cache[ms] = luau.load(ms.Source, { debugName = ms:GetFullName(), environment = e })()
	return cache[ms]
end
env = {
	game = setmetatable({}, {
		__index = function(_, k)
			if k == "GetService" then
				return function(_, n)
					return place:GetService(n)
				end
			end
			return place[k]
		end,
	}),
	workspace = place:GetService("Workspace"),
	require = requireModule,
	Instance = {
		new = function(c)
			local i = roblox.Instance.new(c)
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
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	Random = { new = function(s)
		return Rng.new(s or 1)
	end },
	warn = print,
}

local function r(n)
	return math.floor(n * 1000 + 0.5) / 1000
end
local out = {}
local function export(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local c = { d.CFrame:GetComponents() }
			for i, v in ipairs(c) do
				c[i] = r(v)
			end
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			table.insert(out, {
				cf = c,
				s = { r(d.Size.X), r(d.Size.Y), r(d.Size.Z) },
				c = { math.floor(d.Color.R * 255), math.floor(d.Color.G * 255), math.floor(d.Color.B * 255) },
				t = r(d.Transparency),
				m = d.Material.Name,
				sh = if d:IsA("SpawnLocation") or d.ClassName == "Part" then d.Shape.Name else "Block",
				mesh = mesh and mesh.MeshType.Name or nil,
			})
		end
	end
end

local Shared = place:GetService("ReplicatedStorage"):FindFirstChild("SproutValley")
if mode == "crops" then
	local CropConfig = requireModule(Shared.Config.CropConfig)
	local CropModels = requireModule(Shared.CropModels)
	for i, crop in ipairs(CropConfig.List) do
		local col = (i - 1) % 9
		local row = (i - 1) // 9
		for stage = 1, 4 do
			local cf = roblox.CFrame.new(col * 22 + (stage - 1) * 5, 0, row * 14)
			local opts = { seed = i }
			if stage == 4 and i % 5 == 0 then
				opts.variant = "Golden"
			end
			export(CropModels.build(crop, stage, cf, opts))
		end
	end
else
	local Services = place:GetService("ServerScriptService"):FindFirstChild("SproutValleyServer"):FindFirstChild("Services")
	local VillageBuilder = requireModule(Services.VillageBuilder)
	local CropConfig = requireModule(Shared.Config.CropConfig)
	local CropModels = requireModule(Shared.CropModels)
	local village = VillageBuilder.build()
	-- Fill plot 1 and 4 with a sample garden.
	for _, id in ipairs({ 1, 2, 4 }) do
		local plot = village.plots[id]
		for index = 1, 36 do
			local tile = plot.tiles[index]
			VillageBuilder.setTileLocked(tile, index > 24)
			if index <= 24 then
				local crop = CropConfig.List[((index + id * 5) % #CropConfig.List) + 1]
				local p = VillageBuilder.tileLocal(index)
				export(CropModels.build(crop, (index % 4) + 1, plot.cf * roblox.CFrame.new(p.X, p.Y, p.Z), { seed = index }))
			end
		end
	end
	export(village.folder)
end
fs.writeFile(outPath, serde.encode("json", out))
print(string.format("exported %d parts to %s", #out, outPath))
