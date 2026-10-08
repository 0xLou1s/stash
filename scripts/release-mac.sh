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
#   4. Uploads the zip as release v<version> of 0xLou1s/stash-releases (public).
#   5. Adds the release to appcast.xml in that repo: the feed installed apps check.
#   6. Commits the version bump here, tags it mac-v<version>, and pushes.
#
# Needs Xcode, gh (logged in) and a clean working tree.
set -euo pipefail

VERSION="${1:?usage: scripts/release-mac.sh <version> [release-notes.md]}"
NOTES_FILE="${2:-}"
DRY_RUN="${DRY_RUN:-}"

RELEASES_REPO="0xLou1s/stash-releases"
KEY_ACCOUNT="stash"
MINIMUM_MACOS="15.0" # Keep in sync with MACOSX_DEPLOYMENT_TARGET.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/macos/Stash.xcodeproj"
PACKAGES="$ROOT/macos/.build/SourcePackages"
WORK="$(mktemp -d)"

if [[ -n "$DRY_RUN" ]]; then
  # Leave the project exactly as it was.
  cp "$PROJECT/project.pbxproj" "$WORK/project.pbxproj.orig"
  trap 'cp "$WORK/project.pbxproj.orig" "$PROJECT/project.pbxproj"; rm -rf "$WORK"' EXIT
else
  trap 'rm -rf "$WORK"' EXIT
  if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "Commit or stash your changes first; the release commit should only bump the version." >&2
    exit 1
  fi
  if gh release view "v$VERSION" --repo "$RELEASES_REPO" >/dev/null 2>&1; then
    echo "v$VERSION is already released." >&2
    exit 1
  fi
fi

NOTES="Stash $VERSION"
if [[ -n "$NOTES_FILE" ]]; then
  NOTES="$(cat "$NOTES_FILE")"
fi

# Sparkle decides what's newer by the build number, so it has to keep going up.
# The commit count (plus this release's own commit) does.
BUILD="$(( $(git -C "$ROOT" rev-list --count HEAD) + 1 ))"
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

FEED_ITEM="$(python3 - "$VERSION" "$BUILD" "$SIGNATURE" "$NOTES" "$RELEASES_REPO" "$MINIMUM_MACOS" <<'PY'
import email.utils, sys
version, build, signature, notes, repo, minimum = sys.argv[1:]
url = f"https://github.com/{repo}/releases/download/v{version}/Stash-{version}.zip"
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

echo "→ Uploading to $RELEASES_REPO"
gh release create "v$VERSION" "$ZIP" --repo "$RELEASES_REPO" --title "Stash $VERSION" --notes "$NOTES"

echo "→ Updating the feed"
gh repo clone "$RELEASES_REPO" "$WORK/releases" -- --quiet --depth 1
python3 - "$WORK/releases/appcast.xml" "$FEED_ITEM" <<'PY'
import sys
path, item = sys.argv[1:]
xml = open(path).read()
# Newest first: before the first existing item, or at the end of the channel.
anchor = "    <item>" if "    <item>" in xml else "  </channel>"
open(path, "w").write(xml.replace(anchor, item + "\n" + anchor, 1))
PY
git -C "$WORK/releases" commit -q -am "Stash $VERSION"
git -C "$WORK/releases" push -q

echo "→ Tagging mac-v$VERSION"
git -C "$ROOT" commit -q -m "Release Stash for Mac $VERSION" -- "$PROJECT/project.pbxproj"
git -C "$ROOT" tag "mac-v$VERSION"
git -C "$ROOT" push -q --follow-tags

echo "✓ Stash $VERSION is out: https://github.com/$RELEASES_REPO/releases/tag/v$VERSION"
