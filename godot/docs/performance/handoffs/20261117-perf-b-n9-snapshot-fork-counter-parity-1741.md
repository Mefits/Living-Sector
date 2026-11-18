# PERF B handoff — 2026-11-17 snapshot phase counter fork parity

Branch: `integration/perf-astra-5-workers-20261116`, PR #262.

- CODE `0f331147e3e848001cc3acd6775c21de4fb1bd56`: `godot/scripts/sim/economy/credit_ledger.gd`. The opt-in N9 snapshot phase counters introduced in prior B work were not copied by `_profile_inner_fork()`, unlike seven older counters. Carry `snapshot_rebuild_calls`, `snapshot_rebuild_usec`, and `snapshot_copy_usec` into the child. The fork remains COW and no authoritative data or save format is changed.
- TEST `5718e379ca3361c4134f46c34076ba26436aebe9`: `godot/tests/p2_perf_b_n9_snapshot_fork_counters_20261117.gd`. Covers parent/child/sibling inherited counters, independent growth, exact snapshots, and duplicate-operation rejection.
- TEST: NOT RUN. CODE_UNVERIFIED (Godot runtime not executed). No measured CPU/paid tick improvement; fixes validity of cumulative late-tick N9 instrumentation.
- Earlier CI #43972442164 PASS does NOT validate these commits. Do not repeat Astra fixes `99ab25e9` or `1676db61`.
- Next: collect real N9 `append_calls/usec`, `snapshot_rebuild_calls/usec`, `snapshot_copy_usec`, receipt counts, and N38 encoded bytes at tick100/300/600/900. If B is not a material share of paid-tick CPU, stop local micro-optimizations. Run targeted regression with next coordinated bounded CI (<12 min), plus N38 exact restart/parity as required.
