# LAST LIFEBOAT

*The ship is sinking. One boat. Go!*

LAST LIFEBOAT is a co-op escape game for Roblox, for 1–8 players. A huge ship is going down. Your crew spawns in the lowest deck at the bow. Climb up and back through the flooding, tilting ship to the **last lifeboat** at the stern of the top deck before it launches. On the way, grab valuables (risk against reward) and save each other.

The ship doesn't sink smoothly. It goes down in sudden **LURCHES**. Every ~20 s a horn blares, the screen flashes red, **BRACE!** appears, and the whole ship drops a few studs and tips further bow-down. Loose chairs and crates slide, chandeliers fall, and the sea floods one more stretch of deck.

> **Honest status.** This is a Rojo project. It has **never been opened or played in Roblox Studio** (there is no Studio here).
>
> What *was* verified headlessly, in Lune:
> - every file lints (`selene`: 0 errors, 0 warnings) and compiles (43 files);
> - **41 unit tests** pass. They cover:
>   - ShipGen, for every ship over 8 seeds: the lifeboat is reachable from spawn with no dive and every bulkhead shut; every deck cell is connected; every loot spot is reachable and clear; the part budget holds; route choice exists.
>   - The lurch maths: tilt and sink curves, pivot deltas, the client's relative move, waterline and slide.
>   - Oxygen, downed and revive timers, life jackets.
>   - Loot slots, weight, rarity rolls and the payout.
>   - Upgrade costs and effects; the daily streak, codes, ship unlocks and the vote.
>   - Config sanity and audio coverage.
> - **33 harness checks** pass. They run the real server and client modules against Lune's Roblox instance model, with stubbed engine services, stubbed Terrain (`FillBlock` is recorded) and a fake clock. They time the world build and play three ship rounds. They cover:
>   - Voting and ready-up (locked ships, ties, pads, the 25 s auto-start).
>   - Lurches that really move the ship's pivot, with the brace warning first.
>   - Loot with slots and weight, legendary announcements and drops.
>   - Valves, a two-lever bulkhead and the solo hold.
>   - Steam, chandeliers and wires.
>   - Drowning, then downed, revive and bleed-out; the life jacket and the rescue flare.
>   - The grapple validation and the ship guard.
>   - A Full Crew early launch with the x2 pass, a timed launch, an empty launch, and leaving mid-round.
>   - Receipts sent twice, the session lock, junk remotes, and every client controller rendering real server data.
>
> Lune has no physics, no terrain voxels and no renderer, so the harness moves characters itself and "underwater" is the same world-Y test the game uses. The ship and harbour were checked visually with three.js renders of the exported parts (`build/preview-*.png`). Those are not Roblox's renderer. **Follow the Studio test plan below before publishing.**

## Quick start

```bash
cd last-lifeboat
rojo build -o build/LastLifeboat.rbxlx   # open it in Roblox Studio and press Play
# or live-sync: rojo serve              (then Connect in the Rojo Studio plugin)
```

1. Open `build/LastLifeboat.rbxlx` in Studio.
2. **To test saving:** go to Game Settings → Security and turn on **Enable Studio Access to API Services**. Without it the game still runs and tells you saving is off.
3. Press **Play** (solo), or **Test → Clients and Servers** with 2–4 players. Bulkheads, revives and Full Crew need friends.
4. Studio uses separate `_Studio` DataStores, so test saves never touch live data. Robux items with an ID of 0 are granted free in Studio for testing.

## Controls

| Action | Keyboard | Gamepad | Mobile |
|---|---|---|---|
| Interact (grab loot, levers, valves, revive) | hold **E** | hold **X** | tap / hold the prompt |
| Grapple Hook (pass) | **Q** (aims at the mouse) | **L1** (aims at the screen centre) | **GRAPPLE** button |
| Rescue Flare (if you own one) | **F** | **DPad up** | **FLARE** button |
| Menu / shop | **M** | **Select** | **MENU** / **SHOP** buttons |
| Drop a carried item | click its slot | – | tap its slot |

## How a round plays

1. **The harbour (lobby).** It is a dock at dusk with lanterns, crates, bunting and a departures arch, and a ship moored alongside. The dock also has:
   - the **ticket booth** (shop), the **Hall of Survivors** leaderboard, the **daily reward** sea chest and the **codes** post box;
   - three **vote pads**, one per ship.

   Press **READY** and vote a ship, either with the cards on the lobby panel or by standing on its pad. Votes only count for ships *you* have unlocked. The most votes wins and a tie goes to the easier ship. The countdown (6 s) starts when everyone is ready, or 25 s after the first player readies up.
2. **Boarding.** The voted ship is built a few hundred parts per frame. If it is the fresh ship already at the dock, it is reused. The crew spawns on the lowest deck at the bow.
3. **Escape aft and up.** The **lifeboat timer** shows "LIFEBOAT LAUNCHES IN m:ss". Climb stairs, ladders and service shafts. The routes zig-zag, and some stairwells are blocked by debris, so you have to pick a route.
4. **Lurches** come every 18–25 s (per ship). Each one has a 2 s **BRACE!** warning (alarm, horn, red flash), then the ship drops and tips. Your client keeps your character in place on the deck, and the camera shakes. Above 12° of tilt you slide gently downhill toward the bow (Grip upgrade reduces it).
5. **The water** is static terrain at sea level, so anything the ship sinks below Y = 0 is flooded and you swim with Roblox's own swimming. When your head is underwater, oxygen drains (12 s base). At zero you're **DOWNED**: you float to the surface (or just under a ceiling), can't move, and bleed out in 20 s. A teammate holds **E** for 2 s beside you to revive you with 50% oxygen. If nobody comes you're **out**: you watch your crew from the dock and lose your loot.
6. **The last lifeboat.** Step into its seat zone. If everyone still in the round (alive or downed) is aboard for 3 s, it launches **early** with a **Full Crew bonus (x1.25)**. Otherwise it launches when the timer ends. It swings out past the stern, lowers to the sea and rows away while the ship takes its final plunge. Everyone aboard **ESCAPED** and gets paid; everyone else is **LOST AT SEA** and gets a small participation reward.
7. **Results:** who escaped, your loot banked, each coin line, and your session goals. Then everyone is back on the dock and a fresh ship is moored.

A round always ends. The boat launches on time, early with a Full Crew, or empty if nobody is left alive or downed. The round is aborted if every participant leaves.

## The ships

| Ship | Decks (bottom → top) | Length / beam | Round | Lurch every | Max tilt | Loot × | Unlock |
|---|---|---|---|---|---|---|---|
| **The Gull** (ferry) | Cargo Hold, Cabins, Top Deck | 160 / 44 | 3:00 | 18–22 s | 22° | ×1 | always |
| **Aurora Grand** (cruise liner) | Engine Room, Crew Quarters, Cabins, Grand Dining Hall, Top Deck | 240 / 56 | 4:00 | 19–23 s | 25° | ×1.5 | 3 escapes |
| **Iron Leviathan** (giant liner) | Engine Room, Cargo Hold, Crew Quarters, Cabins, Grand Dining Hall, Promenade, Top Deck | 320 / 64 | 5:00 | 20–25 s | 27° | ×2.2 | 10 escapes |

All three come from one parametric generator, **`ShipGen`**. It is a pure planning module and unit-tested:
- The hull tapers in a parabola over the last three cells to a narrow bow and is rounded off at the stern.
- Decks are 16-stud cells. Each deck boundary gets a main stair (a **grand staircase** out of the dining hall), a ladder, and between the lower decks a **service shaft at the bow**. The shaft is the dive shortcut: it floods first.
- Debris blocks one of the dry routes about half the time.
- **Bulkhead doors** cut some decks. ShipGen guarantees the whole ship stays connected with every bulkhead shut, so they are shortcuts.
- It also places one valve per deck, the hazards, the loot spots, the spawn, the lifeboat and the deckhouse.

**`ShipBuilder`** turns the plan into parts:
- **Hull:** a dark hull with a red boot-top, a coloured cheatline and white upper works; belt lines at every deck; warm portholes (big windows on the Promenade); a stem, rudder, propellers and the ship's name on both bows and the stern.
- **Top deck:** teak planking, cap rails and lamp posts; a deckhouse (two tiers on the liners) with the bridge and its wings; raked funnels (smoke on the first); masts with lights and stays.
- **Lifeboat area:** empty davits along both sides (the other boats are gone), cowl vents, a cargo hatch, a helm station with a ship's wheel, binnacle and telegraph, and the stern gantry davits holding the last lifeboat. A green beacon lamp marks it.
- **Deck themes:**
  - Engine Room: boilers, pipes, catwalks.
  - Cargo Hold: crate stacks, cars under tarps, wire cages.
  - Crew Quarters: bunks, lockers, mess tables.
  - Cabins: a corridor of cabin doors, beds, suitcases.
  - Grand Dining Hall: round tables with candles, chairs, chandeliers, a grand piano and the grand staircase.
  - Promenade: deck chairs, benches, palms, brass railings.

Part counts (vary a little by seed): Gull ≈ 710, Aurora ≈ 1,670–1,690, Leviathan ≈ 2,860–2,910, plus loot (about 4 parts per item, 14–36 items). The harness checks the Leviathan stays within 1,500–3,500 and that the ShipGen estimate is within 30% of the real count.

## Sinking (the lurch)

- **Ship-local frame:** the pivot is the stern on the centreline at the waterline.
- **Lurch *k* of *N*:** the pivot moves to `base * CFrame.new(0, -sink_k, 0) * CFrame.Angles(rad(tilt_k), 0, 0)`, where `tilt_k = MaxTilt * (k/N)^1.6` (small lurches first, 3–4° at the end) and `sink_k = MaxSink * k/N`. *N* is the number of lurches expected in a round.
- **On the server**, a lurch is one `PivotTo`. Loose props (at most 40 per ship, low friction) are carried by the same delta and nudged downhill. Downed bodies, which the server has anchored, are carried too.
- **On the client**, the `Lurch` remote carries both pivots. Each client moves its own character by the delta (`LurchMath.relocate`): same spot on the deck, kept upright, turned with the ship's yaw.
- **Valve wheels** (one per deck, single use) push the next lurch back 6 s, so a crew that closes valves ends the round less tilted.
- **The sea** is terrain water. It fills a wide harbour 24 studs deep and a 240-stud trench under the berth, deep enough for the Leviathan's bow at its final plunge (unit-tested). It is filled two blocks per frame at startup.

## Obstacles and hazards

- **Bulkhead doors:** two levers on the bow side. Two players holding both levers at once open the door (it slides up into the ceiling). If you are the only one still up (solo), holding one lever for 4 s opens it.
- **Steam pipes** (Engine Room, Crew Quarters, Cargo Hold) burst on a 7 s cycle. An amber light and a hiss warn you 1.6 s ahead, then the burst knocks you back and does a little damage.
- **Chandeliers** (dining hall): on each BRACE one chandelier shows a dark warning shadow on the floor, and it drops on the lurch. Damage is checked in ship space against the pre-lurch pivot, because the clients haven't moved yet.
- **Sparking wires** (lower decks, bow half) only matter once flooded. Every 1.6 s they zap anyone underwater nearby for 3 s of oxygen.

## Loot

- 13 valuables in four rarities: **Common** (cream), **Rare** (blue), **Epic** (purple) and **Legendary** (gold). They include a pocket watch, silver spoons, a pearl necklace, a captain's compass, a crystal decanter, a jewel box, a gold bar, a painting, a ruby tiara, a golden sextant and a star sapphire.
- Lower decks and bigger ships roll rarer loot. The decks that flood first hold the best loot.
- Hold **E** to grab. You have 3 slots (Loot Slots upgrade up to 6, VIP +1). Gold bars and paintings are **heavy** and lower your WalkSpeed (never below 9). Tap a slot to drop the item.
- A Legendary find is announced to the whole server.
- **Only escaping pays.** The payout is `floor(value × ship ×1/1.5/2.2 × Full Crew 1.25 × x2 Loot pass) + 40 × ship + 10 per revive`. Lost at sea pays 15 (+ revives).

## Progression and shop

- **Coin upgrades** (ticket booth or menu, 5 levels each): **Lung Capacity** (12 → 25 s of air), **Swim Speed** (×1 → ×1.4), **Grip** (slide ×1 → ×0.3), **Loot Slots** (3 → 6), **Climb Speed** (×1 → ×1.5).
- **Daily login streak** (7 steps, 60–300 coins).
- **Codes:** `RELEASE` (200 coins), `MAYDAY` (150 coins + a Life Jacket), `ABANDONSHIP` (250 coins).
- **Session goals** (each pays once per server visit): *Escape 2 times*, *Revive a teammate*, *Bank a Rare or better*.
- **Global leaderboards** (OrderedDataStore, refreshed every 75 s): **Total Escapes** and **Loot Banked**, on the harbour board and in the menu.
- **Stats panel**, **friend invite**, **first-round tutorial hints** (can be turned off).

**Robux shop** (all optional; prices are display-only, the real price is set in Creator Hub):

| Item | Type | Price | What it does |
|---|---|---|---|
| Life Jacket | Developer Product (stackable) | R$ 25 | Auto-revives you once when you go down (max one per round) |
| Rescue Flare | Developer Product | R$ 49 | Revives every downed teammate within 30 studs + a route arrow to the lifeboat for 15 s for the whole crew |
| Pouch / Chest of Coins / Captain's Hoard | Developer Products | R$ 49 / 129 / 349 | +500 / +1,500 / +4,500 coins |
| x2 Loot | Game Pass | R$ 199 | Banked loot pays double |
| Grapple Hook | Game Pass | R$ 249 | Grapple to a surface within 40 studs, 12 s cooldown. The server checks the pass, cooldown, range, finite input and a raycast. |
| Captain's Outfit | Game Pass | R$ 149 | A cap and a navy coat with brass buttons and epaulettes, built from parts. Cosmetic. |
| VIP | Game Pass | R$ 299 | +1 loot slot, a gold **[VIP]** chat tag and a gold name over your head |

Pay-to-win is bounded:
- A jacket saves you once per round.
- The flare only helps people near you.
- The grapple has a long cooldown.
- VIP is one slot, and free players reach 6 slots with coins.
- Nothing changes the lurch timer, oxygen drain or the boat.

## UI

The palette is nautical: navy panels, brass strokes, cream text and signal red. Panels have rounded corners. Every ScreenGui has a **UIScale** (0.58–1.15 by viewport), so the layout shrinks on phones.

The HUD has:
- the lifeboat timer and next-lurch countdown;
- a **tilt / depth indicator** (a ship silhouette tipping over a water line, the tilt in degrees, your deck and how far above the sea you are);
- the oxygen bar (teal → amber → red) and the carried-loot slots (3D icons with rarity strokes, HEAVY tags, carried value);
- the **BRACE!** banner and red edge flash;
- the downed overlay with the bleed-out timer and a revive progress bar;
- the spectate bar, the flare route arrow and a cinematic letterbox;
- the team list (state, oxygen, ABOARD);
- toasts, announcements, the results card and tutorial tips;
- side buttons: SHOP, MENU, GRAPPLE and FLARE.

Underwater the screen gets a teal grade and blur. Downed is desaturated. *Reduced effects* tones these down.

## What you need to add before publishing

| Item | Where | Notes |
|---|---|---|
| 5 Developer Products | `src/shared/Config/ShopConfig.lua` → `ProductId` | LifeJacket (R$25), Flare (R$49), Coins500 (R$49), Coins1500 (R$129), Coins4500 (R$349) |
| 4 Game Passes | `ShopConfig.Passes[i].PassId` | DoubleLoot (R$199), Grapple (R$249), Captain (R$149), VIP (R$299) |
| 5 empty sound slots | `src/shared/Config/AudioAssets.lua` | Waves, Seagulls, Splash, Gasp, Oars (see **Sound**) |
| Icon and thumbnails | see `POLISH.md` | none are included |

### Shop setup steps
1. Publish the place (File → Publish to Roblox), then open it in **Creator Hub → Creations → (experience) → Monetization**.
2. **Developer Products → Create**: one per row in `ShopConfig.Products` (same name, price as in the table). Copy each **Product ID** into its `ProductId`.
3. **Passes → Create a Pass**: one per row in `ShopConfig.Passes`, put it **on sale** at its price, and copy each **Pass ID** into its `PassId`.
4. Rebuild (`rojo build`) and republish. With real IDs the Buy buttons prompt real purchases. In a live game, items whose ID is still 0 say "not available yet". `ProcessReceipt` grants each `PurchaseId` once, saved before it acknowledges.

## Sound

**No asset IDs were invented.** Every filled slot reuses an ID that the DEAD AIR project in this repo already uses (a unit test enforces it). Five slots are empty (`Id = ""`) and are skipped by the code until you add your own.

| Slot | Made from (DEAD AIR slot) | Stand-in? |
|---|---|---|
| Brace / Horn | Alarm (short) / Alarm pitched 0.5 | Horn: **yes – a real ship's horn would be much better** |
| Lurch | DistantImpact + PipeCreak + DoorSlam, all low | partly |
| ShipCreak / ShipHum | PipeCreak low / VentilationLoop low | yes |
| Pickup / PickupRare / Coins | Pickup | no |
| Legendary | EscapeSting pitched up | no |
| Drop | ItemDrop | no |
| LowOxygen | Heartbeat | no |
| Downed | DistantImpact | yes |
| Revive / Lever | BreakerPull | yes |
| Bulkhead | HeavyDoor | no |
| Valve | PipeCreak + FuseInsert | yes |
| SteamHiss / SteamBurst / Flare | FuelPour pitched up | **yes – replace with real steam** |
| Spark | FluorescentBuzz, short and high | yes |
| ChandelierFall | GlassBreak + MetalDrop | no |
| PropSlide / Grapple | CanClatter | yes |
| Winch | PipeCreak | yes |
| LobbyMusic / RoundMusic / FinalMinute | LobbyMusic / TensionLayer / ChaseLayer | no |
| Countdown / UIClick | TerminalBeep | no |
| Escape / LostAtSea | EscapeSting / FailSting | no |
| **Waves, Seagulls, Splash, Gasp, Oars** | – | **empty: add your own** |

## Studio test plan

1. **Solo, the Gull.**
   - Ready up and watch the ship build at the dock (it should take well under a second).
   - On spawn: you're on the lowest deck at the bow.
   - At the first BRACE!: alarm, horn, red flash. On the lurch your character stays put on the deck (no falling through, no sliding off, no snapping) and the camera shakes.
   - The water: the bow floods within a minute or so. Swim through a flooded corridor and watch the oxygen bar. Go down, check that you float up, and check the bleed-out timer.
   - Grab loot (E), feel the gold bar slow you down, drop an item.
   - Close a valve and watch the next-lurch timer jump +6.
   - Solo-hold a bulkhead lever for 4 s.
   - Board the lifeboat: solo counts as a Full Crew after 3 s. Watch the cinematic and the results.
2. **2–4 clients, the Aurora** (set your `Escapes` stat to 3 in a Studio profile, or play 3 rounds).
   - Two players on a bulkhead's levers.
   - Revive a downed friend: the downed player sees the progress bar.
   - Chandelier shadow → drop; steam bursts; wires zap once flooded.
   - Leave mid-round while holding a lever and carrying loot.
   - Timed launch with one player off the boat (LOST AT SEA).
3. **Physics feel** (not testable headlessly):
   - The slide force above 12° (`Sinking.SlideAccel`): gentle but noticeable?
   - Loose props sliding (low-friction `CustomPhysicalProperties`).
   - Stairs at 25° of extra tilt: they ascend toward the bow, so tilt makes them shallower. Check they are still easy.
   - The grapple pull (`Grapple.PullSpeed`).
   - Swimming speed with the Swim upgrade.
4. **Lurch relocation on a laggy connection:** use Studio's network simulator, or watch for a frame where characters drop before being moved. The client moves on the `Lurch` remote, which normally arrives with the ship's new CFrames. If it ever looks wrong, consider also moving characters by the delta on the server.
5. **Saving** (API access on): rejoin, and check that coins, upgrades, jackets, flares, stats and the streak persist.
6. **Shop:** in Studio every Buy button grants for free. Check the Captain's Outfit, the VIP gold name / chat tag / extra slot, and the grapple.
7. **Mobile emulator:**
   - The lobby panel and HUD scale down.
   - The GRAPPLE / FLARE / MENU buttons don't cover the thumbstick or jump button.
   - Prompts are tappable.

## Publishing checklist

- [ ] Studio test plan passes (above). Fix anything physics-related it finds.
- [ ] Products and passes created; IDs pasted into `ShopConfig.lua`; rebuilt.
- [ ] Game Settings → Security: **Enable Studio Access to API Services** (for testing). Live servers always have DataStores.
- [ ] Empty sound slots filled (or left silent on purpose).
- [ ] Icon (512×512) and 3 thumbnails (1920×1080) uploaded (see POLISH.md).
- [ ] Experience description written: pitch, controls, the codes, "free players escape just as well".
- [ ] Server size **8** (the place file already sets `Players.MaxPlayers = 8`; set the same in Game Settings → Places).
- [ ] Genre: Adventure / Survival. Devices: Computer, Phone, Tablet, Console.
- [ ] Maturity questionnaire answered (below).
- [ ] Publish privately first, play a few rounds on live servers with friends, check the leaderboards and saves, then make it public.

## Maturity questionnaire (suggested answers)

Answer the questionnaire yourself; these are suggestions based on what the game contains.
- **Violence:** mild. Hazards knock you back and cost a little health; drowning and "downed" are shown as floating and a timer; nobody dies on screen and there is no blood or gore.
- **Blood / gore:** none.
- **Fear:** mild peril. A sinking ship, an alarm, rising water and time pressure. No jumpscares or monsters.
- **Crude humour, romance, alcohol, drugs, gambling:** none. There are no random paid rewards: loot rolls are free gameplay and every Robux item is a fixed, known thing.
- **Social:** standard Roblox chat (a VIP tag prefix only), friend invites.
- **Paid items:** optional developer products and game passes (listed above).

This should land in the **Mild** maturity band.

## Project layout

```
src/shared/      Config (Game, Shop, Audio); ShipGen, LurchMath, Survival, LootMath, Upgrades,
                 Progress (pure, unit-tested); Models, Parts (procedural parts), Net, Rng, Signal, Format
src/server/      Main.server.lua; World/LobbyBuilder (the harbour), World/OceanBuilder (terrain sea,
                 chunked), World/ShipBuilder (incremental ship builder); Services: Data, Shop, Upgrade,
                 Reward, Player, Ship, Survival, Loot, Obstacle, Lifeboat, Ability, Round,
                 Leaderboard, RateLimit
src/client/      Main.client.lua; Controllers: ClientState, Ui, Input, Movement, Hud, Menu, Effects,
                 Audio, Social
tests/           run.luau (unit specs), harness.luau (headless game), compile.luau, loader.luau
tools/           export_preview.luau, render_preview.mjs (three.js previews into build/)
```

## Checks

```bash
selene src
lune run tests/compile
lune run tests/run
rojo build -o build/LastLifeboat.rbxlx
lune run tests/harness build/LastLifeboat.rbxlx
# previews (needs Playwright + Chromium; set PLAYWRIGHT_MODULE to its path if it isn't local)
lune run tools/export_preview build/LastLifeboat.rbxlx build/preview.json
node tools/render_preview.mjs build/preview.json build/
```

**Startup and build timing (Lune, from the harness):**
- The harbour (~390 parts) builds in about 0.01 s.
- The sea is 134 `FillBlock`s, two per frame (67 frames), each at most ~86k voxels.
- Ships are built 260 parts per frame:
  - Gull: 3 frames
  - Aurora: 7 frames
  - Leviathan: 11 frames; the worst frame of any ship was 7–13 ms in the last runs, and the harness fails above 50 ms.

Nothing big runs synchronously at startup, so Roblox's ~10 s script timeout can't hit.

**Previews** (`build/`):
- `preview-lobby`
- `preview-ship-gull`, `-aurora`, `-leviathan`, `-leviathan-stern`
- `preview-sinking` (mid-sink, tilted, the water line)
- `preview-sinking-deck`
- `preview-plan` (plan view)
- `preview-interior-engine-room`, `-cargo-hold`, `-cabins`, `-dining-hall`, `-promenade`
- `preview-top-deck`
- `preview-loot-and-crew`
