--[[
	Exports parts (and lights) for browser previews: the harbour with the Gull moored, each
	ship on its own, the Leviathan mid-sink (tilted, the water line at Y = 0), and loot /
	character props.
	Usage (from last-lifeboat/):
	  lune run tools/export_preview build/LastLifeboat.rbxlx build/preview.json
	  node tools/render_preview.mjs build/preview.json build/
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1] or "build/LastLifeboat.rbxlx"))
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

local Shared = place:GetService("ReplicatedStorage"):FindFirstChild("LastLifeboat")
local Server = place:GetService("ServerScriptService"):FindFirstChild("LastLifeboatServer")
local GameConfig = requireModule(Shared.Config.GameConfig)
local ShipGen = requireModule(Shared.ShipGen)
local LurchMath = requireModule(Shared.LurchMath)
local Models = requireModule(Shared.Models)
local ShipBuilder = requireModule(Server.World.ShipBuilder)
local LobbyBuilder = requireModule(Server.World.LobbyBuilder)
local CF, V3 = roblox.CFrame, roblox.Vector3

local seed = tonumber(process.args[3]) or 4242
local lobby = roblox.Instance.new("Folder")
local world = LobbyBuilder.build(lobby)

local ships, records = {}, {}
for _, key in ipairs(GameConfig.ShipOrder) do
	local folder = roblox.Instance.new("Folder")
	local plan = ShipGen.plan(key, seed)
	local record = ShipBuilder.buildAll(plan, folder, LobbyBuilder.shipBase(key))
	-- loot models on every spot (rolled like LootService does)
	local rng = Rng.new(seed)
	local LootMath = requireModule(Shared.LootMath)
	for _, spot in ipairs(plan.loot) do
		local depth = 1 - (spot.deck - 1) / math.max(1, #plan.decks - 1)
		local item = LootMath.roll(rng, depth, plan.def.Tier)
		Models.loot(item, LobbyBuilder.shipBase(key) * CF.new(spot.x, plan.decks[spot.deck].y, spot.z), record.lootFolder)
	end
	ships[key] = folder
	records[key] = record
	print(string.format("%s: %d parts (estimate %d), %d loose props, %d loot", key, record.parts, plan.partEstimate, #record.loose, #plan.loot))
end

-- Mid-sink: a second Leviathan, tilted by the lurch maths two thirds of the way through.
local sunkFolder = roblox.Instance.new("Folder")
local sunkPlan = ShipGen.plan("Leviathan", seed)
local sunkBase = LobbyBuilder.shipBase("Leviathan")
local sunkRecord = ShipBuilder.buildAll(sunkPlan, sunkFolder, sunkBase)
local def = GameConfig.Ships.Leviathan
local n = LurchMath.expectedLurches(def)
local k = math.floor(n * 0.7)
local pivot = LurchMath.pivotFor(def, sunkBase, k, n)
sunkRecord.model:PivotTo(pivot)
local delta = LurchMath.delta(sunkBase, pivot)
for _, entry in ipairs(sunkRecord.loose) do
	entry.part.CFrame = delta * entry.part.CFrame
end
print(string.format("mid-sink: lurch %d/%d, tilt %.1f deg, sink %.1f", k, n, LurchMath.tiltAt(def, k, n), LurchMath.sinkAt(def, k, n)))

-- Characters and loot sheet (x = 2000).
local sheet = roblox.Instance.new("Folder")
for i, key in ipairs(GameConfig.LootOrder) do
	Models.loot(key, CF.new(2000 + (i - 7) * 4, 0, 0), sheet)
end
Models.dummy(CF.new(1990, 0, 10), sheet, false)
Models.dummy(CF.new(1996, 0, 10), sheet, true)
-- a crew on the Gull's top deck (for the lobby / ship shots)
local crew = roblox.Instance.new("Folder")
local gullPlan = ShipGen.plan("Gull", seed)
local gullBase = LobbyBuilder.shipBase("Gull")
local top = gullPlan.decks[#gullPlan.decks].y
for i = 1, 4 do
	Models.dummy(gullBase * CF.new(-4 + i * 2, top, 30 + i * 3) * CF.Angles(0, math.rad(180), 0), crew, i == 2)
end
for i = 1, 3 do
	Models.dummy(CF.new(-10 - i * 4, GameConfig.World.DockTop, -4 + i * 3) * CF.Angles(0, math.rad(-90), 0), crew, i == 1)
end

local function r(x)
	return math.floor(x * 100 + 0.5) / 100
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
				sh = if d:IsA("WedgePart") then "Wedge" elseif d:IsA("TrussPart") then "Truss" elseif d:IsA("Part") then d.Shape.Name else "Block",
			})
		elseif d:IsA("PointLight") and d.Parent and d.Parent:IsA("BasePart") then
			local p = d.Parent.CFrame.Position
			local c = d.Color
			table.insert(lights, { p = { r(p.X), r(p.Y), r(p.Z) }, c = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }, range = d.Range, b = d.Brightness })
		end
	end
end

local out = { lights = {}, sheetLights = {} }
out.lobby = {}
dump(lobby, out.lobby, out.lights)
for key, folder in pairs(ships) do
	out["ship_" .. key] = {}
	out["lights_" .. key] = {}
	dump(folder, out["ship_" .. key], out["lights_" .. key])
end
out.sunk = {}
out.sunkLights = {}
dump(sunkFolder, out.sunk, out.sunkLights)
out.crew = {}
dump(crew, out.crew, out.lights)
out.sheet = {}
dump(sheet, out.sheet, out.sheetLights)
for _, l in ipairs(out.lights_Gull) do
	table.insert(out.lights, l)
end
-- plan geometry for annotations
out.decks = {}
for key, record in pairs(records) do
	out.decks[key] = { length = record.plan.length, beam = record.plan.beam, decks = {} }
	for _, deck in ipairs(record.plan.decks) do
		table.insert(out.decks[key].decks, deck.y)
	end
end
fs.writeFile(outPath, serde.encode("json", out))
print(string.format("exported lobby %d parts (%d built), sunk %d, sheet %d", #out.lobby, world.partCount, #out.sunk, #out.sheet))
