--[[
	VaultBuilder - builds the whole underground vault: seven depths, each a DEEP POOL OF
	TREASURE, stacked 90 studs apart around a shared elevator shaft and joined physically
	by tunnels behind each pool's vault door (see Pools.lua for one depth's layout).

	Per depth: the shell (rim decks round the pool, outer walls, ceiling, the arrival
	hall's plates, lights, access doors and cameras), the arrival area (elevator cabin,
	deposit machine(s), upgrade terminal, signage), then Pools.build (basin, treasure
	surface and decoration, rims, monument, chute deposit, vault door, tunnel, preview
	room, spawn points, safe zones), then the preview room dressing (Themes.build).

	Loot spawn points are kept only if Reach finds them reachable on foot from the arrival
	deck and within pickup range. Returns a world record (see the bottom) used by every
	service.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Vault")
local GameConfig = require(Shared.Config.GameConfig)
local DepthConfig = require(Shared.Config.DepthConfig)
local LootTable = require(Shared.LootTable)
local Props = require(script.Parent.Props)
local Machines = require(script.Parent.Machines)
local Themes = require(script.Parent.Themes)
local Pools = require(script.Parent.Pools)
local Reach = require(script.Parent.Reach)

local VaultBuilder = {}

local M = Enum.Material
local C = Props.Colors
local Z = Vector3.zAxis

local W2 = GameConfig.RoomWidth / 2 -- 70
local FRONT = GameConfig.RoomFront -- -72
local BACK = GameConfig.RoomBack -- 60
local POOL = Pools.Pool

local function facing(pos, dir)
	return CFrame.lookAt(pos, pos + dir)
end

-- Keep-out boxes in the XZ plane (relative to the depth origin): {x0, x1, z0, z1}.
local function inBox(box, x, z, pad)
	pad = pad or 0
	return x >= box[1] - pad and x <= box[2] + pad and z >= box[3] - pad and z <= box[4] + pad
end
VaultBuilder.inBox = inBox

-- The envelope every depth shares: rim decks round the pool, outer walls (elevator opening
-- at the front; on B2+ the arrival tunnel's opening at the back), ceiling, the arrival
-- hall's plates, lights, access doors and cameras.
local function shell(ctx)
	local b, y0, pal = ctx.b, ctx.y0, ctx.palette
	local wall, floor, trim, accent, light = Props.rgb(pal.Wall), Props.rgb(pal.Floor), Props.rgb(pal.Trim), Props.rgb(pal.Accent), Props.rgb(pal.Light)
	local style = ctx.style
	local H = ctx.H
	local function deck(name, x0, x1, z0, z1)
		return b.part({ Name = name, Size = Vector3.new(x1 - x0, 2, z1 - z0), CFrame = CFrame.new((x0 + x1) / 2, y0 - 1, (z0 + z1) / 2), Color = floor, Material = style.FloorMaterial, Reflectance = style.FloorReflect or 0 })
	end
	deck("FrontDeck", -W2, W2, FRONT, POOL.z0)
	deck("SideRim", -W2, POOL.x0, POOL.z0, BACK + 2)
	deck("SideRim", POOL.x1, W2, POOL.z0, BACK + 2)
	deck("BackRim", POOL.x0, POOL.x1, POOL.z1, BACK + 2)
	b.deco({ Name = "HallPlates", Size = Vector3.new(GameConfig.RoomWidth, 0.06, POOL.z0 - FRONT), CFrame = CFrame.new(0, y0 + 0.03, (FRONT + POOL.z0) / 2), Color = trim, Material = M.DiamondPlate })
	b.deco({ Name = "PoolEdge", Size = Vector3.new(POOL.x1 - POOL.x0, 0.1, 1), CFrame = CFrame.new(0, y0 + 0.05, POOL.z0 - 0.5), Color = C.Hazard, Material = M.SmoothPlastic, CastShadow = false })
	local function wallPart(name, size, pos)
		return b.part({ Name = name, Size = size, CFrame = CFrame.new(pos), Color = wall, Material = style.WallMaterial })
	end
	local zMid, zLen = (FRONT + BACK + 4) / 2, BACK + 4 - FRONT
	wallPart("WallLeft", Vector3.new(2, H + 2, zLen), Vector3.new(-W2 - 1, y0 - 2 + (H + 2) / 2, zMid))
	wallPart("WallRight", Vector3.new(2, H + 2, zLen), Vector3.new(W2 + 1, y0 - 2 + (H + 2) / 2, zMid))
	-- Front wall: elevator opening x -7..7, height 11.
	wallPart("WallFrontL", Vector3.new(W2 - 7, H, 2), Vector3.new(-(W2 + 7) / 2, y0 + H / 2, FRONT - 1))
	wallPart("WallFrontR", Vector3.new(W2 - 7, H, 2), Vector3.new((W2 + 7) / 2, y0 + H / 2, FRONT - 1))
	wallPart("WallFrontTop", Vector3.new(14, H - 11, 2), Vector3.new(0, y0 + 11 + (H - 11) / 2, FRONT - 1))
	-- Back wall (z 62..64); B2+ have the opening where the tunnel from above arrives.
	local bz = BACK + 3
	local ax = Pools.Tunnel.arrivalX
	if ctx.def.Depth >= 2 then
		wallPart("WallBack", Vector3.new(ax - 5 + W2, H, 2), Vector3.new((-W2 + ax - 5) / 2, y0 + H / 2, bz))
		wallPart("WallBack", Vector3.new(W2 - (ax + 5), H, 2), Vector3.new((ax + 5 + W2) / 2, y0 + H / 2, bz))
		wallPart("WallBackTop", Vector3.new(10, H - 14, 2), Vector3.new(ax, y0 + 14 + (H - 14) / 2, bz))
		local prev = DepthConfig.get(ctx.def.Depth - 1)
		Props.sign(b, facing(Vector3.new(ax, y0 + 15.5, bz - 1.1), -Z), 10, 1.2, "FROM " .. prev.Code .. "  " .. string.upper(prev.Name), { Color = accent, PPS = 30 })
	else
		wallPart("WallBack", Vector3.new(GameConfig.RoomWidth, H, 2), Vector3.new(0, y0 + H / 2, bz))
	end
	b.part({ Name = "Ceiling", Size = Vector3.new(GameConfig.RoomWidth + 4, 2, zLen + 2), CFrame = CFrame.new(0, y0 + H + 1, zMid), Color = trim, Material = M.Concrete })
	-- Wainscot band and accent stripe on the long walls (the facility's common trim).
	for _, x in ipairs({ -W2 + 0.15, W2 - 0.15 }) do
		b.deco({ Name = "Wainscot", Size = Vector3.new(0.3, 3, zLen), CFrame = CFrame.new(x, y0 + 1.5, zMid), Color = trim, Material = M.Metal })
		b.deco({ Name = "WallStripe", Size = Vector3.new(0.32, 0.5, zLen), CFrame = CFrame.new(x, y0 + 3.2, zMid), Color = accent, Material = M.Metal })
	end
	-- Hall lights, side access doors and cameras.
	for _, x in ipairs({ -30, 30 }) do
		local _, l = Props.lightFixture(b, CFrame.new(x, y0 + math.min(H, 30) - 1.8, -56), light, (style.LightBrightness or 2.2) * 0.9, 40, 8)
		l.Shadows = false
	end
	Props.accessDoor(b, facing(Vector3.new(-W2, y0, -54), Vector3.xAxis), "MAINTENANCE")
	Props.accessDoor(b, facing(Vector3.new(W2, y0, -54), -Vector3.xAxis), "SECURITY")
	Props.camera(b, facing(Vector3.new(-W2 + 0.4, y0 + 20, FRONT + 4), Vector3.new(1, 0, 1).Unit))
	Props.camera(b, facing(Vector3.new(W2 - 0.4, y0 + 20, FRONT + 4), Vector3.new(-1, 0, 1).Unit))
end

local function arrival(ctx)
	local b, y0, pal, def = ctx.b, ctx.y0, ctx.palette, ctx.def
	local accent = Props.rgb(pal.Accent)
	local side = ctx.depositSide -- -1: deposits left / terminal right; 1: mirrored
	-- Elevator cabin in the front wall.
	local cabinCF = facing(Vector3.new(0, y0, FRONT - 6.5), Z)
	ctx.elevator = Machines.elevator(b, cabinCF, def.Code, accent)
	-- Elevator surround: frame, depth display, call panel, hazard sill.
	b.deco({ Name = "ElevatorFrameTop", Size = Vector3.new(17, 1.4, 1), CFrame = CFrame.new(0, y0 + 11.7, FRONT + 0.4), Color = C.SteelDark, Material = M.Metal })
	for _, x in ipairs({ -8, 8 }) do
		b.deco({ Name = "ElevatorFrameSide", Size = Vector3.new(1.2, 11, 1), CFrame = CFrame.new(x, y0 + 5.5, FRONT + 0.4), Color = C.SteelDark, Material = M.Metal })
	end
	local display = b.deco({ Name = "DepthDisplay", Size = Vector3.new(5, 1.6, 0.3), CFrame = facing(Vector3.new(0, y0 + 13.4, FRONT + 0.2), Z), Color = C.Black, Material = M.SmoothPlastic })
	ctx.elevator.display = Props.text(display, Enum.NormalId.Front, def.Code, { Color = Color3.fromRGB(255, 170, 60), PPS = 40, Brightness = 2, LightInfluence = 0 })
	Props.accessPanel(b, facing(Vector3.new(9.6, y0 + 4.4, FRONT + 0.2), Z), true)
	Props.hazardStripes(b, CFrame.new(0, y0, FRONT + 1.4), 14, 1.2)
	Props.sign(b, facing(Vector3.new(0, y0 + 17, FRONT + 0.2), Z), 30, 3.4, def.Code .. "  |  " .. string.upper(def.Name), { Color = accent, PPS = 30 })
	Props.sign(b, facing(Vector3.new(0, y0 + 14.9, FRONT + 0.2), Z), 10, 0.9, "ELEVATOR - ALL DEPTHS", { PPS = 40, Trim = false })
	Props.floorText(b, CFrame.new(0, y0, -60) * CFrame.Angles(0, math.pi, 0), 9, 7, def.Code, accent)
	-- Deposit machine(s) (two in the starting area so a crowd doesn't queue).
	ctx.deposits = {}
	local xs = if def.Depth == 1 then { -28, -50 } else { 30 * side }
	for i, x in ipairs(xs) do
		local id = string.format("D%d_%d", def.Depth, i)
		table.insert(ctx.deposits, Machines.deposit(b, facing(Vector3.new(x, y0, -60), Z), id, accent))
		table.insert(ctx.keepOut, { x - 6, x + 6, -64, -42 })
	end
	-- Upgrade terminal on the other side.
	local tx = -30 * side
	ctx.terminal = Machines.terminal(b, facing(Vector3.new(tx, y0, -58), Z), accent, def.Depth == 1)
	table.insert(ctx.keepOut, { tx - 6, tx + 6, -62, -50 })
	-- Hanging direction signs.
	local dx = if def.Depth == 1 then -28 else 30 * side
	Props.sign(b, facing(Vector3.new(dx, y0 + 14, -46), -Z), 12, 1.6, if side < 0 then "<<  DEPOSIT" else "DEPOSIT  >>", { Color = Color3.fromRGB(120, 255, 170), PPS = 30 })
	Props.sign(b, facing(Vector3.new(tx, y0 + 14, -46), -Z), 12, 1.6, if side < 0 then "UPGRADES  >>" else "<<  UPGRADES", { Color = accent, PPS = 30 })
	local hang = math.min(ctx.H, 30) - 15
	for _, x in ipairs({ dx, tx }) do
		for _, o in ipairs({ -5, 5 }) do
			b.deco({ Name = "SignCable", Size = Vector3.new(0.08, hang, 0.08), CFrame = CFrame.new(x + o, y0 + 14.8 + hang / 2, -46), Color = C.Black, CastShadow = false })
		end
	end
end

function VaultBuilder.build()
	local existing = Workspace:FindFirstChild("Vault")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Vault"
	folder.Parent = Workspace
	local lootFolder = Instance.new("Folder")
	lootFolder.Name = "Loot"
	lootFolder.Parent = folder

	local world = { folder = folder, lootFolder = lootFolder, depths = {}, machines = {}, partCount = 0 }
	local shaftDepths = {}
	for _, def in ipairs(DepthConfig.List) do
		local y0 = -(def.Depth - 1) * GameConfig.DepthSpacing
		local depthFolder = Instance.new("Folder")
		depthFolder.Name = def.Code
		depthFolder.Parent = folder
		local b = Props.builder(depthFolder)
		local layout = { H = Pools.ceiling(def.Depth), depositSide = if def.Depth % 2 == 0 then 1 else -1 }
		local ctx = {
			b = b,
			folder = depthFolder,
			y0 = y0,
			def = def,
			palette = def.Palette,
			style = Themes.style(def.Depth),
			H = layout.H,
			depositSide = layout.depositSide,
			keepOut = {},
			extraPoints = {},
			safeZones = {},
		}
		shell(ctx)
		arrival(ctx)
		Pools.build(ctx) -- the pool, its treasure, rims, monument, door, tunnel, spawn points
		Themes.build(ctx) -- the preview room's display of the next depth's loot
		-- Keep only spawn points a player can actually walk to and pick up (Reach).
		local reach = Reach.index(depthFolder)
		local walk = Reach.walk(reach, VaultBuilder.walkBounds(y0), VaultBuilder.walkStart(y0))
		local kept, dropped = {}, 0
		for _, extra in ipairs(ctx.extraPoints) do
			local ok = if extra.kind == "Fill" then Reach.surfaceOk(reach, walk, extra.cframe.Position) else Reach.pointOk(reach, walk, extra.cframe.Position)
			if ok then
				table.insert(kept, { cframe = extra.cframe, size = extra.size, kind = extra.kind, bonus = extra.bonus, index = #kept + 1 })
			else
				dropped += 1
			end
		end
		ctx.points = kept
		local record = {
			depth = def.Depth,
			def = def,
			y0 = y0,
			folder = depthFolder,
			points = ctx.points,
			keepOut = ctx.keepOut,
			deposits = ctx.deposits,
			terminal = ctx.terminal,
			elevator = ctx.elevator,
			exitDoor = ctx.exitDoor,
			preview = ctx.preview,
			landmark = ctx.landmark,
			rarePoint = ctx.rarePoint,
			ambience = ctx.ambience,
			parts = b.count,
			droppedPoints = dropped,
			exitDoorPosition = ctx.exitDoorPosition,
			tunnelEnd = ctx.tunnelEnd,
			standin = ctx.standin,
			safeZones = ctx.safeZones,
			layout = layout,
		}
		-- Loot staged in the preview chamber: the next floor's items, decorative only.
		record.previewItems = ctx.preview.nextDepth
		world.depths[def.Depth] = record
		for _, machine in ipairs(ctx.deposits) do
			world.machines[machine.id] = machine
			machine.depth = def.Depth
		end
		world.partCount += b.count
		table.insert(shaftDepths, { y = y0, code = def.Code })
	end
	-- One shaft through every floor.
	local shaftFolder = Instance.new("Folder")
	shaftFolder.Name = "Shaft"
	shaftFolder.Parent = folder
	local sb = Props.builder(shaftFolder)
	Machines.shaft(sb, GameConfig.CeilingHeight + 2, -(DepthConfig.Count - 1) * GameConfig.DepthSpacing - 2, FRONT - 13.5, shaftDepths)
	world.partCount += sb.count
	-- Starting area extras: four leaderboards on the hall walls and the how-to board.
	local d1 = world.depths[1]
	local b1 = Props.builder(d1.folder)
	world.boards = {}
	for i, lb in ipairs(GameConfig.Leaderboards) do
		local x = if i <= 2 then -W2 + 1.7 else W2 - 1.7 -- in front of the pilasters
		local z = if i % 2 == 1 then -44 else -64.5
		local dir = if i <= 2 then Vector3.xAxis else -Vector3.xAxis
		world.boards[lb.Key] = Machines.leaderboard(b1, facing(Vector3.new(x, 9, z), dir), lb.Title)
	end
	Props.sign(b1, facing(Vector3.new(-14, 7.5, FRONT + 0.2), Z), 9, 4.2, "1  COLLECT\n2  DEPOSIT\n3  UPGRADE\n4  GO DEEPER", { Color = Color3.fromRGB(255, 226, 150), PPS = 30, Name = "HowToBoard" })
	world.spawn = Instance.new("SpawnLocation")
	world.spawn.Name = "VaultSpawn"
	world.spawn.Anchored = true
	world.spawn.Size = Vector3.new(8, 0.2, 6)
	world.spawn.CFrame = CFrame.new(0, 0.1, -64)
	world.spawn.Transparency = 1
	world.spawn.CanCollide = false
	world.spawn.Neutral = true
	world.spawn.Duration = 0
	world.spawn.Parent = folder
	world.partCount += b1.count
	return world
end

-- Bounds for the walk graph of a depth: the rims, the pool, the tunnel down to the next
-- depth's rim (90 lower) and the landing / preview room behind.
function VaultBuilder.walkBounds(y0)
	return { -W2, W2, FRONT, 164, y0 - GameConfig.DepthSpacing - 4, y0 + 6 }
end

-- Where the walk graph starts: on the arrival deck in front of the elevator.
function VaultBuilder.walkStart(y0)
	return Vector3.new(0, y0, FRONT + 8)
end

-- Which depth a world position is on (by height band).
function VaultBuilder.depthAt(position)
	return DepthConfig.depthAtY(position.Y, GameConfig.DepthSpacing)
end

-- Sanity check used by the harness: every spawn point is in its pool, on its depth's
-- treasure surface (between the rim and the deep end).
function VaultBuilder.validatePoint(record, point)
	local pos = point.cframe.Position
	if pos.X < POOL.x0 or pos.X > POOL.x1 or pos.Z < POOL.z0 or pos.Z > POOL.z1 then
		return false, "outside the pool"
	end
	if pos.Y < record.y0 - POOL.depth - 0.01 or pos.Y > record.y0 + 0.5 then
		return false, "not on this depth's treasure"
	end
	local h = Pools.surface(pos.Z)
	if math.abs(pos.Y - (record.y0 + h)) > 0.6 then
		return false, "not on the treasure surface"
	end
	if not LootTable.SizeRank[point.size] then
		return false, "bad size"
	end
	return true
end

-- Is a world position inside any depth's safe volume (rims, pool, tunnels)?
function VaultBuilder.isSafe(world, position, margin)
	margin = margin or 0
	for _, record in ipairs(world.depths) do
		for _, zone in ipairs(record.safeZones) do
			local lo, hi = zone[1], zone[2]
			if position.X >= lo.X - margin and position.X <= hi.X + margin and position.Y >= lo.Y - margin and position.Y <= hi.Y + margin + 6 and position.Z >= lo.Z - margin and position.Z <= hi.Z + margin then
				return true
			end
		end
	end
	return false
end

return VaultBuilder
