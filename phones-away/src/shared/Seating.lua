--[[
	Seating - assigns desks for a class (pure).

	* VIP players get the gold VIP desks in the back row first (then other back-row desks).
	* Friends sit together ("party seating"): friend groups are placed in neighbouring desks
	  of the same row when there is room, otherwise in the closest free desks.
	* Everyone else fills the remaining desks in a shuffled order.

	students = { { id, vip = bool, friends = { [id] = true } } }
	desks    = { { index, row, col, vip = bool } }   (row 1 = front)
	Returns { [id] = deskIndex }
]]

local Seating = {}

local function groups(students)
	local byId = {}
	for _, s in ipairs(students) do
		byId[s.id] = s
	end
	local seen, out = {}, {}
	for _, s in ipairs(students) do
		if not seen[s.id] then
			local group, stack = {}, { s }
			seen[s.id] = true
			while #stack > 0 do
				local cur = table.remove(stack)
				table.insert(group, cur)
				for otherId in pairs(cur.friends or {}) do
					local other = byId[otherId]
					if other and not seen[otherId] then
						seen[otherId] = true
						table.insert(stack, other)
					end
				end
			end
			table.sort(group, function(a, b)
				return tostring(a.id) < tostring(b.id)
			end)
			table.insert(out, group)
		end
	end
	return out
end
Seating.groups = groups

function Seating.assign(students, desks, rng)
	local result = {}
	local free = {}
	for _, d in ipairs(desks) do
		free[d.index] = d
	end
	local maxRow = 0
	for _, d in ipairs(desks) do
		maxRow = math.max(maxRow, d.row)
	end
	local function take(id, desk)
		result[id] = desk.index
		free[desk.index] = nil
	end
	local function freeSorted(filter)
		local list = {}
		for _, d in pairs(free) do
			if not filter or filter(d) then
				table.insert(list, d)
			end
		end
		table.sort(list, function(a, b)
			if a.row ~= b.row then
				return a.row > b.row
			end
			return a.col < b.col
		end)
		return list
	end

	-- 1) VIPs: VIP desks, then the back row.
	for _, s in ipairs(students) do
		if s.vip then
			local options = freeSorted(function(d)
				return d.vip
			end)
			if #options == 0 then
				options = freeSorted(function(d)
					return d.row == maxRow
				end)
			end
			if options[1] then
				take(s.id, options[1])
			end
		end
	end

	-- 2) Friend groups (largest first) next to each other, ideally next to a seated VIP friend.
	local list = groups(students)
	table.sort(list, function(a, b)
		if #a ~= #b then
			return #a > #b
		end
		return tostring(a[1].id) < tostring(b[1].id)
	end)
	local function nearestFree(row, col)
		local best, bestScore
		for _, d in pairs(free) do
			local score = math.abs(d.row - row) * 10 + math.abs(d.col - col)
			if not best or score < bestScore or (score == bestScore and d.index < best.index) then
				best, bestScore = d, score
			end
		end
		return best
	end
	local deskByIndex = {}
	for _, d in ipairs(desks) do
		deskByIndex[d.index] = d
	end
	for _, group in ipairs(list) do
		if #group > 1 then
			-- Anchor: an already seated member, or the free run of desks that fits best.
			local anchor
			for _, s in ipairs(group) do
				if result[s.id] then
					anchor = deskByIndex[result[s.id]]
					break
				end
			end
			if not anchor then
				local unseated = 0
				for _, s in ipairs(group) do
					if not result[s.id] then
						unseated += 1
					end
				end
				-- Find a row with a run of `unseated` adjacent free desks.
				for row = maxRow, 1, -1 do
					local cols = {}
					for _, d in pairs(free) do
						if d.row == row then
							cols[d.col] = d
						end
					end
					for col = 1, 8 do
						local run = 0
						for c = col, col + unseated - 1 do
							if cols[c] then
								run += 1
							end
						end
						if run == unseated and not anchor then
							anchor = cols[col]
						end
					end
					if anchor then
						break
					end
				end
				anchor = anchor or freeSorted()[1]
			end
			if anchor then
				for _, s in ipairs(group) do
					if not result[s.id] then
						local d = nearestFree(anchor.row, anchor.col)
						if d then
							take(s.id, d)
						end
					end
				end
			end
		end
	end

	-- 3) Everyone else, shuffled.
	local rest = {}
	for _, s in ipairs(students) do
		if not result[s.id] then
			table.insert(rest, s)
		end
	end
	for i = #rest, 2, -1 do
		local j = rng:integer(1, i)
		rest[i], rest[j] = rest[j], rest[i]
	end
	local remaining = freeSorted()
	for i = #remaining, 2, -1 do
		local j = rng:integer(1, i)
		remaining[i], remaining[j] = remaining[j], remaining[i]
	end
	for i, s in ipairs(rest) do
		local d = remaining[i]
		if d then
			take(s.id, d)
		end
	end
	return result
end

-- True when two desks are side by side (same row, neighbouring columns).
function Seating.adjacent(a, b)
	return a.row == b.row and math.abs(a.col - b.col) == 1
end

return Seating
