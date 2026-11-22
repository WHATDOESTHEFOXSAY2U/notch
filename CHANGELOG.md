# Changelog

What changed in each release of Notch, newest first. A version is three numbers, like 1.0.0, and its git tag is
`v1.0.0`. The part under a version becomes its release notes on GitHub (`release.sh` copies it).

## Unreleased

### Added
- REMOVE BACKGROUND NOISE, on from the start: macOS cleans the microphone's sound before DICTATE reads it, taking out
  noise and the echo of what the Mac plays. While you dictate, the microphone modes in the menu bar offer Voice
  Isolation for Notch as well.

### Fixed
- DICTATE hears AirPods that were connected just before it started. A dictation started while they were still
  connecting got a microphone that sent nothing, and every later one kept it, so DICTATE heard nothing until Notch
  restarted. Now a microphone that sends nothing for a second and a half is started again.
- A dictation whose microphone kept changing ends instead of staying on with nothing to hear.

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
