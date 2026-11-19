# Astra II-B N39 L129/L196 — N150/N149 fleet publication
STATUS: IN_PROGRESS
OWNER: A
START: 2026-11-19 09:12 MSK
BASE_SHA: d55e2e6dd819ea7d7fe4ea8d4a74104cacc187e2
ASTRA: bounded owned write sets for repeated deep World snapshots; preserve Schema, N9, rollback and alias isolation.
SCOPE: N39 apply_native_ship_price_observation and apply_native_n149_ship_crew; shared owned fleet stage, positive and negative oracle tests.
FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n150_n149_fleet_owned_publication.gd
TEST: old deep-copy oracle, sleeping/changed ship, nested alias, malformed/rollback, repeated stage.
