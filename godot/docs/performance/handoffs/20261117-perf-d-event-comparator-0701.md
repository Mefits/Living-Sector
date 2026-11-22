# PERF D handoff — 2026-11-17 07:01 MSK, event comparator
Branch: integration/perf-astra-5-workers-20261116, PR #262 (no merge).
CODE commit: 5d7c34f4e7814af1123b192f1b9c1f25b2b9b9f8
TEST commit: 7732b7aae38846af8513dda40fa10b609c283f8
Files: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_event_order_comparator_20261117.gd.
Change: canonical event comparator no longer creates an array of field names for each sort comparison; direct ordered comparisons of due_tick, phase, entity_id, sequence preserve comparator semantics. This is the live dispatch/snapshot sorting path, not an unused index.
Oracle: equal tick/phase/entity ties, cancellation, unknown cancellation, restore, unknown event kind, invalid duplicate sequence and failed-restore atomicity.
Status: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot execution or same-seed early/late measurements. No speedup claimed. No CI launched.
Next: run targeted test in shared bounded checkpoint, record comparator site calls/time and event counts, then same-seed early/late phase and p95. Avoid duplicating 99ab25e9/1676db61; do not touch N152 ownership without A/B agreement.
