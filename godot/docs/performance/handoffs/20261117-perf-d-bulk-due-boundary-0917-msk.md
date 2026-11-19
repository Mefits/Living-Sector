# PERF D — bulk due boundary, 17.11.2026

CODE COMMIT: 9a14ddcb06c0436c5d8c8c9c47af263033cd5b3c
TEST COMMIT: 63d0ee3ae19500ce19379d0bee03796f43490cd8

Files:
- godot/scripts/sim/event_queue.gd
- godot/tests/p2_perf_d_due_bulk_boundary_20261117.gd

The live take_due path previously called cancel() once per due event, repeatedly constructing the same due boundary key, updating counts, and mutating the due bucket. It now removes each event directly by the existing swap-position map, then clears the boundary indexes once. The authoritative pending store, comparator, schedule, public cancel, and restore remain unchanged. All extracted events still undergo canonical ordering by due_tick/phase/entity_id/sequence. No changes to N9/N39/N152/N158.

Negative regression covers same-boundary ordering, unknown event kinds, cancel, unknown cancellation, empty extraction, repeat extraction, restore, later events, re-schedule after draining, and duplicate-sequence snapshot rejection.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No runtime speedup claimed. The change avoids repeated per-event index maintenance when a due boundary has many events, but event dispatch frequency and per-site costs have not yet been measured. Checkpoint #43972442164 predates this change.

NEXT: run the targeted test and bounded same-seed early/late event_queue call/time counters; compare canonical event stream and N38 restart before accepting. If event queue contribution is negligible, prioritize measured N150/Head market DTO and ContractBoard paths. Do not run a separate long CI for this small patch.
