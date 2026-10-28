--[[
	Exports parts for a browser preview: the built facility with the three machines on
	pads and a dummy mid-flight, plus a sheet of every machine and dummy design.
	Usage (from crash-lab/):
	  lune run tools/export_preview build/CrashLab.rbxlx build/preview.json
	  node tools/render_preview.mjs build/preview.json build/
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1] or "build/CrashLab.rbxlx"))
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
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
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

local Shared = place:GetService("ReplicatedStorage"):FindFirstChild("CrashLab")
local Server = place:GetService("ServerScriptService"):FindFirstChild("CrashLabServer")
local MachineConfig = requireModule(Shared.Config.MachineConfig)
local CosmeticConfig = requireModule(Shared.Config.CosmeticConfig)
local MachineModels = requireModule(Shared.MachineModels)
local DummyModel = requireModule(Shared.DummyModel)
local world = requireModule(Server.World.FacilityBuilder).build()

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

-- The three machines on pads 2-4, as players would have them.
for i, id in ipairs(MachineConfig.Order) do
	local pad = world.pads[i + 1]
	local model = MachineModels.build(id, pad.cframe)
	model.Parent = pad.slot
end

-- A dummy mid-flight above the arena (arms out) and one crumpled on a crash pad.
local action = roblox.Instance.new("Folder")
DummyModel.build("Default", roblox.CFrame.new(-6, 34, 70) * roblox.CFrame.Angles(math.rad(-50), math.rad(20), math.rad(25)), { ragdoll = false }).Parent = action
DummyModel.build("Safety", roblox.CFrame.new(16, 8.5, 62) * roblox.CFrame.Angles(math.rad(-80), math.rad(70), 0), { ragdoll = false }).Parent = action

-- Sheet: every machine and every dummy design, far away.
local sheet = roblox.Instance.new("Folder")
for i, id in ipairs(MachineConfig.Order) do
	MachineModels.build(id, roblox.CFrame.new(2000 + (i - 2) * 16, 0, 0) * roblox.CFrame.Angles(0, math.rad(150), 0)).Parent = sheet
end
for i, id in ipairs(CosmeticConfig.SkinOrder) do
	DummyModel.build(id, roblox.CFrame.new(2000 + (i - 5) * 4.2, DummyModel.RootHeight, -16) * roblox.CFrame.Angles(0, math.rad(180), 0), { ragdoll = false }).Parent = sheet
end

local out = { world = {}, action = {}, sheet = {} }
dump(world.folder, out.world)
dump(action, out.action)
dump(sheet, out.sheet)
fs.writeFile(outPath, serde.encode("json", out))
print(string.format("exported %d world, %d action, %d sheet parts", #out.world, #out.action, #out.sheet))
