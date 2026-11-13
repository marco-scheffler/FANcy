#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/FANcy.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
SPARKLE_DIR="$SCRIPT_DIR/vendor/Sparkle"

echo "🔨 Building FANcy..."

# Sparkle (auto-update) — pinned release, fetched once into native/vendor
bash "$SCRIPT_DIR/fetch-sparkle.sh"

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

# Copy Info.plist
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS/"

# ── 1. Compile main app ──

swiftc -O \
    -target arm64-apple-macos13.0 \
    -sdk $(xcrun --show-sdk-path) \
    -import-objc-header "$SCRIPT_DIR/SMCBridge.h" \
    "$SCRIPT_DIR/SMCBridge.c" \
    "$SCRIPT_DIR"/Core/*.swift \
    "$SCRIPT_DIR"/Sources/*.swift \
    -F "$SPARKLE_DIR" \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -framework IOKit \
    -framework CoreFoundation \
    -o "$MACOS/FANcy"

# ditto keeps the framework's internal symlinks intact (cp -R would not)
ditto "$SPARKLE_DIR/Sparkle.framework" "$FRAMEWORKS/Sparkle.framework"

echo "  ✅ FANcy app compiled (Sparkle embedded)"

# ── 2. Compile privileged helper ──

cc -O2 \
    -target arm64-apple-macos13.0 \
    -o "$MACOS/FANcyHelper" \
    "$SCRIPT_DIR/helper_main.c" \
    "$SCRIPT_DIR/SMCBridge.c" \
    -framework IOKit \
    -framework CoreFoundation

echo "  ✅ FANcy Helper compiled"

# ── 2b. Bundle the LaunchDaemon plist for SMAppService ──

mkdir -p "$CONTENTS/Library/LaunchDaemons"
cp "$SCRIPT_DIR/Resources/com.fancy.helper.plist" "$CONTENTS/Library/LaunchDaemons/"

echo "  ✅ Helper LaunchDaemon bundled"

# ── 3. Generate app icon ──

swift "$SCRIPT_DIR/generate_icon.swift" "$RESOURCES" 2>&1 || echo "  ⚠️  Icon generation skipped"

echo ""
echo "✅ Built: $APP_DIR"
echo ""
echo "── Run ────────────────────────────────────────"
echo "  open \"$APP_DIR\""
echo ""
echo "── Install Helper (one-time, for fan control) ─"
echo "  Click 'Install' in the app's HELPER section, then enable FANcy"
echo "  under System Settings → General → Login Items & Extensions."
echo "  (Requires the signed/notarized app — see native/package.sh.)"
echo ""
echo "── Or run with sudo (development) ──────────────"
echo "  sudo \"$MACOS/FANcy\""
