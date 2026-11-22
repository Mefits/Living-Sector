# Astra II-B — N39 N15 logistics owned publication
STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: PERF A
START: 2026-11-19 10:10 MSK
BASE SHA: b0ab88d12bfa916ccd73e52a2dc12de5968e505c
BACKLOG: II-B bounded owned write sets, local validators, versions & delta; N39 L129/L196 deep copy.
SCOPE: apply_fleet_logistics N15 load/unload/undock, ownership of ships/markets/cargo and dock receipts, preserve full Schema/N9 oracle and rollback.
INTENDED FILES: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n15_logistics_owned_publication.gd
TEST: old deep-copy publication comparator; mutable alias; missing/extra/altered receipts, ship and market; negative rejection.
RISK: staged proposal alias, registry shape, cargo and dock receipt integrity.

CODE SHA: 5ad986f41cf37348f8a95eaf8a148a2cd9353ec3
TEST SHA: 1f96e0a26a51ed2399eee9168e45d4e4cf13c567
TEST: NOT_RUN; CODE_UNVERIFIED; PERFORMANCE_NOT_MEASURED
SOURCE: apply_fleet_logistics now publishes N15 ship/market/receipt owned write set; _n15_owned_logistics_publication detaches modified ship, market, new receipt only. Existing full Schema.validate and N9 account checks run before publication; caller validates all unrelated rows and receipts, preserving rollback.
REGRESSION: old deep-copy oracle on load/unload/undock; sequential paid updates, proposal/World alias isolation, missing ship/market, duplicate receipt, wrong action/domain.
RISK: No Godot 4.7.2 execution, same-seed paid-tick/N38 restart or measured before/after yet.
NEXT: Astra II-B N39 real paid ship-service N97/N83 stage ownership and receipt-history scans, with full Schema/N9 oracle and negative tests; avoid C-owned physical service logic.
