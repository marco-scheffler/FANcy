#!/bin/bash
#
# Build, sign, notarize and package FANcy into a distributable DMG — and, for a
# real release, sign that DMG for Sparkle and add it to appcast.xml.
#
# One-time setup:
#   1. Notary credentials (app-specific password from appleid.apple.com):
#        xcrun notarytool store-credentials fancy-notary \
#          --apple-id "<your-apple-id-email>" --team-id 7YN7YUH475 \
#          --password "<app-specific-password>"
#   2. The Sparkle signing key lives in the Keychain under account "fancy".
#      On a new Mac, restore it from the backup first:
#        native/vendor/Sparkle/bin/generate_keys --account fancy -f <backup-file>
#
# Then:  ./native/package.sh
#
# Version and build number come from native/Resources/Info.plist.
# Overridable via env: FANCY_SIGN_ID, FANCY_NOTARY_PROFILE, SKIP_NOTARIZE=1
# (SKIP_NOTARIZE=1 only signs + packages: no notarization, no appcast entry.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP="$BUILD_DIR/FANcy.app"
PLIST="$SCRIPT_DIR/Resources/Info.plist"
APPCAST="$REPO/appcast.xml"
SPARKLE_BIN="$SCRIPT_DIR/vendor/Sparkle/bin"
SPARKLE_ACCOUNT="fancy"

IDENTITY="${FANCY_SIGN_ID:-Developer ID Application: Marco Scheffler (7YN7YUH475)}"
NOTARY_PROFILE="${FANCY_NOTARY_PROFILE:-fancy-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
DMG="$BUILD_DIR/FANcy-$VERSION.dmg"
NOTES="$REPO/docs/release-notes/$VERSION.html"
RELEASE=1
[[ "${SKIP_NOTARIZE:-0}" == "1" ]] && RELEASE=0

bash "$SCRIPT_DIR/fetch-sparkle.sh"

# ── Pre-flight: fail in seconds, not after minutes of building/notarizing ──
if [[ $RELEASE == 1 ]]; then
    echo "▸ Pre-flight checks…"
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "✖ Notary profile '$NOTARY_PROFILE' isn't usable — missing, or Apple wants an" >&2
        echo "  updated agreement accepted. See this script's header, or re-run with" >&2
        echo "  SKIP_NOTARIZE=1 to only sign + package." >&2
        exit 1
    fi

    # The key that signs must be the key the app trusts — otherwise every
    # user's update check fails, and it looks like a server problem.
    KEY_IN_KEYCHAIN="$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null || true)"
    KEY_IN_APP="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")"
    if [[ -z "$KEY_IN_KEYCHAIN" ]]; then
        echo "✖ No Sparkle signing key in the Keychain (account '$SPARKLE_ACCOUNT')." >&2
        echo "  Restore it: $SPARKLE_BIN/generate_keys --account $SPARKLE_ACCOUNT -f <backup-file>" >&2
        exit 1
    fi
    if [[ "$KEY_IN_KEYCHAIN" != "$KEY_IN_APP" ]]; then
        echo "✖ SUPublicEDKey in Info.plist isn't the key this Mac signs with." >&2
        echo "  Keychain: $KEY_IN_KEYCHAIN" >&2
        echo "  App:      $KEY_IN_APP" >&2
        exit 1
    fi

    # Sparkle compares CFBundleVersion, not the version humans read. If it
    # doesn't go up, the release ships fine and nobody is ever offered it.
    NEWEST_IN_FEED="$(python3 - "$APPCAST" <<'PY'
import os, sys, xml.etree.ElementTree as ET
path = sys.argv[1]
if not os.path.exists(path):
    print(0)
    raise SystemExit
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
builds = [int(e.text) for e in ET.parse(path).getroot().iterfind(".//sparkle:version", ns)
          if e.text and e.text.strip().isdigit()]
print(max(builds, default=0))
PY
)"
    if (( BUILD_NUMBER <= NEWEST_IN_FEED )); then
        echo "✖ CFBundleVersion is $BUILD_NUMBER, the appcast already has $NEWEST_IN_FEED." >&2
        echo "  Bump it in native/Resources/Info.plist — Sparkle would offer this to nobody." >&2
        exit 1
    fi

    [[ -f "$NOTES" ]] || echo "  ⚠️  $NOTES missing — the update window would show the GitHub page instead." >&2
    echo "  ✅ $VERSION (build $BUILD_NUMBER) · feed has build $NEWEST_IN_FEED · signing key matches"
fi

echo "▸ Building app…"
bash "$SCRIPT_DIR/build.sh" >/dev/null

# ── Sign inside-out: Sparkle's nested code, the helper, then the app ──
# Hardened Runtime + secure timestamp on every piece, or notarization refuses.
# Order and Downloader's preserved entitlements follow Sparkle's code-signing docs.
echo "▸ Signing with: $IDENTITY"
SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
SPK="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPK/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPK/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPK/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPK/Versions/B/Updater.app"
"${SIGN[@]}" "$SPK"
"${SIGN[@]}" "$APP/Contents/MacOS/FANcyHelper"
"${SIGN[@]}" "$APP"

echo "▸ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ $RELEASE == 1 ]]; then
    echo "▸ Notarizing app (this can take a few minutes)…"
    ZIP="$BUILD_DIR/FANcy.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$ZIP"
    echo "▸ Stapling ticket to app…"
    xcrun stapler staple "$APP"
else
    echo "▸ SKIP_NOTARIZE=1 → skipping notarization (signed, but Gatekeeper will object on download)"
fi

# ── Build DMG with a drag-to-Applications target ──
echo "▸ Building DMG…"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "FANcy $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ $RELEASE == 1 ]]; then
    echo "▸ Signing, notarizing and stapling the DMG…"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "▸ Gatekeeper assessment:"
    spctl -a -t open --context context:primary-signature -vv "$DMG" || true

    # Sign exactly the file that gets uploaded — after stapling, because
    # stapling changes the DMG and Sparkle rejects anything that differs.
    echo "▸ Signing the DMG for Sparkle…"
    SIGNATURE="$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" -p "$DMG")"
    "$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$DMG" "$SIGNATURE" >/dev/null
    LENGTH="$(stat -f%z "$DMG")"

    NOTES_ARG=()
    [[ -f "$NOTES" ]] && NOTES_ARG=(--notes-file "$NOTES")
    python3 "$SCRIPT_DIR/appcast.py" --appcast "$APPCAST" \
        --version "$VERSION" --build "$BUILD_NUMBER" \
        --signature "$SIGNATURE" --length "$LENGTH" \
        --tag "v$VERSION" --dmg-name "$(basename "$DMG")" \
        ${NOTES_ARG[@]+"${NOTES_ARG[@]}"}
fi

echo ""
echo "✅ Done: $DMG"
if [[ $RELEASE == 1 ]]; then
    echo ""
    echo "To ship it, in this order:"
    echo "  1. Create release v$VERSION and attach $(basename "$DMG") — the appcast already points there."
    echo "  2. Commit appcast.xml and push to main — only then do installed copies learn about $VERSION."
fi
