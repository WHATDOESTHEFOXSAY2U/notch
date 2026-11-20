#!/bin/sh
# Installs the latest Notch release into /Applications and opens it.
#   curl -fsSL https://raw.githubusercontent.com/WHATDOESTHEFOXSAY2U/notch/main/install.sh | sh
set -e
REPO="WHATDOESTHEFOXSAY2U/notch"

[ "$(uname -s)" = "Darwin" ] || { echo "Notch runs on macOS only."; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "Notch needs a Mac with Apple silicon (M1 or later)."; exit 1; }
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 26 ] || { echo "Notch needs macOS 26 or later (this Mac has $(sw_vers -productVersion))."; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Downloading Notch..."
curl -fL --progress-bar "https://github.com/$REPO/releases/latest/download/Notch.zip" -o "$TMP/Notch.zip"
ditto -x -k "$TMP/Notch.zip" "$TMP"
[ -d "$TMP/Notch.app" ] || { echo "The download did not contain Notch.app."; exit 1; }
codesign --verify --strict "$TMP/Notch.app" || { echo "The download is damaged. Try again."; exit 1; }

# A running Notch quits the normal way, so it gives Caps Lock and the Mac's sound back first.
osascript -e 'tell application id "local.notch" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf /Applications/Notch.app
ditto "$TMP/Notch.app" /Applications/Notch.app
# Notch is not notarized by Apple. Without this, macOS refuses to open a downloaded copy until you allow it in
# System Settings > Privacy & Security.
xattr -dr com.apple.quarantine /Applications/Notch.app 2>/dev/null || true

echo "Notch is installed. Opening it now: move the pointer up into the notch."
echo "Each tool asks for its permission the first time you use it."
open /Applications/Notch.app
