# Astra II-B — N39 policy single-domain owned stage
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-19 07:14 MSK
BASE_SHA: 04e3ca86fb0faf7b610035f5667a5ffa1650cd45
ASTRA: II-B N39 owned writes, L129/L196 avoid unnecessary growing World copies, alias/rollback/full Schema oracle.
SCOPE: apply_native_player_research_policy: only operation-selected optional policy registry and target row detached, other registries read-only; preserve legacy optional maps, original mandate validation and full Schema/accounts before commit.
INTENDED_FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n110_policy_owned.gd
TEST: positive set/clear across policy domains vs full-deep oracle; malformed map, no-op, nested alias and rejected rollback.
RISK: source clear_mandate returns detached map; no authoritative nested aliases may escape.

## Result
CODE_SHA: d7c845d94e0524f2142569533f297b627806fae7
TEST_SHA: 6afde8f46929eef9a01284034adb3dc1c6048593
TEST: NOT_RUN
CODE_UNVERIFIED: true
PERFORMANCE_NOT_MEASURED: true
CALLSITE: apply_native_player_research_policy now stages only operation-selected optional registry, and detaches only its faction row. Existing source N109/N110 validators and full Schema/accounts publication gate unchanged. Old optional maps retained, absent maps materialized as before. Invalid map/row rejected before mutation. Tests compare against full deep-copy oracle for all five operations, alias/rollback, legacy missing maps and malformed negative cases.
LIMITATION: Test targets staging helper; production N109/N110 and full same-seed N9/N38 not executed. This is a bounded ownership improvement, not a demonstrated paid-tick acceleration.
NEXT ASTRA II-B: find remaining actual N39 paid-tick L129/L196 snapshot callers (construction escrow/other funded stage), remove full copies only where read/write ownership proven; full Schema/rollback/negative oracle and Windows same-seed profile.
