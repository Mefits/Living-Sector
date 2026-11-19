# Astra II-B — N39 N15 logistics owned publication
STATUS: IN_PROGRESS
OWNER: PERF A
START: 2026-11-19 10:10 MSK
BASE SHA: b0ab88d12bfa916ccd73e52a2dc12de5968e505c
BACKLOG: II-B bounded owned write sets, local validators, versions & delta; N39 L129/L196 deep copy.
SCOPE: apply_fleet_logistics N15 load/unload/undock, ownership of ships/markets/cargo and dock receipts, preserve full Schema/N9 oracle and rollback.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n15_logistics_owned_publication.gd
TEST: old deep-copy publication comparator; mutable alias; missing/extra/altered receipts, ship and market; negative rejection.
RISK: staged proposal alias, registry shape, cargo and dock receipt integrity.
