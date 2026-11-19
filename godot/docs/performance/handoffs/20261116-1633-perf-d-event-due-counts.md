# PERF D · Empty due-boundary fast path · 2026-11-16 16:33 MSK

CODE COMMIT: `3d6149838907784dfda8c8a1f5431500244b1378`
TEST COMMITS: `8a0a15e19a566dda47197383a0a932cc8d5d6f7f`, `47eb23574ee7d32c5799388d3f6c254b605e003d`

FILES:
- `godot/scripts/sim/event_queue.gd`: derived per-(tick,phase) counts; skip O(E) scan when no events due; update on schedule/cancel/take_due; stage counts on successful restore only. No change to event payload, ordering, snapshot format or external API.
- `godot/tests/p2_perf_d_event_due_counts_20261116.gd`: 240 events, cancellation, rejected restore atomicity, successful restore, empty boundary and independent sorted snapshot oracle.

TEST EXECUTED: NOT RUN (Godot unavailable). CODE_UNVERIFIED / TEST_ADDED_NOT_RUN.
WHY: Frequent phase boundaries with no due events previously scanned the entire pending queue. Expected O(1) empty-boundary lookup; due boundaries retain O(E), and memory grows with distinct due boundaries. Benefit not measured. Counts are derived and are not serialized.
NEXT: Run targeted test in Godot 4.7.2, verify parser, benchmark empty and populated phase boundaries with same event distribution, N38 restart and full checkpoint parity. If overhead exceeds benefit, revert. No CI triggered.
