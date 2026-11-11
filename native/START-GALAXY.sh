#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
export BIND_ADDR=127.0.0.1:8080 DATA_DIR="$PWD/priv/galaxy/data" DATABASE_PATH="$PWD/living-galaxy-02.db"
export LIVING_SECTOR_UI_DIR="$PWD/observer" WORLD_SPEED=16 LIVING_SECTOR_STRATEGY_MODE=execute LIVING_SECTOR_GALAXY=1
printf '%s\n' 'Open http://127.0.0.1:8080/observer after the server starts. Ctrl+C saves and exits.'
exec ./genesis-server-linux
