#!/bin/sh
# Checks the house rules a machine can check. Prints each broken rule and the lines that broke it, then fails.
#   scripts/rules.sh               the sources
#   scripts/rules.sh <App>.app     the sources and a built app
# CI runs both. release.sh runs the second on the app it ships.
cd "$(dirname "$0")/.." || exit 2
fail=0
broke() { echo "RULE: $1"; fail=1; }

# The app's Swift files.
app_files() { find Sources -name '*.swift' -type f 2>/dev/null; }

# The lines of app code that match an extended regular expression, as file:line:text.
# Comment lines are left out. A match in a comment after code on the same line still counts.
code() {
  app_files | while IFS= read -r f; do grep -H -n -E "$1" "$f"; done |
    grep -v -E '^[^:]*:[0-9]+:[[:space:]]*(//|/\*|\*)'
}

[ -n "$(app_files)" ] || broke "no app sources found: run this from the repository"

# 1. Nothing leaves the Mac: no network code of any kind.
net='URLSession|URLRequest|NSURLConnection|NSURLSession|NSURLRequest'                       # Foundation's URL loading
net="$net"'|import[[:space:]]+(Network|WebKit|CloudKit|MultipeerConnectivity)'                # frameworks that reach other machines
net="$net"'|NWConnection|NWListener|NWBrowser|NWEndpoint|NWPathMonitor|nw_[a-z_]+[(]'         # Network framework
net="$net"'|CFNetwork|CFSocket|CFHTTP|CFHost|CFStreamCreatePairWithSocket'                   # CFNetwork
net="$net"'|(^|[^A-Za-z0-9_])socket[(]|getaddrinfo|gethostbyname|AF_INET|PF_INET|sockaddr_in|SOCK_STREAM|SOCK_DGRAM'  # sockets
net="$net"'|WKWebView|NSUbiquitousKeyValueStore|NetService'                                    # web views, iCloud, Bonjour
net="$net"'|(https?|wss?|ftp)://'                                                              # web addresses
net="$net"'|"(/usr/bin/)?(curl|wget|nc|ssh|scp|sftp|rsync|telnet)"'                           # a network tool run as a process
code "$net" && broke "no network code: nothing the app does leaves the Mac"

# 2. Private calls are looked up by name, with a fallback, so a missing one cannot stop the app from starting.
code '@_silgen_name' && broke "private calls only through dlsym, with a fallback"

# 3. No personal paths, in any text file. In a git worktree, .git is a file that names the main checkout's folder:
# it is git's own, and left out like the .git folder.
grep -r -I -n -E --exclude-dir=.git --exclude=.git --exclude-dir=.build --exclude-dir=.swiftpm --exclude-dir=build \
  --exclude-dir=dist --exclude-dir='*.app' '/Users/[A-Za-z0-9._-]+' . &&
  broke "no personal paths: use ~ or a relative path"

# 4. build.sh is the only way to make the app.
[ -n "$(find . \( -name .git -o -name .swiftpm \) -prune -o \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print)" ] &&
  broke "no Xcode project: build.sh makes the app"

# 5. No outside libraries.
[ -f Package.swift ] && grep -n '\.package(' Package.swift && broke "no outside packages"

# The built app: what it links and imports, however the source spelled it.
if [ $# -gt 0 ]; then
  app=${1%/}
  plist="$app/Contents/Info.plist"
  exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null)
  bin="$app/Contents/MacOS/$exe"
  if [ -z "$exe" ] || [ ! -f "$bin" ]; then echo "rules: no app at $app"; exit 2; fi

  otool -L "$bin" | grep -E '/(Network|CFNetwork|WebKit|CloudKit|MultipeerConnectivity)\.framework/' &&
    broke "no network code: $app links a framework that reaches other machines"

  nm -u "$bin" | grep -E 'URLSession|URLRequest|NSURLConnection|NSURLSession|NSURLRequest|NWConnection|NWListener|NWBrowser|NWEndpoint|NWPathMonitor|^_nw_|CFSocket|CFHTTP|CFHost|CFStreamCreatePairWithSocket|WKWebView|NSUbiquitousKeyValueStore|NetService|^_(socket|connect|getaddrinfo|gethostbyname|gethostbyname2|sendto|recvfrom|bind|listen|accept)$' &&
    broke "no network code: $app imports a network call"

  strings -a "$bin" | grep -E '(https?|wss?|ftp)://|/Users/' &&
    broke "no web addresses or personal paths in $app"

  # The binary must run on every macOS that Info.plist promises.
  minos=$(otool -l "$bin" | awk '$1 == "minos" { print $2; exit }')
  want=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist" 2>/dev/null)
  case $want in *.*) ;; ?*) want="$want.0" ;; esac
  [ -n "$minos" ] && [ "$minos" = "$want" ] ||
    broke "the binary needs macOS ${minos:-?}, Info.plist says ${want:-nothing}: keep build.sh's -target and LSMinimumSystemVersion the same"
fi

if [ "$fail" = 0 ]; then echo "rules: all kept${app:+ (sources and $app)}"; fi
exit $fail
