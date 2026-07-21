#!/usr/bin/env bash
# check-api.sh — hit the running sim's HTTP endpoints and report
# Assumes sim is already running on localhost:8080
# Usage: scripts/check-api.sh
set -euo pipefail

HOST="${SIM_HOST:-localhost:8080}"

echo "=== health ==="
curl -s --max-time 3 "http://${HOST}/api/health" | head -c 400
echo ""
echo ""

echo "=== ships (first 1) ==="
curl -s --max-time 3 "http://${HOST}/api/ships" | head -c 600
echo ""
echo ""

echo "=== markets (first 1) ==="
curl -s --max-time 3 "http://${HOST}/api/markets" | head -c 600
echo ""
