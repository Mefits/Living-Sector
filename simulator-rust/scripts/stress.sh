#!/usr/bin/env bash
# stress.sh — ramp ships per facility, sample tick perf at each plateau.
#
# Each wave spawns one ship at every faction-owned facility. With 93 facilities
# in the seed (8 are gates and skip), each wave adds ~85 ships. Settle for N
# seconds between waves so the perf p50/p99 ring fills with steady-state samples.
#
# Usage: scripts/stress.sh [waves] [settle_seconds] [tps]
#   waves   default 10 (so ~850 added on top of the ~282 baseline = ~1130 ships)
#   settle  default 15
#   tps     default 8 (default cadence). Bump to 20-30 to exercise tighter budget.
#
# Output: a markdown table with wave, ships_added, total, p50_ms, p99_ms,
# tps_observed. The test fails (red row) when p50 crosses the 125ms / tps budget
# OR observed tps drops below 80% of the configured tps (real cadence missed).
set -euo pipefail

cd "$(dirname "$0")/.."

WAVES="${1:-10}"
SETTLE="${2:-15}"
TPS="${3:-8}"
DB=$(mktemp -t simrust-stress-XXXXXX.db)
LOG=$(mktemp -t simrust-stress-XXXXXX.log)

cleanup() {
    [[ -n "${SIM_PID:-}" ]] && kill "$SIM_PID" 2>/dev/null || true
    [[ -n "${SIM_PID:-}" ]] && wait "$SIM_PID" 2>/dev/null || true
    rm -f "$DB" "$DB"-*
}
trap cleanup EXIT

echo "=== building ==="
cargo build --bin simulator 2>&1 | tail -3

echo ""
echo "=== launching (db=$DB, waves=$WAVES, settle=${SETTLE}s, tps=$TPS) ==="
RUST_LOG=warn DATABASE_PATH="$DB" ./target/debug/simulator > "$LOG" 2>&1 &
SIM_PID=$!

# Wait for ready
for i in $(seq 1 80); do
    grep -q "sim:ready" "$LOG" 2>/dev/null && break
    sleep 0.25
done
if ! grep -q "sim:ready" "$LOG"; then
    echo "✗ sim never ready"
    cat "$LOG"
    exit 1
fi

# Switch to configured tps so the budget reflects what we want to stress.
# 125 ms / tps 8 = 125 ms budget; tps 20 = 50 ms; tps 30 = 33 ms.
curl -sS -X POST http://127.0.0.1:8080/api/sim/speed \
    -H 'Content-Type: application/json' \
    -d "{\"ticks_per_second\": $TPS}" > /dev/null
BUDGET_MS=$(python3 -c "print(round(1000.0 / $TPS, 1))")
echo "✓ tps=$TPS, budget=${BUDGET_MS}ms/tick"

# Snapshot cache builds on the FIRST tick's broadcast cycle (every 8 ticks for
# facilities). At default 8 tps, that's ~1 s; bump to 3 s for safety so the
# /api/facilities GET below returns the populated list instead of `[]`.
sleep 3

# Pull facility list once. Cache (loc, faction) per facility; skip empty faction
# (gates) so we don't spawn into uninhabited slots.
FACS_JSON=$(curl -s http://127.0.0.1:8080/api/facilities)
echo "  facilities response length: ${#FACS_JSON}"
FAC_PAIRS=$(echo "$FACS_JSON" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)['data']
except Exception as e:
    sys.stderr.write(f'parse failed: {e}\n')
    sys.exit(1)
for f in data:
    loc = f.get('location') or f.get('location_name') or ''
    fac = f.get('faction_id') or ''
    typ = f.get('type') or f.get('facility_type') or ''
    if loc and fac and typ != 'gate':
        print(f'{loc}|{fac}')
" 2>&1)
FAC_COUNT=$(printf '%s\n' "$FAC_PAIRS" | grep -c '|' || true)
echo "✓ $FAC_COUNT eligible facilities (excluding gates)"
if [[ "$FAC_COUNT" -lt 1 ]]; then
    echo "  pairs raw output:"
    echo "$FAC_PAIRS" | head -5
    exit 1
fi

# Probe helper. Reads /api/health repeatedly to average the per-phase
# breakdown (single-tick samples are noisy), then emits one row showing
# ships count, p50/p99 wall-time, observed tps, budget %, and the top
# three phases by μs.
probe() {
    local label="$1"
    local added="$2"
    local tick_before="$3"
    sleep "$SETTLE"
    local health=$(curl -s http://127.0.0.1:8080/api/health)
    local ship_count=$(curl -s http://127.0.0.1:8080/api/ships | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
    # Sample phase + ship-sub breakdowns 8× over 1s so noisy single-tick
    # numbers stabilize. Both averaged below.
    local samples=()
    local sub_samples=()
    for i in 1 2 3 4 5 6 7 8; do
        local resp=$(curl -s http://127.0.0.1:8080/api/health)
        samples+=("$(echo "$resp" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["perf"]["phase_us"]))')")
        sub_samples+=("$(echo "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin)["perf"].get("ships_breakdown_us",{}); print(json.dumps(d))')")
        sleep 0.125
    done
    local samples_json=$(printf '%s\n' "${samples[@]}" | python3 -c 'import json,sys; print(json.dumps([json.loads(l) for l in sys.stdin if l.strip()]))')
    local sub_json=$(printf '%s\n' "${sub_samples[@]}" | python3 -c 'import json,sys; print(json.dumps([json.loads(l) for l in sys.stdin if l.strip()]))')
    python3 - "$label" "$added" "$ship_count" "$tick_before" "$SETTLE" "$BUDGET_MS" "$samples_json" "$sub_json" <<EOF
import json, sys
label, added, ships, tick_before, settle, budget, samples_json, sub_json = sys.argv[1:]
ships = int(ships); tick_before = int(tick_before); settle = float(settle); budget = float(budget)
h = json.loads('''$health''')
tick_now = int(h['tick'])
p50 = h['perf']['tick_compute_p50_us'] / 1000.0
p99 = h['perf']['tick_compute_p99_us'] / 1000.0
tps_obs = (tick_now - tick_before) / settle
budget_pct = max(p50, p99) / budget * 100
flag = '✗' if (p50 > budget or tps_obs < ${TPS} * 0.80) else ('!' if budget_pct > 70 else '✓')
# Average phase breakdown over the samples we collected.
samples = json.loads(samples_json)
phases_avg = {}
if samples:
    keys = samples[0].keys()
    for k in keys:
        phases_avg[k] = sum(s.get(k, 0) for s in samples) / len(samples)
top3 = sorted(phases_avg.items(), key=lambda kv: kv[1], reverse=True)[:3]
top_str = '  '.join(f'{k}={v/1000:.2f}ms' for k,v in top3)
# Ship sub-phase breakdown — same average, only print non-zeros sorted.
subs = json.loads(sub_json)
sub_avg = {}
if subs:
    keys = subs[0].keys()
    for k in keys:
        sub_avg[k] = sum(s.get(k, 0) for s in subs) / len(subs)
sub_str = '  '.join(f'{k}={v/1000:.2f}ms' for k,v in sorted(sub_avg.items(), key=lambda kv: kv[1], reverse=True) if v > 0)
print(f"{flag} {label:>3}  +{added:>4} = {ships:>5}  p50={p50:6.2f} p99={p99:6.2f} tps={tps_obs:4.1f} bud={budget_pct:3.0f}%")
print(f"        top: {top_str}")
print(f"        ships: {sub_str}")
EOF
}

# Header
echo ""
printf "%-3s %3s  %5s   %5s    %s\n" "" "wave" "added" "total" "metrics"
echo "------------------------------------------------------------------------------"

# Wave 0 = baseline measurement
TICK0=$(curl -s http://127.0.0.1:8080/api/health | python3 -c "import json,sys; print(json.load(sys.stdin)['tick'])")
probe "0" "0" "$TICK0"

CLASSES=("freighter" "courier" "hauler" "tanker" "miner")
for wave in $(seq 1 "$WAVES"); do
    CLASS="${CLASSES[$(((wave - 1) % 5))]}"
    SPAWNED=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        FAC_LOC="${line%%|*}"
        FAC_FAC="${line##*|}"
        curl -sS -X POST http://127.0.0.1:8080/api/admin/ships \
            -H 'Content-Type: application/json' \
            -d "{\"class\":\"$CLASS\",\"faction_id\":\"$FAC_FAC\",\"location\":\"$FAC_LOC\"}" > /dev/null
        SPAWNED=$((SPAWNED + 1))
    done <<< "$FAC_PAIRS"

    TICK_BEFORE=$(curl -s http://127.0.0.1:8080/api/health | python3 -c "import json,sys; print(json.load(sys.stdin)['tick'])")
    probe "$wave" "$SPAWNED" "$TICK_BEFORE"
done

echo ""
echo "✓ stress test done. log: $LOG"
echo ""
echo "Legend: ✓ ok / ! >70% budget / ✗ over budget or tps drift"
