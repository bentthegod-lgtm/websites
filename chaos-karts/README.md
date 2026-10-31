# CHAOS KARTS

*Drift. Boost. Survive the chaos.*

CHAOS KARTS is a chaotic multiplayer kart racer for Roblox. Up to 12 players race 3 laps (about 4–5 minutes) through **Chaos City**. Bots fill the empty grid slots. Drift through corners to charge blue, orange and purple mini-turbos. Leap between rooftops, dive under the river and fly off the big jump. Meanwhile the city itself goes wrong around you: a giant rubber duck in neon sneakers parades across the road. On the **final lap the chaos gets turned up**.

This folder is **Stage 1** of 7: the core race, the driving, the Chaos City track and the Event Director architecture.

> **Honest status.** This is a Rojo project. It has **never been opened or played in Roblox Studio**, because there is no Studio here.
>
> **Verified headlessly, in Lune:**
> - `selene src`: 0 errors, 0 warnings.
> - All 94 `.lua` files compile.
> - **44 unit tests** pass. They cover:
>   - KartPhysics: acceleration curve, top speed, braking and reverse, speed-sensitive steering with slide, the 3 drift levels and their boosts, wall glances, slopes, air time and landing squash, kickers, pads, off-road, determinism, KartEffects, the start boost and bumps.
>   - Every vehicle uses the same physics and the same hitbox.
>   - The track: spline continuity, widths, closed loop, real elevation, checkpoints covering the lap, and shortcuts that still cross their checkpoints. The Rooftop Leap fails at top speed and works with a boost.
>   - Laps and positions, the skip and wrong-way rules, and rewards.
>   - Every Event Director rule, and the 35-event catalog.
>   - Config sanity, the audio-ID whitelist, the shop and the item odds.
> - **21 harness checks** pass. The harness loads the Rojo-built place and runs the real server and client modules against Lune's Roblox instance model. Engine services are stubbed and the clock is fake. `workspace:Raycast` is answered from the analytic track. It checks:
>   - The timed, chunked world build (about 5,300 parts) and that the built road matches the analytic track.
>   - Lobby → portal pad / READY → bots fill the grid → countdown → race.
>   - **6 bots and a client-sim player finish 3 laps** on the real KartPhysics, with laps of **85.0–87.6 s** (target window 80–95 s).
>   - The speed-hack teleport-back (including small hops farmed at a high send rate, and creeping off the grid), an honest burst after a lag spike, a checkpoint skip, respawn with rate limit and ghost, wrong way, the 30 s DNF timer, and results saved to the profile.
>   - A late joiner spectating and then racing, and leaving mid-race.
>   - The reference event end to end: synced, hitting a bot and a player, cleaned up, plus the hard timeout.
>   - The final-lap scheduler, the lobby auto-start clock, receipt de-dupe, the session lock, junk remotes, settings, daily rewards and codes.
>   - **Every client controller running a real race against the real server through bridged remotes**: kart physics on raycasts, start boost, drift sparks, tire marks, HUD, minimap, camera modes, event playback, spectating, results and every menu tab.
>
> **Not verified (needs Studio):** how the driving *feels* at 60 fps with real input, how well the camera and network smoothing work over real latency, what Roblox's renderer and lighting make of the city (the previews are three.js approximations), welds and `LocalTransparencyModifier` at runtime, mobile layout on real phones, and real DataStores and purchases. **Follow the Studio test plan below.**

## Quick start

```bash
cd chaos-karts
rojo build -o build/ChaosKarts.rbxlx      # open it in Roblox Studio and press Play
# or live-sync: rojo serve                (then Connect in the Rojo Studio plugin)
```

1. Open `build/ChaosKarts.rbxlx` in Studio.
2. **To test saving:** go to Game Settings → Security and turn on *Enable Studio Access to API Services*. Without it the game still runs and tells you saving is off.
3. Press **Play** (solo). You spawn in the lobby. Walk into the **RACE PORTAL**, or press **READY**. Bots fill the grid, so you race 8 karts solo.
4. For multiplayer: **Test → Clients and Servers** with 2–4 players.
5. Studio uses separate `_Studio` DataStores, so test saves never touch live data. Robux items with an ID of 0 are free in Studio.

## Controls

| Action | Keyboard | Gamepad | Mobile |
|---|---|---|---|
| Gas | **W** / Up | **RT** | **GAS** |
| Brake / reverse | **S** / Down | **LT** | **BRAKE** |
| Steer | **A D** / Left Right | left stick | **< >** buttons (or the slider stick: Settings) |
| Drift / hop (hold while turning) | **Shift** or **Space** | **RB** (or A) | **DRIFT** |
| Respawn at the last checkpoint | **R** | **Y** | **RESPAWN** |
| Item (Stage 3; wired as a stub) | **F** | **X** | **ITEM** |
| Menu | **M** | Select | **MENU** |
| Spectate: previous / next kart | **Q / E** | DPad left / right | < > on the spectate bar |

**Drifting:** press drift while steering to hop. Land still holding drift and steering, and you slide. Keep holding to charge the sparks: blue, then orange, then purple. Steering *into* the drift charges faster. Release for a mini-turbo of 0.5 / 0.95 / 1.45 s.

**Start boost:** press gas in the last ~0.35 s before GO. Pressing too early (holding from more than 1.25 s out) stalls you.

## How a race plays

1. **Lobby.** The lobby has the race portal pad, a READY button, two leaderboards (Most Wins, Fastest Lap), a showroom with both karts, and kiosks for the Garage, Shop, Daily reward and Codes. The race starts when everyone present is ready, or 20 s after the first player readies. Up to 12 players race; bots fill the grid up to 8 karts (`GameConfig.Bots`, on by default).
2. **Countdown.** A camera flyover of the grid, then the 3-2-1-GO lights on the HUD and on the start gantry. Gas at the right moment gives a start boost.
3. **The race.** 3 laps of Chaos City (about 7,300 studs a lap):
   - the downtown straight with neon skyscrapers;
   - the 22° **Big Banked Bowl**;
   - the **Skyline Highway**, which climbs to 40 studs and crosses *over* the north leg;
   - the **River Tunnel** under the river (–25);
   - the stadium bulge;
   - the **river bridge** and the **BIG JUMP**, then *under* the highway;
   - the S-curve chicane and the hairpin.

   There are two shortcuts:
   - **Rooftop Leap**: up onto the parking garage roof and over a gap to the pit. It needs a boost.
   - **Neon Alley**: a narrow brick alley with dumpsters and slime puddles. It is shorter but risky.
4. **World events.** Events start after a 15 s grace period. In Stage 1 that is *Quackaroni's Sneaker Parade*. On the final lap events come faster, and the big intensity-3 events unlock (from Stages 4–5).
5. **Finish.** After you cross the line the camera orbits your kart. The first finisher starts a **30 s DNF timer**. Then come the results: placings, times and best laps, plus coins and XP into your profile. Then everyone goes back to the lobby.

Late joiners **spectate** (cycle the karts with Q / E) and are queued for the next race.

## Systems and how they talk

```
                      SERVER (authoritative)                                CLIENT
 ┌──────────────────────────────────────────────────────┐     ┌──────────────────────────────────────┐
 │ RaceService   lobby queue · grid · countdown · laps   │     │ KartController  YOUR kart:            │
 │               (RaceMath: ordered gates, ranking,      │◄────│  input → KartPhysics (fixed 1/60 s)    │
 │               wrong way, DNF, results, rewards)       │ Kart│  vs WorldQuery raycasts → chassis CF   │
 │ KartService   validates KartState (types, rate,       │State│  → KartState 20 Hz                     │
 │               SPEED SANITY → KartCorrect teleport-    │20 Hz│ RemoteKarts  everyone else: 100 ms     │
 │               back), rebroadcasts Karts 15 Hz ────────┼────►│  buffer, Hermite interpolation         │
 │ BotService    bots: same KartPhysics + BotBrain vs    │Karts│ CameraController chase/intro/orbit/... │
 │               the analytic TrackQuery, bumps          │15 Hz│ EffectsController sparks, marks, shake │
 │ EventDirector EventRules picks → module.serverStart / │     │ EventController plays events from the  │
 │               serverStep / serverStop, Maid + timeout │────►│  server clock (EventStart / EventStop) │
 │ KartEffects   spinOut/slow/launch/freeze/knockback/   │────►│ KartEffect → applied to your kart      │
 │               respawnToCheckpoint (never eliminate)   │     │ HudController · MenuController · Audio │
 │ Data/Shop/Reward/Leaderboard/PlayerService            │     │ InputController (kbd / pad / touch)    │
 └──────────────────────────────────────────────────────┘     └──────────────────────────────────────┘
        shared (ReplicatedStorage.ChaosKarts): KartPhysics · KartStats · TrackMath · MapData ·
        TrackQuery · RaceMath · EventRules · Events/* · Vehicles/* · VehicleModels · BotBrain · Net
```

- **Client-predicted karts.** Each driver's client runs the pure `KartPhysics` for its own kart. The kart is a kinematic CFrame on one invisible, anchored `Chassis`. The cosmetic model is welded on, massless, with CanCollide off.
  - The server never trusts the result blindly. Every move spends from a travel budget that refills at `KartStats.MaxLegalSpeed` (with slack, plus extra right after a KartEffect launch) and banks at most `AntiCheat.MaxDt` seconds; a move it can't cover is rejected. The Ghost flag is set by the server, never the client. The client is then teleported back to its last accepted state, and further updates are ignored until it comes back.
  - Checkpoints only count in order.
  - Respawns are rate-limited (2.5 s).
- **One ground interface.** `KartPhysics.step(state, input, ground, dt)` asks `ground:ground(probe)` under its 4 wheel points and `ground:walls(pos, radius)` for walls.
  - In the game, `client/WorldQuery` answers with `workspace:Raycast` against `Track/Ground` and `Track/Walls`. Their parts carry `Surface` and `Course` attributes.
  - Bots, the server and the tests use the analytic `TrackQuery`, built from the same data the `TrackBuilder` builds parts from.
- **Identical physics.** Every kart uses `Config/KartStats`. A unit test fails if any vehicle definition, or any shop item, contains a physics-like key. All chassis use the same `KartStats.Hitbox`.
- **Event sync.** The server sends `EventStart{instanceId, id, seed, warnAt, serverStartTime, endAt, zone}`. Every client computes the same positions from `(seed, zone, track, server time)`. Only the server resolves hits, and they go through **KartEffects**.
- **Fast startup.** The lobby is built at once. The track and city (about 5,300 parts) are queued as plain spec tables and created **350 parts per Heartbeat** (`World.PartsPerStep`), about 15 frames. The harness times every step.
- **Data.** `DataService` has:
  - a session lock (UpdateAsync, a stale lock is taken over), with migration before defaults;
  - validation of every saved field, `_Studio` stores, autosave, save on leave and on BindToClose;
  - `LEAVE_HOOKS`, so the race cleans up before the save.

  `ShopService` records receipts in the profile and saves *before* returning PurchaseGranted. A retry while that save is still in flight is not acknowledged early. Leaderboards use OrderedDataStores for Wins and the Chaos City best lap (in ms, ascending).

### Files

```
src/shared/   KartPhysics, Config/KartStats (THE physics table), Config/GameConfig, AudioAssets,
              ShopConfig, PowerUps · TrackMath (spline) · MapData (compiles a map) ·
              TrackQuery (analytic ground) · Maps/ChaosCity · RaceMath · BotBrain · EventRules ·
              Events/Registry + 35 event modules (EventBase, QuackaroniParade = reference) ·
              Vehicles/Registry + one module per vehicle · VehicleModels · ItemOdds · Maid ·
              Net · Parts · Progress · Format · Rng · Signal
src/server/   Main.server · World/ (World, BuildJob, TrackBuilder, CityBuilder, LobbyBuilder) ·
              Services/ (Data, Shop, Reward, Player, KartEffects, Kart, Bot, EventDirector,
              Race, Leaderboard, RateLimit)
src/client/   Main.client · Controllers/ (ClientState, Ui, Input, WorldQuery, KartController,
              RemoteKarts, Effects, Camera, Spectate, Event, Hud, Menu, Audio, FrameLoop)
tests/        run.luau (+ *.spec.luau), compile.luau, harness.luau, loader.luau
tools/        export_preview.luau, render_preview.mjs, store_art.mjs (three.js previews)
```

## The 35-event catalog (all planned; 1 live in Stage 1)

These names were chosen after a per-character IP and policy check (`docs/IP-CHECK.md`). Real brainrot meme names are used only where no owner or filing was found. Characters with registered trademarks or active disputes get a **parody name and a clearly different design**. No real people, politicians, aircraft, flags or places appear.

- **Brainrot and meme (25):**
  - **Quackaroni's Sneaker Parade** (live)
  - Bonk Bonk Bonko (a log-drum chaser)
  - **Bombardiro Crocodilo** (bombing run)
  - **Lirilì Larilà** (slow-time bubble)
  - **Bombombini Gusini** (goose dive-bombers)
  - **Trippi Troppi** (pogo bounce)
  - **Frigo Camelo** (freeze breath)
  - **La Vaca Saturno Saturnita** (low gravity)
  - Squalo Scarpalino (a sneaker shark)
  - Espressina Piroetta (a pirouette spin-out)
  - Frr Frr Patapum (root hurdles)
  - Gorillini Mangini (mango barrage)
  - Espresso Ninjetto (coffee puddles)
  - Toaster Downpour, Mega Burger Roll, Cactus Conga, Loaf Cat Spin, Pigeon Mafia, Disco Banana Fever, Rubber Chicken Choir, Spaghetti Tornado, Mime Wall, Sofa Stampede, Pancake Flipper, Turbo Snail
- **Fiction-style, original characters (5):**
  - **GORGANTOR** (our own giant monster)
  - **Blaze: MEGA WAVE** (an anime-style energy beam down one lane)
  - Mecha Sentinel, Sword Saint Slash, Wizard Duel
- **Disasters (5):**
  - **The Mayor's Missile Alert** (a fictional mayor's emergency broadcast plus cartoon missiles)
  - **Jet Strafing Run** (generic cartoon jets)
  - **MEGA BOMB** (a cartoon shockwave)
  - **Giant Meteor Shower**
  - City Quake

Each event is one module in `src/shared/Events/` with its rules: intensity, weight, warning time, tags, conflicts, minimum lap, final-lap boost, zone tags, lanes blocked and effects. The Event Director already enforces every rule for all 35.

## How to add …

### a vehicle (Stage 2 adds 23 more: see `Vehicles/Registry.PLANNED`)
1. Copy `src/shared/Vehicles/Sparkplug.lua` to `src/shared/Vehicles/<Id>.lua`.
2. Set `Id`, `Name`, `Rarity`, `Colors`, and build the body in `Build(b)` with `b:box / b:wedge / b:ball / b:cylinder / b:wheels / b:driver`. Local space: y = 0 is the chassis centre, the ground is at y = –1.4, and –Z is the nose. Keep it under about 60 parts.
3. Add the Id to `Registry.ORDER`.
4. **Never add physics.** No speed, handling, weight or size fields: the test `Vehicles: every vehicle definition has NO physics overrides` fails if you do. Every vehicle drives with `KartStats` and the same hitbox.
5. Run `lune run tests/run` and `lune run tests/harness build/ChaosKarts.rbxlx`. The showroom and the Garage tab pick the new kart up automatically.

### an event (Stages 4–5 implement the other 34)
1. Open its stub in `src/shared/Events/<Id>.lua`, or add a new file and an entry in `Events/Registry.ORDER`.
2. Replace `EventBase.stub{...}` with a full module, using `QuackaroniParade.lua` as the template:
   - `Def` (keep the catalog fields; set `implemented = true`);
   - `Sounds` (Warning / Entrance / Attack / Impact / Exit; `Id = ""` is fine);
   - `serverStart(ctx)`, `serverStep(ctx, dt)`, `serverStop(ctx)`;
   - `play(ctx)`, `step(ctx, dt)`, `cleanup(ctx)`.
3. Rules:
   - Compute everything visible from `(ctx.seed, ctx.zone, ctx.data, ctx.now())` so clients stay in sync.
   - Touch karts **only** through `ctx.hit(racer, kind, params)` with `spinOut / slow / launch / freeze / knockback / respawnToCheckpoint`. Never eliminate.
   - Put every part and connection in `ctx.maid`. The director cleans it at the end and at the hard timeout.
   - If it blocks lanes, tag it `blocks-lane` and set `blocksLanes`. EventRules always leaves a lane free.
   - Set `zoneTags` to the kinds of map zones it can use.
4. Test it in Studio from the command bar: `require(game.ServerScriptService.ChaosKartsServer.Services.EventDirector).trigger("<Id>", "<ZoneId>", true)` during a race.
5. Add a harness check modelled on the reference-event one.

### a map (Stage 6: Supermarket, Volcano Island, Space Madness)
1. Copy `src/shared/Maps/ChaosCity.lua` to `Maps/<Id>.lua` and define:
   - `Track.points`, each `{x, y, z, w, bank, sh, wl, wr, tags}`;
   - `Shortcuts`, `Checkpoints` (by control point), `BoostPads`, `Kickers` and `ItemRows`;
   - `Zones` (with lanes and tags), `Floor` rects (with holes), `KillY`, `Lobby` and `Grid`.
2. Lap pace is roughly track length ÷ 84 studs/s. Tune the length or the layout, not `KartStats`.
3. Run `lune run tests/run`. The track spec checks continuity, checkpoints vs shortcuts, the grid, pads, zones, and that every event has a zone. For a new map, point the specs at it (or parameterize them).
4. Map-specific scenery goes in a builder like `CityBuilder`. Set `GameConfig.Race.Map` (a map vote arrives in Stage 6).

## Roadmap (content targets unchanged: 25 vehicles, 12 power-ups, 35 events, 4 maps)

| Stage | Scope | Status |
|---|---|---|
| 1 | Core race + driving + Chaos City + Event Director architecture (all 35 events catalogued, 1 reference event live) | **this build** |
| 2 | All **25 vehicles** (cosmetic only, identical physics). 2 placeholder karts exist; 23 more are named in `Vehicles/Registry.PLANNED` | planned |
| 3 | All **12 power-ups**: Homing Missile, Nuclear Bomb (cartoon), Mega Wave beam, Black Hole, Meteor Strike, Lightning, Giant Boxing Glove, Freeze Ray, Banana Bomb, UFO Abduction, Speed Boost, Force Field. Item rolls are position-weighted and never guaranteed (`ItemOdds`, already tested). Item box spots are already placed (`Track/ItemSpots`) | planned |
| 4 | World events part 1: the **25 brainrot / meme** events (1 done) | planned |
| 5 | World events part 2: **5 fiction-style** (original characters) + **5 disasters**: **all 35 live**, with the final lap running hotter | planned |
| 6 | **4 maps**: Chaos City (done), Supermarket, Volcano Island, Space Madness; map vote | planned |
| 7 | Polish + the cosmetic shop (no pay-to-win: nothing sold can touch `KartStats`) | planned |

## Studio test plan (driving feel first)

Do this before anything else. Driving is the whole game.

1. **Solo race** (Play): bots on, 3 laps. Write down how each part feels:
   - **Launch:** is 0 → top speed in about 2.5 s punchy enough? Is the start-boost window (0.35 s) findable?
   - **Straights:** does 80 studs/s feel fast with the camera FOV kick and speed lines? Lap pace should be 85–90 s.
   - **Turning:** is the speed-sensitive steering responsive without being twitchy? Is there a small slide at full lock?
   - **Drift:** hop, slide, sparks. Does each level arrive at a satisfying moment (0.7 / 1.45 / 2.25 s)? Does the purple boost *feel* big?
   - **Walls:** a shallow hit should glance and keep about 90 % of your speed. A head-on hit should bounce and turn, not stop dead.
   - **Air:** the Big Jump (about 1 s of air) and air control. Is the landing squash and shake readable without being annoying?
   - **Bowl and highway:** does the banking and the alignment to the slope look right? Is the climb noticeably slower?
   - **Off-road:** do grass and sidewalk shoulders punish without trapping you?
   - **Shortcuts:** can you make the Rooftop Leap with a level-2/3 mini-turbo released on the roof? Do you fall into the pit at plain top speed? Is the alley worth it?
2. **Network:** Clients and Servers with 2–3 players. Set *Incoming Replication Lag* to 0.15 s. Remote karts should glide, not jitter (the interpolation buffer is `GameConfig.Net.InterpDelay`). Bump each other. Drive into the wall at full boost: you must never get a false speed teleport (if you do, raise `GameConfig.AntiCheat.SpeedSlack`).
3. **Respawn:** press R; fall into the Rooftop Leap pit (auto-respawn); hold gas against a wall for 3 s (stuck → auto-respawn); land on the grass anywhere off the course (auto-respawn after 2.5 s); drive the wrong way (WRONG WAY warning).
4. **Events:** wait for Quackaroni (about 15–40 s in). Check the warning stripe, the waddle, the knockback, and that it disappears. Run it from the command bar (see *How to add an event*).
5. **Mobile:** use the Studio device emulator (a phone). Check the touch buttons, the slider stick (Settings), and that the HUD scales.
6. **Data:** enable API access and finish a race. Check the coins, XP, best lap, Daily, and the codes `RELEASE` and `CHAOS`. Rejoin and confirm it saved.

**Tuning knobs** (all in `src/shared/Config/KartStats.lua`, the same for every kart):

| Knob | Default | Effect |
|---|---|---|
| `TopSpeed` | 80 | pace (re-check bot lap times: the harness asserts 80–95 s) |
| `Accel`, `AccelCurve` | 70, 2.2 | launch punch and how quickly it tapers |
| `TurnRateLow` / `TurnRateHigh` | 2.55 / 1.55 rad/s | steering at low speed and at top speed |
| `SteerResponse` | 11 | how fast steering reacts (higher = twitchier) |
| `Grip`, `GripTransfer` | 9, 0.7 | how planted the kart is, and how much speed turns keep |
| `DriftBaseTurn`, `DriftSteerRange`, `DriftGrip` | 1.25, 0.8, 2.4 | drift tightness, control and slide |
| `DriftChargeLevels`, `DriftBoostTime` | {0.7, 1.45, 2.25}, {0.5, 0.95, 1.45} | mini-turbo timing and reward |
| `BoostTopMul`, `BoostAccel`, `PadBoostTime` | 1.32, 150, 1.1 | how strong boosts are |
| `Gravity`, `HopVelocity`, `JumpLaunch`, `AirSteer` | 105, 13, 36, 1.2 | air feel |
| `OffroadMul` | 0.52 | grass / sidewalk slowdown |
| `WallKeep`, `WallMinKeep`, `WallRestitution` | 0.9, 0.45, 0.18 | wall glances |
| `SlopeGravity` | 0.5 | how much hills matter |

Camera (`GameConfig.Camera`): `Distance`, `Height`, `LookAhead`, `Smooth`, `BaseFov` / `BoostFov` / `SpeedFov`, and the shake amounts. Network (`GameConfig.Net`): `SendRate`, `BroadcastRate`, `InterpDelay`. Events (`GameConfig.Events`): the interval, the final-lap multipliers and the budget.

## Sound

Every slot is in `src/shared/Config/AudioAssets.lua`, plus each event's own `Sounds` table. IDs are **only** ones already used in this repo (DEAD AIR / LAST LIFEBOAT; a unit test enforces this). Slots with `Id = ""` are skipped until you add your own. Empty slots that matter:
- **`Engine`**: the code already pitches it from 0.7 to 1.6 with speed.
- `EngineRemote`, `DriftSkid`, `Checkpoint`, `Crowd`, `ItemRoll`.
- The parade's QUACK (`Attack`) and band (`Exit`).

## Shop setup (Stage 1: placeholders)

`Config/ShopConfig.lua` has two coin packs and two **cosmetic** passes (Neon Trails, VIP tag), all with ID 0. In Studio, Buy grants them for free; in a live game it says "not available yet". Before Stage 7: create each item in Creator Hub (Monetization → Developer Products / Passes) and paste its ID. The prices in the config are display-only. The coin packs are safe to sell (coins only buy cosmetics). **Nothing sold may touch KartStats** (enforced by a test).

## Publishing checklist

- [ ] Studio test plan passed (driving feel, network, mobile, data).
- [ ] Game Settings → Security: API access on (DataStores), and *Allow HTTP* off unless needed.
- [ ] Add your own audio for the empty slots (or accept silence); licensed IDs only.
- [ ] Replace placeholder art: icon, thumbnails (`icon-512.png` and `thumbnail-1920x1080.png` are three.js placeholders; see POLISH.md).
- [ ] Shop: create the products / passes, paste the IDs (or hide the shop tab until Stage 7).
- [ ] Max players 12 (set in `default.project.json`). Check the server size in Game Settings too.
- [ ] Maturity questionnaire: cartoon violence (karts get bonked, launched and spun; nobody is hurt), no blood, no realistic weapons, no gambling (no paid random items), no chat beyond Roblox's default, and no user-generated content.
- [ ] Codes `RELEASE` and `CHAOS` work; announce them on the game page.
- [ ] Publish to a private test place first and play 5+ full races with friends.

## Tests and tools

```bash
selene src                                          # lint (custom roblox_min std)
lune run tests/compile                              # every .lua compiles
lune run tests/run                                  # 44 unit tests
rojo build -o build/ChaosKarts.rbxlx
lune run tests/harness build/ChaosKarts.rbxlx       # 21 harness checks (~1 min)
# previews (Playwright + Chromium; set PLAYWRIGHT_MODULE if it isn't local)
lune run tools/export_preview build/ChaosKarts.rbxlx build/preview.json
node tools/render_preview.mjs build/preview.json build/     # VIEW=name renders one view
node tools/store_art.mjs build/preview.json .               # placeholder thumbnail + icon
```

Preview renders in `build/`:
- `preview-plan`
- `preview-start-gantry`, `preview-grid-karts`
- `preview-downtown-neon`
- `preview-highway-overpass`, `preview-highway-deck`
- `preview-river-bridge`
- `preview-banked-turn`, `preview-banked-turn-driver`
- `preview-big-jump`, `preview-big-jump-runup`
- `preview-shortcut-rooftop`, `preview-shortcut-rooftop-wide`
- `preview-shortcut-alley`, `preview-shortcut-alley-wide`
- `preview-tunnel`, `preview-tunnel-portal`
- `preview-statue`, `preview-parade`
- `preview-lobby`, `preview-karts-closeup`

## Known limitations (Stage 1)

- Only 1 of 35 events is implemented (by design); power-ups are a stub (F / ITEM says "Stage 3"). There are 2 of 25 vehicles and 1 of 4 maps.
- Bots always take the main racing line (no shortcuts), and their variety is behavioural only.
- Kart-to-kart contact on the server is a sanity check, not a simulation:
  - player karts push each other on each client;
  - the server bumps bots against everyone;
  - the speed check caps what a bump can do.
- Remote karts are rendered about 100 ms in the past. Close door-to-door racing can look a touch off at high latency.
- No real playtest has been done (see the honest status above). Feel values come from simulation and reasoning and need tuning in Studio.
