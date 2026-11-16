# PERF D — ordered station rosters, 2026-11-16 05:07 MSK

Code commit: 8eb179384b59928bc541df087eb02d1b1f2181e4
Test commit: b8e7549739b684fd8291b460a7e4203d37ba1a74

Files: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_station_roster_oracle.gd

Replaced repeated full population/facility scans per market with per-proposal ordered rosters grouped by (faction,location). Built after cadence gate, discarded after each proposal. Original lexicographic ordering and assignment initialization retained. No persistent cache, schema, economy, pricing, AI budget or clock changes.

TEST EXECUTED: NOT RUN. CODE_UNVERIFIED; Godot 4.7.2 not available. Targeted oracle compares grouped vs original sorted scans over eight cycles with facility/population transfer, relocation, deletion, installation. It does not yet assert full paid-world plan parity. Performance benefit NOT MEASURED.

Next: run Godot oracle, then compare full N18 plans/assignments and N9/world snapshots before/after under same 420/900-tick seed; measure N18 phase time. Do not claim FPS improvement or merge PR #262 automatically.
