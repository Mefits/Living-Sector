# II-C N140 cursor staging and deferred fleet ownership
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: C
START: 2026-11-19 08:30 Europe/Moscow
BASE_SHA: d17865d88e759249d15851ed0d3bd4755cf94b77
CLAIM_SHA: a9d4a11e7b8fa0a5b41eb80e7d4dfd89cdc5f0a2
CODE_SHA: 1d8b43c0548f38a3d7fae6f5f3ce1b369d6e77eb
TEST_SHA: 410c916979c93b67be178e140abaa3f529b960d4
TEST: NOT_RUN
CODE: CODE_UNVERIFIED
PERFORMANCE: NOT_MEASURED
ASTRA: II-C ship/contract/dock/route caches; N140 ship/agent copies and read-only/owned boundary.
FILES:
- godot/scripts/sim/phase2/unified_n140_ship_lod_phase.gd
- godot/tests/p2_perf_c_n140_deferred_fleet_ownership.gd

IMPLEMENTATION:
- N140.stage validates every source ship, LOD cursor and transit before detaching full fleet.
- Ship position projection is built only when the original recompute cadence actually fires and only for rows with LOD.
- SourceLod.set_divisor/try_fire produce small detached cursor values, staged in a proposal-local overlay; failures do not deep-copy the cargo/BT fleet.
- One final deep fleet copy after successful gates, followed by cursor assignment, preserving full owned output for N14/N84 caller.
- No changes to RNG, N9, N38, World, source cadence, route or physical transit.

ORACLE:
- Independent SourceLod.recompute + ship_gate for 500 mixed LOD/no-LOD ships, missing locations, active transit, 8 ticks × 2 multipliers × 2 observer configurations.
- Exact fields ships/changed/fired/fired_count/skipped_count/recomputed/stats/tick.
- Negative late invalid cursor/transit, sleeping cursor and nested cargo/BT/memory alias checks.
- Manual Godot run required; no PASS claimed.

RISK:
- Deferred copy changes only allocation timing; must confirm parser and exact replay with paid 24/100/500 ship fixtures.
- No performance improvement asserted without same-seed paid-tick A/B.

NEXT ASTRA II-C: paid 24/100/500 N140/N84/N153 BT/cargo/fuel/route parity and remaining dock/contract occupancy scans with version-safe invalidation.
