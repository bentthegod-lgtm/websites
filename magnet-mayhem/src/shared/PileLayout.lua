--[[
	PileLayout - where each piece of a player's scrap pile sits, relative to the character's
	root (x right, y up, z backwards). Pure and deterministic: piece i always gets the same
	slot, so the pile never reshuffles or flickers as it grows.

	Shape: stacked rings that start at head height and rise like a scrap tornado, so the
	character's body stays readable and the camera (behind and above) keeps a clear view of
	what is in front. Rings rotate slowly in alternating directions.
]]

local PileLayout = {}

local RING_BASE = 7 -- pieces in the first ring
local RING_STEP = 2 -- each ring holds this many more
local HEIGHT0 = 2.9 -- first ring height above the root (about head height)
local RISE = 1.05 -- height between rings
local RADIUS0 = 2.7
local RADIUS_STEP = 0.32

-- Ring index and position inside that ring for slot i (1-based).
function PileLayout.ringOf(i)
	local ring, start = 0, 1
	while true do
		local count = RING_BASE + RING_STEP * ring
		if i < start + count then
			return ring, i - start, count
		end
		start += count
		ring += 1
	end
end

--[[
	Offset for slot i at time `t` (seconds, for the slow orbit). `size` is the piece's
	rough size: bigger pieces sit further out so they don't swallow the character.
	`compaction` (0.7..1) comes from the Pile Packing upgrade.
	Returns x, y, z, yaw.
]]
function PileLayout.slot(i, t, size, compaction)
	compaction = compaction or 1
	local ring, index, count = PileLayout.ringOf(i)
	local direction = if ring % 2 == 0 then 1 else -1
	local angle = (index / count) * math.pi * 2 + ring * 0.7 + direction * (t or 0) * (0.55 - math.min(0.3, ring * 0.03))
	local radius = (RADIUS0 + ring * RADIUS_STEP) * compaction + (size or 1) * 0.35
	-- A little stable per-slot jitter so it looks like a heap, not a ring of soldiers.
	local jitter = ((i * 7919) % 100) / 100 - 0.5
	local y = HEIGHT0 + ring * RISE * compaction + jitter * 0.35
	return math.cos(angle) * radius, y, math.sin(angle) * radius, angle + jitter
end

-- Height of the pile's top for n pieces (used to place the overflow cluster and labels).
function PileLayout.topHeight(n, compaction)
	if n <= 0 then
		return HEIGHT0
	end
	local ring = PileLayout.ringOf(n)
	return HEIGHT0 + (ring + 1) * RISE * (compaction or 1)
end

-- Size (studs) of the compressed "overflow" cluster that represents pieces beyond the
-- visual budget. Grows with the cube root of the hidden mass so it never gets absurd.
function PileLayout.clusterSize(hiddenMass)
	if hiddenMass <= 0 then
		return 0
	end
	return math.min(7, 0.9 + hiddenMass ^ (1 / 3) * 0.55)
end

return PileLayout
