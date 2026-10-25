# PHONES AWAY!

A funny, tense high-school stealth game for Roblox (up to 12 players in one classroom). Everyone
sits at a desk while **Ms. Bellweather** teaches. Sneak your phone out to scroll, text, play and
take selfies for **Clout**. Hide it before she sees you. If her suspicion of you fills up, she
**CONFISCATES** your phone and you go to the detention corner. The class goes on without you.

The genre is "using your phone in class without the teacher catching you". The game is original:
original names, characters, rules, UI and art. Everything is built from code: the school, the
teacher rigs, the phones, the desk decorations, the effects and all the UI. There are no imported
models and no uploaded images.

Rojo project name: `PhonesAway`.

## Build, run, test

```bash
cd phones-away
rojo build -o build/PhonesAway.rbxlx   # open this file in Roblox Studio
rojo serve                              # or live-sync with the Rojo Studio plugin

selene src                              # lint (custom std: roblox_min.yml)
lune run tests/compile                  # compile every source file
lune run tests/run                      # unit tests (pure logic)
rojo build -o build/PhonesAway.rbxlx && lune run tests/harness build/PhonesAway.rbxlx
```

In Studio:

* **Solo:** press Play. The hallway countdown is 12 s when you're alone. Then the bell rings, you
  are seated, and class starts.
* **Multiplayer:** Test → Clients and Servers with 2 to 12 players. This tests seating, notes,
  paper airplanes, Teacher's Pet reports, the group chat and the Pizza Party.
* **Saving:** turn on *Game Settings → Security → Enable Studio Access to API Services*. Studio
  uses separate stores, `PhonesAway_Profiles_v1_Studio` and `PhonesAway_TotalClout_v1_Studio`,
  so free Studio test grants never reach live data. Without API access the game runs in memory
  and says so.
* **Robux items:** while the IDs are `0`, every product and pass is granted for free in Studio.
  Passes granted this way last for the session only.

## How to play

1. **Hallway (between classes):** shop at the School Store kiosk (or the SHOP button), buy
   upgrades and cosmetics, check the leaderboard, claim your daily reward, redeem codes.
2. **Bell:** you're seated at your desk. Friends sit next to each other. VIPs get the gold desks
   in the back row.
3. **Class (3:20, the wall clock runs from 10:05 to 10:55):** hold your phone button to use it.
   Let go to hide it. Watch the teacher:

| Phase | What she does | Risk |
|---|---|---|
| Writing on the board | Back to the class. Every few seconds she **pauses** ("..." bubble), then glances over her shoulder | SAFE (watch for the pause) |
| Lecturing | Faces the class and sweeps her gaze slowly. She drifts toward suspicious students | RISKY |
| Walking the rows | Walks the aisles, scans desks left and right, checks desks up close | VERY RISKY |
| Pop Quiz | Everyone answers a simple question in 9 s. **Anyone with a phone out gets it wrong** | Phones = wrong |

4. **The teacher AI** keeps a **suspicion meter for each student**. The server alone decides what
   she sees:
   * **Sight:** a field-of-view cone that turns slowly. You can see it on the floor, tinted by your
     own suspicion. A phone that is out, coming out, being hidden, or still glowing in the desk is
     visible in the cone. The closer she is, the worse. A phone case dims the glow, a hood or a
     textbook stand covers part of it, and a selfie flash is 5x brighter.
   * **Desk checks:** while she walks the rows she checks desks up close, and cover barely helps.
   * **Hearing:** every screen tap makes noise, which she hears in all directions. Earbuds make
     you quieter.
   * A **"?"** over her head means she's suspicious of you. **"!"** means she's about to catch
     you. At full suspicion: *CONFISCATED!* You lose half the Clout you earned this class, your
     phone goes into the basket on her desk, and you sit in the detention corner until the bell.
5. **Escape detention once per class:** talk your way out (Clout, scales with level) or use a
   *Get Out of Detention* pass. You return with suspicion at 45% and an 8 s phone cooldown.
6. **Bell:** the Clout you earned this class is banked. The results show the class's top three,
   and the **Phone Legend** (most Clout without getting caught) is announced.

### Phone apps (tiny minigames, all validated on the server)

| App | How | Reward |
|---|---|---|
| Scroll Feed | LIKE posts, NEXT for a new one. 8% of posts are VIRAL (x4) | 1.5 Clout per like |
| Text Bestie | Reply with the word your bestie asks for: tap a quick reply (1/2/3) or type it | 6 + up to 6 for speed |
| Tap Dash | Tap when the marker is in the zone: gold = Perfect, green = Good. Combos up to x2 | 2–4 + combo |
| Selfie | SNAP. 9 s cooldown. The flash is very risky | 22 |

You also earn passive Clout every second the phone is out (0.8/s × your phone's rate).

### Social

* **Paper airplane:** throw one at any desk (seating chart). When it lands she turns toward the
  noise for 3.2 s, which gives your friends cover. If she sees you throw it, you gain suspicion.
  3 per class, 18 s cooldown.
* **Pass a note:** only to the desk right next to you. Both of you get +8 Clout, and it rustles
  (noise).
* **Teacher's Pet mode** (opt-in in the hallway, `[PET]` tag): you get a REPORT button. Telling on
  a student whose phone is out adds 22% suspicion to them and gives you +6 Clout. You also get
  +25% quiz rewards. Limits: 3 reports per class, 20 s cooldown, and a false report gives you
  15% suspicion. This keeps it a fun twist without ruining the round.
* **Class group chat:** funny auto messages from invented classmate handles when someone gets
  caught, escapes, takes a selfie, buys pizza, and so on. Real players are never quoted.
* **Party seating:** friends (`IsFriendsWith`) sit in neighbouring desks.

### Random class events (one per class, or none)

| Event | Effect |
|---|---|
| Substitute Teacher | Mr. Dozely subs. He is lenient (0.55x detection), turns slower and naps (sees nothing for 6 s) |
| The Principal walks in | Principal Granite stands in the doorway for 24 s: **double detection** plus a second pair of eyes |
| Fire Drill | 16 s of chaos. The alarm rings, the teacher spins around, detection drops, Clout x1.5 |
| Early Lunch Bell | She walks to the door and checks the hallway with her back to the class for 12 s. Clout x1.25 |

### Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Use phone (hold) | Hold **F** (or hold the PHONE button) | Hold **L2** | Hold the big PHONE button |
| App action (like / tap / snap) | Space / E / click | R2 / A | tap the button |
| Next post (feed) | S | – | NEXT |
| Quick reply (text) | 1 / 2 / 3 | D-pad left / up / right | tap |
| Switch app | Q / Tab, or the tabs | R1 / L1 | tabs |
| Airplane / note / report | buttons → seating chart | UI selection | buttons |
| Menus | buttons | Select focuses the menu | buttons |

The UI scales with a `UIScale` on every ScreenGui, so it fits phones. Jumping out of your chair
is disabled during class.

## Systems

| System | Where | Notes |
|---|---|---|
| Round flow | `RoundService` | Hallway → Bell → Class → Results. 10 Hz authoritative tick. Late joiners wait in the hallway |
| Lesson schedule | `shared/Lesson` | Seeded. It always opens with the board, has one pop quiz near the middle, at least 2 walks, and at most one event |
| Teacher AI | `shared/TeacherBrain`, `TeacherService` | Pure state machine: board glances with a telegraphed pause, lecture sweep and focus drift, aisle walking with desk scans, distract, point/caught, nap, panic, door check |
| Detection | `shared/Detection` | Pure sight cone (soft edge, distance), visibility states, desk checks, noise and hearing, flash, suspicion rise/decay. It adapts the sight + noise split of DEAD AIR's MonsterBrain |
| Phones | `PhoneService`, `shared/Minigames` | Up/down states with raise and hide delays, glow linger, server-side minigames, per-class caps (900 base Clout total, per-app caps), 8 actions/s budget, toggle spam limit |
| Social | `ClassmateService` | Airplanes, notes, Teacher's Pet, group chat |
| Seating | `shared/Seating` | VIP desks first, friend groups placed contiguously, then the rest shuffled |
| Economy | `shared/Economy` | Pass multipliers add up and are capped at 2.2x. Upgrade stats, levels and ranks, daily streak, codes, bail cost |
| Data | `DataService` | Copies Sprout Valley's reviewed approach: DataStore + **session lock**, retries, versioned defaults and reconcile, autosave every 90 s, save on leave and on BindToClose, in-memory fallback, `_Studio` store in Studio. leaderstats: Clout, Rank |
| Shop | `ShopService` | Receipts are de-duplicated in the profile and **saved before PurchaseGranted**. In a live game, if the profile can't be saved: **NotProcessedYet**. Pass checks are cached. PolicyService covers paid random items |
| Cosmetics / upgrades | `CosmeticService`, `shared/CrateRoll` | Clout upgrades, phone skins, desk decor, wallpapers, crates with published odds, pity at 30, duplicate refunds, server-wide announcement for Legendary and Mythic pulls |
| Leaderboard | `LeaderboardService` | OrderedDataStore "Most Clout Ever" in the hallway. Every call is in pcall and it refreshes every 60 s. It falls back to this server's players |
| World | `ClassroomBuilder`, `shared/TeacherRig`, `shared/Props` | About 640 parts for the school. The teacher rigs use Motor6D joints and 42–52 parts each |
| Client | `HudController`, `PhoneController`, `TeacherController`, `MenuController`, `EffectsController` | HUD, the phone UI and apps, procedural teacher animation, vision cones, "?"/"!" marks, menus, juice |

### Progression and retention

* **Clout** is the currency. **Upgrades** (all buyable with Clout):
  * phone model: 6 tiers, 1.0x → 3.3x Clout/s
  * phone case: dimmer glow, down to 58%
  * earbuds: quieter taps, down to 38% noise
  * cover (hood → textbook stand → textbook fort): down to 64% visible
  * hide speed: 0.45 s → 0.20 s
  * backpack spot: the glow lingers 1.0 s → 0.2 s after you hide the phone
* **Cosmetics:** 10 phone skins, 9 desk decorations, 8 wallpapers, from Common to Mythic.
  Classmates see your skin when your phone is out.
* **Levels and ranks:** XP from earned Clout, finished classes and quizzes.
  Freshman (1) → Sophomore (5) → Junior (10) → Senior (16) → Legend (25). Each level-up gives
  +40 Clout, and new ranks are announced.
* **Daily streak:** 7 days (50 → 500 Clout). VIP gets +50%.
* **Codes:** `RELEASE` (250), `NOPHONES` (150), `SKIPCLASS` (100 + a Fake Hall Pass), `LIKE1K`
  (300, for the "like the game" poster in the hallway). Edit them in `ProgressionConfig.Codes`.
* **Session goals:** 3 at a time, for example "Use your phone for 30s while she walks the rows",
  "Earn 150 Clout in one class", "Ace a Pop Quiz", "Distract her with a paper airplane".
* **Invite:** "BRING YOUR CLASS" uses `SocialService:PromptGameInvite` after
  `CanSendGameInviteAsync` (pcall). +75 Clout once per session.
* **Global leaderboard** for lifetime Clout in the hallway.

## Robux shop

The **SHOP** button is always on the HUD, and the School Store kiosk in the hallway opens it
too. Tabs: Clout, Social, Escapes, Crates, Game Passes. Prices show as "R$ 49". Everything is
defined in `src/shared/Config/ShopConfig.lua`.

| Developer Product | Display price | What it does |
|---|---|---|
| Pocket / Trending / Viral Clout | R$ 25 / 79 / 249 | +500 / +2,000 / +7,500 Clout |
| Get Out of Detention | R$ 25 | Leave detention right away and get your phone back. Bought outside detention, it's saved as a token. Once per class |
| Fake Hall Pass | R$ 35 | Your next catch is forgiven. Used automatically, once per class |
| PIZZA PARTY! | R$ 99 | The **whole server** gets a lenient teacher (0.5x detection) and **2x Clout** for one class. Bought during class it starts right away, otherwise the next class (queue capped at 3). The buyer is announced to everyone |
| Phone Skin Crate | R$ 49 | A random phone skin, Rare or better. **The odds are shown** before buying. Hidden and refused when `PolicyService` says `ArePaidRandomItemsRestricted`, or when the policy lookup fails |

| Game Pass | Display price | What it does |
|---|---|---|
| 2x Clout | R$ 199 | +100% Clout |
| VIP | R$ 149 | VIP name and chat tag, +10% Clout, the gold VIP desk in the back row, +50% daily |
| Silent Mode | R$ 99 | Permanent earbuds at tier 3 of 4 |
| Extra Hide Speed | R$ 79 | Hide 0.05 s faster on top of your upgrades (minimum 0.15 s) |
| Pro Phone | R$ 249 | Exclusive Prism Pro: 3.6x Clout/s (10% above the best Clout phone) |

**Pay-to-win is bounded:**
* Every gameplay upgrade can be bought with Clout.
* Pass multipliers are capped at 2.2x.
* Silent Mode is below the best Clout earbuds.
* The passes never touch suspicion rules.
* Escapes work once per class.
* Per-class Clout caps apply to everyone.
* The Pizza Party helps the whole server.

A skilled free player who reads the teacher wins classes.

### Setting up the shop (Creator Hub)

1. Publish the place. Then open create.roblox.com → your experience → **Monetization**.
2. **Developer Products:** create one product for each entry in `ShopConfig.Products` (7
   products: Clout500, Clout2000, Clout7500, DetentionPass, HallPass, PizzaParty, SkinCrate) and
   set its price. Paste each numeric ID into that entry's `ProductId`.
3. **Game Passes:** create the 5 passes (DoubleClout, VIP, SilentMode, ExtraHide, ProPhone) and
   paste each ID into `PassId`.
4. Keep the display `Robux` values the same as the real prices.
5. While an ID is `0`, the live game shows "This item isn't available yet" instead of selling it.

## Audio

No asset IDs were invented. `src/shared/Config/AudioAssets.lua` has two kinds of slot:

* **Reused from the DEAD AIR project** (Roblox licensed partner libraries):
  * TerminalBeep → phone taps
  * DrawerOpen / DrawerClose → phone out / away
  * Pickup → Clout gain
  * AlarmClockRing → school bell
  * Alarm → fire drill
  * DoorOpen / DoorClose
  * Locker
  * ItemDrop → paper airplane landing
  * FailSting → caught
  * EscapeSting → class over
  * CardSwipe → purchase
* **Empty slots** (`Id = ""`, skipped until you add your own): SelfieShutter, Notification,
  MarkerSqueak, ClassMusic, HallwayMusic, Suspicious ("?"), Alert ("!"), QuizSting,
  PizzaFanfare, LevelUp, Click.

Gameplay never depends on audio. The teacher "hears" taps through the server's noise model.

## Publishing checklist

- [ ] Create the products and passes and paste their IDs (see above). Test a real purchase in a
      private server, including a Pizza Party and a Get Out of Detention pass.
- [ ] Enable API Services. Check that saving works across two sessions and that the leaderboard
      fills.
- [ ] Set Max Players to **12** (Game Settings → Places). There are 12 desks.
- [ ] Upload an icon and thumbnails (ComfyUI prompts are in POLISH.md). Fill the empty audio
      slots.
- [ ] Genre: Comedy / Party & Casual. Devices: Phone, Tablet, Computer, Console.
- [ ] Watch real classes and tune `TeacherConfig` (sight rate, cone, decay) and `PhoneConfig`
      (rewards, caps). See POLISH.md.
- [ ] Put the `LIKE1K` code in the description ("Like the game for a code at 1K likes!").

### Maturity questionnaire suggestions

This is a lighthearted school comedy for **all ages**. Expect **Minimal** (at most **Mild**):

* **Violence / blood / gore:** none. "Caught" means the phone goes into a basket and you sit in
  a detention corner.
* **Fear:** none. The teacher is a friendly cartoon character with rosy cheeks, glasses and a
  pencil in her hair bun.
* **Crude humour:** mild school jokes only ("F in the chat", "caught in 4K").
* **Romance, drugs, alcohol, gambling with real money:** none.
* **Paid random items:** yes. The Phone Skin Crate shows its odds before purchase and is hidden
  and refused where `PolicyService` restricts paid random items.
* **Social:** the group chat uses invented handles and fixed lines. There is no free-text
  player-to-player content beyond Roblox's own chat.

## Honest status

**Verified here** (Linux sandbox, no Roblox Studio):

* `selene src` reports 0 errors and 0 warnings. `lune run tests/compile` compiles every file.
* 49 unit tests cover:
  * detection maths, the teacher brain in every phase, lesson schedules over 200 seeds, and
    the school clock
  * minigame validation and caps
  * the economy, crates and odds, and seating
  * config sanity, including "no invented audio IDs"
* The Lune harness (34 checks) loads the **built .rbxlx**, builds the whole school and every
  rig and prop against Lune's reflection-checked Instance API, and runs the real services with
  stubbed engine services. It covers:
  * board phase vs. walking phase with the same phone use: board stays safe, the walk gets
    caught after about 5 s
  * confiscation, detention, bail, the detention-pass receipt sent twice and granted once, and
    the Fake Hall Pass
  * the pop quiz (phone users wrong), the airplane distraction, notes and Teacher's Pet limits
  * remote validation, rate limits and caps, and the selfie flash
  * banking at the bell, the Pizza Party (queued, announced, 2x for everyone, lenient
    teacher), the principal event and leaving mid-class
  * upgrades and cosmetics, crates with PolicyService, daily rewards and codes, and the
    leaderboard fallback
  * live-game NotProcessedYet, the DataStore session lock, and `_Studio` vs. live store names
  * five complete classes on the real schedule, one per event type
  * initialising every client controller and rendering every panel, app, pose and effect

**Not verified** (no Studio playtest was possible):

* Real physics and seating (`Seat:Sit`, jump disabling).
* How the procedural animation looks.
* Camera feel.
* Network smoothing of the teacher.
* Mobile layouts on real devices.
* Real DataStore, MarketplaceService and PolicyService behaviour.
* Audio.

Balance values come from a small offline simulation (smart vs. greedy players per phase) and
need tuning with real players.
