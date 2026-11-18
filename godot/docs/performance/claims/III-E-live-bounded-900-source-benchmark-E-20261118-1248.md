# Astra III/E — bounded real paid-tick benchmark integration
STATUS: IN_PROGRESS
OWNER: E
START: 2026-11-18 12:48 MSK
BASE_HEAD: 8267fdf5ecb2b0b2a170e7f9496b0c480015991d
SOURCE: ASTRA_FIVE_SHIFTS_RU.md — E separate benchmarking duty; paid-tick 100/300/600/900, bounded phase/copy/size evidence and no fabricated worker metrics.
INTENDED FILES: godot/tests/p2_late_growth_capture.gd; godot/tests/p2_perf_e_live_bounded_capture_oracle.gd
GOAL: connect actual N158 paid step and completed checkpoint to bounded per-window timing and authoritative size probe, remove unbounded 2600 default and misleading window semantics, ensure invalid/timeout failure and negative oracle.
EXPECTED TEST: targeted positive/negative script, later Godot manual run (no Actions).
