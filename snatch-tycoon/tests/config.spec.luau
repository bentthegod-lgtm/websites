local H = require("./helpers")
local BlobbyConfig = require("../src/shared/Config/BlobbyConfig")
local RarityConfig = require("../src/shared/Config/RarityConfig")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local RewardConfig = require("../src/shared/Config/RewardConfig")
local AudioAssets = require("../src/shared/Config/AudioAssets")
local EventConfig = require("../src/shared/Config/EventConfig")
local cases, test = H.suite("Config")

local SHAPES = { Round = true, Tall = true, Flat = true, Spiky = true, Pear = true, Cube = true, Noodle = true, Dumpling = true }
local EYES = { Googly = true, Sleepy = true, Cyclops = true, Tiny = true, Angry = true, Shades = true, Stalks = true }
local HATS = { None = true, Top = true, Crown = true, Propeller = true, Wizard = true, Chef = true, Party = true, Halo = true, Viking = true, Beanie = true }
local ACCS = { Bowtie = true, Mustache = true, Tongue = true, Cape = true, Monocle = true, Antenna = true, Tail = true, Arms = true, Wings = true }
local BOBS = { Bounce = true, Wobble = true, Spin = true, Hop = true, Sway = true, Float = true }

test("20 unique species with valid looks, every rarity covered", function()
	H.eq(#BlobbyConfig.List, 20)
	local names, looks = {}, {}
	for _, s in ipairs(BlobbyConfig.List) do
		assert(not names[s.Name], "duplicate name " .. s.Name)
		names[s.Name] = true
		assert(RarityConfig.Tiers[s.Rarity], s.Id .. " bad rarity")
		assert(SHAPES[s.Shape] and EYES[s.Eyes] and HATS[s.Hat] and BOBS[s.Bob], s.Id .. " bad look field")
		for _, a in ipairs(s.Accessories) do
			assert(ACCS[a], s.Id .. " bad accessory " .. a)
		end
		local look = s.Shape .. s.Eyes .. s.Hat .. table.concat(s.Accessories) .. s.Bob
		assert(not looks[look], s.Id .. " looks identical to another species")
		looks[look] = true
		assert(#s.Body == 3 and #s.Accent == 3, s.Id .. " colors")
	end
	for _, r in ipairs(RarityConfig.Order) do
		assert(BlobbyConfig.ByRarity[r] and #BlobbyConfig.ByRarity[r] >= 2, "rarity " .. r .. " needs 2+ species")
	end
end)

test("prices rise with rarity", function()
	local lastMax = 0
	for _, r in ipairs(RarityConfig.Order) do
		local minP, maxP = math.huge, 0
		for _, s in ipairs(BlobbyConfig.ByRarity[r]) do
			minP = math.min(minP, s.Price)
			maxP = math.max(maxP, s.Price)
		end
		assert(minP > lastMax, r .. " overlaps the tier below")
		lastMax = maxP
	end
end)

test("shop ids are placeholders and keys are unique", function()
	local keys = {}
	for _, p in ipairs(ShopConfig.Products) do
		assert(not keys[p.Key], "dup " .. p.Key)
		keys[p.Key] = true
		H.eq(p.ProductId, 0, p.Key .. " ProductId must stay 0 until set in Creator Hub")
		assert(p.Robux > 0 and p.Name and p.Kind)
	end
	for _, p in ipairs(ShopConfig.Passes) do
		assert(not keys[p.Key], "dup " .. p.Key)
		keys[p.Key] = true
		H.eq(p.PassId, 0, p.Key .. " PassId must stay 0")
	end
	for _, needed in ipairs({ "DoubleCash", "VIP", "AutoCollect", "FastCarry", "ExtraSlots", "ServerLuck", "MythicCrate", "LockNow", "CashSmall" }) do
		assert(keys[needed], "missing shop item " .. needed)
	end
end)

test("rewards and codes reference real things", function()
	H.eq(#RewardConfig.Daily, 7)
	for _, d in ipairs(RewardConfig.Daily) do
		if d.Kind == "Blobby" then
			assert(RarityConfig.Tiers[d.Rarity])
		end
	end
	assert(RewardConfig.Codes.RELEASE, "RELEASE code")
	for code, reward in pairs(RewardConfig.Codes) do
		H.eq(code, string.upper(code), "codes are stored upper-case")
		assert(reward.Cash or (reward.Blobby and RarityConfig.Tiers[reward.Blobby]))
	end
	assert(#EventConfig.Admin >= 4)
end)

test("audio slots are empty or reused ids", function()
	local allowed = {
		["rbxassetid://9113880475"] = true, ["rbxassetid://1837953706"] = true, ["rbxassetid://9116173869"] = true,
		["rbxassetid://9113722650"] = true, ["rbxassetid://9120851227"] = true, ["rbxassetid://9119661709"] = true,
		["rbxassetid://9116612715"] = true, ["rbxassetid://9116537007"] = true, ["rbxassetid://9119631707"] = true,
		["rbxassetid://9120839599"] = true, ["rbxassetid://9114591515"] = true, ["rbxassetid://9114533169"] = true,
		["rbxassetid://9113087803"] = true,
	}
	for key, def in pairs(AudioAssets) do
		assert(def.Id == "" or allowed[def.Id], key .. " uses an id that is not from the reference project")
	end
end)

return cases
