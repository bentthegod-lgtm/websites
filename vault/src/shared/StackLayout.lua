--[[
	StackLayout - where every piece of a carried loot stack sits, relative to the character's
	HumanoidRootPart (x right, y up, -z forward). Pure and deterministic: the same inventory
	always gives the same layout, so the stack never reshuffles or flickers as it grows.

	The arrangement changes at item-count thresholds, so capacity upgrades are visible:
	  Hand    1-3    a few bills / bars fanned in the right hand
	  Bundle  4-12   a small bundle held at the chest (2 per layer)
	  Stack   13-36  a tall stack carried in front (2 x 2 per layer, 1 piece = 2 items)
	  Tower   37-90  a large organised stack (3 x 2 per layer, 1 piece = 4 items)
	  Crate   91+    a strapped vault crate carried overhead with loot on top
	Gold, platinum and legendary bars interlock: alternate layers turn 90 degrees.
	Gems ride in compact trays (one piece each). The number of pieces is capped (budget);
	anything beyond the budget is reported as `hidden` and the crate / counter shows it.
]]

local LootConfig = require(script.Parent.Config.LootConfig)

local StackLayout = {}

StackLayout.Modes = {
	{ Name = "Hand", Max = 3, Per = 1 },
	{ Name = "Bundle", Max = 12, Per = 1 },
	{ Name = "Stack", Max = 36, Per = 2 },
	{ Name = "Tower", Max = 90, Per = 4 },
	{ Name = "Crate", Max = math.huge, Per = 0 }, -- Per is worked out from the budget
}

StackLayout.PieceSize = { X = 1.1, Y = 0.46, Z = 0.74 }
StackLayout.CrateSize = { X = 4.2, Y = 2.4, Z = 3.2 }
StackLayout.CrateY = 4.1 -- crate centre above the root
local INTERLOCK = { Gold = true, Platinum = true }

function StackLayout.modeFor(count)
	for _, mode in ipairs(StackLayout.Modes) do
		if count <= mode.Max then
			return mode
		end
	end
	return StackLayout.Modes[#StackLayout.Modes]
end

-- Ordered list of categories with counts (heavy metals at the bottom, gems on top).
local ORDER = { "Platinum", "Gold", "Legendary", "Artifact", "Cash", "Emerald", "Diamond" }

local function grids(modeName)
	local P = StackLayout.PieceSize
	if modeName == "Bundle" then
		return { cols = { -0.58, 0.58 }, rows = { -1.35 }, baseY = -0.35 }
	elseif modeName == "Stack" then
		return { cols = { -0.58, 0.58 }, rows = { -1.2, -1.2 - (P.Z + 0.06) }, baseY = -0.4 }
	elseif modeName == "Tower" then
		return { cols = { -1.16, 0, 1.16 }, rows = { -1.3, -1.3 - (P.Z + 0.06) }, baseY = -0.45 }
	else -- Crate top
		return { cols = { -1.2, 0, 1.2 }, rows = { -0.5, 0.45 }, baseY = StackLayout.CrateY + StackLayout.CrateSize.Y / 2 + P.Y / 2 }
	end
end

--[[
	counts: { [category] = items carried }  budget: max visible pieces (PerformanceConfig).
	Returns { mode = name, count = n, per = items per piece, pieces = { {category, x, y, z,
	yaw, layer} }, hidden = items not represented, crate = bool, top = height of the top }.
]]
function StackLayout.layout(counts, budget)
	budget = budget or 24
	local total = 0
	for _, category in ipairs(LootConfig.CategoryOrder) do
		total += math.max(0, math.floor(counts[category] or 0))
	end
	local mode = StackLayout.modeFor(total)
	local result = { mode = mode.Name, count = total, pieces = {}, hidden = 0, crate = mode.Name == "Crate", top = 0 }
	if total == 0 then
		return result
	end
	local per = mode.Per
	local maxPieces = budget
	if mode.Name == "Crate" then
		maxPieces = math.min(budget, 12)
		per = math.max(1, math.ceil(total / maxPieces))
	elseif mode.Name == "Hand" then
		maxPieces = 3
	end
	result.per = per
	-- Expand categories into pieces.
	local sequence = {}
	for _, category in ipairs(ORDER) do
		local n = math.max(0, math.floor(counts[category] or 0))
		local pieces = math.ceil(n / per)
		for _ = 1, pieces do
			if #sequence < maxPieces then
				table.insert(sequence, category)
			end
		end
	end
	local shown = math.min(total, #sequence * per)
	result.hidden = math.max(0, total - shown)

	if mode.Name == "Hand" then
		for i, category in ipairs(sequence) do
			table.insert(result.pieces, { category = category, x = 1.22, y = -0.2 + 0.1 * (i - 1), z = -0.62, yaw = 0.35 * (i - 1), layer = i - 1, scale = 0.62 })
		end
		result.top = 0.2
		return result
	end

	local grid = grids(mode.Name)
	local perLayer = #grid.cols * #grid.rows
	local P = StackLayout.PieceSize
	local layerCount = math.ceil(#sequence / perLayer)
	for layer = 0, layerCount - 1 do
		local first = layer * perLayer + 1
		local last = math.min(#sequence, first + perLayer - 1)
		-- A layer interlocks (turns 90 degrees) only if every piece in it is a bar.
		local interlock = layer % 2 == 1
		for i = first, last do
			if not INTERLOCK[sequence[i]] then
				interlock = false
			end
		end
		local centreZ = 0
		for _, z in ipairs(grid.rows) do
			centreZ += z
		end
		centreZ /= #grid.rows
		for i = first, last do
			local slot = i - first
			local col = slot % #grid.cols + 1
			local row = slot // #grid.cols + 1
			local x, z = grid.cols[col], grid.rows[row]
			local yaw = 0
			if interlock then
				-- Course turned 90 degrees: bars run front-to-back, packed closer side to side
				-- and spaced wider front to back, so they never overlap (brick-wall bond).
				x = (col - (#grid.cols + 1) / 2) * (P.Z + 0.06)
				z = centreZ + (row - (#grid.rows + 1) / 2) * (P.X + 0.06)
				yaw = math.pi / 2
			end
			table.insert(result.pieces, { category = sequence[i], x = x, y = grid.baseY + layer * (P.Y + 0.02), z = z, yaw = yaw, layer = layer, scale = 1 })
		end
	end
	result.top = grid.baseY + layerCount * (P.Y + 0.02)
	return result
end

return StackLayout
