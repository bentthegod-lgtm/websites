--[[
	QUACKARONI'S SNEAKER PARADE (Brainrot, intensity 1) - the Stage 1 REFERENCE EVENT, built
	end to end to prove the pipeline:

	  1. The Event Director (server) picks it for a zone tagged plaza / open / park and sends
	     EventStart { id, instanceId, seed, warnAt, serverStartTime, endAt, zone }.
	  2. Every client plays it locally from the SERVER clock: a flashing warning stripe
	     across the road (3 s), then Quackaroni - a giant rubber duck in neon high-top
	     sneakers, sunglasses and a crown, with a toaster marching band - waddles across the
	     road. Its path is a pure function of (seed, zone, track), so every client and the
	     server agree on where it is at any server time (Event.positionAt).
	  3. The server resolves hits: a kart that touches the duck gets a KartEffects knockback
	     (bounced away and up, never eliminated), at most once per HitCooldown.
	  4. Cleanup: every part / connection is in the instance's Maid; the director cleans it
	     at the end or at the hard timeout.

	Quackaroni is an original character (no real-world IP).
]]

local Parts = require(script.Parent.Parent.Parts)
local Rng = require(script.Parent.Parent.Rng)

local Event = {}

Event.Def = {
	id = "QuackaroniParade",
	name = "Quackaroni's Sneaker Parade",
	category = "Brainrot",
	intensity = 1,
	weight = 10,
	duration = 12,
	warning = 3,
	tags = { "area", "crosses-track", "blocks-lane" },
	conflictsWith = {},
	minLap = 1,
	finalLapBoost = 1.3,
	zoneTags = { "plaza", "open", "park" },
	blocksLanes = 1,
	effects = { "knockback" },
	implemented = true,
	stage = 1,
	description = "A giant rubber duck in neon sneakers waddles across the road with a toaster marching band. Touch it and you get bounced.",
}

-- Its own sound slots (ids reused from DEAD AIR's licensed library; "" = add your own).
Event.Sounds = {
	Warning = { Id = "rbxassetid://9119661709", Volume = 0.45, Pitch = 1.35, Duration = 2.6, Fade = 0.6 }, -- "Alarm", up: parade siren
	Entrance = { Id = "rbxassetid://9113134899", Volume = 0.7, Pitch = 1.5, Duration = 3 }, -- "DistantImpact", up: a big squeaky stomp
	Attack = { Id = "", Volume = 0.7 }, -- a QUACK: add your own
	Impact = { Id = "rbxassetid://9116612715", Volume = 0.7, Pitch = 1.25 }, -- "CanClatter": kart bonked
	Exit = { Id = "", Volume = 0.5 }, -- the band marching off: add your own
}

Event.HitRadius = 11
Event.Overshoot = 30 -- how far beyond the road edges the parade starts / ends
Event.KnockSide = 46
Event.KnockUp = 24

--[[
	The parade's path, a pure function of the seed and the zone: a crossing of the main
	road somewhere in the middle of the zone, left-to-right or right-to-left.
]]
function Event.path(seed, zone, data)
	local rng = Rng.new(seed)
	local main = data.main
	local d = (zone.from + zone.span * rng:NextNumber(0.3, 0.7)) % main.length
	local s = main:at(d)
	local reach = s.w / 2 + s.sh + Event.Overshoot
	local dir = if rng:NextNumber() < 0.5 then 1 else -1
	local from = main:point(d, -reach * dir)
	local to = main:point(d, reach * dir)
	return { dist = d, from = from, to = to, length = (to - from).Magnitude, band = rng:NextInteger(3, 4) }
end

--[[
	Where the duck is at server time `now`: position, facing (unit), phase ("warning" /
	"walking" / "done") and progress 0..1.
]]
function Event.positionAt(path, timing, now)
	local walk = timing.endAt - timing.startAt
	local t = (now - timing.startAt) / walk
	local phase = if t < 0 then "warning" elseif t > 1 then "done" else "walking"
	local p = math.clamp(t, 0, 1)
	local base = path.from:Lerp(path.to, p)
	local dir = (path.to - path.from).Unit
	local bob = math.abs(math.sin((now - timing.startAt) * 5.5)) * 1.3
	return base + Vector3.new(0, bob, 0), dir, phase, p
end

-- SERVER --------------------------------------------------------------------------------

function Event.serverStart(ctx)
	ctx.path = Event.path(ctx.seed, ctx.zone, ctx.data)
	ctx.lastHit = {}
	ctx.hits = 0
end

function Event.serverStep(ctx, _dt)
	local now = ctx.now()
	local pos, dir, phase = Event.positionAt(ctx.path, ctx, now)
	if phase ~= "walking" then
		return
	end
	for _, racer in ipairs(ctx.racers()) do
		if not racer.ghost then
			local d = racer.pos - pos
			local flat = Vector3.new(d.X, 0, d.Z)
			if flat.Magnitude < Event.HitRadius + 3.6 and math.abs(d.Y) < 14 then
				local last = ctx.lastHit[racer.id]
				if not last or now - last >= ctx.hitCooldown then
					ctx.lastHit[racer.id] = now
					local away = if flat.Magnitude > 0.5 then flat.Unit else dir
					local impulse = away * Event.KnockSide + Vector3.new(0, Event.KnockUp, 0)
					if ctx.hit(racer, "knockback", { impulse = impulse }) then
						ctx.hits += 1
					end
				end
			end
		end
	end
end

function Event.serverStop(ctx)
	ctx.lastHit = {}
end

-- CLIENT --------------------------------------------------------------------------------

local P = Parts.Palette
local rgb = Color3.fromRGB

local function buildDuck(folder)
	local model = Instance.new("Model")
	model.Name = "Quackaroni"
	local root = Parts.new({ Name = "Root", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(), Transparency = 1, CanCollide = false, Parent = model })
	model.PrimaryPart = root
	local function add(opts)
		opts.CanCollide = false
		opts.Anchored = false
		opts.Parent = model
		local part = Parts.new(opts)
		Parts.weldCosmetic(part, root)
		return part
	end
	local yellow = rgb(255, 214, 40)
	-- body, tail, wings
	add({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(18, 18, 18), CFrame = CFrame.new(0, 13, 0), Color = yellow })
	add({ Name = "Belly", Shape = Enum.PartType.Ball, Size = Vector3.new(15, 15, 15), CFrame = CFrame.new(0, 11.5, -3), Color = rgb(255, 232, 120) })
	add({ Name = "Tail", Size = Vector3.new(6, 5, 6), CFrame = CFrame.new(0, 17, 8.5) * CFrame.Angles(math.rad(35), 0, 0), Color = yellow })
	for _, side in ipairs({ -1, 1 }) do
		add({ Name = "Wing", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 10, 12), CFrame = CFrame.new(side * 8.8, 14, 1) * CFrame.Angles(0, 0, math.rad(side * 18)), Color = rgb(245, 196, 30) })
	end
	-- head, beak, eyes, sunglasses, crown
	add({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12), CFrame = CFrame.new(0, 26, -3.5), Color = yellow })
	add({ Name = "Beak", Size = Vector3.new(7, 2.4, 6), CFrame = CFrame.new(0, 24.5, -10.5), Color = P.Orange })
	add({ Name = "BeakLow", Size = Vector3.new(6, 1.2, 5), CFrame = CFrame.new(0, 23.2, -10), Color = rgb(230, 110, 30) })
	add({ Name = "Shades", Size = Vector3.new(10.5, 2.4, 1), CFrame = CFrame.new(0, 27.5, -9.3), Color = P.Black, Material = Enum.Material.Glass, Reflectance = 0.3 })
	add({ Name = "ShadeGlow", Size = Vector3.new(10.8, 0.4, 1.1), CFrame = CFrame.new(0, 28.8, -9.3), Color = P.NeonPink, Material = Enum.Material.Neon })
	add({ Name = "Crown", Size = Vector3.new(6, 3, 6), CFrame = CFrame.new(0, 33, -3.5), Color = rgb(255, 196, 40), Material = Enum.Material.Metal })
	for i = 0, 3 do
		local a = i * math.pi / 2
		add({ Name = "CrownSpike", Size = Vector3.new(1.4, 2.6, 1.4), CFrame = CFrame.new(math.cos(a) * 2.4, 35.5, -3.5 + math.sin(a) * 2.4), Color = rgb(255, 196, 40), Material = Enum.Material.Metal })
	end
	-- neon high-top sneakers
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 4.6
		add({ Name = "Leg", Size = Vector3.new(2.4, 5, 2.4), CFrame = CFrame.new(x, 4.6, 0), Color = P.Orange })
		add({ Name = "Sneaker", Size = Vector3.new(5, 4, 9), CFrame = CFrame.new(x, 2.2, -1.5), Color = if side < 0 then P.NeonCyan else P.NeonPink })
		add({ Name = "Sole", Size = Vector3.new(5.3, 1, 9.4), CFrame = CFrame.new(x, 0.5, -1.5), Color = P.White })
		add({ Name = "Laces", Size = Vector3.new(3.4, 0.4, 4), CFrame = CFrame.new(x, 4.3, -3), Color = P.White })
		add({ Name = "Swoosh", Size = Vector3.new(5.4, 0.8, 4.5), CFrame = CFrame.new(x, 2.4, -1.5) * CFrame.Angles(math.rad(-12), 0, 0), Color = P.NeonYellow, Material = Enum.Material.Neon })
	end
	model.Parent = folder
	return model
end

local function buildToaster(folder, i)
	local model = Instance.new("Model")
	model.Name = "Toaster" .. i
	local root = Parts.new({ Name = "Root", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(), Transparency = 1, CanCollide = false, Parent = model })
	model.PrimaryPart = root
	local function add(opts)
		opts.CanCollide = false
		opts.Anchored = false
		opts.Parent = model
		local part = Parts.new(opts)
		Parts.weldCosmetic(part, root)
		return part
	end
	add({ Name = "Body", Size = Vector3.new(4, 3.2, 2.6), CFrame = CFrame.new(0, 2.8, 0), Color = rgb(200, 205, 215), Material = Enum.Material.Metal, Reflectance = 0.2 })
	add({ Name = "Toast", Size = Vector3.new(2.6, 1.6, 0.5), CFrame = CFrame.new(0, 4.8, 0), Color = rgb(214, 160, 90) })
	add({ Name = "Drum", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 2.6, 2.6), CFrame = CFrame.new(0, 2.6, -2) * Parts.ALONG_Z, Color = P.Red })
	for _, side in ipairs({ -1, 1 }) do
		add({ Name = "Foot", Size = Vector3.new(1, 1.2, 1.4), CFrame = CFrame.new(side * 1.2, 0.6, 0), Color = P.Black })
	end
	model.Parent = folder
	return model
end

local function buildWarning(folder, path)
	local d = path.to - path.from
	local mid = (path.from + path.to) / 2
	local stripe = Parts.new({
		Name = "ParadeWarning",
		Size = Vector3.new(16, 0.3, d.Magnitude),
		CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.35, 0), path.to + Vector3.new(0, 0.35, 0)),
		Color = P.NeonYellow,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CastShadow = false,
		Parent = folder,
	})
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(300, 70)
	gui.StudsOffset = Vector3.new(0, 12, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 600
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "QUACK CROSSING!"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = P.NeonYellow
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = stripe
	return stripe
end

function Event.play(ctx)
	ctx.path = Event.path(ctx.seed, ctx.zone, ctx.data)
	ctx.warning = ctx.maid:give(buildWarning(ctx.folder, ctx.path))
	ctx.duck = ctx.maid:give(buildDuck(ctx.folder))
	ctx.band = {}
	for i = 1, ctx.path.band do
		ctx.band[i] = ctx.maid:give(buildToaster(ctx.folder, i))
	end
	ctx.entered, ctx.exited = false, false
	ctx.sound("Warning", ctx.path.from)
	Event.step(ctx, 0)
end

function Event.step(ctx, _dt)
	if not ctx.duck then
		return
	end
	local now = ctx.now()
	local pos, dir, phase = Event.positionAt(ctx.path, ctx, now)
	if ctx.warning then
		local blink = math.floor(now * 4) % 2 == 0
		ctx.warning.Transparency = if phase == "warning" then (if blink then 0.25 else 0.7) else 0.85
	end
	local hidden = phase == "warning"
	local sway = math.sin((now - ctx.startAt) * 5.5) * math.rad(9)
	local cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, sway)
	if hidden then
		cf = CFrame.new(ctx.path.from - Vector3.new(0, 80, 0))
	end
	ctx.duck:PivotTo(cf)
	for i, toaster in ipairs(ctx.band) do
		local back = pos - dir * (12 + i * 6.5) + Vector3.new(0, math.abs(math.sin((now + i) * 7)) * 0.8 - pos.Y + ctx.path.from.Y, 0)
		toaster:PivotTo(if hidden then cf else CFrame.lookAt(back, back + dir) * CFrame.Angles(0, 0, -sway))
	end
	if phase == "walking" and not ctx.entered then
		ctx.entered = true
		ctx.sound("Entrance", pos)
	elseif phase == "done" and not ctx.exited then
		ctx.exited = true
		ctx.sound("Exit", pos)
	end
	-- the local kart gets a little shake when the duck stomps nearby
	local mine = ctx.localKart()
	if mine and phase == "walking" and (mine.pos - pos).Magnitude < 40 then
		ctx.shake(0.12)
	end
end

function Event.cleanup(ctx)
	ctx.duck, ctx.band, ctx.warning = nil, nil, nil
end

return Event
