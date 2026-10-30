# POLISH.md – to-do list for the PC pass (Blender / ComfyUI / Studio)

Everything in LAST LIFEBOAT is built from parts in code. Gameplay, monetisation and UI are complete. This list is what would lift it from "clean blocky" to "store-page ready". Work in this order: icon and thumbnails, the sounds, the hero meshes, then balance.

## 1. Store art (ComfyUI)

The palette is dusk orange to purple sky, navy hull, warm portholes, brass and signal red. **Never** use a real ship's name or livery (no famous liners), and no brand logos.

| Asset | Size | Prompt |
|---|---|---|
| Game icon | 512×512 | "stylized 3D game icon, a small orange-and-white wooden lifeboat with four cartoon survivors rowing away, behind them a huge dark ocean liner tilting bow-down into the sea at dusk, warm porthole lights, splash spray, bold silhouette, saturated orange and navy palette, soft rim light, Roblox game icon style, centered, no text" |
| Thumbnail 1 – "The lurch" | 1920×1080 | "stylized 3D render, interior of a grand ship dining hall tilting 20 degrees, chandeliers swinging, chairs sliding, red carpet, seawater rushing in from the lower left, four blocky cartoon passengers bracing, one shouting, a big red BRACE warning glow, dramatic dusk light through windows, Roblox style, high detail" |
| Thumbnail 2 – "One boat" | 1920×1080 | "stylized 3D render, the stern of a sinking ocean liner rising out of the sea at sunset, a single orange lifeboat hanging from davits at the stern, cartoon survivors running across a steep wooden deck toward it carrying a gold bar and a painting, funnels with smoke, warm portholes, cinematic wide angle, Roblox style" |
| Thumbnail 3 – "Save your crew" | 1920×1080 | "stylized 3D render, flooded ship corridor half underwater, teal light, one cartoon survivor floating with a life jacket and a timer ring, a friend reaching to pull them up, sparks from a broken cable in the water, cabin doors along the corridor, Roblox style" |
| Shop icons (256×256, transparent) | each | Life jacket ("orange inflatable life jacket, game icon, soft shading"), rescue flare ("handheld red rescue flare burning with pink smoke"), coin pouch / chest / hoard ("gold coins in a leather pouch / small chest / overflowing chest"), x2 loot ("gold bar with a glowing x2 badge"), grapple hook ("brass grappling hook with coiled rope"), captain's outfit ("white captain's cap with gold badge and navy coat"), VIP ("gold ship's wheel with a VIP ribbon") |
| Loot icons (128×128) | 13 | one per item in `GameConfig.LootOrder`, rarity-coloured glow behind (cream / blue / purple / gold) |

If you add images, upload them to Roblox. Put the IDs in a new `Config/ImageAssets.lua`, and have `HudController.refreshSlots`, `MenuController` (shop cards) and the results card use them in place of the viewport icons. Never invent IDs.

## 2. Sounds (fill the empty slots, upgrade stand-ins)

Use `src/shared/Config/AudioAssets.lua`. Licensed Creator Store audio only.

1. **Waves** (loop, ambient): calm harbour water. Plays everywhere at low volume.
2. **Splash**: going under. **Gasp**: surfacing for air.
3. **Seagulls**: lobby ambience, played now and then (wire a timer in `AudioController.step` when filled).
4. **Oars**: during the launch cinematic.
5. Replace the stand-ins, most important first:
   - **Horn**: a deep ship's horn.
   - **SteamHiss / SteamBurst**.
   - **Lurch**: a big metal groan plus an impact.
   - **ShipCreak**, **Winch**.

## 3. Meshes to replace (Blender → MeshPart)

Keep the same names, rough sizes and pivots, so the code that finds them (by name) still works. Collision should stay simple: keep the existing parts invisible as collision, or use `CollisionFidelity = Box`.

| Model (code) | Where | Size (studs) | Style notes |
|---|---|---|---|
| Hull plates (`Hull`, `Transom`, `BowTip`, `Stem`) | `ShipBuilder.hullCell` / `hullEnds` | per ship: 160/240/320 long, 44/56/64 beam, keel −6 to top deck +3.5 | The biggest visual win. A curved, flared hull with sheer (the bow rising a few studs) and a rounded counter stern. Keep the waterline at Y = 0 and the cell layout (the decks are flat inside). Paint: dark hull, red boot-top, cheatline, white upper works. |
| Funnels (`Funnel`, `FunnelBand`, `FunnelTop`) | `superstructure` | ⌀ 6–10 × 14–18 | Elliptical, raked 8°, with steam pipes and a top cage |
| Lifeboat (`Lifeboat` model) | `lifeboat` | 6 × 3 × 15 | Clinker-built wooden boat, orange gunwale, thwarts, oars, a canvas cover rolled at the bow |
| Davits (`DavitPost` / `DavitArm`, `GantryPost` / `GantryBeam`) | `superstructure` / `lifeboat` | 7–12 tall | Curved quadrant davits with pulley blocks and falls |
| Ship's wheel, binnacle, telegraph | `superstructure` helm station | wheel ⌀ 4 | Classic wooden wheel with brass hub; brass binnacle; engine-order telegraph with a dial |
| Chandelier (`Chandelier` model) | `hazard` | ⌀ 5 | Crystal tiers; keep `Ring` as the PrimaryPart |
| Grand piano, dining chairs, tables | `DECOR.DiningHall` | piano 5 × 3 × 6 | Art-deco style |
| Boilers, catwalks | `DECOR.EngineRoom` | ⌀ 7 × 11 | Riveted, with gauges and pipework |
| Cars under tarps | `DECOR.CargoHold` | 6 × 4 × 11 | 1930s-style car shapes under draped canvas |
| Loot items (`Models.loot` shapes) | `src/shared/Models.lua` | 1–2.6 | One mesh each; keep the glow ring |
| Captain's Outfit | `Models.CaptainOutfit` | avatar scale | Proper cap and coat meshes; weld as now (massless, no collision) |
| Harbour (`LobbyBuilder`) | – | – | Ticket booth, warehouse, crane, lighthouse, town houses: a cohesive harbour-town kit |

Also consider:
- Textures (SurfaceAppearance) for deck planks, rusted metal and carpet.
- A real water edge (spray particles) where the hull meets the waterline during lurches.

## 4. Balance values to tune (`src/shared/Config/GameConfig.lua`)

| Value | Now | What to watch |
|---|---|---|
| `Ships.*.LurchEvery`, `MaxTilt`, `MaxSink`, `Sinking.TiltCurve` | 18–25 s, 22–27°, 8–14, 1.6 | Is the lowest deck flooded too early to loot? The bow half of deck 1 floods around lurch 2–3. |
| `Ship.DeckBase` | 6 | Higher = the lowest deck survives longer |
| `Oxygen.Base` / `Regen` | 12 s / 4 per s | Dive shortcuts should be tense but doable |
| `Downed.BleedOut` / `ReviveHold` | 20 s / 2 s | – |
| `Sinking.SlideAccel` / `SlideTilt` | 22 / 12° | Physics feel in Studio |
| `Hazards.*` | steam 12 dmg / 55 knockback; chandelier 30 / 30; wires −3 s air | – |
| `Rewards`, `Upgrades.*.Costs` | escape 40 × ship, participation 15 | About 3–4 good escapes per upgrade level early on |
| `LootRules.DepthBonus` / `TierBonus` | 1.6 / 0.35 | Rare+ is 40% of rolls on the Gull's top deck and much more below decks on the Leviathan |
| `Lifeboat.FullCrewHold` / `FullCrewBonus` | 3 s / ×1.25 | – |
| `Grapple.Range` / `Cooldown` | 40 / 12 s | Keep it a convenience, not a skip |

## 5. Nice-to-haves (not built)

- Rotating limited-time "event ships", e.g. a storm night variant with lightning and lower visibility.
- Badges (create them in Creator Hub first; never invent IDs): first escape, Full Crew, a legendary find, all three ships.
- Cosmetic trails or boat skins for coins.
- A spectator "camera drone" with free look for players who are out.
