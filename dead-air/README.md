# DEAD AIR

A Roblox multiplayer (1–6 players) survival horror game. You explore a procedurally assembled
underground office complex, restore its systems, and escape in the service elevator, while
**The Listener** hunts you by sound.

> It cannot see you in the dark. It can hear everything.

## Build and run

This is a [Rojo](https://rojo.space) project. Everything, including the map, the monster and the UI,
is built at runtime from code. No external models or uploaded assets are required.

```bash
cd dead-air
rojo build -o DeadAir.rbxlx        # build a place file, then open it in Roblox Studio
# or live-sync into an open place:
rojo serve                          # then Connect from the Rojo Studio plugin
```

In Studio:

* **Solo:** press Play, then click **READY** in the lobby.
* **Multiplayer test:** go to Test → Clients and Servers, start a local server with 2–4 players,
  and ready up in each client.
* **Saving:** enable *Game Settings → Security → Enable Studio Access to API Services* to test
  DataStores. Without it the game still runs and tells the player that progress isn't saved.
* **Noise debugging:** in the server command bar run
  `workspace:SetAttribute("DeadAirDebugNoise", true)` to see every noise event as a sphere.
  The sphere's size is its radius and its colour is its loudness.
  `require(game.ServerScriptService.DeadAirServer.Services.MonsterService).debugState()`
  prints the Listener's recent state transitions.

### Audio

No Roblox asset IDs are invented. `src/shared/Config/AudioAssets.lua` uses either:

* Roblox's built-in `rbxasset://sounds/...` character sounds (re-pitched) as fallbacks, or
* empty slots that are skipped until you add audio you own or that the Creator Store marks
  as usable.

Gameplay detection never depends on audio files.

## Lobby

Players arrive in a surface-level staff reception between runs:

* **Service elevator "DESCENT"** on the north wall, with a hazard-striped **ready pad** in front.
  Standing on the pad readies you, and so does the READY button. When everyone is ready, a
  5-second countdown starts the run.
* **Status board** above the elevator showing the ready count, the countdown or "run in
  progress", and a **record board** showing the last run's outcome and the escape streak.
* **Specimen 01:** the real Listener rig, frozen in a glass cage under red light, so new
  players learn its silhouette before they meet it.
* **Footstep test floor:** carpet, tile and metal strips. Walk, sprint and crouch across them
  to hear how loud each surface is.
* **Briefing boards** covering sound, hiding and teamwork, plus a **practice locker** you can
  climb into.
* A **staff lounge** with couches, a vending machine and the spawn point.

## Playing with friends

The lobby has four party elevators: **SOLO (1)**, **DUO (2)**, **TRIO (3)** and **SQUAD (4)**.

* Walk onto an elevator's striped pad with your friends. The first player in is the
  leader and picks the difficulty.
* It leaves when it's full, or when everyone on it presses READY, after a 5-second
  countdown. That means two friends can take a Squad elevator without waiting for strangers.
* **In a published game**, each party is teleported to its own private (reserved) server,
  so several parties can play at once. When the run ends, everyone is teleported back to
  a lobby. Studio can't teleport, so there the run happens on the same server, and the
  elevators show "IN USE" until it ends.
* To test parties in Studio, use Test → Clients and Servers with 2–4 players.

## Robux shop (one-run boosts)

The lobby **SHOP** button sells boosts. You switch a boost "ON" and it's used up when your
next descent starts.

| Boost | Effect |
|---|---|
| Padded Soles | Footsteps 40% quieter |
| Second Wind | 50% more stamina, sprint drains 25% slower |
| Lithium Cell | Flashlight battery lasts twice as long |
| Lure Kit | Start with 2 tin cans and an alarm clock |
| Adrenaline Shot | Once per run, get back up on your own 6 seconds after going down (even solo) |
| X-Ray Goggles | See the Listener outlined in red through walls for the whole run |

**Setup:**
1. In Creator Hub, go to your experience → Monetization → Developer Products and create one
   product per entry in `src/shared/Config/ShopConfig.lua`.
2. Paste each product's ID into `ProductId`. Prices there are only shown in the shop UI; the
   real price is whatever you set in Creator Hub.

Until a ProductId is set, Buy grants that boost for free in Studio (for testing) and says
"not available yet" in the live game.

Purchases are handled through `ProcessReceipt`. Each purchase ID is saved with the profile
before the purchase is confirmed, so a purchase is never granted twice.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Sprint (crouch-run while crouched) | Hold Shift | L3 (toggle) | Run button (toggle) |
| Crouch (silent except on metal floors) | C / Ctrl (toggle) | B | Crouch button |
| Interact / hide / revive | E (hold where prompted) | X | Tap prompt |
| Flashlight | F | Y | Light button |
| Throw bottle | G | R1 | Throw button |
| Drop selected item | Q | D-pad down | Drop button |
| Select item | 1–5 | D-pad left / right | Tap slot |
| Leave locker | E / Space | A | Tap prompt |
| Settings | Tab | Select | ≡ button |

## Core loop

1. Ready up in the lobby. The host picks a difficulty: Easy, Normal, Hard or Nightmare.
2. The facility is generated from a seed: an 8×8 grid of rooms with loops, dead ends and
   three locked special rooms.
3. Each run picks one objective chain:
   * **Blackout Protocol:** keycard → electrical room → 3–4 fuses → main breaker → security
     override → elevator.
   * **Emergency Generator:** keycard → generator room → fuel cans → crank the generator
     → override → elevator.
4. The Listener arrives after a grace period. Doing objectives is loud. The breaker can be
   heard across the whole sub-level, and the elevator alarm keeps sounding until the car arrives.
5. Board the elevator to escape. A run ends only when nobody is left standing in the
   facility; there is no timer. You then get results and XP, and return to the lobby.

## Systems

* **Sound (server-authoritative):** `NoiseService` handles every footstep (gait × surface),
  jump, landing, door, drop, throw, objective action, revive, panting and black-box burst.
  Each noise has a category, position, loudness, radius and timestamp, plus modifiers for
  surface, room acoustics and crouching.
  * Hearing works in all directions (an area around the Listener), not only where it faces.
  * Occlusion is estimated with iterative raycasts that count walls, closed doors and large props.
    Walls only muffle sound; a walking step one wall away is still heard.
  * Noises that repeat close together are merged, and each player is rate-limited.
  * The monster receives only an *approximate* position, jittered more for distant or muffled
    sounds, and never the player's live position.
* **No eyes:** the Listener only senses players who are moving (or within ~4 studs). Standing
  still makes you invisible to it; noise still gives you away.
* **The Listener:** `MonsterBrain` is a pure state machine with these states: Patrol, Suspicion,
  Investigate, Search, CheckHiding, Chase, Attack, Lost (search after a chase) and Recover.
  `MonsterService` runs it in the world:
  * It sees within a field of view, with shorter range in the dark and longer range toward a
    lit flashlight.
  * Awareness builds over time, so a glimpse makes it suspicious but sustained exposure starts
    a chase.
  * Paths are recomputed on a throttle, and it pursues directly when it has line of sight.
  * It bursts through doors.
  * When stuck it repaths, then starts a new search, then, as a last resort, moves to a patrol
    point no player can see.
  * Its patrols lean toward places where noise was recently heard.
* **Hiding:** players can hide in lockers. The Listener checks lockers near its evidence. It
  finds you almost certainly if it watched you get in, and more often if you're panting
  because you hid while low on stamina.
* **Downed / revive:** in multiplayer a catch downs you instead of killing you. Teammates
  can revive you with a 4-second hold that the server enforces, before you bleed out.
  Nightmare difficulty turns this off.
* **Items:** keycards, fuses, fuel cans, bottles, batteries and an optional black box. The
  black box gives bonus XP but emits static the monster can hear. Dropping an item is noisy;
  crouch to set it down gently. Throw a bottle to lure the Listener away.
* **Horror events:** occasional, never during a chase:
  * lights failing;
  * a distant figure that only one player sees;
  * a door slamming behind you;
  * distant vocalisations;
  * footsteps behind you;
  * a pipe burst.
* **Progression:** XP and levels, statistics, collectible lore notes, and flashlight colours
  unlocked by level or by stats. Consecutive escapes add "pressure" that makes the next run
  harder. Shop boosts are paid, but they only help for one run and never stop the Listener.
* **Accessibility:** volume controls, sensitivity, field of view, brightness, head bob, camera
  shake, a photosensitivity "reduce flicker" mode, and large text.

## Layout

```
src/shared/            pure logic + configs (ReplicatedStorage.DeadAir)
  Config/              every tunable number: Map, Sound, Monster, Player, Difficulty,
                       Objective, Item, Audio, HorrorEvent, Progression, Lore
  MazeGen.lua          seeded layout generation (pure, tested)
  MonsterBrain.lua     Listener state machine (pure, tested)
  SoundMath.lua        propagation maths (pure, tested)
  ObjectiveChain.lua   objective progression (pure, tested)
  ItemModels.lua       procedural 3D model for every item (pickups, thrown items, HUD icons)
src/server/Services/   MapBuilder, DoorService, HidingService, ItemService, NoiseService,
                       PlayerService, MonsterService, MonsterModel, ObjectiveService,
                       HorrorEventService, RoundService, DataService
src/client/Controllers/ input, camera, HUD, menus, audio, effects, horror events,
                       procedural monster animation
tests/                 Lune test suites
```

## Tests

```bash
cd dead-air
lune run tests/run                                         # 43 logic tests
lune run tests/compile                                     # Luau compile check of every file
selene src                                                 # lint (roblox_min std)
rojo build -o build/DeadAir.rbxlx && lune run tests/harness build/DeadAir.rbxlx
```

The **harness** loads the built place in Lune and runs the real modules against Lune's Roblox
instance implementation, which checks every class and property name against the Roblox
reflection database. It:

* builds 30 facilities using both objective chains;
* builds the lobby (ready pad, boards, caged specimen, practice locker) and the Listener rig;
* wires up all services and sets up the objectives;
* sends real NoiseService events into the Listener's brain: a crouched step 30 studs away
  goes unheard, while a dropped metal object is investigated at an approximate position;
* builds every item's 3D model and checks the parts are welded, inside the pickup box and
  don't affect physics or raycasts;
* initialises every client controller and renders sample state.

Physics, pathfinding, tweens and players are stubbed.

## Status

These checks pass: unit tests, compile check, lint, Rojo build and the headless harness.

These have **not** been done, because no Roblox client was available in the build environment:

* a real play-test in Roblox Studio;
* checking game feel and difficulty balance;
* PathfindingService behaviour on the generated map;
* checking performance on mobile hardware.

Tuning values live in the `Config` modules. Expect to adjust monster speeds, hearing and
stamina after the first play-tests.
