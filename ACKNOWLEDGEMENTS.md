# Acknowledgements

Notch uses nothing but what ships with macOS and Swift. Some of what it does, though, it learned from these
open-source projects. Thank you to everyone who made them.

- **[Scribe](https://github.com/WHATDOESTHEFOXSAY2U/scribe)** (MIT): does TRANSCRIBE's work, as a separate app that Notch only starts. How a link
  to one video is told from a channel or a playlist, how a text file is named and what goes in it follow Scribe's
  own rules, so both apps treat a recording alike (`Sources/Transcribe/Link.swift`, `Transcript.swift`).

- **[Stats](https://github.com/exelban/stats)** (MIT): how to read the Mac's System Management Controller, and the
  names of the temperature sensors on each chip, which TEMP reads. The commit they were taken from is named beside
  them, in `Sources/Panel/SMC.swift`.
- **[AudioCap](https://github.com/insidegui/AudioCap)** (BSD-2-Clause): how to hear what the Mac plays with a Core
  Audio tap, and how to check the System Audio Recording permission (HEAR THE MAC'S SOUND TOO).
- **[yabai](https://github.com/koekeishiya/yabai)** and **[Amethyst](https://github.com/ianyh/Amethyst)** (both MIT):
  the window server's calls that tell whether a display shows a full-screen Space.
- **[Rectangle](https://github.com/rxhanson/Rectangle)**, **[yabai](https://github.com/koekeishiya/yabai)**,
  **[AeroSpace](https://github.com/nikitabobko/AeroSpace)** (all MIT) and
  **[AltTab](https://github.com/lwouis/alt-tab-macos)** (GPL-3.0): `_AXUIElementGetWindow`, a window's number through
  Accessibility. AltTab is credited only: none of its code is used, and none may be.
- **[HapticKey](https://github.com/niw/HapticKey)** (MIT): the trackpad actuator's calls, which play the knocks a
  swipe makes.
- **[nspasteboard.org](https://nspasteboard.org)**: the markers that tell clipboard managers to leave a text out, which
  INCOGNITO uses.
- **[Hyperkey](https://hyperkey.app)**: only its bundle id is used, so that CAPS LOCK IS HYPER KEY steps aside while
  Hyperkey runs (QUIT HYPERKEY FIRST). The two would change Caps Lock against each other.

No code from these projects was found in Notch, but no line-by-line comparison was made. The names and
signatures of macOS functions are facts about macOS, not anyone's code.
