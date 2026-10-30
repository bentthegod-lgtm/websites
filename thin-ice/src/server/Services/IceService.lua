--[[
	IceService - the ice reacts to weight. Every frame each tile under a player gains
	stress from how they move (sprinting is heavy, sneaking is light, carrying a core adds
	more); empty tiles slowly recover. Halfway to breaking a tile CRACKS (a visible web of
	cracks and a loud crack the Antlered can hear); at full strength it BREAKS into open
	water. Broken tiles refreeze as thin ice after a while.

	Solid tiles never break: the first two rows off the shore, braziers, snow drifts and
	the tiles the frozen cores sit on.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ThinIce")
local GameConfig = require(Shared.Config.GameConfig)
local IceMath = require(Shared.IceMath)
local LakeGen = require(Shared.LakeGen)

local IceService = {}

local services
local run
local LakeBuilder
local stressed = {} -- tile -> true while it has stress
local broken = {} -- tile -> true while it is broken water that will refreeze
local rng = Random.new()

function IceService.init(registry)
	services = registry
	LakeBuilder = require(script.Parent.Parent.World.LakeBuilder)
end

local function solid(tile)
	return tile.r <= 1 or tile.type == "brazier" or tile.drift == true or tile.core == true
end
IceService.solid = solid

function IceService.startRun(newRun)
	run = newRun
	stressed = {}
	broken = {}
	for _, core in ipairs(run.layout.cores) do
		run.layout.tiles[LakeGen.key(core.c, core.r)].core = true
	end
end

function IceService.stopRun()
	run = nil
	stressed = {}
	broken = {}
end

function IceService.tileAt(position)
	if not run then
		return nil
	end
	local c, r = LakeGen.worldToCell(position.X, position.Z)
	return c and run.layout.tiles[LakeGen.key(c, r)]
end

local function breakTile(tile, now)
	tile.type = "water"
	tile.stress = 0
	tile.cracked = false
	tile.brokenAt = now
	broken[tile] = true
	stressed[tile] = nil
	LakeBuilder.applyTile(tile)
	local x, z = LakeGen.cellToWorld(tile.c, tile.r)
	services.Remotes.WorldSound:FireAllClients("Break", Vector3.new(x, GameConfig.Lake.IceTop, z))
end

-- Breaks a tile right now (tests and debugging).
function IceService.forceBreak(tile)
	breakTile(tile, os.clock())
end

function IceService.step(dt)
	if not run then
		return
	end
	local now = os.clock()
	-- 1. Load from everyone standing on the ice.
	local loads = {}
	for _, rec in pairs(services.SurvivalService.records()) do
		if rec.state == "Active" and not rec.inWater then
			local character = rec.player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local tile = IceService.tileAt(root.Position)
				if tile and LakeGen.walkable(tile) and not solid(tile) then
					loads[tile] = (loads[tile] or 0) + IceMath.stressRate(rec.effective, rec.moving, rec.carrying ~= nil)
					stressed[tile] = true
				end
			end
		end
	end
	-- 2. Advance stress on every tile that has any.
	for tile in pairs(stressed) do
		local before = tile.stress or 0
		local stress, event = IceMath.stepStress(before, tile.thick, loads[tile] or 0, dt, tile.cracked)
		tile.stress = stress
		if event == "break" then
			breakTile(tile, now)
		else
			if event == "crack" then
				tile.cracked = true
				LakeBuilder.addCracks(tile, rng)
				local x, z = LakeGen.cellToWorld(tile.c, tile.r)
				services.NoiseService.emit("Crack", Vector3.new(x, GameConfig.Lake.IceTop, z), nil)
			end
			local damage = IceMath.damage(stress, tile.thick)
			if math.abs(damage - (tile.shownDamage or 0)) > 0.08 or (stress <= 0 and (tile.shownDamage or 0) > 0) then
				tile.shownDamage = damage
				LakeBuilder.applyTile(tile, damage)
			end
			if stress <= 0 then
				stressed[tile] = nil
				if tile.cracked then
					tile.cracked = false
					LakeBuilder.removeCracks(tile)
				end
			end
		end
	end
	-- 3. Refreeze old breaks (as thin ice) once nobody is splashing about in them.
	for tile in pairs(broken) do
		if now - tile.brokenAt >= GameConfig.Ice.RefreezeAfter then
			local occupied = false
			for _, rec in pairs(services.SurvivalService.records()) do
				local root = rec.player.Character and rec.player.Character:FindFirstChild("HumanoidRootPart")
				if rec.inWater and root and IceService.tileAt(root.Position) == tile then
					occupied = true
				end
			end
			if not occupied then
				broken[tile] = nil
				tile.type = "ice"
				tile.thick = 1
				tile.stress = 0
				tile.brokenAt = nil
				tile.shownDamage = 0
				LakeBuilder.applyTile(tile, 0)
			end
		end
	end
end

return IceService
