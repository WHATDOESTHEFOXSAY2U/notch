# Changelog

What changed in each release of Notch, newest first. A version is three numbers, like 1.0.0, and its git tag is
`v1.0.0`. The part under a version becomes its release notes on GitHub (`release.sh` copies it).

## 0.10.4 - 2026-11-27

### Fixed
- CAPS LOCK IS HYPER KEY stays enabled at launch when CoreGraphics delivers the initial `tapDisabledByUserInput`
  notification queued by `EventTap.make` before enabling the tap.

## 0.10.3 - 2026-11-27

### Fixed
- CAPS LOCK IS HYPER KEY no longer calls `IOHIDManagerOpen`, so Notch never attaches a raw kernel `IOHIDLibUserClient`
  handle to the built-in SPI keyboard (`AppleHIDTransportHIDDevice`) or external keyboards across sleep/reset cycles,
  and cleanly unschedules keyboard matching when stopped.
- Closed-panel temperature polling samples `AppleSMC` every 10 seconds (and skips it altogether when `TEMP` is switched
  off) instead of every 2 seconds, cutting background kernel SMC analytics noise by 80%.

## 0.10.2 - 2026-11-26

### Fixed
- Closing Settings, finishing a selection, or dragging the recording strip no longer leaves Notch as the focused app
  with no key window (which silently swallowed typing until another app was clicked), and floating panels no longer
  hide when Notch deactivates. Settings also responds to ⌘W and ⌘Q.
- CAPS LOCK IS HYPER KEY takes a zero-overhead fast path on ordinary typing and never extends a missed Caps Lock
  key-up across subsequent keystrokes, so continuous typing recovers automatically within seconds even if an F18
  release event is ever dropped.
- The Accessibility watchdog listens to macOS's Accessibility notification and checks `AXIsProcessTrusted()` directly,
  eliminating periodic `tccd` IPC traffic in the background.
- SWIPE TITLE BARS verifies native `AXWindow` attributes and traffic-light bounds directly instead of calling
  `AXUIElementCopyElementAtPosition`, eliminating Chromium/Electron first-swipe timeouts and DOM accessibility wakeups,
  working across the top bezel of notched MacBooks in full screen and stationary green-button swipes, and responding
  crisply to quick two-finger flicks.
- Simplified notch hover tracking (`FloatingPanel`), full-screen exit Space settling (`Windows`), open-panel process
  sampling (`Stats`), and speech-engine shutdown timeouts (`Recognizer`).

## 0.10.1 - 2026-11-26

### Fixed
- Windows in macOS full screen (whether entered with the green button or a swipe up) snap out to left, right, quarters
  or fill reliably — both immediately without moving the pointer from where it entered full screen, and at any time
  later from the top band or revealed full-screen title/tab strip (`AXFullScreenWindow` and floating full-screen
  toolbar layers included). Exiting full screen refreshes the Desktop's usable frame and re-acquires replaced window
  elements so the window lands cleanly beside the menu bar and Dock.

## 0.10.0 - 2026-11-26

### Added
- COMPRESS for any video: drop a video on the notch and it asks TRANSCRIBE or COMPRESS. COMPRESS offers three sizes,
  each with what the copy will weigh and how much smaller that is, worked out from a few seconds of the video: BEST
  (the same picture, looks the same), BALANCED (1080p) and WHATSAPP (720p, in the kind of file every phone plays, under
  WhatsApp's limit for a video). The notch shows how far it is and offers STOP COMPRESSING under the pointer; when the
  copy is made, one line shows its size, how much smaller it is, and SHOW IN FINDER. The copy goes next to the
  original, named like `Trip small.mp4`; the original is never touched. An iPhone's HDR video keeps its colours.

- REMOVE BACKGROUND NOISE, on from the start: macOS cleans the microphone's sound before DICTATE reads it, taking out
  noise and the echo of what the Mac plays. While you dictate, the microphone modes in the menu bar offer Voice
  Isolation for Notch as well.

### Changed
- A video dropped on the notch is no longer transcribed at once: the notch asks first. Sound files, links and several
  files dropped together go to TRANSCRIBE as before.
- A video can be dropped on the notch without the Scribe app: the notch then offers the sizes at once.
- TRANSCRIBE stays visible in the panel before the Scribe app is installed, and says what is needed when pressed or
  when a sound file or link is dropped on the notch.
- COMPRESS on a recording's card now keeps a tall recording upright at 1080 × 1920 instead of fitting it into 1080
  points of height.

### Fixed
- The closed notch no longer opens when the pointer is merely near it after an earlier expansion. Its tracking area
  collapses back to the physical notch immediately on close and verifies the pointer's screen coordinates.
- SWIPE TITLE BARS acts strictly on the top title-bar strip and empty top toolbars of resizable standard windows —
  never on tabs, buttons, sidebars, scroll views, sub-windows or page content — and uses calmer travel thresholds and
  polar direction cones so slight finger twitches neither hide the pointer nor misfire.
- Window snapping verifies title bars in a few milliseconds instead of timing out on busy apps, places windows cleanly
  across constrained and multi-display layouts, and never drops the next swipe after scrolling a page.
- The keyboard stays responsive: the Accessibility watchdog no longer creates temporary HID event taps every few
  seconds, the hyper-key tap makes no WindowServer calls while typing, a Caps Lock release missed during Secure Input
  (password fields, Touch ID, 1Password) no longer leaves ⌃⌥⇧⌘ stuck on later keys, and selection overlays release
  keyboard focus cleanly when switching apps.
- Dragging a file near the notch and letting go elsewhere or pressing Esc no longer leaves the drop band open.
- DICTATE hears AirPods that were connected just before it started. A dictation started while they were still
  connecting got a microphone that sent nothing, and every later one kept it, so DICTATE heard nothing until Notch
  restarted. Now a microphone that sends nothing for a second and a half is started again.
- A dictation whose microphone kept changing ends instead of staying on with nothing to hear.
- CAPS LOCK IS HYPER KEY works on a Bluetooth keyboard that connects or wakes while Notch runs.

## 0.9.0 - 2026-11-20

The first public version: any Mac with Apple silicon, on macOS 26 or newer.

### Added
- A one-line installer, `install.sh`, and the source under the MIT license.
- Runs on macOS 26 as well as 27.
- A welcome card, shown once: where the panel is, that nothing you do here leaves this Mac, a START AT LOGIN choice,
  and that each tool asks for its permission the first time.
- PERMISSIONS in Settings: SCREEN, MICROPHONE, CAMERA, ACCESSIBILITY and SYSTEM AUDIO, each ON, OFF or NOT ASKED, with
  a key that opens the right pane of System Settings.
- COPY REPORT in Settings: the version, the Mac, macOS, the displays, the sensors found and the permissions, as text to
  paste into an issue. Notch sends nothing.
- The version and build number at the bottom of Settings.
- Downloads on GitHub Releases: a disk image and a zip, with SHA-256 sums. They are signed ad hoc, not notarized, so
  macOS asks you to allow the app once. The release notes say how.
- How to uninstall, in the README.
- TRANSCRIBE: writes down what is said in a video or a sound file. PASTE LINK takes the link on the clipboard, CHOOSE
  FILE lists your newest recordings, and a recording or a link can be dropped on the notch. A channel or a playlist
  asks how many. The notch shows how far it is and offers STOP TRANSCRIBING under the pointer; a card offers COPY, OPEN
  and SHOW for the text. The work is done by the Scribe app, which must be installed: without it TRANSCRIBE hides.

### Changed
- Macs without a notch get a slimmer black stand-in at the top centre.
- A status line too long for the notch widens the black shape, as the COPIED band does, then takes a second line.
- TEMP reads the sensors the Stats app lists for each chip, and hides when none answers. It no longer shows 0.
- What a Mac lacks is hidden: no microphone hides DICT and MIC, no camera hides MIRROR and CAM, and DICT hides where
  Apple's speech engine does not run. Without a trackpad, SWIPE TITLE BARS says NEEDS A TRACKPAD.
- Run from outside Applications, START AT LOGIN says to move Notch there first, and adds no login item.
- Opening a second copy shows the first one's Settings.
- One plain line goes with macOS's question for Screen Recording, and a RESTART key comes once you allow it.
- Pasting without Accessibility says so once. Your text is on the clipboard.
- CAPS LOCK IS HYPER KEY and SWIPE TITLE BARS check every 2 seconds that macOS still lets them watch keys and scrolls.
  If it stops, as it is expected to once Accessibility is taken away, both switch off and Caps Lock works again. They
  start again once it is allowed: with Settings open, or at the next launch.
- The text-reading model is prepared at launch only the first time and after a macOS update, and only when TEXT is
  on. Before, it was prepared at every launch.
- Every status line and caption in one voice. No springs when Reduce Motion is on.

### Fixed
- Caps Lock always comes back: when you quit, when you switch CAPS LOCK IS HYPER KEY off (even if macOS had stopped
  the key watch), and at the next launch after a crash. Only Notch's own Caps Lock mapping is removed, and a
  keyboard's earlier mapping is put back.
- The Mac's sound comes back at the next launch if Notch stopped while MUTE THE MAC WHILE DICTATING had it muted.
- DICTATE follows the microphone when it changes: AirPods switching to their call mode, or being connected or taken
  out, no longer leave it hearing nothing.
- COMPRESS writes the copy's sound as plain AAC, which every player and chat app plays. Before, some played the
  picture in silence.
- A shortcut on the comma key keeps its label after a restart.
- SHORTCUT TAKEN shows when macOS refuses a shortcut.
- A recording over an hour reads the same on the strip and the card: 1:01:05.
- No crash when macOS lists no screens.
- Notch starts even on a macOS without the private call FREE uses to count helpers with their app. Each process then
  counts alone.
- The app needed macOS 27.2 while it said 27.0. Now the app and its Info.plist say the same.

### Removed
- The development log of every trackpad scroll.
- Code left over from development.

### Under the hood
- The code is grouped by feature in `Sources/`, one subject per file. Nothing you see or hear changes.
- Tests for the logic that needs no screen: `./test.sh`.
- Each private call is looked up by name, in one file, with a fallback.
- Natural scrolling is read from each scroll event, not from a hidden setting. The System Audio permission is asked
  for the public way.
- Log lines (`os.Logger`) only at real failures. Never dictated text, clipboard text or window titles.
- CI builds every push and pull request, runs the tests, and checks that the app has no network code.
