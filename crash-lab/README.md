# CRASH LAB

A multiplayer Roblox physics simulator: **build a machine, launch a dummy, cause an absurd
crash, earn coins, upgrade everything, try again.** Cartoon crash-test dummies, ragdoll
physics and stylised destruction, with no gore.

Everything (the facility, the machines, the dummies and the UI) is built from code in this
Rojo project. There are no imported models and no free-model scripts.

> **Honest status:** every check that can run in this environment passes (lint, compile,
> 24 unit tests, a 27-check headless harness on the built place, preview renders). **No
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
- **16 achievements**, some unlocking cosmetics.
- **3 daily challenges per UTC day**: targets are frozen from that morning's records, so
  they are always achievable, and no purchase is needed.
- **Codes**: `CRASHLAB`, `BUCKLEUP`.
- **Lab Certification (prestige)**: needs the Air Cannon and a best score of 3,000.
  - Resets coins, upgrades and the two unlockable machines.
  - Keeps records, achievements, cosmetics, settings and facility access.
  - Grants Lab Credits (+5% coins each, up to +100%).
  - The confirmation lists exactly what resets.
- **Facilities framework**: High-Altitude, Destruction Zone, Gravity Lab and Space Launch
  unlock through **real** requirements (checked and saved on the server). Their courses
  aren't built yet, so the gate says "under construction" instead of pretending.

### Multiplayer
- Shared facility, with clear pad ownership (one per player, one player per pad).
- Dummies and debris never collide with players or with each other's dummies.
- Scores and rewards are tied to the run's owner.
- **Crash duels**: invite a player; each of your next runs counts, and the winner gets a
  bonus scaled to the *lower* score, so it can't be farmed.
- Two global leaderboards (OrderedDataStore, batched writes), with friends marked in the
  Lab Log.

### UI
- **HUD**: coins (exact on hover), machine, launch readiness, objective / next step,
  "upgrade available" badge, live flight estimate, toasts, popups and announcements.
- **Launch panel and results card**: animated tally, records, next recommended upgrade,
  RETRY / CONFIGURE.
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
  and a unit test fails on any other ID. Empty slots are listed in POLISH.md.

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
- **Audio:** 8 empty slots: `AirHiss`, `Whoosh`, `SoftLanding`, `Boing`, `Achievement`,
  `ChallengeDone`, `MusicLobby`, `MusicRun`, plus any you want to replace (see POLISH.md).
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
4. Moving targets are CFramed every frame, so they can fling a dummy rather than push it.
5. Whether the camera sensitivity setting (`MouseDeltaSensitivity`) has a noticeable effect.
6. On phones under 500 px tall, the results card overlaps the Jump button.

**Gameplay and UI:**
- [ ] The first launch comes within a minute and the first upgrade within a few minutes.
- [ ] The follow camera is smooth and skippable, and it returns to the player afterwards.
- [ ] The launch panel works with mouse, touch (drag the power bar) and gamepad.
- [ ] Menus fit phone, tablet and 4:3 screens; nothing overlaps Roblox's Jump button.
- [ ] Settings apply and persist, and volume groups behave.
- [ ] Every button does something, and insufficient funds shows red.

**Multiplayer:**
- [ ] Two to four players launch at once without blocking each other.
- [ ] Duels work end to end.
- [ ] Server performance holds with six dummies and debris in the air.

## Tests

```bash
cd crash-lab
selene src                         # lint
lune run tests/compile             # compile every file
lune run tests/run                 # 24 unit tests
rojo build -o build/CrashLab.rbxlx && lune run tests/harness build/CrashLab.rbxlx   # 27 checks
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
src/shared/            configs + pure logic (Economy, Scoring, Progress) + models (DummyModel, MachineModels) + Net
src/server/World/      FacilityBuilder
src/server/Services/   Data, Upgrade, Pad, Launch, Crash, Course, Scoring, Quest, Duel, Shop, Player, Leaderboard, Analytics, RateLimit
src/client/Controllers ClientState, Audio, Camera, Input, Launch, Hud, Results, Effects, Tutorial, Menu, Ui
tests/                 unit specs, compile check, headless harness
tools/                 preview export (Lune) + render (three.js / Playwright)
```
