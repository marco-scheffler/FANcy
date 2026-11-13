#!/bin/bash
#
# Fetch the pinned Sparkle release into native/vendor/Sparkle (gitignored).
#
# Pinned to an exact version and SHA256, so a moved or compromised tag can't
# flow straight into a signed, notarized FANcy. Bump both values deliberately
# when a new Sparkle ships (the digest is on the release's asset page).
set -euo pipefail

SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$SCRIPT_DIR/vendor/Sparkle"
STAMP="$VENDOR/.version"

if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$SPARKLE_VERSION" ]]; then
    exit 0
fi

echo "▸ Fetching Sparkle $SPARKLE_VERSION…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
echo "$SPARKLE_SHA256  $TMP/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null

rm -rf "$VENDOR"
mkdir -p "$VENDOR"
tar -xJf "$TMP/sparkle.tar.xz" -C "$VENDOR"
echo "$SPARKLE_VERSION" > "$STAMP"
echo "  ✅ Sparkle $SPARKLE_VERSION → native/vendor/Sparkle"
