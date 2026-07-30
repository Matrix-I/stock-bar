#!/bin/bash
# release.sh — cuts a release: drops the -SNAPSHOT suffix, builds, tags, uploads a .dmg to a GitHub
# release, then bumps VERSION to the next -SNAPSHOT so the branch is immediately ready for the next
# feature.
#
#   ./release.sh --dry-run     # build the artifacts and print the plan; touches nothing remote
#   ./release.sh               # the real thing, with a confirmation prompt
#   ./release.sh --next patch  # bump to x.y.(z+1)-SNAPSHOT afterwards instead of x.(y+1).0-SNAPSHOT
#
# The version lives in exactly one line of build_app.sh (VERSION="x.y.z-SNAPSHOT"), which stamps it
# into Info.plist. This script rewrites that line — drop the suffix, release, bump — so the bundle, the
# git tag, the appcast and the GitHub release can't drift apart.

set -euo pipefail
cd "$(dirname "$0")"

APP=StockBar
# The releases live under this account's repo, so a release cut while `gh` is switched to a different
# logged-in account would publish to the wrong place — or fail confusingly. Checked, never switched:
# `gh auth switch` is global state that would affect the user's other shells.
GH_ACCOUNT=Matrix-I
BRANCH=main

BUMP=minor
DRY_RUN=0
ASSUME_YES=0

die() { printf '✗ %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --next)     BUMP="${2:-}"; shift 2 ;;
        --next=*)   BUMP="${1#*=}"; shift ;;
        --dry-run)  DRY_RUN=1; shift ;;
        -y|--yes)   ASSUME_YES=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          die "unknown argument: $1 (try --help)" ;;
    esac
done

# ── Version arithmetic ────────────────────────────────────────────────────────────────────────────
# Read and write the single VERSION="..." line in build_app.sh. The pattern is anchored to the whole
# line, so it cannot match anything else in the script; read_version returning two lines (which would
# mean two assignments) makes the write verification below fail rather than silently picking one.
read_version() { sed -n -E 's|^VERSION="(.*)"$|\1|p' build_app.sh; }
write_version() {
    sed -i '' -E "s|^VERSION=\".*\"\$|VERSION=\"$1\"|" build_app.sh
    [ "$(read_version)" = "$1" ] || die "could not write VERSION=\"$1\" into build_app.sh"
}

SNAPSHOT_VERSION=$(read_version)
[ -n "$SNAPSHOT_VERSION" ] || die "no VERSION=\"...\" line found in build_app.sh."
case "$SNAPSHOT_VERSION" in
    *-SNAPSHOT) ;;
    *) die "build_app.sh says VERSION=\"$SNAPSHOT_VERSION\", which has no -SNAPSHOT suffix. Either a
   release is already in progress or the post-release bump never ran — fix it by hand first." ;;
esac
RELEASE_VERSION=${SNAPSHOT_VERSION%-SNAPSHOT}
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "'$RELEASE_VERSION' is not a three-part semver; refusing to guess what to tag."

IFS=. read -r MAJ MIN PAT <<< "$RELEASE_VERSION"
case "$BUMP" in
    major) NEXT_VERSION="$((MAJ + 1)).0.0" ;;
    minor) NEXT_VERSION="$MAJ.$((MIN + 1)).0" ;;
    patch) NEXT_VERSION="$MAJ.$MIN.$((PAT + 1))" ;;
    *)     die "--next must be major, minor or patch (got '$BUMP')" ;;
esac
TAG="v$RELEASE_VERSION"
DMG="$APP-$RELEASE_VERSION.dmg"

# ── Preflight ─────────────────────────────────────────────────────────────────────────────────────
# All of these are cheap, and every one of them is a mistake that is annoying to undo once a tag or a
# release exists on a public repo.
command -v gh >/dev/null || die "the GitHub CLI (gh) is not installed."

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$CURRENT_BRANCH" = "$BRANCH" ] || die "on branch '$CURRENT_BRANCH'; releases are cut from '$BRANCH'."

[ -z "$(git status --porcelain)" ] \
    || die "the working tree is dirty. Commit or stash first — the release commit must contain only
   the version bump and the appcast entry."

# if/then rather than `check && die`: an AND-list whose left side fails is fine mid-script, but it
# returns non-zero, which under `set -e` would abort the moment one of these is refactored into a
# function or moved to the end of a block. Spelling it out removes the trap.
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    die "tag $TAG already exists locally. Delete it or bump VERSION."
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    die "tag $TAG already exists on origin — $RELEASE_VERSION has been released."
fi

ACTIVE_ACCOUNT=$(gh api user --jq .login 2>/dev/null) \
    || die "gh is not authenticated. Run: gh auth login"
[ "$ACTIVE_ACCOUNT" = "$GH_ACCOUNT" ] \
    || die "gh is active as '$ACTIVE_ACCOUNT' but this repo releases as '$GH_ACCOUNT'.
   Switch with: gh auth switch --user $GH_ACCOUNT"

# A release built from a stale checkout would ship code that isn't what the tag points at.
git fetch --quiet origin "$BRANCH"
BEHIND=$(git rev-list --count "HEAD..origin/$BRANCH")
[ "$BEHIND" -eq 0 ] || die "$BEHIND commit(s) on origin/$BRANCH are not in this checkout. Pull first."

# ── Release notes ─────────────────────────────────────────────────────────────────────────────────
mkdir -p .build
NOTES=".build/release-notes-$TAG.md"
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
RANGE=${PREV_TAG:+$PREV_TAG..}HEAD

# Conventional-commit subjects are grouped; anything else lands under "Other" rather than being
# dropped, because a silently omitted change is worse than an untidy heading.
commits_matching() { git log --no-merges --reverse --pretty='%s' "$RANGE" | grep -E "$1" || true; }
strip_prefix() { sed -E 's/^[a-z]+(\([^)]*\))?!?: */- /'; }

{
    if [ -n "$PREV_TAG" ]; then
        echo "Changes since $PREV_TAG."
    else
        echo "First release."
    fi
    echo

    feats=$(commits_matching '^feat(\(|!?:)' | strip_prefix)
    fixes=$(commits_matching '^fix(\(|!?:)' | strip_prefix)
    # chore: is filtered out here only — the release/bump commits this script makes are noise in notes.
    others=$(git log --no-merges --reverse --pretty='%s' "$RANGE" \
             | { grep -Ev '^(feat|fix|chore)(\(|!?:)' || true; } | sed 's/^/- /')

    if [ -n "$feats" ];  then echo "### Added"; echo; echo "$feats";  echo; fi
    if [ -n "$fixes" ];  then echo "### Fixed"; echo; echo "$fixes";  echo; fi
    if [ -n "$others" ]; then echo "### Other"; echo; echo "$others"; echo; fi

    cat <<'NOTES_TAIL'
### Install

1. Open the `.dmg` and drag **StockBar** into Applications.
2. The app is ad-hoc signed, not notarized, so Gatekeeper will refuse to open it. Clear the
   quarantine flag once:

   ```bash
   xattr -dr com.apple.quarantine /Applications/StockBar.app
   ```

3. Launch it. The ticker appears in the menu bar — there is no Dock icon and no window.

Requires macOS 13 Ventura or later. Building from source needs only the Xcode Command Line Tools.
NOTES_TAIL
} > "$NOTES"

# ── Plan ──────────────────────────────────────────────────────────────────────────────────────────
echo "───────────────────────────────────────────────────────────────────"
printf '  release   %s  →  tag %s\n' "$RELEASE_VERSION" "$TAG"
printf '  artifact  %s\n' "$DMG"
printf '  then bump %s  (--next %s)\n' "$NEXT_VERSION-SNAPSHOT" "$BUMP"
printf '  as        %s → %s\n' "$ACTIVE_ACCOUNT" "$(git remote get-url origin)"
echo "───────────────────────────────────────────────────────────────────"
sed 's/^/  │ /' "$NOTES"
echo "───────────────────────────────────────────────────────────────────"

if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    printf 'Push the tag and publish this release? [y/N] '
    read -r reply < /dev/tty || die "no terminal to confirm on; re-run with --yes if that's intended."
    case "$reply" in
        y|Y|yes|YES) ;;
        *) die "aborted; nothing was changed." ;;
    esac
fi

# ── Build the release artifacts ───────────────────────────────────────────────────────────────────
# The version is rewritten before the build so the bundle carries the released version. If anything
# below fails before the commit, put the snapshot back — a tree left on a bare version is exactly the
# state the preflight above refuses to start from, so a failed release would block the next attempt.
trap 'write_version "$SNAPSHOT_VERSION"' EXIT

write_version "$RELEASE_VERSION"

# Ad-hoc rather than the local self-signed identity: a "StockBar Local" certificate exists only on this
# machine, so signing the distributed app with it buys nothing for anyone downloading it and makes the
# artifact depend on the build machine's keychain.
echo "🔨 Building $APP $RELEASE_VERSION ..."
STOCKBAR_SIGN_IDENTITY="__adhoc__" ./build_app.sh --no-launch

STAMPED=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP.app/Contents/Info.plist")
[ "$STAMPED" = "$RELEASE_VERSION" ] \
    || die "the built bundle reports '$STAMPED', not '$RELEASE_VERSION'."

echo "💿 Building $DMG ..."
# .build/ rather than mktemp -d: same reason Tools/probe.sh uses it, and it is already gitignored.
STAGE=".build/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP.app" "$STAGE/"
# The /Applications symlink is what makes the window a drag-to-install target instead of just a folder
# with an app in it.
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP $RELEASE_VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO -quiet "$DMG"
printf '   %s (%s)\n' "$DMG" "$(du -h "$DMG" | cut -f1)"

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "✅ Dry run. $DMG and $NOTES are on disk; build_app.sh is back to $SNAPSHOT_VERSION."
    echo "   Nothing was committed, tagged, signed or pushed."
    exit 0
fi

# ── Commit, tag, publish ──────────────────────────────────────────────────────────────────────────
trap - EXIT   # from here the released version in build_app.sh is intentional and about to be committed

git add build_app.sh
git commit --quiet -m "chore(release): $RELEASE_VERSION"
git tag -a "$TAG" -m "$APP $RELEASE_VERSION"

echo "⬆️  Pushing $BRANCH and $TAG ..."
git push --quiet origin "$BRANCH"
git push --quiet origin "$TAG"

echo "🚀 Creating the GitHub release ..."
# --verify-tag makes gh use the tag we just pushed rather than silently creating its own from HEAD.
#
# The title is the tag and nothing else. "StockBar 1.0.0" repeats the repository's own name on every entry
# in a list that is already all StockBar, and the version is then spelled twice per row — once in the
# heading and once in the tag beside it.
gh release create "$TAG" "$DMG" \
    --title "$TAG" \
    --notes-file "$NOTES" \
    --verify-tag

# ── Publish to the Sparkle feed ───────────────────────────────────────────────────────────────────
# Deliberately after the release exists: the appcast's enclosure URL points at the uploaded asset, so
# signing and inserting it earlier would publish a feed entry that 404s for every installed copy.
echo "📡 Adding $TAG to the appcast ..."
if ./update_appcast.sh "$RELEASE_VERSION" "$DMG" "$NOTES"; then
    git add appcast.xml
    git commit --quiet -m "chore(release): add $TAG to the appcast"
else
    # The release itself is already published and is fine — only the feed is missing, and it can be
    # added by hand. Say so loudly rather than exiting silently, because until this lands no installed
    # copy will ever see the update.
    echo "⚠️  update_appcast.sh failed — $TAG is published but NOT in the feed."
    echo "   Fix it with: ./update_appcast.sh $RELEASE_VERSION $DMG $NOTES && git add appcast.xml"
    echo "   (a denied keychain prompt for the EdDSA signing key is the usual cause)"
fi

# ── Prepare the next development cycle ────────────────────────────────────────────────────────────
write_version "$NEXT_VERSION-SNAPSHOT"
git add build_app.sh
git commit --quiet -m "chore: prepare $NEXT_VERSION-SNAPSHOT"
git push --quiet origin "$BRANCH"

echo ""
echo "✅ Released $TAG · now on $NEXT_VERSION-SNAPSHOT"
gh release view "$TAG" --json url --jq .url
