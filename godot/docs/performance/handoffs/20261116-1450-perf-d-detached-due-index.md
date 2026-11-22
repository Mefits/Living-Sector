# PERF D handoff — detached due index, 2026-11-16 14:50 MSK

CODE COMMIT: 84ea631be31f69202a94d15fa23e18d60a4e853f
TEST COMMIT: f237eed8edcf9b4b763f863a4b0bb574436c7a3c
FILES:
- godot/scripts/sim/event_due_index_experimental.gd
- godot/tests/p2_perf_d_due_index_oracle.gd

WHY: immutable detached EventQueue snapshot can be grouped by integer due_tick/phase once, then extracted without scanning all pending events on each phase boundary. Within each bucket entity_id and sequence sorting matches EventQueue._less. Full-width integer keys avoid 32-bit truncation. rebuild stages all buckets before replacing the index, and take_due returns detached payloads. It is an isolated experiment, NOT live-wired; rebuild is required after any source mutation.

TEST EXECUTED: NOT RUN (Godot runtime unavailable).
STATUS: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. No measured performance benefit. Static source comparison against current event_queue.gd only.
NEGATIVES: invalid rebuild rollback, snapshot mutation alias, duplicate extraction, 64-bit tick collision, cancellation and mixed phase/entity ordering.

NEXT: run targeted oracle under Godot 4.7.2, then benchmark baseline take_due vs indexed on realistic event counts and cadence. If beneficial, design explicit source-version invalidation and N38 restart parity before any opt-in live integration. Do not enable by default. No Actions started.
