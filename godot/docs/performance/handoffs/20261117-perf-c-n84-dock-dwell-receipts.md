# C handoff — 2026-11-17 N84 DockDwell receipts

Code commit: b7c3b392c0da09140ead6e020b250057a1a9ba83
Test commit: c975cd5eb1794863507897b18de9766d5467bcd4

Files:
- godot/scripts/sim/phase2/unified_ship_ai_execution.gd
- godot/tests/p2_perf_c_n84_dock_dwell_receipt_oracle_20261117.gd

N84 DockDwell previously scanned every entry in growing world.dock_receipts for each ship executing the leaf. Now a single read-only, lazy, proposal-local latest-dock-tick map is built on first DockDwell evaluation, reused for other ships in the same N84 propose call. It is never saved across ticks or to N38. Same max tick, action and ship matching, timeout and missing receipt behavior. No N9/N39/N158 changes, no money/cargo/fuel operations.

Targeted oracle: 4000 receipts / 120 ships; compares each status to the old full scan; negative undocked and newly appended dock receipt on a new invocation; checks fuel/cargo unchanged.

Verification: CODE_UNVERIFIED / TEST_ADDED_NOT_RUN. Godot execution NOT RUN; no speedup measured, no same-seed parity yet. This is a source-level reduction from O(active DockDwell ships * dock receipts) to O(dock receipts + active DockDwell ships) for this site, not proof that the site dominates N84 or that total TPS improved.

Next: bounded profiler on same seed at tick100/600/900 with N84 DockDwell calls/receipt count/site ms and ships+dock phase avg/p95. Run targeted oracle, N38 restart and paid cargo/contract parity before acceptance. If site is negligible, inspect N14/N140 and N153 proposal scans rather than add more caches.
