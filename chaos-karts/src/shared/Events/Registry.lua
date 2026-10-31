--[[
	Events/Registry - the catalog of all 35 planned world events (25 Brainrot / 5 Fiction-
	style / 5 Disasters). One module per event in this folder; ORDER is the catalog order.
	Only events with Def.implemented = true are ever picked by the Event Director (Stage 1
	implements the reference event, QuackaroniParade; the rest arrive in Stages 4-5).
]]

local Registry = {}

Registry.ORDER = {
	"QuackaroniParade",
	"ToasterDownpour",
	"MegaBurgerRoll",
	"CactusConga",
	"LoafCatSpin",
	"PigeonMafia",
	"SockPuppetSiege",
	"BouncyCastleDrop",
	"PotatoGolem",
	"DiscoBananaFever",
	"FridgeSquadron",
	"RubberChickenChoir",
	"SpaghettiTornado",
	"RocketRecliner",
	"JellyAvalanche",
	"HotdogHurdles",
	"MimeWall",
	"BubbleBathFlood",
	"SunglassesSun",
	"BeatboxBroccoli",
	"NoodleWorm",
	"SofaStampede",
	"PancakeFlipper",
	"LaserLlamaDisco",
	"TurboSnail",
	"KaijuKrunchjaw",
	"MechaSentinel",
	"SpiritFoxDash",
	"SwordSaintSlash",
	"WizardDuel",
	"CityQuake",
	"TwisterAlley",
	"FlashFlood",
	"FreakBlizzard",
	"NeonBlackout",
}

local modules = {}
local catalog = {}
for _, id in ipairs(Registry.ORDER) do
	local module = require(script.Parent[id])
	assert(module.Def and module.Def.id == id, "event module id mismatch: " .. id)
	modules[id] = module
	table.insert(catalog, module.Def)
end

Registry.catalog = catalog

function Registry.module(id)
	return modules[id]
end

function Registry.def(id)
	local m = modules[id]
	return m and m.Def
end

function Registry.implemented()
	local list = {}
	for _, def in ipairs(catalog) do
		if def.implemented then
			table.insert(list, def)
		end
	end
	return list
end

function Registry.countBy(field)
	local counts = {}
	for _, def in ipairs(catalog) do
		counts[def[field]] = (counts[def[field]] or 0) + 1
	end
	return counts
end

return Registry
