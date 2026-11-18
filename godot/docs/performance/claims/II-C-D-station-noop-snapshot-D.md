# Astra II-C / D — remove unused non-due station admin snapshot copy

STATUS: IN_PROGRESS
OWNER: D
START: 2026-11-18 10:35 MSK
BASE HEAD: cd1ca1dde219100afed61114d0ef4c3bc7165a51 (before claim commits)
SOURCE: ASTRA_FIVE_SHIFTS_RU.md D repeated station/faction scans and DTO materializations; paid-path repeated snapshot overhead.
INTENDED FILES: godot/scripts/sim/phase2/unified_native_station_administration_phase.gd; godot/tests/p2_perf_d_station_noop_snapshot_20261118.gd
RATIONALE: N39 consumes station_admin.snapshots only when due=true; on 4/5 ticks adapter deep-copies entire persisted administrator memory and N39 discards it. Keep no-due assignments/views/cadence and return an empty detached snapshot container.
EXPECTED CHECK: no-due output detached, no mutation; due output unchanged; same-seed N39/N38 parity later. CODE_UNVERIFIED until runtime.
