#!/bin/bash
# probe.sh — compiles Tools/probe.swift against the app's own data layer and runs it, so a fetch or
# formatting problem can be seen as text instead of being guessed at from a menu-bar glyph.
#
# Only the layers the probe needs are compiled: Model, Support, Reader, plus View/MenuBarGlyph.swift so
# the real status-bar image can be rendered. Sources/App and the rest of Sources/View are excluded —
# App carries the @main entry point, which would collide with the probe's own.
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
    $(find Sources/Model Sources/Support Sources/Reader -name '*.swift') \
    Sources/View/MenuBarGlyph.swift \
    Tools/probe.swift \
    -o "$BIN"

"$BIN" "$@"
