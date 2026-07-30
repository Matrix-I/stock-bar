#!/bin/bash
# makeicon.sh — regenerates AppIcon.icns from Tools/makeicon.swift and the app's own BrandMark.
#
#   ./Tools/makeicon.sh                 # writes AppIcon.icns in the repo root
#   ./Tools/makeicon.sh /tmp/Alt.icns   # writes it somewhere else, to compare before replacing
#
# Only BrandMark is compiled in, not the whole tree: the mark is deliberately free of Theme and of the
# panel's types precisely so this stays a two-file build with no Sparkle and no app entry point.
#
# The .icns it produces IS committed. build_app.sh copies whatever is in the repo root and does not run
# this, so a fresh clone can build the signed app with nothing but the Command Line Tools — regenerating
# the artwork is a deliberate act, not a build step.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-AppIcon.icns}"
ICONSET=".build/AppIcon.iconset"

mkdir -p .build
rm -rf "$ICONSET"

swiftc -O -target "$(uname -m)-apple-macos13.0" \
    Tools/makeicon.swift Sources/View/Design/BrandMark.swift \
    -o .build/makeicon

echo "🎨 Rendering each tier at its own pixel size ..."
.build/makeicon "$ICONSET"

# iconutil ships with the Command Line Tools. It validates the tier names and sizes, so a wrong name in
# makeicon.swift fails here rather than producing an .icns macOS silently ignores.
iconutil -c icns "$ICONSET" -o "$OUT"

echo ""
echo "✅ $OUT ($(du -h "$OUT" | cut -f1))"
echo "   Rebuild the app to pick it up: ./build_app.sh"
