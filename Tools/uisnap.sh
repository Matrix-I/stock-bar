#!/bin/bash
# uisnap.sh — compiles Tools/uisnap.swift against the app's own views and renders the popover to a PNG.
#
#   ./Tools/uisnap.sh /tmp/panel.png        # dark (default)
#   ./Tools/uisnap.sh /tmp/panel-light.png light
#
# Everything except Sources/App is compiled: App carries the @main entry point, which would collide with
# uisnap's own. Sparkle is linked because TickerPopover takes an Updater.
#
# The file list is an exclusion, not an enumeration, so a new source file or a new layer directory is
# picked up without editing this script — the same reason build_app.sh globs the whole tree.

set -euo pipefail
cd "$(dirname "$0")/.."

./fetch_sparkle.sh

mkdir -p .build
BIN=".build/uisnap"
TARGET="$(uname -m)-apple-macos13.0"

# shellcheck disable=SC2046
swiftc -O -parse-as-library -target "$TARGET" \
    $(find Sources -name '*.swift' ! -path 'Sources/App/*') \
    Tools/uisnap.swift \
    -F "$PWD/Frameworks" -framework Sparkle \
    -Xlinker -rpath -Xlinker "$PWD/Frameworks" \
    -o "$BIN"

"$BIN" "$@"
