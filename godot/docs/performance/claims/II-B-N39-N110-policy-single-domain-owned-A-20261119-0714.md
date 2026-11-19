# Astra II-B — N39 policy single-domain owned stage
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-19 07:14 MSK
BASE_SHA: 04e3ca86fb0faf7b610035f5667a5ffa1650cd45
ASTRA: II-B N39 owned writes, L129/L196 avoid unnecessary growing World copies, alias/rollback/full Schema oracle.
SCOPE: apply_native_player_research_policy: only operation-selected optional policy registry and target row detached, other registries read-only; preserve legacy optional maps, original mandate validation and full Schema/accounts before commit.
INTENDED_FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n110_policy_owned.gd
TEST: positive set/clear across policy domains vs full-deep oracle; malformed map, no-op, nested alias and rejected rollback.
RISK: source clear_mandate returns detached map; no authoritative nested aliases may escape.
