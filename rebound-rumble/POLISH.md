# POLISH.md: to-do list for the PC pass (Blender + ComfyUI)

The gameplay, monetization and UI are complete and built from code. This list covers what to make
prettier. **Keep instance names, sizes and orientation** so the code keeps working. Swap a
procedural part for a MeshPart with the same name, or parent the mesh under the same model and
hide the old parts.

## 1. Blender models

General style: chunky, readable silhouettes, bright saturated colours, emissive accents (these
map to Neon parts), low poly (under 2k tris each), and stylised rather than realistic. Export FBX,
1 stud = 1 unit.

### Parry weapons (`src/shared/WeaponModels.lua`)

These are client-side visual swings, anchored and non-colliding. The pivot (`GripRoot`) is at the
hand, and the **weapon points along +Y**. Keep each one about 5 studs long.

| Style | Used by (CosmeticConfig) | Size (studs) | Notes |
|---|---|---|---|
| Sword | Training Blade (Common), Solar Edge (Mythic) | 1.6 x 5.2 x 0.5 | Straight blade, crossguard and pommel. The Solar variant has a glowing orange edge and runes. |
| Bat | Slugger (Common), Neon Slugger (Rare) | 0.7 x 5.1 x 0.7 | Baseball bat with grip tape and a band. The Neon variant has emissive stripes. |
| Katana | Moonlit Katana (Rare) | 0.8 x 5.5 x 0.6 | Slight curve, round tsuba, wrapped handle, pale blue steel. |
| Hammer | Thunder Mallet (Epic) | 2.4 x 3.8 x 1.3 | Big blocky head with a lightning-bolt inlay (emissive yellow). |
| Scythe | Reaper's Arc (Legendary) | 1.3 x 5.5 x 3.5 | Long shaft with a curved purple glowing blade bending back (-Z). |

Optional: a matching "swing smear" mesh (a flat arc, about 9 studs in diameter) to replace the
cylinder arc in `EffectsController.swing`.

### Ball (`src/client/Controllers/BallController.lua`)

* `Core`: sphere, 2.4 studs, emissive and white (the colour is set at runtime by speed).
* `Shell`: sphere, 3.6 studs, ForceField material. A Blender replacement would be an energy-cage
  mesh (geodesic lattice) with 2 counter-rotating rings.
* Lobby monument (`LobbyBuilder` > `BallMonument`): a giant 9-stud version with 3 orbit rings.
  It's a good place for a hero model.

### Arenas (`src/server/Services/ArenaBuilder.lua`)

Play area: a **70-stud radius circle**, floor top at the arena origin's Y, kept clear of
obstacles. Decorate only outside a radius of 70. Ball pad: a 10-stud disc at the centre.

| Theme | Replace | Style notes |
|---|---|---|
| Sky Isle (FloatingIsland) | Floor disc, rocky underside (6 stacked cylinders), 9 trees, clouds, islets | Stylised floating island with an inverted rock cone, puffy low-poly trees and soft clouds. |
| Neon Grid (NeonGrid) | Grid floor, 16 pylons, data cubes, synthwave sun | Dark reflective floor, pink and cyan neon grid lines, chrome pylons with glowing caps. |
| Magma Crater (Volcano) | Basalt floor with cracks, 20 crater wall wedges, lava falls, lava sea | Cracked basalt, glowing orange cracks, jagged crater ring, lava cascades. |
| Frost Ring (FrostRing) | Ice floor, snow ring, 18 crystals, glacier underside | Translucent blue ice crystals and a snowy ring, cold and bright. |

### Lobby (`src/server/Services/LobbyBuilder.lua`)

* 130-stud floating platform with a neon rim, pillars (12), crate pedestal (`CratePedestal` >
  `Crate`, which keeps the `CratePrompt` ProximityPrompt), leaderboard frame, and signs.
* Bot rig (`BotService.buildModel`): a blocky robot about 2 x 5 x 1 studs with a visor, antenna and
  chest light. A cute robot mesh would be nice. Keep `HumanoidRootPart` (2 x 2 x 1) and HipHeight 2.

## 2. ComfyUI prompts

Style anchor for all prompts: *"vibrant 3D cartoon game art, Roblox-style blocky characters,
glossy plastic and neon materials, dramatic rim lighting, high contrast, clean composition, no
text"*. Negative: *"text, watermark, logo, realistic gore, blood, blurry, lowres, extra limbs"*.

**Game icon (512x512)**
> A glowing magenta-white energy ball with motion streaks, bursting toward the viewer, being
> deflected by a stylised neon sword swing arc, sparks and shards flying, dark purple-to-cyan
> gradient background, centred bold composition, vibrant 3D cartoon game art, glossy neon, high
> contrast, no text

**Thumbnail 1 (1920x1080): the clutch parry**
> Blocky cartoon hero mid-swing with a glowing sword deflecting a blazing red energy ball at
> point-blank range, shockwave ring and sparks, three rival blocky players reacting in the
> background, floating sky island arena with clouds, dramatic low angle, motion blur on the ball
> trail, vibrant 3D cartoon game art, no text

**Thumbnail 2 (1920x1080): neon showdown**
> Two blocky players facing off on a dark reflective synthwave grid arena with pink and cyan neon
> lines, a fast energy ball streaking between them leaving a rainbow trail, chrome pylons with
> glowing caps, a giant pink sun on the horizon, cinematic wide shot, vibrant 3D cartoon game art,
> no text

**Thumbnail 3 (1920x1080): confetti party**
> Cartoon explosion of colourful confetti instead of fire over a magma crater arena, blocky
> players cheering and dancing, one player with a golden VIP crown, glowing lava falls behind,
> festive and funny mood, vibrant 3D cartoon game art, no text

**Shop / UI icons (256x256 each, transparent background)**
* Coin pouch / sack / vault: *"stack of shiny gold coins with a lightning bolt emblem, in a
  pouch / sack / open vault, 3D cartoon icon, transparent background"*
* Premium Spin: *"golden prize wheel with rainbow segments and sparkles, 3D cartoon icon"*
* Explosion Party: *"party popper exploding with confetti and a tiny cartoon bomb, 3D icon"*
* VIP: *"golden crown with a VIP gem, glossy, 3D icon"*
* 2x Coins: *"two gold coins with a bold x2 shape made of light (no letters), 3D icon"*
* Prism Trail: *"rainbow comet trail curling around a glowing orb, 3D icon"*
* Extra Slot: *"two glowing ability orbs in slots on a sleek panel, 3D icon"*
* Abilities: Dash (*"blue speed burst with wind lines"*), Super Jump (*"green spring launch with
  upward arrow of light"*), Swap (*"two purple swirling portals"*), Freeze (*"ice crystal
  snowflake encasing an orb"*), Shield (*"golden bubble shield"*)
* Crates: Basic (*"blue cube crate with neon edges"*), Elite (*"purple crate with gold bands"*),
  Premium (*"golden glowing crate with rays"*)

The UI currently uses text and colour only. To use icons, upload them, put the asset IDs in a new
config, and add ImageLabels to `MenuController` rows.

## 3. Sound slots to fill (`src/shared/Config/AudioAssets.lua`)

Empty now: `Whiff` (short air swish), `Confetti` (party popper), `Dash` (whoosh), `FreezeCast`
(ice crackle), `SwapWarp` (warp zap), `LobbyMusic` and `BattleMusic` (upbeat electronic loops).
Also consider replacing the reused clang, impact and beep with a punchier sword "shing" and a big
explosion.

## 4. Balance values to tune after real playtests

| Value | File | Current | Watch for |
|---|---|---|---|
| `Parry.BaseRange`, `WindowSeconds` | GameConfig | 9 studs, 0.22 s | Window too tight or too loose at real ping. |
| `Parry.MaxRewind`, `HitGrace` | GameConfig | 0.25 s, 0.12 s | High-ping fairness versus "I parried it!" complaints. |
| `Parry.WhiffCooldown` | GameConfig | 0.9 s | Spam versus frustration. |
| `Ball.BaseSpeed`, `DeflectMultiplier`, `DeflectAdd`, `MaxSpeed` | GameConfig | 42, x1.07 + 4, 300 | Rally length. Aim for rounds of about 60 to 120 s. |
| `Ball.OvertimeAfter` / `OvertimeAccel` | GameConfig | 100 s / 6 per s | Endless 1v1 rallies. |
| `Bots.SkillMin/Max`, `SpeedPenalty` | GameConfig | 0.55 to 0.9, 0.11 | Bots too hard or too easy for new players. |
| `Lobby.FillToContestants` | GameConfig | 5 | Round size in empty servers. |
| Ability prices and cooldowns | AbilityConfig | 0 / 750 / 1500 / 2500 / 4000 | Progression pace: about 30 to 50 coins per round for a casual player. |
| Crate prices, odds, pity | CosmeticConfig | 400 / 1500, pity 40 | Odds must stay displayed if you change them. |
| Rewards | ProgressionConfig | kill 25, win 120, streak 15 per level (cap 90) | Coin inflation. |
| Daily rewards | ProgressionConfig | 100 to 750 | Day-7 spike. |

## 5. Nice-to-have later

* A badge set (first win, 5-streak, Mythic unbox). Create the badges and add the IDs; none are
  invented now.
* Animated R15 swing emote synced with the weapon arc. A KeyframeSequence would need an uploaded
  animation, so it isn't done.
* A private-server "practice mode" with a slow ball.
