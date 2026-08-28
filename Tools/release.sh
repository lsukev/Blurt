#!/bin/bash
#
# Cut a release: build, notarize, staple, sign the appcast, publish.
#
#   make release VERSION=0.4.0
#
# Everything signed here is signed on this machine. The Developer ID lives in the login
# keychain, the notarization credential in a keychain profile, and the Sparkle EdDSA key in
# the keychain too — none of them are in this repo, and moving this to CI would mean putting
# all three into GitHub secrets.
set -euo pipefail

VERSION="${VERSION:?usage: make release VERSION=0.4.0}"
REPO="${REPO:-lsukev/Blurt}"
NOTARY_PROFILE="${NOTARY_PROFILE:-blurt-notary}"
EXEC="${EXEC:-Blurt}"
BUNDLE="${BUNDLE:?BUNDLE not set — run through the Makefile}"
SPARKLE_BIN="${SPARKLE_BIN:?SPARKLE_BIN not set — run through the Makefile}"
DIST="${DIST:-dist}"
APPCAST="docs/appcast.xml"

say() { printf '\n▸ %s\n' "$1"; }

# ── Preflight ────────────────────────────────────────────────────────────────
# Cheap checks first. Discovering a missing credential after a five-minute notarization
# round trip is a bad way to spend an afternoon.
say "preflight"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION must be x.y.z"; exit 1; }
git diff --quiet || { echo "working tree is dirty — commit first"; exit 1; }
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "sparkle tools missing; run 'swift package resolve'"; exit 1; }
"$SPARKLE_BIN/generate_keys" -p >/dev/null 2>&1 || { echo "no Sparkle signing key in the keychain"; exit 1; }
git tag | grep -qx "v$VERSION" && { echo "tag v$VERSION already exists"; exit 1; }

# CFBundleVersion is what Sparkle compares — the marketing string is only displayed. It has
# to increase monotonically or an update looks older than what is installed.
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
NEXT_BUILD=$((CURRENT_BUILD + 1))
say "version $VERSION (build $NEXT_BUILD, was $CURRENT_BUILD)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                        -c "Set :CFBundleVersion $NEXT_BUILD" Resources/Info.plist

# ── Build, notarize, staple ──────────────────────────────────────────────────
say "building release"
make --no-print-directory app CONFIG=release TIMESTAMP=--timestamp

say "notarizing (a few minutes)"
mkdir -p "$DIST"
rm -f "$DIST/$EXEC-submit.zip" "$DIST/$EXEC.zip"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$DIST/$EXEC-submit.zip"
xcrun notarytool submit "$DIST/$EXEC-submit.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$BUNDLE"
rm -f "$DIST/$EXEC-submit.zip"

# The zip is rebuilt from the stapled bundle. Shipping the one that was submitted is the
# mistake that produces a build which notarized fine and is still stopped on arrival.
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$DIST/$EXEC.zip"
spctl -a -vvv -t exec "$BUNDLE" 2>&1 | sed -n '1,2p'

# ── Appcast ──────────────────────────────────────────────────────────────────
# generate_appcast signs each archive with the EdDSA key from the keychain and writes the
# feed. --download-url-prefix points enclosures at the GitHub release that does not exist
# yet; it is created immediately below, so the feed is only ever published alongside it.
say "signing the appcast"
mkdir -p docs
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --link "https://github.com/$REPO" \
  -o "$APPCAST" \
  "$DIST"

grep -q 'sparkle:edSignature' "$APPCAST" || { echo "appcast has no signature — refusing to publish"; exit 1; }

# ── Publish ──────────────────────────────────────────────────────────────────
say "publishing"
git add Resources/Info.plist "$APPCAST"
git commit -m "Release $VERSION" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git tag "v$VERSION"
git push origin HEAD --tags

gh release create "v$VERSION" "$DIST/$EXEC.zip" \
  --repo "$REPO" --target main --title "$EXEC $VERSION" --prerelease \
  --notes "See the commit log for what changed in $VERSION."

say "released v$VERSION"
echo "  feed     $(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Resources/Info.plist)"
echo "  artifact $DIST/$EXEC.zip"
echo
echo "  The appcast is served by GitHub Pages, which can lag a minute behind the push."
echo "  Existing installs pick this up on their next check."
