# PERF C handoff — 2026-11-17, N84 BT validation

Branch: integration/perf-astra-5-workers-20261116 (PR #262).

Code: 6fd5d1b74acc90d05996f907a57fe62692dd1d62
Test: a976ed487b76f33e54709d05872baae62c613e18

Files:
- godot/scripts/sim/phase2/unified_ship_ai_execution.gd
- godot/tests/p2_perf_c_n84_single_autonomous_bt_validation_20261117.gd

Source finding: autonomous goal branch checks Bt.validate(assigned_bt) before the shared BT handling. The same non-mutated tree was recursively validated again by the shared guard on each paid tick. Now the second validation is conditional on nonempty contract_id; contract-bound and invalid autonomous plans retain their rejection paths.

Test: TEST_ADDED_NOT_RUN (source guard only, NOT an independent behavioral oracle).
Runtime: CODE_UNVERIFIED. No Godot runtime or same-seed profiling performed. Performance benefit is unmeasured; likely bounded by BT depth and autonomous ship count. No claim of solving late-tick slowdown.

Next: run targeted test, independent N84 negative BT replay, N38 restart, and same-seed tick100/600/900 source-level timing. Measure N84 Bt.validate counts/time and ship+dock phase totals. If insignificant, prioritize measured contract/dock hotpaths, not more speculative micro changes. No N9/N39/N158 changes. No CI triggered.
