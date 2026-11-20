# Security

## Report a problem privately

Do not open a public issue for a security problem.

- **On GitHub:** https://github.com/WHATDOESTHEFOXSAY2U/notch/security/advisories/new. It is the **Report a vulnerability** button on the repository's
  Security tab. Only the maintainer sees the report.

Include what you can:
- what someone could do with it, and what they need first: an app already on the Mac, the Mac in their hands, or
  nothing at all;
- the steps, or a small proof;
- the Notch version, the macOS version and build, and the Mac model (COPY REPORT in Settings copies them);
- where your copy came from: the Releases page, or your own `./build.sh`.

What happens next:
- You should hear back within a week.
- If the problem is real, the fix goes into a new release. Then a GitHub advisory says what was wrong, and names you
  if you want.
- Please keep it private until the fix is out.

There is no bug bounty. Problems in macOS itself go to Apple: https://security.apple.com.

## Supported versions

Only the latest release gets fixes. Check that the problem is still there in the latest release, or on `main`.

## What Notch can touch

This helps judge a report.

| What it can touch | When |
|---|---|
| The screen | SHOT, TEXT and REC, while they run |
| The microphone | while you dictate; in a recording with MIC on |
| The camera | MIRROR; a recording with CAM on |
| What the Mac plays | a recording with SOUND on; dictation with HEAR THE MAC'S SOUND TOO on |
| Where you click | a recording with CLICKS on |
| Every key press | while CAPS LOCK IS HYPER KEY is on |
| Every scroll and trackpad gesture | while SWIPE TITLE BARS is on |
| Other apps' windows: move, resize, minimise, close, full screen | a swipe or a pinch on a title bar |
| A Command-V pressed for you in the app in front | after a dictation, with PASTE INTO ACTIVE TEXT BOX on |
| The clipboard | SHOT, TEXT and dictation put their result there; with INCOGNITO on, they also read what was there, to put it back. PASTE LINK reads it once, at the press, for a link; COPY on a transcript's card puts the text there |
| Scribe, a separate app, started as a program of its own | TRANSCRIBE: once for each recording, with the file's path or the link; ended at STOP and when Notch quits |
| What is being dragged anywhere on the Mac: its kind, and where the pointer is | always, with TRANSCRIBE on: so the notch widens as a recording or a link comes close. Never what is in it |
| The Desktop, Downloads and Movies folders: the names and lengths of the newest recordings | CHOOSE FILE, when it is pressed |
| Caps Lock, turned into F18 on every keyboard | while CAPS LOCK IS HYPER KEY is on |
| The Mac's sound output, muted | while you dictate, with MUTE THE MAC WHILE DICTATING on |
| Running apps: how much memory each uses, and force quit | FREE; it quits only the app you press |
| Files: shots and recordings on the Desktop, transcripts in Scribe's folder, and its own settings | SHOT, REC, TRANSCRIBE, Settings |
| Itself: a second copy for a moment, or a restart | at the first launch and after each macOS update, with TEXT on, a copy reads one made-up picture to prepare text reading; RESTART Notch, after you allow Screen Recording |

macOS asks for Screen Recording, Microphone, Camera, System Audio Recording and Accessibility the first time a part
needs them, never at launch.

What it does not do:
- It sends nothing anywhere: there is no network code. Any way to make it send something is a security bug. (macOS
  itself may download Apple's speech model the first time you dictate. And TRANSCRIBE with a link has Scribe, a
  separate app, fetch that link: the link you gave it, and nothing else.)
- It writes no log of key presses, dictated text, clipboard text or window titles. When something fails, it writes
  one line to the Mac's log: what failed, in words fixed in the code, and macOS's number for why.
- It installs no helper, no system extension and nothing that runs as root. Scribe is installed by you, never by
  Notch, and runs as you.
- It never updates itself.

## Known limits

These are known and accepted. A report is still welcome if you find they do more harm than described here.

- **Releases are not notarized.** They are signed ad hoc. macOS blocks the first open; you allow it once in System
  Settings → Privacy & Security → Open Anyway. Do that only for a copy from https://github.com/WHATDOESTHEFOXSAY2U/notch/releases, and compare its SHA-256
  sum (`shasum -a 256 <file>`) with the one in the release notes. Or build it yourself.
- **Permissions follow the bundle id.** The app is signed ad hoc, so macOS knows it by its id, `local.notch`, and not by a
  developer certificate. Another app signed ad hoc with the same id might receive the same permissions. This follows
  from how macOS checks signatures (Apple's TN3127); it has not been tested.
