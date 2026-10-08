#!/usr/bin/env bash
# Publishes a new version of Stash for Mac. Installed copies pick it up
# through Sparkle within a day, or right away from Stash › Check for Updates….
#
#   scripts/release-mac.sh 0.2.0 [release-notes.md]
#   DRY_RUN=1 scripts/release-mac.sh 0.2.0     # build and sign only, publish nothing
#
# Steps:
#   1. Sets the version and build number in the Xcode project.
#   2. Builds the app in Release and zips it.
#   3. Signs the zip with the Sparkle key in your login Keychain (account "stash").
#   4. Commits the version bump, tags it mac-v<version> and pushes.
#   5. Uploads the zip as the GitHub release for that tag.
#   6. Adds the release to appcast.xml (the feed installed apps check) and pushes.
#
# Needs Xcode, gh (logged in), a clean working tree, and main level with origin/main.
set -euo pipefail

VERSION="${1:?usage: scripts/release-mac.sh <version> [release-notes.md]}"
NOTES_FILE="${2:-}"
DRY_RUN="${DRY_RUN:-}"

REPO="0xLou1s/stash"
TAG="mac-v$VERSION"
KEY_ACCOUNT="stash"
MINIMUM_MACOS="15.0" # Keep in sync with MACOSX_DEPLOYMENT_TARGET.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/macos/Stash.xcodeproj"
FEED="$ROOT/appcast.xml"
PACKAGES="$ROOT/macos/.build/SourcePackages"
WORK="$(mktemp -d)"

fail() {
  echo "$1" >&2
  exit 1
}

# Until the version bump is committed, any exit (dry run, failed build, Ctrl-C)
# puts the project file back the way it was.
COMMITTED=""
cp "$PROJECT/project.pbxproj" "$WORK/project.pbxproj.orig"
trap '[[ -z "$COMMITTED" ]] && cp "$WORK/project.pbxproj.orig" "$PROJECT/project.pbxproj"; rm -rf "$WORK"' EXIT

if [[ -z "$DRY_RUN" ]]; then
  [[ -z "$(git -C "$ROOT" status --porcelain)" ]] ||
    fail "Commit or stash your changes first; the release commit should only bump the version."
  [[ "$(git -C "$ROOT" branch --show-current)" == "main" ]] ||
    fail "Release from main: installed apps read the update feed from main."
  git -C "$ROOT" fetch -q origin main
  [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(git -C "$ROOT" rev-parse origin/main)" ]] ||
    fail "main isn't level with origin/main. Pull or push first."
  ! git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null ||
    fail "$TAG already exists."
fi

NOTES="Stash $VERSION"
if [[ -n "$NOTES_FILE" ]]; then
  NOTES="$(cat "$NOTES_FILE")"
fi
# The notes go inside a CDATA section in the feed; this would end it early.
[[ "$NOTES" != *"]]>"* ]] || fail "Release notes can't contain ']]>'."

# Sparkle decides what's newer by the build number, so it must always go up.
# Take it from the feed itself: one more than the highest build ever published.
LAST_BUILD="$(grep -o '<sparkle:version>[0-9]*' "$FEED" | grep -o '[0-9]*$' | sort -n | tail -1 || true)"
BUILD="$(( ${LAST_BUILD:-0} + 1 ))"
echo "→ Stash $VERSION (build $BUILD)"

sed -i '' -E \
  -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/" \
  -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD;/" \
  "$PROJECT/project.pbxproj"

echo "→ Building"
xcodebuild -project "$PROJECT" -target Stash -configuration Release \
  -clonedSourcePackagesDirPath "$PACKAGES" \
  SYMROOT="$WORK/build" build -quiet
APP="$WORK/build/Release/Stash.app"
ZIP="$WORK/Stash-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "→ Signing"
# Prints: sparkle:edSignature="…" length="…"
SIGNATURE="$("$PACKAGES/artifacts/sparkle/Sparkle/bin/sign_update" --account "$KEY_ACCOUNT" "$ZIP")"

FEED_ITEM="$(python3 - "$VERSION" "$BUILD" "$SIGNATURE" "$NOTES" "$REPO" "$TAG" "$MINIMUM_MACOS" <<'PY'
import email.utils, sys
version, build, signature, notes, repo, tag, minimum = sys.argv[1:]
url = f"https://github.com/{repo}/releases/download/{tag}/Stash-{version}.zip"
print(f"""    <item>
      <title>Version {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[{notes}]]></description>
      <enclosure url="{url}" type="application/octet-stream" {signature} />
    </item>""")
PY
)"

if [[ -n "$DRY_RUN" ]]; then
  echo "→ Dry run: built and signed $(du -h "$ZIP" | cut -f1 | xargs) zip. Feed entry would be:"
  echo "$FEED_ITEM"
  exit 0
fi

echo "→ Tagging $TAG"
git -C "$ROOT" commit -q -m "Release Stash for Mac $VERSION" -- "$PROJECT/project.pbxproj"
COMMITTED=1
git -C "$ROOT" tag "$TAG"
# Branch and tag land together or not at all. The tag is pushed by name:
# --follow-tags skips lightweight tags like this one.
git -C "$ROOT" push -q --atomic origin main "refs/tags/$TAG"

echo "→ Uploading"
gh release create "$TAG" "$ZIP" --repo "$REPO" --verify-tag --title "Stash for Mac $VERSION" --notes "$NOTES"

# Only now, with the zip online, does the feed point at it.
echo "→ Updating the feed"
python3 - "$FEED" "$FEED_ITEM" <<'PY'
import sys
path, item = sys.argv[1:]
xml = open(path).read()
# Newest first: before the first existing item, or at the end of the channel.
anchor = "    <item>" if "    <item>" in xml else "  </channel>"
open(path, "w").write(xml.replace(anchor, item + "\n" + anchor, 1))
PY
git -C "$ROOT" commit -q -m "Add Stash for Mac $VERSION to the update feed" -- "$FEED"
git -C "$ROOT" push -q origin main

echo "✓ Stash $VERSION is out: https://github.com/$REPO/releases/tag/$TAG"
