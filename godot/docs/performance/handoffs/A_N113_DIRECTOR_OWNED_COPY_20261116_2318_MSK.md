# A handoff — unpaid N113 director strategy bounded copy (2026-11-16)

CODE COMMIT: 3bcf8df3a9bb988d536669fff05747c93d742408
TEST COMMIT: d0b79d3812bf55bd26655da84ba33998f02b0e39
BRANCH: integration/perf-astra-5-workers-20261116 (draft PR #262)

Files:
- godot/scripts/sim/phase1/n39_native_world_production.gd
- godot/tests/p2_perf_a_n113_director_owned_copy_20261116.gd

Unpaid N113 strategic memory previously used _copy_world("L1751", true). It now takes a shallow root and deep-detaches research_directors, the sole mutated domain. Full Schema.validate and Schema.accounts comparison remain in place, before publishing. Grant strategy is duplicated; no ledger/receipt/ship/contract behavior was changed.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED; TEST_ADDED_NOT_RUN. The test compares bounded staging with full deep-copy oracle and exercises a negative alias fixture. This is a structural test, NOT N39/ledger/restart parity. No runtime acceleration or site frequency measured; the change removes one full World deep copy per reached unpaid N113 strategy path, but may not affect dominant deep:L129 snapshot cost.

NEXT: execute targeted Godot test and full same-seed N9/N39/N38/BT/RNG parity before acceptance. Measure L1751 calls and cost in early/late windows; prioritize deep:L129 snapshot callers in ships/dock_queue with owner C, proving no intervening writes before any snapshot reuse. No CI was started.
