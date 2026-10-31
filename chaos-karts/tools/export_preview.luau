--[[
	Exports the built world (track, city, lobby) plus 12 karts on the starting grid and a
	Quackaroni mid-parade as JSON for the three.js previews, with camera views computed from
	the track data (so they follow the map if it changes).
	Usage (from chaos-karts/):
	  lune run tools/export_preview build/ChaosKarts.rbxlx build/preview.json
	  node tools/render_preview.mjs build/preview.json build/
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile(process.args[1] or "build/ChaosKarts.rbxlx"))
local outPath = process.args[2] or "build/preview.json"
local workspaceService = place:GetService("Workspace")

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return self:FindFirstChild(name)
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
	os = os,
}

local Shared = place:GetService("ReplicatedStorage"):FindFirstChild("ChaosKarts")
local Server = place:GetService("ServerScriptService"):FindFirstChild("ChaosKartsServer")
local ChaosCity = requireModule(Shared.Maps.ChaosCity)
local VehicleModels = requireModule(Shared.VehicleModels)
local KartStats = requireModule(Shared.Config.KartStats)
local GameConfig = requireModule(Shared.Config.GameConfig)
local Registry = requireModule(Shared.Events.Registry)
local World = requireModule(Server.World.World)
local CF, V3 = roblox.CFrame, roblox.Vector3

local world = World.new(ChaosCity, workspaceService)
world.job:finish()
local data = world.data
local main = data.main
print(string.format("world: %d parts", world:partCount()))

-- 12 karts on the grid (alternating bodies, bot colours)
local karts = roblox.Instance.new("Folder")
for slot, cf in ipairs(data.grid) do
	local vehicles = { "Sparkplug", "BubblegumBumper" }
	local color = GameConfig.Bots.Colors[slot]
	VehicleModels.build(vehicles[(slot - 1) % 2 + 1], { cframe = cf, driverColor = color, parent = karts })
end
-- the two karts up close (showroom sheet, x = 3000)
local sheet = roblox.Instance.new("Folder")
VehicleModels.build("Sparkplug", { cframe = CF.new(2990, KartStats.RideHeight, 0) * CF.Angles(0, math.rad(210), 0), parent = sheet })
VehicleModels.build("BubblegumBumper", { cframe = CF.new(3010, KartStats.RideHeight, 0) * CF.Angles(0, math.rad(150), 0), parent = sheet })
local sheetFloor = roblox.Instance.new("Part")
sheetFloor.Size = V3.new(80, 1, 60)
sheetFloor.CFrame = CF.new(3000, -0.5, 0)
sheetFloor.Color = roblox.Color3.fromRGB(40, 36, 70)
sheetFloor.Parent = sheet

-- Quackaroni mid-parade on the Neon Plaza (client visuals, played like the client does)
local events = roblox.Instance.new("Folder")
local Quack = Registry.module("QuackaroniParade")
local zone = data.zoneById.NeonPlaza
local ctx = {
	seed = 77,
	zone = zone,
	data = data,
	startAt = 10,
	endAt = 22,
	now = function()
		return 15.6
	end,
	maid = { give = function(_, x)
		return x
	end },
	folder = events,
	sound = function() end,
	shake = function() end,
	localKart = function()
		return nil
	end,
}
Quack.play(ctx)
Quack.step(ctx, 0)

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
				sh = if d:IsA("WedgePart") then "Wedge" elseif d:IsA("Part") then d.Shape.Name else "Block",
			})
		elseif (d:IsA("PointLight") or d:IsA("SpotLight")) and d.Parent and d.Parent:IsA("BasePart") then
			local p = d.Parent.CFrame.Position
			local c = d.Color
			table.insert(lights, { p = { r(p.X), r(p.Y), r(p.Z) }, c = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }, range = d.Range, b = math.max(d.Brightness, 0.6) })
		end
	end
end

local out = { world = {}, lights = {}, karts = {}, sheet = {}, events = {}, views = {} }
dump(world.root, out.world, out.lights)
dump(karts, out.karts, out.lights)
dump(sheet, out.sheet, out.lights)
dump(events, out.events, out.lights)

-- camera views from the track data
local function at(pointIndex, offset)
	return main:at((data.pointDist[pointIndex] + (offset or 0)) % main.length)
end
local function view(name, eye, target, fov, extra)
	local v = { name = name, eye = { r(eye.X), r(eye.Y), r(eye.Z) }, target = { r(target.X), r(target.Y), r(target.Z) }, fov = fov or 60 }
	for k, x in pairs(extra or {}) do
		v[k] = x
	end
	table.insert(out.views, v)
end
local function chaseView(name, pointIndex, back, up, side, ahead, fov)
	local s = at(pointIndex)
	local eye = s.pos - s.flat * back + V3.new(0, up, 0) + s.right * (side or 0)
	local target = s.pos + s.flat * (ahead or 40) + V3.new(0, 4, 0)
	view(name, eye, target, fov)
end
-- the full plan, from above (x across, z down the image)
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, s in ipairs(main.samples) do
	minX, maxX = math.min(minX, s.pos.X), math.max(maxX, s.pos.X)
	minZ, maxZ = math.min(minZ, s.pos.Z), math.max(maxZ, s.pos.Z)
end
local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
view("preview-plan", V3.new(cx, 2600, cz + 0.01), V3.new(cx, 0, cz), 52, { top = true, groups = { "world", "karts" } })
-- start / finish gantry with the grid
local s0 = at(1)
view("preview-start-gantry", s0.pos - s0.flat * 150 + V3.new(26, 22, 0) + s0.right * 18, s0.pos + V3.new(0, 14, 0), 55, { groups = { "world", "karts" } })
view("preview-grid-karts", s0.pos - s0.flat * 40 + V3.new(0, 16, 0) + s0.right * 34, s0.pos - s0.flat * 80, 50, { groups = { "world", "karts" } })
-- downtown neon (looking down the straight from the hairpin end)
chaseView("preview-downtown-neon", 55, 30, 14, -6, 160, 66)
-- the elevated highway / overpass (from below, beside the north leg) and on top of it
local o = at(14)
view("preview-highway-overpass", o.pos + V3.new(120, 8, 160), o.pos + V3.new(-20, 20, 0), 62)
chaseView("preview-highway-deck", 12, 40, 16, 0, 120, 62)
-- the river bridge
local b = at(35)
view("preview-river-bridge", b.pos + b.right * 160 + V3.new(0, 30, 60), b.pos + V3.new(0, 4, 0), 55)
-- the banked bowl, from inside the infield
local bw = at(7)
view("preview-banked-turn", bw.pos + bw.right * 120 - bw.flat * 120 + V3.new(0, 30, 0), bw.pos + bw.flat * 60 + V3.new(0, 10, 0), 66)
chaseView("preview-banked-turn-driver", 6, 26, 9, 8, 80, 70)
-- the big jump, from the side as a kart would see it on the run-up
local j = at(38)
view("preview-big-jump", j.pos + j.right * 110 - j.flat * 40 + V3.new(0, 20, 0), j.pos + j.flat * 40 + V3.new(0, 4, 0), 58)
chaseView("preview-big-jump-runup", 36, 10, 10, 0, 90, 64)
-- shortcuts
local roof = data.byId.RooftopLeap
local rf = roof.track:at(roof.gapStart - 40)
view("preview-shortcut-rooftop", rf.pos - rf.flat * 30 + V3.new(0, 14, 0) + rf.right * 10, rf.pos + rf.flat * 90 - V3.new(0, 8, 0), 64)
local roofWide = roof.track:at(roof.track.length / 2)
view("preview-shortcut-rooftop-wide", roofWide.pos + V3.new(-220, 90, 60), roofWide.pos, 56)
local alley = data.byId.NeonAlley
local al = alley.track:at(70)
local al2 = alley.track:at(220)
view("preview-shortcut-alley", al.pos + V3.new(0, 6, 0), al2.pos + V3.new(0, 3, 0), 70)
local alw = alley.track:at(alley.track.length / 2)
view("preview-shortcut-alley-wide", alw.pos + V3.new(0, 160, 170), alw.pos, 55)
-- the tunnel (inside, then the portal from outside)
local t0, t1 = at(20, -10), at(22)
view("preview-tunnel", t0.pos + V3.new(0, 6, 0) + t0.right * -6, t1.pos + V3.new(0, 5, 0), 72, { interior = true })
local tp = at(19)
view("preview-tunnel-portal", tp.pos - tp.flat * 90 + V3.new(30, 30, 0), tp.pos + tp.flat * 40 - V3.new(0, 8, 0), 60)
-- the landmark statue on the Neon Plaza (with the parade crossing)
local plaza = world.plaza
local toTrack = (zone.centre - plaza)
toTrack = V3.new(toTrack.X, 0, toTrack.Z).Unit
view("preview-statue", plaza + toTrack * 75 + V3.new(25, 22, 0), plaza + V3.new(0, 30, 0), 58, { groups = { "world", "events" } })
local cross = (ctx.path.from + ctx.path.to) / 2
local cs = main:at(ctx.path.dist)
view("preview-parade", cross - cs.flat * 95 + cs.right * -30 + V3.new(0, 16, 0), cross + V3.new(0, 10, 0) + cs.right * 25, 60, { groups = { "world", "events", "karts" } })
-- the lobby
local lc = data.lobby.centre
view("preview-lobby", lc + V3.new(80, 50, -60), lc + V3.new(0, 6, 40), 62)
view("preview-karts-closeup", V3.new(3000, 9, -22), V3.new(3000, 1.5, 0), 48, { groups = { "sheet" }, bright = true })

fs.writeFile(outPath, serde.encode("json", out))
print(string.format("exported %d world parts, %d kart parts, %d event parts, %d lights, %d views", #out.world, #out.karts, #out.events, #out.lights, #out.views))
