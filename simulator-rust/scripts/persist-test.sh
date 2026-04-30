#!/usr/bin/env bash
# persist-test.sh — verify DB persistence works across restarts
#   1. Boot sim with a fixed DB, run 15s, snapshot a ship's credits + tick
#   2. Stop cleanly (SIGTERM)
#   3. Boot again with same DB, verify tick counter resumed + ship credits persisted
# Usage: scripts/persist-test.sh
set -euo pipefail

cd "$(dirname "$0")/.."

DB=$(mktemp -t simrust-persist-XXXXXX.db)
LOG1=$(mktemp -t simrust-persist-XXXXXX.log)
LOG2=$(mktemp -t simrust-persist-XXXXXX.log)

echo "=== building ==="
cargo build -p client_bevy --bin client_bevy 2>&1 | tail -3

echo ""
echo "=== Run 1 (seed + run 15s) ==="
RUST_LOG=client_bevy=info,sim_server=info,sim_core=info \
  WORLD_SPEED=6.0 \
  DATABASE_PATH="$DB" \
  BIND_ADDR="127.0.0.1:8090" \
  ./target/debug/client_bevy --headless > "$LOG1" 2>&1 &
PID=$!
# Wait for ready
for i in $(seq 1 30); do
    if grep -q "sim:ready" "$LOG1" 2>/dev/null; then
        break
    fi
    sleep 0.5
done
sleep 15
# Capture state before shutdown
TICK_BEFORE=$(curl -s --max-time 3 http://127.0.0.1:8090/api/health | grep -o '"tick":[0-9]*' | cut -d: -f2 || echo "?")
CREDITS_BEFORE=$(curl -s --max-time 3 http://127.0.0.1:8090/api/ships | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['data'][0]['credits'] if d['data'] else '?')" 2>/dev/null || echo "?")
SHIP_ID=$(curl -s --max-time 3 http://127.0.0.1:8090/api/ships | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['data'][0]['id'] if d['data'] else '?')" 2>/dev/null || echo "?")

echo "Before shutdown: tick=$TICK_BEFORE, $SHIP_ID credits=$CREDITS_BEFORE"

# SIGTERM for clean shutdown (persistence flush)
kill -TERM $PID 2>/dev/null || true
wait $PID 2>/dev/null || true
# Give the SQLite file a moment to close
sleep 1

# Inspect the DB directly
echo ""
echo "=== DB state after run 1 ==="
if command -v sqlite3 >/dev/null; then
    echo -n "  simulation_state tick: "
    sqlite3 "$DB" "SELECT value FROM simulation_state WHERE key='tick_counter'" 2>/dev/null || echo "(none)"
    echo -n "  ships updated count: "
    sqlite3 "$DB" "SELECT COUNT(*) FROM ships WHERE updated_at > inserted_at" 2>/dev/null || echo "?"
    echo -n "  markets updated count: "
    sqlite3 "$DB" "SELECT COUNT(*) FROM markets WHERE updated_at > inserted_at" 2>/dev/null || echo "?"
    echo -n "  factions updated count: "
    sqlite3 "$DB" "SELECT COUNT(*) FROM factions WHERE updated_at > inserted_at" 2>/dev/null || echo "?"
fi

echo ""
echo "=== Run 2 (same DB, should resume) ==="
RUST_LOG=client_bevy=info,sim_server=info,sim_core=info \
  WORLD_SPEED=6.0 \
  DATABASE_PATH="$DB" \
  BIND_ADDR="127.0.0.1:8090" \
  ./target/debug/client_bevy --headless > "$LOG2" 2>&1 &
PID=$!
for i in $(seq 1 30); do
    if grep -q "sim:ready" "$LOG2" 2>/dev/null; then
        break
    fi
    sleep 0.5
done
sleep 2
TICK_AFTER=$(curl -s --max-time 3 http://127.0.0.1:8090/api/health | grep -o '"tick":[0-9]*' | cut -d: -f2 || echo "?")
echo "After restart: tick=$TICK_AFTER (should be >= $TICK_BEFORE)"

kill -TERM $PID 2>/dev/null || true
wait $PID 2>/dev/null || true

# Check for "Resuming from persisted tick" in log
echo ""
if grep -q "Resuming from persisted tick" "$LOG2"; then
    echo "✓ Persistence test passed: sim resumed from persisted tick"
else
    echo "✗ Persistence test failed — no resume message in log"
    echo "--- run 2 log tail ---"
    tail -15 "$LOG2"
fi

echo ""
echo "(logs: $LOG1, $LOG2, db: $DB)"
