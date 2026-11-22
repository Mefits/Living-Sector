# C handoff — N21 active FIFO read, 16 Nov 2026

CODE COMMIT: 6e385d6976844861ca9b5b30d17c51aa78b738d1
TEST COMMIT: a915624bac2256592e202d581cfa44037de65f8f

Files: godot/scripts/sim/phase2/unified_n21_dock_queue_stage.gd; godot/tests/p2_perf_c_n21_fifo_read_oracle_20261116.gd.

WHY: active N21.advance previously used _queue(fac) for every head and loop condition, recursively duplicating the remaining FIFO on every iteration. The staged facility already owns a detached queue. Read it directly without changing mutation/admission/payment paths. This removes repeated O(Q) copies from the Q-item iteration. _prune still detaches and validates once. No N9/N39/N38 changes.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. New oracle compares original detached reads with direct reads for 1200 entries including repeated IDs, and verifies source queue remains unchanged. It does not establish paid contract/fuel/cargo/N38 parity.

Performance benefit UNMEASURED. Prior source phase baseline: tick601–900 dock_queue 26.49s total; not attributable entirely to this site. Do not claim TPS improvement until same-seed early/late benchmark.

NEXT: targeted Godot oracle; bounded same-seed 100/600/900 phase/site timing and p95; N21 paid docking and N38 restart negative parity. Check if _stage_world full snapshot now dominates. Do not edit A-owned N39 without coordination.
