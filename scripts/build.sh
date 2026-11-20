#!/usr/bin/env bash
# Builds ClipCoard.app. Prefers SwiftPM; falls back to swiftc when SwiftPM is unusable
# (e.g. a Command Line Tools install whose swift-package doesn't match its SDK).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/ClipCoard.app"
BIN="build/ClipCoard"
mkdir -p build

if ( swift build -c release ) >/dev/null 2>&1; then
    cp "$(swift build -c release --show-bin-path)/ClipCoard" "$BIN"
else
    echo "SwiftPM unavailable — compiling with swiftc"
    # Pick the newest SDK whose Swift version the compiler can read.
    SDK=""
    for candidate in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk 2>/dev/null | sort -rV) "$(xcrun --show-sdk-path)"; do
        if echo 'import Foundation' | swiftc -sdk "$candidate" -typecheck -target arm64-apple-macosx14.0 - >/dev/null 2>&1; then
            SDK="$candidate"; break
        fi
    done
    [ -n "$SDK" ] || { echo "No usable macOS SDK found"; exit 1; }
    swiftc -O -sdk "$SDK" -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
        -o "$BIN" $(find Sources -name '*.swift') -lsqlite3
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipCoard"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>ClipCoard</string>
    <key>CFBundleDisplayName</key><string>ClipCoard</string>
    <key>CFBundleIdentifier</key><string>dev.clipcoard.app</string>
    <key>CFBundleExecutable</key><string>ClipCoard</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>ClipCoard imports new screenshots saved to your Desktop so you can annotate and batch them.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>ClipCoard imports new screenshots saved to your Documents folder.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
