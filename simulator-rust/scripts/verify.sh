#!/usr/bin/env bash
# verify.sh — quick correctness gate: cargo check + test + clippy (warnings allowed)
# Usage: scripts/verify.sh [--strict]  (strict = clippy errors on warnings)
set -euo pipefail

cd "$(dirname "$0")/.."

STRICT="${1:-}"
CLIPPY_FLAGS=""
if [[ "$STRICT" == "--strict" ]]; then
    CLIPPY_FLAGS="-- -D warnings"
fi

echo "=== cargo check ==="
cargo check --workspace --all-targets

echo ""
echo "=== cargo test ==="
cargo test --workspace

echo ""
echo "=== cargo clippy ==="
cargo clippy --workspace --all-targets $CLIPPY_FLAGS

echo ""
echo "✓ verify passed"
