# CRASH LAB

A multiplayer Roblox physics simulator: **build a machine, launch a dummy, cause an absurd
crash, earn coins, upgrade everything, try again.** Cartoon crash-test dummies, ragdoll
physics and stylised destruction, with no gore.

Everything (four facilities, the machines, the dummies and the UI) is built from code in
this Rojo project. There are no imported models and no free-model scripts.

> **Honest status:** every check that can run in this environment passes (lint, compile,
> 38 unit tests, a 32-check headless harness on the built place, preview renders). **No
> Roblox Studio play-test has been possible here.** Lune does not simulate physics, so
> the real ragdoll motion, how launches *feel*, bounce and slide behaviour and the
> camera/UI on real devices are **unverified**. See [Studio testing checklist](#studio-testing-checklist).

## Build and run

```bash
cd crash-lab
rojo build -o build/CrashLab.rbxlx      # open the file in Roblox Studio and press Play
# or live-sync:  rojo serve   (then Connect in the Rojo Studio plugin)
```

## How to play

1. **Spawn** in the lobby (the CRASH LAB sign, the dummy display and the crashed-car exhibit).
   Follow the yellow arrows to the launch deck.
2. **Walk onto a glowing green launch pad and press E.** The pad is now yours, and your
   machine appears on it.
3. **Set up the launch** in the panel: power (drag the bar), angle, aim (left/right) and
   spin mode. A **featured objective** is shown at the top.
4. **Press LAUNCH** (F / R2). The machine charges, then fires. The follow camera chases your
   dummy (Space skips it).
5. **Score**: distance, max height, impacts (by tier), targets, smashed props, rings,
   landing zones and objectives. The featured objective pays a multiplier. Coins = score.
6. **Upgrade** at the station or with U, unlock the Spring Cannon and the Air Cannon,
   and go again.
7. **New facilities**: once you meet a facility's requirement, unlock it once for coins in
   the Facilities menu (M, or the hub's FACILITY TRANSIT gate) and TRAVEL there. Each
   facility's HUB TRANSIT kiosk (behind its deck) brings you back.

The first launch happens in seconds. The first upgrade (Launch Power, 60 coins) is
affordable after one to three launches, and it is a visible change: about 7% faster,
which means roughly 15% further.

### Controls

| Action | PC | Gamepad | Touch |
|---|---|---|---|
| Use pad / stations | E | X | tap prompt |
| Launch | F or LAUNCH | R2 | LAUNCH |
| Power - / + | 1 / 2, drag bar | D-pad down / up | drag bar |
| Angle - / + | 3 / 4 | D-pad left / right | - / + |
| Aim left / right | 5 / 6 | L1 / R1 | - / + |
| Spin mode | 7 | Y | SPIN |
| Skip follow camera | Space (in flight) | B | SKIP |
| Retry from results | R | - | RETRY |
| Upgrades / Menu / Help | U / M / H | L2 (menu) | menu buttons |

Movement, camera, jump and Escape keep Roblox's defaults. Tab, /, I/O and the arrow keys
are left alone.

## Systems

### Crash physics (server-authoritative)
- **The dummy** (`src/shared/DummyModel.lua`) is a purpose-built 11-part ragdoll:
  - joints are `BallSocketConstraint`s with cone and twist limits (neck, shoulders, elbows,
    hips, knees);
  - `NoCollisionConstraint`s keep limbs from fighting each other;
  - the dummy class (Payload upgrade) sets density and elasticity;
  - there is no Humanoid, so nothing can "control" it.
- **Launch** (`LaunchService`): the server validates the request and computes the velocity
  (`Economy.launch`) from server-side upgrade levels. Power, angle, aim and spin are clamped
  to what the player has unlocked. The client never sends a speed, direction, score or
  reward.
- **Run** (`CrashService`):
  - the server spawns the dummy;
  - collision group `CL_Dummy` doesn't collide with players or other dummies;
  - `SetNetworkOwner(nil)` keeps physics on the server, so a client can't teleport it;
  - every body part gets the launch velocity, plus spin.
- **Tracking** (`Scoring.Run`):
  - the server samples the dummy 12 times a second;
  - distance is the furthest *valid* point down the course, and height is the highest
    valid sample;
  - a sample that moves further than physically possible is rejected, and 3 of them void
    the run (token coins, no records).
- **Impacts**:
  - each server `Touched` contact is classified by the dummy part's own speed into tiers
    (Light / Medium / Heavy / Massive);
  - the same object is debounced and counted at most 3 times, the floor counts as one
    grouped object (max 5), and each run has a cap (10 + 3 per Durability level);
  - raw impulses are never used as reward.
- **End of run**: the dummy settles (slower than 4 st/s for 1.4 s), gets stuck (moves under
  1.5 studs in 4 s), leaves the arena or falls out of the world, the rig breaks, the time
  limit (22 s) is hit, or the player leaves. Cleanup is always scheduled, and leaving
  cancels the run with no reward.

### Machines
| Machine | Behaviour | Unlock |
|---|---|---|
| **Standard Launcher** | Catapult arm; what you aim is what you get. 0.8 s prep. | Owned |
| **Spring Cannon** | Coil compresses then snaps. Faster, fires **12° flatter** with **backspin**: skims, bounces, slides. | 2,500 coins + reach 140 studs |
| **Experimental Air Cannon** | Pressure builds, the beacon flashes and the gauge climbs, then a blast. Fastest; fires **8° steeper** with a forward tumble; needs at least 50% pressure. | 25,000 coins + Payload 1 + reach 300 studs |

Each machine has its own model, animation (client-side, purely visual) and sound profile.

### Course (Industrial Crash Lab)
- **Lobby**: CRASH LAB sign, dummy display, crashed-car exhibit, upgrade station, Dummy
  Locker, results board, two leaderboards, tutorial signs and the facility gate.
- **Launch deck**: six pads that aim slightly toward the centre line.
- **Arena (540 studs)**:
  - bounce pads, kicker ramps and a skid ramp;
  - barriers: jersey barriers and bumpers;
  - three rings (20 / 58 / 105 studs high) and three targets (swinging, sliding, and the
    far gong);
  - two landing zones, distance markers every 50 studs, and landing cushions;
  - glass and net walls, a catch net, spectator stands, an observation booth, gantries,
    light towers and test fans.
- **Destructibles**: cardboard boxes, plastic pins, wooden fences, breakaway glass panels
  (need the Reinforced dummy) and test towers.
  - Debris is capped server-wide (60 parts), cleaned up after 4 s, and props respawn after
    9 s.
  - Each prop pays once per run.
- **Objectives** (14): rings, targets, landings, distance goals, breaking a barrier or the
  panel wall, and hitting 3 things in one run. All are checked on the server. One featured
  objective, picked to suit your setup's reach, is shown before each launch and pays x2
  (up to x3.5 with upgrades).

### Progression
- **10 upgrades in 4 categories**, each changing how a launch plays:
  - **Launch Power**: Power, Payload class.
  - **Launcher Mechanics**: Quick Reload, Aim Range, Precision (faster charge, no spread).
  - **Dummy Technology**: Durability (more counted impacts), Spin Module (Flip /
    Corkscrew / Chaos).
  - **Scoring**: Objective Bonus, Challenge Multiplier, Lab Analyst.
- **Personal records**: best score, farthest, highest and most impacts.
- **22 achievements**, some unlocking cosmetics (6 are for the new facilities).
- **3 daily challenges per UTC day**: targets are frozen from that morning's records, so
  they are always achievable, and no purchase is needed.
- **Codes**: `CRASHLAB`, `BUCKLEUP`.
- **Lab Certification (prestige)**: needs the Air Cannon and a best score of 3,000.
  - Resets coins, upgrades and the two unlockable machines.
  - Keeps records, achievements, cosmetics, settings and facility access.
  - Grants Lab Credits (+5% coins each, up to +100%).
  - The confirmation lists exactly what resets.
- **Facilities**: three more are built and playable (see [Facilities](#facilities)). Each
  unlocks with a real requirement **and** a one-time coin price, both checked on the
  server. The Space Launch Facility is the only one still "under construction".

### Facilities

All four are built at server start, 4,000 studs apart (so they can never interact). Each
has its own deck and pads (your unlocked machines and upgrades work everywhere), course,
objectives, bounds, run limits, scoring tuning, distance markers, lighting and ambient
sound. Every run is measured in its own course's local space.

| Facility | Unlock | Course | Special rules |
|---|---|---|---|
| Industrial Crash Lab (hub) | start | 540-stud arena, 14 objectives | - |
| Destruction Testing Zone | break 150 props + 6,000 coins | demolition yard: brick walls (each block a prop), crate towers, glass gallery, oil-drum stacks, crane with a swinging wrecking ball, rubble pit, dumpster; 14 objectives | **Combo**: breaks within 1.2 s chain; each break from the 2nd adds min(chain - 1, 8) x 12 points, capped at 500 per run |
| High-Altitude Launch Facility | 400 studs + Air Cannon + 20,000 coins | cliff-top deck over a 200-stud canyon: three rope bridges, ledges at three depths, hanging rings, a cliff-face and a cable-car target; 14 objectives | **Wind**: a gust every 0.7 s past Z 20, at most 12 st/s each and 36 st/s in total per run, deterministic per run seed. **Free-Fall Bonus**: 0.8 pts per stud dropped from the run's peak (15-240 studs) |
| Experimental Gravity Lab | 1 prestige + 30,000 coins | dark neon hall: two low-g fields, a gravity-flip column, three bounce fields, ceiling flip panels, floating rings; 12 objectives | **Low gravity**: inside a field, each body part of *that* dummy gets an upward VectorForce of mass x g x (1 - scale); `workspace.Gravity` never changes. A run ends after 7 s of continuous drifting in low-g (paid, not landed); 18 s time limit |
| Space Launch Facility | 3 prestiges | under construction | - |

- **Travel**: the server checks access, frees your pad, moves you and remembers where you
  are (you respawn there; anyone who falls off the High-Altitude mesa is put back on the
  deck). No travelling mid-launch.
- **Personal bests per facility** (`Stats["BestScore:<Id>"]`, `BestDistance:<Id>`), shown
  in the Facilities menu. Grades and the "vs last run" delta use the facility's own best.
  The global leaderboards stay global.
- **Featured objective**: picked from the facility you are in.
- **Daily challenges**: "Complete N runs in the <facility>", "Free-fall N studs" and
  "Chain an xN combo", offered only once you have unlocked that facility.
- **Lighting**: each client applies its facility's preset (sunny mountain, dusty orange
  floodlight, dark cyan/purple neon with restrained bloom). It is local to that player.
- **Debris**: fragments come from a reused pool that never holds more than 60 parts;
  props are prebuilt parts that are only hidden when broken.
- **Part counts** (harness): hub + Industrial Crash Lab 1,016, Destruction 479,
  High-Altitude 426, Gravity Lab 365 (2,286 total).

### Multiplayer
- Shared facilities, with clear pad ownership (one per player, one player per pad; pads
  are numbered across all four facilities).
- Dummies and debris never collide with players or with each other's dummies.
- Scores and rewards are tied to the run's owner.
- **Crash duels**: invite a player; each of your next runs counts, and the winner gets a
  bonus scaled to the *lower* score, so it can't be farmed.
- Two global leaderboards (OrderedDataStore, batched writes), with friends marked in the
  Lab Log.

### UI
- **HUD**: coins (exact on hover), machine, launch readiness, objective / next step,
  "upgrade available" badge, toasts, popups and announcements.
- **Juice (client-only, visual)**: live DISTANCE / HEIGHT (with peak) readout, "x3 COMBO!"
  counter in the tier colour, floating "+points" popups at the impact point, capped speed
  lines, landing dust, camera punch and shake scaled by impact tier, a short hit-stop on
  Massive hits (camera and effects only, never the physics), a 3-2-1 charge countdown with
  a per-machine wind-up line, and a NEW RECORD banner with confetti. Reduced Effects and
  Camera Shake settings turn these down or off.
- **Launch panel and results card**: per-line count-up, D-S grade stamp against your
  personal best, "+X% vs last run", records, next recommended upgrade, RETRY (R) and
  BACK TO SETUP. Screens under 500 px tall get a compact top-centre card that stays clear
  of the thumbstick and Jump button.
- **Menu**: Upgrades, Machines, Lab Log, Locker, Facilities, Settings and Help.
- **Tutorial**: six steps, each advanced by a real server event; skippable, replayable and
  saved.

### Sound
- Layered cues with five volume groups (Master, Music, Effects, Ambient, UI).
- Throttling: a minimum gap per cue plus a shared budget, so a pinball run doesn't turn
  into noise.
- 3D impact sounds by tier, plus 3D ambient emitters.
- Lobby and run music slots that fade.
- **No audio IDs are invented.** Every filled slot reuses an ID from DEAD AIR's checked list,
  and a unit test fails on any other ID. The polish pass filled `AirHiss`, `Whoosh`,
  `SoftLanding`, `Achievement` and `ChallengeDone` with pitched reuses; `Boing`,
  `MusicLobby` and `MusicRun` stay empty (see POLISH.md).

### Lighting
- Bright industrial daylight: warm sun, cool ambient, light Atmosphere, restrained bloom and
  colour grade.
- Spotlight towers over the arena, surface lights in the lobby, and neon accents on
  machines, rings and landing zones.

## Shop (optional, cosmetic only)

| Item | Type | Display price | Config key |
|---|---|---|---|
| Neon Dummy (skin) | Developer Product (permanent) | R$ 149 | `NeonDummy` |
| Fireworks Launch (effect) | Developer Product (permanent) | R$ 99 | `Fireworks` |
| Rainbow Trail | Game Pass | R$ 99 | `RainbowTrail` |

Other cosmetics are bought with **coins** or unlocked by **achievements**. Nothing sold
changes physics, scoring or rewards, and normal progression never needs Robux.

`ProductId` / `PassId` are **0** in `src/shared/Config/ShopConfig.lua` until you create the
items in Creator Hub. With an ID of 0, Studio grants the item for free and a live game says
"not available yet". Receipts are de-duplicated and saved before `PurchaseGranted`. A live
server returns `NotProcessedYet` if the profile can't persist or is mid leave-save.

## Phase reports

### Phase 1: Inspect and plan
- **Implemented:** a new project (no existing CRASH LAB code). Reused the reviewed patterns
  from this repo's other games: the session-locked DataService, the `_Studio` stores, the
  receipt handling, the Lune test harness, the selene std and the preview tools.
- **Files:** `default.project.json`, `selene.toml`, `roblox_min.yml`, `tests/compile.luau`,
  `tests/run.luau`, `tests/loader.luau`.
- **Remaining:** nothing.

### Phase 2: Core playable game
- **Implemented:** facility, Standard Launcher, ragdoll dummy, server launch physics,
  obstacles, run tracking, scoring, coins, HUD, reset / retry.
- **Files:**
  - `src/server/World/FacilityBuilder.lua`
  - `src/shared/DummyModel.lua`, `MachineModels.lua`, `Scoring.lua`, `Economy.lua`
  - `src/server/Services/LaunchService.lua`, `CrashService.lua`, `ScoringService.lua`,
    `PadService.lua`
  - `src/client/Controllers/LaunchController.lua`, `HudController.lua`
- **Tested:**
  - Unit: scoring maths, sample rejection, impact tiers / debounce / caps, settle / stuck /
    timeout, ring and landing geometry.
  - Harness: scripted flights through the real services.
- **Remaining:** real physics feel (Studio).

### Phase 3: Progression
- **Implemented:** upgrade shop (4 categories), machine progression, objectives, results
  screen, DataStore persistence.
- **Files:** `UpgradeService.lua`, `QuestService.lua`, `DataService.lua`,
  `ResultsController.lua`, `MenuController.lua`, `Config/*`.
- **Tested:**
  - Unit: prices, every upgrade level changes something, clamping, machine requirements
    reachable.
  - Harness: upgrade, then a faster and longer run; unlocks; records; session lock;
    receipts.
- **Remaining:** balance tuning with real players.

### Phase 4: Presentation
- **Implemented:** lighting, sounds, machine animations, follow camera, impact feedback,
  destructibles, UI polish, previews.
- **Files:** `Main.server.lua`, `AudioController.lua`, `EffectsController.lua`,
  `CameraController.lua`, `CourseService.lua`, `Ui.lua`, `tools/*`.
- **Tested:**
  - Harness: animation maths, the camera follow frame, every client controller renders.
  - Preview renders of the facility, deck, course, lobby and catalog, which caught a
    camera-blocking booth and backwards ramps (both fixed).
- **Remaining:** listening tests; how the effects look in the real engine.

### Phase 5: Replayability
- **Implemented:** achievements, daily challenges, personal records, leaderboards,
  additional machines, the facility unlock framework, prestige, codes, crash duels,
  cosmetics.
- **Tested** in the harness: each of these rewards exactly once; dailies reset on a new UTC
  day; prestige resets exactly what it says.

### Phase 6: Multiplayer and QA
- **Tested** in the harness:
  - two players launching at once, with isolated runs and rewards;
  - a player leaving mid-run or mid-charge;
  - out-of-bounds, timeout and broken-rig endings;
  - anti-teleport;
  - spam and junk remote arguments;
  - the debris cap.
- **Fixed during QA:** the debris cap counted bursts instead of parts; pads stood the owner
  facing backwards; the ramps and the deck ramp were rotated the wrong way round; the
  control booth was moved off the camera line.
- **Remaining:** see the Studio checklist below.

### Facilities phase
- **Built**: the Destruction Testing Zone, the High-Altitude Launch Facility and the
  Experimental Gravity Lab (see [Facilities](#facilities)), plus unlock + travel, per-facility
  bests, lighting presets, facility dailies and achievements, a fragment pool and a
  player-only wall collision group. The world builder was split into `World/Kit` (shared
  pieces) and `World/Facilities/*`.
- **Fixed on the way**: debris fragments copied the *broken* prop's transparency (1), so
  they were invisible; they now use the prop's normal look.
- **Tested (harness)**: unlocking each facility (requirement enforced, coins taken once,
  refused when short); travel there and back; a scripted run in each facility: wind gusts
  capped and deterministic, free-fall bonus, per-facility out-of-bounds (100 studs down
  the canyon is fine, below it isn't), destruction combo capped at 500 and reset after the
  window, fragment pool capped and reused, low-g force on inside a field / off outside /
  removed after the run, bounce and flip contacts, the drift limit, `workspace.Gravity`
  untouched; per-facility personal best saved; the Facilities menu and lighting presets.
- **Tested (unit)**: gust determinism and caps, gravity volume lookup and lift force,
  combo and free-fall maths, per-course run limits, facility dailies, per-facility bests,
  and that every course's objectives, cues and unlocks are real.
- **Not tested here**: physics. Whether the wind feels fair, how low-g and bounce fields
  move a real ragdoll, and whether a max-power launch tunnels through any wall all need
  Studio.

### Polish pass
- **Juice:** live readout, combos, score popups, speed lines, dust, tiered camera punch,
  Massive hit-stop, charge countdown and wind-up, record banner and confetti (all
  client-side, all respecting Reduced Effects / Camera Shake).
- **Results:** count-up, grade stamp, delta vs last run, RETRY (R) / BACK TO SETUP,
  compact phone layout. The server computes `grade` and `delta` (`src/shared/Grades.lua`).
- **Fixes:** moving targets now get an `AssemblyLinearVelocity` matching their motion
  (`src/shared/Motion.lua`); prestige needs the score requirement again every cycle
  (`Stats.CycleBestScore`); a machine unlocked mid-launch says it will be selected after
  the run and is selected when the run is cleaned up.
- **Visuals:** lane lines, centre dashes, keep-out edges and distance numbers on the
  arena floor; scuffs and tyre marks from thin parts; more deck hazard stripes; a warm
  work-light bar over the deck; a walkway with chevrons from the lobby to an overhead
  LAUNCH DECK sign; calmer Air Cannon beacon light. Previews re-rendered and checked (the
  lobby chevrons were pointing the wrong way and were flipped).
- **Tested:** prestige per-cycle requirement, grade / delta thresholds, velocity as the
  exact derivative of target motion (unit); movers' velocity after `CourseService.step`,
  mid-run unlock queue, compact results layout, countdown / combo / speed-line maths and
  the record banner (harness).
- **Not tested here:** how any of it feels. Hit-stop length, shake strength, popup
  readability and the compact card on a real phone need a look in Studio.

## Saving

Profiles live in `CrashLab_Profiles_v1` (and `_Studio` when in Studio). Each profile holds:
coins, upgrades, machines, the selected machine, facilities, stats and records,
achievements, dailies, prestige, tutorial, settings, cosmetics, the last launch settings,
codes and receipts.

Key safety features:
- **Session lock:** a server only writes a profile it holds the lock for.
- **Validated loads:** everything loaded is clamped, and unknown keys are dropped.
- **Migration before defaults.**
- **Regular saves:** autosave every 60 s, on leave (with retries), and in parallel during
  BindToClose.
- **Nothing before data is ready:** no launches, purchases or rewards until the profile
  is loaded.

### Save / load test plan (in Studio)
1. Publish the place. In **Game Settings, Security**, turn on **Enable Studio Access to API
   Services**. Studio play-tests then use the `_Studio` stores, so your live data is never
   touched.
2. Play: launch, buy an upgrade, unlock something, change a setting, finish a daily. Note
   your coins and records. Stop.
3. Play again and check that everything is restored. In the Output window there should be
   no "saving is unavailable" notice.
4. Test the session lock: start a 2-player local server, leave with one player and rejoin
   quickly. Progress must not roll back.
5. Test a failed load: turn API access off, play, and check that the "saving unavailable"
   notice appears and nothing persists.

## IDs and assets you must provide

- **Shop IDs:** Developer Product IDs for `NeonDummy` and `Fireworks`, and the Game Pass
  ID for `RainbowTrail`, in `ShopConfig.lua`.
- **Audio:** 5 empty slots: `Boing`, `BounceField`, `TransitWhoosh`, `MusicLobby`,
  `MusicRun`, plus any reused or pitched placeholder you want to replace (see POLISH.md).
- **Icon and thumbnails:** see the ComfyUI prompts in POLISH.md.
- **Publishing:** publish the place and enable API access to use DataStores and
  leaderboards.

## Studio testing checklist

**Physics (couldn't be verified here):**
- [ ] The dummy ragdolls stably: no jitter at rest, no limbs exploding, joints look natural.
- [ ] Launch feel at each power and angle: Standard reaches about 55 studs on the first
  launch, Spring skims and slides, Air Cannon lobs high.
- [ ] Bounce pads bounce, ramps kick, the panel wall bounces a Standard dummy and breaks
  under a Reinforced one.
- [ ] Impact counts look right (Touched fires on real contacts, not on resting jitter).
- [ ] The run ends promptly when the dummy rests. A stuck or wedged dummy ends within 4 s.
- [ ] A dummy never escapes the arena; out-of-bounds ends the run.
- [ ] Moving targets register hits and debris behaves (falls, despawns, never blocks).

**Physics risks found in review, most likely first. Watch these in Studio:**
1. Fast dummies tunnelling through nets. The side nets are now 4 studs thick and the catch
   net 6 studs. If a max-power launch still passes through, thicken them again in
   `FacilityBuilder.lua`.
2. High lobs crossing the side nets. The nets now reach 130 studs and the out-of-bounds
   ceiling is 320, while the top Air Cannon arc peaks at about 251.
3. Ragdoll stability at Chaos spin (about 13 rad/s), and knees and elbows bending 70° in
   every direction.
4. Moving targets are CFramed every frame. They now carry a matching velocity so contacts
   should push rather than fling; confirm in Studio.
5. Whether the camera sensitivity setting (`MouseDeltaSensitivity`) has a noticeable effect.
6. The compact results card (screens under 500 px tall) is laid out to clear the Jump
   button; confirm on a real phone or the device emulator.

**Gameplay and UI:**
- [ ] The first launch comes within a minute and the first upgrade within a few minutes.
- [ ] The follow camera is smooth and skippable, and it returns to the player afterwards.
- [ ] The launch panel works with mouse, touch (drag the power bar) and gamepad.
- [ ] Menus fit phone, tablet and 4:3 screens; nothing overlaps Roblox's Jump button.
- [ ] Settings apply and persist, and volume groups behave.
- [ ] Every button does something, and insufficient funds shows red.

**New facilities:**
- [ ] Travel from the hub gate / menu and back with each HUB TRANSIT kiosk; respawning
  keeps you in the facility; you can't walk off the High-Altitude mesa.
- [ ] High-Altitude: gusts are noticeable but fair; long falls don't trip the anti-teleport
  check (it allows 1.35x speed there); dummies settle on the ledges and bridges.
- [ ] Destruction: walls and towers break satisfyingly with only a few fragments; the
  wrecking ball pushes rather than flings.
- [ ] Gravity Lab: dummies float in the fields and fall normally outside; the flip column
  lifts them to the ceiling and the flip panels let them drop; bounce fields launch them;
  nothing drifts forever (7 s limit).
- [ ] Lighting switches when you arrive and back when you leave; bloom stays controlled
  in the Gravity Lab.

**Multiplayer:**
- [ ] Two to four players launch at once without blocking each other.
- [ ] Duels work end to end.
- [ ] Server performance holds with six dummies and debris in the air.

## Tests

```bash
cd crash-lab
selene src                         # lint
lune run tests/compile             # compile every file
lune run tests/run                 # 38 unit tests
rojo build -o build/CrashLab.rbxlx && lune run tests/harness build/CrashLab.rbxlx   # 32 checks
lune run tools/export_preview build/CrashLab.rbxlx build/preview.json && node tools/render_preview.mjs build/preview.json build/
```

The harness loads the built place and runs the real modules against Lune's
reflection-checked Instance API, with stubbed engine services. Physics is not simulated:
flights are scripted trajectories fed through the real server code.

## Maturity

Cartoon slapstick with no blood, gore or injury: crash-test dummies just tumble. This
should fit **Minimal / Mild** (all ages or 9+). Roblox assigns the final label from your
questionnaire answers.

## Layout

```
src/shared/            configs + pure logic (Economy, Scoring, Progress, Hazards, Grades, Motion) + LightingPresets + models (DummyModel, MachineModels) + Net
src/server/World/      FacilityBuilder (hub + Industrial Crash Lab), Kit (shared pieces), Facilities/ (Destruction, HighAltitude, GravityLab)
src/server/Services/   Data, Upgrade, Pad, Launch, Crash, Course, Scoring, Quest, Duel, Shop, Player, Leaderboard, Analytics, RateLimit
src/client/Controllers ClientState, Audio, Camera, Input, Launch, Hud, Results, Juice, Effects, Tutorial, Menu, Lighting, Ui
tests/                 unit specs, compile check, headless harness
tools/                 preview export (Lune) + render (three.js / Playwright)
```
