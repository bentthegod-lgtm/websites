--[[
	EventBase - the shape every world event module has. One file per event (Events/<Id>.lua):

	  Event.Def      the catalog entry (see below)
	  Event.Sounds   its own sound slots: Warning, Entrance, Attack, Impact, Exit
	                 (same fields as Config/AudioAssets; Id = "" is skipped)
	  Server:  Event.serverStart(ctx), Event.serverStep(ctx, dt), Event.serverStop(ctx)
	  Client:  Event.play(ctx), Event.step(ctx, dt), Event.cleanup(ctx)

	Def fields: id, name, category ("Brainrot" | "Fiction" | "Disaster"), intensity (1-3),
	weight, duration, warning (seconds of warning before it starts), tags ("area",
	"track-wide", "projectile", "blocks-lane", "sky", "chase", "screen-effect",
	"crosses-track"), conflictsWith (ids), minLap, finalLapBoost (weight multiplier on the
	final lap), zoneTags (the map zone tags it can use - any of them), blocksLanes (lanes of
	its zone it blocks, if tagged blocks-lane), effects (KartEffects it may apply),
	implemented (false until its stage: the director never picks it), stage, description.

	Server ctx: { id, instanceId, def, seed, rng, zone, data (MapData), warnAt, startAt,
	  endAt, now(), maid, racers() -> list of { id, pos, vel, ghost }, hit(racer, kind,
	  params) -> applies a KartEffect (never an elimination) }.
	Client ctx: { same timing + seed / zone / data, now(), maid, folder, sound(slot, pos),
	  shake(amount), localKart() -> { pos, vel } or nil }.
]]

local EventBase = {}

local SLOTS = { "Warning", "Entrance", "Attack", "Impact", "Exit" }
EventBase.SoundSlots = SLOTS

local function noop() end

-- A catalog-only event (not implemented yet): every hook is a no-op.
function EventBase.stub(def)
	def.implemented = false
	local sounds = {}
	for _, slot in ipairs(SLOTS) do
		sounds[slot] = { Id = "", Volume = 0.6 }
	end
	return {
		Def = def,
		Sounds = sounds,
		serverStart = noop,
		serverStep = noop,
		serverStop = noop,
		play = noop,
		step = noop,
		cleanup = noop,
	}
end

return EventBase
