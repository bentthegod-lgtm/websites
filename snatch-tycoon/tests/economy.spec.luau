local H = require("./helpers")
local Economy = require("../src/shared/Economy")
local GameConfig = require("../src/shared/Config/GameConfig")
local MutationConfig = require("../src/shared/Config/MutationConfig")
local BlobbyConfig = require("../src/shared/Config/BlobbyConfig")
local ShopConfig = require("../src/shared/Config/ShopConfig")
local cases, test = H.suite("Economy")

test("mutations multiply income and price", function()
	local s = BlobbyConfig.ById.CaptainSquish
	H.eq(Economy.blobbyIncome(s, nil), s.Income)
	H.eq(Economy.blobbyIncome(s, MutationConfig.Types.Gold), s.Income * 2)
	H.eq(Economy.blobbyPrice(s, MutationConfig.Types.Rainbow), s.Price * 6)
	H.eq(Economy.sellValue(1000, GameConfig.SellRefund), 500)
	H.eq(Economy.sellValue(1, 0.5), 1, "sell value has a floor of 1")
end)

test("rebirth cost grows and multiplier stacks", function()
	local r = GameConfig.Rebirth
	H.eq(Economy.rebirthCost(0, r), 50000)
	H.eq(Economy.rebirthCost(1, r), 300000)
	assert(Economy.rebirthCost(5, r) > Economy.rebirthCost(4, r))
	H.near(Economy.rebirthMultiplier(0, r), 1)
	H.near(Economy.rebirthMultiplier(3, r), 2.5)
end)

test("player multiplier combines rebirth, 2x pass, friends and events", function()
	local m = Economy.playerMultiplier({
		rebirths = 2, rebirthCfg = GameConfig.Rebirth, doubleCash = true,
		friends = 5, friendPer = GameConfig.FriendBoostPer, friendMax = GameConfig.FriendBoostMax, eventMult = 2,
	})
	-- (1 + 2*0.5) * 2 * (1 + 0.3 capped) * 2
	H.near(m, 2 * 2 * 1.3 * 2, 1e-9)
	H.near(Economy.playerMultiplier({ rebirths = 0, rebirthCfg = GameConfig.Rebirth }), 1)
end)

test("slot count respects rebirth cap, passes and pedestal maximum", function()
	H.eq(Economy.slotCount(0, false, false, GameConfig), 8)
	H.eq(Economy.slotCount(3, false, false, GameConfig), 11)
	H.eq(Economy.slotCount(99, false, false, GameConfig), 13)
	H.eq(Economy.slotCount(99, true, true, GameConfig), 17)
	assert(Economy.slotCount(99, true, true, GameConfig) <= GameConfig.MaxPedestals)
end)

test("offline earnings are capped and rejects bad input", function()
	local cap = GameConfig.OfflineCapHours * 3600
	H.eq(Economy.offlineEarnings(10, 100, cap, 0.5), 500)
	H.eq(Economy.offlineEarnings(10, 1e9, cap, 0.5), math.floor(10 * cap * 0.5))
	H.eq(Economy.offlineEarnings(10, -50, cap, 0.5), 0)
	H.eq(Economy.offlineEarnings(0 / 0, 50, cap, 0.5), 0)
	H.eq(Economy.offlineEarnings(10, math.huge, cap, 0.5), 0)
end)

test("cash packs scale with income and have a floor", function()
	local small = ShopConfig.Products[1].Pack
	H.eq(Economy.cashPackAmount(small, 0), 2500)
	H.eq(Economy.cashPackAmount(small, 1000), 600000)
	H.eq(Economy.cashPackAmount(small, 0 / 0), 2500)
	H.eq(Economy.roundNice(12345), 12000)
	H.eq(Economy.roundNice(87), 87)
end)

test("every species pays itself back in under two minutes", function()
	for _, s in ipairs(BlobbyConfig.List) do
		local payback = s.Price / s.Income
		assert(payback > 10 and payback < 120, s.Id .. " payback " .. payback)
	end
end)

return cases
