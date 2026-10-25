# PHONES AWAY!

A funny, tense high-school cheating-on-a-test stealth game for Roblox (up to 12 players in one
classroom). **Every class period is a TEST.** A 10-question multiple-choice paper lands on every
desk and on screen, and the exam timer starts. The questions are hard on purpose. So you sneak
your phone out, **SNAP a screenshot** of your test, and keep the phone out while the scanner app
processes. Then it shows you the correct answers to 2 questions (more with upgrades). Put the phone
away and click those answers. Answering is safe; phone use is not. If **Ms. Bellweather**'s
suspicion of you fills up, she **CONFISCATES** your phone, **rips up your test** (F, 0 points) and
sends you to the detention corner. The class goes on without you.

The genre is "cheating during a test without the teacher catching you". Names, characters,
questions, wording, UI and art are all our own; no assets or text from other games. The game is original:
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
3. **Class = TEST (3:20, the wall clock runs from 10:05 to 10:55):** your test paper shows
   10 questions (3 easy, 4 medium, 3 hard, from 5 subjects) with 4 options each, a **VERSION A/B**
   badge and the exam timer. Friends get the **same version** (and sit together) so they can help
   each other; neighbouring groups get the other version. To cheat, hold your phone button and
   SNAP. Watch the teacher:

| Phase | What she does | Risk |
|---|---|---|
| Writing on the board | Back to the class. Every few seconds she **pauses** ("..." bubble), then glances over her shoulder | SAFE (watch for the pause) |
| Lecturing | Faces the class and sweeps her gaze slowly. She drifts toward suspicious students | RISKY |
| Walking the rows | Walks the aisles, scans desks left and right, checks desks up close | VERY RISKY |
| Bonus Question | She reads out one extra (easy) question, 9 s to answer. **Anyone with a phone out gets it wrong** | Phones = wrong |

4. **The teacher AI** keeps a **suspicion meter for each student**. The server alone decides what
   she sees:
   * **Sight:** a field-of-view cone that turns slowly. You can see it on the floor, tinted by your
     own suspicion. A phone that is out, coming out, being hidden, or still glowing in the desk is
     visible in the cone. The closer she is, the worse. A Dim Screen case dims the glow, a hood or
     a textbook stand covers part of it, and the screenshot flash is 2.5x brighter (if she sees the
     flash: instant suspicion). A smart-watch glance is a small, dim glow.
   * **Desk checks:** while she walks the rows she checks desks up close, and cover barely helps.
   * **Hearing:** the screenshot shutter clicks and the scanner app beeps while it works. She
     hears that in all directions. Silent Shutter (earbuds) makes you quieter.
   * A **"?"** over her head means she's suspicious of you. **"!"** means she's about to catch
     you. At full suspicion: *CONFISCATED!* Your **test is ripped up** (answers and revealed answers
     gone), you lose half your side Clout (airplanes, notes, bonus question), your phone goes into
     the basket on her desk, and you sit in the detention corner until the bell.
5. **Escape detention once per class:** talk your way out (Clout, scales with level) or use a
   *Get Out of Detention* pass. You get a **fresh blank copy** of your test and return with
   suspicion at 45% and an 8 s phone cooldown. Stay in detention and your grade is F.
6. **Bell (or the timer runs out): pencils down, the test is graded.** Score %, a letter grade
   (A+ = 10/10, A ≥ 90%, B ≥ 80%, C ≥ 70%, D ≥ 60%, F) and Clout by grade (150 / 120 / 90 / 65 /
   40 / 15), plus **+50 for an A+** and **+60 GHOST bonus** for cheating (phone or watch) without
   her ever getting to "?". Pass and Pizza multipliers apply. The results show the class's top
   three with grades, and the **Phone Legend** is announced. No answers count after the bell.

### The phone: screenshot, scan, reveal (all timed by the server)

| Step | What happens | Risk |
|---|---|---|
| 1. Phone out | Hold F / L2 / PHONE. 0.25 s to raise it | visible while out |
| 2. SNAP | Space / E / R2 / the SNAP button. 0.6 s lining up the camera over your paper | visible |
| 3. Shutter | A click (noise) and a screen flash (2.5x glow, dimmed by Dim Screen) | she can SEE the flash and HEAR the click |
| 4. Scan | The scanner app processes for 6 s (2.5 s with the best Scanner). **Keep the phone out**: hiding it cancels the scan | the long risk window |
| 5. Reveal | The correct answers to 2 questions (Phone upgrade: 3 / 4 / 5) appear on YOUR phone only: "Q3: C" | — |
| 6. Answer | Put the phone away and click the answers on the test | safe |

* **Smart Watch** (late upgrade): press W / Y / WATCH with the phone **away**. A 3 s (2.2 s Pro)
  glance at your wrist reveals 1 answer. Very low visibility, but a 45 s (30 s) cooldown.
* **Answer Key Peek** (Robux): 1 answer instantly, max 1 per test. P / the PEEK flow, or used
  automatically when bought during a test.
* The client never has the answer key. The **question bank lives in ServerScriptService**
  (`src/server/Data/QuestionBank.lua`, 162 original questions), not in shared code, so an
  exploiter can't read it from ReplicatedStorage. Clients get question text and options only,
  and an answer only after the server-side snap + scan (or watch / peek).

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
  caught, escapes, screenshots the test, buys pizza, and so on. Real players are never quoted.
* **Party seating:** friends (`IsFriendsWith`) sit in neighbouring desks.

### Random class events (one per class, or none)

| Event | Effect |
|---|---|
| Substitute Teacher | Mr. Dozely subs. He is lenient (0.55x detection), turns slower and naps (sees nothing for 6 s) |
| The Principal walks in | Principal Granite stands in the doorway for 24 s: **double detection** plus a second pair of eyes |
| Fire Drill | 16 s of chaos. The alarm rings, the teacher spins around, detection drops: a great time to snap |
| Early Lunch Bell | She walks to the door and checks the hallway with her back to the class for 12 s. Clout x1.25 |

### Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Use phone (hold) | Hold **F** (or hold the PHONE button) | Hold **L2** | Hold the big PHONE button |
| SNAP the test (phone out) | Space / E / click SNAP | R2 / A | tap SNAP |
| Smart watch | W / click WATCH | Y | WATCH button |
| Answer Key Peek | P | – | – |
| Answer the test | click an option, or 1 / 2 / 3 / 4 | UI selection | tap |
| Previous / next question | Left / Right arrows, PREV / NEXT, the 1–10 grid | D-pad left / right | buttons |
| Airplane / note / report | buttons → seating chart | UI selection | buttons |
| Menus | buttons | Select focuses the menu | buttons |

The UI scales with a `UIScale` on every ScreenGui, so it fits phones. Jumping out of your chair
is disabled during class.

## Systems

| System | Where | Notes |
|---|---|---|
| Round flow | `RoundService` | Hallway → Bell → Class (a test) → Results (graded). 10 Hz authoritative tick. Late joiners wait in the hallway |
| Test | `TestService`, `shared/TestPaper`, `server/Data/QuestionBank` | 162 original questions (Math 40, Science 32, History 30, Geography 30, English 30; 3 tiers). 3/4/3 tier mix spread over subjects, versions A/B with shuffled question AND option order, friends share a version. Answers validated (own version's slots, 1–4, before the bell, 10/s). Grading A+..F, A+ and Ghost bonuses. Caught = ripped (F/0), escape = fresh copy |
| Lesson schedule | `shared/Lesson` | Seeded. It always opens with the board, has one bonus question near the middle, at least 2 walks, and at most one event |
| Teacher AI | `shared/TeacherBrain`, `TeacherService` | Pure state machine: board glances with a telegraphed pause, lecture sweep and focus drift, aisle walking with desk scans, distract, point/caught, nap, panic, door check |
| Detection | `shared/Detection` | Pure sight cone (soft edge, distance), visibility states, desk checks, noise and hearing, flash, suspicion rise/decay. It adapts the sight + noise split of DEAD AIR's MonsterBrain |
| Phones | `PhoneService` | Up/down states with raise and hide delays, glow linger; the server-timed snap (aim → shutter flash/noise → scan, cancelled if hidden) and smart watch; 6 actions/s budget; up-toggle spam limit (hides are never dropped) |
| Social | `ClassmateService` | Airplanes, notes, Teacher's Pet, group chat |
| Seating | `shared/Seating` | VIP desks first, friend groups placed contiguously, then the rest shuffled |
| Economy | `shared/Economy` | Pass multipliers add up and are capped at 2.2x. Upgrade stats, levels and ranks, daily streak, codes, bail cost |
| Data | `DataService` | Copies Sprout Valley's reviewed approach: DataStore + **session lock**, retries, versioned defaults and reconcile, autosave every 90 s, save on leave and on BindToClose, in-memory fallback, `_Studio` store in Studio. leaderstats: Clout, Rank |
| Shop | `ShopService` | Receipts are de-duplicated in the profile and **saved before PurchaseGranted**. In a live game, if the profile can't be saved: **NotProcessedYet**. Pass checks are cached. PolicyService covers paid random items |
| Cosmetics / upgrades | `CosmeticService`, `shared/CrateRoll` | Clout upgrades, phone skins, desk decor, wallpapers, crates with published odds, pity at 30, duplicate refunds, server-wide announcement for Legendary and Mythic pulls |
| Leaderboard | `LeaderboardService` | OrderedDataStore "Most Clout Ever" in the hallway. Every call is in pcall and it refreshes every 60 s. It falls back to this server's players |
| World | `ClassroomBuilder`, `shared/TeacherRig`, `shared/Props` | About 640 parts for the school. The teacher rigs use Motor6D joints and 42–52 parts each |
| Client | `HudController`, `PhoneController`, `TestController`, `TeacherController`, `MenuController`, `EffectsController` | HUD, the phone scanner UI, the test paper UI, procedural teacher animation, vision cones, "?"/"!" marks, menus, juice |

### Progression and retention

* **Clout** is the currency. **Upgrades** (all buyable with Clout):
  * phone model: answers per screenshot 2 → 3 → 4 → 5
  * scanner app: scan time 6 s → 2.5 s
  * silent shutter (earbuds): quieter click and beeps, down to 38% noise
  * dim screen (phone case): dimmer glow and flash, down to 58%
  * cover (hood → textbook stand → textbook fort): down to 64% visible
  * hide speed: 0.45 s → 0.20 s
  * backpack spot: the glow lingers 1.0 s → 0.2 s after you hide the phone
  * smart watch: 1 answer per glance with the phone away (45 s / 30 s cooldown)
* **Cosmetics:** 10 phone skins, 9 desk decorations, 8 wallpapers, from Common to Mythic.
  Classmates see your skin when your phone is out.
* **Levels and ranks:** XP from earned Clout, test scores, finished classes and bonus questions.
  Freshman (1) → Sophomore (5) → Junior (10) → Senior (16) → Legend (25). Each level-up gives
  +40 Clout, and new ranks are announced.
* **Daily streak:** 7 days (50 → 500 Clout). VIP gets +50%.
* **Codes:** `RELEASE` (250), `NOPHONES` (150), `SKIPCLASS` (100 + a Fake Hall Pass), `LIKE1K`
  (300, for the "like the game" poster in the hallway). Edit them in `ProgressionConfig.Codes`.
* **Session goals:** 3 at a time, for example "Screenshot your test and reveal answers",
  "Get a B or better", "Snap a screenshot while she walks the rows", "GHOST a test", "Get an A+".
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
| Answer Key Peek | R$ 29 | 1 answer revealed instantly, no phone needed. **Max 1 per test**; bought outside a test (or after peeking) it's saved |
| PIZZA PARTY! | R$ 99 | The **whole server** gets a lenient teacher (0.5x detection) and **2x Clout** for one class. Bought during class it starts right away, otherwise the next class (queue capped at 3). The buyer is announced to everyone |
| Phone Skin Crate | R$ 49 | A random phone skin, Rare or better. **The odds are shown** before buying. Hidden and refused when `PolicyService` says `ArePaidRandomItemsRestricted`, or when the policy lookup fails |

| Game Pass | Display price | What it does |
|---|---|---|
| 2x Clout | R$ 199 | +100% Clout |
| VIP | R$ 149 | VIP name and chat tag, +10% Clout, the gold VIP desk in the back row, +50% daily |
| Silent Mode | R$ 99 | Permanent earbuds at tier 3 of 4 |
| Extra Hide Speed | R$ 79 | Hide 0.05 s faster on top of your upgrades (minimum 0.15 s) |
| Pro Phone | R$ 249 | Exclusive Prism Pro: +1 answer per screenshot, **capped at 5** (what the best Clout phone already reveals) |

**Pay-to-win is bounded:**
* Every gameplay upgrade can be bought with Clout.
* Pass multipliers are capped at 2.2x.
* The Pro Phone never reveals more than the free Ultra Max 12 (5 per snap). The Peek is 1 per
  test. A free player who reads the teacher can still get an A+.
* Silent Mode is below the best Clout earbuds.
* The passes never touch suspicion rules.
* Escapes work once per class.
* The Pizza Party helps the whole server.

A skilled free player who reads the teacher wins classes.

### Setting up the shop (Creator Hub)

1. Publish the place. Then open create.roblox.com → your experience → **Monetization**.
2. **Developer Products:** create one product for each entry in `ShopConfig.Products` (8
   products: Clout500, Clout2000, Clout7500, DetentionPass, HallPass, AnswerPeek, PizzaParty,
   SkinCrate) and
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
* **Empty slots** (`Id = ""`, skipped until you add your own): SelfieShutter (the screenshot click), Notification,
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
* **Theme:** "cheating on a test" is the comedic premise (like a school cartoon). Getting caught
  always backfires (F, detention) and honest answers also score.
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

* `selene src`: 0 errors, 0 warnings. `lune run tests/compile`: compiled 47 files, 0 failures.
* `lune run tests/run`: 53 unit tests, covering:
  * detection maths, the teacher brain in every phase, lesson schedules over 200 seeds, the
    school clock
  * the question bank (162 questions, 5 subjects, 3 tiers, no duplicates), test picking (3/4/3,
    subject spread, 100 seeds), A/B versions (same questions, shuffled order and options, correct
    answers still map), the client view containing no answer key, friends sharing a version,
    answer validation, grading A+..F with A+ / Ghost / ripped rewards, reveal order
  * a check that the answer key text is not in shared or client code
  * the economy (answers per snap, Pro Phone capped at 5), crates and odds, seating, config
* `lune run tests/harness build/PhonesAway.rbxlx`: 39 checks on the **built .rbxlx** with the
  real services and stubbed engine services, covering:
  * test start: every student has a version, friends share one, every "view" payload has
    question text and options only, the bank isn't in ReplicatedStorage, a paper on each desk
  * **board phase: snap → aim → shutter → scan → exactly 2 correct answers revealed, to that
    player only → phone away → answered → graded**; hiding mid-scan cancels it
  * **walk phase: snapping gets caught (~4–5 s) → phone confiscated → test ripped (F, 0) →
    detention**; escaping gives a fresh copy
  * remote validation (bad slots / options / NaN / types, answer and action rate limits, no
    reveal without a server-side scan, no answers after the bell), smart watch, Answer Key Peek
    receipt twice → granted once and max 1 per test, the screenshot flash
  * an A+ paid with its bonus, the Pizza Party paying 2x for a non-buyer's grade, bonus
    question, airplane, notes, Teacher's Pet, detention pass / hall pass receipts, the
    principal, leaving mid-class, seating fixes
  * upgrades and cosmetics, crates with PolicyService, daily / codes, the leaderboard fallback
  * live-game NotProcessedYet, the DataStore session lock, `_Studio` vs. live store names
  * five complete classes on the real schedule (one per event) with a cheating student
  * every client controller, including the test paper UI and the phone scanner states
* `build/classroom-preview.png` re-rendered with `tools/` (test papers on the desks).

**Not verified** (no Studio playtest was possible):

* Real physics and seating (`Seat:Sit`, jump disabling).
* How the procedural animation looks.
* Camera feel.
* Network smoothing of the teacher.
* Mobile layouts on real devices.
* Real DataStore, MarketplaceService and PolicyService behaviour.
* Audio.
* Whether the test is hard enough (or too hard) for real players: the tier mix and timer need
  watching.

Balance values come from a small offline simulation (smart vs. greedy players per phase) and
need tuning with real players.
