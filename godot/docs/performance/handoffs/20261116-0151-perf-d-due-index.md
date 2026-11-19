# PERF D — isolated deterministic due index (2026-11-16)

Code commits: d6137aea559a2c2412711661f97c8b86e5ca2b5c, 2ebbce49f7063c606b1b1547558ffcef752ca59a, 643c0b64601bf8853eaa454889295c7d594f3d80.

Files: `godot/scripts/sim/phase2/p2_perf_d_due_index.gd`, `godot/tests/p2_perf_d_due_index_check.gd`. Added opt-in bucket index by exact due_tick/phase with detached payloads, ID removal, transactional rebuild, deterministic comparator matching EventQueue. Used string keys to avoid Vector2i 32-bit tick truncation. Original `event_queue.gd` and live backend unchanged; no price, ledger, AI, cadence or save-format changes.

Test: oracle compares 240 scheduled events, cancellations, late insertions, matching ordered due outputs and invalid rebuild rollback. TEST_ADDED_NOT_RUN / CODE_UNVERIFIED (Godot 4.7.2 not executed). No measured speedup, no 420/900 or N38 restart claim. Static comparison: original comparator matches; all preloads exist in branch. No lease required: only new D-owned files; no shared-file edits.

Next: run headless oracle, add max-tick/phase boundary negatives and benchmark indexed vs uncached on same event stream. If parity and benefit are established, consider opt-in integration into EventQueue, preserving snapshot/restore and exact event sequence; do not switch live backend before tests.
