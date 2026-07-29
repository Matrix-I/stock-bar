#!/bin/bash
# probe.sh — compiles Tools/probe.swift against the app's own data layer and runs it, so a fetch or
# formatting problem can be seen as text instead of being guessed at from a menu-bar glyph.
#
# Three directories are excluded and everything else is compiled, so a new source file or layer is picked
# up without editing this script:
#
#   Sources/App          — carries the @main entry point, which would collide with the probe's own.
#   Sources/Update       — `import Sparkle`, and the probe has nothing to do with updating; linking the
#                          framework here would make a data-layer check fail whenever Frameworks/ hasn't
#                          been fetched.
#   Sources/View/Panel   — the SwiftUI popover, which takes an Updater and so pulls Sparkle back in.
#
# Sources/View/MenuBar and Sources/View/Design stay in on purpose: the probe renders the real status-bar
# image, and that needs the glyph plus the band colours.
#
# Set GLYPH_OUT to a path to also write the rendered menu-bar label as a PNG:
#   GLYPH_OUT=/tmp/glyph.png ./Tools/probe.sh

set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build
BIN=".build/probe"
TARGET="$(uname -m)-apple-macos13.0"

# shellcheck disable=SC2046
swiftc -O -parse-as-library -target "$TARGET" \
    $(find Sources -name '*.swift' \
        ! -path 'Sources/App/*' ! -path 'Sources/Update/*' ! -path 'Sources/View/Panel/*') \
    Tools/probe.swift \
    -o "$BIN"

"$BIN" "$@"
