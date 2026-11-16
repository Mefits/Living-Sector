# PERF A — N104 release bounded World commit (2026-11-16 19:58 MSK)

- Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.
- Code commit: `4c7770d091d1e00747c731183ba0bf5c449f2c87`.
- Test commit: `55a84fa976a4c62fa75725f41081dbe60d7ed301`.
- Code: `godot/scripts/sim/phase1/n39_native_world_production.gd`.
- Test: `godot/tests/p2_perf_a_n104_release_owned_domains.gd`.
- Replaced N104 successful release's `next.duplicate(true)` full World commit with authoritative shallow World copy plus deep detached `ships`, `contract_board`, `faction_relations`. The source's existing explicit domain comparisons, full Schema.validate and N9 account check remain unchanged. No changed-domain alias from external stage is published. No ledger, N158, C, D, E or save files changed.
- Targeted test compares bounded commit to deep-copy oracle, verifies source isolation and negative mutable-alias case. This test is a **synthetic ownership oracle**, not a complete Schema.validate or N38 replay test.
- TEST EXECUTED: NOT RUN; CODE_UNVERIFIED (Godot runtime not available in this connector-only execution). No same-seed timing or improvement claim. Full N39/N9/N38/BT/RNG/contract/cargo parity remains unverified.
- Scope/expected benefit: removes one full World deep copy per **successful changed N104 release**; stage creation and full Schema checks remain. Actual N104 release call count and cost not measured, and this may not materially reduce deep:L129 snapshots.
- Next: coordinate with C on N21 ships/dock snapshot callsites and quantify per-caller deep:L129 copies. Run parser + targeted N104 test, full Schema oracle, N38 restart and bounded same-seed early/late profile in a single coordinated checkpoint. No risky default backend enabled.
