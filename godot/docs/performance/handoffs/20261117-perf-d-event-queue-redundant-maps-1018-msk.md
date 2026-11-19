# PERF D — event queue redundant maps, 17.11.2026 10:18 MSK

CODE acdf40cf29e4d1dda4c9d582cde4f7232532df5d
TEST 2d27dd42cd0e96e4a060755255328d551550888f

Files: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_event_queue_redundant_maps_oracle.gd.

The live event queue already has authoritative _pending, an event-id-to-position map _positions, and a due boundary -> IDs index _due_ids. Removed duplicate _ids membership map and _due_counts counter map, both updated on every schedule/cancel/restore/take_due but never needed for dispatch. Identity membership is now _positions.has(id). Restore still rejects duplicate IDs/sequences using its local seen_ids. No change to ordering comparator, event payload copying, snapshot schema, or due dispatch. This is a constant-factor reduction in hot event operations and retained index state, NOT a measured late-tick speedup.

Negative oracle: duplicate scheduling, cancel/unknown cancel, ordering on equal due boundary, snapshot/restore, unknown event kind, duplicate sequence rejection, consumed event not reissued, source queue unaffected.

TEST EXECUTED: NOT RUN; CODE_UNVERIFIED (Godot runtime not invoked). No new CI. Performance improvement NOT MEASURED. Existing #43972442164 predates this patch.

Next: run targeted oracle at agreed bounded CI checkpoint, compare early/late same-seed event queue site time/calls and event counts; if event queue remains negligible, prioritize measured N150/Head work. No N9/N39/N152/N158 changes; no merge.
