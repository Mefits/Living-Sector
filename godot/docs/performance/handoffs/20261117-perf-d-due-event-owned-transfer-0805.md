# PERF D — due-event ownership transfer (17.11.2026 08:05 MSK)

CODE COMMIT: 6c23518d794aa587f164c13dda3d62168f5614da
TEST COMMIT: 0c8fa76b35e8dcf23c277dd69059f9675293ea3c

Files: godot/scripts/sim/event_queue.gd; godot/tests/p2_perf_d_due_transfer_ownership_20261117.gd.

Existing take_due() removes every returned record from the only authoritative _pending store before returning. schedule() and restore() already deep-detach payloads at input. Removed redundant result.duplicate(true) after canonical sort, transferring ownership of removed records instead. No change to due indexing, order, cancellation, snapshots, or RNG.

Targeted negative test checks source payload mutation, event cancellation/unknown kind, canonical order, mutation of dispatched payload, pending isolation, restore and re-dispatch. Test NOT RUN; CODE_UNVERIFIED. No Godot runtime used, no measured CPU benefit, no parity acceptance claimed. Existing CI #43972442164 predates this patch.

NEXT: run targeted oracle, bounded same-seed early/late profiling of take_due call counts, event count and deep copy cost; retain only if beneficial and exact replay/parity. No changes to N9/N39/N152/N158 or Astra commits.
