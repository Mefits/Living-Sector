# PERF A · batched protected alias traversal (16.11.2026)

- Code commit: `de9c656a687c8c9797f98bc4c303dcda8681336f`
- Test commit: `9aaa832b80d75f8419c612054674198004c3e783`
- Code: `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`
- Test: `godot/tests/p2_perf_a_batched_market_alias_check.gd`
- Status: **CODE_UNVERIFIED / TEST_ADDED_NOT_RUN**. No Godot runtime was used; no performance measurement, no CI run.
- Change: group each row's protected field values into a temporary Array and scan the proposed row once, instead of repeatedly flattening the same mutable graphs for every protected-field × proposed-field pair. Cross-market checks similarly group each old row once. This is a diagnostic-only helper; full Schema.validate and production TickRunner remain unchanged.
- Regression: independent two-market copies accepted; nested alias under a second protected field caught within same market and across markets; independent illegal stock mutation still rejected.
- Benefit: fewer repeated graph traversals by source inspection; **not measured**. _shares_mutable_storage still has pairwise node-identity comparisons, so asymptotic cost remains potentially quadratic in unique nodes.
- Next: execute targeted test and existing `p2_perf_a_market_owned_write_guard_check.gd` under Godot 4.7.2, then compare old/new guard cost on real N150 market snapshots and strict Schema oracle before any shadow wiring with D.
