# CHAOS KARTS — polish to-do (for the PC pass with Blender + ComfyUI)

Stage 1 is built entirely from parts. Everything below can be swapped without touching game logic.

The constraints:
- **Kart physics never depend on visuals.** Every kart is an invisible `Chassis` (`KartStats.Hitbox` = 5.4 × 2.6 × 8.4 studs). The cosmetic model is welded on, massless and CanCollide off.
- **The road is raycast.** Karts drive on whatever is in `Workspace.ChaosKartsWorld.Track.Ground` and bounce off `Track.Walls`. If you replace road or wall parts with meshes, keep them in those folders with the same `Surface` / `Course` attributes, and keep the surfaces where the track data says they are (the harness checks that the built road matches `TrackQuery`). Scenery (`Track.Deco`, `City`, `Lobby`) is free to change.

## 1. Meshes to model (Blender → MeshPart, low-poly, flat or soft shading, saturated colors)

| What | Where in code | Size (studs) | Style notes |
|---|---|---|---|
| **Sparkplug** kart body | `Vehicles/Sparkplug.lua` | fits 5.4 × 2.6 × 8.4 (+ the wing) | Classic go-kart: red tub, white racing stripe, yellow neon side pods, rear wing, twin chrome exhausts. Keep the wheel positions (wheels spin and steer via Welds) |
| **Bubblegum Bumper** body | `Vehicles/BubblegumBumper.lua` | same | Fairground bumper car: glossy pink shell, cyan rubber ring, pole antenna with a glowing tip, tail fin |
| **Driver** (shared) | `VehicleModels` `Builder:driver` | about 2 × 3.6 × 2 | Chunky cartoon racer: helmet with visor and stripe, gloves on the wheel. Tinted per racer (`driverColor`) |
| **Wheels** (2 sizes) | `Builder:wheels` | r = 0.95 / 1.15 | Fat tire + rim; separate so they can spin |
| **Big Toasty** statue | `CityBuilder.statue` | about 30 × 55 × 30 incl. pedestal | Original brainrot hero: a golden slice of toast with sunglasses and a grin, flexing both arms, neon butter "crown", marble pedestal and plaque |
| **Quackaroni** (event star) | `Events/QuackaroniParade.lua` `buildDuck` | about 20 × 36 × 22 | Giant rubber duck in neon high-top sneakers (one cyan, one pink), sunglasses, small gold crown. Rig for a waddle (the code sways and bobs the root) |
| **Toaster marching band** | `buildToaster` | 4 × 5 × 3 | Chrome toasters with a toast slice popping up, a little red drum, tiny feet |
| **Start / finish gantry** | `TrackBuilder` (Gantry*, LightBar, StartLight1–5) | about 88 × 30 | Truss gantry with 5 big start lights (keep the 5 lights as separate parts named `StartLight1..5`: the client colors them) and a big CHAOS KARTS banner |
| **Skyscrapers** (4–6 variants) | `CityBuilder.tower` | 30–60 wide, 60–220 tall | Neon cyberpunk-cartoon towers: dark glass, window bands, vertical neon trims, rooftop signs. Variants can replace the box + bands |
| **Parking garage** + spiral tower | `CityBuilder` `garage` | about 34 × 24 × 250 | Open-deck concrete garage with neon level stripes; the roof is the Rooftop Leap road (keep the road parts) |
| **Stadium** stands, floodlight towers, scoreboard | `CityBuilder` `stadium` | ellipse about 360 × 210 | Colorful tiered stands, chunky floodlights |
| **River bridge arches** | `CityBuilder` `bridgeArches` | span about 110, 30 high | Red steel tied-arch bridge with white hangers |
| **Tunnel portals** | (new) at the River Tunnel ends | road width + walls | Concrete portals with neon "RIVER TUNNEL" lettering |
| Props | `CityBuilder` `props`, `TrackBuilder` | small | Street lamps, tyre stacks, cones, dumpsters (alley), palm and park trees, billboards |
| Lobby race portal | `LobbyBuilder` | about 44 wide arch | A glowing neon arch with a swirling portal surface |

## 2. ComfyUI prompts

**Game icon (512 × 512):**
> cartoon kart racing game icon, a bright red go-kart drifting toward the camera with blue and purple sparks flying from the rear wheels, a giant rubber duck in neon sneakers in the background, neon city at dusk, bold chunky 3D style, saturated pink, cyan and yellow, high contrast, centered, no text, Roblox game icon style

**Thumbnail 1 (1920 × 1080): the race:**
> wide action shot of 8 colorful cartoon go-karts racing down a neon-lit city street at dusk, one kart mid-drift with purple sparks, a start gantry with red lights behind, skyscrapers with glowing window bands, motion lines, low camera angle, vibrant arcade style, space on the left for a title

**Thumbnail 2: the chaos:**
> cartoon go-karts dodging a giant yellow rubber duck wearing neon sneakers, sunglasses and a crown as it waddles across a city race track, a band of chrome toasters marching behind, karts bouncing into the air, a golden toast statue flexing in a plaza, funny chaotic arcade style, dusk sky

**Thumbnail 3: the track:**
> cartoon kart soaring off a big jump ramp with pink flags, an elevated highway overpass and a red arch bridge over a river behind, neon city skyline at sunset, other karts below, dynamic angle, vibrant saturated colors, playful 3D style

**UI icons (256 × 256, transparent background):**
> - "flat cartoon icon of a drift spark burst, blue orange purple, game UI"
> - "flat cartoon icon of a racing helmet" (garage tab)
> - "flat icon of a gold trophy with a checkered flag" (wins)
> - "flat icon of a stopwatch with a speed streak" (best lap)
> - "flat icon of a treasure chest with coins" (daily)
> - "flat icon of a gift ticket" (codes)
> - The 12 power-ups for Stage 3: homing missile, cartoon nuke, energy wave, black hole, meteor, lightning bolt, giant boxing glove, freeze ray, banana bomb, UFO, speed boost arrow, force field bubble

Replace `icon-512.png` and `thumbnail-1920x1080.png` (the current ones are three.js placeholders made with `tools/store_art.mjs`).

## 3. Sound slots to fill

These are in `src/shared/Config/AudioAssets.lua`. Use licensed / Creator Store audio only; never invent IDs.

| Slot | What | Notes |
|---|---|---|
| **Engine** | kart engine loop | looped; the code sets PlaybackSpeed 0.7 → 1.6 with speed (+ a bit on boost) |
| EngineRemote | other karts' engines | looped, 3D, quieter |
| DriftSkid | tyre squeal loop | plays while drifting |
| Boost / BoostPad / StartBoost | whoosh | currently "FuelPour" stand-ins |
| MiniTurbo | spark level-up ding | currently "TerminalBeep" up |
| Checkpoint | soft tick | empty |
| Crowd | stadium crowd loop | empty; for the stadium |
| RaceMusic / FinalLapMusic | upbeat racing music; a hotter final-lap track | currently stand-ins from DEAD AIR |
| ItemRoll | item roulette tick (Stage 3) | empty |
| Quackaroni `Attack` / `Exit` | QUACK honk, marching-band outro | in `Events/QuackaroniParade.lua` `Sounds` |
| The other 34 events | Warning / Entrance / Attack / Impact / Exit each | in each `Events/<Id>.lua` (all empty) |

## 4. Balance and feel to tune in Studio

These live in `Config/KartStats` and are the same for every kart. See the README's tuning table.

- `TopSpeed` 80 gives clean bot laps of 85–88 s on Chaos City. If you raise it, re-run the harness: it asserts laps of 80–95 s. Scale the track instead if needed.
- Drift: `DriftChargeLevels` {0.7, 1.45, 2.25} and `DriftBoostTime` {0.5, 0.95, 1.45}. Purple should feel like a real reward.
- Rooftop Leap: today it needs about 98+ studs/s at the lip (top speed 80 falls short; boost 105 makes it). If it's too hard or too easy, move the landing ramp start (`Shortcuts[1].points[7]`). The unit test checks both sides.
- Neon Alley: the dumpster positions and slime puddles (`Shortcuts[2].obstacles / puddles`) set the risk.
- Events: `GameConfig.Events.Interval` 26 s (×0.55 on the final lap), `GraceSeconds` 15, budget 1 major + 1 minor.
- Camera: `GameConfig.Camera` (distance 15, height 5.6, look-ahead 0.32 rad, FOV 70 → 84 on boost).
- Bots: `GameConfig.Bots.FillTo` 8. BotBrain variety is look-ahead, line, drift habit and throttle discipline, never stats.
- Rewards: `GameConfig.Rewards` (place coins 120 … 18, XP 40 + 10 per kart beaten + 60 for a win, +25 for a new best lap).

## 5. Visual polish ideas (from the previews)

- The grass reads flat: add Roblox Terrain grass or textured MeshParts, flower beds, and paths through Chaos Park.
- The hill under the Big Jump is stepped boxes (`Embankment`). Replace it with one smooth hill mesh.
- Downtown: add street-level detail (shop fronts, awnings, crosswalks, traffic lights flashing at the start).
- The tunnel looks great through the glass ceiling. Add fish / bubbles (ParticleEmitters) above it.
- Add SurfaceGui art to the billboards. Their text is already set in code; they just need a picture.
- Speed lines and drift sparks currently use default particles. Give them textures (sparks, smoke puffs, tyre-smoke on drift start).
