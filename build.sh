#!/bin/sh
# Builds the app next to this script, named after CFBundleName: Notch.app. No Xcode project, no dependencies.
# WARNINGS_AS_ERRORS=1 ./build.sh refuses to finish if the compiler warns about anything: automatic checks build this way.
set -e
cd "$(dirname "$0")"
# The app's name, its program's name, its id and the oldest macOS it runs on are written in one place,
# Resources/Info.plist: read them from there.
info() { plutil -extract "$1" raw Resources/Info.plist; }
NAME=$(info CFBundleName)
EXE=$(info CFBundleExecutable)
ID=$(info CFBundleIdentifier)
MIN_MACOS=$(info LSMinimumSystemVersion)
APP="$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# The version people see, from the VERSION file, and the build number: how many commits the code has (0 outside git).
# Both go into the built app's copy of Info.plist only, so a build leaves the repository as it was.
plutil -replace CFBundleShortVersionString -string "$(tr -d '[:space:]' < VERSION)" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD 2>/dev/null || echo 0)" "$APP/Contents/Info.plist"
# -target: the program is built for the oldest macOS that Info.plist names, so the two always agree.
# Every .swift file under Sources goes into one program, so no two of them may have the same name, even in different folders.
STRICT=""
if [ "${WARNINGS_AS_ERRORS:-}" = 1 ]; then STRICT="-warnings-as-errors"; fi
swiftc -O -swift-version 5 -target "arm64-apple-macos$MIN_MACOS" $STRICT $(find Sources -name '*.swift' | sort) -o "$APP/Contents/MacOS/$EXE"
# Signed ad hoc, which needs no Apple developer account: no hardened runtime and no entitlements (only notarization
# needs those). The app is signed by its id, not by its exact contents, so macOS keeps its Screen Recording, camera and
# microphone permissions across rebuilds and updates instead of asking again each time. The cost, by Apple's rules for
# such a signature (TN3127; not tested): any program signed the same way under the same id could pass as this app and
# use those permissions. So the id must be one nobody else uses, and must never change.
codesign --force --sign - -r="designated => identifier \"$ID\"" "$APP"
