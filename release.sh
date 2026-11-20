#!/bin/sh
# Makes a release in dist/: a zip and a disk image of the app, signed ad hoc, their SHA-256 sums and
# the release notes. No Apple developer account, no notarization. It uploads nothing.
#
# The app's name and bundle id are read from Resources/Info.plist, the one place they are written.
# build.sh writes the version (from VERSION) and the build number (the commits so far) into the app it
# makes; this script checks them, and the signature, before it packs anything.
#
# Before: put the version in VERSION (one line, like 1.0.0). In CHANGELOG.md, move the Unreleased
# lines under "## 1.0.0 - <date>". Commit, then tag: git tag v1.0.0.
# Then: ./release.sh. Check the app. Publish by hand with the commands it prints.
set -eu
cd "$(dirname "$0")"

die() { echo "release: $*" >&2; exit 1; }
[ -x scripts/rules.sh ] || die "scripts/rules.sh is missing"

# One value from a property list, or nothing.
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null; }
# The name and the bundle id. Never change the id once the app is out: macOS ties every permission to it.
NAME=$(plist CFBundleName Resources/Info.plist) || die "Resources/Info.plist has no CFBundleName"
ID=$(plist CFBundleIdentifier Resources/Info.plist) || die "Resources/Info.plist has no CFBundleIdentifier"

# The version: three numbers.
[ -f VERSION ] || die "no VERSION file"
VERSION=$(tr -d ' \t\r\n' < VERSION)
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "VERSION must be three numbers, like 1.0.0, not '$VERSION'"
TAG="v$VERSION"

# This version's part of CHANGELOG.md, for the release notes. It must call the app by its name, not by a
# placeholder in double braces, as the documents do until the name is chosen.
CHANGES=$(awk -v v="$VERSION" 'BEGIN { gsub(/\./, "\\.", v) }
  /^## / { if (on) exit; if ($0 ~ ("^## \\[?" v "\\]?( |$)")) { on = 1; next } }
  on && (seen || NF) { seen = 1; print }' CHANGELOG.md 2>/dev/null || true)
[ -n "$CHANGES" ] || echo "release: CHANGELOG.md has no '## $VERSION' section, so the notes have no changes"
case $CHANGES in
  *'{{'*) die "CHANGELOG.md's $VERSION section still has a placeholder in double braces: fill it in" ;;
esac

# Only committed code goes out, and a version names one commit.
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
[ -z "$(git status --porcelain)" ] || die "uncommitted changes: commit or stash them first"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  [ "$(git rev-list -n 1 "$TAG")" = "$(git rev-parse HEAD)" ] || die "$TAG is another commit: raise VERSION"
else
  echo "release: $TAG is not tagged yet. Tag this commit before you publish: git tag $TAG"
fi
BUILD=$(git rev-list --count HEAD)   # the build number: commits so far, as build.sh counts them

# Build from source, as anyone can, into a fresh app. A warning stops it.
APP="$NAME.app"
PLIST="$APP/Contents/Info.plist"
rm -rf "$APP"
WARNINGS_AS_ERRORS=1 ./build.sh
[ -d "$APP" ] || die "build.sh made no $APP"

# What build.sh promises: the id, the version and the build number, and an ad hoc signature whose rule is
# the id alone, so that permissions given to an earlier version carry over to this one.
got=$(plist CFBundleIdentifier "$PLIST") || true
[ "$got" = "$ID" ] || die "$APP has the id '$got', not $ID"
got=$(plist CFBundleShortVersionString "$PLIST") || true
[ "$got" = "$VERSION" ] || die "$APP is version '$got', not $VERSION"
got=$(plist CFBundleVersion "$PLIST") || true
[ "$got" = "$BUILD" ] || die "$APP is build '$got', not $BUILD"
codesign --verify --strict --verbose=2 "$APP"
codesign -d -r- "$APP" 2>&1 | grep -qxF "designated => identifier \"$ID\"" ||
  die "$APP is not signed with the rule: identifier \"$ID\". Permissions would not carry over."
scripts/rules.sh "$APP" || die "$APP breaks a house rule (above)"

mkdir -p dist
ZIP="dist/$NAME-$VERSION.zip"
DMG="dist/$NAME-$VERSION.dmg"
SUMS="dist/$NAME-$VERSION.sha256"
NOTES="dist/$NAME-$VERSION-notes.md"
rm -f "$ZIP" "$DMG" "$SUMS" "$NOTES"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The zip: the app at the top, with its signature and links kept. --norsrc leaves out file attributes
# (macOS tags new files): stored in a zip they become ._ files, and any unzip but Finder's breaks the signature.
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"

# The disk image: the app and a link to Applications to drag it onto.
# (macOS 27 calls hdiutil create deprecated but still runs it. The new way: diskutil image create from.)
mkdir "$TMP/dmg"
ditto "$APP" "$TMP/dmg/$APP"
ln -s /Applications "$TMP/dmg/Applications"
hdiutil create -quiet -volname "$NAME" -srcfolder "$TMP/dmg" -format UDZO -ov "$DMG"
hdiutil verify -quiet "$DMG"

# What people download: unpack the zip with plain unzip, the strictest way, and check the app in it.
unzip -q "$ZIP" -d "$TMP/unzipped"
codesign --verify --strict "$TMP/unzipped/$APP" || die "the app in $ZIP does not verify"
[ "$(plist CFBundleShortVersionString "$TMP/unzipped/$PLIST")" = "$VERSION" ] ||
  die "the app in $ZIP is not version $VERSION"

(cd dist && shasum -a 256 "$NAME-$VERSION.dmg" "$NAME-$VERSION.zip") > "$SUMS"
# The same two files under names without the version: releases/latest/download/Notch.dmg always leads to the newest.
cp "$DMG" "dist/$NAME.dmg"
cp "$ZIP" "dist/$NAME.zip"

# The release notes: this version's part of CHANGELOG.md, how to open the app the first time, the sums.
MIN=$(plist LSMinimumSystemVersion "$PLIST")
cat > "$NOTES" <<EOF
$CHANGES

## Install

Needs a Mac with Apple silicon and macOS $MIN or newer.

1. Download $NAME-$VERSION.dmg, open it, and drag $NAME to Applications.
2. Open $NAME. macOS blocks it the first time, because it is not notarized by Apple.
3. Go to System Settings → Privacy & Security, and click Open Anyway.

Or, in Terminal: \`xattr -dr com.apple.quarantine /Applications/$NAME.app\`

Each new version needs this once. A copy you build yourself with \`./build.sh\` opens with no warning.

## SHA-256

\`\`\`
$(cat "$SUMS")
\`\`\`
EOF

echo
cat "$SUMS"
echo
echo "release: $NAME $VERSION (build $BUILD) is in dist/. Check it, then publish by hand:"
echo "  git push origin $TAG"
echo "  gh release create $TAG \"$DMG\" \"$ZIP\" \"dist/$NAME.dmg\" \"dist/$NAME.zip\" \"$SUMS\" --title \"$NAME $VERSION\" --notes-file \"$NOTES\""
