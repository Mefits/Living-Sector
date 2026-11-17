# PERF A — 2026-11-17 N151 consumption owned World stage

Branch: `integration/perf-astra-5-workers-20261116`; PR #262. No merge/force push.

CODE: `34256967dcf23099be10de99a5791e352ccb255b`
TEST: `f056b91d8038a9c9bd23f97af31103f44c5a0c94`

Changed `godot/scripts/sim/phase1/n39_native_world_production.gd` in `apply_population_phase`: former `_copy_world("L4144", true)` replaced with shallow root plus deep-detached `populations`, `facilities`, `markets`. All purchase and sentiment writes in this stage target those domains; full Schema.validate, N9 account comparison, ledger fork and atomic publication remain intact. Other domains are read-only during stage and are never returned as mutable output.

Added `godot/tests/p2_perf_a_n151_consumption_owned_domains.gd`: full-copy oracle, original-world isolation, rejected partial transaction, and deliberate shallow-alias negative fixture.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No local Godot or bounded CI run for this change. No measured ms/tick improvement, p95 or late-tick parity claim. The previous CI #43972442164 predates this patch.

Next: execute targeted N151 test and N151 actual paid-purchase replay, then same-seed early/late checkpoint with N9/N39/N38/BT/RNG/contract/cargo exact parity. Profile callsite counts and elapsed for L4144_owned_root before attributing performance benefit. Do not duplicate N9 WeakRef, N158 projections or N39 L196 fixes.
