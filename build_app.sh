#!/bin/bash
# build_app.sh — compiles the Sources/ tree and packages it into StockBar.app
# Requires: Xcode Command Line Tools only (xcode-select --install). Full Xcode is NOT needed —
# swiftc against the CLT SDK builds a SwiftUI/AppKit menu-bar app fine, and the bundle below is
# assembled by hand.

set -euo pipefail
cd "$(dirname "$0")"

APP=StockBar

# The single source of truth for the version — release.sh rewrites this file and nothing else, so the
# bundle can never disagree with the git tag. During development it carries a -SNAPSHOT suffix, which
# is dropped for the release commit and restored (at the next version) immediately after.
VERSION=$(tr -d '[:space:]' < VERSION)
# CFBundleVersion must be purely numeric-and-dots — LaunchServices and SMAppService compare it as a
# version, and "-SNAPSHOT" makes that comparison undefined. So the suffix lives only in
# CFBundleShortVersionString, which is free-form and is what the user actually sees.
BUNDLE_VERSION=${VERSION%%-*}

# By default, relaunch the app once it's built so "build finished" actually means "the new version is
# running". Pass --no-launch to only produce the bundle.
RELAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --no-launch) RELAUNCH=0 ;;
    esac
done

echo "🔨 Compiling $APP $VERSION (Sources/*.swift) ..."
SOURCES=$(find Sources -name '*.swift')
# -target pins the deployment target. WITHOUT it swiftc defaults to the build machine's OS, which
# (a) produces a binary that won't load on anything older, contradicting the LSMinimumSystemVersion
# declared below, and (b) silently disables availability checking — a macOS 14+ API then compiles
# without a warning and crashes at runtime. Keep this in step with LSMinimumSystemVersion. The arch
# comes from uname so building on an Intel Mac still produces a native x86_64 binary rather than
# cross-compiling to arm64.
TARGET="$(uname -m)-apple-macos13.0"
# -parse-as-library is required for @main to be honoured in a multi-file module (without it swiftc
# looks for top-level statements and rejects the @main attribute).
# shellcheck disable=SC2086
swiftc -O -parse-as-library -target "$TARGET" $SOURCES -o "$APP"

echo "📦 Building the app bundle ..."
rm -rf "$APP.app"
mkdir -p "$APP.app/Contents/MacOS" "$APP.app/Contents/Resources"
mv "$APP" "$APP.app/Contents/MacOS/$APP"

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP.app/Contents/Resources/AppIcon.icns"
fi

cat > "$APP.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>       <string>StockBar</string>
    <key>CFBundleIdentifier</key>       <string>local.stockbar</string>
    <key>CFBundleName</key>             <string>StockBar</string>
    <key>CFBundleIconFile</key>         <string>AppIcon</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>          <string>$BUNDLE_VERSION</string>
    <key>LSMinimumSystemVersion</key>   <string>13.0</string>
    <!-- Menu-bar-only app: no Dock icon, no app menu. -->
    <key>LSUIElement</key>              <true/>
    <key>NSHighResolutionCapable</key>  <true/>
</dict>
</plist>
PLIST

# Code signing.
#
# An *ad-hoc* signature's designated requirement is the binary's cdhash, which changes on every
# build. macOS keys some per-app state (and, for apps that use them, TCC permissions) to that
# requirement, so an ad-hoc-signed app looks brand new after each rebuild. StockBar needs no TCC
# permissions — it only makes outbound HTTPS requests — so ad-hoc is genuinely fine here. Signing
# with a stable self-signed identity is still nicer: SMAppService's login-item registration is keyed
# to the bundle, and a stable identity keeps "Launch at login" from being re-asked after a rebuild.
#
# To create one: Keychain Access ▸ Certificate Assistant ▸ Create a Certificate… → Name
# "StockBar Local", Identity Type "Self Signed Root", Certificate Type "Code Signing". Then either
# `export STOCKBAR_SIGN_IDENTITY="StockBar Local"` or just name it that (the default below).
#
# NOTE: we look the identity up WITHOUT `find-identity -v`. A self-signed cert isn't trusted as a
# root, so the `-v` (valid) filter hides it — but codesign signs with it fine anyway (signing needs
# the private key, not a trusted chain). Requiring `-v` would needlessly fall back to ad-hoc for
# exactly the self-signed local cert this is meant to use.
SIGN_IDENTITY="${STOCKBAR_SIGN_IDENTITY:-StockBar Local}"
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$SIGN_IDENTITY\""; then
    echo "🔏 Signing with stable identity: $SIGN_IDENTITY"
    codesign --force -s "$SIGN_IDENTITY" "$APP.app"
else
    echo "🔏 No stable signing identity ('$SIGN_IDENTITY') — ad-hoc signing."
    codesign --force -s - "$APP.app" 2>/dev/null || true
fi

# Force LaunchServices to re-register this exact bundle and drop any cached icon render, so a freshly
# built AppIcon appears immediately instead of a stale/generic placeholder. lsregister is the private
# LaunchServices support tool; touch bumps mtime so IconServices re-rasterizes. Best-effort — never
# fail the build over it.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$PWD/$APP.app" 2>/dev/null || true
touch "$APP.app"

echo ""
echo "✅ Done: $APP.app ($VERSION)"

if [ "$RELAUNCH" -eq 1 ]; then
    echo "🔄 Relaunching $APP ..."
    # Quit any running copy first — a menu-bar (LSUIElement) app has no window for `open` to
    # activate, so without this it would just no-op against the old instance and the new build would
    # never come up.
    pkill -x "$APP" 2>/dev/null || true
    # LaunchServices can briefly return -600 (procNotFound) right after the old instance dies, so a
    # single `open` here fails and the app looks like it "won't start". Retry until it takes.
    launched=0
    for _ in 1 2 3 4 5; do
        sleep 0.6
        if open "$APP.app" 2>/dev/null; then launched=1; break; fi
    done
    if [ "$launched" -eq 1 ]; then
        echo "✅ $APP is running — look for the ticker in the menu bar."
    else
        echo "⚠️  Auto-launch didn't take — run it manually: open $APP.app"
    fi
else
    echo "   Run it         : open $APP.app"
    echo "   Launch at login: toggle it in StockBar's own settings, or System Settings → General → Login Items"
fi
