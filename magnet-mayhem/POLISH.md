# MAGNET MAYHEM: polish list (for the Claude on your PC)

Everything is built from Roblox parts right now. These are the upgrades that matter most, in
priority order (the same order as the design brief).

## 1. Blender meshes

How to swap a model in:

1. Import the mesh with Studio's 3D Importer.
2. Put the MeshPart in `ReplicatedStorage.MagnetMayhem.Meshes`.
3. Change that entry's builder in `src/shared/ScrapModels.lua` (or `MagnetModel.lua`) to
   clone the mesh instead of building parts.
4. Keep the same pivot convention: an invisible `Root` at the object's centre, and the
   objects anchored, non-colliding and non-queryable. For the magnet rig, keep the part names
   `Mount`, `MagnetHead` and `Core`.

Aim for 300–2,000 triangles per scrap object, shared materials, and pivots at the centre.

| Priority | Asset | Size (studs) | Notes |
|---|---|---|---|
| 1 | Magnet rig, tiers 1–6 | head ~1.3 × 0.6 × 1.4, pack 1.7 × 1.9 × 0.75 | Horseshoe electromagnet on a jointed shoulder arm plus back pack. Each tier adds coils, a bigger glowing core, fins (T4+), a ring (T5+) and a halo (T6). Skins only recolour: keep separate material slots for body / prongs / tips / core. |
| 2 | Shredder | 34 × 32 × 24 | Hopper on top, two counter-rotating rollers (separate meshes, they spin), two pistons (separate, they pump), a smokestack, an output belt with slats, warning beacons. |
| 3 | Pile look | – | Pile pieces reuse the scrap meshes at 0.22–0.62 scale. Also make a lumpy "scrap cluster" ball mesh for the overflow (`MagnetController` → `updateCluster`). |
| 4 | Rare objects | see `ScrapConfig.Size` | Motorcycle Engine, Industrial Motor, Steel Safe, Experimental Power Core, Prototype Magnetic Reactor (hero piece: rotating rings, glowing core), Wrecked Scooter, Engine Block, Armored ATM, Golden Taxi (hero piece). |
| 5 | Upgrade station | 14 × 11 × 10 | Kiosk with a screen, neon trims, a coil on a bench. |
| 6 | Landmarks | – | Tower cranes (60 tall) with a hanging magnet, warehouses, the Metro gate arch, Metro building facades with window variety. |
| 7 | Common scrap | 0.8–3 | Soda can, bolt, washer, gear, pipe, sign, toolbox, fan, chain, engine part, hubcap, parking meter, traffic light, manhole cover, street lamp, car door, storm shard. |

## 2. ComfyUI images

Make the experience icon at 512 × 512, three thumbnails at 1920 × 1080, and the shop and HUD
icons at 256 × 256 on a transparent background.

* **Icon:** "a chunky red-and-silver horseshoe electromagnet glowing orange at the core,
  pulling bolts, gears and a toolbox that fly toward it with motion streaks, bright warm
  junkyard background, Roblox game icon style, bold outlines, high contrast, centered, no text"
* **Thumbnail 1, "the pull":** "third-person view of a blocky Roblox character with a big
  shoulder-mounted magnet, dozens of scrap pieces swirling into a tornado above their head,
  golden late-afternoon junkyard, cranes in the haze, dynamic, vibrant"
* **Thumbnail 2, "the shredder":** "a giant yellow industrial shredder with sparks flying from
  its rollers as a mountain of scrap pours into the hopper, coins bursting out, warm sunset
  light, Roblox style"
* **Thumbnail 3, "the Golden Taxi":** "a shining golden taxi lifted into the air by a
  glowing magnetic beam in a wrecked city street at dusk, broken streetlights, purple sky,
  Roblox style, epic"
* **Shop icons:**
  * Chrome magnet, Gold Rush magnet, Neon Pulse magnet: the same horseshoe magnet in each
    finish.
  * Spark trail and Plasma trail: an abstract streak.
* **HUD icons:**
  * coin;
  * magnet;
  * the twelve upgrade icons: strength coil, range rings, speed arrow, pulse wave, heavy clamp,
    capacity crate, multi-grip, packing, boots, sprint, shredder contract, lucky detector.

  The menu currently shows text badges (STR, RNG, ...): swap them for `ImageLabel`s once you
  have the images.

## 3. Sound slots to fill

In `src/shared/Config/AudioAssets.lua`:

* **Empty slots:**
  * `MagnetCharge`: rising electrical whine, 0.5 s;
  * `ChainRattle`;
  * `QuestDone`: short jingle;
  * `LevelUp`: fanfare;
  * `Birds`: ambient loop;
  * `MusicRustyard`: playful, industrial, adventurous loop;
  * `MusicMetro`: urban dusk loop.
* **Reused slots:** the filled ones reuse DEAD AIR's Creator Store sounds; some were picked for
  a horror game. Listen to `PulseWave`, `HeavyGroan`, `RareSting`, `ShredderSlam` and
  `StormSiren`, and replace any that feel too dark.

## 4. Balance to tune after playtests

| Value | Where | Now |
|---|---|---|
| Starting capacity / range | `MagnetConfig.Base` | 30 / 16 studs |
| Upgrade curves | `EconomyConfig.Upgrades` (Base, Growth, Max, Per) | first upgrade 20–22 coins |
| Tier prices | `MagnetConfig.Tiers` | 400, 4K, 40K, 350K, 2.5M |
| Metro Wreck unlock | `ZoneConfig` | strength 6 + 15K coins |
| Flight feel | `Attraction.lua` (ANTICIPATION, speed formula, `MagnetConfig.Base.FlightSpeed`) | light 0.08 s, medium 0.28 s, heavy 0.65 s wind-up |
| Scrap density | `ZoneConfig.MaxScrap`, `PerformanceConfig.SpawnPerSecond`, region weights in WorldBuilder | 150 / 120, 6 per second |
| Storm | `EventConfig.MagneticStorm` | every 12–18 min, 2 min long |
| Prestige | `EconomyConfig.Prestige` | 500K run earnings → 3 cores |
| Visual budgets | `PerformanceConfig` | 42 / 14 pile pieces, 70 flights |

## 5. Nice next features (after the core is proven in Studio)

* A third zone, Industrial Core, using the same ZoneConfig + WorldBuilder pattern.
* Character animations: a magnet-activation pose and a heavy-pull recoil. These need animation
  assets.
* Friends comparison on the leaderboard and personal best-sale records.
