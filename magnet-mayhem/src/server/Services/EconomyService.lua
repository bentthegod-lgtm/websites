--[[
	EconomyService - selling scrap at the shredder.

	Sale flow (all on the server, one function so it can't half-happen):
	  validate (profile loaded, scrap carried, standing at the shredder, cooldown)
	  -> compute value from the server-side pile * the player's multiplier
	  -> clear the pile -> grant coins once -> stats / quests / analytics -> effects.
	Standing on the sell pad sells automatically; the console prompt and the HUD button
	call the same function. Repeated touches can't pay twice: the pile is emptied in the
	same step that pays, and there is a cooldown on top.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MagnetMayhem")
local GameConfig = require(Shared.Config.GameConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)

local EconomyService = {}

local services
local world
local lastSale = {}
local SELL_REACH = 16 -- studs from the pad centre (pad is 18 x 12)

function EconomyService.init(registry)
	services = registry
end

function EconomyService.setWorld(newWorld)
	world = newWorld
end

function EconomyService.atShredder(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not world then
		return false
	end
	local pad = world.sellPad.Position
	local d = root.Position - pad
	return math.abs(d.X) <= SELL_REACH and math.abs(d.Z) <= SELL_REACH * 0.8 and d.Y < 12
end

-- Returns coins paid (0 if nothing was sold) and a message.
function EconomyService.sell(player, _source)
	local data = services.DataService.getProfile(player)
	if not data then
		return 0, "Your data is still loading."
	end
	if #data.Carried == 0 then
		return 0, "Nothing to sell yet - turn on your magnet!"
	end
	if not EconomyService.atShredder(player) then
		return 0, "Bring your scrap to the shredder to sell it."
	end
	local t = os.clock()
	if lastSale[player] and t - lastSale[player] < GameConfig.SellCooldown then
		return 0, nil
	end
	lastSale[player] = t
	local _, pileValue = services.DataService.carriedTotals(data)
	local count = #data.Carried
	local stats = services.UpgradeService.statsFor(player)
	local coins = Economy.saleValue(pileValue, stats.ScrapValueMultiplier)
	data.Carried = {}
	services.DataService.addCoins(player, coins, true)
	data.TotalScrapValue += coins
	services.DataService.bump(player, "SellCount", 1)
	services.DataService.bump(player, "SellValue", coins)
	services.QuestService.tutorialEvent(player, "Sell")
	services.Analytics.funnel(player, "FirstSale")
	services.Analytics.custom(player, "SaleValue", coins)
	services.PlayerService.updatePileAttributes(player)
	services.Remotes.SellFx:FireAllClients(player.UserId, coins, count, coins >= EconomyConfig.BigSale)
	services.DataService.sendProfile(player)
	return coins, string.format("Sold %d scrap for %s coins!", count, Format.short(coins))
end

function EconomyService.onPlayerRemoving(player)
	lastSale[player] = nil
end

function EconomyService.start()
	services.Remotes.Sell.OnServerEvent:Connect(function(player)
		local coins, message = EconomyService.sell(player, "Button")
		if coins == 0 and message then
			services.Remotes.Notify:FireClient(player, message, "warn")
		end
	end)
	world.sellPrompt.Triggered:Connect(function(player)
		local coins, message = EconomyService.sell(player, "Prompt")
		if coins == 0 and message then
			services.Remotes.Notify:FireClient(player, message, "warn")
		end
	end)
	-- Auto-sell while standing on the pad (checked on the server, not with Touched).
	task.spawn(function()
		while true do
			task.wait(0.3)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = services.DataService.getProfile(player)
				if data and #data.Carried > 0 and EconomyService.atShredder(player) then
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					local pad = world.sellPad.Position
					if root and math.abs(root.Position.X - pad.X) <= 9 and math.abs(root.Position.Z - pad.Z) <= 6 then
						EconomyService.sell(player, "Pad")
					end
				end
			end
		end
	end)
end

return EconomyService
