# How Notch is put together

A map for anyone about to change the code: where each part lives, how the parts talk, where code runs, what is kept
in the settings, and which calls are not in Apple's published SDK.

## The shape

- One app, one module. `build.sh` compiles every `.swift` file under `Sources/` with one `swiftc` call. There is no
  Xcode project and no outside code. So no two files may share a name, even in different folders.
- `Sources/` is grouped by feature, one subject per file, each file named after its main type.
- `Resources/` holds `Info.plist` (the name, the bundle id, the usage strings) and the icon.
- `Tests/LogicTests` tests the code that needs no window, no screen and no permission. `Package.swift` lists those
  files; it exists only for the tests, and `./test.sh` runs them.

## Start and quit

- `App/main.swift`: started with the argument `warm`, Notch only reads one made-up picture and leaves (the warm
  helper, below). If another copy with the same id is running (`Launch.otherCopy`), it opens that one, which shows its
  Settings, and quits before anything starts. Otherwise it starts the app with no Dock icon.
- `AppDelegate.applicationDidFinishLaunching`, in order: the settings' default values (`Prefs.register`); the sounds;
  the welcome card, until its key has been pressed once (`Prefs.welcomed`); the notch panel (`place`, again whenever
  the screens change); the global shortcuts; `Dictation.say` pointed at `Tools.say`; the Mac's sound given back if a
  crash left it muted (`Quiet.recover`); the speech engine looked up (`Dictation.prepare`); the hyper key started if
  switched on, or Caps Lock given back if a crash left it as F18 (`Hyper.recover`); `Swipe.say` pointed at
  `Tools.say`; swiping started if switched on; `Transcribe.say` pointed at `Tools.say`, and its watch on drags started
  (`Transcribe.watchDrags`); `Shrink.say` pointed at `Tools.say`, and its watch on presses started
  (`Shrink.watchPresses`); then the warm helper (`Launch.warmTextModel`): only with TEXT on, and
  only when macOS has changed since it last ran to the end (`Prefs.warmedFor`), a second Notch, started with
  `warm`, reads one picture so macOS prepares its text model before the first TEXT.
- Quitting waits until a recording's file is finished (`applicationShouldTerminate`), then gives Caps Lock and the
  Mac's sound back, takes down the system-audio tap and stops a transcription under way, which ends Scribe's program
  (`applicationWillTerminate`).
- Opening the app while it runs shows Settings (`applicationShouldHandleReopen`): from Finder, or from a second copy
  as it quits.

## The files

**App**
- `main.swift`: start-up only; the warm helper's way out; one copy at a time.
- `AppDelegate.swift`: makes `Stats`, `Tools`, `Dictation`, `Transcribe`, `Shrink` and the notch panel; wires the shortcuts and the status
  line; starts the hyper key and swiping if they are on; the Settings window; placing the panel, on the notch or, on
  a screen without one, on a 140-point stand-in at the top centre; the welcome card; quitting.
- `Launch.swift`: another copy already running, if there is one; whether the warm helper runs, and starting it.

**Shared** (used by several folders)
- `AppInfo.swift`: the app's name, version and build, read from Info.plist while it runs; whether it runs from an
  Applications folder.
- `Clipboard.swift`: puts text on the clipboard, plainly or INCOGNITO (marked, kept on this Mac, handed over only
  when an app pastes, taken back later).
- `EventCodes.swift`: named numbers for Esc, the trackpad gesture event and the scroll phases.
- `EventTap.swift`: makes a tap on input events and runs it on a thread of its own.
- `FloatingPanel.swift`: the see-through panel every window but Settings is; the host that lets the first click land;
  `NotchHost` and `NotchHover`, which bind the notch's tracking rectangle strictly to the physical notch when closed
  and to the open black shape while expanded; the window levels of a recording.
- `Format.swift`: a length of time ("1:01:05") and a file size ("9.1 MB").
- `Hardware.swift`: what this Mac is and has: model, chip, macOS, screens and notch, microphone, camera, the speech
  engine, trackpads.
- `Log.swift`: one line in the Mac's log at a real failure: words fixed in the code and macOS's number for why.
- `Permissions.swift`: where each permission stands, without asking; each one's page in System Settings; whether
  Screen Recording was given after Notch started, for the RESTART key.
- `Prefs.swift`: every settings key and its default value; which parts are switched off.
- `PrivateCalls.swift`: every call outside Apple's published SDK, looked up by name, each with its fallback.
- `Report.swift`: the COPY REPORT text, from facts gathered without asking anything; the newest crash file's name.

**Style**
- `Style.swift`: the palette (black, white, two greys, amber, red), the one spring, the fonts, headings, captions,
  hairlines, outlines and the lamp of a switch.
- `Key.swift`: the text key every surface uses: it ticks under the pointer and acts on mouse-down.
- `Glyphs.swift`: the small pictures, drawn from lines and blocks on a 16-point grid: one for each tool, the
  recording strip's, and TRANSCRIBE's two large keys.
- `Sounds.swift`: the app's sounds, short sine tones made at launch; silent while recording or when switched off.

**Panel**
- `Console.swift`: the black shape on the notch: closed, open, dictating, the COPIED band, transcribing (the meter, the
  band that catches a drop, DONE), a dropped video (its choices, the meter, the copy made), the line under the notch.
  A line too long for the notch widens the shape, as the COPIED band does, then takes a second line.
- `Readouts.swift`: the open panel: the gauges, the mirror and the function bar, or TRANSCRIBE's choices once it is
  pressed; `Parts`, the parts' names. A cell of the bar whose name is wider than its share widens under the pointer.
- `Stats.swift`: the readings (memory, CPU, temperature, fan, swap, battery) and FREE's heaviest apps; what this Mac
  lacks for TEMP, DICT, TRANSCRIBE and the mirror (`missing`), looked at as the panel opens.
- `SMC.swift`: reads temperature and fan keys from the Mac's System Management Controller: the keys for each chip
  generation, from the Stats app's list, each asked once for its type.
- `Camera.swift`: the mirror: the camera's picture, flipped, only while it shows.
- `Welcome.swift`: the card shown once, at the first launch: where the panel is, that nothing done here leaves this
  Mac, START AT LOGIN as a choice, and that each tool asks for its permission the first time.

**Settings**
- `SettingsView.swift`: the Settings window: a switch for each part, PERMISSIONS, COPY REPORT and the version line,
  the shortcuts, the hyper key, swiping, dictation, recording, START AT LOGIN, INCOGNITO and QUIT; a switch that waits
  for a permission is tried every second, and while the window is open the permissions are read again every second.
- `SettingsPreview.swift`: the drawing of the open panel at the top of Settings, with made-up readings.
- `LoginItem.swift`: START AT LOGIN, through macOS's login item; only a copy in an Applications folder is added.

**Capture**
- `Tools.swift`: runs SHOT, TEXT and REC, and holds the line under the notch (`say`).
- `Restart.swift`: the card with the RESTART key, once Screen Recording is allowed: a small `/bin/sh` waits for the
  app to quit, then opens it again.
- `Selection.swift`: the dimmed screen and the crosshair to drag out a rectangle; for REC, then the outline and the
  red frame.
- `Region.swift`: a rectangle on one screen, as ScreenCaptureKit wants it; a still picture of it, and PNG data.
- `ReadText.swift`: reads the text in a picture with Vision, keeping lines, indents and columns; `warmReader`.
- `TextLayout.swift`: the arithmetic of text reading: columns, indents, arrows.
- `Card.swift`: the card a finished SHOT or REC shows at the bottom left: COPY, SHOW, ×, and COMPRESS.

**Compress**
- `Compress.swift`: the smaller copy of a video, written by the Mac's own encoders (HEVC, or H.264 for WhatsApp): of a
  recording, from its card, and of a video dropped on the notch; what a copy would weigh, from a few seconds of it
  compressed as a trial.
- `Preset.swift`: the three sizes, BEST, BALANCED and WHATSAPP, and their arithmetic: the picture each keeps, the
  bits WhatsApp's limit leaves, a copy's weight from its trial pieces, where the copy goes.
- `Shrink.swift`: COMPRESS for a dropped video: the video the notch asks about and its sizes as they are worked out,
  the copy being written, the copy just made; stopping.
- `Sizes.swift`: the panel for a dropped video: TRANSCRIBE and COMPRESS, then the three sizes (`Sizes`); the one line
  for the copy once it is made, with SHOW IN FINDER (`Shrunk`).

**Recording**
- `Session.swift`: one recording, from the options strip to the finished file.
- `Recorder.swift`: the screen, the Mac's sound and the microphone, straight into an HEVC file; pause and resume.
- `Strip.swift`: the row of keys beside the region: the options (MIC and CAM only on a Mac with a microphone and a
  camera), start, pause, stop and the clock.
- `Stage.swift`: the one Notch window in a recording: the click marks and the camera tile.

**Dictation**
- `Dictation.swift`: DICTATE: the microphone, the words as they come, stopping, delivering the text.
- `Recognizer.swift`: one dictation's line to Apple's on-device speech engine: sound in, text out.
- `Loudness.swift`: how loud the microphone is, for the wings.
- `Paste.swift`: where the finished text goes: the clipboard and, with Accessibility, ⌘V in the text box in front.
- `Quiet.swift`: mutes the Mac's output while you dictate, and gives it back, after a crash too.
- `Ordinals.swift`: "1st" back to "first", except beside a month.
- `MacSound.swift`: HEAR THE MAC'S SOUND TOO: a Core Audio tap on what the Mac plays.
- `Backlog.swift`: carries the Mac's sound from Core Audio's thread to the microphone's.
- `Wings.swift`: what the notch shows while you dictate (`Wings`), and the band after it (`Copied`).

**Transcribe**
- `Transcribe.swift`: TRANSCRIBE: takes a pasted link, a chosen file or a drop; the recordings waiting their turn;
  what the notch shows of the one in hand; saving each text; stopping; the watch on drags near the notch.
- `Scribe.swift`: the separate app that does the work: where its program is, starting it for one recording or for a
  channel's list, reading the lines it prints, ending it; where it keeps its texts.
- `Transcript.swift`: what Scribe hands back, and what Notch makes of it: the text, the file's name, the word
  count, the folder's name on the card, a failure as one line.
- `Link.swift`: a web link found in a piece of text; one video told from a channel or a playlist; a video or sound
  file told by its name.
- `Recent.swift`: CHOOSE FILE's list: the newest recordings on the Desktop and in Downloads and Movies.
- `Choices.swift`: the panel once TRANSCRIBE is pressed: PASTE LINK and CHOOSE FILE, how many of a channel, the
  list of recordings, the SPEAKERS switch.
- `Meter.swift`: what the notch shows while a recording is worked on, and the STOP key under the pointer (`Meter`);
  the line across the notch for a drop and for DONE (`Band`).
- `Catch.swift`: catches what is dragged onto the black shape, if it is something to transcribe or one video to
  compress; the video goes to `Shrink`, which asks what to do with it.
- `TranscriptCard.swift`: the card a finished transcript shows at the bottom left: COPY, OPEN, SHOW, ×.

**Keys**
- `Hotkeys.swift`: the global shortcuts (Carbon hot keys): stored, labelled, registered; SHORTCUT TAKEN.
- `Hyper.swift`: Caps Lock as a hyper key: Caps Lock mapped to F18 on each keyboard, and a key tap that adds ⌃⌥⇧⌘.
- `HyperState.swift`: pure state machine for the hyper key: Secure Input and idle-hold recovery when an F18 key-up is
  missed, and a circuit breaker for repeated tap timeouts.
- `Watchdog.swift`: every 3 s while the hyper key or swiping runs, checks Accessibility trust off the main thread; if
  removed, switches both off and gives Caps Lock back without creating temporary HID event taps.

**Windows**
- `Swipe.swift`: the tap on scrolls and gestures: swipes and pinches on title bars, decided on the tap's thread.
- `Windows.swift`: moves, minimises, closes and full-screens other apps' standard windows through Accessibility.
- `Place.swift`: where a swipe can send a window: a rectangle of the screen, and a colour for the picture.
- `Layout.swift`: whether a window is the title strip of a full-screen window, `TitleBar` rules restricting swipes
  strictly to the top title-bar section of real top-level resizable standard windows (never sub-windows, tabs, sidebars
  or content), and `SwipeMath` polar swipe cones and hysteresis.
- `Pointer.swift`: the small picture that stands in for the pointer during a swipe.
- `Bars.swift`: verifies through Accessibility that a point is strictly on the top section of a real standard window.
- `WindowList.swift`: the windows on screen, front to back, from the window server.
- `Spaces.swift`: whether a display shows a full-screen Space.
- `Knock.swift`: the knocks felt in the trackpad.
- `AX.swift`: small helpers for asking another app through Accessibility; the text-box test.

## How the parts talk

- **Five objects keep the state.** `AppDelegate` makes `Stats`, `Tools`, `Dictation`, `Transcribe` and `Shrink` once.
  The panel's views are rebuilt every time it opens, so nothing lasting lives in them. The five (and a recording's
  `Session`) are `@Observable`: the views read them and call their methods.
- **One line under the notch.** Everything the notch says goes through `Tools.say(_:stays:)`, which sets
  `Tools.status` for 2 seconds (or, with `stays`, until the next line); `Console` shows it. `Dictation.say`,
  `Transcribe.say` and `Swipe.say` are set to `Tools.say` at launch; `Windows` speaks through `Swipe.say`, on the main thread; a
  recording's `Session` calls `Tools.say` itself.
- **Shortcuts** run what the panel's keys run: `Hotkeys.actions`, set at launch, sends SHOT, TEXT and REC to
  `Tools.run` and DICT to `Dictation.toggle`.
- **Settings and the parts meet in the settings**, under the keys in `Prefs`: Settings writes a switch, and each part
  reads it when it runs. No part refers to Settings. Where a switch needs a tap or a permission to work at once,
  Settings also starts or stops that part itself: `Hyper.start`/`stop`, `Swipe.start`/`stop`,
  `MacSound.ask`/`stop`/`allowed`, `Hotkeys` (to read and save the keys), `Permissions` (to show each permission and
  open its list), `Report` for COPY REPORT, and `LoginItem` for START AT LOGIN. While the window is open, it also
  starts the hyper key and swiping again if they are switched on but not running, as after the `Watchdog`.
- **SHOT and TEXT:** `Tools.run` → the Screen Recording check (macOS's question the first time; once it is allowed,
  the `Restart` card until Notch starts again) → `Selection.pick` → `Region.picture`
  (ScreenCaptureKit) → SHOT: a PNG on the Desktop and the clipboard, then `Card.show`; TEXT: `readText` (Vision, off
  the main thread) → `Clipboard.put`.
- **REC:** `Tools.run` → `Selection.pick`, which stays → `Session` (puts up the `Stage` and the `Strip`, and
  prepares a `Recorder`) → REC again starts the file → STOP → `Tools.stop` → `Session.end` → `Card.show` →
  COMPRESS → `Compress.run`.
- **DICTATE:** `Dictation.toggle` → the microphone's permission → `Quiet.begin` (unless HEAR is on) → the
  microphone's tap: each buffer goes to `MacSound.mix` (with HEAR on), `Loudness.take` and `Recognizer.hear` → words
  come back on the main thread → `Wings` → on stop, `Recognizer.finish` → `deliver`: `Clipboard.put` and
  `pasteIntoTextBox` → the `Copied` band.
- **TRANSCRIBE:** the bar's key → `Choices` in the panel → `Transcribe.paste` (the clipboard's link; a channel or a
  playlist comes back for `Choices` to ask how many, then `Transcribe.take`) or `Recent.files` and `Transcribe.take`;
  or a drop on the shape → `Catch` → `Transcribe.drop`. Then, one recording at a time: `Scribe.transcribe` starts
  Scribe's program and reads its lines → `Transcribe.working` → `Meter` on the notch → the text written to a file →
  when nothing waits, `Transcribe.done` (the DONE band) and `TranscriptCard.show`. A channel or a playlist is first
  opened out into its recordings (`Scribe.list`). STOP: `Transcribe.stop` cancels the task, which ends the program.
- **COMPRESS, for a dropped video:** one video file (mov, mp4, m4v) dropped on the shape → `Catch` → `Shrink.offer`
  → `Shrink.asking` → `Sizes` on the notch: TRANSCRIBE (`Transcribe.take`, as above) or COMPRESS, then a size.
  Meanwhile `Compress.estimate` works out what each size would weigh. A size pressed → `Shrink.compress` →
  `Compress.run` → `Shrink.working` → `Meter` on the notch → `Shrink.done` → `Shrunk`, until SHOW IN FINDER is pressed,
  the pointer has been and gone, or 30 seconds pass. STOP: `Shrink.stop` cancels the task and removes the unfinished
  copy. Several files, a sound file or a link go to TRANSCRIBE as before.
- **SWIPE:** the tap's thread → `Swipe.route` → `begin` (`WindowList.read`, `Spaces.fullScreen`) → at once, or
  after `Bars.ask` → `move` → `Knock.knock` and `Pointer.show` → fingers lift → `Windows.send`.
- **The hyper key:** its tap's thread → `Hyper.route`: while F18 (Caps Lock) is held, every other key gets ⌃⌥⇧⌘.
- **The watchdog:** while the hyper key or swiping runs, `Watchdog` makes a test tap every 2 s, on the main thread. If
  macOS refuses it, it calls `Hyper.stop` and `Swipe.stop`. Their switches stay on, so they start again at the next
  launch, or from Settings while it is open.

## Where code runs

- **The main thread:** everything drawn, `Tools`, `Dictation`'s state, `Transcribe`, `Session`, Settings, the hot keys,
  the readings' timer, the `Watchdog`'s test tap every 2 s, and the watch on drags (a few numbers read per mouse move
  while a button is down). It asks another app one thing: before a paste, whether a
  text box has the keyboard (`Paste`).
- **Two tap threads**, made by `EventTap.run`, each with its own run loop at the highest priority: the hyper key's
  keyboard tap and swiping's scroll tap. Every key press, or every scroll, in every app passes through them, so they
  never wait for another app. Answers from other queues reach the swipe's thread through its run loop
  (`Swipe.onTap`).
- **Serial queues**, one per job that may block:
  - `notch.camera` (`Camera`): starting and stopping the camera;
  - `notch.recorder` (`Recorder`): every frame and every write of a recording;
  - `notch.dictation` (`Dictation`): starting and stopping the microphone;
  - `notch.macsound` (`MacSound`): making and taking down the system-audio tap;
  - `notch.bars` (`Bars`): Accessibility questions about toolbars;
  - `notch.windows` (`Windows`): moving windows, with a time limit on every question to an app;
  - `notch.knock` (`Knock`): the trackpad's actuator, whose calls take 3 to 35 ms.
- **Core Audio's real-time thread** calls `Backlog.write` with each piece of the Mac's sound. It never allocates, and
  holds its lock only while it copies.
- **The microphone's thread** calls `MacSound.mix`, `Loudness.take` and `Recognizer.hear` for each buffer.
- **Swift tasks off the main thread:** packing a SHOT into PNG, reading text, compressing a recording, the speech
  engine's results, Settings' reading of the five permissions, every second while it is open, waiting for the next
  line Scribe prints, and reading CHOOSE FILE's folders.
- **A global queue:** `Stats.look`, as the panel opens: is there a microphone, the speech engine, a camera, Scribe.
- **Other processes:** the warm helper, which reads one picture and exits; the RESTART key's `/bin/sh`, which
  waits for Notch to quit, opens it again, and exits; and Scribe's program, once for each recording TRANSCRIBE
  works on. It is not Notch's code: it does the fetching and the speech work, at low priority, and is ended at
  STOP and when Notch quits.

## Settings keys

Kept by macOS under the bundle id (`defaults read local.notch`). A key never changes: what was saved under the old one would
be lost.

| Key | Starts | What |
|---|---|---|
| `hidden` | "" | the parts switched off, e.g. "CAM,FAN" |
| `incognito` | false | INCOGNITO |
| `effects` | true | SOUND EFFECTS |
| `hyper` | false | CAPS LOCK IS HYPER KEY |
| `swipe` | false | SWIPE TITLE BARS |
| `shortcut.SHOT`, `.TEXT`, `.REC`, `.DICT` | ⌃⌥S, ⌃⌥T, ⌃⌥R, ⇪D | each shortcut, as "key code,modifiers,label" |
| `paste` | true | PASTE INTO ACTIVE TEXT BOX |
| `hush` | true | MUTE THE MAC WHILE DICTATING |
| `hear` | false | HEAR THE MAC'S SOUND TOO |
| `quality` | BALANCED | a recording's QUALITY |
| `fps` | 60 | a recording's FRAMES / SEC |
| `cam`, `mic`, `sound`, `clicks` | false, false, true, true | a recording's options |
| `camShape`, `camWidth` | 0, 0 | the camera tile's shape and width |
| `speakers` | true | TRANSCRIBE's SPEAKERS: tell who is speaking |

Notes Notch leaves itself, with no default: `capsLockIsF18` and `mutedOutput`, put right at the next launch after a
crash; `welcomed`, `warmedFor` and `toldPasteNeedsAccessibility`, so that the welcome card, the warm helper (once per
macOS build) and the paste line are not repeated.

## Calls outside the published SDK

Each is looked up by name in `PrivateCalls.swift` the first time it is needed, never linked, so a macOS without it
still starts Notch, and the part falls back as the last column says.

| Call | Used by | For | Without it |
|---|---|---|---|
| `_CGSDefaultConnection`, `CGSManagedDisplayGetCurrentSpace`, `CGSGetActiveSpace`, `CGSSpaceGetType` | `Spaces` | whether a display shows a full-screen Space | "not full screen" |
| `CGSSetConnectionProperty` ("SetsCursorInBackground") | `Pointer` | hiding the arrow during a swipe | the arrow stays visible |
| `_AXUIElementGetWindow` | `Windows` | a window's number | windows are found by their frames |
| `MTActuatorCreateFromDeviceID`, `MTActuatorOpen`, `MTActuatorClose`, `MTActuatorActuate` (MultitouchSupport) | `Knock` | the knocks | the public haptic call |
| `TCCAccessPreflight` (TCC) | `MacSound`, `Permissions` (PERMISSIONS in Settings; the RESTART key, through `Permissions.screenNeedsRestart`, from `Tools.run`) | whether a permission is given, without asking | `MacSound` simply tries; `Permissions` tells SCREEN and ACCESSIBILITY only ON or OFF, and SYSTEM AUDIO not at all; no RESTART key: after allowing Screen Recording, quit Notch and open it again |
| `responsibility_get_pid_responsible_for_pid` | `Stats` | which app a helper process belongs to, for FREE | each process counts alone |

Public calls used in ways Apple does not document:

| What | Used by | For | If it changes |
|---|---|---|---|
| SMC temperature keys for each chip generation (`SMC.tempKeys`, from the Stats app's list) and `F0Ac`, `F1Ac` (fans), each asked once for its type, read through IOKit | `SMC`, `Stats` | TEMP and FAN | TEMP hides; FAN shows SWAP |
| Gesture event field 110 (8 is a pinch) | `Swipe` | pinch to close | pinches pass through to the app |
| `"AXFullScreen"`, `"AXEnhancedUserInterface"` | `Windows` | full screen; no animated resizes | full-screen swipes fail |
| The "inverted" flag of a scroll caught by the tap (`NSEvent.isDirectionInvertedFromDevice`) | `Swipe` | natural scrolling | if scrolls stopped carrying it, swipes would point the wrong way with natural scrolling on |
| `expectsMediaDataInRealTime`, a property macOS 27 retired that a recording's newer calls still need | `Recorder` | a recording's file takes its data live | built for macOS 26 it compiles without a warning; an SDK without it would stop the build |

## Files Notch writes

Shots and recordings on the Desktop; transcripts, as text files, in the folder Scribe saves to (read from Scribe's
own settings, `local.scribe`; Documents/Scribe until one is chosen there); its settings, through macOS; the text
model macOS compiles for it, in `~/Library/Caches/local.notch`; and, at real failures, lines in the Mac's log under the
subsystem `local.notch`. Nothing else.
