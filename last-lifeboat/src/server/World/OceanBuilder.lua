--[[
	OceanBuilder - fills the static Terrain sea (sea level Y = 0) a block per frame.

	A wide shallow harbour (OceanDepth deep with a sand floor) and a deep trench under the
	ship's berth, deep enough for the bow of the biggest ship at its final plunge. The water
	never moves: the ship sinks into it, and swimming is Roblox's own terrain swimming.
	FillBlock on the whole sea at once could stall the server, so it is split into
	OceanChunk-sized blocks and RoundService steps the job once per Heartbeat at startup.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("LastLifeboat")
local GameConfig = require(Shared.Config.GameConfig)

local OceanBuilder = {}
OceanBuilder.__index = OceanBuilder

local W = GameConfig.World

function OceanBuilder.blocks()
	local list = {}
	local half, chunk = W.OceanHalf, W.OceanChunk
	local depth = W.OceanDepth
	for x = -half, half - chunk, chunk do
		for z = -half, half - chunk, chunk do
			local cx, cz = x + chunk / 2, z + chunk / 2
			table.insert(list, { kind = "Sand", cf = CFrame.new(cx, -depth - 4, cz), size = Vector3.new(chunk, 8, chunk) })
			table.insert(list, { kind = "Water", cf = CFrame.new(cx, -depth / 2, cz), size = Vector3.new(chunk, depth, chunk) })
		end
	end
	-- the trench under the berth (covers the biggest ship plus a margin)
	local maxLen, maxBeam = 0, 0
	for _, def in pairs(GameConfig.Ships) do
		maxLen = math.max(maxLen, def.Length)
		maxBeam = math.max(maxBeam, def.Beam)
	end
	local tx = maxBeam / 2 + W.TrenchMargin
	local tz = maxLen / 2 + W.TrenchMargin
	local top, bottom = -depth, -W.TrenchDepth
	for z = -tz, tz - 1, chunk do
		local z1 = math.min(tz, z + chunk)
		local cz, len = (z + z1) / 2, z1 - z
		table.insert(list, { kind = "Water", cf = CFrame.new(W.ShipX, (top + bottom) / 2, cz), size = Vector3.new(tx * 2, top - bottom, len) })
		table.insert(list, { kind = "Rock", cf = CFrame.new(W.ShipX, bottom - 4, cz), size = Vector3.new(tx * 2 + 16, 8, len) })
	end
	return list
end

function OceanBuilder.new(terrain)
	return setmetatable({ terrain = terrain, list = OceanBuilder.blocks(), index = 1, done = false }, OceanBuilder)
end

-- Fills `count` blocks; returns true when the sea is complete.
function OceanBuilder:step(count)
	for _ = 1, count or 1 do
		local block = self.list[self.index]
		if not block then
			break
		end
		if self.terrain then
			local material = Enum.Material[block.kind]
			pcall(function()
				self.terrain:FillBlock(block.cf, block.size, material)
			end)
		end
		self.index += 1
	end
	self.done = self.index > #self.list
	return self.done
end

return OceanBuilder
