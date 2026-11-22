# PERF A — bounded mutable alias traversal (2026-11-16 11:10 MSK)

Branch: `integration/perf-astra-5-workers-20261116`, draft PR #262.

CODE COMMIT: `84be804748c9b601e81a3fdf49c8caa13bc63c7d`
TEST COMMIT: `4f85952fa98c8e43aaec1f55766d477450fcb1a6`

Files:
- `godot/scripts/sim/phase1/n39_market_owned_write_guard.gd`: replace recursively repeated cross-tree scans with visited-by-identity flattening of Dictionary/Array nodes and identity intersection. Prevents repeated traversal of shared subtrees, handles mixed container types, and terminates on cyclic references.
- `godot/tests/p2_perf_a_market_owned_write_guard_check.gd`: wide detached tree acceptance and cross-branch deep alias rejection.

TEST EXECUTED: NOT RUN (Godot runtime unavailable). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Source checked for GDScript indentation, pre-existing preload and signatures. No performance improvement measured. Traversal remains diagnostic only and can be quadratic in number of distinct mutable nodes, but avoids the earlier recursive cross-product explosion.

Invariants: no production runtime, World, N9, N158, N38, balance or full Schema oracle changes; no CI triggered.

NEXT: run targeted Godot test and profile old/new guard on representative N150 market snapshots, then coordinate shadow boundary with D; retain full Schema oracle and rollback/alias negatives.
