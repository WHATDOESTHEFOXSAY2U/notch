# Contributing to Notch

Notch is small on purpose: one Mac app of about 3.6 MB, plain Swift built by one script, no outside code and no
network code. Nothing it does leaves the Mac. These rules keep it that way.

- Security problems: do not open an issue. See [SECURITY.md](SECURITY.md).
- Everyone here follows the [code of conduct](CODE_OF_CONDUCT.md).
- The look and the words are under Code rules, below. The map of the parts is in [ARCHITECTURE.md](ARCHITECTURE.md).

## Before you start

- **Fixes, tests and clearer comments:** send a pull request.
- **Anything a user can see or hear, a new feature, a new permission:** open an issue first and wait for a yes. It
  saves you work that might not be merged.
- **Help without code:** reports from Macs unlike the maintainer's are wanted (no notch, M3 or newer, Mac mini or
  Studio, macOS 26). COPY REPORT in Settings gives the details to paste. Issues that need such a Mac carry the
  `needs hardware` label.
- New here? Look for the `good first issue` label.
- One person maintains Notch. Reviews can take a while.

## What fits

A change fits when:
1. it belongs to a part that already exists: a gauge, a tool or a setting;
2. it adds no library and no network code;
3. it is off by default if it needs a permission or changes how the Mac behaves;
4. the app stays small, and looks and sounds the same.

An idea that does not fit is better as a fork: the [MIT license](LICENSE) allows one. Please give a fork its own
name, icon and bundle id.

## What will not be accepted

- **Dependencies.** No Swift packages, CocoaPods, Carthage, frameworks, binaries or copied-in libraries. Only what
  ships with macOS and Swift. (`Package.swift` exists only to run the tests, and names no packages.)
- **Network code.** No URLSession, sockets, web views, update checks or downloads.
- **Telemetry.** No analytics, usage counts, crash services or "anonymous" statistics, not even opt-in.
- **An Xcode project.** `build.sh` stays the only way to build the app.
- **Private calls linked directly:** `@_silgen_name`, or linking a private framework. See the code rules.
- **Early permission requests:** at launch, or for a part the user has not used.
- **Logs of what people do.** No dictated text, clipboard text, window titles or key presses in any log.
- **Code you may not use.** Code from elsewhere needs a license that allows it here, its notice kept, and its source
  named in the pull request. Nothing from GPL projects.
- **Mixed pull requests:** a fix, a rename and a reformat together. Split them.

One part leans on another program. TRANSCRIBE starts Scribe, a separate app the user installs, once for each
recording, and reads what it prints (`Sources/Transcribe/Scribe.swift`). Fetching a link and turning speech into text
are Scribe's work. Nothing of Scribe's is copied in or linked, and the code here still holds no network code:
`scripts/rules.sh` checks that as before. Keep it so: a change that fetches anything itself will not be accepted.

## Build and run

You need an Apple silicon Mac with Xcode 27, for the macOS 27 SDK; Xcode 27.2 runs on macOS 26.6 or later. The
Command Line Tools alone cannot build the app: they lack the SwiftUI macro plugin. The app itself runs on macOS 26 or
newer.

```sh
./build.sh                    # makes Notch.app, in about 45 seconds on an M1 Pro
open "Notch.app"
```

- Start it with `open`, never the binary inside it. Otherwise macOS gives the permissions to Terminal.
- Your build has the same bundle id as a downloaded copy, `local.notch`, so it shares that copy's settings and permissions.
- A build made on your own Mac opens without the warning a downloaded copy gets.
- Nothing is asked at launch. macOS asks for each permission the first time you use the part that needs it.
- CI builds with `WARNINGS_AS_ERRORS=1 ./build.sh`, which fails on any warning. The build has none. Keep it that way.

Careful while you try things:
- Quit the copy you use every day first (QUIT Notch in Settings). One copy runs at a time: opening a second one
  brings up the first one's Settings, and the second one quits.
- If a build crashes with CAPS LOCK IS HYPER KEY on, Caps Lock does nothing until Notch starts again or the Mac
  restarts.
- Do not take Accessibility away from Notch while CAPS LOCK IS HYPER KEY or SWIPE TITLE BARS is on, unless you have
  a second way into the Mac (Screen Sharing or SSH). One report says this can freeze all input.

## Tests

```sh
./test.sh
```

It runs the logic tests (`swift test`): the code that needs no window, no screen and no permission, such as window
places and layout, ordinals, the sound backlog, the clipboard, text layout, the report and more. Nothing shows on
screen, nothing asks for a permission, nothing makes a sound.

`scripts/rules.sh` checks the rules a machine can check: no network calls, no `@_silgen_name`, no `/Users/` paths, no
Xcode project, no outside packages. `scripts/rules.sh Notch.app` checks the built app as well: no network framework
or call, no web address, and the macOS it needs is the one Info.plist names.

CI runs these on every push and pull request: `WARNINGS_AS_ERRORS=1 ./build.sh`, both `scripts/rules.sh` checks and
`./test.sh`.

- New pure logic (code that needs no window, screen or permission) gets a test in `Tests/LogicTests`, and its file
  goes in the list in `Package.swift`.
- When you change code that has a test, run the test before and after.
- Swipes, the hyper key, dictation, recording and transcribing need a person. Try them by hand, and say in the pull
  request what you did.

## Code rules

- **Lean.** Fewer lines over clever ones. Each thing written once. No option nobody asked for.
- **One subject per file**, named after its main type, in its feature's folder under `Sources/`. File names must be
  unique across folders: the app is one module built by one `swiftc` call, and the compiler refuses two files with the
  same name.
- **Comments a non-expert can follow.** Say what the code does, why, and in which units. A measured number gets the
  date, with the year, and the Mac it was measured on. No names of people: history belongs in commit messages.
- **No outside libraries. No network code.**
- **Private macOS calls only through `dlsym`, each with a fallback.** They all live in `PrivateCalls.swift`. Next to
  each, a comment says what it is for and what happens without it. If Apple removes a symbol, Notch must still
  start, and the part must still work in a plainer way, or hide.
- **Settings keys** and their defaults live in `Prefs.swift`. Never rename a key: people would lose their settings.
- **Threads.** The main thread never waits. An event tap never waits for another app. The real-time audio thread never
  allocates, and holds a lock only while it copies.
- **Permissions** are asked only when someone first uses the part that needs it.
- **Logs.** Only `Log.failed`, and only at real failures: words written in the code and macOS's number for the
  reason. Never dictated text, clipboard text, window titles or file names.
- **Names.** Plain words, in American spelling as in Apple's APIs. Named constants, not bare numbers.
- **The look.** Black and white, monospaced capitals, square corners, hairline dividers. Colour only for meaning: amber
  warns, red is critical or recording. Words in capitals, few and plain: say what happened or what is needed, with no
  exclamation marks.
- **No license notice in the files.** The [LICENSE](LICENSE) file covers every file here, so the Swift files carry
  no notice of their own.

## Commits

- One subject per commit. Moving code is one commit; changing it is another.
- The first line says what changed, in plain words. The body says why, and how you checked it.
- Your commit email is public. To keep yours private, use your GitHub noreply address.

## Pull requests

One subject per pull request. It is squash-merged, so it lands on `main` as one commit.

A pull request shows:
- **What and why**, with a link to the issue.
- **Before and after** for anything a user can see or hear: two pictures, or a short recording if it moves or makes
  a sound. Leave out anything private: other apps, names, files.
- **How it was checked:** the Mac and chip, the macOS version and build (`sw_vers`), the displays, the commands you
  ran, and what you tried by hand, step by step.
- **For a private call:** the macOS versions you checked it on, and what the fallback does.

The pull request template asks for each of these.

## Review

The maintainer, @WHATDOESTHEFOXSAY2U, reviews every pull request, and CI must pass. Anything a user sees or hears gets the
`design` label and needs the maintainer's yes. A no is about fit, not about you.

A contribution is published under the project's license, [MIT](LICENSE). There is no agreement to sign.

## Words used here

| Word | Meaning |
|---|---|
| panel | the black shape that opens from the notch when you hover |
| stand-in | the black block at the top centre of a screen without a notch |
| welcome card | what the first launch shows under the notch: where the panel is, START AT LOGIN, how permissions are asked |
| gauges | MEM, CPU, TEMP, FAN / SWAP and BAT |
| function bar | the row of tools: SHOT, TEXT, REC, DICTATE, TRANSCRIBE, MIRROR, FREE and SET |
| FREE | turns the function bar into a list of the heaviest apps; pressing one force-quits it |
| card | what a finished SHOT or REC shows at the bottom left for a few seconds; on a recording's card, COMPRESS makes a smaller copy |
| recording strip | the small row of keys beside a region being recorded |
| wings | what the notch shows while you dictate: the sound level on both sides, the words under it |
| Scribe | the separate app that does TRANSCRIBE's work; Notch starts its program and reads what it prints |
| meter | what the notch shows while TRANSCRIBE works: what is being done, how far it is, the recording's name; point at it for STOP |
| hyper key | Caps Lock held with another key counts as Control, Option, Shift and Command |
| swipe | two fingers on a window's title bar: halves, quarters, fill, minimise, full screen; a pinch there closes the window |
| knock | a short click you feel in the trackpad during a swipe |
| INCOGNITO | dictation and TEXT show nothing and make no sound; their text is kept from clipboard managers |
| HEAR | dictation also writes down what the Mac is playing |
| COPY REPORT | the key in Settings that copies a plain description of the Mac and of how Notch is set up |
| private call | a macOS function outside the public SDK, looked up by name |
