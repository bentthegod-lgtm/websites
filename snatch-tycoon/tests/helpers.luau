-- Shared helpers for the spec files.
local H = {}

function H.suite(prefix)
	local cases = {}
	local function test(name, fn)
		table.insert(cases, { name = prefix .. ": " .. name, fn = fn })
	end
	return cases, test
end

-- Deterministic [0,1) generator (LCG) so roll tests are reproducible.
function H.rng(seed)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

function H.eq(a, b, msg)
	assert(a == b, (msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

function H.near(a, b, eps, msg)
	assert(math.abs(a - b) <= (eps or 1e-9), (msg or "not close") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

return H
