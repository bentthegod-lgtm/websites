# PHONES AWAY!: polish to-do (for the PC Claude with Blender and ComfyUI)

The game works fully with its procedural part models. This list covers the meshes to replace,
the art to generate, the sounds to add and the balance to tune. A rough three.js render of the
current room (with the test papers) is `build/classroom-preview.png`; re-render it with
`tools/export_classroom.luau` + `tools/render_preview.mjs` (commands at the top of each file).
Open `build/PhonesAway.rbxlx` in Studio to see the real look.

**Core loop reminder:** every class is a test. Students screenshot the test with their phone,
the scanner app processes while the phone stays out, and it reveals answers. The test paper,
the phone and the smart watch are the hero props.

**Style for everything:** bright, friendly "cartoon school". Chunky, rounded, slightly
oversized props (think toy classroom), with saturated but warm colours: teal, coral, sunny
yellow, sky blue and cream walls. No realistic textures. Use vertex colours or one small palette
texture. Nothing creepy: the teacher must read as kind but strict, never scary. 1 stud = 1
Blender unit (scale by 0.28 m if you work in meters). Origin at the bottom centre unless noted.
Export as FBX, import as MeshParts, and set `CanCollide = false` on decorative meshes.

## 1. Classroom (built by `src/server/Services/ClassroomBuilder.lua`)

The room is 60 (X) × 50 (Z) × 16 studs, centred on the origin. The whiteboard is on the −Z
wall, the windows on the −X wall, and the door to the hallway at +X, z = 18. Keep the names
the code looks up, and keep collision on floors, walls and desk tops.

| Model | Size (studs) | Notes |
|---|---|---|
| Whiteboard (`Whiteboard`) | 30 × 9.4 × 0.4 | Aluminium frame, marker tray with 4 markers and an eraser. **Keep a flat part named `Surface`** with its `SurfaceGui.Text`: the lesson is written there live |
| Wall clock (`WallClock`) | 3.4 diameter × 0.4 | Round school clock. Keep the separate `HourHand`, `MinuteHand` and `Center` parts: the client rotates them |
| Teacher's desk (`TeacherDesk`) | 8 × 3.4 × 4 | Wooden desk with drawers, monitor, mug, apple, paper stack. Keep a part named `Basket` (2 × 0.7 × 1.4) on top: confiscated phones are placed in it |
| Bookshelf + globe | 6 × 8 × 2 | Colourful books, globe on top |
| Window bay ×4 | 8 × 8 each | Frame + mullions + sill. Glass stays a transparent part |
| Door | 0.4 × 9.5 × 6 | Wooden door with a small window and a lever handle. The code swings it open and shut (CFrame), so the pivot is at the hinge edge |
| Ceiling light panel ×6 | 8 × 0.2 × 3 | Keep the SurfaceLights |
| Posters | 5 × 6 | ComfyUI textures (see section 5): "Hang in there (class ends eventually)", "Math is everywhere", "Class rules: 1. Be kind 2. No phones 3. NO PHONES", a periodic table, and "RULE #1: PHONES AWAY!" above the board |
| Cubbies + 6 backpacks | 2.3 × 2.3 × 1.6 each | Backpacks in different colours |
| Detention corner (`DetentionCorner`) | rug 7 × 6 | Small grey desk facing the back wall, a stool, a red "DETENTION - think about what you did" sign and a digital timer (`Timer` part with a SurfaceGui: keep it). Keep the two `Seat`s `DetentionSeat` and `DetentionSeat2`. Make it funny: a sad little plant, an hourglass |
| Floor | 60 × 50 | Checker linoleum tiles (two tones). Can become one mesh with a tiled texture |

## 2. Student desks (12, `Desks/DeskN`)

| Model | Size | Notes |
|---|---|---|
| Student desk | top 4 × 0.25 × 2.6 at y = 2.7 | Classic school desk: wood-look top, metal legs, wire book shelf under the top. Keep the part `Top` (collision) and `NameCard` (with its SurfaceGui) |
| Chair | seat 2.2 × 0.3 × 2 at y = 1.7 | Blue plastic school chair with metal legs. **Must stay a `Seat`** named `Seat` (the server sits students in it) |
| VIP desk (back row, columns 1 and 4) | same | Darker wood, gold trim, magenta cushion and a gold "VIP" plate. Make it look comfy and a bit ridiculous |
| Textbook + pencil | 1.3 × 0.22 × 1.7 | Small props on every desk |

Phone and decor spots on each desk come from `ClassroomBuilder` (`phoneUp`, `phoneDown`,
`decor`). If the desk shape changes, keep those CFrames sensible.

## 3. Teacher, substitute and principal (`src/shared/TeacherRig.lua`)

These are procedural rigs with Motor6D joints. The client animates `Motor6D.Transform` from the
`Pose` attribute. To swap in meshes:

* Keep the joint names `RootJoint`, `Neck`, `LeftShoulder`, `RightShoulder`, `LeftHip` and
  `RightHip`.
* Keep the part names `Root` (anchored, invisible, 2 × 2 × 1, moved by the server), `Torso`,
  `Head`, `LeftArm`, `RightArm`, `LeftLeg` and `RightLeg`.
* Keep the `LegH` model attribute (2.6 studs of leg).
* Shoulder pivots sit at the top of the arms, hip pivots at the top of the legs.
* Total height is about 7.3 studs (the principal is 1.12x).

| Character | Look |
|---|---|
| **Ms. Bellweather** (teacher) | Kind but strict, about 40, warm skin tone. Teal cardigan over a cream blouse, navy skirt, brown hair in a bun with a yellow pencil stuck in it. Round glasses, coral lanyard with a staff badge, coral earrings, rosy cheeks, a small smile. She holds a blue whiteboard marker in her right hand. Extra blend shapes or textures would help: "suspicious squint" and "caught you!" faces |
| **Mr. Dozely** (substitute) | Sleepy, older, grey hair and beard, tweed-ish vest over a beige shirt, blue tie, droopy eyelids. He visibly naps (`Nap` pose) |
| **Principal Granite** | Tall (1.12x), dark navy suit, red tie, glasses, stern eyebrows, arms crossed (`Arms` pose). Imposing but cartoony, not scary |

Poses already animated procedurally: Write, Pause (the "about to glance" tell), Glance, Lecture,
Walk, Quiz, Point (caught you), Distracted, Panic (fire drill), Door, Nap and Arms. If you make
real Animation assets, keep the pose names and switch `TeacherController.animate` to play
them.

## 4. Phones and desk decorations (`src/shared/Props.lua`)

The phone screen faces the model's −Z. Keep the parts `Body` (PrimaryPart), `Screen` (Neon,
with the PointLight `Glow`) and the PointLight `Flash` on Body.

| Model | Size (W×H×D studs) | Look |
|---|---|---|
| Hand-me-down Brick (2 answers / snap) | 0.62 × 1.15 × 0.22 | Chunky old grey phone, antenna nub, one tiny camera |
| Flip Classic (3) | 0.6 × 1.1 × 0.16 | Blue flip phone, visible hinge |
| Slab S (4) | 0.6 × 1.2 × 0.1 | Black modern slab, dual camera |
| Ultra Max 12 (5) | 0.72 × 1.45 × 0.08 | Gold-trimmed flagship, big triple camera bump |
| Prism Pro (pass, +1 capped at 5) | 0.7 × 1.4 × 0.07 | Iridescent teal-to-pink glassy back, glowing edges |

The camera bump matters now (the phone takes screenshots): make it readable from across the
room. A **screen glow** variant for "scanning" (a pulsing green scan line) would sell the risk.

Skins recolour the body: Bubblegum, Mint, Camo (wood), Denim (fabric), Marble, Lava (neon
stripe), Gold (foil), Galaxy, Hologram. A small skin texture atlas would look great.

Desk decor, each about 0.6 × 1 stud and placed on the desk top:
* Pencil Cup
* Tiny Cactus
* Rubber Duck
* Apple for Teacher
* Lava Lamp
* Participation Trophy
* Spinny Globe
* Class Crown

Paper airplane: about 0.5 × 0.15 × 1.1, folded white paper.

### Test paper (`Props.testPaper`, `Props.rippedPaper`) - hero prop

| Model | Size | Notes |
|---|---|---|
| Test paper | 1.7 × 0.03 × 2.2 on the desk top | Slightly curled printer paper: title line, 8 question lines with answer bubbles, a name line, a round **VERSION** badge (A = blue, B = pink; keep the `Version` part and its SurfaceGui letter), a yellow pencil. Keep `Sheet` as PrimaryPart |
| Ripped test | scraps in a 1.2 radius | 6 torn scraps with jagged edges, a few question lines visible, maybe a big red "F" on one |
| (optional) Red-pen grade | 0.5 | A circled letter grade that could stamp onto the paper at the bell |

### Smart watch (late upgrade) - new prop

Shown on the student's wrist when owned (not built yet: add it to the character in
`RoundService.refreshDesk`). About 0.35 × 0.1 × 0.4: a chunky square watch with a bright
screen and a coloured band; "Smart Watch Pro" is sleeker with a glowing edge. A dim screen
glow while glancing would match the gameplay (the server already treats it as a small glow).

## 5. Hallway (lobby)

The hallway is 20 × 74 studs. Lockers alternate blue and red (1.8 × 8 × 2.2 each, vents and
handle). There is also the School Store kiosk (counter, striped awning, snacks, sign), a
"WELCOME" mat spawn, the "ROOM 104" sign, the "PHONES AWAY!" banner, a "LIKE THE GAME! code
LIKE1K" poster, and the `Leaderboard` board (keep the SurfaceGui rows).

Ideas to add:
* trophy case
* water fountain
* bulletin board with flyers
* vending machine

## 6. ComfyUI prompts

**Shared negative prompt:** `text, watermark, logo, signature, realistic photo, horror, scary,
creepy, blood, gore, violence, weapon, dark, gloomy, deformed hands, extra fingers, lowres,
blurry, jpeg artifacts`

Brand names, real logos and real phones must not appear. Add any text in Studio or Photoshop,
not in the generation.

### Game icon (512×512)

> cartoon game icon, a cheeky teenage student peeking at a glowing smartphone hidden behind a
> standing textbook, a friendly teacher with a bun and round glasses in the background turning
> around with a big yellow question mark above her head, bright classroom, vibrant saturated
> colors, bold clean outlines, 3D render in Roblox style, centered composition, high contrast,
> playful, funny, square icon

### Thumbnails (1920×1080)

1. **"Don't get caught"**
   > wide cartoon classroom scene in Roblox 3D style, rows of blocky students at desks secretly
   > photographing their test papers with glowing phones under their desks, a friendly teacher
   > with a teal cardigan writing on a whiteboard with her back turned, one phone flashing as it
   > snaps a test paper, a progress bar glowing on its screen, comedic
   > tension, warm sunny light from big windows, vibrant colors, dynamic angle, high detail
2. **"CONFISCATED!"**
   > cartoon Roblox style, a teacher pointing dramatically at a shocked blocky student, a red
   > exclamation mark above her head, a test paper torn into confetti, a phone flying into a basket, classmates gasping
   > and laughing, bright classroom, exaggerated expressions, comic energy, vibrant colors,
   > motion lines
3. **"PIZZA PARTY"**
   > cartoon Roblox style classroom celebration, pizza boxes and slices raining down, confetti,
   > blocky students cheering and holding up glowing phones, a relaxed smiling teacher with
   > pizza, gold coins and sparkles, super vibrant colors, joyful chaotic energy, wide shot

### Shop / UI icons (256×256, transparent background, same style)

* Clout packs (3 sizes): a stack of glowing gold "like" hearts and stars, growing bigger
* Get Out of Detention: a golden ticket with a running shoe
* Fake Hall Pass: a wooden hall pass paddle with a wink sticker
* Pizza Party: a pizza box bursting with confetti
* Phone Skin Crate: a school locker crate glowing pink with phone silhouettes
* 2x Clout: a big golden "2x" with sparkles
* VIP: a gold desk with a crown cushion
* Silent Mode: earbuds with a "shh" mute symbol
* Extra Hide Speed: a phone with speed lines and a lightning bolt
* Pro Phone: an iridescent teal-pink phone with glowing edges
* Answer Key Peek: a golden key over a test paper with one glowing checkmark
* Scanner app icon ("ScanBuddy"): a friendly scanning-eye mascot inside a phone
* Smart watch: a chunky smart watch with a glowing answer letter on its screen
* Letter grade stamps: A+, A, B, C, D, F in red marker, and a "GHOST" stamp (cute ghost)
* Rank badges: Freshman, Sophomore, Junior, Senior and Legend, as school-crest shields in green,
  blue, purple, orange and pink

Poster textures (5×6 stud posters, 1024×1228): a motivational cat hanging from a branch ("hang
in there"), a math doodle poster, a class-rules poster and a periodic table. Write the text
separately.

## 7. Sounds (empty slots in `AudioAssets.lua`)

Fill these with audio you own or Creator Store audio that is marked usable:

* **SelfieShutter:** the screenshot shutter click (short camera click)
* (new idea) a soft scanner "processing" beep loop for the scan window
* **Notification:** soft message ping for the group chat
* **MarkerSqueak:** whiteboard marker loop. It stops when she pauses, which is the audio tell
* **Suspicious:** a quizzical "hm?" sting for "?"
* **Alert:** a sharp sting for "!"
* **QuizSting:** a pop quiz jingle
* **PizzaFanfare:** a party horn
* **LevelUp**
* **Click:** UI click
* **ClassMusic:** light, sneaky comedy loop
* **HallwayMusic:** upbeat lobby loop

You can also replace the reused DEAD AIR IDs (bell, fire alarm, taps) with sounds that fit
school better.

## 8. Balance to tune (watch real classes)

| Value | Where | Now | Watch for |
|---|---|---|---|
| Sight rate / near bonus | `TeacherConfig.Sight.Rate`, `NearBonus` | 0.24/s, +60% | Lecture should catch greedy players in about 3–5 s. Smart players should survive |
| Cone half-angle | `TeacherConfig.Sight.FovDegrees` | 36° | Too wide = lecture is the same as walk. Too narrow = no tension |
| Decay | `Suspicion.DecayPerSecond`, `DecayDelay` | 0.1/s after 1 s | "?" should feel recoverable |
| Desk check | `Sight.DeskCheckRange/Rate` | 8 studs, 1.3/s | Walks should be the scariest phase |
| Board glance | `TeacherConfig.Board` | every 7–12 s, 55%, 0.9 s warning | The pause tell must be readable |
| Hearing | `Hearing.Rate`, `MinNoise` | 0.3, 0.08 | Earbuds should matter for front-row students |
| Snap timing | `PhoneConfig.Snap`, `UpgradeConfig.Scanner` | 0.6 s aim + 6 s scan (2.5 s best) | The scan should feel like a risky hold, not a free win |
| Flash / shutter | `PhoneConfig.Snap` | 2.5x glow, +0.22 if seen, 0.9 noise | A snap in her cone should be a real "!" moment |
| Answers per snap | `UpgradeConfig.Phone` | 2 / 3 / 4 / 5 | 2 snaps + honest knowledge ≈ B; A+ needs skill or upgrades |
| Test difficulty | `GameConfig.Test.Mix`, `QuestionBank` | 3 easy / 4 medium / 3 hard | Honest players should still reach C–B |
| Grade rewards | `GameConfig.Test.Grades` | A+ 150 … F 15, A+ +50, Ghost +60 | A good class ≈ 150–300 Clout |
| Upgrade prices | `UpgradeConfig` | 120 → 9,000 | First upgrade after 1–2 classes |
| Bail cost | `GameConfig.DetentionBail*` | 60 + 6/level | Should sting but be possible |
| Pet | `GameConfig.Pet` | +22% suspicion per report, 3 per class | Must not dominate a class |

The offline simulation used for the current numbers runs 20 s per phase over 10 seeds:

| Phase | Smart player (hides when she looks or comes close) | Greedy player |
|---|---|---|
| Board | caught 0/12, phone out about 17.6 s | maxes at "?" |
| Lecture | caught 0/12, phone out about 6 s | always caught |
| Walk | caught 3.7/12, phone out about 11.5 s | caught 11/12 |
