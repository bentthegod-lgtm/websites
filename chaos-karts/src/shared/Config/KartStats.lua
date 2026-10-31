--[[
	KartStats - THE physics table. Every kart in CHAOS KARTS (all 25 planned vehicles, bots,
	shop cosmetics) drives with exactly these numbers. Vehicles are cosmetic only: a vehicle
	definition may not contain any of these keys (a unit test enforces it), and nothing a
	player buys can change them.

	Units: studs, seconds, radians. Speeds are studs/s.

	TUNING KNOBS (see README "Studio test plan"):
	  TopSpeed / Accel / AccelCurve   straight-line pace and how punchy the launch feels
	  TurnRateLow / TurnRateHigh      steering at low vs top speed (speed-sensitive steering)
	  SteerResponse                   how fast the yaw rate follows the stick (higher = twitchier)
	  Grip / DriftGrip                lateral grip (higher = less slide)
	  DriftBaseTurn / DriftSteerRange how tight a drift is and how much you can widen/tighten it
	  DriftChargeLevels / DriftBoostTime  mini-turbo thresholds (blue, orange, purple) and boosts
	  BoostTopMul / BoostAccel        how strong every boost is
	  Gravity / HopVelocity / JumpLaunch  air feel
	  OffroadMul                      grass / sidewalk slowdown
	  WallKeep / WallRestitution      how much speed a wall glance keeps
]]

local KartStats = {
	-- Body / collision (identical hitbox for every vehicle)
	Hitbox = { X = 5.4, Y = 2.6, Z = 8.4 }, -- the invisible chassis part
	Radius = 3.6, -- wall and kart-to-kart collision circle
	RideHeight = 1.4, -- chassis centre above the ground
	WheelX = 2.2, -- wheel probe points (local, for ground sampling)
	WheelZ = 3.0,

	-- Engine
	TopSpeed = 80,
	Accel = 70, -- at standstill
	AccelCurve = 2.2, -- accel = Accel * (1 - (speed / cap) ^ AccelCurve)
	Brake = 120,
	ReverseSpeed = 30,
	ReverseAccel = 45,
	CoastDrag = 16, -- no throttle
	OverspeedDecay = 1.6, -- per second, pulls speed back down to the cap after a boost

	-- Steering
	TurnRateLow = 2.55, -- rad/s at TurnFullSpeed
	TurnRateHigh = 1.55, -- rad/s at TopSpeed
	TurnFullSpeed = 16, -- below this the turn rate fades in (no spinning on the spot)
	SteerResponse = 11, -- yaw-rate smoothing (1/s)
	Grip = 9, -- lateral velocity decay (1/s): a little slide, mostly planted
	GripTransfer = 0.7, -- share of the killed sideways speed that goes back into forward speed
	AirGrip = 0.5,
	AirSteer = 1.2, -- rad/s of air control

	-- Hop / drift / mini-turbo
	HopVelocity = 13,
	DriftMinSpeed = 36,
	DriftStartWindow = 0.35, -- after a hop, steer within this time to start a drift
	DriftBaseTurn = 1.25, -- rad/s with the stick centred
	DriftSteerRange = 0.8, -- +- rad/s from steering into / out of the drift
	DriftGrip = 2.4,
	DriftDrag = 4,
	DriftChargeLevels = { 0.7, 1.45, 2.25 }, -- seconds of drifting: blue, orange, purple sparks
	DriftChargeOuterBonus = 0.55, -- extra charge rate when steering hard into the drift
	DriftBoostTime = { 0.5, 0.95, 1.45 },

	-- Boosts
	BoostTopMul = 1.32,
	BoostAccel = 150,
	PadBoostTime = 1.1,
	StartBoostTime = 1.2,
	StartBoostWindow = 0.35, -- press gas within this many seconds before GO
	StartStallTime = 0.8, -- pressed gas too early: a short stall

	-- Air
	Gravity = 105,
	JumpLaunch = 36, -- a Jump surface (kicker ramp) launches at least this fast upward
	SnapDown = 0.9, -- how far below the wheels the ground can be and still count as grounded
	StepUp = 2.6, -- ground probes start this far above the wheels (curbs, seams)
	MaxProbe = 60,
	SlopeGravity = 0.5, -- fraction of gravity that acts along a slope (uphill slower)
	LandSquashMax = 0.35,
	AlignRate = 10, -- how fast the body aligns to the ground normal (visual + physics)

	-- Surfaces
	OffroadMul = 0.52, -- top speed on grass / sidewalk
	OffroadDrag = 38,

	-- Walls and bumps
	WallRestitution = 0.18, -- bounce off the wall normal
	WallKeep = 0.9, -- tangential speed kept on a glance
	WallMinKeep = 0.45, -- even a head-on hit keeps this fraction (never a dead stop)
	BumpPush = 18, -- kart-to-kart separation impulse
	BumpShare = 0.5,

	-- Effects (KartEffects API defaults)
	SpinOutTime = 1.1,
	FreezeTime = 1.6,
	SlowMul = 0.6,
	SlowTime = 2.5,
	GhostTime = 2.5, -- invulnerable / non-colliding after a respawn

	-- Simulation
	FixedStep = 1 / 60,
	MaxSubsteps = 6,
}

-- Speed the server accepts from a client before calling it impossible (boost + launch slack).
KartStats.MaxLegalSpeed = KartStats.TopSpeed * KartStats.BoostTopMul * 1.25 + 20

-- Every key in this table is a physics key: vehicle definitions may not contain any of them.
function KartStats.physicsKeys()
	local keys = {}
	for k, v in pairs(KartStats) do
		if type(v) ~= "function" then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	return keys
end

return KartStats
