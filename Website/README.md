# Notch website

A static site: one page of markup, one shared stylesheet and script, and one stylesheet and script per part of the
page. No build step, no dependencies, no network requests: every picture on it is drawn in HTML, CSS and inline SVG
from the app's own constants. Preview: `python3 -m http.server 4173 --bind 127.0.0.1 --directory .` in this folder, then
http://localhost:4173 (opening `index.html` straight from disk also works in most browsers).

## The files

- **`index.html`** holds all the markup; nothing generates it. In order: the skip link, the page's sprite (`g-*`
  symbols: the app's own pictures, drawn after `Sources/Style/Glyphs.swift`, a few for the site, and the Mac's pointer,
  crosshair, Control Centre and modifier signs), the nav, the hero, the rack (`#segments`), one `section.seg` per
  segment (`#numbers`, `#capture`, `#dictation`, `#windows`, `#keys`, `#mirror`, `#transcribe`), the open slot
  (`#next`), open source (`#source`), the download card (`#download`) and the footer. Each part sits between
  `<!-- @seg name -->` and `<!-- /@seg name -->` comments. A part that needs SVG definitions of its own keeps them in a
  sprite inside its block, with ids prefixed by the part (`cp-` capture, `mr-` mirror, `mo-` more), so no id repeats.
- **`styles.css`** is the shared base: the tokens (`:root`), the base (focus ring, `.skip`, `.vh`, `.wrap`), type
  (`.micro`, `.pair__name`, `.pair__line`), the small parts (`.glyph` and the glyph tile, `.lamp`, `.chip`, `.btn`), the
  app's own vocabulary (`.bar10`, `.gauge`, `.bar` and `.cell`, `.hairline`, `.cam`), the segment head, the surfaces
  (`.bays`, `.bay`, `.bay__stage`, `.bay__foot`), the voice strip `.vn`, the shared breakpoints, motion off, forced
  colours, the camera in the notch `.ncam`, and the Mac drawn once (`.mbar`, `.tl`, `.mptr`, `.mcross`, `.keys` and
  `.kc`, `.steps`, `.hint`).
- **`app.js`** defines `window.Kit`, then runs what the whole page shares: the Motion and Sound switches, the menu bars'
  clock, reveal on scroll and the fitting of a bay's object to its stage. See "Kit" below.
- **`segments/`**, one stylesheet and one script per part: `hero` (the nav and the hero), `home` (the rack, the
  download card, the footer), `numbers`, `capture`, `dictation`, `windows`, `keys`, `mirror`, `transcribe`, and `more`
  (`#next` and `#source`). Every rule of a segment starts with its section's id (`#capture …`), and those of `hero`
  and `home` with their parts' own classes (`.nav`, `.hero`, `.rack`, `.get`, `.foot`), so no rule can reach another
  part. Each script reads `window.Kit` and touches only its own part.
- **`assets/`**: the app icon at the sizes the page uses (`icon-64.png` in the nav and the footer, `icon-336.png` on
  the download card, `icon-192.png` as the page's icon) and `og.png`, the 1200 × 630 picture a shared link shows.
- **Shared drawings.** The hero's mirror shows the Mirror segment's own picture through `<use>` (`#mr-room-art`,
  `#mr-me-art`, framed 464 × 261): keep those ids if that drawing changes. Capture's "You" tile uses the same person.

Names: a segment's classes and ids carry its two-letter prefix and a hyphen (`dc-`, `mr-`), a state is `is-…`
(`is-on`, `is-hot`). The shared classes above have no prefix.

## Kit (`window.Kit`, from `app.js`)

- **`$`, `$$`, `clamp`, `ease`, `wob`, `rand`, `fmt(seconds)`**: small helpers.
- **`player(scene, once)`** makes a loop that can be stopped from outside: `scene` is `async (wait, alive) => {}` and
  waits only through `wait(ms)` or `wait.frame()` (the next frame the display draws), so a stopped scene never runs on.
- **`whenVisible(root, scene, still)`** registers a scene. **`turns`** plays one scene at a time: the one nearest the
  middle of the screen (at least 30% of it showing), which stays the nearest until another is a tenth of a screen
  nearer. After each full loop the turn passes on, in reading order, among the scenes side by side with it and the
  scenes of its section that show at least 60% of themselves. A scene without the turn is stopped and shows its
  `still()` frame. `turns.hold(scene)` and `turns.release(scene)`: a person is driving it, so it takes the turn, keeps
  it while it shows, and its loop waits. `turns.playing` lists the scenes running now, for checking. A scene whose own
  code throws is reported in the console and the turn goes on to the others.
- **`handsOn(root, scene, onTake)`** lets a person take a scene over by doing something on `root` (pass the control or
  the panel, not the whole bay): a real move of the pointer, a press or a tap, a key, or keyboard focus arriving.
  `onTake()` then draws what they take over. The scene plays on 2.6 s after the last of those, never while keyboard
  focus is inside. A pointer at rest takes nothing, and neither does a page scrolling under it.
- **`moved(event)`** is false for an enter, leave or move event that scrolling produced under a pointer at rest.
- **`reduced()`** is the one gate for motion: true with Reduce Motion set on the device, and while the visitor has
  switched Motion off on the page. The switch is any element with the attribute `data-motion` (the nav has one, beside
  Sound); `app.js` wires it, keeps its `aria-pressed` and its lamp, and remembers the choice for the visit. `<html>`
  then has `.is-still`, under which the base stylesheet stops every transition and animation (a rule a segment writes
  under `@media (prefers-reduced-motion: reduce)` needs an `.is-still` twin). **`onMotion(fn)`** calls `fn(reduced())`
  when the answer changes; **`motion`** is `{ on, set(on), toggle() }`.
- **`tween(wait, ms, fn)`** calls `fn(0…1)` once per display frame; **`press(cell, wait, ms)`** lights a panel key
  (`.is-hot`) for a moment.
- **`makeVoice(root)`** drives a voice strip `.vn`: `idle()`, `still(n)`, `run(wait, { limit, from, onCopied })`. The
  strip's clock counts 0.4 s for each word shown, because the demo types faster than anyone speaks. `SPEECH` is its text.
- **`clock()`, `tickClocks()`, `fitBar(bar, hole)`**: the menu bar's date and time as an English Mac writes them where
  the visitor is; every `.mbar__clock` filled with it (one marked `data-own` is left to its scene); whole menus, and
  whole things at the right end of a bar, left out where they would run under the notch or an open panel.
- **`touch()`** is true on a touch screen: `(hover: none)`, or from the first real touch on. `<html>` is then
  `.is-touch`, which the `.when-point` / `.when-tap` pairs of words follow.
- **`Sound`** plays the app's own seven tones (`Sources/Style/Sounds.swift`); the switch is `#sound`, off until asked.
  With it on, a real control ticks under the visitor's pointer and sounds when pressed, and a demo plays the tone the
  app would at that moment (`Sound.play('listen')`), whoever drives the demo. Nothing else makes a sound.

## The Mac, drawn once

The page draws real hardware and real macOS, so each piece is drawn once, in `styles.css`, at its real size: 1 px is
1 pt, measured on a 14-inch MacBook Pro with macOS 27 and against the system's own glyphs. A scene drawn smaller
scales the whole part (`zoom` or a transform), never one measure of it. `lab/kit.html` shows them all on one sheet
while the `lab/` folder exists.

- **The notch** is 180 × 32, `#000`, flush with the top of the screen, bottom corners radius 10. Closed, it has no rim
  and no shadow. The rim and the shadow are the site's device for the app's opened shapes (the panel, the strip, a card).
- **The camera** `<i class="ncam"></i>`, in the notch's 32-px band: a 9-px lens of neutral dark glass and, 13 px to its
  right, the light. The light is green only while a camera runs (`.is-on`, or `data-cam="on"` on an ancestor): the only
  colour a notch ever has. `--d` scales it for a smaller notch.
- **The menu bar** `.mbar` is 33 px tall, 13-px type in one ink: the Apple menu (`.mbar__apple`, drawn from the
  visitor's own system font, on Apple devices only), the app's name in `<b>`, its real menus in order; then the
  battery (`.mbar__batt`, `--b` its charge, `data-chg` on mains power), Control Centre (`#g-cc`), the privacy dot
  (`.mbar__dot`, `data-on="mic"` or `"cam"`) and the clock.
- **A window's buttons** `.tl` are 14 px, 23 px apart, 9 px from the left and top; in colour only on the window in
  front (`.is-front`). `--s` and `--p` scale them.
- **The pointer** `.mptr` (`#g-pointer`) is macOS's arrow, black with rounded corners and a white edge, 10 × 17 with
  its edge, its tip at `left`, `top`; it never changes size. **The crosshair** `.mcross` (`#g-cross`) is 15 × 15.
- **A shortcut** is `.keys` with one `.kc` per key, the modifier signs drawn (`#g-ctrl`, `#g-opt`, `#g-shift`,
  `#g-cmd`; Caps Lock is `#g-key`). **Steps along a bay's foot** are `.steps` > `.step`; **a prompt to try a demo** is
  `.hint`, centred under the object.
- **The app's panel** (`Sources/Panel/Console.swift`) is 500 wide with the site's 1-px rim: gauges 80 wide and 16 apart,
  label mono 11 in `--gray`, number mono 20, ten 6 × 8 segments 2 apart; function bar 34 high with equal cells. A panel
  drawn smaller sets `--pz` (its scale) on the scaled element: the small type in it is then set larger, to stay about
  10 px on screen, and on a touch screen a bar whose cells are controls is at least 40 px tall on screen.

Colour: white and greys; amber and red only as the app's signals; `--sys-*` only for the swipe picture and the camera's
green; `--tl-*` only for a front window's buttons; `--mic` only for the menu bar's dot. `--gray` for any words a visitor
needs, `--dim` only for decoration. Type: titles 44 px at most, body 14 to 15, labels 11 mono; a name over a line inside
a bay is `.pair__name` over `.pair__line` (15/600 over 14/400), along a bay's foot `.bay__name` with `.bay__line`.

## Adding a segment to the page

1. **Markup**, in `index.html` after the last segment and before `#next`, between `<!-- @seg name -->` markers:
   ```html
   <section class="seg" id="name" aria-labelledby="name-t">
     <div class="wrap">
       <header class="seg__head rv">
         <p class="seg__kicker"><span class="seg__no">08</span><svg class="glyph" aria-hidden="true"><use href="#g-…"/></svg><span class="seg__name">Name</span></p>
         <h2 class="seg__title" id="name-t">The point, in white. <span>The rest in grey.</span></h2>
         <p class="seg__lede">One short line.</p>                                                        <!-- optional -->
         <dl class="seg__facts"><div><dt>Smaller after Compress</dt><dd>78<span>%</span></dd></div></dl>  <!-- optional, at most 2 -->
         <p class="seg__chips"><span class="chip">Needs a trackpad</span></p>                             <!-- optional -->
       </header>
       <div class="seg__body">
         <article class="bay rv" style="--h:440px;--hs:380px" aria-labelledby="name-b1">  <!-- --hs: the height on a phone -->
           <div class="bay__stage" aria-hidden="true">… the demo …</div>
           <footer class="bay__foot"><h3 class="bay__name" id="name-b1"><svg class="glyph" aria-hidden="true"><use href="#g-…"/></svg>Name</h3><span class="bay__line">What it does, in a line.</span></footer>
         </article>
       </div>
     </div>
   </section>
   ```
   Several bays go in `<div class="bays bays--22">` (or `bays--3`). Content always sits on a bay. A fact's label is
   written as the claim; a sign that belongs to its number goes in a `<span>` (`78<span>%</span>`), a unit in words in
   a `<small>` (`0.19<small>s</small>`).
2. **The rack:** a `.mod` in `#segments` linking to `#name`, numbered like the head. If the tool has a cell in the
   hero's panel, link that cell to `#name` too.
3. **Styles and script:** `segments/name.css`, every rule under `#name`; `segments/name.js`. Link the stylesheet in the
   head after the others, and the script with `defer` after `app.js`.
4. **The Mac and the app:** wherever the demo shows a piece of the Mac or of the app's panel, use the shared parts above
   at their sizes. Check anything new against the Swift source before drawing it.
5. **The demo:** `Kit.whenVisible(root, Kit.player(async wait => { … await wait(ms) … }), still)`. `still()` must draw a
   complete, true frame by itself (the result of the story, not its middle): it is what shows with motion off, and
   while another scene plays. The loop must undo at its start anything the still frame changed. One thing moves at a
   time. If a person can drive the demo, use `Kit.handsOn(control, player, onTake)`. Anything clickable is a real
   `button` or link with a name and a visible focus; a drawn demo is `aria-hidden`.
6. **Check:** `node --check segments/name.js`; then, at 360 px and 1440 px, with motion on and off: no errors in the
   console, no sideways scroll, never more than one entry in `Kit.turns.playing` while scrolling, nothing moving with
   Motion off, a visible focus on each control. Add any number the segment shows to the list below, with its source.

## Where every number on the page comes from

Recount when the code changes. The app's repository is `Desktop/Projects/Notch`; the reports are in
`Desktop/Notch/Reports`. Counted on 17 Nov 2026, in the working tree: the TRANSCRIBE tool (`Sources/Transcribe`) is
new and not yet committed, so everything said about it may still change.

- **71 Swift files, 0 libraries, 0 network calls** (`#source`): `find Sources -name '*.swift' | wc -l` (62 of them
  committed, `git ls-files 'Sources/*.swift'`; the other 9 are `Sources/Transcribe`), in the folders App, Capture,
  Dictation, Keys, Panel, Recording, Settings, Shared, Style, Transcribe and Windows (the tree in `#source` shows them).
  Every `import` is one of Apple's frameworks; `Package.swift` exists only for the tests (22 files, 109 tests; 20 and 88
  committed). `scripts/rules.sh` checks the source, and the built app, for network code. Version 0.9.0 (`VERSION`);
  built, `Notch.app` is 3.6 MB with Transcribe (3.0 MB at the last commit, `488a44f`).
- **Apple silicon, macOS 26 or later** (hero, `#download`): `Resources/Info.plist`, `LSMinimumSystemVersion` 26.0;
  `build.sh` builds for `arm64-apple-macos` at that version. Used every day on one Mac only: a 14-inch MacBook Pro,
  M1 Pro, macOS 27.
- **Numbers.** `Sources/Panel/Stats.swift`: read every 0.25 s while the panel is open, every 2 s while closed.
  `Sources/Panel/Console.swift`: CPU amber at 70%, red at 90%; TEMP amber at 80 °C, red at 95; BAT amber at 20%, red at
  10%, only while unplugged; MEM follows macOS memory pressure, never a percentage; the line under the notch watches
  MEM, CPU, TEMP and BAT. FREE lists the four apps using the most memory; from the open panel, quitting one is two
  presses (FREE, then the app).
- **Capture.** `Sources/Capture/Card.swift`: the card stays 6 s; COPY, SHOW, COMPRESS. `Sources/Capture/Tools.swift`:
  file names ("Shot <date>.png", "Rec <date>.mp4"). **78% smaller**: measured once, on a 31-minute 3K recording of a
  call, and written down where the setting was chosen (`Sources/Capture/Compress.swift`); the demo's sizes keep that
  ratio and are made up. **0 uploads**: no network code.
- **Dictation.** `Reports/Dictation research - results.tsv`, M1 Pro, 13 Nov 2026, on short clips outside the app:
  the final text is ready **0.19 s** (median) after the last sound; the first words come about 1 s after starting;
  1.4% of words wrong on clean read speech, 4.3% across all 97 clips. INCOGNITO (`Sources/Shared/Clipboard.swift`): the
  text is marked so clipboard managers that honour the mark skip it, and it is gone from the clipboard within 90 s.
- **Windows.** `Sources/Windows/Place.swift`: ten places. **51 ms** from lift to landed: the swipe rig's median for a
  plain move, 14 Nov 2026 (`Reports/Window snapping - final report.md`; its grain is 5 ms).
- **Shortcuts and what starts on.** `Sources/Shared/Prefs.swift`: ⌃⌥S, ⌃⌥T, ⌃⌥R, and ⌃⌥⇧⌘D for DICTATE, which
  Settings prints as ⇪D; CAPS LOCK IS HYPER KEY and SWIPE TITLE BARS start off and need Accessibility; INCOGNITO starts
  off; everything else starts on.
- **Transcribe.** The app's `README.md` (TRANSCRIBE) and `Sources/Transcribe`: TRANSCRIBE sits between DICTATE and
  MIRROR (`Sources/Panel/Readouts.swift`; its picture is SCRIBE in `Glyphs.swift`, `#g-scribe` here). The work is done
  on the Mac by Scribe, a separate free app (https://github.com/WHATDOESTHEFOXSAY2U/scribe); without it TRANSCRIBE
  hides; links also need yt-dlp. The first time ever, Scribe fetches its speech models, about 1 GB
  (`Sources/Transcribe/Scribe.swift`, GETTING MODEL). Notch itself has no network code: it starts Scribe and reads what
  it prints.
- **The panel, the strip, the card, the swipe picture**: their sizes are the app's own, in `Sources/Panel/Console.swift`,
  `Sources/Dictation/Wings.swift`, `Sources/Capture/Card.swift` and `Sources/Windows/Pointer.swift`; colours and the
  grey in `Sources/Style/Style.swift`.
- **Made up** (the footer says so): the readings, file sizes, app names and times in the demos, the people on the
  call and every transcript.

## Before publishing

- **The two addresses.** Every link marked `data-download` points at `#download` and every link marked `data-repo` at
  `#source` until there is a release and a public repository. Then give the download card's button the release's
  address (the repository's latest release) and every `data-repo` link the repository's (the one with
  `data-repo-path="CONTRIBUTING.md"` that file's). The nav's and the hero's Download keep leading to the card on
  purpose: the card carries the first-open line, and macOS blocks the app the first time it opens. This lists what
  still points inside the page; afterwards it must print only those two:
  `grep -n 'data-download\|data-repo' index.html | grep 'href="#'`
- **The license.** The repository has none yet; the owner decides. The page says "Open source" and names no license.
  Once a `LICENSE` file exists, name it in `#source` or the footer.
- **The name.** It is not final in the app's repository. It appears in the title, both descriptions, `og:site_name`,
  the picture's alt text and the page's words.
- **The page's own address.** Add `<meta property="og:url" content="https://…/">` and
  `<link rel="canonical" href="https://…/">` to the head, and make `og:image` absolute (`https://…/assets/og.png`).
- **The link's picture.** Render `assets/og.png` again from the finished page, served as in the first paragraph:
  ```sh
  node lab/shot.mjs http://localhost:4173/ --w 1440 --h 756 --dpr 0.8333334 --reduced --wait 1500 --out assets/og --eval "const s = document.createElement('style'); s.textContent = '.nav,.skip,.pill,.hero__cta,.hero__fine,.hero__hint{display:none!important}.hero{padding-top:64px!important}'; document.head.append(s); dispatchEvent(new Event('resize')); document.querySelectorAll('.mbar__clock').forEach(e => { e.textContent = Kit.clock(new Date(2026, 10, 17, 9, 41)); }); await new Promise(r => setTimeout(r, 600));"
  ```
  It is the hero at 1440 wide with Reduce Motion (its still frame: the panel open), without the nav and the buttons,
  the clock at 9:41, scaled to 1200 × 630. Check it by eye, and keep `og:image:alt` true to it.
- **The two speeds.** 0.19 s and 51 ms were measured on 13 and 14 Nov 2026; the recogniser and the swipe code changed on
  16 Nov. Run both rigs again on the build that ships and write the commit here. Until then the page says
  "51 ms, measured" or "about 50 ms".
- **Recount** on the day: the Swift files, the tests and the size, once TRANSCRIBE is committed (and the tree in
  `#source` with it); run `scripts/rules.sh`; read TRANSCRIBE's lines on the page against the app's README again.
- **Safari.** The page was checked in Chrome only. Open it in Safari at 390, 820 and 1440 before publishing.
- **"First open: Privacy & Security › Open Anyway"** (`#download`) holds while releases are signed ad hoc and not
  notarized. If they are ever notarized, remove the line, and let the nav's and the hero's Download download.
- **Last, delete the scaffolding:** `lab/` (the polish round's tools, findings and screenshots; render the link's
  picture first), the working copies `_work-*.html`, `assets/icon-512.png` once nothing uses it
  (`grep -c icon-512 index.html` prints 0), and in `app.js` the `tiny()` guard, which is there only for `lab/shot.mjs`.
