#!/usr/bin/env bash
# ws-test.sh — launch sim, hit HTTP endpoints, connect to WS briefly, kill
# Usage: scripts/ws-test.sh [seconds]
set -euo pipefail

cd "$(dirname "$0")/.."
SECS="${1:-8}"
DB=$(mktemp -t simrust-ws-XXXXXX.db)
LOG=$(mktemp -t simrust-ws-XXXXXX.log)

echo "=== building ==="
cargo build -p client_bevy --bin client_bevy 2>&1 | tail -3

echo ""
echo "=== launching sim ==="
RUST_LOG="${RUST_LOG:-client_bevy=info,sim_server=info,sim_core=info,tower_http=warn}" \
    WORLD_SPEED="${WORLD_SPEED:-2.0}" \
    DATABASE_PATH="$DB" \
    BIND_ADDR="127.0.0.1:8080" \
    ./target/debug/client_bevy --headless > "$LOG" 2>&1 &
SIM_PID=$!

# Wait for ready
READY=0
for i in $(seq 1 30); do
    if grep -q "sim:ready" "$LOG" 2>/dev/null; then
        READY=1; break
    fi
    sleep 0.5
done
if [[ $READY -eq 0 ]]; then
    echo "✗ sim did not signal ready"
    kill $SIM_PID 2>/dev/null || true
    tail -40 "$LOG"
    exit 1
fi
echo "✓ sim:ready"

echo ""
echo "=== GET /api/health ==="
curl -s --max-time 3 http://127.0.0.1:8080/api/health | head -c 400
echo ""

echo ""
echo "=== GET /api/ships (count + first ship preview) ==="
if command -v jq >/dev/null; then
    curl -s --max-time 3 http://127.0.0.1:8080/api/ships | jq '{count: (.data | length), first: .data[0]}'
else
    curl -s --max-time 3 http://127.0.0.1:8080/api/ships | head -c 500
fi

echo ""
echo "=== GET /api/markets (count + first market preview) ==="
if command -v jq >/dev/null; then
    curl -s --max-time 3 http://127.0.0.1:8080/api/markets | jq '{count: (.data | length), first: .data[0]}'
else
    curl -s --max-time 3 http://127.0.0.1:8080/api/markets | head -c 500
fi

echo ""
echo "=== POST /api/sim/pause, then /api/health, then /api/sim/resume ==="
curl -s -X POST http://127.0.0.1:8080/api/sim/pause
echo ""
curl -s --max-time 3 http://127.0.0.1:8080/api/health
echo ""
curl -s -X POST http://127.0.0.1:8080/api/sim/resume
echo ""

echo ""
echo "=== running sim for ${SECS}s to collect traffic ==="
sleep "$SECS"

echo ""
echo "=== final /api/ships/first.credits ==="
if command -v jq >/dev/null; then
    curl -s --max-time 3 http://127.0.0.1:8080/api/ships | jq '.data[0] | {id, credits, current_goal}'
fi

echo ""
echo "=== shutting down ==="
kill $SIM_PID 2>/dev/null || true
wait $SIM_PID 2>/dev/null || true

echo ""
echo "=== last 20 log lines ==="
tail -20 "$LOG"

echo ""
echo "(log: $LOG, db: $DB)"
