#!/bin/bash
#
# Build, sign, notarize and package FANcy into a distributable DMG.
#
# One-time setup (creates the notary credentials this script needs):
#   1. Create an app-specific password at https://appleid.apple.com → Sign-In & Security
#   2. Store it once:
#        xcrun notarytool store-credentials fancy-notary \
#          --apple-id "<your-apple-id-email>" \
#          --team-id 7YN7YUH475 \
#          --password "<app-specific-password>"
#
# Then just run:  ./native/package.sh
#
# Overridable via env: FANCY_SIGN_ID, FANCY_NOTARY_PROFILE, FANCY_VERSION, SKIP_NOTARIZE=1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP="$BUILD_DIR/FANcy.app"

IDENTITY="${FANCY_SIGN_ID:-Developer ID Application: Marco Scheffler (7YN7YUH475)}"
NOTARY_PROFILE="${FANCY_NOTARY_PROFILE:-fancy-notary}"
VERSION="${FANCY_VERSION:-1.2.0}"
DMG="$BUILD_DIR/FANcy-$VERSION.dmg"

echo "▸ Building app…"
bash "$SCRIPT_DIR/build.sh" >/dev/null

# ── Sign: nested code first (helper), then the app bundle ──
# Hardened Runtime (--options runtime) + secure timestamp are required for notarization.
echo "▸ Signing with: $IDENTITY"
codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$APP/Contents/MacOS/FANcyHelper"
codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$APP"

echo "▸ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
    echo "▸ SKIP_NOTARIZE=1 → skipping notarization (app is signed but will still hit Gatekeeper on download)"
else
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "✖ Notary profile '$NOTARY_PROFILE' not found. Run the store-credentials step in this script's header first," >&2
        echo "  or re-run with SKIP_NOTARIZE=1 to only sign + package." >&2
        exit 1
    fi
    echo "▸ Notarizing app (this can take a few minutes)…"
    ZIP="$BUILD_DIR/FANcy.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$ZIP"
    echo "▸ Stapling ticket to app…"
    xcrun stapler staple "$APP"
fi

# ── Build DMG with a drag-to-Applications target ──
echo "▸ Building DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "FANcy $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
    echo "▸ Signing, notarizing and stapling the DMG…"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "▸ Gatekeeper assessment:"
    spctl -a -t open --context context:primary-signature -vv "$DMG" || true
fi

echo ""
echo "✅ Done: $DMG"
