# Sprout Valley

A cozy, colorful real-time farming game for Roblox (1–6 players per server). It is an
original game in the "garden simulator" genre. You get a fenced plot in a shared village.
You buy seeds from **Pip's Seed Shop**, plant them, and watch them grow in real time. They
keep growing while you're offline. You harvest the fruit and sell it to **Marlow at the Sell
Stand**. Seed stock changes every 5 minutes. Server-wide weather events mutate your crops
into fruit worth hundreds of times more.

Everything is built from code: the village, NPCs, 26 crops with 4 growth stages each, the
UI and the effects. No models or uploaded assets are needed.

## Build and run

This is a [Rojo](https://rojo.space) project (Rojo names it `SproutValley`).

```bash
cd sprout-valley
rojo build -o build/SproutValley.rbxlx   # open this file in Roblox Studio
# or live-sync into an open place:
rojo serve                                # then Connect from the Rojo Studio plugin
```

In Studio:

* **Play solo:** press Play. You spawn at your garden gate with 4 Carrot seeds, 1 Strawberry seed and a 5-use Watering Can.
* **Multiplayer:** Test → Clients and Servers → 2–6 players. This tests gifting, the friend bonus, announcements and visiting other gardens.
* **Saving:** turn on *Game Settings → Security → Enable Studio Access to API Services* to test
  DataStores. Without it the game still runs in memory and says that progress isn't saved.
* **Robux items:** while the IDs are `0`, every Robux button grants the item for free in Studio. Game
  passes granted this way last for the session only.

## How to play

1. **Plant:** pick a seed on the bottom hotbar and tap an empty soil tile in your garden.
   With the seed still selected, hold and drag to plant a whole row.
2. **Grow:** crops grow in real time through **Sprout → Small → Full → Ripe** (sparkles).
   Hover over or tap a plant to see its time left, its growth speed and its mutations.
3. **Harvest:** tap a ripe plant, or hold and drag across a row. Fruit goes into your
   **backpack** (60 slots, or 200 with the pass). Multi-harvest crops (bushes, vines, trees,
   cacti, mushrooms) regrow fruit after you pick them.
4. **Sell:** go to the Sell Stand (the SELL button teleports you) and press **SELL ALL**.
   Favourite a fruit to keep it.
5. **Grow your garden:** buy rarer seeds, gear and more garden rows. Then wait for the weather.

**Price** = crop base value × (weight ÷ base weight) × mutation multiplier. Each harvest rolls
a weight between 0.75x and 1.45x of the base. 2% of harvests are **HUGE** (2.5–4x).

### Controls

| Action | Keyboard / mouse | Touch | Gamepad |
|---|---|---|---|
| Act on a tile (plant / harvest / use gear) | Left click (hold and drag for rows) | Tap (drag for rows) | R2 (aims at screen centre) |
| Select hotbar slot | 1–9, click a slot; 0 / Q = hand | Tap a slot | L1 / R1 |
| Talk to a stall NPC | E | Tap the prompt | X |
| Close a window | X button | X button | B |
| Travel | GARDEN / SEEDS / GEAR / SELL buttons | same | same (UI selection) |

The UI scales with a `UIScale` on every ScreenGui, so it fits phones. The HUD stays clear of
Roblox's top bar and the mobile jump button.

## Systems

### Crops (26, from Common to Prismatic)

| Rarity | Crops (M = multi-harvest) |
|---|---|
| Common | Carrot, Radish, Lettuce, Strawberry (M) |
| Uncommon | Blueberry (M), Tomato (M), Corn (M), Bell Pepper (M) |
| Rare | Pumpkin, Watermelon, Cactus (M), Grape (M) |
| Epic | Apple Tree (M), Coconut Palm (M), Mango Tree (M), Pineapple |
| Legendary | Dragon Fruit (M), Glow Mushroom (M), Frostmint (M, fantasy) |
| Mythic | Moon Melon, Star Fruit (M), Ember Pepper (M, fantasy) |
| Divine | Cloudberry (M, fantasy floating cloud bush), Crystal Beet (fantasy) |
| Prismatic | Prism Pear (M, fantasy glass tree), Starlight Lotus (fantasy) |

All values are in `src/shared/Config/CropConfig.lua`. The models are built by
`src/shared/CropModels.lua` from 12 archetypes: Root, Leafy, Bush, Stake, Stalk, Ground,
Cactus, Tree, Palm, Mushroom, Rosette and Lotus. Each archetype changes with the growth stage.

### Real-time and offline growth

Growth is stored as "grown seconds" per plant, together with the time of the last save. The
server adds `dt × rate` every second. The rate includes weather, sprinklers and the
Auto-Water pass. When you rejoin, the time you were away is added at base rate (×1.25 with
Auto-Water), capped at 3 days.

### Seed Shop restock (FOMO)

* The stock restocks every 5 minutes, aligned to the real clock. Everyone sees the same
  countdown on the HUD and in the shop.
* The scheduled stock is rolled from the time window. **Every server sells the same seeds at
  the same time.**
* Each seed has its own stock chance and quantity. Prismatic seeds appear in about 0.3–0.4% of
  restocks.
* Each player can buy up to the listed quantity per restock, so nobody can buy out a rare
  seed before others see it.
* Legendary and rarer seeds in stock are **announced server-wide**.

### Weather events (every 10–15 minutes)

| Event | Weight | Effect |
|---|---|---|
| Rain | 40 | Growth ×1.5, fruit may turn **Wet** (2x) |
| Thunderstorm | 22 | Growth ×1.5, Wet, and lightning strikes a plant every 12 s: **Shocked** (6x) |
| Frost | 20 | **Chilled** (2x). Wet + Chilled = **Frozen** (8x) |
| Golden Hour | 12 | Growth ×1.2, fruit may turn **Golden** (10x variant) |
| Blood Moon (rare) | 4 | Night sky, red moon, **Bloodlit** (5x) |
| Aurora (rare) | 2 | Night sky, aurora ribbons, growth ×1.3, **Aurora** (9x) |

* The client shows each event with lighting, fog and colour tweens. It also adds falling
  particles (rain, snow, golden motes, embers), a giant moon, aurora ribbons, lightning
  bolts and flashes.
* Mutations show on the fruit as coloured auras, tints and materials: Golden foil, Frozen
  ice, Rainbow neon.
* **Stacking:** environmental mutations add up, and the variant multiplies the total.
  Variants are Golden (10x, 1% natural chance) and Rainbow (40x, 0.1% natural chance).
  Example: Golden + Frozen + Shocked = 10 × (1 + 7 + 5) = 130x.
* The mutation chance per tick is capped at 20%, whatever boosts are stacked.

### Gear Shop (Coins)

| Gear | Effect |
|---|---|
| Watering Can (10 uses) | Instantly grows a plant (8% of its grow time, max 3 min). 10% chance to make it Wet. 15 s cooldown per tile |
| Sprinkler | Plants in a 3×3 area grow ×1.5 for 5 min |
| Pro Sprinkler | Plants in a 5×5 area grow ×1.8 for 10 min |
| Lucky Fertilizer | 2x weather mutation chance on that plant until harvest |
| Trowel (permanent) | Dig a plant up and move it to an empty tile |

### Garden expansion

The plot is 6 × 10 tiles. You start with 3 rows (18 tiles). **EXPAND** unlocks one row
(6 tiles) at a time. Costs: 300 → 630 → 1,320 → … Coins. VIP adds one bonus row.

### Visiting, gifting and why there's no trading

* Anyone can walk into any garden and hover over plants to see what's growing.
* **Gifting:** in the Backpack, press GIFT on a fruit and pick a player standing within
  30 studs. Gifting is one-way. Favourited fruit can't be gifted. Each player can turn off
  "Accept gifts".
* **Two-sided trading was skipped on purpose.** A safe trade needs escrow, a final-offer
  confirmation from both sides, cooldowns and logs. Trade scams are among the most reported
  problems in this genre, and a half-built trade window is worse than none. Gifting keeps
  the social moment without that risk.

### Retention and social features

* **Daily login streak:** 7 days. One claim per UTC day; missing a day resets the streak.
  VIP gets +50% coins. A red dot on REWARDS shows when a claim is ready.
* **Codes:** `RELEASE`, `SPROUT`, `RAINYDAY`, `LIKE1K`. Codes are case-insensitive and work
  once per player. Edit them in `GameConfig.Codes`; an optional `Expires` field retires a
  code. The panel says "Like the game and join the group for new codes!".
* **Session goals:** 3 short goals, e.g. "Harvest 8 crops" or "Earn 300 coins selling".
  Each finished goal pays out and is replaced by a harder one.
* **Global leaderboard:** the "Top Gardeners - Total Coins Earned" board in the plaza uses an
  OrderedDataStore. Every call is wrapped in pcall, and it refreshes every 60 s. If the store
  is unavailable, the board shows this server's players. `leaderstats` show Coins and Earned.
* **INVITE button:** `SocialService:PromptGameInvite`, wrapped in pcall, after
  `CanSendGameInviteAsync`. Each friend in the server gives **+10% sell value** (max +30%).
* **Announcements:** server-wide banners for:
  * rare seeds in stock,
  * Mythic or rarer harvests, HUGE harvests and fruit worth 20x or more,
  * restock and weather purchases (with the buyer's name),
  * rare crate pulls,
  * new VIPs.
* **Feedback:**
  * floating harvest text with rarity colours,
  * particle bursts,
  * coins that fly into the wallet,
  * camera punch,
  * a popup for crates, daily rewards, goals, gifts and expansions,
  * a smooth coin counter,
  * a ripe sparkle on plants and a click "pop" on tiles.

## Robux shop

The SHOP button on the HUD opens a window with four tabs: Coins, Boosts, Crates and Passes.
Prices show as "R$ 49". Items are defined in `src/shared/Config/ShopConfig.lua`.

| Developer Product | Display price | What it does |
|---|---|---|
| Handful / Sack / Barrel / Wagon of Coins | R$ 25 / 99 / 249 / 799 | 2,500 / 15,000 / 60,000 / 300,000 Coins |
| Restock for Everyone! | R$ 39 | Instantly restocks the Seed Shop for the whole server, and the buyer is announced |
| Growth Skip | R$ 19 | Instantly ripens one plant. Pick the plant first with the hotbar's Growth Skip tool, then the purchase applies to it |
| Rain / Storm / Golden Hour Totem | R$ 29 / 49 / 79 | Starts that weather for the server, or queues it right after the current event. Announced |
| Seed Crate / 5x Seed Crate | R$ 49 / 199 | A random seed from Uncommon to Prismatic. The **odds are shown** in the Crates tab |

| Game Pass | Display price | What it does |
|---|---|---|
| 2x Sell Value | R$ 199 | Everything you sell is worth double |
| VIP Gardener | R$ 149 | VIP overhead and chat tag, +1 garden row, +50% daily coins |
| Bigger Backpack | R$ 79 | 200 fruit instead of 60 |
| Auto-Water | R$ 129 | Crops grow 25% faster, online and offline |
| Lucky Gardener | R$ 249 | 1.5x mutation and natural Golden/Rainbow chance, capped at 20% per tick |

**Pay-to-win is bounded:**
* Coin packs are fixed amounts.
* Mutation boosts are capped.
* Totems only start common weather (Blood Moon and Aurora can't be bought).
* The crate only gives seeds the free shop also sells.
* Restocks help everyone in the server.

**Purchase safety:**
* `ProcessReceipt` stores each PurchaseId in the profile.
* It saves the profile **before** returning `PurchaseGranted`. If the save fails, it undoes
  the grant and returns `NotProcessedYet`.
* Server-wide effects run only after a successful save.
* Passes are checked with `UserOwnsGamePassAsync`, which is cached and wrapped in pcall.
  `PromptGamePassPurchaseFinished` activates a pass bought in-game.

### Setting up the shop (Creator Hub)

1. Publish the place. Then open create.roblox.com → your experience → **Monetization**.
2. **Developer Products:** create one product for each entry in `ShopConfig.Products`
   (11 products) and set its price. Copy each numeric ID into that entry's `ProductId`.
3. **Passes:** create the 5 passes and paste each ID into `PassId` in `ShopConfig.Passes`.
4. Keep the display `Robux` values in `ShopConfig` the same as the real prices.
5. While an ID is `0`, the live game shows "This item isn't available yet" instead of selling it.

## Audio

No asset IDs were invented. `src/shared/Config/AudioAssets.lua` has two kinds of slot:

* Six slots reuse IDs from the DEAD AIR project, which come from Roblox's licensed partner
  libraries: Pickup → Harvest/Plant, TerminalBeep → UI click, CanClatter → Sell,
  DoorOpen → Gate, MetalDrop (pitched down) → Thunder.
* The other slots are empty (`Id = ""`) and are skipped until you add your own sounds:
  Music, RainLoop, WindLoop, Restock, RareAnnounce, WeatherStart, Purchase, Mutation, Daily,
  Water, Expand.

## Publishing checklist

- [ ] Fill in the Product and Pass IDs (see above). Test a real purchase in a private server.
- [ ] Enable API Services. Check that saving works across two sessions, and that crops grew
      while you were offline.
- [ ] Set Max Players to **6** (Game Settings → Places). The village has 6 plots.
- [ ] Upload an icon and thumbnails (see POLISH.md for the ComfyUI prompts). Add audio to the
      empty slots.
- [ ] Choose a genre (Simulation) and devices (Phone, Tablet, Computer, Console).
- [ ] Do a balance pass on GrowTime, Value and StockChance after watching real players.
- [ ] Put the `LIKE1K` code in the description ("Like the game for a code at 1K likes!").

### Maturity questionnaire suggestions

There is no violence, blood, gore, romance, gambling with real money, or real-world
currency. **Minimal / All ages** is expected. Two items to answer honestly:

* Players can buy random items (the Seed Crate) with Robux. Roblox requires the odds to be
  disclosed before purchase, and the game shows them in the Crates tab.
* There is no free-form user-generated content apart from Roblox chat.

"Blood Moon" is only a red-tinted night sky.

## Layout

```
src/shared/            ReplicatedStorage.SproutValley
  Config/              CropConfig, RarityConfig, MutationConfig, WeatherConfig, GearConfig,
                       ShopConfig, GameConfig, AudioAssets
  Economy, Growth, Stock, Crate, Rewards, WeatherLogic, Format, Rng   pure logic (unit tested)
  CropModels           procedural crop models
  Net, Signal          remotes / signals
src/server/            ServerScriptService.SproutValleyServer
  Main.server.lua      lighting, remotes, wiring
  Services/            DataService, ShopService (Robux), PlotService, StockService,
                       SellService, WeatherService, RewardsService, PlayerService,
                       LeaderboardService, VillageBuilder, RateLimit
src/client/            StarterPlayerScripts.SproutValleyClient
  Main.client.lua      controller bootstrap, VIP chat tag
  Controllers/         ClientState, Ui, Audio, HudController, HotbarController,
                       PlotController, PanelsController, StoreController,
                       EffectsController, WeatherController
tests/                 run.luau (unit), compile.luau, harness.luau (Lune smoke harness)
tools/                 export_preview.luau + preview_html.py + preview_shot.js (3D previews)
```

The server owns every rule: currency, inventory, stock, growth, mutations and purchases.
Every remote checks argument types and rejects NaN. Tile indices must be integers in
range, and there are distance checks to tiles, stalls and gift targets. All remotes are
token-bucket rate limited.

## Tests

```bash
selene src                                        # lint (custom roblox_min std)
lune run tests/compile                            # every .lua file compiles
lune run tests/run                                # unit tests for the pure logic
rojo build -o build/SproutValley.rbxlx && lune run tests/harness build/SproutValley.rbxlx
```

The **harness** loads the built place in Lune and runs the real modules against Lune's
reflection-checked Instance API. It stubs Players, DataStores, Marketplace, tweens and input,
then runs these checks:

* builds every crop model at every stage, with mutations,
* builds the village,
* starts all services,
* joins two players,
* runs the game loop: buy seeds → plant → grow → harvest → sell,
* checks multi-harvest regrowth, backpack capacity and favourites,
* processes a receipt **twice** and checks it is granted once,
* tests instant restock, Seed Crate and Growth Skip,
* tests weather: growth boost, Wet → Frozen combo, lightning, queued totems and Golden Hour,
* tests all gear, expansion to the maximum, daily rewards and codes, and gifting rules,
* tests offline catch-up, travel, the leaderboard fallback and the VIP tag,
* starts every client controller with a real profile snapshot, and renders every window,
  effect and weather preset.

Optional previews of the procedural models:

```bash
lune run tools/export_preview build/SproutValley.rbxlx ripe build/ripe.json
python3 tools/preview_html.py build/ripe.json /tmp/ripe.html "21,30,-24,21,1,12"
NODE_PATH=$(npm root -g) node tools/preview_shot.js /tmp/ripe.html $PWD/build/preview-crops.png
```

`build/preview-crops.png` and `build/preview-village.png` were rendered this way. They are
approximate three.js renders, not Roblox screenshots.

## Status (honest)

**Verified here:**
* lint is clean, every file compiles, and the unit tests pass,
* the Lune harness passes on the built `.rbxlx`,
* 3D previews of the crop and village geometry were rendered and checked.

**Not verified:** no Roblox Studio playtest was possible in this environment. Specifically
untested:
* real physics and character movement,
* camera raycasts for clicks and taps (Lune stubs them),
* the real rendering of SurfaceGuis, BillboardGuis, ParticleEmitters and ViewportFrames,
* UI layout and scaling on real screens,
* TextChatService chat tags,
* real DataStore, OrderedDataStore and MarketplaceService behaviour,
* the friend check (`IsFriendsWith`) and game invites.

**Known limitations:**
* Offline growth runs at base rate (sprinklers and weather don't apply while you're away).
* Weather only mutates plants of players who are online.
* Instant restock effects aren't replayed if the server dies between the save and the effect.
* The pass grants from the Studio free-test path aren't saved.

Balance numbers are first-pass values; see POLISH.md.
