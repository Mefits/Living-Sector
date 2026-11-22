# PERF D — N150 wire trend snapshot copy (16.11.2026 13:58 MSK)

- CODE COMMIT: fd4f753d319fa41d4849c431374205088b1c5480
- TEST COMMIT: ded8fa635de90235cdf615c1de99d60633d6922b
- FILES: godot/scripts/sim/phase1/n150_native_full_market_tick.gd; godot/tests/p2_perf_d_n150_wire_trends_copy_20261116.gd
- WHY: wire_snapshot validated and duplicated each historical trend record separately. It now validates every record before a single deep Array.duplicate(true), preserving order, nested detachment and error handling. No live World, N9, N158 or pricing logic changed.
- TEST EXECUTED: NOT RUN (Godot unavailable); CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Source-level signature/preload checked against fetched N150 file. No FPS or TPS gain claimed.
- NEXT: run targeted Godot script and full N150 regression; compare same-seed 420/900 tick N150 timings and exact N38 restart checkpoint before acceptance. Do not enable experimental event queue backend without its parity gate.
