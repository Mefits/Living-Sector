# Astra II-B N39 L129/L196 — N150/N149 fleet publication
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: A
START: 2026-11-19 09:12 MSK
BASE_SHA: d55e2e6dd819ea7d7fe4ea8d4a74104cacc187e2
ASTRA: bounded owned write sets for repeated deep World snapshots; preserve Schema, N9, rollback and alias isolation.
SCOPE: N39 apply_native_ship_price_observation and apply_native_n149_ship_crew; shared owned fleet stage, positive and negative oracle tests.
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n150_n149_fleet_owned_publication.gd
TEST: old deep-copy oracle, sleeping/changed ship, nested alias, malformed/rollback, repeated stage.

## Result
CODE_SHA: 47f79087ee6786cd0e7e67ca59dd1ede57cf15d1
TEST_SHA: 30dbd4ae53e9cf4b4ff94ef3cb55c78bab2b5c0f
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED.
Changed production callsites: N150 apply_native_ship_price_observation and N149 apply_native_n149_ship_crew. Both now detach only modified fleet rows via _owned_fleet_publication_stage; reject changed sleeping rows, invalid roster/types; preserve full Schema and N9 account/receipt oracles and atomic publish. Candidate mutable rows detached deeply, unchanged rows shared read-only.
Test: legacy deep-copy oracle, two sequential stages, nested alias isolation, no-op, missing roster, forbidden sleeping mutation, malformed row, rollback.
NEXT: Astra II-B remaining N39 paid operating-world snapshots L129/L196; inspect N97/N83 paid service/trade and implement owned writes with full Schema/N9/rollback oracle, then Windows same-seed 100/300/600/900 + N38 restart.
