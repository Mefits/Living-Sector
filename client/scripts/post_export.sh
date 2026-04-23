#!/bin/bash
# post_export.sh — copy the bundled Rust simulator binary into an
# exported Godot macOS .app bundle. Godot's export doesn't ship
# non-resource files as real files on disk, so we do it ourselves.
# Used by the Makefile's `post-export-mac` target; safe standalone.
#
# Usage:  post_export.sh <path-to-.app> [path-to-simulator-binary]
#
# The simulator binary is placed at
#   <app>/Contents/Resources/simulator
# which matches one of ServerManager's candidate lookup paths
# (client/scripts/autoload/server_manager.gd:_binary_candidates).
#
# The Rust sim is a single native binary — no release directory
# tree to copy (the Elixir sim with its BEAM release was retired
# during the Rust port).

set -euo pipefail

APP="${1:-}"
SIM="${2:-./simulator}"

if [ -z "$APP" ]; then
    echo "usage: post_export.sh <path-to-.app> [path-to-simulator-binary]" >&2
    exit 1
fi

if [ ! -d "$APP" ]; then
    echo "error: no .app directory at $APP" >&2
    exit 1
fi

if [ ! -f "$SIM" ]; then
    echo "error: simulator binary not found at $SIM" >&2
    echo "Run 'make sim' first to build + copy it in." >&2
    exit 1
fi

DST="$APP/Contents/Resources/simulator"
echo "==> $SIM -> $DST"
mkdir -p "$APP/Contents/Resources"
cp "$SIM" "$DST"
chmod +x "$DST"

echo "==> done."
