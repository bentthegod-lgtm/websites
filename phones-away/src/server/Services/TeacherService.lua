--[[
	TeacherService - the teacher NPC (and the Principal) in the world.

	Runs TeacherBrain (pure) every tick, moves the rigs and publishes their state as model
	attributes for the client (Pose, Heading, X, Z, Warn, Checking, Fov, Sight) so
	TeacherController can animate joints smoothly, draw the vision cone, and show "?"/"!".
	The SERVER alone decides what she can see (Detection uses these same brain numbers).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("PhonesAway")
local GameConfig = require(Shared.Config.GameConfig)
local TeacherConfig = require(Shared.Config.TeacherConfig)
local TeacherBrain = require(Shared.TeacherBrain)
local TeacherRig = require(Shared.TeacherRig)
local Detection = require(Shared.Detection)
local Rng = require(Shared.Rng)

local TeacherService = {}

local services
local L = GameConfig.Classroom
local rng = Rng.new(os.time() % 77777 + 11)
local teacherModel, principalModel
local brain
local principal -- { present, x, z, heading, sight }
local currentStyle

function TeacherService.init(registry)
	services = registry
end

local function publish(model, b)
	model:SetAttribute("Pose", b.pose)
	model:SetAttribute("Heading", b.heading)
	model:SetAttribute("X", b.x)
	model:SetAttribute("Z", b.z)
	model:SetAttribute("Warn", b.warn == true)
	model:SetAttribute("Checking", b.checking == true)
	model:SetAttribute("Fov", b.fov or TeacherConfig.Sight.FovDegrees)
	model:SetAttribute("Sight", b.sight or 0)
	TeacherRig.place(model, b.x, b.z, b.heading, 0)
end

local function buildTeacher(styleKey)
	if teacherModel then
		teacherModel:Destroy()
	end
	currentStyle = styleKey
	local style = TeacherRig.Styles[styleKey]
	teacherModel = TeacherRig.build(style, CFrame.new(L.BoardSpot[1], 0, L.BoardSpot[2]))
	teacherModel.Name = "Teacher"
	teacherModel:SetAttribute("DisplayName", style.Name)
	teacherModel:SetAttribute("Role", "Teacher")
	teacherModel:SetAttribute("Range", TeacherConfig.Sight.Range)
	teacherModel.Parent = services.World.npcs
end

function TeacherService.setup()
	buildTeacher("Teacher")
	brain = TeacherBrain.new(TeacherConfig, L, rng)
	brain:setPhase("Board", 0)
	publish(teacherModel, brain)
	principalModel = TeacherRig.build(TeacherRig.Styles.Principal, CFrame.new())
	principalModel.Name = "Principal"
	principalModel:SetAttribute("DisplayName", TeacherRig.Styles.Principal.Name)
	principalModel:SetAttribute("Role", "Principal")
	principalModel:SetAttribute("Range", TeacherConfig.Sight.Range * 0.7)
	principalModel.Parent = services.World.npcs
	principal = { present = false }
	TeacherService.parkPrincipal()
end

-- The principal waits at the far end of the hallway between visits.
function TeacherService.parkPrincipal()
	principal.present = false
	principal.x, principal.z, principal.heading = L.HallwayX + 4, 34, math.pi
	principal.pose, principal.sight = "Lecture", 0
	principal.fov = 40
	publish(principalModel, principal)
end

--[[
	New class: fresh brain. opts = { substitute, detection }
]]
function TeacherService.startClass(opts, now)
	opts = opts or {}
	local styleKey = if opts.substitute then "Substitute" else "Teacher"
	if styleKey ~= currentStyle then
		buildTeacher(styleKey)
	end
	brain = TeacherBrain.new(TeacherConfig, L, rng, {
		substitute = opts.substitute,
		detection = opts.detection or 1,
		turnScale = if opts.substitute then TeacherConfig.Events.Substitute.TurnScale else 1,
	})
	brain:setPhase("Board", now)
	publish(teacherModel, brain)
end

function TeacherService.setPhase(phase, now)
	brain:setPhase(phase, now)
	teacherModel:SetAttribute("Phase", phase)
end

function TeacherService.setDetection(multiplier)
	brain:setDetection(multiplier)
end

function TeacherService.brain()
	return brain
end

function TeacherService.model()
	return teacherModel
end

function TeacherService.principalModel()
	return principalModel
end

function TeacherService.principalPresent()
	return principal ~= nil and principal.present
end

function TeacherService.principalEnter()
	principal.present = true
	principal.x, principal.z = services.World.principalSpot[1], services.World.principalSpot[2]
	principal.heading = Detection.headingTo(principal.x, principal.z, 0, 5)
	principal.pose = "Arms"
	principal.sight = 0.5
	publish(principalModel, principal)
end

function TeacherService.principalLeave()
	TeacherService.parkPrincipal()
end

function TeacherService.distract(x, z, now)
	return brain:distract(x, z, now, GameConfig.Plane.DistractSeconds)
end

function TeacherService.caught(x, z, now)
	brain:caught(x, z, now)
end

-- Observer list for Detection (teacher + principal when present).
function TeacherService.observers()
	local list = { brain:observer() }
	if principal.present then
		table.insert(list, { x = principal.x, z = principal.z, heading = principal.heading, fov = principal.fov, sight = principal.sight, hearing = 0.6, checking = false })
	end
	return list
end

function TeacherService.update(dt, now, focus)
	brain:update(dt, now, { focus = focus })
	publish(teacherModel, brain)
	if principal.present then
		-- Slow, judgemental sweep across the room from the doorway.
		local base = Detection.headingTo(principal.x, principal.z, 0, 4)
		principal.heading = Detection.turnToward(principal.heading, base + math.rad(math.sin(now * 0.4) * 30), math.rad(25) * dt)
		publish(principalModel, principal)
	end
end

-- Between classes: back at the board, relaxed.
function TeacherService.idle(now)
	if brain then
		brain:setPhase("Board", now or 0)
		brain.x, brain.z, brain.heading = L.BoardSpot[1], L.BoardSpot[2], math.pi
		brain.distractUntil, brain.caughtUntil = nil, nil
		brain.pose = "Write"
		brain.sight = 0
		publish(teacherModel, brain)
	end
end

return TeacherService
