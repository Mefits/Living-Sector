# PERF D · 17.11.2026 · live event dispatch regression

CODE COMMIT: c62dbaf633025ac98def41b3a99b7b36be279d35
TEST COMMIT: 48ede567537468859c19c2366718b920eebdc300

## Root cause
The previous D change removed the redundant `_ids` index from `event_queue.gd`, but `take_due()` still called `_ids.erase(event_id)`. `_ids` is not declared anywhere in the current class. Any nonempty due boundary would hit that invalid access. This is a functional regression, not an optimization claim.

## Fix
Removed the stale erase from the actual live `take_due()` path. `_positions`, `_pending` and `_due_ids` remain the only storage/index structures. The canonical comparator and restore format are unchanged. No changes to N9/N39/N152/N158 or Astra's two commits.

## Targeted negative regression
`godot/tests/p2_perf_d_event_queue_removed_index_regression_20261117.gd` tests a multi-event boundary, tie ordering by entity_id, cancellation, unknown kind, repeat dispatch, restore and later boundary dispatch.

TEST EXECUTED: NOT RUN (no Godot runtime invoked). CODE_UNVERIFIED; no claimed CPU ms/tick benefit. The 500-tick PASS #43972442164 predates these later D patches and is not acceptance evidence.

NEXT: Run this targeted Godot test in the coordinated <=12-minute checkpoint; verify all earlier D event-queue tests and exact event/snapshot parity. Then profile N150/Head early-vs-late same-seed, rather than making further speculative queue micro-optimizations.
