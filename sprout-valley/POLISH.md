# Sprout Valley: polish to-do (for the PC Claude with Blender and ComfyUI)

The game works fully with its procedural part models. This list covers what to replace with
meshes, the art to generate, the sounds to add and the balance to tune. Rough renders of the
current models are in `build/preview-crops.png` and `build/preview-village.png`. Re-render
them with the commands in the README.

**Style for everything:** cozy, chunky, low-poly "toy garden" style. Soft rounded shapes,
saturated pastel colors and no realistic textures; use vertex colors or one small palette
texture. 1 stud = 1 Blender unit (scale by 0.28 m if you work in meters). Keep the origin at
the bottom centre of the model. Export as FBX, import as MeshParts, and set `CanCollide = false`
on crops.

## 1. Crop meshes (26 crops × 4 stages)

How the swap works:
* `src/shared/CropModels.lua` builds every crop from parts on a tile that is **3.7 × 3.7
  studs**. The model must fit inside about 3.6 × 3.6, with height ≤ 8 studs for trees and
  ≤ 3.5 for low crops.
* To swap in meshes, put Models under `ReplicatedStorage.SproutValley.CropMeshes.<CropId>`
  with children `Stage1`, `Stage2`, `Stage3` and `Stage4`.
* Then change `CropModels.build` to clone the mesh when it exists. Keep the invisible `Base`
  part, the `Fruit` naming (mutations tint every part named Fruit, Petal, Cob, Grape, Cap,
  Coconut, Shard, Point, Rib, Stripe or Heart) and the particle emitters.

**Stages:**
* Stage1 (Sprout): a tiny mound with two leaves. It can be shared by every crop, tinted with
  the leaf colour.
* Stage2 (Small): about 55% size, no fruit.
* Stage3 (Full): full size, no fruit or a small unripe green fruit.
* Stage4 (Ripe): full size with **separate fruit sub-meshes**, so they can be tinted
  Golden, Frozen or Rainbow.

| Crop (Id) | Rarity | Archetype | Size (W×H studs) | Notes |
|---|---|---|---|---|
| Carrot | Common | Root | 2×1.6 | Feathery fan of 5 leaves, orange shoulder poking out of the soil |
| Radish | Common | Root | 2×1.6 | Round magenta root, half buried |
| Lettuce | Common | Leafy | 2.6×1.4 | Ruffled rosette, pale green heart when ripe |
| Strawberry | Common | Bush (multi) | 2.6×1.8 | Low bush, 6 red berries with seeds and green caps |
| Blueberry | Uncommon | Bush (multi) | 2.6×2 | Dense dark bush, 9 small blue berries |
| Tomato | Uncommon | Stake (multi) | 1.8×3.2 | Wooden stake, vine and 4 red tomatoes |
| Corn | Uncommon | Stalk (multi) | 2×3.6 | Two stalks, long leaves, tassels, yellow cobs in husks |
| BellPepper | Uncommon | Stake (multi) | 1.8×3.2 | Glossy yellow peppers |
| Pumpkin | Rare | Ground | 3.4×2 | Ribbed orange pumpkin with a curly stem, vine leaves |
| Watermelon | Rare | Ground | 3.4×1.8 | Long striped melon |
| Cactus | Rare | Cactus (multi) | 2×3 | Saguaro with 2 arms, pink fruit on the tips |
| Grape | Rare | Stake (multi) | 1.8×3.2 | Trellis vine with 4 purple bunches |
| Apple | Epic | Tree (multi) | 3.6×5.5 | Round canopy, 6 red apples |
| Coconut | Epic | Palm (multi) | 3.6×5 | Curved, segmented trunk, 7 drooping fronds, 3 coconuts |
| Mango | Epic | Tree (multi) | 3.6×5.5 | Dark leaves, oval orange/red mangoes |
| Pineapple | Epic | Rosette | 2.4×2.4 | Spiky leaves, golden diamond-pattern fruit with a crown |
| DragonFruit | Legendary | Cactus (multi) | 2.4×3 | 3-arm cactus, magenta scaled fruit with green tips |
| GlowMushroom | Legendary | Mushroom (multi) | 2.2×1.8 | 3 mushrooms with cyan glowing caps (Neon material) and white spots |
| Frostmint | Legendary | Bush (multi) | 2.6×2 | Fantasy: icy, translucent mint bush with frosted crystal berries |
| MoonMelon | Mythic | Ground | 3.4×2.4 | Fantasy: pale blue glowing melon with craters, night-blue leaves |
| StarFruit | Mythic | Tree (multi) | 3.6×5.5 | Teal canopy, glowing 5-point star fruit |
| EmberPepper | Mythic | Stake (multi) | 1.8×3.2 | Fantasy: chili peppers like small flames, ember particles |
| Cloudberry | Divine | Bush (multi) | 2.6×3 | Fantasy: a white cloud floating on a thin stalk, golden berries |
| CrystalBeet | Divine | Root | 2×2 | Fantasy: purple crystal beet with glowing shards |
| PrismPear | Prismatic | Tree (multi) | 3.6×5.5 | Fantasy: a glass tree, with pears in every colour of the rainbow |
| StarlightLotus | Prismatic | Lotus | 3.3×1.5 | Fantasy: a small pond disc with lily pads and a glowing two-ring lotus |

**Budget:** ≤ 1,500 triangles per ripe crop and ≤ 400 per sprout. Up to 360 plants can be on
screen at once.

## 2. Village meshes (`src/server/Services/VillageBuilder.lua`)

| Item | Size (studs) | Notes |
|---|---|---|
| Seed Shop stall | 15×12×10 | Wooden market stall with a green/cream striped awning and scalloped edge, seed packet display, two produce crates, sign board |
| Gear Shop stall | same | Blue/cream awning, tools on hooks: watering can, sprinkler, trowel |
| Sell Stand | same | Orange/cream awning, scales, coin pile, baskets |
| NPCs: Pip, Bolt, Marlow | 2×6.5 | Chibi farmers (R15-compatible rig optional), with a straw hat / cap / beanie and aprons. An idle sway animation would be nice |
| Garden plot gate arch | 9.8×8 | Pastel posts with ball caps and a cream sign beam (it has a SurfaceGui for the owner's name: keep a flat face) |
| Picket fence | 5-stud sections | White picket fence (post + 2 rails + pickets) to replace the post/rail parts |
| Soil tile | 3.7×0.5×3.7 | Slightly domed tilled soil with furrows. A grass "locked" variant |
| Flower boxes | 5×0.9×1.2 | Planters by each gate |
| Fountain | Ø15×6 | Stone, two tiers, water (keep the spray emitter) |
| Windmill | Ø9×20 | Plaster tower, clay roof, 4 fabric blades (the client spins `Blades`, so keep the hub as PrimaryPart) |
| Lamp posts | 9 tall | Green iron street lamps (keep the PointLight) |
| Trees | 7–12 tall | 3 variants: round green, blossom pink, pine |
| Leaderboard board | 13×14 | Wooden notice board with a red roof (keep the SurfaceGui face) |
| Clouds | 30×12 | Puffy low-poly clouds |
| Sprinkler / Pro Sprinkler (placed gear) | 1.2×2.6 | Metal pole and head (blue / gold). The spray emitter and the area ring stay |
| Extra decor (new) | - | Hay bales, wheelbarrow, mailbox per plot, scarecrow, pond with ducks, bushes along the boundary |

## 3. ComfyUI prompts

**Shared negative prompt:** `text, watermark, logo, signature, blurry, lowres, deformed,
photorealistic, dark, gritty, horror, extra limbs, ugly, jpeg artifacts`

**Game icon (512×512):**
> cute cozy farming game icon, a smiling sprout seedling in a tiny terracotta pot with a shiny golden strawberry and a glowing blue moon melon beside it, sparkles, bright pastel colours, soft studio lighting, chunky toy-like 3D render, rounded shapes, centred composition, vibrant green and sky blue background with a soft radial gradient, Roblox game icon style, high detail

**Thumbnail 1 (1920×1080), garden overview:**
> wide shot of a cheerful cartoon farming village at sunny midday, fenced garden plots full of colourful crops (pumpkins, strawberry bushes, apple trees, glowing mushrooms, a palm tree), white picket fences, a cobblestone street, striped market stalls, a windmill, a fountain, blocky cute characters harvesting fruit with sparkles, saturated pastel palette, soft shadows, 3D toy render, tilt-shift depth of field

**Thumbnail 2 (1920×1080), weather event:**
> dramatic cozy thunderstorm over a cartoon garden, a bright lightning bolt striking a pumpkin that glows electric yellow, rain streaks, other crops shimmering with blue and yellow auras, cute blocky farmer characters cheering, a purple-grey sky with a warm lamp glow, vibrant stylised 3D render, sense of excitement

**Thumbnail 3 (1920×1080), rare finds / Blood Moon and Aurora:**
> split scene of a magical night garden: on the left a huge red moon bathing the crops in crimson light, on the right green and purple aurora ribbons over glowing rainbow fruit trees and a starlight lotus; a cute character holding up a giant golden rainbow fruit with sparkles, a big "rare!" glow, stylised cozy 3D render, rich colours

**Shop / UI icons (512×512 each, transparent background, same style):**
`isolated game item icon, cute chunky 3D render, soft lighting, transparent background,` plus:
* Coins: a pile of shiny gold coins with a sprout emblem. Make 4 sizes: handful, sack, barrel, wagon
* Restock: a seed packet with a circular refresh arrow and sparkles
* Growth Skip: a purple hourglass with a sprouting leaf and lightning sparkles
* Rain / Storm / Golden Hour Totem: a carved wooden totem topped with a raincloud / lightning cloud / golden sun
* Seed Crate: a wooden crate with glowing seeds spilling out, rainbow light
* 2x Sell: a gold coin with a big "2x" made of leaves
* VIP: a pink and gold gardening crown
* Bigger Backpack: an overstuffed brown backpack with fruit poking out
* Auto-Water: a self-watering can with a little gear and droplets
* Lucky Gardener: a four-leaf clover with a golden glow
* Gear: watering can, sprinkler, pro sprinkler, lucky fertilizer bag, trowel
* Seed packets for each of the 26 crops (optional): they would replace the ViewportFrame previews in the shop and hotbar

To use the icons, upload them and paste the asset IDs. Add an `Icon = "rbxassetid://..."`
field to ShopConfig / GearConfig entries. The UI currently draws a letter tile or a
ViewportFrame; swap in an ImageLabel where the field is set.

## 4. Sound slots (`src/shared/Config/AudioAssets.lua`)

**Empty slots:**
* Music: a looping cozy acoustic or ukulele track,
* RainLoop, WindLoop (loops),
* Restock: a shop bell jingle,
* RareAnnounce: a sparkly fanfare,
* WeatherStart: a whoosh or chime,
* Purchase: a cash register "cha-ching",
* Mutation: a magical shimmer,
* Daily: a reward fanfare,
* Water: a pour or splash,
* Expand: a construction "pop".

**Reused stand-ins worth replacing:**
* Sell: CanClatter. Swap it for a coin jingle.
* Thunder: MetalDrop pitched down. Swap it for a real thunder clap.
* Harvest and Plant: Pickup. A juicy "pop" and a soil "fwump" would be better.

## 5. Balance values to tune (first-pass numbers)

* **Crops** (`CropConfig`): `GrowTime`, `Value`, `Regrow`, `StockChance`, `StockQty`.
  Current targets: early crops earn 16–40 coins/min per tile; Epic about 180–250; Legendary
  about 600–850; Mythic 1,250–2,000; Divine 3,300–5,000; Prismatic 8,900–17,000.
  Multi-harvest crops pay back their seed in ≤ 8 harvests (a unit test enforces this).
* **Weather** (`WeatherConfig`): `MinGap`/`MaxGap` (600–900 s), `TickChance`, `Duration`,
  the rare event weights (Blood Moon 4, Aurora 2), and `MutationConfig.ChanceCap` (0.2).
* **Mutation multipliers:** Wet 2, Chilled 2, Frozen 8, Shocked 6, Bloodlit 5, Aurora 9,
  Golden 10, Rainbow 40.
* **Plot expansion:** base 300, ×2.1 per row, 7 purchasable rows. The late rows may be too
  cheap against Prismatic income.
* **Starting kit:** 40 Coins, 4 Carrot, 1 Strawberry, 5 Watering Can uses.
* **Backpack:** 60 / 200. **Friend bonus:** +10% each, max +30%.
* **Coin packs:** fixed amounts. Consider scaling them with the player's best crop later in
  the game (common in the genre).
* **Daily rewards and codes:** `GameConfig.Daily` and `GameConfig.Codes`.

## 6. Nice-to-have features (not built)

* A "harvest all ripe" button for VIPs.
* A pet or companion system.
* Seasonal events.
* A safe two-sided trading booth with escrow (see the README for why it was skipped).
* An index or collection book of crops and mutations, with rewards for discovering them.
* A rebirth/prestige reset (garden reset for a permanent sell multiplier).
* Badges (create them in Creator Hub first; no IDs are invented here).
