#!/usr/bin/env bash
# Living Sector: install upstream GUT 9.7.1 exactly at its audited commit.
# Run from anywhere: bash godot/testing/gut/install-gut.sh
set -euo pipefail
PIN="aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605"
PROJECT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEST="$PROJECT_DIR/addons/gut"
if [[ ! -f "$PROJECT_DIR/project.godot" ]]; then
  echo "Not a Godot project: $PROJECT_DIR" >&2
  exit 2
fi
copy_project_specs() {
  local specs="$PROJECT_DIR/testing/gut/specs"
  local target="$PROJECT_DIR/tests/gut"
  mkdir -p "$target"
  local file
  for file in "$specs"/test_*.gd.txt; do
    [[ -f "$file" ]] || continue
    cp "$file" "$target/$(basename "${file%.txt}")"
  done
}
if [[ -f "$DEST/plugin.cfg" ]] && grep -q 'version="9.7.1"' "$DEST/plugin.cfg"; then
  copy_project_specs
  echo "GUT 9.7.1 already installed; refreshed Living Sector unit specs"
  exit 0
fi
if [[ -e "$DEST" ]]; then
  echo "Refusing to overwrite an existing addon; move it first: $DEST" >&2
  exit 2
fi
for tool in curl unzip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required $tool" >&2
    exit 2
  fi
done
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl --fail --location --retry 3 --silent --show-error \
  "https://codeload.github.com/bitwes/Gut/zip/$PIN" -o "$TMP/gut.zip"
unzip -q "$TMP/gut.zip" -d "$TMP/src"
SOURCE="$(find "$TMP/src" -type f -path '*/addons/gut/plugin.cfg' -print -quit)"
if [[ -z "$SOURCE" ]]; then
  echo "Pinned archive has no addons/gut/plugin.cfg" >&2
  exit 2
fi
if ! grep -q 'version="9.7.1"' "$SOURCE"; then
  echo "Unexpected GUT version in pinned archive" >&2
  exit 2
fi
mkdir -p "$(dirname "$DEST")"
cp -R "$(dirname "$SOURCE")" "$DEST"
if [[ ! -f "$DEST/gut_cmdln.gd" ]] || [[ ! -f "$DEST/LICENSE.md" ]]; then
  echo "GUT installation incomplete" >&2
  exit 2
fi
copy_project_specs
echo "Installed official GUT 9.7.1 at commit $PIN"
echo "godot --headless --path \"$PROJECT_DIR\" --script res://addons/gut/gut_cmdln.gd -gdir=res://tests/gut -gexit"
