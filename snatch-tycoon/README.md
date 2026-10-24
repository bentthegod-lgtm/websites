# Snatch a Blobby

*(working title, Rojo project name `SnatchTycoon`)*

An original steal-and-tycoon Roblox game for up to 8 players per server. Goofy creatures called
**Blobbies** waddle out of a portal and along a red carpet. Buy them and they walk to your base,
sit on a pedestal and make cash. Your friends can sneak into your base, grab one and run home
with it over their head. You can slap them so they drop it, or lock your laser door.

Everything is built from code: the map, the 8 bases, all 20 Blobby species, the UI and the effects.
There are no imported models, images or invented asset IDs.

![Blobbies](build/blobbies-preview.png)

*(`build/*.png` are three.js approximations rendered from the real model data. See "Preview tools"
below. They are not Roblox screenshots.)*

---

## Build and run

```bash
cd snatch-tycoon
rojo build -o build/SnatchTycoon.rbxlx     # open this in Roblox Studio
# or live-sync into an open place:
rojo serve                                  # then Connect from the Rojo Studio plugin
```

In Studio:

* **Solo:** press Play. You spawn in your base. Walk to the red carpet and buy a Blobby (E).
* **Stealing needs 2+ players:** Test → Clients and Servers → 2 or 3 players.
* **Saving:** turn on *Game Settings → Security → Enable Studio Access to API Services* to test
  DataStores. Without it the game still runs, and it tells the player that saving is off.
* **Shop:** every Developer Product / Game Pass has ID `0` until you create it, and in Studio the
  Buy buttons grant the item **for free** so you can test it.
* **Game Settings → Places → Max Players = 8** (there are exactly 8 bases).

## How to play

1. **Buy.** Blobbies of random rarity walk slowly down the red carpet. Walk up and press **E**
   (Buy $X). It walks to your base and sits on a free pedestal.
2. **Earn.** Each Blobby makes cash per second. The cash piles up as floating text on the green
   pad in front of its pedestal. **Step on the pad** to collect it, or buy Auto-Collect.
3. **Steal.** Walk into another player's base and **hold E for 1.5 s** on one of their Blobbies.
   You carry it over your head and walk slower. Get back into **your own base** to keep it.
4. **Defend.** Press **F** (SLAP) near a thief and they drop it, and it runs home. Press **L**
   (or the red console button by your door) to **lock your laser door** for 45 s. It then needs
   60 s to recharge.
5. **Grow.** Sell weak Blobbies (hold E on your own Blobby for half price) to make room for
   better ones. **Rebirth** to reset for a permanent cash multiplier and an extra pedestal.

### Controls

| Action | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Buy / steal / sell / lock console | E (ProximityPrompt) | X | tap the prompt |
| Slap | F | R1 | SLAP button |
| Lock base | L | L1 | LOCK button |
| Drop carried Blobby | G | D-pad down | DROP button |
| Shop | B | D-pad up | SHOP button |

All HUD buttons can be selected with a gamepad. On small screens a `UIScale` shrinks the whole
UI (`Ui.autoScale`). On phones the goals panel starts collapsed and the action buttons sit above
the jump button.

---

## Systems

### Rarities (base carpet odds)

| Rarity | Base odds | Glow | Announced |
| --- | --- | --- | --- |
| Common | 52.0% | | |
| Uncommon | 26.0% | | |
| Rare | 13.0% | | |
| Epic | 6.0% | point light | |
| Legendary | 2.2% | light + sparkles | feed |
| Mythic | 0.6% | light + sparkles | feed + chat |
| Secret | 0.12% | light + sparkles | feed + chat |

The odds come from `RarityConfig` weights. **Luck** multiplies the weights of Rare and above, and
"Mythic Madness" multiplies Mythic and Secret on top of that (`Spawner.rarityWeights`). Rarer
Blobbies are bigger, from 1.0x scale for Common to 1.66x for Secret.

**Mutations** roll on top of the rarity: **Gold** (4%, x2 price and income), **Diamond**
(1.5%, x3) and **Rainbow** (0.4%, x6, and its hue cycles on the client). Every mutation spawn
goes to the server feed. Diamond and Rainbow spawns also go to chat. The total mutation chance is
capped at 50% even when boosted.

### The 20 Blobbies

| Rarity | Species (price -> income/s) |
| --- | --- |
| Common | Wobbleton ($25 -> 1), Snorkpuff ($40 -> 2), Gloopsy ($60 -> 3), Bonkus ($85 -> 4) |
| Uncommon | Tater Tumble ($180 -> 7), Fizzlewick ($260 -> 10), Mumbo Jello ($360 -> 14) |
| Rare | Spikelord Pip ($1.1K -> 35), Noodle Nanny ($1.5K -> 46), Captain Squish ($2.1K -> 62) |
| Epic | Disco Dumpling ($8.5K -> 230), Wizzlebop the Wise ($12K -> 310), Sir Pancake III ($16K -> 400) |
| Legendary | Gigachonk ($65K -> 1.4K), Bubblegum Baron ($90K -> 1.9K), Lord Wigglesworth ($125K -> 2.5K) |
| Mythic | Cosmo Blorbo ($550K -> 10.5K), The Grand Gloobini ($900K -> 16K) |
| Secret | Blorbzilla ($5.5M -> 100K), Void Noodle Supreme ($9M -> 155K) |

`BlobbyModels.lua` builds each species from its config: one of 8 body shapes (round, tall, flat,
spiky, pear, cube or jelly, noodle, dumpling), 7 eye styles, 10 hats (some with spinning parts),
9 accessories and 6 idle animations (bounce, wobble, spin, hop, sway, float). A Blobby being
carried wiggles frantically. Each model is 8 to 40 parts. They are all welded and massless, with
a `Root` → `Body` Motor6D that the client animates.

### Income, collecting and slots

* Income per second = the sum of the placed Blobbies × the rebirth multiplier × 2 (with 2x Cash) ×
  (1 + 10% per friend in the server, max +30%) × any event bonus.
* Pending cash shows on each pedestal's pad. Touching the pad (owner only) collects it.
* Pedestal slots: 8, plus 1 per rebirth (max +5), plus 1 for VIP, plus 3 for the +3 Pedestals pass.
  The most is 17, and 20 pedestals are physically built. Locked slots show as faded "LOCKED SLOT"
  pedestals.
* If a gift, crate or steal arrives while the base is full, it waits in a **queue**. It walks in
  as soon as a pedestal frees up. Queued Blobbies survive rebirths and rejoins.

### Stealing rules (`StealService`)

* You can't steal your own Blobby, steal from a locked base, steal while you're already carrying
  one, steal within 1.6 s of being slapped, or steal when your own base is full. You also have to
  be within range. The server checks every one of these.
* When the hold starts, the owner gets an alarm (red screen flash, sound and text) and the feed
  says someone is trying. A grab is announced in the feed and in chat. Delivery is too
  ("X STOLE Y's MYTHIC Cosmo Blorbo!").
* A carried Blobby earns nothing. Carry speed is 55% of walk speed (75% with Speedy Snatcher,
  still slower than walking) and jumps are lower.
* The thief **drops** it when slapped by anyone, zapped by the victim's door locking while
  they're still inside, after 45 s, on death, on leaving, or with G. The Blobby then **runs home**.
* If the victim leaves, the Blobby leaves with them, so a leaving victim never duplicates or
  loses one.

### Laser door lock (`PlotService`)

The door locks for 45 s, then recharges for 60 s. The blocker part is solid on the server. The
owner's client turns its collision off locally, so only the owner can walk through. Locking pushes
intruders out to the doorstep and zaps thieves who are still inside. **Lock Base Now** (Robux)
skips the recharge, but the door always stays open for at least 8 s between locks, so a paid lock
can never be permanent. If the product can't apply right away it becomes a saved **lock token**,
and the next LOCK press uses it.

### Rebirth

The cost is $50K × 6^rebirths. A rebirth resets your cash to $100 and clears your Blobbies (queued
ones are kept). In exchange you get +50% income permanently, plus one more pedestal (up to +5).
The server announces it, with confetti.

### Events and FOMO (`EventService`)

* **Lucky Hour:** the first 10 minutes of every UTC hour give luck x2. It starts at the same moment
  in every server, so players learn to come back for it.
* **Admin-style events:** every 15 minutes (the first one 5 minutes after the server starts) a
  random event runs for 3 minutes:
  * **Cash Rain:** coins fall over the carpet, each worth 4 s of the collector's income.
  * **Mythic Madness:** Mythic and Secret odds x8.
  * **Mutation Mayhem:** mutation odds x4.
  * **Blobby Stampede:** spawns 2.2x faster and Blobbies walk 1.4x faster.
  * **Double Cash:** everyone earns x2.
* The HUD shows the active events with countdowns, "Next: X in 7:12" and "Lucky Hour in 23:00".
  A board by the portal shows the same thing.
* **Server Luck x2** comes from the Robux product or the day-3 daily reward. It boosts everyone in
  the server and the time stacks, capped at 2 h.

### Retention and social

* **Daily streak** (7-day cycle): cash that scales with your income, Server Luck for everyone, a
  free Rare Blobby on day 5 and a free **Legendary** on day 7. Missing a day resets the streak.
* **Codes:** `RELEASE`, `BLOBBY`, `SNATCH` (a free Rare) and `LIKE`. They're case-insensitive,
  work once per player, and live in `RewardConfig.Codes`. The panel has a "Like the game for
  codes" message.
* **Session goals:** 3 active at a time out of a pool of 12 (buy, collect, lock, slap, steal, sell,
  buy an Epic, defend, coins, play time). Rewards scale with income, and the pool loops with
  bigger targets.
* **Offline earnings:** 50% of your income per second while you were away, capped at 3 h,
  shown on a "Welcome back" card.
* **Friends boost:** +10% cash for every friend in the server (max +30%), with a toast when a
  friend joins. **INVITE** uses `SocialService:PromptGameInvite` (pcall +
  `CanSendGameInviteAsync`).
* **Index (Blobbydex):** all 20 species with live 3D previews. Undiscovered ones are black
  silhouettes. A toast pops up for every new discovery.
* **Global leaderboard:** "Top Earners ($/s)" board in the world. It stores the best income per
  second in an OrderedDataStore and refreshes every 60 s, with pcall. Without DataStores it shows
  this server's players.
* **leaderstats:** Cash, Per Sec, Rebirths. The overhead nameplate shows rebirths and $/s, and is
  gold with a `[VIP]` tag for VIPs. VIPs also get a `[VIP]` chat tag (TextChatService).
* **Juice:** flying cash numbers, rarity reveal banners with rays, confetti, camera FOV punch,
  "SLAP!" bursts, knockback, an animated cash counter, bouncy buttons and a pulsing alarm.

---

## Robux shop

The **SHOP** button (or B) has three tabs.

**Developer Products** (`ShopConfig.Products`; prices are display only):

| Key | Name | R$ | What it does |
| --- | --- | --- | --- |
| CashSmall | Pocket of Cash | 19 | 10 min of income (min $2.5K) |
| CashMedium | Bag of Cash | 79 | 45 min of income (min $15K) |
| CashLarge | Vault of Cash | 299 | 3 h of income (min $80K) |
| ServerLuck | Server Luck x2 (15 min) | 99 | luck x2 for **everyone** in the server, stacks |
| MythicCrate | Mythic Crate | 249 | guaranteed Mythic (92%) or Secret (8%), odds shown in the shop |
| LockNow | Lock Base Now | 25 | lock immediately, skipping the cooldown (bounded, see above) |

**Game Passes** (`ShopConfig.Passes`):

| Key | Name | R$ | Effect |
| --- | --- | --- | --- |
| DoubleCash | 2x Cash | 199 | income x2 |
| VIP | VIP | 299 | [VIP] chat tag, gold nameplate, +1 pedestal |
| AutoCollect | Auto-Collect | 149 | cash goes straight to your wallet |
| FastCarry | Speedy Snatcher | 129 | carry at 75% speed instead of 55% |
| ExtraSlots | +3 Pedestals | 249 | three more pedestal slots |

### Setting up the shop (Creator Hub)

1. Publish the place (File → Publish to Roblox).
2. Go to create.roblox.com → your experience → **Monetization → Developer Products** and create
   the 6 products above. Use the same names and prices, or update `Robux =` in
   `src/shared/Config/ShopConfig.lua` to match.
3. In **Monetization → Passes**, create the 5 passes, each with an icon (see POLISH.md for the
   prompts), and put them on sale.
4. Copy each numeric ID into `ProductId = ...` or `PassId = ...` in `ShopConfig.lua`, then rebuild.
5. While an ID is `0`, the item is granted for free in Studio and shows "not available yet" in a
   live game. Nothing breaks if you leave some at 0.

**How purchases are processed (`ShopService`):** `ProcessReceipt` applies the grant to the
profile (cash, the queued crate Blobby or a lock token), records the `PurchaseId`, and **saves**
the profile. If the save fails, everything is rolled back and it returns `NotProcessedYet`, so
Roblox retries later. World effects (server luck, placing the Blobby, locking the door) only run
after a successful save. A receipt that was already seen returns `PurchaseGranted` without
granting again. Passes use `UserOwnsGamePassAsync` (pcall, cached per session) and
`PromptGamePassPurchaseFinished`.

**Paid random items:** the Mythic Crate is hidden and refused when
`PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted` is true. It is also
hidden if that check fails.

**Pay-to-win limits:** free players can earn every Blobby. Server Luck helps the whole server.
Carry speed stays below walking speed. Paid locks can't chain. Cash packs only speed things up.

---

## Data

* DataStore `SnatchTycoon_Profiles_v1`, key `player_<UserId>`. Schema version 1 has the defaults in
  `DataService.defaultProfile()`. `reconcile()` fills any missing fields, and `migrate()` is the
  hook for future versions.
* Autosave every 90 s when something changed. The profile also saves on leave, on BindToClose and
  right after every Robux purchase.
* If a load fails 3 times, the session runs **non-persistent and never saves**, so it can't
  overwrite real data. The player sees a notice.
* **Session lock:** the stored profile carries `Lock = { JobId, Time }`. Loading takes it with
  `UpdateAsync`, waits (about 12 s, then kicks with "rejoin in a minute") while another live server
  holds it, and steals a lock older than 3 minutes. Every save refreshes it, the save on leave
  clears it, and a save that finds another server's lock is cancelled and stops saving. In a live
  game a purchase for a profile that can't be saved returns `NotProcessedYet`. A Blobby moved by a
  steal is still written to two profiles that save independently.
* OrderedDataStore `SnatchTycoon_BestIncome_v1` holds the leaderboard.

## Audio

No audio IDs were invented. `src/shared/Config/AudioAssets.lua` reuses IDs from the DEAD AIR
project (TerminalBeep, EscapeSting, Pickup, CardSwipe, ItemDrop, Alarm, CanClatter, MetalDrop,
HeavyDoor, DoorOpen, GlassBreak, ElevatorArrive, AlarmClockRing), re-pitched where it helps.
Two slots are empty and are skipped until you **add your own**:

* `Music`: an upbeat tycoon loop
* `BlobbySqueak`: plays when a Blobby lands on a pedestal

The settings panel has Music and SFX toggles, which are saved to the profile.

## Tests

```bash
cd snatch-tycoon
selene src                                              # lint (custom roblox_min std)
lune run tests/compile                                  # every .lua file compiles
lune run tests/run                                      # unit tests (pure logic)
rojo build -o build/SnatchTycoon.rbxlx && lune run tests/harness build/SnatchTycoon.rbxlx
```

* **Unit tests (37):** number formatting, economy math (rebirth cost and multiplier, slots, offline
  cap, cash packs, payback times), rarity, species, mutation and crate rolls (odds checked over
  200K rolls), luck and mythic boosts, lock and cooldown state (including the paid-lock gap),
  daily streak, event schedule, Lucky Hour, server luck stacking, goals, layout geometry, and
  config sanity (20 unique looks, ID placeholders, audio IDs).
* **Harness (26 checks):** loads the built place in Lune and runs the **real modules** against
  Lune's reflection-checked Instance API, with stubbed engine services and in-memory DataStores.
  It covers:
  * building the world (8 bases × 20 pedestals) and every species × every mutation
  * init and start of all services; two players joining (plots, leaderstats, welcome, friend boost)
  * buying from the carpet (distance, price, double buy), walking home, income ticks and collect pads
  * a steal attempt with the alarm, the grab and carry, a slap drop and the run home, then a steal
    plus delivery that transfers ownership
  * a lock blocking steals and ejecting intruders
  * receipts: a duplicate is granted once, a failed save rolls back, plus the crate, server luck
    and lock token
  * Studio pass grants (2x, VIP slot, auto-collect, a real-ID prompt and its finish event)
  * selling, the full-base queue, rebirth, daily, codes and goals
  * all 5 admin events, cash rain coins, carpet despawn, the leaderboard and offline earnings
  * the PolicyService crate restriction, leaving and saving, and junk remote arguments
  * every client controller initialising, then receiving real server snapshots, every popup type,
    every panel, the shop tabs and the Blobby animator

## Preview tools

```bash
lune run tools/export_blobbies build/SnatchTycoon.rbxlx build/blobbies.json
lune run tools/export_blobbies build/SnatchTycoon.rbxlx build/world.json world
# three.min.js from `npm pack three@0.160.0`; playwright must be resolvable (PLAYWRIGHT_MODULE=...)
node tools/render_preview.mjs build/blobbies.json path/to/three.min.js build build/world.json
```

This writes `build/blobbies-preview.png`, `mutations-preview.png`, `world-overview.png` and
`world-base.png`. Shapes and materials are approximated in three.js, so the previews don't look
exactly like Roblox.

## Publishing checklist

- [ ] Max Players 8; enable Studio API access to test saving
- [ ] Create the 6 products and 5 passes, paste the IDs, rebuild and test one real purchase
- [ ] Fill the `Music` / `BlobbySqueak` slots (optional)
- [ ] Icon and thumbnails (POLISH.md prompts); description; genre: Simulator / Tycoon
- [ ] Complete the Maturity & Compliance questionnaire (below)
- [ ] Test on a phone and a gamepad in Studio's device emulator
- [ ] Playtest stealing with 2-3 clients (Test → Clients and Servers)
- [ ] Add new codes in `RewardConfig.Codes` at like milestones

### Maturity questionnaire suggestions

* **Violence:** cartoon slapping that knocks players back, with no damage, blood or weapons. This
  probably fits *mild* / unrealistic violence.
* **Theme:** playful "stealing" of cartoon creatures between players. It isn't crime-themed and
  nothing real is stolen.
* **Social:** standard Roblox text chat. System messages are server announcements.
* **Monetization:** Developer Products and Game Passes. **Paid random item: yes** (Mythic Crate,
  with odds shown and a PolicyService check).
* No gambling with real money, no romance, no scary content, no crude humour beyond goofy names.

## Honest status

**Verified here (no Roblox Studio available):**

* `selene src`: 0 errors, 0 warnings. All 41 Luau files compile.
* 37 of 37 unit tests pass. The harness passes 26 of 26 checks on the Rojo-built `.rbxlx`.
* The 20 Blobbies and the world layout were checked visually through the three.js preview renders
  (approximate).

**Not verified (needs a Studio playtest):**

* Real physics and replication: carrying a welded Blobby on the head, knockback velocity,
  smoothness of server-moved Blobbies, the local-only laser door collision trick.
* Client animation: Motor6D bob, spinners and rainbow cycling (the code paths ran in Lune, but
  nothing was rendered).
* UI layout and scaling on real screens (UIScale on a ScreenGui, phone layout, overlap with the
  Roblox top bar, player list and chat), and gamepad selection flow.
* TextChatService system messages and the VIP tag, SocialService invites, MarketplaceService
  prompts, PolicyService, and real DataStore and OrderedDataStore behaviour and limits.
* Performance with 8 full bases (about 1,100 world parts plus up to 17 × 8 Blobbies of 8 to 40
  parts each, plus up to 28 on the carpet).
* Balance: the numbers are reasoned and payback times are unit tested, but nobody has played them.
