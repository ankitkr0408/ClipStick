#!/usr/bin/env bash
# Builds ClipStick, installs it to /Applications (or ~/Applications), and launches it.
# On first launch from there it registers itself as a login item.
set -euo pipefail

# If piped through `curl | bash` or run from outside the repo, clone into a temp directory
if [ ! -f "scripts/build.sh" ]; then
    TMP_DIR=$(mktemp -d)
    echo "Downloading ClipStick..."
    git clone --depth 1 https://github.com/ankitkr0408/ClipStick.git "$TMP_DIR"
    cd "$TMP_DIR"
else
    cd "$(dirname "$0")/.."
fi

./scripts/build.sh

DEST_DIR="/Applications"
[ -w "$DEST_DIR" ] || { DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; }
DEST="$DEST_DIR/ClipStick.app"

pkill -x ClipCoard 2>/dev/null || true
pkill -x ClipStick 2>/dev/null || true
sleep 0.5
rm -rf "$DEST_DIR/ClipCoard.app"
rm -rf "$DEST"
cp -R build/ClipStick.app "$DEST"
open "$DEST"
echo "Installed to $DEST — look for the clipboard icon in the menu bar."
