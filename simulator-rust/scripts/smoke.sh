#!/usr/bin/env bash
# smoke.sh — build, launch sim with temp DB, let it run N seconds, kill, print log
# Usage: scripts/smoke.sh [seconds]   (default 8)
set -euo pipefail

cd "$(dirname "$0")/.."

SECS="${1:-8}"
DB=$(mktemp -t simrust-smoke-XXXXXX.db)
LOG=$(mktemp -t simrust-smoke-XXXXXX.log)

echo "=== building ==="
cargo build --bin simulator 2>&1 | tail -5

echo ""
echo "=== launching (db=$DB, duration=${SECS}s) ==="
RUST_LOG="${RUST_LOG:-simulator=info,sim_core=info}" \
    DATABASE_PATH="$DB" \
    ./target/debug/simulator > "$LOG" 2>&1 &
SIM_PID=$!

# Wait for sim:ready or timeout
READY=0
for i in $(seq 1 20); do
    if grep -q "sim:ready" "$LOG" 2>/dev/null; then
        READY=1
        break
    fi
    sleep 0.25
done

if [[ $READY -eq 0 ]]; then
    echo "✗ sim did not print sim:ready within 5s"
    kill $SIM_PID 2>/dev/null || true
    echo "--- log ---"
    cat "$LOG"
    exit 1
fi

echo "✓ sim:ready — running for ${SECS}s..."
sleep "$SECS"

# Graceful shutdown
kill $SIM_PID 2>/dev/null || true
wait $SIM_PID 2>/dev/null || true

echo ""
echo "=== log ==="
cat "$LOG"

echo ""
echo "=== db contents ==="
if command -v sqlite3 >/dev/null; then
    echo "Tables:"
    sqlite3 "$DB" ".tables"
    echo ""
    echo "Counts:"
    for tbl in star_systems celestial_bodies locations facilities markets ships populations factions travel_routes contracts; do
        count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM $tbl" 2>/dev/null || echo "?")
        printf "  %-20s %s\n" "$tbl" "$count"
    done
fi

# Show body angle progression (proves orbital ticks are firing)
if command -v sqlite3 >/dev/null; then
    echo ""
    echo "=== sample body angles (from DB, seeded values — runtime state not yet flushed) ==="
    sqlite3 -column -header "$DB" "SELECT name, ROUND(current_angle,2) AS angle FROM celestial_bodies LIMIT 5"
fi

echo ""
echo "✓ smoke test complete (log: $LOG, db: $DB)"
