#!/bin/bash
# Fork only: builds a release and publishes it as a GitHub Release on the
# fork, where the fork's updater looks (Sources/Search/Fork.swift).
#
#   ./release.sh          signed with your Developer ID, not notarised:
#                         the updater takes it on any Mac already running the
#                         fork; a fresh DMG install needs right-click › Open
#   ./release.sh ship     + notarised and stapled (needs a notarytool profile:
#                         xcrun notarytool store-credentials "search")
#
# Apple Silicon only. Replaces upstream's publish.sh, which copies into
# Office Commun's website and checks for their team.
set -euo pipefail

cd "$(dirname "$0")"
STEP="${1:-dmg}"
case "$STEP" in dmg|ship) ;; *) echo "usage: ./release.sh [ship]" >&2; exit 1 ;; esac

REPO="adamodeven/Search"
TEAM="$(sed -n 's/.*static let team = "\([A-Z0-9]*\)".*/\1/p' Sources/Search/Fork.swift)"
[ -n "$TEAM" ] || { echo "couldn't read the team from Sources/Search/Fork.swift" >&2; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "release from an Apple Silicon Mac" >&2; exit 1; }

# A release is made from a commit GitHub has, so the tag points at the code.
[ -z "$(git status --porcelain)" ] || { echo "commit your changes first" >&2; exit 1; }
git fetch -q origin
COMMIT="$(git rev-parse HEAD)"
git branch -r --contains "$COMMIT" | grep -q "origin/" \
  || { echo "push $(git rev-parse --abbrev-ref HEAD) to origin first" >&2; exit 1; }

# The developer ID identity for this team, so build.sh signs with it and not
# some other one that happens to be first in the keychain.
IDENTITY="$(security find-identity -v -p codesigning \
  | grep -o "\"Developer ID Application: [^\"]*($TEAM)\"" | head -1 | tr -d '"' || true)"
[ -n "$IDENTITY" ] || { echo "no Developer ID Application certificate for team $TEAM in the keychain" >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION-$(date +%Y%m%d%H%M)"
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && { echo "$TAG already exists" >&2; exit 1; }

SEARCH_SIGN_IDENTITY="$IDENTITY" \
SEARCH_DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG" \
SEARCH_ALLOW_NO_PASSKEYS=1 \
SEARCH_ARCH=arm64 \
  ./build.sh release "$STEP"

FILES=(build/Search.dmg build/Search.zip build/appcast.json build/appcast.json.zip)
for FILE in "${FILES[@]}"; do [ -f "$FILE" ] || { echo "$FILE is missing" >&2; exit 1; }; done

# The same checks publish.sh makes, for this team: a feed that doesn't
# verify would silently stop every update.
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
ditto -x -k build/appcast.json.zip "$CHECK/feed"
codesign --verify -R="anchor apple generic and identifier \"com.officecommun.search.appcast\" and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"$TEAM\"" "$CHECK/feed/appcast.json" \
  || { echo "the signed appcast doesn't verify for team $TEAM — not publishing" >&2; exit 1; }
cmp -s "$CHECK/feed/appcast.json" build/appcast.json || { echo "signed appcast differs from build/appcast.json" >&2; exit 1; }
ditto -x -k build/Search.zip "$CHECK/app"
codesign --verify --strict --deep "$CHECK/app/Search.app"
[ "$(lipo -archs "$CHECK/app/Search.app/Contents/MacOS/Search")" = "arm64" ] || { echo "Search.zip isn't an arm64 app" >&2; exit 1; }

NOTES="$(awk 'NF { printf "%s%s", (n++ ? " " : ""), $0; next } n { exit }' NOTES.md 2>/dev/null || true)"
gh release create "$TAG" "${FILES[@]}" --repo "$REPO" --target "$COMMIT" \
  --title "Search $VERSION ($TAG)" --notes "${NOTES:-Search $VERSION}" --latest
echo "released: https://github.com/$REPO/releases/tag/$TAG"
