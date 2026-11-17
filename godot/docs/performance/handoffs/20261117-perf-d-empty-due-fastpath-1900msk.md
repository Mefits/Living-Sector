# PERF D — empty due fast path (17.11.2026 19:00 MSK)

Branch: `integration/perf-astra-5-workers-20261116`; PR #262. No merge.

CODE commit: `1f876532f7ab59d3e05bcfbe682bce485b7ef078` — `godot/scripts/sim/event_queue.gd`. Early return when authoritative `_pending` is empty, before constructing string due key on every phase. Nonempty behavior unchanged.

TEST commit: `cf99450e2f6a729a20780cdc1e9c9241a63dcb26` — `godot/tests/p2_perf_d_event_queue_empty_fastpath_20261117.gd`. Tests empty queue, scheduled future event, cancellation to empty, same-boundary canonical entity ordering, double extraction, empty snapshot restore.

Status: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No Godot execution or CPU measurement. Expected benefit limited to empty queue phases; does not explain measured markets/factions growth. Do not claim speedup.

Next: integrate targeted test in the shared bounded checkpoint; compare same-seed early/late phase timings and event queue occupancy. Prioritize measured MarketHistory copy and Head paths. N9/N39/N152/N158 and Astra fixes untouched.
