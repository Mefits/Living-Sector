#!/usr/bin/env bash
# Execute on a machine with a compatible Rust/Cargo toolchain.
# Does NOT run the bundled old genesis-server-linux or modify a game save.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v cargo >/dev/null 2>&1; then
  echo "BLOCKED: Rust/Cargo not installed. No new Rust code was tested." >&2
  exit 127
fi
OUT="${1:-ai-build-validation}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
printf '%s\n' "rustc: $(rustc --version)" "cargo: $(cargo --version)" > "$OUT/toolchain.txt"
run() {
  local name="$1"; shift
  echo "Running $name: $*"
  if "$@" > "$OUT/$name.log" 2>&1; then
    echo "PASS $name" | tee "$OUT/$name.status"
  else
    code=$?
    echo "FAIL $name (exit $code)" | tee "$OUT/$name.status" >&2
    echo "See $OUT/$name.log" >&2
    exit "$code"
  fi
}
run check_sim_core cargo check --locked -p sim_core
run test_planning cargo test --locked -p sim_core strategy::planning
run test_coordination cargo test --locked -p sim_core strategy::coordination
run check_server cargo check --locked -p sim_server -p sim_db
printf '%s\n' 'SOURCE CHECKS PASSED. Do not claim runtime verification until a NEW binary is built and executed.' | tee "$OUT/RESULT.txt"
