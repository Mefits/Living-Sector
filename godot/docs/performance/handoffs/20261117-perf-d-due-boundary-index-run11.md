# PERF D — due-boundary dispatch (17.11.2026)

Code commit: d01a2a7e2c04045aeedf7eb213d37af9268e4627
Test commit: cb107ac6c7b5162a1a12932b395998f7852ca728

Files: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_due_boundary_index_oracle.gd.

Replaced full O(E) pending scan in take_due with boundary-indexed event IDs and O(k) position-map swap removals. _due_ids updated on schedule/cancel and atomically rebuilt on restore; not serialized. Canonical due_tick/phase/entity_id/sequence sort remains authoritative; unknown event kinds still dispatch as data. Negative oracle covers cancel, unknown ID, restore, due ordering, distinct phases, repeat take, rejected corrupt restore.

STATUS: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No local Godot runtime or measured CPU improvement. No new CI launched; checkpoint #43972442164 predates this patch. Do not claim late-tick speedup. Next: run targeted oracle and bounded same-seed early/late site profile (event count and due count), exact N9/N39/N38/BT/RNG/contract/cargo parity before enabling further optimizations. No N152/N9/N39/N158 modifications.
