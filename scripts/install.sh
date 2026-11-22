#!/usr/bin/env bash
# Installs ClipStick to /Applications (or ~/Applications) and launches it.
set -euo pipefail

# Ensure we are in the repo directory if run locally
if [ -f "$(dirname "$0")/../downloads/ClipStick.zip" ] || [ -f "$(dirname "$0")/build.sh" ]; then
    cd "$(dirname "$0")/.."
fi

DEST_DIR="/Applications"
[ -w "$DEST_DIR" ] || { DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; }
DEST="$DEST_DIR/ClipStick.app"

APP_SOURCE=""

# 1. Prefer local pre-built zip if available (e.g. inside downloaded ZIP)
if [ -f "downloads/ClipStick.zip" ]; then
    echo "Found pre-built ClipStick. Unpacking..."
    TMP_EXTRACT=$(mktemp -d)
    unzip -qo "downloads/ClipStick.zip" -d "$TMP_EXTRACT"
    APP_SOURCE="$TMP_EXTRACT/ClipStick.app"
# 2. Or local build if present
elif [ -d "build/ClipStick.app" ]; then
    APP_SOURCE="build/ClipStick.app"
# 3. If swift compiler and SDK exist locally, build from source
elif command -v swiftc >/dev/null 2>&1 && xcrun --show-sdk-path >/dev/null 2>&1 && [ -f "scripts/build.sh" ]; then
    echo "Developer tools found. Compiling with swiftc..."
    ./scripts/build.sh
    APP_SOURCE="build/ClipStick.app"
# 4. Otherwise, download the lightweight pre-built app (370 KB) from GitHub
else
    echo "Downloading pre-built ClipStick for Mac (370 KB)..."
    TMP_ZIP=$(mktemp /tmp/ClipStick.XXXXXX.zip)
    curl -fsSL "https://raw.githubusercontent.com/ankitkr0408/ClipStick/main/downloads/ClipStick.zip" -o "$TMP_ZIP"
    TMP_EXTRACT=$(mktemp -d)
    unzip -qo "$TMP_ZIP" -d "$TMP_EXTRACT"
    APP_SOURCE="$TMP_EXTRACT/ClipStick.app"
fi

# Clean up any old running instances
pkill -x ClipCoard 2>/dev/null || true
pkill -x ClipStick 2>/dev/null || true
sleep 0.5
rm -rf "$DEST_DIR/ClipCoard.app"
rm -rf "$DEST"

echo "Installing to $DEST..."
cp -R "$APP_SOURCE" "$DEST"
open "$DEST"
echo "Success! ClipStick is installed and running in your menu bar."
