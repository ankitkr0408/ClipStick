#!/usr/bin/env bash
# Builds ClipStick.app. Prefers SwiftPM; falls back to swiftc when SwiftPM is unusable
# (e.g. a Command Line Tools install whose swift-package doesn't match its SDK).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.2.0"
BUILD_NUMBER="2"
APP="build/ClipStick.app"
BIN="build/ClipStick"
mkdir -p build downloads

if ( swift build -c release ) >/dev/null 2>&1; then
    cp "$(swift build -c release --show-bin-path)/ClipStick" "$BIN"
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
    echo "Compiling for Apple Silicon (arm64)..."
    swiftc -O -sdk "$SDK" -swift-version 5 -parse-as-library -target "arm64-apple-macosx14.0" \
        -o "$BIN-arm64" $(find Sources -name '*.swift') -lsqlite3

    if swiftc -O -sdk "$SDK" -swift-version 5 -parse-as-library -target "x86_64-apple-macosx14.0" \
        -o "$BIN-x86_64" $(find Sources -name '*.swift') -lsqlite3 2>/dev/null; then
        echo "Compiling for Intel (x86_64)..."
        lipo -create -output "$BIN" "$BIN-arm64" "$BIN-x86_64"
        rm -f "$BIN-arm64" "$BIN-x86_64"
        echo "Created Universal Binary (Apple Silicon + Intel)"
    else
        mv "$BIN-arm64" "$BIN"
    fi
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipStick"
if [ -f "assets/AppIcon.icns" ]; then
    cp "assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>ClipStick</string>
    <key>CFBundleDisplayName</key><string>ClipStick</string>
    <key>CFBundleIdentifier</key><string>dev.clipstick.app</string>
    <key>CFBundleExecutable</key><string>ClipStick</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>ClipStick imports new screenshots saved to your Desktop so you can annotate and batch them.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>ClipStick imports new screenshots saved to your Documents folder.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
(cd build && rm -f "ClipStick-v$VERSION-macOS.zip" && zip -rq "ClipStick-v$VERSION-macOS.zip" "ClipStick.app")
cp "build/ClipStick-v$VERSION-macOS.zip" "downloads/ClipStick.zip"
# Update manifest read by the in-app "Check for Updates…" (commit + push it together with downloads/ClipStick.zip).
SHA=$(shasum -a 256 downloads/ClipStick.zip | awk '{print $1}')
cat > version.json <<JSON
{
  "version": "$VERSION",
  "url": "https://raw.githubusercontent.com/ankitkr0408/ClipStick/main/downloads/ClipStick.zip",
  "sha256": "$SHA",
  "notes": "${RELEASE_NOTES:-Bug fixes and improvements.}"
}
JSON
echo "Built $APP, build/ClipStick-v$VERSION-macOS.zip, downloads/ClipStick.zip and version.json"
