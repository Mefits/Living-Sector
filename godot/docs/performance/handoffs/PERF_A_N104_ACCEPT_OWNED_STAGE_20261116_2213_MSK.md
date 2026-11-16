# PERF A — N104 accept bounded owned World stage (16 Nov 2026)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE COMMIT: `74bd210aa31c6c98e639339670e5d1043b45d335`
TEST COMMIT: `6570bea8b2ce8a6de23f80ccd6f5a2ee48e812cd`

Files:
- `godot/scripts/sim/phase1/n39_native_world_production.gd`
- `godot/tests/p2_perf_a_n104_accept_owned_stage_20261116.gd`

N104 acceptance previously staged `_copy_world("L3885", true)`, copying the entire growing World after paid contract acceptance. The new stage shallow-copies the root, deeply detaches the exact mutated domains `ships`, `facilities`, `escrow_balances`, `faction_treasuries`, and installs a detached `board.snapshot()` for `contract_board`. The existing full `Schema.validate`, `Schema.accounts` against staged N9, and atomic `_world/_ledger` publication are unchanged. No C/D/E files touched. This does not eliminate `deep:L129` from `world_snapshot()`.

Test checks staged values against full deep-copy oracle, unchanged original, detached owned domains, and a negative shallow-alias control. **TEST EXECUTED: NOT RUN; CODE_UNVERIFIED.** No Godot runtime executed, no CI dispatched. No measured CPU improvement or exact N38/BT/RNG parity claim. Expected copy reduction is structural, one full-World stage per successful N104 acceptance replaced by four domain copies plus board snapshot; overhead depends on domain sizes and acceptance frequency.

Next: owner C identify the N104 accept callsite frequency and consecutive `world_snapshot()` reads in ships/dock_queue; A profile same-seed early/late site counts and N9/N39/N38/BT/RNG parity, including N104 accept rollback and no mutable alias, before accepting the optimization. If unchanged-domain alias ownership is not guaranteed across subsequent operations, revert this stage to the full deep copy pending proof.
