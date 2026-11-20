<!-- One subject per pull request. Read CONTRIBUTING.md first. Security problems go to SECURITY.md, not here. -->

## What and why

<!-- What changed, and why. Link the issue: "Fixes #123". -->


## Before and after

<!--
For anything a user can see or hear: a picture before and after, or a short recording if it moves or makes a sound.
Leave out anything private. Write "Nothing a user sees or hears" if that is so.
-->


## How it was checked

- Mac and chip:
- macOS version and build (`sw_vers`):
- Displays:
- Commands run:
- What I tried by hand, step by step:

## Checklist

- [ ] One subject. Moved code is in its own commit, apart from changes.
- [ ] `WARNINGS_AS_ERRORS=1 ./build.sh` builds with no warnings
- [ ] `./test.sh` and `scripts/rules.sh` pass
- [ ] New pure logic has a test
- [ ] No outside library, no network code, no telemetry
- [ ] No new permission, or it was agreed in an issue; it is asked only on first use
- [ ] Private calls only through `dlsym` in `PrivateCalls.swift`, each with a fallback and a comment
- [ ] Comments a non-expert can follow; one subject per file
- [ ] Anything a user sees or hears follows the look and the words in CONTRIBUTING.md
- [ ] Nothing personal in the code, the pictures or the commits
