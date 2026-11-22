# PERF D · Head commitment sorting, 2026-11-17 00:37 MSK

CODE COMMIT: c9bbdb041ab568c7db80520af1e6c26374225225
TEST COMMIT: ad8e6c3139c5d8c123b676b02c4a0ddf2ef794d2
FILES: godot/scripts/sim/phase2/unified_native_hybrid_planning.gd; godot/tests/p2_perf_d_head_commitment_subset_20261117.gd

Live Head capture formerly sorted every contract ID for every faction. It now scans the authoritative board, collects only matching active faction commitments, sorts those IDs, and projects the exact same fields. Paid/expired exclusions, source order, owner/faction matching and all planner budgets remain unchanged. No cached owner index or alternate state. Cost of sorting changes from O(C log C) to O(K log K) per faction, plus O(C) scan, where K is eligible faction commitments. Actual speedup and share of late-tick cost NOT MEASURED.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Negative regression covers paid/expired filtering, lexicographic order, changing owner, and detached snapshot values. No Godot runtime test or same-seed early/late measurements in this iteration. No parity PASS claimed.

NEXT: execute targeted test in coordinated bounded CI checkpoint; compare same-seed Head capture call counts and CPU time at early/late paid ticks, with total board size and per-faction eligible count. If sorting contribution is negligible, focus on measured Head/market DTO costs. N9/N39/N38/BT/RNG/cargo/contract parity remains an acceptance gate.
