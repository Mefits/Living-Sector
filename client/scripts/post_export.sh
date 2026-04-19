#!/bin/bash
# post_export.sh — copy the bundled Elixir release into an exported
# Godot macOS .app bundle. The Godot export itself can't easily ship
# non-resource files as real files on disk, so we do it ourselves.
# Used by the Makefile's `post-export` target; also safe to invoke
# standalone.
#
# Usage:  post_export.sh <path-to-.app> [path-to-simulator-release]
#
# The simulator release is placed at
#   <app>/Contents/Resources/simulator/
# which matches one of ServerManager's candidate lookup paths.

set -euo pipefail

APP="${1:-}"
SIM="${2:-./simulator}"

if [ -z "$APP" ]; then
    echo "usage: post_export.sh <path-to-.app> [path-to-simulator-release]" >&2
    exit 1
fi

if [ ! -d "$APP" ]; then
    echo "error: no .app directory at $APP" >&2
    exit 1
fi

if [ ! -d "$SIM" ]; then
    echo "error: simulator release not found at $SIM" >&2
    echo "Run 'make sim' first to copy it in." >&2
    exit 1
fi

DST="$APP/Contents/Resources/simulator"
echo "==> $SIM → $DST"
rm -rf "$DST"
cp -R "$SIM" "$DST"

# Preserve executable bits on the launcher scripts just in case cp
# drops them on some filesystems (e.g. SMB shares).
chmod +x "$DST/bin/simulator" 2>/dev/null || true

echo "==> done."
