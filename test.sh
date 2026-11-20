#!/bin/sh
# Runs the tests of the logic that needs no screen (Package.swift lists its files). No window, no permission,
# nothing audible. The app itself is built by build.sh, never by this.
set -e
cd "$(dirname "$0")"
# Package.swift is read afresh each time, so a file just added to Sources is left out of the tests at once.
swift test --manifest-cache none "$@"
