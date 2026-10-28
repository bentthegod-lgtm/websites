--[[
	ScoringService - turns a finished run into rewards, exactly once.

	finish(run, objectives, reason) is called by CrashService when a run ends (never for a
	cancelled run or a player who left). It:
	  1. computes the breakdown with the server's multipliers (Scoring.Run:result);
	  2. marks the run paid BEFORE adding coins (no double payout on any path);
	  3. bumps stats, updates personal records, feeds quests / dailies / achievements /
	     duels / tutorial / analytics;
	  4. sends the owner a Results breakdown (+ next recommended upgrade) and everyone a
	     short summary (results board, announcements for big records).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CrashLab")
local CourseConfig = require(Shared.Config.CourseConfig)
local Format = require(Shared.Format)

local ScoringService = {}

local services
local world
local recent = {} -- latest results for the lobby board

function ScoringService.init(registry)
	services = registry
end

function ScoringService.setWorld(newWorld)
	world = newWorld
end

local function updateBoard()
	if not world or not world.resultsBoard then
		return
	end
	for i, row in ipairs(world.resultsBoard.rows) do
		local r = recent[i]
		row.Text = if r then string.format("%s  -  %s pts  -  %s studs  (%s)", r.name, Format.short(r.score), Format.stat(math.floor(r.distance)), r.machine) else "---"
	end
end

function ScoringService.recent()
	return recent
end

function ScoringService.finish(run, objectives, reason)
	if run.paid then
		return run.result
	end
	run.paid = true
	local player = run.player
	local data = services.DataService.getProfile(player)
	if not data or not player.Parent then
		return nil
	end
	local stats = run.stats
	local result = run.tracker:result({
		impact = stats.ImpactMultiplier,
		bonus = stats.BonusMultiplier,
		featured = stats.FeaturedMultiplier,
		featuredId = run.featuredId,
		coins = stats.CoinMultiplier,
	})
	result.reason = reason
	result.machine = run.machine.Id
	result.objectives = objectives
	result.featuredId = run.featuredId
	result.featuredDone = run.featuredId ~= nil and table.find(objectives, run.featuredId) ~= nil
	run.result = result

	local DS = services.DataService
	DS.addCoins(player, result.coins, true)
	-- Single-run values for daily challenges (checked by QuestService.onRun).
	local targets = run.tracker:count("Target")
	local props = run.tracker:count("Prop")
	local rings = run.tracker:count("Ring")
	DS.bump(player, "Runs", 1)
	DS.bump(player, "Machine:" .. run.machine.Id, 1)
	if result.impacts > 0 then
		DS.bump(player, "Impacts", result.impacts)
	end
	if targets + props > 0 then
		DS.bump(player, "Targets", targets + props)
	end
	if props > 0 then
		DS.bump(player, "Destroyed", props)
	end
	if rings > 0 then
		DS.bump(player, "Rings", rings)
	end
	if #objectives > 0 then
		DS.bump(player, "Objectives", #objectives)
	end
	result.records = {}
	if not result.voided then
		for key, value in pairs({ BestScore = result.score, BestDistance = math.floor(result.distance), BestHeight = math.floor(result.height), BestImpacts = result.impacts }) do
			if DS.record(player, key, value) then
				result.records[key] = true
			end
		end
	end
	result.personalBest = data.Stats.BestScore or 0
	services.QuestService.onRun(player, result, run)
	services.DuelService.onRunFinished(player, result)
	services.QuestService.tutorialEvent(player, "RunDone")
	if #objectives > 0 then
		services.QuestService.tutorialEvent(player, "Objective")
		services.Analytics.funnel(player, "FirstObjective")
	end
	services.Analytics.funnel(player, "FirstResult")
	services.Analytics.custom(player, "RunScore", result.score)
	services.CourseService.checkFacilities(player)
	result.recommend = services.UpgradeService.recommend(player, result)
	result.coinsTotal = data.Coins
	services.QuestService.rerollFeatured(player)
	services.Remotes.Results:FireClient(player, result)
	services.Remotes.RunEnded:FireAllClients(player.UserId, { score = result.score, distance = result.distance, name = player.DisplayName, record = result.records.BestScore == true })
	if result.records.BestDistance and result.distance >= 250 then
		services.Remotes.Announce:FireAllClients(string.format("%s launched a dummy %s studs!", player.DisplayName, Format.stat(math.floor(result.distance))), { 255, 200, 60 })
	end
	table.insert(recent, 1, { name = player.DisplayName, score = result.score, distance = result.distance, machine = run.machine.Short or run.machine.Id })
	while #recent > 6 do
		table.remove(recent)
	end
	updateBoard()
	DS.sendProfile(player)
	return result
end

-- Lookup helper for clients' result screens.
function ScoringService.objectiveName(id)
	local o = CourseConfig.ObjectiveById[id]
	return o and o.Name or id
end

return ScoringService
