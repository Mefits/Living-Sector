# PERF A handoff — 2026-11-17 N152 refund publish
Branch: integration/perf-astra-5-workers-20261116; PR #262.

Code commits: 1dc3a72ee9feafc734f8bb1abf505a5b510d3e91, 25d02f7fbe253f25002b8635cc9962198654ee3b.
Test commit: ab364ed814fa683b3c6024f2e0a4cdbd22df59ee.

Files: godot/scripts/sim/phase1/n39_native_world_production.gd; godot/tests/p2_perf_a_n152_refund_owned_stage.gd.

N152 apply contract aging/refund publish L3596 previously cloned all of World. It now shallow-copies the root, deep-copies the validated next contract board, and only when there are actual refunds detaches escrow_balances, facilities, populations, faction_treasuries before writes. Full Schema.validate, Schema.accounts, Ledger restore, receipt checks and atomic publication remain unchanged. No-refund ticks avoid wallet clones. Unrelated ships/markets/history no longer cloned by this stage. No changes to N9, N158, N38, or C-owned modules.

TEST_ADDED_NOT_RUN / CODE_UNVERIFIED. No Godot runtime invoked; no measured speedup or exact production parity claimed. The test exercises owned copy/oracle and nested alias negative, but is not a full production integration test. Previous CI #43972442164 predates this patch.

Next: run targeted N152 refund/no-refund integration with rejected refund, receipt duplication, wallet balances and N38 restart; then bounded same-seed early/late phase/site timings and p95. Verify Schema validation of the optional treasury domain and check late-tick N152 frequency. Avoid repeating already fixed L196, N9 WeakRef and N158 projections.
