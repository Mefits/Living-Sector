# Astra II-C / D — remove unused non-due station admin snapshot copy

STATUS: CODE_DONE_TEST_UNVERIFIED
OWNER: D
START: 2026-11-18 10:35 MSK
BASE HEAD: cd1ca1dde219100afed61114d0ef4c3bc7165a51 (before claim commits)
SOURCE: ASTRA_FIVE_SHIFTS_RU.md D repeated station/faction scans and DTO materializations; paid-path repeated snapshot overhead.
INTENDED FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_station_noop_snapshot_20261118.gd
RATIONALE: N39 consumes station_admin.snapshots only when due=true; on 4/5 ticks adapter deep-copies entire persisted administrator memory and N39 discards it. Keep no-due assignments/views/cadence and return an empty detached snapshot container.
EXPECTED CHECK: no-due output detached, no mutation; due output unchanged; same-seed N39/N38 parity later. CODE_UNVERIFIED until runtime.

CODE COMMIT: 655162f60af6a22552a51ce39bc7cf48f6cf7c5d
TEST COMMIT: 1e949d7f658fbdf023fddb6d13a8a670a316bfd0
FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_station_noop_snapshot_20261118.gd
FIX: No-due N18 proposal returns detached empty snapshots rather than deep-copying persisted administrator history on 4/5 paid ticks. N39 only reads snapshots inside due branch; due path untouched. No World mutation or alias.
TEST: NOT_RUN (Godot 4.7.2 runtime not executed). Targeted regression covers idle clocks, snapshot isolation, invalid clock and invalid persisted memory.
MEASURED BENEFIT: NOT_MEASURED; removes one full administrator-memory deep copy on each non-due N18 proposal.
NEXT: E-owned bounded same-seed early/late paid-tick profile and N39/N38 parity; next D item Head per-faction repeated scans with measured callsite cost.
