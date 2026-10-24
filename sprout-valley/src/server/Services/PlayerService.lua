--[[
	PlayerService - characters spawn at their own garden gate, the Travel remote (HUD
	buttons: Garden / Seeds / Gear / Sell), stall prompts that open shop panels, and the
	VIP overhead tag.
]]

local Players = game:GetService("Players")

local RateLimit = require(script.Parent.RateLimit)

local PlayerService = {}

local services
local village
local travelLimiter = RateLimit.new(0.8, 2)

local DESTINATIONS = { Seeds = "SeedShop", Gear = "GearShop", Sell = "SellStand" }

function PlayerService.init(registry)
	services = registry
end

function PlayerService.setVillage(v)
	village = v
end

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function PlayerService.teleport(player, cf)
	local root = rootOf(player)
	if not root then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = cf
	return true
end

function PlayerService.travel(player, destination)
	if destination == "Garden" then
		local plot = services.PlotService.plotOf(player)
		if plot then
			return PlayerService.teleport(player, plot.spawnCFrame)
		end
		return false
	end
	local stallKey = DESTINATIONS[destination]
	local stall = stallKey and village and village.stalls[stallKey]
	if stall then
		return PlayerService.teleport(player, stall.standCFrame)
	end
	return false
end

function PlayerService.refreshTag(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("VipTag")
	if old then
		old:Destroy()
	end
	if not services.ShopService.owns(player, "VIP") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "VipTag"
	gui.Size = UDim2.fromOffset(120, 28)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.MaxDistance = 80
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "VIP"
	label.TextColor3 = Color3.fromRGB(255, 140, 210)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	gui.Parent = head
end

local function onCharacter(player, character)
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end
		task.wait(0.1)
		local plot = services.PlotService.plotOf(player)
		if plot and character.Parent then
			PlayerService.teleport(player, plot.spawnCFrame)
		end
		PlayerService.refreshTag(player)
	end)
end

function PlayerService.onProfileLoaded(player)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

function PlayerService.onPlayerRemoving(player)
	travelLimiter:forget(player)
end

function PlayerService.start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end
	services.Remotes.Travel.OnServerEvent:Connect(function(player, destination)
		if type(destination) == "string" and travelLimiter:allow(player) then
			PlayerService.travel(player, destination)
		end
	end)
	services.Remotes.RequestState.OnServerEvent:Connect(function(player)
		if services.DataService.getProfile(player) and travelLimiter:allow(player) then
			services.DataService.sendProfile(player)
			services.StockService.sendTo(player)
			services.LeaderboardService.sendTo(player)
		end
	end)
	if village then
		local panels = { SeedShop = "SeedShop", GearShop = "GearShop", SellStand = "Sell" }
		for key, stall in pairs(village.stalls) do
			stall.prompt.Triggered:Connect(function(player)
				services.Remotes.OpenPanel:FireClient(player, panels[key])
			end)
		end
	end
end

return PlayerService
